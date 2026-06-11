-- HDG.Selectors -- HouseEditor Companion
-- ============================================================================
-- Selectors for the companion window content. Six display modes:
--   styles      -- user-created style + smartset collections
--   shopping    -- shopping list collections
--   snapshots   -- saved placed-decor snapshots
--   themes      -- pre-authored Room Concepts (StyleDefinitions, tier="thematic")
--   collections -- pre-authored Useful Collections (CollectionDefinitions)
--   recent      -- live placed decor (session.styles.placedDecor)
--
-- Sidebar = collections matching current mode (or recent items flat for "recent").
-- Selecting a sidebar row sets session.ui.companion.selectedItemID.
-- Grid = items in the selected collection (or placedDecor map for "recent").
--
-- Reuses existing data sources (Styles/Collections StaticData, account.collections,
-- session.styles.placedDecor) -- companion is a different view onto Styles-tab data.

HDG = HDG or {}
HDG.Selectors = HDG.Selectors or {}
local Selectors = HDG.Selectors

-- ============================================================================
-- Bare-path selectors (chrome state for binding / repaint subscriptions)
-- ============================================================================

Selectors:Register("companion.windowShown", {
    reads = {"session.ui.companion.windowShown"},
    fn = function(state) return state.session.ui.companion.windowShown == true end,
})

Selectors:Register("companion.mode", {
    reads = {"session.ui.companion.mode"},
    fn = function(state) return state.session.ui.companion.mode end,
})

Selectors:Register("companion.search", {
    reads = {"session.ui.companion.search"},
    fn = function(state) return state.session.ui.companion.search end,
})

Selectors:Register("companion.selectedItemID", {
    reads = {"session.ui.companion.selectedItemID"},
    fn = function(state) return state.session.ui.companion.selectedItemID end,
})

-- Persistent window position: { x, y }, either field may be nil (-> default anchor).
-- Frame restore-on-show reads this; OnDragStop dispatches COMPANION_SET_POSITION.
Selectors:Register("companion.windowPosition", {
    reads = {"account.ui.companion.window"},
    fn = function(state) return state.account.ui.companion.window end,
})

-- Cost-badge visibility toggle (header chip active-state + grid cell stamp).
Selectors:DefinePath("companion.showCost", "session.ui.companion.showCost")

-- Indoor/Outdoor 3-state filter label (header button text binding).
local IO_LABELS = { all = "Indoor + Outdoor", indoor = "Indoor only", outdoor = "Outdoor only" }
Selectors:Register("companion.ioLabel", {
    reads = {"session.ui.companion.ioFilter"},
    fn = function(state) return IO_LABELS[state.session.ui.companion.ioFilter] end,
})

-- Per-mode active-state selectors for the mode chip strip (companion.isMode_<key>).
Selectors:DefineEnum("companion.isMode", "session.ui.companion.mode",
    { "styles", "rooms", "snapshots", "themes", "collections", "recent" })

-- ============================================================================
-- Mode -> collection-type mapping
-- ============================================================================

local MODE_TO_TYPES = {
    styles      = { style = true, smartset = true },   -- user-created styles + smart sets
    -- "rooms" handled separately -- sourced from account.rooms, not collections
    snapshots   = { snapshot = true },
    themes      = { concept = true },                  -- pre-authored Room Concepts
    collections = { collection = true },               -- pre-authored Useful Collections
    -- "recent" handled separately -- not a collection-type filter
}

