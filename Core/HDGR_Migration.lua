-- HDGR_Migration.lua
-- In-place schema transform of HDG_DB -> HDG account.* shape.
--
-- Context: when HousingDecorGuide is renamed to HousingDecorGuide (P2) and its TOC
-- declares "## SavedVariables: HDG_DB", WoW loads the user's existing old-HDG
-- HDG_DB into HDG code unchanged. Migration is NOT a cross-DB copy -- it is an
-- in-place transform of the SAME table, run once on first launch of the new build.
--
-- Design:
--   * Detection:  old-HDG schema = HDG_DB.schemaVersion == 2 OR presence of
--                 HDG-only top-level keys (customStyles, flat craftingHistory
--                 array, flat `collection`, vendorNameCache).  A DB already
--                 stamped account.schemaVersion = HDG.Constants.SCHEMA_VERSION
--                 is a no-op (protects current HDG dev users).
--   * Backup:     snapshot raw HDG_DB to HDG_DB_preMigrationBackup once before
--                 mutating (rollback net; written only on first migration run).
--   * Idempotent: stamps HDG_DB.account.schemaVersion = SCHEMA_VERSION on
--                 completion so re-runs are no-ops.
--   * Guard discipline: all guards here are at the SV boundary (user data of
--                 unknown vintage); each annotated exception(boundary).
--   * NO UI, NO Blizzard API calls, NO events. Pure data transform only.
--
-- Load order: Core/HDGR_Store.lua calls HDG.Migration:Run(HDG_DB) at the top
-- of LoadFromSavedVariables(), BEFORE adopting HDG_DB.account. After Run(),
-- HDG_DB.account is in HDG shape and EnsureStateShape fills in any gaps.

HDG = HDG or {}

local M = {}
HDG.Migration = M

-- ---------------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------------

