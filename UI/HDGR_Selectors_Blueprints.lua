-- HDGR_Selectors_Blueprints.lua
-- ============================================================================
-- Pure selectors for the Blueprints tab.
--
-- NOTE the near-collision: `session.blueprints.available` is a SERVER-derived
-- fact (BLUEPRINT_AVAILABLE_SET) about whether the blueprint system is usable.
-- The retired `blueprints.available` SELECTOR was something else entirely -- a
-- client-build capability gate for the nav child, which HDG no longer needs now
-- that the TOC is 12.1-only. Do not resurrect the name for either job.

local Selectors = HDG.Selectors

local CT_LABEL = { [1] = "House", [2] = "Room", [3] = "Decor", [4] = "Dye", [5] = "Fixture" }

-- Per-entry acquisition resolve. Plain local helper -- Selectors:Call passes
-- NO extra args, so per-item lookups never route through the registry. Catalog
-- access is the sanctioned live-facade pattern (ADR-003a); reactivity comes
-- from the session.resolvers.catalog.tick read on the registered selector.
-- Returns: itemID?, srcKind? (SOURCE_KINDS key for Format.SourceChip), srcName?
-- The recordID -> itemID join lives on the CATALOG (ItemIDForEntry), because a
-- second caller appeared for it -- the public API another Vamoose addon routes
-- a shopping list through. Two copies of a join is how the two quietly start
-- disagreeing about what a manifest entry means.
--
-- What stays here is the part the chips need and the API does not: which SOURCE
-- the row came from, and what to call it.
local function _resolveAcq(entry)
    local itemID = HDG.HousingCatalogObserver:ItemIDForEntry(entry)  -- exception(nullable): structural entry, or a catalog miss
    if not itemID then return nil, nil, nil end
    local row = entry.contentType == 4
        and HDG.HousingCatalogObserver:GetRow(entry.recordID)     -- exception(nullable): dyes may not be catalog rows
        or HDG.HousingCatalogObserver.byDecorID[entry.recordID]   -- exception(nullable): catalog lookup can miss
    -- A dye with no catalog row still routes -- its recordID IS the item ID --
    -- but there is nothing to hang a source chip on.
    if not row then return itemID, nil, nil end
    local kind = HDG.Constants.SOURCE_KIND_BY_DONOR[row.sourceType]  -- exception(nullable): source may be unbaked
    return itemID, kind and kind.key or nil, row.sourceName
end

-- Manifest entries arrive in SERVER order, which on a 201-decor blueprint is
-- unscannable -- the dye group alone reads Purple, Red, Blue, Black, White,
-- Brown, Green. Sorted by name for reading (asked for by madaileinhatter,
-- 2026-08-20).
--
-- recordID breaks ties so the order is TOTAL: table.sort is not stable, and two
-- entries can share a name (dyed variants), so without the tie-break their
-- relative order could differ between repaints and churn the scrollbox keys.
--
-- Returns a COPY. Sorting m.raw.contentGroups in place would have a selector
-- mutating stored state.
local function _byName(entries)
    local out = {}
    for i = 1, #entries do out[i] = entries[i] end
    table.sort(out, function(a, b)
        if a.name ~= b.name then return a.name < b.name end
        return a.recordID < b.recordID
    end)
    return out
end