local function iterAllCollectionsForCompanion(state)
    local out = {}
    -- User collections (account.collections)
    for id, def in pairs(state.account.collections) do
        local colonAt = id:find(":")
        local t = colonAt and id:sub(1, colonAt - 1) or "style"
        if def.type and def.type ~= "" then t = def.type end
        out[#out + 1] = { id = id, type = t, def = def }
    end
    -- Pre-authored Room Concepts
    local sd = HDG.StaticData.Styles:GetDefinitions()
    if type(sd) == "table" then
        for sid, def in pairs(sd) do
                    -- Runtime type: "concept" or "collection". Data-level `tier` is the
            -- semantic subcategory; runtime type drives the filter enum + LandingSection.
            local t = (def.tier == "collection") and "collection" or "concept"
            out[#out + 1] = { id = "concept:" .. sid, type = t, def = def }
        end
    end
    -- Pre-authored Useful Collections
    local cd = HDG.StaticData.Collections:GetDefinitions()
    if type(cd) == "table" then
        for cid, def in pairs(cd) do
            out[#out + 1] = { id = "collection:" .. cid, type = "collection", def = def }
        end
    end
    return out
end

-- ============================================================================
-- Placement-cost buckets ("By Placement Cost" mode).
-- ~99% of decor sits at 1/3/5; cost 6+ is structural room pieces.
-- Declared above sidebarRows + gridItems (both read it).
-- ============================================================================

local PLACEMENT_COST_BUCKETS = {
    { id = "placementcost:small",  text = "Small (1-2)",  lo = 1, hi = 2  },
    { id = "placementcost:medium", text = "Medium (3-4)", lo = 3, hi = 4  },
    { id = "placementcost:large",  text = "Large (5)",    lo = 5, hi = 5  },
    { id = "placementcost:xlarge", text = "X-Large (6+)", lo = 6, hi = 99 },
}
local PLACEMENT_COST_BUCKET_BY_ID = {}
for _, b in ipairs(PLACEMENT_COST_BUCKETS) do PLACEMENT_COST_BUCKET_BY_ID[b.id] = b end

-- Special (resolver-based) collections pinned to the TOP of the Collections sidebar
-- in this order, with a divider after. Mirrors HDG's collection order.
local SPECIAL_COLLECTION_ORDER = {
    ["collection:recently-learned"] = 1,
    ["collection:dyeable"]          = 2,
    ["collection:trophies"]         = 3,
}

-- Themes-mode sidebar: concepts grouped by tier into "Room Concepts / Themed / Faction" sections.
local TIER_SECTIONS = {
    { tier = "thematic", label = "Room Concepts" },
    { tier = "themed",   label = "Themed" },
    { tier = "faction",  label = "Faction" },
}

-- Group concept rows by def.tier into header-prefixed sections. Untiered rows
-- fall under "Room Concepts". Each section + its rows alpha-sorted. Rows already
-- carry isSelected (stamped by the caller), so no selection arg needed here.
local function _sectionByTier(matches)
    local byTier = {}
    for _, m in ipairs(matches) do
        local t = m.tier or "thematic"
        byTier[t] = byTier[t] or {}
        byTier[t][#byTier[t] + 1] = m
    end
    local out = {}
    for _, sec in ipairs(TIER_SECTIONS) do
        local group = byTier[sec.tier]
        if group and #group > 0 then
            table.sort(group, function(a, b)
                return tostring(a.displayName):lower() < tostring(b.displayName):lower()
            end)
            out[#out + 1] = { isHeader = true, displayName = sec.label }
            for _, m in ipairs(group) do out[#out + 1] = m end
        end
    end
    return out
end

-- Owned-item count per cost bucket (one catalog walk; mirrors the grid's owned-only filter).
-- sweepGeneration in the consuming selector's reads refreshes counts on each sweep.
local function _bucketCounts()
    local counts = {}
    for _, b in ipairs(PLACEMENT_COST_BUCKETS) do counts[b.id] = 0 end
    if not HDG.HousingCatalogObserver:IsReady() then return counts end
    HDG.HousingCatalogObserver:IterateRows(function(_, row)
        local cost = row.placementCost
        if cost and HDG.HousingCatalogObserver:IsOwned(row) then
            for _, b in ipairs(PLACEMENT_COST_BUCKETS) do
                if cost >= b.lo and cost <= b.hi then
                    counts[b.id] = counts[b.id] + 1
                    break
                end
            end
        end
    end)
    return counts
end

-- ============================================================================
-- Sidebar rows for the current mode.
-- ============================================================================

Selectors:Register("companion.sidebarRows", {
    reads = {
        "session.ui.companion.mode",
        "session.ui.companion.search",
        "session.ui.companion.selectedItemID",
        "account.collections",
        "account.rooms",                     -- rooms-mode sidebar: one row per room
        "account.furnishingSets",            -- rooms-mode counts
        "session.furn",                      -- rooms-mode change tick
        "session.house.roomCatalog",         -- rooms-mode blueprint tiles
        "session.styles.cacheTick",
        "session.staticData.tick",
        "session.catalog.sweepGeneration",   -- cost-bucket owned counts
    },
    calls = { "companion.recentSessions" },  -- recent-mode sidebar (pulls account.recentActivity into the reads-closure)
    fn = function(state)
        local mode     = state.session.ui.companion.mode
        local search   = state.session.ui.companion.search:lower()
        local selected = state.session.ui.companion.selectedItemID
        local needle   = search ~= "" and search or nil
        local out = {}

        if mode == "recent" then
            -- Recent mode sidebar = persisted edit-session history. Raw session rows;
            -- time labels formatted at paint (time() is impure, can't live in a selector).
            local sessions = HDG.Selectors:Call("companion.recentSessions", state, {})
            for i, s in ipairs(sessions) do
                out[#out + 1] = {
                    id              = s.id,
                    isRecentSession = true,
                    startedAt       = s.startedAt,
                    endedAt         = s.endedAt,
                    eventCount      = s.eventCount,
                    isActive        = s.isActive,
                    isSelected      = (selected == s.id) or (selected == nil and i == 1),
                }
            end
            return out
        end

        if mode == "rooms" then
            -- One row per persistent Furnishings room; count = effective decor
            -- total across its equipped sets + own pieces. Blueprint tile from
            -- the live room catalog (ShapeAtlas glyph pre-snapshot).
            local cat = state.session.house.roomCatalog.byShapeID
            for rid, room in pairs(state.account.rooms) do
                local name = (room.name and room.name ~= "" and room.name)
                    or (room.shape and HDG.Projects.ShapeAtlas.GetLabel(room.shape)) or "Room"
                if not needle or name:lower():find(needle, 1, true) then
                    local n = 0
                    for _, sid in ipairs(room.furnishingSetIDs) do
                        local set = state.account.furnishingSets[sid]
                        if set then   -- exception(nullable): set deleted out from under the room
                            for _, it in ipairs(set.items) do n = n + (it.count or 1) end
                        end
                    end
                    local e = room.shape and cat[room.shape]   -- exception(nullable): shapeless rooms have no tile
                    out[#out + 1] = {
                        id          = rid,
                        type        = "room",
                        displayName = name,
                        count       = n,
                        iconAtlas   = (e and e.iconAtlas)
                            or (room.shape and HDG.Projects.ShapeAtlas.GetAtlas(room.shape)) or nil,
                        isSelected  = selected == rid,
                    }
                end
            end
            table.sort(out, function(a, b)
                local an, bn = tostring(a.displayName):lower(), tostring(b.displayName):lower()
                if an ~= bn then return an < bn end
                return a.id < b.id
            end)
            return out
        end

        -- Collections for this mode, name-filtered. count available only for explicit
        -- membership defs (.items); rule-based concepts/collections leave count nil.
        local typeSet = MODE_TO_TYPES[mode] or {}
        local matches = {}
        for _, entry in ipairs(iterAllCollectionsForCompanion(state)) do
            if typeSet[entry.type] then
                local def  = entry.def
                local name = (def and (def.displayName or def.name)) or entry.id
                if not needle or tostring(name):lower():find(needle, 1, true) then
                    matches[#matches + 1] = {
                        id          = entry.id,
                        type        = entry.type,
                        tier        = def and def.tier,
                        displayName = name,
                        subtitle    = def and def.description or nil,
                        count       = (def and type(def.items) == "table") and #def.items or nil,
                        isSelected  = selected == entry.id,
                    }
                end
            end
        end

        if mode == "themes" then
            -- Grouped into Room Concepts / Themed / Faction sections.
            return _sectionByTier(matches)
        end

        local function _alpha(a, b)
            return tostring(a.displayName):lower() < tostring(b.displayName):lower()
        end

        if mode == "collections" then
            -- Special (resolver-based) collections pinned to the top in a fixed order,
            -- a divider, then the rest alphabetically.
            local specials, rest = {}, {}
            for _, m in ipairs(matches) do
                if SPECIAL_COLLECTION_ORDER[m.id] then specials[#specials + 1] = m
                else rest[#rest + 1] = m end
            end
            table.sort(specials, function(a, b)
                return SPECIAL_COLLECTION_ORDER[a.id] < SPECIAL_COLLECTION_ORDER[b.id]
            end)
            table.sort(rest, _alpha)
            for _, m in ipairs(specials) do out[#out + 1] = m end
            if #specials > 0 and #rest > 0 then
                out[#out + 1] = { isDivider = true, id = "specials" }
            end
            for _, m in ipairs(rest) do out[#out + 1] = m end

            -- Cost-bucket sub-section inside Collections. One catalog walk for all four owned counts.
            out[#out + 1] = { isHeader = true, displayName = "By Placement Cost" }
            local counts = _bucketCounts()
            for _, b in ipairs(PLACEMENT_COST_BUCKETS) do
                out[#out + 1] = {
                    id          = b.id,
                    type        = "placementcost",
                    displayName = b.text,
                    count       = counts[b.id],
                    isSelected  = selected == b.id,
                }
            end
            return out
        end

        table.sort(matches, _alpha)
        for _, m in ipairs(matches) do out[#out + 1] = m end
        return out
    end,
})

-- ============================================================================
-- Grid items for the selected collection (or session events for recent mode).
-- Collection resolution uses HDG.StyleResolve.ItemsFor (shared with Styles tab)
-- so rule-based collections populate too.
-- ============================================================================

-- Emit placement-ready grid cells for one catalog item: base (undyed) + one cell
-- per owned dyed variant. Each cell carries the placement payload (entryID,
-- ownedQty, allowIndoors/allowOutdoors, placementCost, isUniqueTrophy).
-- Dye split: row.quantity is aggregate across variants (12.0.5 catalog API);
-- base undyed = aggregate - sum(dyed numStored). row nil = boundary (catalog not swept).
local function _emitDecorCells(out, itemID, row, needle, ioFilter)
    -- Indoor/Outdoor filter (3-state): skip rows the current filter excludes.
    -- "indoor" keeps indoor-placeable items; "outdoor" keeps outdoor-placeable.
    if row then
        if ioFilter == "indoor"  and row.isAllowedIndoors  == false then return end
        if ioFilter == "outdoor" and row.isAllowedOutdoors == false then return end
    end
    local name = (row and row.name) or ("Item " .. tostring(itemID))
    if needle and not name:lower():find(needle, 1, true) then return end
    local iconTex, iconAtl = HDG.Format.CoerceIconPair(
        row and row.iconTexture, row and row.iconAtlas)
    if not row then
        out[#out + 1] = {
            itemID = itemID, name = name,
            iconTexture = iconTex, iconAtlas = iconAtl,
            isOwned = false, ownedQty = 0,
        }
        return
    end
    local dyed = row.dyedVariants or {}
    local dyedStored = 0
    for _, dv in ipairs(dyed) do dyedStored = dyedStored + (dv.numStored or 0) end
    local baseQty = #dyed > 0 and math.max(0, (row.quantity or 0) - dyedStored)  -- exception(boundary): catalog struct field sparse
                                or (row.quantity or 0)  -- exception(boundary): catalog struct field sparse
    out[#out + 1] = {
        itemID         = itemID,
        name           = #dyed > 0 and (name .. " (Undyed)") or name,
        iconTexture    = iconTex,
        iconAtlas      = iconAtl,
        isOwned        = row.isOwned == true,
        entryID        = row.entryID,
        ownedQty       = baseQty,
        numPlaced      = row.numPlaced,   -- aggregate placed (tooltip "Placed:"); per-variant not exposed
        allowIndoors   = row.isAllowedIndoors,
        allowOutdoors  = row.isAllowedOutdoors,
        placementCost  = row.placementCost,
        isUniqueTrophy = row.isUniqueTrophy == true,
    }
    for _, dv in ipairs(dyed) do
        out[#out + 1] = {
            itemID         = itemID,
            name           = name .. " (" .. (dv.label or "Dyed") .. ")",
            iconTexture    = iconTex,
            iconAtlas      = iconAtl,
            isOwned        = true,
            entryID        = dv.entryID,
            ownedQty       = dv.numStored or 0,
            allowIndoors   = row.isAllowedIndoors,
            allowOutdoors  = row.isAllowedOutdoors,
            placementCost  = row.placementCost,
            isUniqueTrophy = row.isUniqueTrophy == true,
        }
    end
end

-- Stamp the cost-badge toggle onto every grid cell so the factory paints badges
-- as a pure function of ed. gridItems reads session.ui.companion.showCost, so
-- COMPANION_TOGGLE_COST re-pushes the grid and badges flip.
local function _stampShowCost(out, showCost)
    for _, ed in ipairs(out) do ed.showCost = showCost end
    return out
end

-- Observer is primary source for name/icon/isOwned + placement payload.
-- Cost-bucket mode walks the whole catalog via IterateRows (tied to sweepGeneration).
Selectors:Register("companion.gridItems", {
    reads = {
        "session.ui.companion.mode",
        "session.ui.companion.selectedItemID",
        "session.ui.companion.search",
        "session.ui.companion.ioFilter",
        "session.ui.companion.showCost",    -- cell cost-badge gate (stamped per cell)
        "account.recentActivity",
        "account.collections",
        "account.rooms",                    -- rooms-mode grid: the selected room
        "account.furnishingSets",           -- rooms-mode grid: its effective furnishings
        "session.styles.cacheTick",
        "session.staticData.tick",          -- StyleResolve reads pre-authored defs
        "session.catalog.sweepGeneration",
    },
    fn = function(state)
        local mode     = state.session.ui.companion.mode
        local search   = state.session.ui.companion.search:lower()
        local needle   = search ~= "" and search or nil
        local ioFilter = state.session.ui.companion.ioFilter
        local showCost = state.session.ui.companion.showCost

        local out = {}

        if mode == "recent" then
            -- Per-item placed/removed event groups of the selected session
            -- (selectedItemID = sessionID; defaults to newest). Cells carry
            -- the placement payload so recent items can be re-placed on click.
            local ra    = state.account.recentActivity
            local house = ra.lastHouseKey and ra.houses[ra.lastHouseKey]
            if not house then return out end
            local sid = state.session.ui.companion.selectedItemID
            if type(sid) ~= "number" or not house.sessions[sid] then
                sid = house.sessionOrder[1]
            end
            local session = sid and house.sessions[sid]
            if not session then return out end

            local groups = {}
            for _, ev in pairs(session.events) do groups[#groups + 1] = ev end
            table.sort(groups, function(a, b) return (a.lastTs or 0) > (b.lastTs or 0) end)

            for _, ev in ipairs(groups) do
                local row  = HDG.HousingCatalogObserver:GetRow(ev.itemID)
                local name = (row and row.name) or ("Item " .. tostring(ev.itemID))
                if not needle or name:lower():find(needle, 1, true) then
                    local iconTex, iconAtl = HDG.Format.CoerceIconPair(
                        row and row.iconTexture, row and row.iconAtlas)
                    out[#out + 1] = {
                        itemID         = ev.itemID,
                        name           = name,
                        iconTexture    = iconTex,
                        iconAtlas      = iconAtl,
                        isOwned        = row and row.isOwned == true,
                        placedCount    = ev.placed,
                        removedCount   = ev.removed,
                        -- exception(boundary): row nil for unswept items -> entryID nil -> click no-ops
                        entryID        = row and row.entryID,
                        ownedQty       = row and row.quantity,
                        numPlaced      = row and row.numPlaced,
                        allowIndoors   = row and row.isAllowedIndoors,
                        allowOutdoors  = row and row.isAllowedOutdoors,
                        placementCost  = row and row.placementCost,
                        isUniqueTrophy = row and row.isUniqueTrophy == true,
                    }
                end
            end
            return _stampShowCost(out, showCost)
        end

        if mode == "rooms" then
            -- Selected room's EFFECTIVE furnishings (equipped sets + own
            -- pieces) as placement cards -- place straight from your plan.
            local room = state.account.rooms[state.session.ui.companion.selectedItemID or ""]   -- exception(nullable): nothing selected yet
            if room then
                local seen = {}
                for _, sid in ipairs(room.furnishingSetIDs) do
                    local set = state.account.furnishingSets[sid]
                    if set then   -- exception(nullable): set deleted out from under the room
                        for _, it in ipairs(set.items) do
                            if not seen[it.id] then
                                seen[it.id] = true
                                local row = HDG.HousingCatalogObserver:GetRow(it.id)
                                _emitDecorCells(out, it.id, row, needle, ioFilter)
                            end
                        end
                    end
                end
            end
            return _stampShowCost(out, showCost)
        end

        -- Cost bucket: walk the catalog for owned decor in [lo,hi].
        -- IterateRows reads the observer's baked cache (freshness via sweepGeneration).
        -- Checked before collection resolution since a bucket id resolves to no collection.
        local bucket = PLACEMENT_COST_BUCKET_BY_ID[
            state.session.ui.companion.selectedItemID]
        if bucket then
            HDG.HousingCatalogObserver:IterateRows(function(itemID, row)
                local cost = row.placementCost or 0  -- exception(boundary): catalog struct field sparse
                if cost >= bucket.lo and cost <= bucket.hi
                   and HDG.HousingCatalogObserver:IsOwned(row) then
                    _emitDecorCells(out, itemID, row, needle, ioFilter)
                end
            end)
            table.sort(out, function(a, b)
                return tostring(a.name):lower() < tostring(b.name):lower()
            end)
            return _stampShowCost(out, showCost)
        end

        -- Membership/rule-based modes: resolved through StyleResolve.ItemsFor so
        -- smartsets, concepts, and name-pattern Useful Collections all populate.
        local itemIDs = HDG.StyleResolve.ItemsFor(
            state.session.ui.companion.selectedItemID, state)
        for _, itemID in ipairs(itemIDs) do
            local row = HDG.HousingCatalogObserver:GetRow(itemID)
            _emitDecorCells(out, itemID, row, needle, ioFilter)
        end
        return _stampShowCost(out, showCost)
    end,
})

-- ============================================================================
-- Bottom strip: most-recently-placed items, newest first (all modes).
-- Horizontal filmstrip, capped at 20. Cells are re-placeable (observer-keyed).
-- ============================================================================
Selectors:Register("companion.recentStrip", {
    reads = {
        "session.styles.placedDecor",
        "session.styles.cacheTick",
        "session.catalog.sweepGeneration",
        "session.ui.companion.showCost",   -- re-placeable cells -> cost badge respects the toggle
        "account.recentActivity",          -- this-session placed/removed -> +/- corner badges
    },
    fn = function(state)
        -- Per-ACTION feed: 1 card = 1 place/remove action, newest first, one direction only.
        -- Built from session.actions (NOT the per-item events aggregate which conflates
        -- place+remove into a single cell). Cells are re-placeable via catalog entryID.
        local ra      = state.account.recentActivity   -- factory-seeded: strict read
        local house   = ra.lastHouseKey and ra.houses[ra.lastHouseKey]
        local sess    = house and house.sessionOrder[1] and house.sessions[house.sessionOrder[1]]
        local actions = (sess and sess.actions) or {}   -- exception(boundary): pre-existing sessions lack actions

        local out = {}
        for i = 1, math.min(20, #actions) do
            local a   = actions[i]   -- { itemID, kind, ts }, newest first
            local row = HDG.HousingCatalogObserver:GetRow(a.itemID)
            local name = (row and row.name) or ("Item " .. tostring(a.itemID))
            local iconTex, iconAtl = HDG.Format.CoerceIconPair(
                row and row.iconTexture, row and row.iconAtlas)
            out[i] = {
                itemID         = a.itemID,
                name           = name,
                iconTexture    = iconTex,
                iconAtlas      = iconAtl,
                isActionStrip  = true,   -- per-action feed: hide qty badge, +/- direction only
                -- exception(boundary): row nil for unswept items -> entryID nil -> click no-ops
                isOwned        = row and row.isOwned == true,
                entryID        = row and row.entryID,
                ownedQty       = row and row.quantity,
                numPlaced      = row and row.numPlaced,
                -- ONE direction per action (+/- corner icon), not a count.
                placedCount    = (a.kind == "placed")  and 1 or 0,
                removedCount   = (a.kind == "removed") and 1 or 0,
                allowIndoors   = row and row.isAllowedIndoors,
                allowOutdoors  = row and row.isAllowedOutdoors,
                placementCost  = row and row.placementCost,
                isUniqueTrophy = row and row.isUniqueTrophy == true,
            }
        end
        return _stampShowCost(out, state.session.ui.companion.showCost)
    end,
})

-- ============================================================================
-- Recent mode sidebar: edit-session history for the active house, newest first.
-- Returns raw session data; time labels formatted by the module (time() is impure).
-- ============================================================================

Selectors:Register("companion.recentSessions", {
    reads = { "account.recentActivity" },
    fn = function(state)
        local ra    = state.account.recentActivity
        local house = ra.lastHouseKey and ra.houses[ra.lastHouseKey]
        if not house then return {} end
        local newestID = house.sessionOrder[1]
        local out = {}
        for _, sid in ipairs(house.sessionOrder) do
            local s = house.sessions[sid]
            if s then
                out[#out + 1] = {
                    id         = sid,
                    startedAt  = s.startedAt,
                    endedAt    = s.endedAt,
                    eventCount = s.eventCount or 0,
                    isActive   = (sid == newestID) and not s.endedAt,
                }
            end
        end
        return out
    end,
})

-- ============================================================================
-- Header label per mode (for the companion window title bar).
-- ============================================================================

local MODE_LABELS = {
    styles       = "Your Styles",
    rooms        = "My Rooms",
    snapshots    = "Snapshots",
    themes       = "Room Concepts",
    collections  = "Useful Collections",
    recent       = "Recent Placements",
}

Selectors:Register("companion.headerLabel", {
    reads = {"session.ui.companion.mode"},
    fn = function(state)
        return MODE_LABELS[state.session.ui.companion.mode]
    end,
})
