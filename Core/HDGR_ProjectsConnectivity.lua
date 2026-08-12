-- HDG.Projects.Connectivity
-- ============================================================================
-- Pure connectivity solver: captured rooms (with transient placementIndex +
-- doors) -> a door-aligned, non-overlapping tree layout mirroring the real
-- house. Chronological tree-grow (HDGR_AUTOLAYOUT_SOLVER_SPEC_2026-08-10 SS5):
-- rooms in placement-counter order (the roomGUID counter is chronological, and
-- every room's tree-parent was placed earlier), each attached to an open
-- opposite-cardinal occupied stub on an already-placed room, doors aligned via
-- ShapeAtlas.DoorMid, DFS backtracking on footprint overlap.
--
-- Cross-floor constraints (spec SS10): `seedCells` = projected garden volumes
-- from lower floors (forbidden); `supportCells` = the anchored-from-below rule
-- (upper-floor rooms must sit fully on the floor below's roofed footprint);
-- `pins` = stair sections fixed directly above their lower-floor mates.
--
-- Side-effect free: returns (result, nil) or (nil, reason) -- AutoLayout logs
-- and falls back to grid-pack. result = { layout, edges, warnings }.
-- No WoW API.

HDG = HDG or {}
HDG.Projects = HDG.Projects or {}
HDG.Projects.Connectivity = HDG.Projects.Connectivity or {}
local M = HDG.Projects.Connectivity

local OPP      = { N = "S", S = "N", E = "W", W = "E" }
local CARDS    = { "N", "E", "S", "W" }
local MAX_SCAN = 64   -- root-placement scan bound on seeded floors

local function _cardinalList(doors)
    local out = {}
    for _, d in ipairs(doors) do out[#out + 1] = d.cardinal end
    table.sort(out)
    return out
end

-- Pre-checks (spec SS5.1). Any miss -> (nil, reason); the caller logs + grid-packs.
-- Deterministic first-failure: rooms scanned in sorted-id order.
local function _precheck(rooms)
    local A, ids = HDG.Projects.ShapeAtlas, {}
    for id in pairs(rooms) do ids[#ids + 1] = id end
    table.sort(ids)
    for _, id in ipairs(ids) do
        local room = rooms[id]
        if room.placementIndex == nil then
            return ("room %s missing placementIndex (GUID unparsed)"):format(id)
        end
        if room.doors == nil then
            return ("room %s missing doors (pre-feature record or blueprint import)"):format(id)
        end
        local want = #A.GetDoors(room.shape)
        if #room.doors ~= want then
            return ("room %s door count %d vs atlas %d (interrupted capture?)"):format(id, #room.doors, want)
        end
    end
    return nil
end

-- Solve order: placementIndex asc, ties by id (stable under pairs() nondeterminism).
local function _order(rooms)
    local ids = {}
    for id in pairs(rooms) do ids[#ids + 1] = id end
    table.sort(ids, function(a, b)
        local pa, pb = rooms[a].placementIndex, rooms[b].placementIndex
        if pa ~= pb then return pa < pb end
        return a < b
    end)
    return ids
end

-- Per-room geometry + stub state, computed once per solve.
local function _prep(rooms)
    local A, out = HDG.Projects.ShapeAtlas, {}
    for id, room in pairs(rooms) do
        local w, d, mask, rot = A.FootprintFor(room.shape, _cardinalList(room.doors))
        local stubs = {}
        for _, door in ipairs(room.doors) do
            if door.occupied then stubs[door.cardinal] = "open" end
        end
        out[id] = { w = w, d = d, mask = mask, rot = rot, stubs = stubs }
    end
    return out
end

local function _cellKeys(geo, x, y)
    local keys = {}
    for i, m in ipairs(geo.mask) do keys[i] = (x + m[1]) .. "," .. (y + m[2]) end
    return keys
end

-- support = nil means unconstrained (lowest floor / legacy callers); a TABLE
-- means the anchored-from-below rule (spec SS10): every cell must be supported.
local function _fits(occ, seed, support, keys)
    for _, k in ipairs(keys) do
        if occ[k] or (seed and seed[k]) then return false end
        if support and not support[k] then return false end
    end
    return true
end

local function _mark(occ, keys, on)
    for _, k in ipairs(keys) do occ[k] = on or nil end
end

-- Root placement: (0,0) on unconstrained floors; else the first fitting origin
-- scanning y then x (deterministic; the seed/support keep it out of shafts and
-- on top of the floor below). nil, "exhausted" when the bounded window ran out
-- WITH free space possibly beyond it -- distinct from genuine unsolvability.
local function _placeRoot(geo, occ, seed, support)
    if not ((seed and next(seed)) or support) then return 0, 0 end
    for y = 0, MAX_SCAN do
        for x = 0, MAX_SCAN do
            if _fits(occ, seed, support, _cellKeys(geo, x, y)) then return x, y end
        end
    end
    return nil, "exhausted"
end

-- Pre-place PINNED rooms (stair sections directly above their lower-floor
-- mates -- the vertical anchor, spec SS10). Pins are trusted positions from
-- committed reality: exempt from the support rule, but never into a shaft or
-- each other. A conflicting pin means the shared frame has drifted ->
-- whole-floor fallback. Returns (unplaced, anyPin) or (nil, reason).
local function _prePlacePins(ids, geos, pins, occ, pos, seed)
    local unplaced, anyPin = {}, false
    for _, id in ipairs(ids) do
        local pin = pins and pins[id]
        if pin then
            local keys = _cellKeys(geos[id], pin.x, pin.y)
            if not _fits(occ, seed, nil, keys) then
                return nil, ("pinned section %s conflicts at (%d,%d) -- frame drift"):format(id, pin.x, pin.y)
            end
            pos[id] = { x = pin.x, y = pin.y }
            _mark(occ, keys, true)
            anyPin = true
        else
            unplaced[#unplaced + 1] = id
        end
    end
    return unplaced, anyPin
end

-- Leftover open stubs after a successful solve: valid data (a stub whose
-- partner isn't on this floor) -- surfaced, never fatal (spec SS5.6).
local function _leftoverWarnings(ids, geos)
    local warnings = {}
    for _, id in ipairs(ids) do
        for _, card in ipairs(CARDS) do
            if geos[id].stubs[card] == "open" then
                warnings[#warnings + 1] = ("leftover open stub %s on %s"):format(card, id)
            end
        end
    end
    return warnings
end

-- Translate an UNCONSTRAINED solve to min cell (0,0); a seed, support set, or
-- pin ties the layout to the shared cross-floor frame instead (SS5.5/5.7/SS10).
local function _normalize(pos)
    local minX, minY = math.huge, math.huge
    for _, p in pairs(pos) do
        if p.x < minX then minX = p.x end
        if p.y < minY then minY = p.y end
    end
    for _, p in pairs(pos) do p.x, p.y = p.x - minX, p.y - minY end
end

local function _materialize(pos, geos)
    local layout = {}
    for id, p in pairs(pos) do
        local g = geos[id]
        layout[id] = { cell = { x = p.x, y = p.y }, w = g.w, d = g.d, rotation = g.rot, mask = g.mask }
    end
    return layout
end

function M.Solve(input)
    local rooms, seed, support, pins = input.rooms, input.seedCells, input.supportCells, input.pins
    if not next(rooms) then return nil, "no rooms" end
    local reason = _precheck(rooms)
    if reason then return nil, reason end

    local A     = HDG.Projects.ShapeAtlas
    local ids   = _order(rooms)
    local geos  = _prep(rooms)
    local occ   = {}
    local pos   = {}    -- id -> {x, y}
    local edges = {}

    local unplaced, anyPin = _prePlacePins(ids, geos, pins, occ, pos, seed)
    if not unplaced then return nil, anyPin end   -- anyPin carries the reason on failure

    -- Root for floors with no pins: first room chronologically.
    local startAt = 1
    if not anyPin and #unplaced > 0 then
        local rootID  = unplaced[1]
        local rootGeo = geos[rootID]
        local rx, ry = _placeRoot(rootGeo, occ, seed, support)
        if not rx then   -- ry carries "exhausted": the only nil case is window exhaustion
            return nil, ("root scan window (%d) exhausted clear of seed/support -- committed rooms may sit beyond it"):format(MAX_SCAN)
        end
        pos[rootID] = { x = rx, y = ry }
        _mark(occ, _cellKeys(rootGeo, rx, ry), true)
        startAt = 2
    end

    -- DFS over the remaining rooms chronologically; for room i try every
    -- (placed P by placementIndex asc, P stub NESW, matching R stub) -- spec
    -- SS5.4 candidate order, with a node budget as a runaway backstop.
    local budget = 200000
    local function attach(i)
        if i > #unplaced then return true end
        budget = budget - 1
        if budget <= 0 then return false end
        local rid, rgeo = unplaced[i], geos[unplaced[i]]
        for _, pid in ipairs(ids) do
            if pos[pid] then
                local pgeo = geos[pid]
                for _, pCard in ipairs(CARDS) do
                    local rCard = OPP[pCard]
                    if pgeo.stubs[pCard] == "open" and rgeo.stubs[rCard] == "open" then
                        local mx, my = A.DoorMid(pCard, pos[pid].x, pos[pid].y, pgeo.w, pgeo.d, pgeo.mask)
                        local lx, ly = A.DoorMid(rCard, 0, 0, rgeo.w, rgeo.d, rgeo.mask)
                        local x, y = mx - lx, my - ly
                        local keys = _cellKeys(rgeo, x, y)
                        if _fits(occ, seed, support, keys) then
                            pos[rid] = { x = x, y = y }
                            _mark(occ, keys, true)
                            pgeo.stubs[pCard], rgeo.stubs[rCard] = "closed", "closed"
                            edges[#edges + 1] = { a = pid, cardinal = pCard, b = rid }
                            if attach(i + 1) then return true end
                            edges[#edges] = nil
                            pgeo.stubs[pCard], rgeo.stubs[rCard] = "open", "open"
                            _mark(occ, keys, nil)
                            pos[rid] = nil
                        end
                    end
                end
            end
        end
        return false
    end

    if not attach(startAt) then
        if budget <= 0 then return nil, "search budget exhausted (pathological stub set)" end
        return nil, "unattachable room (backtracking exhausted)"
    end

    local warnings = _leftoverWarnings(ids, geos)
    if not ((seed and next(seed)) or support or anyPin) then _normalize(pos) end
    return { layout = _materialize(pos, geos), edges = edges, warnings = warnings }
end
