-- HDGR_Selectors_Blueprints.lua
-- ============================================================================
-- Pure selectors for the Blueprints tab (12.1). This file loads on ALL builds:
-- NAV_TREE's `gatedBy = "blueprints.available"` is evaluated on live too, so
-- the gate selector must exist there. The 12.1-only RUNTIME files (observer,
-- LayoutConfig, controller) are file-top gated on IS_121 instead.

local Selectors = HDG.Selectors

-- Capability gate: true only on a 12.1 client. NAV_TREE omits the Blueprints
-- child when false (same mechanism as the Debug leaf's config.debug gate).
Selectors:Register("blueprints.available", {
    reads = {},  -- constant per session; IS_121 is stamped at file load
    fn = function() return HDG.Constants.IS_121 end,
})

local CT_LABEL = { [1] = "House", [2] = "Room", [3] = "Decor", [4] = "Dye", [5] = "Fixture" }

-- Per-entry acquisition resolve. Plain local helper -- Selectors:Call passes
-- NO extra args, so per-item lookups never route through the registry. Catalog
-- access is the sanctioned live-facade pattern (ADR-003a); reactivity comes
-- from the session.resolvers.catalog.tick read on the registered selector.
-- Returns: itemID?, srcKind? (SOURCE_KINDS key for Format.SourceChip), srcName?
local function _resolveAcq(entry)
    if entry.contentType == 1 or entry.contentType == 2 or entry.contentType == 5 then
        return nil, nil, nil                                 -- structural: house/room/fixture, no chip in v1
    end
    local row
    if entry.contentType == 4 then
        -- Dye recordIDs ARE item IDs (verified in-game 68629); the itemID is
        -- what shopping routing needs even when the catalog has no dye row.
        row = HDG.HousingCatalogObserver:GetRow(entry.recordID)  -- exception(nullable): dyes may not be catalog rows
        if not row then return entry.recordID, nil, nil end
    else
        row = HDG.HousingCatalogObserver.byDecorID[entry.recordID]  -- exception(nullable): catalog lookup can miss
        if not row then return nil, nil, nil end             -- resolves at vendor at runtime
    end
    local kind = HDG.Constants.SOURCE_KIND_BY_DONOR[row.sourceType]  -- exception(nullable): source may be unbaked
    return row.itemID, kind and kind.key or nil, row.sourceName
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
            for _, e in ipairs(g.entries) do
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