-- The inspector envelope: manifest -> rendered groups with acquisition joins.
-- nil when nothing is selected; a groupless envelope while pending/failed.
-- missingCount counts ACQUIRABLE entries (Decor=3/Dye=4) with numMissing>0 --
-- fixtures/rooms/house types can't be routed or bought, so the number the
-- verdict shows matches what Route to Shopping actually adds (UX review #5).
-- Per-group header counts still cover every type.
Selectors:Register("blueprints.inspector", {
    reads = { "session.blueprints.selectedCode", "session.blueprints.manifests",
              "session.ui.blueprints.missingOnly", "session.ui.blueprints.collapsedGroups",
              "session.resolvers.catalog.tick" },
    fn = function(state)
        local sb = state.session.blueprints
        local code = sb.selectedCode
        if not code then return nil end                      -- exception(nullable): empty state pre-selection
        local m = sb.manifests[code]
        if not m or m.status ~= "received" then
            return { shareCode = code, status = m and m.status or "idle", groups = {}, missingCount = 0 }
        end
        local ui = state.session.ui.blueprints
        local groups, missing = {}, 0
        for _, g in ipairs(m.raw.contentGroups) do
            local items = {}
            for _, e in ipairs(_byName(g.entries)) do
                if e.numMissing > 0 and (g.contentType == 3 or g.contentType == 4) then missing = missing + 1 end
                if not ui.missingOnly or e.numMissing > 0 then
                    local itemID, srcKind, srcName = _resolveAcq(e)
                    items[#items + 1] = {
                        name = e.name, total = e.total, numMissing = e.numMissing,
                        invalid = e.invalid, tooltip = e.tooltip,
                        itemID = itemID, srcKind = srcKind, srcName = srcName,
                    }
                end
            end
            if #items > 0 then
                groups[#groups + 1] = {
                    ct = g.contentType, ctLabel = CT_LABEL[g.contentType],
                    collapsed = ui.collapsedGroups[g.contentType] == true,
                    items = items,
                }
            end
        end
        return { shareCode = code, status = "received", groups = groups,
                 missingCount = missing, shownMissingOnly = ui.missingOnly }
    end,
})

-- ===== Cost to build =========================================================
-- "Can I afford this blueprint?", beside "does it fit?". Asked for by
-- Madailein Hatter (Discord 2026-08-04): people pass up a share code because the
-- commitment is invisible until they are already committed.
--
-- Prices the ACQUISITION GAP, not the whole build -- what you still need, at
-- numMissing each. Only Decor(3)/Dye(4) can be bought; rooms and fixtures are
-- structural, which is the same set blueprints.inspector counts as missing.
--
-- A CURRENCY summary, not a gold total (owner ruling): housing decor is sold for
-- several currencies, so each keeps its own running total and gold is just
-- another line. Costs come from the catalog's baked row.costEntries
-- ({currencyID, amount, icon}) -- no vendor-DB join needed.
--
-- unpricedCount is carried, not swallowed. A total that silently drops the
-- entries it could not price reads as authoritative while being wrong; one that
-- says "12 of 47 unpriced" is honest about what it knows.
--
-- KNOWN LIMIT: row.costEntries is the FIRST vendor block's cost. Components
-- within it are ANDed (100g + 5 coupons) and summing them is right, but where an
-- item is sold "30 coupons OR 500g" the alternatives live in separate vendor
-- blocks (row.costVariants) and this counts whichever vendor is listed first.
-- So the badge is "a price to build", not "the cheapest price to build".
local ACQUIRABLE_CT = { [3] = true, [4] = true }

Selectors:Register("blueprints.acquisitionCost", {
    calls = { "blueprints.inspector" },
    reads = { "session.resolvers.catalog.tick" },
    fn = function(state, ctx)
        local insp = Selectors:Call("blueprints.inspector", state, ctx)
        local out = { currencies = {}, pricedCount = 0, unpricedCount = 0, missingCount = 0 }
        if not insp or insp.status ~= "received" then return out end  -- exception(nullable): nothing inspected yet
        local byCurrency, order = {}, {}
        for _, g in ipairs(insp.groups) do
            if ACQUIRABLE_CT[g.ct] then
                for _, it in ipairs(g.items) do
                    if it.numMissing > 0 then
                        out.missingCount = out.missingCount + 1
                        local row = it.itemID and HDG.HousingCatalogObserver:GetRow(it.itemID)  -- exception(nullable): uncatalogued entry
                        local entries = row and row.costEntries
                        if entries and #entries > 0 then
                            out.pricedCount = out.pricedCount + 1
                            for _, e in ipairs(entries) do
                                local cur = byCurrency[e.currencyID]
                                if not cur then
                                    cur = { currencyID = e.currencyID, total = 0, icon = e.icon }
                                    byCurrency[e.currencyID] = cur
                                    order[#order + 1] = cur
                                end
                                cur.total = cur.total + (e.amount or 0) * it.numMissing  -- exception(boundary): baked catalog cost may omit an amount
                            end
                        else
                            out.unpricedCount = out.unpricedCount + 1
                        end
                    end
                end
            end
        end
        -- Gold first, then by currencyID. NOT by magnitude: 4,200 of a token and
        -- 1,550 gold are different units, so ranking them against each other
        -- implies a comparison that does not exist -- and it put a token above
        -- gold purely for having a bigger number. Sorting by ID instead is
        -- arbitrary but honest, and it is total, so the badge cannot reshuffle
        -- between repaints. CURRENCY_GOLD is the -1 sentinel, so it sorts first
        -- on its own.
        table.sort(order, function(a, b) return a.currencyID < b.currencyID end)
        out.currencies = order
        return out
    end,
})

-- Badge text: every currency, gold first. Empty when there is nothing left to
-- buy -- the band already says "you have everything" and a "0" badge beside it
-- reads like a price, not an absence.
Selectors:Register("blueprints.costBadge", {
    calls = { "blueprints.acquisitionCost" },
    fn = function(state, ctx)
        local cost = Selectors:Call("blueprints.acquisitionCost", state, ctx)
        if #cost.currencies == 0 then return "" end
        local parts = {}
        for _, c in ipairs(cost.currencies) do
            parts[#parts + 1] = HDG.Format.FormatCurrency(c.total, c.currencyID, c.icon)
        end
        return table.concat(parts, "  ")
    end,
})

Selectors:Register("blueprints.hasCostBadge", {
    calls = { "blueprints.costBadge" },
    fn = function(state, ctx)
        return Selectors:Call("blueprints.costBadge", state, ctx) ~= ""
    end,
})

-- ===== Budget fit ============================================================
-- Room-type blueprints ADD to spent; House/Interior/Exterior REPLACE (verified
-- 68629), so meters compare the blueprint's COST against the target house MAX.
-- A cost of 0 means the blueprint doesn't touch that budget ("na"). The fit
-- verdict comes from blockingRequirementFlags (server-computed).

local function _meterState(cost, max)
    if cost <= 0 then return "na" end
    if cost > max then return "over" end
    if cost == max then return "full" end
    return "fit"
end

local METER_CAPTION = {
    na = "not used by this blueprint", fit = "fits", full = "fits exactly", over = "over budget",
}

-- Blueprint type for a code, from STATE only (selector-pure): the own-collection
-- entry's blueprintType, else the type stamped at paste time. Callers declare
-- reads on session.blueprints.groups + account.blueprints.pastedTypes.
local function _codeType(state, code)
    for _, g in ipairs(state.session.blueprints.groups) do
        for _, e in ipairs(g.entries or {}) do  -- exception(boundary): server payload shape
            if e.shareCode == code and e.blueprintType then return e.blueprintType end
        end
    end
    return state.account.blueprints.pastedTypes[code]  -- exception(nullable): pre-stamp pastes have no type
end

-- HousingBlueprintUnmetRequirementFlags bit -> Blizzard's shipped reason string.
-- Bits + globals verified 12.1.68629 (enum key != global suffix -- e.g.
-- MissingRoom=2 -> ERR_..._ROOM, InsufficientBudget=1 -> ERR_..._BUDGETS -- so
-- the map is explicit). The English `alt` only shows headless/pre-12.1, where
-- this path never renders (blueprints are 12.1-only).
local BLOCK_FLAGS = {
    { bit = 1,   g = "ERR_HOUSING_BLUEPRINT_REQUIREMENT_BUDGETS",          alt = "not enough placement budget" },
    { bit = 2,   g = "ERR_HOUSING_BLUEPRINT_REQUIREMENT_ROOM",             alt = "rooms not unlocked" },
    { bit = 4,   g = "ERR_HOUSING_BLUEPRINT_REQUIREMENT_FIXTURE",          alt = "fixtures not unlocked" },
    { bit = 8,   g = "ERR_HOUSING_BLUEPRINT_REQUIREMENT_DECOR",            alt = "missing decor" },
    { bit = 16,  g = "ERR_HOUSING_BLUEPRINT_REQUIREMENT_DYE",              alt = "missing dyes" },
    { bit = 32,  g = "ERR_HOUSING_BLUEPRINT_REQUIREMENT_EXTERIOR_FACTION", alt = "wrong faction for this house type" },
    { bit = 64,  g = "ERR_HOUSING_BLUEPRINT_REQUIREMENT_HOUSE_TYPE",       alt = "house type not unlocked" },
    { bit = 128, g = "ERR_HOUSING_BLUEPRINT_REQUIREMENT_HOUSE_SIZE",       alt = "house size not unlocked" },
}

Selectors:Register("blueprints.budgetFit", {
    reads = { "session.blueprints.selectedCode", "session.blueprints.manifests",
              "session.blueprints.groups", "account.blueprints.pastedTypes" },
    fn = function(state)
        local sb = state.session.blueprints
        local m = sb.selectedCode and sb.manifests[sb.selectedCode]
        if not m or m.status ~= "received" then return { meters = {}, fits = false } end  -- exception(nullable): no manifest yet
        local raw = m.raw
        -- 12.1 (68675) reshaped the blueprint contents budget (verified in-game
        -- 2026-07-15). `budgetInfo` now holds `interiorBudgets` + `exteriorBudgets`,
        -- each a map keyed by HousingBudgetType (0 = RoomPlacement, 1 = DecorPlacement,
        -- 2 = PetDecor) -> { max, current, cost }. The old flat targetHouseBudgetInfo /
        -- raw.*BudgetCost fields are gone. Rooms are interior-only; decor splits
        -- interior/exterior; PetDecor (2) feeds the interiorPet/exteriorPet meters below.
        local bi = raw.budgetInfo or {}  -- exception(boundary): nilable for houseless players
        local inter, exter = bi.interiorBudgets or {}, bi.exteriorBudgets or {}
        local room, intDecor, extDecor = inter[0] or {}, inter[1] or {}, exter[1] or {}  -- exception(boundary): reshaped/nilable budget map
        local intPet, extPet = inter[2] or {}, exter[2] or {}  -- PetDecor = budgetType 2; exception(boundary): reshaped/nilable
        local meters = {
            { key = "room",        name = "Rooms",          cost = room.cost     or 0, max = room.max     or 0, cur = room.current     or 0 },
            { key = "interior",    name = "Interior decor", cost = intDecor.cost or 0, max = intDecor.max or 0, cur = intDecor.current or 0 },
            { key = "exterior",    name = "Exterior decor", cost = extDecor.cost or 0, max = extDecor.max or 0, cur = extDecor.current or 0 },
            { key = "interiorPet", name = "Interior pets",  cost = intPet.cost   or 0, max = intPet.max   or 0, cur = intPet.current   or 0 },
            { key = "exteriorPet", name = "Exterior pets",  cost = extPet.cost   or 0, max = extPet.max   or 0, cur = extPet.current   or 0 },
        }
        -- Room blueprints ADD to the target's spent budget (House/Interior/
        -- Exterior REPLACE -- verified 68629), so a Room's headroom is what's
        -- LEFT (max - current), not the full max (review finding: meters could
        -- show green while the server verdict said over-budget).
        local isRoomAdd = _codeType(state, sb.selectedCode) == 2
        for _, mt in ipairs(meters) do
            local avail = isRoomAdd and (mt.max - mt.cur) or mt.max
            mt.used    = mt.cost > 0
            mt.state   = _meterState(mt.cost, avail)
            -- 12.1 uses cost = -1 (was 0) for a budget the blueprint doesn't touch;
            -- _meterState already maps cost<=0 -> "na", so clamp the DISPLAY so the
            -- label reads "0 / N" (not "-1 / N"). Caption still says "not used".
            mt.label   = math.max(mt.cost, 0) .. " / " .. avail
            mt.caption = METER_CAPTION[mt.state]
        end
        local blocking = raw.blockingRequirementFlags
        local blockingText
        if blocking ~= 0 then
            local parts = {}
            for _, f in ipairs(BLOCK_FLAGS) do
                if blocking % (f.bit * 2) >= f.bit then
                    parts[#parts + 1] = _G[f.g] or f.alt  -- exception(boundary): Blizzard string, nil headless/pre-12.1
                end
            end
            blockingText = table.concat(parts, " ")   -- Blizzard's strings are full sentences
        end
        return { meters = meters, fits = (blocking == 0), blocking = blocking, blockingText = blockingText }
    end,
})

-- ===== Naming ================================================================
-- The manifest has NO top-level name (verified 68629). Display-name resolution:
-- own collection name -> player label (account.blueprints.labels) -> the
-- house-type entry name from the manifest -> the short code. Plain local
-- helper shared with collectionRows (Selectors:Call passes no extra args).

local function _houseTypeName(manifest)
    if not manifest or not manifest.raw then return nil end
    for _, g in ipairs(manifest.raw.contentGroups) do
        if g.contentType == 1 and g.entries[1] then return g.entries[1].name end
    end
    return nil
end

local function _displayName(state, shareCode)
    for _, g in ipairs(state.session.blueprints.groups) do
        for _, e in ipairs(g.entries or {}) do  -- exception(boundary): server payload shape
            if e.shareCode == shareCode and e.name then return e.name end  -- own saved: Blizzard name wins
        end
    end
    local label = state.account.blueprints.labels[shareCode]
    if label then return label end
    return _houseTypeName(state.session.blueprints.manifests[shareCode])
        or (shareCode:sub(1, 10) .. "...")
end

-- Display name for the SELECTED code (the inspector header binding).
Selectors:Register("blueprints.displayName", {
    reads = { "session.blueprints.selectedCode", "session.blueprints.groups",
              "session.blueprints.manifests", "account.blueprints.labels" },
    fn = function(state)
        local code = state.session.blueprints.selectedCode
        if not code then return nil end  -- exception(nullable): empty state pre-selection
        return _displayName(state, code)
    end,
})

-- ===== Collection browser rows ==============================================
-- Flat scrollbox projection: group-header rows (kind="header") + entry rows
-- (kind="row"). Pasted & shared first (forget-eligible), then the player's own
-- saved blueprints in their server groups.

local BP_TYPE_LABEL = { [1] = "House", [2] = "Room", [3] = "Interior", [4] = "Exterior" }

Selectors:Register("blueprints.collectionRows", {
    reads = { "session.blueprints.groups", "account.blueprints.pasted",
              "session.blueprints.selectedCode", "session.blueprints.manifests",
              "account.blueprints.pastedTypes", "account.blueprints.labels",
              "account.blueprints.factions" },
    fn = function(state)
        local sb, ab, rows = state.session.blueprints, state.account.blueprints, {}
        if #ab.pasted > 0 then
            rows[#rows + 1] = { kind = "header", label = "Pasted codes" }
            for _, code in ipairs(ab.pasted) do
                rows[#rows + 1] = {
                    kind = "row", shareCode = code,
                    name = _displayName(state, code),
                    typeLabel = BP_TYPE_LABEL[ab.pastedTypes[code]],  -- exception(nullable): pre-stamp pastes have no type
                    faction = ab.factions[code],  -- exception(nullable): only House/Exterior, only after inspect
                    isPasted = true, isSelected = (code == sb.selectedCode),
                }
            end
        end
        local catalogShown = false
        for _, g in ipairs(sb.groups) do
            local entries = g.entries or {}  -- exception(boundary): server payload shape
            if #entries > 0 then
                if not catalogShown then  -- one zone divider, before the first non-empty group
                    rows[#rows + 1] = { kind = "divider", label = "Your catalog" }
                    catalogShown = true
                end
                rows[#rows + 1] = { kind = "header", label = g.name or "My blueprints" }  -- exception(boundary): server payload
                for _, e in ipairs(entries) do
                    rows[#rows + 1] = {
                        kind = "row", shareCode = e.shareCode,
                        blueprintID = e.blueprintID,   -- unique numeric ID (distinct from shareCode)
                        name = _displayName(state, e.shareCode),
                        typeLabel = BP_TYPE_LABEL[e.blueprintType],
                        faction = ab.factions[e.shareCode],  -- exception(nullable): only House/Exterior, only after inspect
                        isAuto = e.isAutoSave == true,
                        isPasted = false, isSelected = (e.shareCode == sb.selectedCode),
                    }
                end
            end
        end
        return rows
    end,
})

-- ===== House picker ==========================================================
-- Emits RAW session-scoped houseGUIDs ("Opaque-N") -- exactly what
-- RequestBlueprintContentsForContext needs. Deliberately NOT reusing
-- projects.houseMenuItems: Projects re-hashes name+plotID into its own stable
-- ID space, which is the WRONG token for the blueprint API.

-- Radio menu items for the dropdown kind: { value, text } (kind defaults to
-- radio; picking dispatches { houseGUID = value } via the widget's dispatch spec).
Selectors:Register("blueprints.houseMenuItems", {
    reads = { "session.house.ownedHouses" },
    fn = function(state)
        local items = {}
        for guid, h in pairs(state.session.house.ownedHouses) do
            items[#items + 1] = {
                value = guid,
                text = h.houseName or h.name or guid,  -- exception(boundary): HouseInfo fields nilable (_SIGNATURES gotcha)
            }
        end
        table.sort(items, function(a, b) return a.text < b.text end)
        return items
    end,
})

-- What is currently selected: an OWN saved blueprint (carries blueprintID +
-- Blizzard's real name; rename hits the catalog) or a pasted code (HDG label
-- overlay). Drives the name box's text AND which rename mechanism it commits to.
Selectors:Register("blueprints.selectedEntry", {
    reads = { "session.blueprints.selectedCode", "session.blueprints.groups", "account.blueprints.labels" },
    fn = function(state)
        local code = state.session.blueprints.selectedCode
        if not code then return nil end  -- exception(nullable): empty pre-selection
        for _, g in ipairs(state.session.blueprints.groups) do
            for _, e in ipairs(g.entries or {}) do  -- exception(boundary): server payload shape
                if e.shareCode == code then
                    return { isOwn = true, blueprintID = e.blueprintID, name = e.name, isAuto = e.isAutoSave == true }
                end
            end
        end
        return { isOwn = false, label = state.account.blueprints.labels[code] }
    end,
})


-- Architect lays out interior rooms, so it only makes sense for a full House (1)
-- or an Interior (3) -- not a single Room (2) or an Exterior (4).
Selectors:Register("blueprints.selectedIsArchitectable", {
    reads = { "session.blueprints.selectedCode", "session.blueprints.groups", "account.blueprints.pastedTypes" },
    fn = function(state)
        local code = state.session.blueprints.selectedCode
        if not code then return false end  -- exception(nullable): empty pre-selection
        local t = _codeType(state, code)
        return t == 1 or t == 3   -- House / Interior (see BP_TYPE_LABEL)
    end,
})


-- Current picker value (dropdown `current` binding). Until the player picks a
-- house explicitly, fall back to the TARGET the server actually computed the
-- selected manifest against (a no-target request defaults to the current
-- house) -- so the dropdown always names the house the numbers are for
-- (UX review #7). Display-only: dispatching a back-fill would re-trigger the
-- target-change re-fetch and loop.
Selectors:Register("blueprints.targetHouse", {
    reads = { "session.blueprints.targetHouseGUID", "session.blueprints.selectedCode",
              "session.blueprints.manifests" },
    fn = function(state)
        local sb = state.session.blueprints
        if sb.targetHouseGUID then return sb.targetHouseGUID end
        local m = sb.selectedCode and sb.manifests[sb.selectedCode]
        return m and m.raw and m.raw.targetHouseGUID or nil  -- exception(nullable): no manifest / pre-target
    end,
})

-- ===== Failure + pending copy (player-facing text is selector-composed) ======

Selectors:Register("blueprints.failureText", {
    reads = { "session.blueprints.selectedCode", "session.blueprints.manifests" },
    fn = function(state)
        local sb = state.session.blueprints
        local m = sb.selectedCode and sb.manifests[sb.selectedCode]
        if not m or m.status ~= "failed" then return nil end  -- exception(nullable): not in a failed state
        if m.timedOut then
            -- Ticker-swept timeout: the server silently dropped the request
            -- (no RECEIVED or FAILURE ever fires for some foreign codes).
            return "No response from the server -- this code may not be readable from here."
        end
        if m.reasonCode == Enum.HousingResult.DbError then    -- exception(boundary): Blizzard enum (never hardcode values)
            -- Cause-neutral: our only DbError sample was a PTR db-wipe; a live
            -- deleted code may return BlueprintNotFound(8), which the map covers.
            return "This blueprint no longer exists on the server."
        end
        local map = _G.HousingResultToErrorText  -- exception(boundary): Blizzard global map (verified global, 68629)
        return map[m.reasonCode] or _G.ERR_HOUSING_RESULT_BLUEPRINT_GENERIC_CONTENT_ERROR  -- exception(boundary): not every value is mapped
    end,
})

-- Count-up pending copy (big manifests take 5-10s). Escalates at 15s; the
-- observer's ticker sweep flips a dead request to a timedOut failure at
-- BLUEPRINT_REQUEST_TIMEOUT. Pure: elapsed composes from the tick-dispatched
-- pendingNow, never GetTime().
local BP_PENDING_ESCALATE_S = 15

Selectors:Register("blueprints.pendingText", {
    reads = { "session.blueprints.selectedCode", "session.blueprints.manifests",
              "session.blueprints.pendingNow" },
    fn = function(state)
        local sb = state.session.blueprints
        local m = sb.selectedCode and sb.manifests[sb.selectedCode]
        if not m or m.status ~= "pending" then return nil end  -- exception(nullable): not pending
        local elapsed = math.max(0, math.floor(sb.pendingNow - (m.requestedAt or sb.pendingNow)))  -- exception(optional): first render may precede the first tick
        if elapsed >= BP_PENDING_ESCALATE_S then
            return ("Still waiting (%ds) -- some codes never get a reply; this gives up at %ds."):format(
                elapsed, HDG.Constants.BLUEPRINT_REQUEST_TIMEOUT)
        end
        return ("Waiting for the server... (%ds)"):format(elapsed)
    end,
})

-- ===== View-composition selectors (LayoutConfig bindings) ====================
-- All thin, pure projections over inspector/budgetFit for the declarative tree.

-- Flat scrollbox projection: header rows + item rows; a collapsed group keeps
-- its header but hides its items.
Selectors:Register("blueprints.contentRows", {
    calls = { "blueprints.inspector" },
    fn = function(state, ctx)
        local insp = Selectors:Call("blueprints.inspector", state, ctx)
        if not insp or insp.status ~= "received" then return {} end
        local rows = {}
        for _, g in ipairs(insp.groups) do
            local gm = 0
            for _, it in ipairs(g.items) do if it.numMissing > 0 then gm = gm + 1 end end
            rows[#rows + 1] = { kind = "header", ct = g.ct, label = g.ctLabel,
                                count = #g.items, missing = gm, collapsed = g.collapsed }
            if not g.collapsed then
                for _, it in ipairs(g.items) do
                    rows[#rows + 1] = { kind = "item", ct = g.ct, name = it.name,
                        total = it.total, numMissing = it.numMissing, invalid = it.invalid,
                        tooltip = it.tooltip, itemID = it.itemID, srcKind = it.srcKind, srcName = it.srcName }
                end
            end
        end
        return rows
    end,
})

local function _meterByKey(state, ctx, key)
    local b = Selectors:Call("blueprints.budgetFit", state, ctx)
    for _, m in ipairs(b.meters) do
        if m.key == key then return m end
    end
    return nil
end

local function _meterFrac(m)
    if not m or m.max <= 0 or m.cost <= 0 then return 0 end
    local p = m.cost / m.max
    return (p > 1) and 1 or p
end

-- Blizzard's own budget icons (Blizzard_HousingBlueprintContentSummary.xml,
-- ptr): rooms / interior decor / exterior decor. Icon + numbers, like the
-- Import dialog; the bar tooltips carry the full budget names.
local METER_ICON = {
    room        = "house-room-limit-icon",
    interior    = "house-decor-budget-icon",
    exterior    = "house-decor-exteriorbudget-icon",
    interiorPet = "house-decor-pets-icon",
    exteriorPet = "house-decor-pets-icon",
}

local function _meterText(m)
    -- No caption: the bar color carries the state (teal fits / amber at-limit /
    -- red over), and any blocking reason is spelled out in the fit-verdict line.
    if not m then return "" end
    return "|A:" .. METER_ICON[m.key] .. ":14:14|a  " .. m.label
end

Selectors:Register("blueprints.meterFracRoom", {
    calls = { "blueprints.budgetFit" },
    fn = function(state, ctx) return _meterFrac(_meterByKey(state, ctx, "room")) end,
})
Selectors:Register("blueprints.meterTextRoom", {
    calls = { "blueprints.budgetFit" },
    fn = function(state, ctx) return _meterText(_meterByKey(state, ctx, "room")) end,
})
Selectors:Register("blueprints.meterFracInterior", {
    calls = { "blueprints.budgetFit" },
    fn = function(state, ctx) return _meterFrac(_meterByKey(state, ctx, "interior")) end,
})
Selectors:Register("blueprints.meterTextInterior", {
    calls = { "blueprints.budgetFit" },
    fn = function(state, ctx) return _meterText(_meterByKey(state, ctx, "interior")) end,
})
Selectors:Register("blueprints.meterFracExterior", {
    calls = { "blueprints.budgetFit" },
    fn = function(state, ctx) return _meterFrac(_meterByKey(state, ctx, "exterior")) end,
})
Selectors:Register("blueprints.meterTextExterior", {
    calls = { "blueprints.budgetFit" },
    fn = function(state, ctx) return _meterText(_meterByKey(state, ctx, "exterior")) end,
})
Selectors:Register("blueprints.meterFracInteriorPet", {
    calls = { "blueprints.budgetFit" },
    fn = function(state, ctx) return _meterFrac(_meterByKey(state, ctx, "interiorPet")) end,
})
Selectors:Register("blueprints.meterTextInteriorPet", {
    calls = { "blueprints.budgetFit" },
    fn = function(state, ctx) return _meterText(_meterByKey(state, ctx, "interiorPet")) end,
})
Selectors:Register("blueprints.meterFracExteriorPet", {
    calls = { "blueprints.budgetFit" },
    fn = function(state, ctx) return _meterFrac(_meterByKey(state, ctx, "exteriorPet")) end,
})
Selectors:Register("blueprints.meterTextExteriorPet", {
    calls = { "blueprints.budgetFit" },
    fn = function(state, ctx) return _meterText(_meterByKey(state, ctx, "exteriorPet")) end,
})

-- Fit verdict pill line ("Fits this house -- N items to acquire first").
Selectors:Register("blueprints.fitVerdict", {
    calls = { "blueprints.budgetFit", "blueprints.inspector" },
    fn = function(state, ctx)
        local insp = Selectors:Call("blueprints.inspector", state, ctx)
        if not insp or insp.status ~= "received" then return "" end
        local b = Selectors:Call("blueprints.budgetFit", state, ctx)
        if not b.fits then return b.blockingText end
        if insp.missingCount > 0 then
            return ("Fits this house -- %d item%s to acquire first"):format(
                insp.missingCount, insp.missingCount == 1 and "" or "s")
        end
        return "Fits this house -- you have everything"
    end,
})

-- Selection gates: the action row enables only with a selection, and the
-- blank-state hint shows only without one (UX review #1).
Selectors:Register("blueprints.hasSelection", {
    reads = { "session.blueprints.selectedCode" },
    fn = function(state) return state.session.blueprints.selectedCode ~= nil end,
})
-- Enable gate for actions that need CONTENTS, not just a selection: Copy
-- requirements has nothing to render until the server answers, and a live
-- button that copies an empty string reads as a broken button.
Selectors:Register("blueprints.hasManifest", {
    reads = { "session.blueprints.selectedCode", "session.blueprints.manifests" },
    fn = function(state)
        local sb = state.session.blueprints
        local m = sb.selectedCode and sb.manifests[sb.selectedCode]
        return m ~= nil and m.status == "received"
    end,
})
Selectors:Register("blueprints.blankDetail", {
    reads = { "session.blueprints.selectedCode" },
    fn = function(state) return state.session.blueprints.selectedCode == nil end,
})
-- Verdict band shows only when there is a verdict to show (card chrome on an
-- empty string reads as a stray stripe).
Selectors:Register("blueprints.hasVerdict", {
    calls = { "blueprints.fitVerdict" },
    fn = function(state, ctx)
        local v = Selectors:Call("blueprints.fitVerdict", state, ctx)
        return v ~= nil and v ~= ""
    end,
})


-- Pending/failure/paste-error line under the header (one label; nil states
-- compose to ""). Paste errors outrank the manifest states -- the player just
-- typed something and needs the answer next to the field.
Selectors:Register("blueprints.statusLine", {
    reads = { "session.ui.blueprints.pasteError" },
    calls = { "blueprints.pendingText", "blueprints.failureText" },
    fn = function(state, ctx)
        if state.session.ui.blueprints.pasteError then
            return "That doesn't look like a share code -- check the paste and try again."
        end
        return Selectors:Call("blueprints.pendingText", state, ctx)
            or Selectors:Call("blueprints.failureText", state, ctx)
            or ""  -- exception(nullable): both are nil outside pending/failed states
    end,
})

-- Segmented filter actives ("All items" / "Missing only").
Selectors:Register("blueprints.filterAllActive", {
    reads = { "session.ui.blueprints.missingOnly" },
    fn = function(state) return state.session.ui.blueprints.missingOnly == false end,
})
Selectors:Register("blueprints.filterMissingActive", {
    reads = { "session.ui.blueprints.missingOnly" },
    fn = function(state) return state.session.ui.blueprints.missingOnly == true end,
})

-- "N items - M missing" (controls-row right).
Selectors:Register("blueprints.itemCountText", {
    calls = { "blueprints.inspector" },
    fn = function(state, ctx)
        local insp = Selectors:Call("blueprints.inspector", state, ctx)
        if not insp or insp.status ~= "received" then return "" end
        local total = 0
        for _, g in ipairs(insp.groups) do total = total + #g.items end
        return ("%d items -- %d missing"):format(total, insp.missingCount)
    end,
})

-- "Blueprint slots  used / max" (browser footer).
Selectors:Register("blueprints.slotsText", {
    reads = { "session.blueprints.slots" },
    fn = function(state)
        local s = state.session.blueprints.slots
        if s.max <= 0 then return "" end
        return ("Blueprint slots  %d / %d"):format(s.used, s.max)
    end,
})

-- ===== Plain-text manifest ===================================================
-- A readable requirements list to publish ALONGSIDE the share code -- a Reddit
-- post, a Discord drop, a Wowhead comment. The audience is the READER of
-- someone else's post, which is why nothing here reflects the exporter's own
-- collection: counts are `total`, never numMissing, and there are no budgets
-- and no progress. That is what makes the output publishable rather than
-- personal -- the author owns everything, so their missing count is zero and
-- the reader's is different.
--
-- Spec: docs/HDGR_PLAINTEXT_EXPORT_SPEC_2026-08-20.md
--
-- Deliberately NOT built on blueprints.inspector: that envelope applies the
-- player's missing-only filter, which would silently drop lines from a
-- published list. This reads the manifest.

-- Plural headings are an explicit map, not CT_LABEL .. "S" -- "DECOR" is a mass
-- noun and "DECORS" is not a word.
local CT_HEADING  = { [1] = "HOUSE", [2] = "ROOMS", [3] = "DECOR", [4] = "DYES", [5] = "FIXTURES" }
local PET_HEADING = "PET DECOR"

local EXPORT_FOOTER = "Generated by Vamoose's Housing Decor Guide\n"
    .. "https://www.curseforge.com/wow/addons/housing-decor-guide"

-- " -- " separates the entry from its source: a single hyphen would read as a
-- second bullet beside the leading "- ", and an em-dash is not ASCII.
-- Decor lines carry a source; every other group is name and count. Dyes are
-- crafted or bought at auction, so a source tells the reader nothing, and
-- rooms / fixtures / house types have no acquisition join at all.
local function _textLine(entry, withSource)
    local line = ("- %s x%d"):format(entry.name, entry.total)
    if not withSource then return line end
    local _, srcKind, srcName = _resolveAcq(entry)
    -- UNKN is the honest "no signal" fallback the on-screen chip wants so data
    -- gaps surface. A published list is the wrong place for it: it would stamp
    -- "Unknown" on every unbaked line. Bare is better.
    if not (srcKind and srcName) or srcKind == "UNKN" then return line end
    return ("%s -- %s: %s"):format(line, HDG.Constants.SOURCE_KIND_BY_KEY[srcKind].label, srcName)
end

-- No column alignment anywhere: Reddit, Discord, forums and Wowhead comments do
-- not all preserve whitespace, but "- name xN" survives every one of them.
-- The header count is the sum of totals, so ROOMS (3) matches x1 + x2 below it.
local function _blockText(heading, entries, withSource)
    if #entries == 0 then return nil end
    local total, lines = 0, {}
    for _, e in ipairs(entries) do
        total = total + e.total
        lines[#lines + 1] = _textLine(e, withSource)
    end
    return ("%s (%d)\n%s"):format(heading, total, table.concat(lines, "\n"))
end

-- Pet decor is decor a pet can be placed ON -- beds, plinths, nests. It is
-- furniture, so these are ordinary contentType 3 entries and this is a
-- presentation split, which is why the block renders next to DECOR rather than
-- somewhere else in manifest order.
local function _splitPetDecor(entries)
    local plain, pets = {}, {}
    for _, e in ipairs(entries) do
        local bucket = HDG.Constants.PET_DECOR_BY_DECOR_ID[e.recordID] and pets or plain
        bucket[#bucket + 1] = e
    end
    return plain, pets
end

local function _headerText(state, ctx, code)
    local name = Selectors:Call("blueprints.displayName", state, ctx)
    local typeLabel = BP_TYPE_LABEL[_codeType(state, code)]  -- exception(nullable): a pasted code may have no type stamp
    return ("%s\nShare code: %s"):format(
        typeLabel and ("%s - %s blueprint"):format(name, typeLabel) or name, code)
end

-- Every content type, not only the acquirable ones: someone building this needs
-- to know it wants three rooms, not only the furniture inside them. (The
-- Decor/Dye-only filter on blueprints.inspector's missingCount is correct for a
-- shopping list, and a manifest is not a shopping list.)
-- Group order follows the manifest's own contentType order, not an invented one.
Selectors:Register("blueprints.manifestText", {
    calls = { "blueprints.displayName" },
    reads = { "session.blueprints.selectedCode", "session.blueprints.manifests",
              "session.blueprints.groups", "account.blueprints.pastedTypes",
              "session.resolvers.catalog.tick" },
    fn = function(state, ctx)
        local sb = state.session.blueprints
        local code = sb.selectedCode
        if not code then return nil end  -- exception(nullable): nothing selected
        local m = sb.manifests[code]
        if not m or m.status ~= "received" then return nil end  -- exception(nullable): no contents to publish yet
        local blocks = { _headerText(state, ctx, code) }
        for _, g in ipairs(m.raw.contentGroups) do
            if g.contentType == 3 then
                local plain, pets = _splitPetDecor(_byName(g.entries))
                blocks[#blocks + 1] = _blockText(CT_HEADING[3], plain, true)
                blocks[#blocks + 1] = _blockText(PET_HEADING, pets, true)
            else
                blocks[#blocks + 1] = _blockText(CT_HEADING[g.contentType], _byName(g.entries), false)
            end
        end
        blocks[#blocks + 1] = EXPORT_FOOTER
        return table.concat(blocks, "\n\n")
    end,
})
