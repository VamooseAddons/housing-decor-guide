-- HDG.Projects selectors
-- ============================================================================
-- Pure read layer over account.projects + account.collections (crates) +
-- session.house (live budget/floor) + session.ui.projects (nav).
-- reads declared; test_selector_reads enforces accuracy by execution.

HDG = HDG or {}
local Selectors = HDG.Selectors

-- ===== Active-version resolution ============================================
-- Rooms live under versions[versionID].rooms. Active version = most-recently-captured
-- house's activeVersionID. Returns nil pre-capture (selectors fall back to empty rooms).
local function _activeVersionContext(state)
    local houses = state.account.projects.houses
    -- The Architect shows the FOCUSED house (highest focusSeq, set by the house
    -- switcher). Ties fall back to most-recently-captured, then the lexicographically
    -- greatest houseID (pairs() order is non-deterministic; memo correctness requires
    -- a stable pick). focusSeq + lastCapturedAt both live under account.projects.houses,
    -- so no new selector reads-path is introduced.
    local houseID, house, bestFocus, bestTS = nil, nil, -1, -1
    for id, h in pairs(houses) do
        local focus, ts = h.focusSeq or 0, h.lastCapturedAt or 0
        if focus > bestFocus
            or (focus == bestFocus and ts > bestTS)
            or (focus == bestFocus and ts == bestTS and houseID and id > houseID) then
            houseID, house, bestFocus, bestTS = id, h, focus, ts
        end
    end
    if not house then return nil end
    local vid     = house.activeVersionID
    local version = vid and state.account.projects.versions[vid]
    if not version then return nil end
    return houseID, vid, version
end

-- Active version's rooms map (or empty). Callers declare the two projects reads.
local function _activeRooms(state)
    local _, _, version = _activeVersionContext(state)
    return (version and version.rooms) or {}
end