-- Canonical deep copy from HDG.TableUtils (hygiene review A'2); handles any
-- vintage/type -- non-tables pass through, cycles are safe.
local DeepCopy = HDG.TableUtils.DeepCopy

-- Returns true when raw DB looks like an old-HDG schema (pre-HDG).
-- We match THREE independent signals so the detection is robust:
--   1. schemaVersion == 2  (HDG v2-flatten stamp)
--   2. flat `craftingHistory` array at top level (HDG shape; HDG nests under account.craft)
--   3. flat `collection` table at top level (HDG warm-start cache; HDG nests under account.collection)
--   4. presence of `vendorNameCache` (HDG-only persisted key, never in HDG)
--   5. presence of `customStyles` (HDG-only; migrated to collections in HDG v1-collections)
-- Any ONE signal is sufficient. Absence of ALL signals + presence of account.schemaVersion
-- = SCHEMA_VERSION means "already HDG; no-op".
local function _isOldHDGSchema(rawDB)
    -- exception(boundary): SV migration -- rawDB may be nil or any vintage
    if type(rawDB) ~= "table" then return false end
    -- Already-HDG: account sub-table present and stamped at current version.
    if type(rawDB.account) == "table" then
        local sv = HDG.Constants.SCHEMA_VERSION
        if rawDB.account.schemaVersion == sv then return false end
        -- Partially-migrated (account present, not yet stamped): let migration
        -- continue so it can stamp and be idempotent.
    end
    -- Old-HDG signals:
    if rawDB.schemaVersion == 2 then return true end
    if type(rawDB.craftingHistory) == "table" then return true end
    if type(rawDB.farmingHistory) == "table" then return true end   -- HDG-only flat key
    if type(rawDB.collection) == "table" then return true end
    if rawDB.vendorNameCache ~= nil then return true end
    if rawDB.customStyles ~= nil then return true end
    return false
end

-- ---------------------------------------------------------------------------
-- Section: shopping lists
-- HDG vendorShoppingLists shape: { [listID] = { name, items, meta, createdAt } }
-- items array: { {itemID, npcID?, qty, addedAt} }
-- HDG shape is identical. Reseed shoppingListSeq from existing IDs.
-- ---------------------------------------------------------------------------
local function _migrateShoppingLists(account, rawDB)
    -- exception(boundary): SV migration -- each field may be absent
    if type(rawDB.vendorShoppingLists) == "table" then
        account.vendorShoppingLists = account.vendorShoppingLists or {}
        local maxN = 0
        for listID, list in pairs(rawDB.vendorShoppingLists) do
            if type(list) == "table" then
                -- Shape is identical; carry verbatim. Guard against clobbering edits
                -- made post-migration if the migration re-runs on a SCHEMA_VERSION bump.
                if account.vendorShoppingLists[listID] == nil then
                    account.vendorShoppingLists[listID] = DeepCopy(list)
                end
                -- Track max seq for monotonic reseed.
                local n = tonumber(string.match(tostring(listID), "^L(%d+)$"))
                if n and n > maxN then maxN = n end
            end
        end
        -- Seed seq once; EnsureShopping owns the reseed-past-existing-ids logic, so
        -- don't reset a counter the user has since advanced on a re-run.
        if type(account.shoppingListSeq) ~= "number" then
            account.shoppingListSeq = maxN
        end
    end
    if type(rawDB.activeShoppingListId) == "string" and account.activeShoppingListId == nil then
        account.activeShoppingListId = rawDB.activeShoppingListId
    end
end

-- ---------------------------------------------------------------------------
-- Section: craftingHistory
-- old-HDG entry: { itemID, itemName, quantity, profession, character, realm,
--                  itemPrice, materialCost, priceSource, source, timestamp }
-- HDGR target:   account.craft.history.entries
-- HDGR entry:    { id, eventType, recipeID, itemID, qty, timestamp }
--
-- Map: itemID -> itemID, quantity -> qty, timestamp -> timestamp (or 0).
-- eventType: "crafted" if source=="Crafted", "learned" if source=="Learned",
--            else "crafted" (safe default). recipeID: nil (HDG never stored it).
-- ---------------------------------------------------------------------------

-- Order history entries OLDEST-first by a time field. The Your Data selectors
-- reverse-render (#..1), so an oldest-first array shows NEWEST at top -- matching
-- the live *_HISTORY_PUSH append-at-end convention. old HDG stored newest-first,
-- so this re-orders on import (and idempotently on any later re-run).
local function _sortHistoryAsc(entries, timeKey)
    table.sort(entries, function(a, b) return (a[timeKey] or 0) < (b[timeKey] or 0) end)
end

local function _migrateCraftingHistory(account, rawDB)
    -- exception(boundary): SV migration -- table may be absent or malformed
    if type(rawDB.craftingHistory) ~= "table" then return end
    account.craft = account.craft or {}
    account.craft.history = account.craft.history or {}
    local hist = account.craft.history
    hist.entries = hist.entries or {}
    hist.nextID  = hist.nextID  or 0
    if #hist.entries > 0 then
        -- Re-run: re-order existing entries oldest-first (idempotent).
        _sortHistoryAsc(hist.entries, "timestamp")
        return
    end
    -- Fresh import: collect + sort SOURCE oldest-first so ids increase with time
    -- (matches the live append-at-end convention), then append.
    local valid = {}
    for _, entry in ipairs(rawDB.craftingHistory) do
        -- exception(boundary): SV migration -- individual entries may be malformed
        if type(entry) == "table" and (entry.itemID or entry.id) then valid[#valid + 1] = entry end
    end
    _sortHistoryAsc(valid, "timestamp")
    for _, entry in ipairs(valid) do
        local itemID = entry.itemID or entry.id  -- HDG had a legacy `id` alias
        local qty    = entry.quantity or entry.qty or 1
        local src    = entry.source or ""
        local evType = (src == "Learned") and "learned" or "crafted"
        hist.nextID = hist.nextID + 1
        hist.entries[#hist.entries + 1] = {
            id        = hist.nextID,
            eventType = evType,
            recipeID  = nil,  -- HDG did not persist recipeID/spellID
            itemID    = itemID,
            qty       = qty,
            timestamp = entry.timestamp or 0,
        }
    end
end

-- ---------------------------------------------------------------------------
-- Section: farmingHistory
-- old-HDG entry: { sessionId, collected, duration, perHour, timestamp, zone,
--                  lumberId, lumberName, character, realm }
-- HDGR target:   account.lumber.history.entries
-- HDGR entry:    { id, lumberID, charKey, startedAt, finalizedAt,
--                  sessionTotal, zone, character, realm }
--
-- Map: timestamp -> startedAt, collected -> sessionTotal, zone/character/realm
-- verbatim, lumberId -> lumberID (the Lumber tab resolves the name from it --
-- DROPPING it was the v1 bug that made rows read "nil" and collide on key).
-- finalizedAt is rebuilt from timestamp+duration so the duration column renders.
-- ---------------------------------------------------------------------------

-- charKey "Name-Realm" from an entry's character/realm (both required).
local function _entryCharKey(entry)
    if entry.character and entry.realm then return entry.character .. "-" .. entry.realm end
    return nil
end

-- v1 dropped lumberID/character/realm; backfill them on already-migrated entries
-- from the intact flat source, matched by timestamp (== startedAt).
local function _repairFarmingInPlace(hist, rawFarming)
    local byTs = {}
    for _, fe in ipairs(rawFarming) do
        -- exception(boundary): SV migration -- flat entry may be malformed
        if type(fe) == "table" and fe.timestamp then byTs[fe.timestamp] = fe end
    end
    for _, e in ipairs(hist.entries) do
        if e.lumberID == nil and e.startedAt then
            local fe = byTs[e.startedAt]
            if fe then
                e.lumberID  = fe.lumberId
                e.character = e.character or fe.character
                e.realm     = e.realm or fe.realm
                e.charKey   = e.charKey or _entryCharKey(fe)
                if e.finalizedAt == nil and fe.duration then e.finalizedAt = e.startedAt + fe.duration end
            end
        end
    end
end

local function _migrateFarmingHistory(account, rawDB)
    -- exception(boundary): SV migration -- table may be absent or malformed
    if type(rawDB.farmingHistory) ~= "table" then return end
    account.lumber = account.lumber or {}
    account.lumber.history = account.lumber.history or {}
    local hist = account.lumber.history
    hist.entries = hist.entries or {}
    hist.nextID  = hist.nextID  or 0
    if #hist.entries > 0 then
        -- Re-run: backfill v1-dropped fields, then re-order oldest-first (idempotent).
        _repairFarmingInPlace(hist, rawDB.farmingHistory)
        _sortHistoryAsc(hist.entries, "startedAt")
        return
    end
    -- Fresh import: collect + sort SOURCE oldest-first so ids increase with time,
    -- then append.
    local valid = {}
    for _, entry in ipairs(rawDB.farmingHistory) do
        -- exception(boundary): SV migration -- individual entries may be malformed
        if type(entry) == "table" and (entry.sessionId or entry.timestamp) then valid[#valid + 1] = entry end
    end
    _sortHistoryAsc(valid, "timestamp")
    for _, entry in ipairs(valid) do
        hist.nextID = hist.nextID + 1
        hist.entries[#hist.entries + 1] = {
            id           = hist.nextID,
            lumberID     = entry.lumberId,
            charKey      = _entryCharKey(entry),
            character    = entry.character,
            realm        = entry.realm,
            startedAt    = entry.timestamp or 0,
            finalizedAt  = (entry.timestamp and entry.duration) and (entry.timestamp + entry.duration) or nil,
            sessionTotal = entry.collected or entry.qty or 0,
            zone         = entry.zone,
        }
    end
end

-- ---------------------------------------------------------------------------
-- Section: characters
-- old-HDG per-char shape: { professions = { [profName] = { knownCount, totalCount,
--                              knownRecipes = { [spellID] = true },
--                              skillLevels  = { [expDisplay] = { current, max } } } },
--                           lastUpdated, knowsFindLumber, lumberInventory }
-- HDGR per-char shape:    { name, realm, class, classFile, hidden, lastSeen,
--                           professions = { [profName] = { knownRecipes,
--                              skillLines = { [expDisplay] = { current, max } } } } }
--
-- TWO shape fixes are required -- a verbatim DeepCopy is WRONG (it was the v1 bug):
--   1. professions: rename per-prof `skillLevels` -> `skillLines` (the Alts grid
--      reads .skillLines; inner {current,max} is identical). knownCount/totalCount
--      drop (HDGR doesn't use them). knownRecipes carries verbatim.
--   2. identity: parse name/realm from the "Name-Realm" charKey so the roster
--      renders immediately. class/classFile stay nil (not derivable from the key;
--      RecipeKnowledgeScanner backfills them on the char's next login).
-- ---------------------------------------------------------------------------

-- old-HDG professions -> HDGR professions. Pure key rename + field trim.
local function _transformProfessions(srcProfs)
    -- exception(boundary): SV migration -- srcProfs entries may be malformed
    local out = {}
    if type(srcProfs) ~= "table" then return out end
    for profName, pd in pairs(srcProfs) do
        if type(pd) == "table" then
            out[profName] = {
                knownRecipes = pd.knownRecipes or {},
                skillLines   = pd.skillLevels or pd.skillLines,  -- old=skillLevels; already-fixed=skillLines
            }
        end
    end
    return out
end

-- charKey is "Name-Realm" (char names never contain '-'); split on the first '-'.
local function _parseCharKey(charKey)
    return charKey:match("^(.-)%-(.+)$")
end

-- In-place repair of an already-stored char record. Reached on a v2 re-run over a
-- v1-migrated account: professions were DeepCopied verbatim (still skillLevels) and
-- identity is nil. Rename skillLevels -> skillLines ONLY where skillLines is absent
-- so scanner-fresh professions are never clobbered; parse identity only when nil.
local function _repairCharInPlace(charKey, rec)
    if rec.name == nil then
        local nm, rlm = _parseCharKey(charKey)
        rec.name  = nm
        rec.realm = rec.realm or rlm
    end
    if type(rec.professions) == "table" then
        for _, prof in pairs(rec.professions) do
            -- exception(boundary): SV migration -- prof may be malformed
            if type(prof) == "table" and prof.skillLevels and not prof.skillLines then
                prof.skillLines  = prof.skillLevels
                prof.skillLevels = nil
            end
        end
    end
end

local function _migrateCharacters(account, rawDB)
    -- exception(boundary): SV migration -- table may be absent or malformed
    if type(rawDB.characters) ~= "table" then return end
    account.characters = account.characters or {}
    for charKey, charData in pairs(rawDB.characters) do
        -- exception(boundary): SV migration -- individual entries may be malformed
        if type(charKey) == "string" and type(charData) == "table" then
            local existing = account.characters[charKey]
            if not existing then
                local nm, rlm = _parseCharKey(charKey)
                account.characters[charKey] = {
                    name        = nm,
                    realm       = rlm,
                    class       = nil,   -- backfilled by RecipeKnowledgeScanner on next login
                    classFile   = nil,
                    hidden      = false,
                    lastSeen    = charData.lastUpdated or 0,
                    professions = _transformProfessions(charData.professions),
                    -- Carry HDG-only fields that HDG observers may read:
                    knowsFindLumber = charData.knowsFindLumber,
                    lumberInventory = charData.lumberInventory,
                }
            else
                -- Already migrated (buggy v1 transform, or partially scanner-healed):
                -- repair in-place, preserving any scanner-fresh professions.
                _repairCharInPlace(charKey, existing)
            end
        end
    end
end

-- ---------------------------------------------------------------------------
-- Section: collections (styles / smartsets / snapshots)
-- old-HDG's style model differs from HDGR's -- a verbatim copy leaves every card
-- reading 0/0 (the count = #def.items, and HDGR resolves items only from `items`):
--   * curated style: type="style", items in a `curatedItems` SET {[itemID]=true}
--                    -> HDGR `items` ARRAY {itemID,...}
--   * snapshot:      type="style" (id "style:snapshot:*") + a `snapshot` sub-table
--                    {capturedAt, items={[itemID]={...}}, totalPlacementCost}
--                    -> HDGR type="snapshot" + `items` ARRAY + takenAt
--   * smart set:     type="style" + `query` (no curatedItems)
--                    -> HDGR type="smartset" (query->rules at runtime via _legacyToRules)
--   * crate:         DROPPED -- the crate feature never shipped in old HDG
--   * library:       DROPPED -- 7 empty curated templates (HDGR ships its own) +
--                    1 player save; no HDGR landing section consumes them
-- `members` was an always-empty legacy field in old HDG -- ignored.
-- Transform reads from account.collections if already present (re-run) else rawDB,
-- and is idempotent: an already-migrated collection (has `items`, no curatedItems/
-- snapshot/query) passes through unchanged.
-- ---------------------------------------------------------------------------
local function _setToArray(set)
    local out = {}
    if type(set) == "table" then for k in pairs(set) do out[#out + 1] = k end end
    return out
end

local function _migrateOneCollection(id, coll)
    -- exception(boundary): SV migration -- coll may be malformed
    if type(coll) ~= "table" then return nil end
    -- crate + library both DROPPED: the crate feature never shipped, and libraries
    -- (7 empty Vamoose-shipped curated templates + 1 player save) are superseded by
    -- HDGR's own curated content -- no HDGR landing section consumes them.
    if coll.type == "crate" or coll.type == "library" then return nil end
    local c = DeepCopy(coll)
    if type(c.snapshot) == "table" then
        c.type    = "snapshot"
        c.items   = _setToArray(c.snapshot.items)
        c.takenAt = c.takenAt or c.snapshot.capturedAt
        c.snapshot, c.curatedItems = nil, nil
    elseif type(c.curatedItems) == "table" and next(c.curatedItems) ~= nil then
        c.type  = "style"
        c.items = _setToArray(c.curatedItems)
        -- curated is item-driven; drop the vestigial smart-set filter it was promoted
        -- from (StyleSerializer:Export encodes `query` regardless of type -> mis-export).
        c.curatedItems, c.query, c._querySets = nil, nil, nil
    elseif type(c.query) == "table" and next(c.query) ~= nil and not (type(c.items) == "table" and #c.items > 0) then
        c.type = "smartset"   -- query-only saved set
    end
    -- Re-key to HDGR's id-prefix-as-type convention: iterAllCollections + the Detail
    -- normalizer route by the id PREFIX, not def.type. old HDG keyed snapshots and
    -- smart-sets under "style:" so without this they stay in My Styles. Type-driven
    -- (works even if a prior run already set the type) + idempotent (already-prefixed
    -- ids are left alone).
    local oldId = tostring(id)
    if c.type == "snapshot" and oldId:match("^style:") then
        c.id = "snapshot:" .. oldId:gsub("^style:", ""):gsub("^snapshot%-", "")
    elseif c.type == "smartset" and oldId:match("^style:") then
        c.id = "smartset:" .. oldId:gsub("^style:", "")
    else
        c.id = oldId   -- table key is authoritative (DeepCopy may carry a stale/bare def.id)
    end
    return c
end

-- Bare logical id with any "<type>:" prefix stripped, so a collection keyed
-- "style:custom-X" / "smartset:custom-X" and a customStyles key "custom-X" all
-- compare equal (used to dedupe the customStyles rescue against collections).
local function _bareCollId(id) return (tostring(id):gsub("^%a+:", "")) end

local function _migrateCollections(account, rawDB)
    -- exception(boundary): SV migration -- tables may be absent or malformed
    if type(rawDB.collections) ~= "table" and type(rawDB.customStyles) ~= "table" then return end
    local src = account.collections or rawDB.collections or {}   -- re-run transforms in place; fresh reads raw
    local out, seen = {}, {}
    for id, coll in pairs(src) do
        local migrated = _migrateOneCollection(id, coll)
        if migrated then out[migrated.id] = migrated end
        seen[_bareCollId(id)] = true
    end
    -- Rescue user-authored styles that live ONLY in the legacy `customStyles` store:
    -- pre-v1-collections HDG users have ALL styles there; v1-migrated users may leak a
    -- few orphans. Keyed "custom-*" -> treat as a "style:custom-*" collection so the
    -- same transform (curated->items / query->smartset) + re-key applies.
    if type(rawDB.customStyles) == "table" then
        for k, def in pairs(rawDB.customStyles) do
            if type(def) == "table" and not seen[_bareCollId(k)] then
                local migrated = _migrateOneCollection("style:" .. tostring(k), def)
                if migrated and out[migrated.id] == nil then out[migrated.id] = migrated end
            end
        end
    end
    account.collections = out
end

-- ---------------------------------------------------------------------------
-- Section: recentActivity -- NOT meaningfully carried.
-- Old HDG's real recentActivity is keyed by runtime houseGUIDs (e.g. "Opaque-1")
-- which are per-session, not persistent across logins -- so there's nothing worth
-- migrating (confirmed against real SVs + with the user). EnsureStateShape seeds
-- account.recentActivity fresh. The .houses carry below is a defensive no-op for a
-- standardized shape that was never actually shipped; real data falls through.
-- ---------------------------------------------------------------------------
local function _migrateRecentActivity(account, rawDB)
    -- exception(boundary): SV migration -- may be nil or non-standard shape
    local ra = rawDB.recentActivity
    if type(ra) == "table" and type(ra.houses) == "table" then
        account.recentActivity = account.recentActivity or DeepCopy(ra)
    end
    -- Real (houseGUID-keyed) shape has no .houses -> left nil; EnsureStateShape seeds fresh.
end

-- ---------------------------------------------------------------------------
-- Main entry point.
-- Called by HDG.Store:LoadFromSavedVariables() BEFORE adopting HDG_DB.account.
-- Mutates HDG_DB in-place to bring it to HDG account.* shape.
-- After Run(), HDG_DB.account is ready for EnsureStateShape.
-- ---------------------------------------------------------------------------
-- Returns true when a migration actually ran (so the caller can show a one-time upgrade
-- notice), or false on a no-op (already current / not an old-HDG DB).
function M:Run(rawDB)
    -- exception(boundary): SV migration -- rawDB is the raw WoW global; nil before first run
    if type(rawDB) ~= "table" then return false end

    -- No-op check: already at HDG schema.
    if not _isOldHDGSchema(rawDB) then return false end

    -- One-shot backup BEFORE any mutation (rollback net).
    -- Guard: only write if backup not already present (idempotency).
    if _G.HDG_DB_preMigrationBackup == nil then  -- exception(boundary): SV migration backup gate
        _G.HDG_DB_preMigrationBackup = DeepCopy(rawDB)
    end

    -- Ensure account sub-table exists (may be nil on a fresh old-HDG schema
    -- because HDG wrote flat keys, not under `.account`).
    rawDB.account = rawDB.account or {}
    local account = rawDB.account

    -- === MIGRATE: user-authored data ========================================

    -- collections: TRANSFORM (not verbatim) -- curatedItems->items, snapshot->snapshot
    -- type, query-only->smartset, drop crates. See _migrateCollections.
    _migrateCollections(account, rawDB)
    account.collections = account.collections or {}

    -- favorites: { [itemID] = true } -- shape-compatible.
    if type(rawDB.favorites) == "table" and account.favorites == nil then
        account.favorites = DeepCopy(rawDB.favorites)  -- exception(boundary): SV migration
    end

    -- userNotes: { [itemID] = { text, ts } } -- shape-compatible.
    if type(rawDB.userNotes) == "table" and account.userNotes == nil then
        account.userNotes = DeepCopy(rawDB.userNotes)  -- exception(boundary): SV migration
    end

    -- vendorNotes: { [npcID] = { text, ts } } -- shape-compatible.
    if type(rawDB.vendorNotes) == "table" and account.vendorNotes == nil then
        account.vendorNotes = DeepCopy(rawDB.vendorNotes)  -- exception(boundary): SV migration
    end

    -- vendorShoppingLists + activeShoppingListId + shoppingListSeq reseed.
    _migrateShoppingLists(account, rawDB)

    -- craftingHistory: shape transform required (see _migrateCraftingHistory).
    _migrateCraftingHistory(account, rawDB)

    -- farmingHistory: shape transform required (see _migrateFarmingHistory).
    _migrateFarmingHistory(account, rawDB)

    -- recentActivity: carry if shape-compatible.
    _migrateRecentActivity(account, rawDB)

    -- characters: shape-compatible professions; HDG identity fields nil until scan.
    _migrateCharacters(account, rawDB)

    -- === DROP: settings / config / mogul / ui / minimap (fresh HDG defaults) =
    -- (intentionally not migrated; EnsureStateShape seeds HDG defaults)

    -- === DROP: caches (self-heal from catalog on use) =======================
    -- vendorNameCache, vendorCurrencyCache, directPriceCache, directPriceCacheTime,
    -- ownedAuctions, collection (warm-start cache) -- all dropped. EnsureCollection
    -- seeds account.collection.ownedDecorIDs fresh.

    -- === DROP: obsolete / superseded ========================================
    -- craftingQueue, customStyles, customStyleOrder, schemaVersion, migrations,
    -- projects (user re-captures), houseTab (cockpit layout), layout, account (cockpit),
    -- records (cockpit) -- all dropped. HDG starts fresh.

    -- === STAMP: version flag (idempotency gate) ==============================
    account.schemaVersion = HDG.Constants.SCHEMA_VERSION  -- exception(boundary): SV migration -- stamps new schema

    return true   -- a migration ran (drives the one-time upgrade notice)
end

return M