-- A room's door cardinals, DERIVED (Phase 2 -- no stored doorCardinals): a stairwell's
-- one door faces its neighbour (FloorMap), everything else is the shape's door slots
-- rotated by the room's cell.rotation. The single source for "where can this connect".
local function _roomDoorCardinals(rooms, roomID)
    local A, room = HDG.Projects.ShapeAtlas, rooms[roomID]
    if not room then return {} end
    -- Single-door rooms (stairwell + garden): one door floats to the nearest neighbour
    -- (any cardinal), derived from the ground-floor connection.
    if room.shape == "staircase" or room.shape == "staircase_mirror" or A.IsCircle(room.shape) then
        return { HDG.Projects.FloorMap.FloatingDoorCardinal(rooms, roomID) }
    end
    local rot, out = (room.cell and room.cell.rotation) or 0, {}
    for _, card in ipairs(A.GetDoors(room.shape)) do
        out[#out + 1] = A.RotateCardinal(card, rot)
    end
    return out
end

-- Any room in the active version? Drives landing <-> architect view switch.
Selectors:Register("projects.hasRooms", {
    reads = { "account.projects.houses", "account.projects.versions" },
    fn = function(state)
        return next(_activeRooms(state)) ~= nil
    end,
})

-- Currently shown/edited versionID (controllers need it since roomID doesn't encode it).
Selectors:Register("projects.activeVersionID", {
    reads = { "account.projects.houses", "account.projects.versions" },
    fn = function(state)
        local _, vid = _activeVersionContext(state)
        return vid
    end,
})

-- All versions of the active house, Live first then what-ifs by createdAt.
-- { versionID, houseID, name, isActive, isCurrent }. Empty pre-capture.
Selectors:Register("projects.versionTabs", {
    reads = { "account.projects.houses", "account.projects.versions" },
    fn = function(state)
        local houseID = _activeVersionContext(state)
        if not houseID then return {} end
        local house, out = state.account.projects.houses[houseID], {}
        for vid, v in pairs(state.account.projects.versions) do
            if v.houseID == houseID then
                out[#out + 1] = {
                    versionID = vid, houseID = houseID, name = v.name or "?",
                    isActive  = (vid == house.activeVersionID),
                    isCurrent = (vid == house.currentVersionID),
                    createdAt = v.createdAt or 0,
                }
            end
        end
        table.sort(out, function(a, b)
            if a.isCurrent ~= b.isCurrent then return a.isCurrent end   -- Live first
            return a.createdAt < b.createdAt
        end)
        return out
    end,
})

-- The active version's label for the switcher button: "Version: Live" / "Version: What-if 1".
Selectors:Register("projects.activeVersionLabel", {
    reads = { "account.projects.houses", "account.projects.versions" },
    fn = function(state)
        local houseID, vid, version = _activeVersionContext(state)
        if not version then return "Version: -" end
        local isCurrent = (vid == state.account.projects.houses[houseID].currentVersionID)
        return "Version: " .. (version.name or "?") .. (isCurrent and " (Live)" or "")
    end,
})

-- House switcher (Architect breadcrumb dropdown). Sourced from ALL the player's
-- owned houses (session.house.ownedHouses) -- not just captured ones -- so both
-- show even before capture; the token is the same digest the capture mints, so
-- picking a captured house focuses it (uncaptured -> a focus stub + empty canvas).
Selectors:Register("projects.houseMenuItems", {
    reads = { "session.house.ownedHouses" },
    fn = function(state)
        local IDs, out = HDG.Projects.IDs, {}
        for _, h in pairs(state.session.house.ownedHouses) do
            if h.name and h.plotID then
                out[#out + 1] = {
                    value = IDs.makeHouseID(IDs.hashToken(h.name .. ":" .. tostring(h.plotID))),
                    text  = h.name,
                }
            end
        end
        table.sort(out, function(a, b)
            if a.text ~= b.text then return a.text < b.text end
            return a.value < b.value
        end)
        return out
    end,
})
-- The focused house token (the dropdown's current value). Picks the highest focusSeq
-- house directly -- works even for a versionless focus stub (unlike _activeVersionContext,
-- which needs a version), so the dropdown reflects the pick before capture.
Selectors:Register("projects.activeHouseID", {
    reads = { "account.projects.houses" },
    fn = function(state)
        local bestID, bestFocus, bestTS = nil, -1, -1
        for id, h in pairs(state.account.projects.houses) do
            local focus, ts = h.focusSeq or 0, h.lastCapturedAt or 0
            if focus > bestFocus or (focus == bestFocus and ts > bestTS)
               or (focus == bestFocus and ts == bestTS and bestID and id > bestID) then
                bestID, bestFocus, bestTS = id, focus, ts
            end
        end
        return bestID
    end,
})

-- Mode: Stock = active version IS the live/current version (palette locked);
-- what-if = branched (design freely). Both false pre-capture.
-- `visible` bindings don't negate, hence two selectors.
Selectors:Register("projects.isWhatIfMode", {
    reads = { "account.projects.houses", "account.projects.versions" },
    fn = function(state)
        local houseID, vid, version = _activeVersionContext(state)
        return (version ~= nil) and (vid ~= state.account.projects.houses[houseID].currentVersionID)
    end,
})
Selectors:Register("projects.isStockMode", {
    reads = { "account.projects.houses", "account.projects.versions" },
    fn = function(state)
        local houseID, vid, version = _activeVersionContext(state)
        return (version ~= nil) and (vid == state.account.projects.houses[houseID].currentVersionID)
    end,
})

-- Canvas render layout for the selected floor: rooms in the active version, positioned
-- by explicit room.cell. One layout path (version IS the design; no plannedOnly/AutoLayout).
Selectors:Register("projects.planLayout", {
    memoized = true,
    reads = { "account.projects.houses", "account.projects.versions", "session.ui.projects.selectedFloor" },
    fn = function(state)
        local IDs, A = HDG.Projects.IDs, HDG.Projects.ShapeAtlas
        local floor = state.session.ui.projects.selectedFloor
        local layout, meta = {}, {}
        for roomID, room in pairs(_activeRooms(state)) do
            local parsed = IDs.parsePath(roomID)
            if parsed and parsed.floor == floor then
                local rot, cells = room.cell.rotation or 0, A.GetCells(room.shape)
                local rc = A.RotateCells(cells, rot)
                layout[roomID] = {
                    cell = { x = room.cell.x, y = room.cell.y },
                    w = rc[1], d = rc[2], rotation = rot,
                    mask = A.RotateMask(A.GetMask(room.shape), rot, cells[1], cells[2]),
                }
                meta[roomID] = { shape = room.shape, name = room.name }
            end
        end
        return { layout = layout, rooms = meta, connections = {} }
    end,
})

-- Placeable-shape palette: every shape except Entry (anchor room; captured, never placed).
-- Merges live stock from room catalog snapshot. Geometry stays ShapeAtlas; catalog supplies ownership.
Selectors:Register("projects.paletteShapes", {
    reads = { "session.house.roomCatalog" },
    fn = function(state)
        local A, out = HDG.Projects.ShapeAtlas, {}
        local cat = state.session.house.roomCatalog.byShapeID
        for _, shape in ipairs(A.ListShapes()) do
            if shape ~= "entry" then
                local e = cat[shape]
                out[#out + 1] = {
                    shape = shape, label = A.GetLabel(shape),
                    budget = A.GetBudget(shape), atlas = A.GetAtlas(shape),
                    owned = (e and e.owned) or false,
                    numStored = (e and e.numStored) or 0,
                    numPlaced = (e and e.numPlaced) or 0,
                }
            end
        end
        return out
    end,
})

-- Live room catalog: snapshotted by the observer on HOUSING_STORAGE_UPDATED.
-- Pure read of state slot (Inv 1: catalog API never runs in a selector).
Selectors:Register("projects.roomCatalog", {
    reads = { "session.house.roomCatalog" },
    fn = function(state) return state.session.house.roomCatalog.entries end,
})

-- Plan validation: no footprint overlap AND within room budget (roomMax 0 = skip).
Selectors:Register("projects.planValidation", {
    reads = { "account.projects.houses", "account.projects.versions",
              "session.ui.projects.selectedFloor" },
    calls = { "projects.placementCaps" },
    fn = function(state, ctx)
        local IDs, A = HDG.Projects.IDs, HDG.Projects.ShapeAtlas
        local floor = state.session.ui.projects.selectedFloor
        local occ, collide, cost, count = {}, false, 0, 0
        for rid, room in pairs(_activeRooms(state)) do
            local p = IDs.parsePath(rid)
            if p and p.floor == floor then
                count, cost = count + 1, cost + A.GetBudget(room.shape)
                local rot, cells = room.cell.rotation or 0, A.GetCells(room.shape)
                for _, m in ipairs(A.RotateMask(A.GetMask(room.shape), rot, cells[1], cells[2])) do
                    local k = (room.cell.x + m[1]) .. "," .. (room.cell.y + m[2])
                    if occ[k] then collide = true else occ[k] = true end
                end
            end
        end
        local roomMax    = Selectors:Call("projects.placementCaps", state, ctx).roomMax
        local overBudget = (roomMax > 0) and (cost > roomMax)
        return { collide = collide, overBudget = overBudget, roomCount = count,
                 roomCost = cost, roomMax = roomMax, hardOK = (not collide) and (not overBudget) }
    end,
})
Selectors:Register("projects.planValidationSummary", {
    calls = { "projects.planValidation" },
    fn = function(state, ctx)
        local v = Selectors:Call("projects.planValidation", state, ctx)
        if v.roomCount == 0 then return "Plan empty - click a shape to add a room" end
        local issues = {}
        if v.collide    then issues[#issues + 1] = "rooms overlap" end
        if v.overBudget then issues[#issues + 1] = "over room budget" end
        if #issues == 0 then
            return string.format("Valid - %d rooms, cost %d/%d", v.roomCount, v.roomCost, v.roomMax)
        end
        return "Fix: " .. table.concat(issues, ", ")
    end,
})

-- Room shopping list: active version vs current (reality) version, tallied by shape.
-- delta > 0 = design wants more (build); < 0 = reality has extra (remove).
-- Active == current -> empty diff. Pure; no live API.
Selectors:Register("projects.planDiff", {
    memoized = true,  -- O(rooms) double-walk; shoppingListRows + planDiffSummary bottom out here.
    reads = { "account.projects.houses", "account.projects.versions", "session.ui.projects.selectedFloor" },
    fn = function(state)
        local IDs, floor = HDG.Projects.IDs, state.session.ui.projects.selectedFloor
        local houseID, _, version = _activeVersionContext(state)
        if not version then return { rows = {}, added = 0, missing = 0 } end
        local house      = state.account.projects.houses[houseID]
        local curVersion = house.currentVersionID and state.account.projects.versions[house.currentVersionID]
        local plan, cap = {}, {}
        for rid, room in pairs(version.rooms) do
            local p = IDs.parsePath(rid)
            if p and p.floor == floor then plan[room.shape] = (plan[room.shape] or 0) + 1 end
        end
        for rid, room in pairs(curVersion and curVersion.rooms or {}) do
            local p = IDs.parsePath(rid)
            if p and p.floor == floor then cap[room.shape] = (cap[room.shape] or 0) + 1 end
        end
        local shapes = {}
        for sh in pairs(plan) do shapes[sh] = true end
        for sh in pairs(cap)  do shapes[sh] = true end
        local rows, added, missing = {}, 0, 0
        for sh in pairs(shapes) do
            local delta = (plan[sh] or 0) - (cap[sh] or 0)
            if delta ~= 0 then
                rows[#rows + 1] = { shape = sh, label = HDG.Projects.ShapeAtlas.GetLabel(sh), delta = delta }
                if delta > 0 then added = added + delta else missing = missing - delta end
            end
        end
        table.sort(rows, function(a, b) return a.label < b.label end)
        return { rows = rows, added = added, missing = missing }
    end,
})
Selectors:Register("projects.planDiffSummary", {
    calls = { "projects.planDiff" },
    fn = function(state, ctx)
        local d = Selectors:Call("projects.planDiff", state, ctx)
        if d.added == 0 and d.missing == 0 then return "vs house: plan matches" end
        local parts = {}
        if d.added   > 0 then parts[#parts + 1] = "+" .. d.added .. " to build" end
        if d.missing > 0 then parts[#parts + 1] = "-" .. d.missing .. " to remove" end
        return "vs house: " .. table.concat(parts, ", ")
    end,
})

-- Room shopping list: BUILD rows (design wants more) first, then REMOVE rows.
-- Empty in Stock mode (active == current version).
Selectors:Register("projects.shoppingListRows", {
    calls = { "projects.planDiff" },
    fn = function(state, ctx)
        local d, A, rows = Selectors:Call("projects.planDiff", state, ctx), HDG.Projects.ShapeAtlas, {}
        for _, r in ipairs(d.rows) do
            if r.delta > 0 then
                rows[#rows + 1] = { kind = "build", shape = r.shape, label = r.label, count = r.delta, weight = r.delta * A.GetBudget(r.shape) }
            end
        end
        for _, r in ipairs(d.rows) do
            if r.delta < 0 then
                rows[#rows + 1] = { kind = "remove", shape = r.shape, label = r.label, count = -r.delta, weight = (-r.delta) * A.GetBudget(r.shape) }
            end
        end
        return rows
    end,
})
Selectors:Register("projects.hasShoppingList", {
    calls = { "projects.shoppingListRows" },
    fn = function(state, ctx) return #Selectors:Call("projects.shoppingListRows", state, ctx) > 0 end,
})

-- Crates for the selected room + orphan holding-bay (demolished rooms with parent cleared).
Selectors:Register("projects.crateRows", {
    memoized = true,
    reads = { "account.collections", "account.projects.houses", "account.projects.versions",
              "session.ui.projects.selectedRoomID" },
    fn = function(state)
        local roomID = state.session.ui.projects.selectedRoomID
        local _, vid = _activeVersionContext(state)
        local crates, orphans = {}, {}
        for id, coll in pairs(state.account.collections) do
            if coll.type == "crate" then
                if roomID and vid and coll.versionID == vid and coll.parent == roomID then
                    crates[#crates + 1] = { id = id, name = coll.name, decor = coll.decor }
                elseif coll.parent == nil then
                    orphans[#orphans + 1] = { id = id, name = coll.name, lastKnownShape = coll.lastKnownShape }
                end
            end
        end
        return { crates = crates, orphans = orphans }
    end,
})


-- placementCaps: room + decor budgets from level-reward records (NOT the live API).
-- WHY: C_HousingLayout.GetRoomPlacementBudget returns engine defaults until Edit Layout
-- opens; max-level houses never open it -> reads 9 forever. The reward record always
-- carries the true cap. Rooms = valueType 2, InteriorDecor = valueType 0.
-- { roomMax, decorMax } = 0 until rewards async-land; consumers treat 0 as "no cap".
local _E_RT = _G.Enum and _G.Enum.HouseLevelRewardType        -- exception(boundary): absent in headless harness
local _E_VT = _G.Enum and _G.Enum.HouseLevelRewardValueType
local REWARD_VALUE   = (_E_RT and _E_RT.Value)         or 0
local VTYPE_ROOMS    = (_E_VT and _E_VT.Rooms)         or 2
local VTYPE_INTERIOR = (_E_VT and _E_VT.InteriorDecor) or 0
Selectors:Register("projects.placementCaps", {
    reads = { "session.house.snapshot", "session.house.snapshotTick" },
    fn = function(state)
        local nr = state.session.house.snapshot.nextRewards
        local roomMax, decorMax = 0, 0
        if nr and nr.rewards then
            for _, r in ipairs(nr.rewards) do
                if r.type == REWARD_VALUE then
                    local v = (nr.atMax and r.newValue or r.oldValue) or 0  -- exception(boundary): reward fields optional in schema
                    if     r.valueType == VTYPE_ROOMS    then roomMax  = v
                    elseif r.valueType == VTYPE_INTERIOR then decorMax = v end
                end
            end
        end
        return { roomMax = roomMax, decorMax = decorMax }
    end,
})

-- Room placement budget: planned room weight vs roomMax cap (reward-derived).
-- Whole-house (NOT per-floor like planValidation). over/overBy drive amber "+N over".
Selectors:Register("projects.roomBudget", {
    reads = { "account.projects.houses", "account.projects.versions" },
    calls = { "projects.placementCaps" },
    fn = function(state, ctx)
        local A, cost = HDG.Projects.ShapeAtlas, 0
        for _, room in pairs(_activeRooms(state)) do
            -- One record per room (a multi-floor room's span is derived, not extra records).
            cost = cost + A.GetBudget(room.shape)
        end
        local max = Selectors:Call("projects.placementCaps", state, ctx).roomMax
        return { cost = cost, max = max, over = (max > 0 and cost > max), overBy = math.max(0, cost - max) }
    end,
})
-- "rooms 59 / 95" with amber "+N over" when over cap (what-if never hard-blocks).
-- ColorCode is a deterministic palette lookup (pure; ADR-022).
Selectors:Register("projects.roomBudgetText", {
    calls = { "projects.roomBudget" },
    fn = function(state, ctx)
        local b = Selectors:Call("projects.roomBudget", state, ctx)
        if b.max <= 0 then return "" end
        -- house-room-limit-icon (Blizzard atlas) prefixes the count as the visual label.
        local txt = "|A:house-room-limit-icon:16:16|a " .. string.format("%d / %d", b.cost, b.max)
        if b.over then
            txt = txt .. "  " .. HDG.Theme:ColorCode("semantic.warning") .. "+" .. b.overBy .. " over|r"
        end
        return txt
    end,
})
-- Room budget as 0-1 fraction for the progressbar (clamped at 1; amber text carries overflow).
Selectors:Register("projects.roomBudgetProgress", {
    calls = { "projects.roomBudget" },
    fn = function(state, ctx)
        local b = Selectors:Call("projects.roomBudget", state, ctx)
        if b.max <= 0 then return 0 end
        local p = b.cost / b.max
        return (p > 1) and 1 or p
    end,
})

-- Architect columns: picker + canvas always; detail column appears when a room is selected
-- (window widens in-place; visible=sidePanelOpen collapses the track when nothing selected).
Selectors:Register("projects.architectColumns", {
    reads = { "session.ui.projects.selectedRoomID" },
    fn = function(state)
        if state.session.ui.projects.selectedRoomID then
            return { 170, 620, 290 }
        end
        return { 170, 620 }
    end,
})

-- Floor tab list: 1..max(live numFloors, version.numFloors, highest room floor).
-- What-if: version.numFloors is the user-controlled count (1..3 cap).
Selectors:Register("projects.floorTabs", {
    reads = { "account.projects.houses", "account.projects.versions", "session.house.numFloors",
              "session.ui.projects.selectedFloor" },
    fn = function(state)
        local IDs = HDG.Projects.IDs
        local _, _, version = _activeVersionContext(state)
        local maxFloor = state.session.house.numFloors
        if version and version.numFloors and version.numFloors > maxFloor then
            maxFloor = version.numFloors
        end
        for roomID in pairs(_activeRooms(state)) do
            local parsed = IDs.parsePath(roomID)
            if parsed and parsed.floor and parsed.floor > maxFloor then maxFloor = parsed.floor end
        end
        local active = state.session.ui.projects.selectedFloor
        local tabs = {}
        for f = 1, maxFloor do tabs[#tabs + 1] = { floor = f, isActive = (f == active) } end
        return tabs
    end,
})

-- What-if floor controls: + Floor (whatIf + count < 3) / - Floor (whatIf + count > 1).
local function _whatIfFloorCount(state)
    local _, _, version = _activeVersionContext(state)
    if not version then return 0 end
    if version.numFloors then return version.numFloors end
    local IDs, maxFloor = HDG.Projects.IDs, 1
    for roomID in pairs(_activeRooms(state)) do
        local parsed = IDs.parsePath(roomID)
        if parsed and parsed.floor and parsed.floor > maxFloor then maxFloor = parsed.floor end
    end
    return maxFloor
end
Selectors:Register("projects.canAddWhatIfFloor", {
    reads = { "account.projects.houses", "account.projects.versions" },
    calls = { "projects.isWhatIfMode" },
    fn = function(state, ctx)
        if not Selectors:Call("projects.isWhatIfMode", state, ctx) then return false end
        return _whatIfFloorCount(state) < 3
    end,
})
Selectors:Register("projects.canRemoveWhatIfFloor", {
    reads = { "account.projects.houses", "account.projects.versions" },
    calls = { "projects.isWhatIfMode" },
    fn = function(state, ctx)
        if not Selectors:Call("projects.isWhatIfMode", state, ctx) then return false end
        return _whatIfFloorCount(state) > 1
    end,
})

-- ============================================================================
-- Render layer: canvas model, room detail, breadcrumb, remap, landing.
-- All pure; live API + relative-time formatting at the controller/view boundary.
-- ============================================================================

-- Display label: room name + "<floor>-<captureIndex>" tag ("Hallway 1-2").
-- Distinguishes duplicate shapes across floors.
local function _withRoomNumber(base, room, floor)
    if room.captureIndex and floor then return base .. " " .. floor .. "-" .. room.captureIndex end
    if room.captureIndex then return base .. " " .. room.captureIndex end
    return base
end

-- FULL label (detail panel / breadcrumb / room lists).
local function _roomLabel(room, floor)
    if not room then return "?" end
    return _withRoomNumber(room.name or HDG.Projects.ShapeAtlas.GetLabel(room.shape), room, floor)
end

-- SHORT label (CANVAS only): shape name only ("Square M", "T-Shape").
local function _roomLabelShort(room)
    if not room then return "?" end
    return HDG.Projects.ShapeAtlas.GetLabel(room.shape)
end

-- roomID -> "in-progress" for rooms with crates holding decor (scoped to vid).
-- Rooms absent from the map read as "unconfigured".
local function _roomStatusMap(collections, vid)
    local out = {}
    for _, coll in pairs(collections) do
        if coll.type == "crate" and coll.versionID == vid and coll.parent
           and coll.decor and #coll.decor > 0 then
            out[coll.parent] = "in-progress"
        end
    end
    return out
end

local function _extend(bb, x, y)
    if bb.minX == nil or x < bb.minX then bb.minX = x end
    if bb.maxX == nil or x > bb.maxX then bb.maxX = x end
    if bb.minY == nil or y < bb.minY then bb.minY = y end
    if bb.maxY == nil or y > bb.maxY then bb.maxY = y end
end

-- Extend a bbox accumulator by a room's whole footprint (origin + far corner).
local function _extendFootprint(bb, x, y, w, d)
    _extend(bb, x, y)
    _extend(bb, x + w - 1, y + d - 1)
end

-- Door midpoint in CELL-BOUNDARY coords: center of the shape's outer edge facing `card`,
-- read from the (rotated) mask so non-convex shapes land on the real footprint edge
-- (not the bounding-box side midpoint). Two opposite-facing doors sharing a midpoint = connected.
local function _doorMid(card, x, y, w, d, mask)
    if not mask or #mask == 0 then
        if card == "N" then return x + w / 2, y end
        if card == "S" then return x + w / 2, y + d end
        if card == "E" then return x + w, y + d / 2 end
        return x, y + d / 2   -- W
    end
    local vertical = (card == "E" or card == "W")   -- door on a vertical (E/W) edge?
    local outward  = (card == "E" or card == "S")   -- extreme is a MAX (else MIN)?
    local rank
    for _, c in ipairs(mask) do
        local v = vertical and c[1] or c[2]
        if rank == nil then rank = v
        elseif outward then if v > rank then rank = v end
        else if v < rank then rank = v end end
    end
    local lo, hi   -- span of the cells sitting on that extreme edge
    for _, c in ipairs(mask) do
        if (vertical and c[1] == rank) or (not vertical and c[2] == rank) then
            local s = vertical and c[2] or c[1]
            lo = (lo == nil) and s or math.min(lo, s)
            hi = (hi == nil) and (s + 1) or math.max(hi, s + 1)
        end
    end
    local mid = (lo + hi) / 2
    if card == "N" then return x + mid,      y + rank end
    if card == "S" then return x + mid,      y + rank + 1 end
    if card == "E" then return x + rank + 1, y + mid end
    return x + rank, y + mid   -- W
end

-- Floor below the selected one -> dimmed backdrop tiles. Extends bbox for auto-fit.
-- Same active-version rooms, one floor down (cells are explicit).
local function _lowerFloorBackdrop(state, selectedFloor, bb)
    if selectedFloor <= 1 then return {} end
    local IDs, A = HDG.Projects.IDs, HDG.Projects.ShapeAtlas
    local below, out = selectedFloor - 1, {}
    for rid, r in pairs(_activeRooms(state)) do
        local p = IDs.parsePath(rid)
        if p and p.floor == below then
            local rot, cells = r.cell.rotation or 0, A.GetCells(r.shape)
            local rc = A.RotateCells(cells, rot)
            out[#out + 1] = { shape = r.shape, x = r.cell.x, y = r.cell.y,
                              w = rc[1], d = rc[2], rotation = rot,
                              atlas = A.GetAtlas(r.shape), circle = A.IsCircle(r.shape) }
            _extendFootprint(bb, r.cell.x, r.cell.y, rc[1], rc[2])
        end
    end
    return out
end

-- Canvas render model: rooms (cell + selection + status), door orbs, lower-floor backdrop,
-- and bbox for auto-fit tiling. One layout path (active version IS the design).
Selectors:Register("projects.canvasModel", {
    memoized = true,
    reads = { "account.projects.houses", "account.projects.versions",
              "account.collections", "session.ui.projects.selectedFloor",
              "session.ui.projects.selectedRoomID" },
    calls = { "projects.planLayout" },
    fn = function(state, ctx)
        local nav          = state.session.ui.projects
        local cur          = Selectors:Call("projects.planLayout", state, ctx)
        local _, vid       = _activeVersionContext(state)
        local roomsByID    = _activeRooms(state)
        local statusMap    = _roomStatusMap(state.account.collections, vid)
        local rooms, orbs = {}, {}
        local bb = { minX = nil, maxX = nil, minY = nil, maxY = nil }
        local A = HDG.Projects.ShapeAtlas
        for roomID, placed in pairs(cur.layout) do
            local meta, cell = cur.rooms[roomID] or {}, placed.cell
            local room = roomsByID[roomID]
            local canon = A.GetCells(meta.shape)
            rooms[#rooms + 1] = {
                roomID = roomID, shape = meta.shape, name = _roomLabelShort(room),
                x = cell.x, y = cell.y, w = placed.w, d = placed.d, rotation = placed.rotation or 0,
                canonW = canon[1], canonD = canon[2],   -- unrotated footprint -> icon rotates without stretch
                atlas = A.GetAtlas(meta.shape), circle = A.IsCircle(meta.shape),
                isSelected = (roomID == nav.selectedRoomID),
                status = statusMap[roomID] or "unconfigured",
            }
            _extendFootprint(bb, cell.x, cell.y, placed.w, placed.d)
            -- Door orbs from SHAPE door slots (not the captured "occupied" subset);
            -- every door can connect in a manual layout. (Real rooms only -- projected
            -- upper-floor ghosts are added later without orbs.)
            do
                local rmask = A.RotateMask(A.GetMask(meta.shape), placed.rotation or 0, canon[1], canon[2])
                if meta.shape == "staircase" or meta.shape == "staircase_mirror" or A.IsCircle(meta.shape) then
                    -- Single-door room (stairwell / garden): one door floating to the
                    -- CLOSEST ground-floor neighbour on any cardinal. World-space (no
                    -- RotateCardinal); stairwells render this SAME door on every floor.
                    local card   = HDG.Projects.FloorMap.FloatingDoorCardinal(roomsByID, roomID)
                    local mx, my = _doorMid(card, cell.x, cell.y, placed.w, placed.d, rmask)
                    orbs[#orbs + 1] = { roomID = roomID, cardinal = card, midX = mx, midY = my }
                else
                    for _, card in ipairs(A.GetDoors(meta.shape)) do
                        local rc = A.RotateCardinal(card, placed.rotation or 0)
                        local mx, my = _doorMid(rc, cell.x, cell.y, placed.w, placed.d, rmask)
                        orbs[#orbs + 1] = { roomID = roomID, cardinal = rc, midX = mx, midY = my }
                    end
                end
            end
        end
        -- Project multi-floor rooms (gardens / stairwells / tall) from lower floors as
        -- dimmed, non-interactive ghosts so their occupancy reads on the floors above.
        -- Gardens stay door-less (ground-only); STAIRWELLS inherit their ground-floor
        -- door on every floor, so the projected ghost gets the same world-cardinal orb
        -- (it connects to a room placed on that side upstairs). SSoT: same FloorMap.
        for _, pr in ipairs(HDG.Projects.FloorMap.ProjectedRooms(roomsByID, nav.selectedFloor)) do
            local canon = A.GetCells(pr.shape)
            local rot   = pr.cell.rotation or 0
            local rc    = A.RotateCells(canon, rot)
            rooms[#rooms + 1] = {
                roomID = "proj:" .. pr.roomID, shape = pr.shape, name = A.GetLabel(pr.shape),
                x = pr.cell.x, y = pr.cell.y, w = rc[1], d = rc[2], rotation = rot,
                canonW = canon[1], canonD = canon[2],
                atlas = A.GetAtlas(pr.shape), circle = A.IsCircle(pr.shape),
                isSelected = false, status = "unconfigured", projected = true,
            }
            _extendFootprint(bb, pr.cell.x, pr.cell.y, rc[1], rc[2])
            if pr.shape == "staircase" or pr.shape == "staircase_mirror" then
                -- Single floating door inherited from the ground-floor connection.
                local rmask  = A.RotateMask(A.GetMask(pr.shape), rot, canon[1], canon[2])
                local card   = HDG.Projects.FloorMap.FloatingDoorCardinal(roomsByID, pr.roomID)
                local mx, my = _doorMid(card, pr.cell.x, pr.cell.y, rc[1], rc[2], rmask)
                orbs[#orbs + 1] = { roomID = "proj:" .. pr.roomID, cardinal = card, midX = mx, midY = my }
            elseif not A.IsCircle(pr.shape) then
                -- Multi-door multi-floor room (tall_room "Stairwell Room (Empty)"):
                -- project ALL its doors on the upper floor so rooms can connect on any
                -- side there. (Gardens are circle -> skipped: their door is ground-only.)
                local rmask = A.RotateMask(A.GetMask(pr.shape), rot, canon[1], canon[2])
                for _, door in ipairs(A.GetDoors(pr.shape)) do
                    local rcard  = A.RotateCardinal(door, rot)
                    local mx, my = _doorMid(rcard, pr.cell.x, pr.cell.y, rc[1], rc[2], rmask)
                    orbs[#orbs + 1] = { roomID = "proj:" .. pr.roomID, cardinal = rcard, midX = mx, midY = my }
                end
            end
        end
        -- Connection by PLACEMENT: two opposite-facing doors at the same edge midpoint
        -- are placed against each other -> connected (glowing orb). Purely spatial.
        local doorMap, OPP = {}, { N = "S", S = "N", E = "W", W = "E" }
        for _, o in ipairs(orbs) do
            local k = o.midX .. "," .. o.midY
            doorMap[k] = doorMap[k] or {}
            doorMap[k][o.cardinal] = true
        end
        for _, o in ipairs(orbs) do
            o.connected = doorMap[o.midX .. "," .. o.midY][OPP[o.cardinal]] == true
        end

        local backdrop = _lowerFloorBackdrop(state, nav.selectedFloor, bb)
        local empty = (#rooms == 0)
        if empty then bb = { minX = 0, maxX = 0, minY = 0, maxY = 0 } end
        return {
            empty = empty, rooms = rooms, orbs = orbs, backdrop = backdrop,
            bbox = { minX = bb.minX, maxX = bb.maxX, minY = bb.minY, maxY = bb.maxY,
                     cols = (bb.maxX - bb.minX) + 1, rows = (bb.maxY - bb.minY) + 1 },
        }
    end,
})

-- Side panel open when a room is selected.
Selectors:Register("projects.sidePanelOpen", {
    reads = { "session.ui.projects.selectedRoomID" },
    fn = function(state)
        return state.session.ui.projects.selectedRoomID ~= nil
    end,
})

-- Selected room detail. Returns nil when nothing's selected (panel.visible gates render).
Selectors:Register("projects.roomDetail", {
    reads = { "account.projects.houses", "account.projects.versions", "session.ui.projects.selectedRoomID" },
    fn = function(state)
        local roomID = state.session.ui.projects.selectedRoomID
        if not roomID then return nil end
        local room = _activeRooms(state)[roomID]
        if not room then return nil end   -- exception(boundary): stale selection (room demolished)
        return {
            roomID = roomID, shape = room.shape, name = room.name,
            shapeLabel = HDG.Projects.ShapeAtlas.GetLabel(room.shape),
            doors      = _roomDoorCardinals(_activeRooms(state), roomID),   -- derived, not stored
            isBase     = room.isBase,
        }
    end,
})

-- Selected room's crate detail. Name + icon stamped INTO the row envelope (not at paint)
-- per ADR-003b: cold-cache resolve bumps itemNames.tick -> selector re-runs -> scrollbox
-- re-configures with real data. Resolving at paint breaks this cycle (the row data
-- wouldn't change on the tick, so cold rows stay on the fallback).
Selectors:Register("projects.crateDetail", {
    memoized = true,
    reads = { "account.collections", "account.projects.houses", "account.projects.versions",
              "session.ui.projects.selectedRoomID", "session.itemNames.tick" },
    fn = function(state)
        local roomID = state.session.ui.projects.selectedRoomID
        if not roomID then return { hasCrate = false } end
        local _, vid = _activeVersionContext(state)
        local crateID, coll
        for id, c in pairs(state.account.collections) do
            if c.type == "crate" and c.versionID == vid and c.parent == roomID then crateID, coll = id, c; break end
        end
        if not coll then return { hasCrate = false } end
        local R, rows, total = HDG.ItemNameResolver, {}, 0
        for _, d in ipairs(coll.decor or {}) do
            local cnt = d.count or 1
            rows[#rows + 1] = { crateID = crateID, decorID = d.id, count = cnt,
                                name = R:ResolveName(d.id), icon = R:ResolveIcon(d.id) }
            total = total + cnt
        end
        return { hasCrate = true, crateID = crateID, crateName = coll.name or "Crate",
                 completed = coll.completed and true or false, decorRows = rows, decorCount = total }
    end,
})

-- Thin composers (declarative widget bindings). per ADR-024.
Selectors:Register("projects.crateDetailRows", {
    calls = { "projects.crateDetail" },
    fn = function(state, ctx) return Selectors:Call("projects.crateDetail", state, ctx).decorRows or {} end,
})
Selectors:Register("projects.crateDetailTitle", {
    calls = { "projects.crateDetail" },
    fn = function(state, ctx)
        local cd = Selectors:Call("projects.crateDetail", state, ctx)
        if not cd.hasCrate then return "" end
        return (cd.crateName or "Crate") .. "  -  " .. cd.decorCount .. (cd.decorCount == 1 and " item" or " items")
    end,
})
Selectors:Register("projects.crateDetailHasCrate", {
    calls = { "projects.crateDetail" },
    fn = function(state, ctx) return Selectors:Call("projects.crateDetail", state, ctx).hasCrate == true end,
})
-- Room selected but no crate yet -> drives the "+ Add Crate" CTA.
Selectors:Register("projects.crateDetailNeedsCrate", {
    calls = { "projects.crateDetail", "projects.sidePanelOpen" },
    fn = function(state, ctx)
        return Selectors:Call("projects.sidePanelOpen", state, ctx)
           and not Selectors:Call("projects.crateDetail", state, ctx).hasCrate
    end,
})

-- ============================================================================
-- Decor picker: catalog browse scoped to "add to this crate".
-- {} when picker is closed (pickerCrateID nil). iconTexture/iconAtlas from
-- catalog (NOT GetItemIconByID -- decor previews).
-- ============================================================================
Selectors:Register("projects.pickerResults", {
    memoized = true,
    reads = { "account.collections", "session.ui.projects.pickerCrateID",
              "session.ui.projects.pickerSearch",
              "session.ui.projects.focusedCategoryID", "session.ui.projects.focusedSubcategoryID",
              "account.collection.ownedDecorIDs", "session.catalog.sweepGeneration" },
    calls = { "decor.allItems" },
    fn = function(state, ctx)
        local crateID = state.session.ui.projects.pickerCrateID
        if not crateID then return {} end   -- picker closed
        local search = state.session.ui.projects.pickerSearch:lower()
        local catFilt = state.session.ui.projects.focusedCategoryID    -- nil = All (rail)
        local subFilt = state.session.ui.projects.focusedSubcategoryID  -- nil = All within category
        local crateCounts = {}   -- decorID -> count in the open crate (for the picker stepper)
        local crate = state.account.collections[crateID]
        if crate and crate.decor then for _, d in ipairs(crate.decor) do crateCounts[d.id] = d.count or 1 end end
        local rows = {}
        for _, it in ipairs(Selectors:Call("decor.allItems", state, ctx)) do
            -- Owned-only: crates hold decor you'll place (All/Owned/Missing toggle removed).
            local nameOK = (search == "") or (it.name and it.name:lower():find(search, 1, true) ~= nil)
            -- Category nav filter (Blizzard categoryID; nil = All; 0 = Uncategorized).
            local row    = HDG.HousingCatalogObserver:GetRow(it.itemID)
            local catID  = (row and row.categoryID)    or 0
            local subID  = (row and row.subcategoryID) or 0
            local catOK  = (catFilt == nil) or (catFilt == catID)
            local subOK  = (subFilt == nil) or (subFilt == subID)
            if it.isOwned and nameOK and catOK and subOK then
                local cc = crateCounts[it.itemID] or 0
                rows[#rows + 1] = {
                    itemID = it.itemID, decorID = it.decorID, name = it.name,
                    iconTexture = it.iconTexture, iconAtlas = it.iconAtlas,
                    isOwned = it.isOwned, inCrate = cc > 0, crateCount = cc,
                }
            end
        end
        return rows
    end,
})

-- (projects.pickerFilterChips removed: picker is owned-only; All/Owned/Missing toggle gone.)
-- Bulk-add gated on non-empty search (so "Add all" can't dump the whole catalog).
Selectors:Register("projects.pickerBulkAddCount", {
    calls = { "projects.pickerResults" },
    reads = { "session.ui.projects.pickerSearch" },
    fn = function(state, ctx)
        if state.session.ui.projects.pickerSearch == "" then return 0 end
        local n = 0
        for _, r in ipairs(Selectors:Call("projects.pickerResults", state, ctx)) do
            if not r.inCrate then n = n + 1 end
        end
        return n
    end,
})
Selectors:Register("projects.pickerCanBulkAdd", {
    calls = { "projects.pickerBulkAddCount" },
    fn = function(state, ctx) return Selectors:Call("projects.pickerBulkAddCount", state, ctx) > 0 end,
})
Selectors:Register("projects.pickerBulkAddLabel", {
    calls = { "projects.pickerBulkAddCount" },
    fn = function(state, ctx) return "+ Add all " .. Selectors:Call("projects.pickerBulkAddCount", state, ctx) end,
})

-- Saved Styles importable into the open crate. {} when picker is closed.
-- ===== Decor-picker category rail (Blizzard in-situ drill-down) =============
-- storedOnly = false: picker dims (not hides) categories with no owned items.
Selectors:Register("projects.pickerRail", {
    memoized = true,
    reads = {
        "session.house.categoryTree",
        "session.ui.projects.focusedCategoryID",
        "session.ui.projects.focusedSubcategoryID",
    },
    fn = function(state)
        local p = state.session.ui.projects
        -- storedOnly = true: owned-only categories (the picker only adds decor you own),
        -- matching the Style Curator's rail. (false showed empty categories -- one read as
        -- a second "All".)
        return HDG.CategoryNav.BuildPickerRail(
            state.session.house.categoryTree, p.focusedCategoryID, p.focusedSubcategoryID, true)
    end,
})

Selectors:Register("projects.pickerStyleRows", {
    reads = { "account.collections", "session.ui.projects.pickerCrateID" },
    fn = function(state)
        if not state.session.ui.projects.pickerCrateID then return {} end
        local rows = {}
        for id, coll in pairs(state.account.collections) do
            if coll.type == "style" and coll.items and #coll.items > 0 then
                -- User styles store their name in displayName (STYLES_CREATE_STYLE), not name.
                rows[#rows + 1] = { id = id, name = coll.displayName or coll.name or "Style", count = #coll.items }
            end
        end
        table.sort(rows, function(a, b) return a.name < b.name end)
        return rows
    end,
})
Selectors:Register("projects.pickerHasStyles", {
    calls = { "projects.pickerStyleRows" },
    fn = function(state, ctx) return #Selectors:Call("projects.pickerStyleRows", state, ctx) > 0 end,
})

-- Picker open when a target crate is set.
Selectors:Register("projects.pickerOpen", {
    reads = { "session.ui.projects.pickerCrateID" },
    fn = function(state) return state.session.ui.projects.pickerCrateID ~= nil end,
})
-- modelPreview binds itemID to this (hovered/selected picker item).
Selectors:Register("projects.pickerSelectedItemID", {
    reads = { "session.ui.projects.pickerSelectedItemID" },
    fn = function(state) return state.session.ui.projects.pickerSelectedItemID end,
})

-- ============================================================================
-- Orphan crates: crates whose room was removed on recapture (parent cleared).
-- Re-attach targets the selected room.
-- ============================================================================
Selectors:Register("projects.orphanRows", {
    calls = { "projects.crateRows" },
    fn = function(state, ctx) return Selectors:Call("projects.crateRows", state, ctx).orphans or {} end,
})
-- Show orphan section when a room is selected AND orphans exist.
Selectors:Register("projects.orphansAttachable", {
    calls = { "projects.crateRows", "projects.sidePanelOpen" },
    fn = function(state, ctx)
        return Selectors:Call("projects.sidePanelOpen", state, ctx)
           and #(Selectors:Call("projects.crateRows", state, ctx).orphans or {}) > 0
    end,
})

-- Breadcrumb chips: House > Floor N > [Room].
Selectors:Register("projects.breadcrumb", {
    reads = { "account.projects.houses", "account.projects.versions",
              "session.ui.projects.selectedFloor", "session.ui.projects.selectedRoomID" },
    fn = function(state)
        local nav, houses = state.session.ui.projects, state.account.projects.houses
        local houseName, n = nil, 0
        for _, h in pairs(houses) do n = n + 1; houseName = h.name end
        local chips = { { id = "house", label = (n == 1 and houseName) or "My House" } }
        chips[#chips + 1] = { id = "floor", label = "Floor " .. nav.selectedFloor }
        if nav.selectedRoomID then
            local room = _activeRooms(state)[nav.selectedRoomID]
            if room then
                local p = HDG.Projects.IDs.parsePath(nav.selectedRoomID)
                chips[#chips + 1] = { id = "room", label = _roomLabel(room, p and p.floor) }
            end
        end
        return chips
    end,
})

-- Ambiguous recapture matches awaiting manual remap. Empty = nothing pending.
Selectors:Register("projects.ambiguousMatches", {
    reads = { "session.ui.projects.ambiguous" },
    fn = function(state)
        return state.session.ui.projects.ambiguous
    end,
})

-- ===== Crate ledger (landing) ===============================================
-- Orphans are GLOBAL (parent cleared -> not house/version-scoped); the inventory is
-- the ACTIVE version's rooms that hold decor. Both feed the landing's one scrollbox.

-- Count of orphaned crates (decor from demolished rooms). Drives the header alert.
Selectors:Register("projects.orphanCount", {
    memoized = true,
    reads = { "account.collections" },
    fn = function(state)
        local n = 0
        for _, coll in pairs(state.account.collections) do
            if coll.type == "crate" and coll.parent == nil then n = n + 1 end
        end
        return n
    end,
})
Selectors:Register("projects.hasOrphans", {
    calls = { "projects.orphanCount" },
    fn = function(state, ctx) return Selectors:Call("projects.orphanCount", state, ctx) > 0 end,
})
Selectors:Register("projects.orphanAlertText", {
    calls = { "projects.orphanCount" },
    fn = function(state, ctx)
        local n = Selectors:Call("projects.orphanCount", state, ctx)
        if n <= 0 then return "" end
        return "! " .. n .. " orphaned"
    end,
})

-- Rooms in the active version, ordered by floor then label -- the reclaim-target menu.
Selectors:Register("projects.reclaimTargets", {
    memoized = true,
    reads = { "account.projects.houses", "account.projects.versions" },
    fn = function(state)
        local IDs = HDG.Projects.IDs
        local _, _, version = _activeVersionContext(state)
        local out = {}
        if not version then return out end
        for roomID, room in pairs(version.rooms) do
            local p = IDs.parsePath(roomID)
            if p then out[#out + 1] = { roomID = roomID, label = _roomLabel(room, p.floor), floor = p.floor } end
        end
        table.sort(out, function(a, b)
            if a.floor ~= b.floor then return a.floor < b.floor end
            return a.label < b.label
        end)
        return out
    end,
})

-- Flat ledger rows: orphan bay (or "all clear") + crate inventory (rooms holding decor).
-- Kinds: orphanHeader{count,orphanIDs} | orphan{crateID,name,decorCount,was,orphanedAt} |
--        orphanEmpty | inventoryHeader{count} | inventoryRoom{roomID,label,floor,decorCount}.
-- NOT room-scoped (no selectedRoomID read) -- this is a global ledger, not a detail panel.
Selectors:Register("projects.crateLedgerRows", {
    memoized = true,
    reads = { "account.collections", "account.projects.houses", "account.projects.versions" },
    fn = function(state)
        local IDs, SA = HDG.Projects.IDs, HDG.Projects.ShapeAtlas
        local _, vid, version = _activeVersionContext(state)
        local colls = state.account.collections

        -- Orphans: parent cleared. Decor summed; "was <room>" + age. Newest first.
        local orphans, orphanIDs = {}, {}
        for id, coll in pairs(colls) do
            if coll.type == "crate" and coll.parent == nil then
                local n = 0
                for _, d in ipairs(coll.decor or {}) do n = n + (d.count or 1) end
                orphans[#orphans + 1] = {
                    crateID = id, name = coll.name or "Crate", decorCount = n,
                    was = coll.lastKnownRoomName or (coll.lastKnownShape and SA.GetLabel(coll.lastKnownShape)),
                    orphanedAt = coll.orphanedAt,
                }
            end
        end
        table.sort(orphans, function(a, b) return (a.orphanedAt or 0) > (b.orphanedAt or 0) end)
        for _, o in ipairs(orphans) do orphanIDs[#orphanIDs + 1] = o.crateID end

        -- Inventory: active-version rooms whose crate holds decor (empty rooms excluded).
        local inv = {}
        if version then
            local byRoom = {}
            for _, coll in pairs(colls) do
                if coll.type == "crate" and coll.versionID == vid and coll.parent and coll.decor then
                    local n = 0
                    for _, d in ipairs(coll.decor) do n = n + (d.count or 1) end
                    if n > 0 then byRoom[coll.parent] = (byRoom[coll.parent] or 0) + n end
                end
            end
            for roomID, n in pairs(byRoom) do
                local room, p = version.rooms[roomID], IDs.parsePath(roomID)
                if room and p then
                    inv[#inv + 1] = { roomID = roomID, label = _roomLabel(room, p.floor), floor = p.floor, decorCount = n }
                end
            end
            table.sort(inv, function(a, b)
                if a.floor ~= b.floor then return a.floor < b.floor end
                return a.label < b.label
            end)
        end

        local rows = {}
        if #orphans == 0 then
            rows[#rows + 1] = { kind = "orphanEmpty" }
        else
            rows[#rows + 1] = { kind = "orphanHeader", count = #orphans, orphanIDs = orphanIDs }
            for _, o in ipairs(orphans) do
                rows[#rows + 1] = { kind = "orphan", crateID = o.crateID, name = o.name,
                                    decorCount = o.decorCount, was = o.was, orphanedAt = o.orphanedAt }
            end
        end
        rows[#rows + 1] = { kind = "inventoryHeader", count = #inv }
        for _, r in ipairs(inv) do
            rows[#rows + 1] = { kind = "inventoryRoom", roomID = r.roomID, label = r.label,
                                floor = r.floor, decorCount = r.decorCount }
        end
        return rows
    end,
})

-- ============================================================================
-- Architect/landing view-feed selectors. per ADR-024.
-- ============================================================================

-- Decor budget as 0-1 fraction for the architect progressbar.
Selectors:Register("projects.budgetProgress", {
    reads = { "session.house.budget" },
    calls = { "projects.placementCaps" },
    fn = function(state, ctx)
        local b = state.session.house.budget
        local decorMax = Selectors:Call("projects.placementCaps", state, ctx).decorMax
        if decorMax <= 0 then return 0 end   -- exception(boundary): pre-capture or no cap -> avoid 0/0
        return b.decorSpent / decorMax
    end,
})

-- Decor budget label "128 / 210 decor" for the architect strip.
Selectors:Register("projects.budgetText", {
    reads = { "session.house.budget" },
    calls = { "projects.placementCaps" },
    fn = function(state, ctx)
        local b = state.session.house.budget
        local decorMax = Selectors:Call("projects.placementCaps", state, ctx).decorMax
        -- house-decor-budget-icon (Blizzard atlas) prefixes the count as the visual label.
        return "|A:house-decor-budget-icon:16:16|a " .. string.format("%d / %d", b.decorSpent, decorMax)
    end,
})

-- Breadcrumb string "My House  >  Floor 1  >  Hall" (ASCII separators only).
Selectors:Register("projects.breadcrumbText", {
    calls = { "projects.breadcrumb" },
    fn = function(state, ctx)
        local labels = {}
        for _, c in ipairs(Selectors:Call("projects.breadcrumb", state, ctx)) do
            labels[#labels + 1] = c.label
        end
        return table.concat(labels, "  >  ")
    end,
})

-- No rooms captured. Drives "Capture my house" CTA (visible bindings don't negate).
Selectors:Register("projects.noRooms", {
    reads = { "account.projects.houses", "account.projects.versions" },
    fn = function(state)
        return next(_activeRooms(state)) == nil
    end,
})

-- Selected room's name for the detail-panel title label binding.
Selectors:Register("projects.roomDetailName", {
    reads = { "account.projects.houses", "account.projects.versions", "session.ui.projects.selectedRoomID" },
    fn = function(state)
        local roomID = state.session.ui.projects.selectedRoomID
        local room = roomID and _activeRooms(state)[roomID]
        if not room then return "Select a room" end   -- exception(boundary): stale or nil selection
        local p = HDG.Projects.IDs.parsePath(roomID)
        return _roomLabel(room, p and p.floor)
    end,
})

-- Selected room meta: "Square M  -  Floor 1  -  doors: N/E".
Selectors:Register("projects.roomDetailMeta", {
    reads = { "account.projects.houses", "account.projects.versions", "session.ui.projects.selectedRoomID" },
    fn = function(state)
        local roomID = state.session.ui.projects.selectedRoomID
        local room = roomID and _activeRooms(state)[roomID]
        if not room then return "" end   -- exception(boundary): stale or nil selection
        local p = HDG.Projects.IDs.parsePath(roomID)
        local doors = table.concat(_roomDoorCardinals(_activeRooms(state), roomID), "/")
        return string.format("%s  -  Floor %d  -  doors: %s",
            HDG.Projects.ShapeAtlas.GetLabel(room.shape), (p and p.floor) or 1,
            (doors ~= "" and doors) or "none")
    end,
})

-- ===== Layouts tab ==========================================================
-- The Layouts tab browses/previews/shares saved versions. Its preview/detail read
-- the SELECTED version (session.ui.projects.layoutSelectedVersionID) -- NOT the
-- Architect's activeVersionID -- so browsing never disturbs editing.

-- Fallback label only -- the Layouts UI shows house.name; this covers houses captured
-- before a name was stamped. (House identity is a plot digest now, not a faction word.)
local function _houseLabel(_houseID)
    return "House"
end

-- Left list: houses -> their versions (Live first, then what-ifs by createdAt), the
-- selected row flagged. Group header carries the faction label + level.
Selectors:Register("projects.layoutGroups", {
    reads = { "account.projects.houses", "account.projects.versions",
              "session.ui.projects.layoutSelectedVersionID" },
    fn = function(state)
        local p   = state.account.projects
        local sel = state.session.ui.projects.layoutSelectedVersionID
        local byHouse = {}
        for vid, v in pairs(p.versions) do
            local g = byHouse[v.houseID]
            if not g then
                local house = p.houses[v.houseID]   -- strict: a version always belongs to a house
                -- Show the real house name (matches the Architect breadcrumb); fall back
                -- to the faction word only if the capture never stamped a name.
                g = { houseID = v.houseID, label = house.name or _houseLabel(v.houseID),
                      level = house.level, currentVersionID = house.currentVersionID, rows = {} }
                byHouse[v.houseID] = g
            end
            g.rows[#g.rows + 1] = {
                versionID = vid, name = v.name or "?", createdAt = v.createdAt or 0,
                isLive = (vid == g.currentVersionID), isSelected = (vid == sel),
            }
        end
        local groups = {}
        for _, g in pairs(byHouse) do
            table.sort(g.rows, function(a, b)
                if a.isLive ~= b.isLive then return a.isLive end   -- Live first
                return a.createdAt < b.createdAt
            end)
            groups[#groups + 1] = g
        end
        table.sort(groups, function(a, b) return a.label < b.label end)
        return groups
    end,
})

-- Preview: ALL floors (1..3) of the SELECTED version, each as positioned room
-- footprints + a bbox for fit-to-frame. Floor count = max room floor or
-- version.numFloors, capped at 3. The controller rotates each floor to fit its slot.
Selectors:Register("projects.layoutPreviewModel", {
    reads = { "account.projects.versions", "session.ui.projects.layoutSelectedVersionID" },
    fn = function(state)
        local A, IDs = HDG.Projects.ShapeAtlas, HDG.Projects.IDs
        local sel = state.session.ui.projects.layoutSelectedVersionID
        local version = sel and state.account.projects.versions[sel]
        -- exception(nullable): nothing selected, or selection points at a deleted
        -- version -- the controller (re)selects a default and paints empty meanwhile.
        if not version then return { floors = {}, floorCount = 0 } end
        local byFloor, maxFloor = {}, 1
        for rid, room in pairs(version.rooms) do
            local pp = IDs.parsePath(rid)
            if pp and pp.floor then
                if pp.floor > maxFloor then maxFloor = pp.floor end
                local rot   = room.cell.rotation or 0
                local cells = A.GetCells(room.shape)
                local rc    = A.RotateCells(cells, rot)
                local fl    = byFloor[pp.floor]
                if not fl then fl = { rooms = {}, bb = {} }; byFloor[pp.floor] = fl end
                fl.rooms[#fl.rooms + 1] = {
                    shape = room.shape, x = room.cell.x, y = room.cell.y,
                    w = rc[1], d = rc[2], rotation = rot,
                    -- Rotated footprint cells -> the preview draws true-shape vector
                    -- outlines (cross/T/L keep their silhouette; rects/octagons = bbox).
                    mask = A.RotateMask(A.GetMask(room.shape), rot, cells[1], cells[2]),
                    circle = A.IsCircle(room.shape),
                }
                _extendFootprint(fl.bb, room.cell.x, room.cell.y, rc[1], rc[2])
            end
        end
        if version.numFloors and version.numFloors > maxFloor then maxFloor = version.numFloors end
        if maxFloor > 3 then maxFloor = 3 end
        local floors = {}
        for f = 1, maxFloor do
            local fl = byFloor[f] or { rooms = {}, bb = {} }
            floors[#floors + 1] = { floor = f, rooms = fl.rooms, bbox = fl.bb }
        end
        return { floors = floors, floorCount = maxFloor }
    end,
})

-- Bottom detail: name / house label / live-or-what-if / room + floor counts / budget /
-- canDelete (everything except the inviolable live version) for the SELECTED version.
Selectors:Register("projects.layoutDetail", {
    reads = { "account.projects.houses", "account.projects.versions",
              "session.ui.projects.layoutSelectedVersionID" },
    calls = { "projects.placementCaps", "projects.layoutPreviewModel" },
    fn = function(state, ctx)
        local A   = HDG.Projects.ShapeAtlas
        local sel = state.session.ui.projects.layoutSelectedVersionID
        local version = sel and state.account.projects.versions[sel]
        if not version then return { hasSelection = false } end   -- exception(nullable): no/deleted selection
        local house  = state.account.projects.houses[version.houseID]
        local isLive = (sel == house.currentVersionID)
        local cost, roomCount = 0, 0
        for _, room in pairs(version.rooms) do
            cost = cost + A.GetBudget(room.shape)
            roomCount = roomCount + 1
        end
        local max = Selectors:Call("projects.placementCaps", state, ctx).roomMax
        return {
            hasSelection = true, versionID = sel, houseID = version.houseID,
            name = version.name or "?", houseLabel = house.name or _houseLabel(version.houseID),
            isLive = isLive, canDelete = not isLive, roomCount = roomCount,
            floorCount = Selectors:Call("projects.layoutPreviewModel", state, ctx).floorCount,
            budgetText = (max > 0) and string.format("%d / %d", cost, max) or "",
        }
    end,
})

-- Header label string for the right detail panel: "<name>  [LIVE]" or "<name>  [wif]".
Selectors:Register("projects.layoutDetailHeader", {
    reads = { "account.projects.houses", "account.projects.versions",
              "session.ui.projects.layoutSelectedVersionID" },
    calls = { "projects.layoutDetail" },
    fn = function(state, ctx)
        local d = Selectors:Call("projects.layoutDetail", state, ctx)
        if not d.hasSelection then return "" end
        local badge = d.isLive and "  [LIVE]" or "  [wif]"
        -- House name first so the right pane says WHICH house this Live/what-if is.
        return d.houseLabel .. "  -  " .. d.name .. badge
    end,
})

-- Flat list for the layouts scrollbox: house group headers interleaved with
-- version rows. Derived from layoutGroups. ed.kind="header"|"version".
Selectors:Register("projects.layoutListRows", {
    reads = { "account.projects.houses", "account.projects.versions",
              "session.ui.projects.layoutSelectedVersionID" },
    calls = { "projects.layoutGroups" },
    fn = function(state, ctx)
        local groups = Selectors:Call("projects.layoutGroups", state, ctx)
        local out = {}
        for _, g in ipairs(groups) do
            out[#out + 1] = { kind = "header", houseID = g.houseID,
                houseLabel = g.label, level = g.level }
            for _, row in ipairs(g.rows) do
                out[#out + 1] = { kind = "version", versionID = row.versionID,
                    name = row.name, isLive = row.isLive, isSelected = row.isSelected,
                    houseID = g.houseID }
            end
        end
        return out
    end,
})

-- Boolean: true when there is a valid layout selection (used for `visible` bindings).
Selectors:Register("projects.hasLayoutSelection", {
    reads = { "account.projects.versions", "session.ui.projects.layoutSelectedVersionID" },
    fn = function(state)
        local sel = state.session.ui.projects.layoutSelectedVersionID
        return sel ~= nil and state.account.projects.versions[sel] ~= nil
    end,
})

-- Stats string for the right detail panel: "Rooms N  Floors N  Budget N/N".
Selectors:Register("projects.layoutDetailStats", {
    reads = { "account.projects.houses", "account.projects.versions",
              "session.ui.projects.layoutSelectedVersionID" },
    calls = { "projects.layoutDetail", "projects.placementCaps" },
    fn = function(state, ctx)
        local d = Selectors:Call("projects.layoutDetail", state, ctx)
        if not d.hasSelection then return "" end
        return string.format("Rooms %d  Floors %d  Budget %s",
            d.roomCount, d.floorCount, d.budgetText)
    end,
})
