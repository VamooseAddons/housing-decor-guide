-- HDG.Projects.AutoLayout
-- ============================================================================
-- Layout entry point for captured rooms. PRIMARY: the Connectivity solver
-- reconstructs the real arrangement from the capture's transient door data
-- (occupied stubs + chronological placement counters -- see
-- HDGR_AUTOLAYOUT_SOLVER_SPEC_2026-08-10). FALLBACK: the original deterministic
-- GRID-PACK -- tidy rows by capture order, entry bottom-centre -- for blueprint
-- imports, pre-feature records, and any capture the solver rejects (every
-- rejection is Log:Warn'd; silent degradation is a NO GUARDS violation).
-- Pure, no WoW API.
--
-- Input:  { rooms = { [id] = { shape, doors?, placementIndex?, isBase?, captureIndex? } },
--           seedCells? = { ["x,y"] = true } }   -- lower floors' projected shafts
-- Output: { layout = { [id] = { cell = {x,y}, w, d, rotation, mask } } }
-- Convention: +x East, +y South. Origin (0,0) top-left.

HDG = HDG or {}
HDG.Projects = HDG.Projects or {}
HDG.Projects.AutoLayout = HDG.Projects.AutoLayout or {}
local M = HDG.Projects.AutoLayout

HDG.Log:RegisterTags({ autolayout = { user = false, level = "warn" } })

local ROW_GUTTER = 1     -- blank cells between rooms + between rows
local MAX_ROW_W  = 22    -- wrap to a new row once a row would exceed this width

-- Sorted cardinal list off a room's transient doors (Capture output). Blueprint
-- and pre-feature rooms have no doors -> nil -> rotation 0 (their existing behavior).
local function _cardinalList(doors)
    if not doors then return nil end   -- exception(nullable): blueprint/pre-feature rooms carry no doors
    local out = {}
    for _, d in ipairs(doors) do out[#out + 1] = d.cardinal end
    table.sort(out)
    return out
end

-- Rotated footprint for a captured room. Rotation is inferred from the captured door
-- cardinals so doors face the right way out of the box.
local function _footprint(room)
    return HDG.Projects.ShapeAtlas.FootprintFor(room.shape, _cardinalList(room.doors))
end

local function _isEntry(room) return room.shape == "entry" or room.isBase end

-- Non-entry, non-pinned rooms in deterministic order: capture order, then id.
local function _packOrder(rooms, pinned)
    local ids = {}
    for id, room in pairs(rooms) do
        if not _isEntry(room) and not (pinned and pinned[id]) then ids[#ids + 1] = id end
    end
    table.sort(ids, function(a, b)
        local ia, ib = rooms[a].captureIndex or 0, rooms[b].captureIndex or 0
        if ia ~= ib then return ia < ib end
        return a < b
    end)
    return ids
end

function M.compute(input)
    local result = { layout = {} }
    if type(input) ~= "table" then return result end
    local rooms = input.rooms or {}
    if not next(rooms) then return result end

    -- Primary: connectivity solve (door-aligned real arrangement).
    local solved, reason = HDG.Projects.Connectivity.Solve({
        rooms = rooms, seedCells = input.seedCells,
        supportCells = input.supportCells, pins = input.pins,
    })
    if solved then
        for _, w in ipairs(solved.warnings) do HDG.Log:Warn("autolayout", w) end
        result.layout = solved.layout
        return result
    end
    HDG.Log:Warn("autolayout", "solver fallback -> grid-pack: " .. reason)

    -- Fallback honors PINS (tower alignment survives even a grid-packed floor);
    -- the support rule cannot be honored here -- warned so the degradation shows.
    local pinned = {}
    if input.pins then
        for id, pin in pairs(input.pins) do
            local room = rooms[id]
            if room then
                local w, d, mask, rot = _footprint(room)
                result.layout[id] = { cell = { x = pin.x, y = pin.y }, w = w, d = d, rotation = rot, mask = mask }
                pinned[id] = true
            end
        end
    end
    if input.supportCells then
        HDG.Log:Warn("autolayout", "grid-pack fallback cannot honor the anchored-from-below rule -- packed rooms may float")
    end

    -- Fallback: grid-pack the remaining non-entry rooms in rows; track the span.
    local x, y, rowMaxD, maxRight, maxBottom = 0, 0, 0, 0, 0
    for _, id in ipairs(_packOrder(rooms, pinned)) do
        local w, d, mask, rot = _footprint(rooms[id])
        if x > 0 and (x + w) > MAX_ROW_W then          -- wrap to the next row
            x, y, rowMaxD = 0, y + rowMaxD + ROW_GUTTER, 0
        end
        result.layout[id] = { cell = { x = x, y = y }, w = w, d = d, rotation = rot, mask = mask }
        if x + w > maxRight then maxRight = x + w end
        x = x + w + ROW_GUTTER
        if d > rowMaxD then rowMaxD = d end
        if y + rowMaxD > maxBottom then maxBottom = y + rowMaxD end
    end

    -- Entry last, at bottom-centre: below the packed rows, centred on their width.
    for id, room in pairs(rooms) do
        if _isEntry(room) and not result.layout[id] then
            local w, d, mask, rot = _footprint(room)
            local ex = math.max(0, math.floor((maxRight - w) / 2))
            local ey = (maxBottom > 0) and (maxBottom + ROW_GUTTER) or 0
            result.layout[id] = { cell = { x = ex, y = ey }, w = w, d = d, rotation = rot, mask = mask }
            break   -- exactly one entry
        end
    end

    -- A fallback floor above projected volume or pinned sections: shift the pack
    -- below both so rows never land inside a shaft or on a pinned tower
    -- (2026-08-10 review critical #5). Pinned rooms themselves stay put.
    local blockBottom = nil
    if input.seedCells then
        for k in pairs(input.seedCells) do
            local sy = tonumber(k:match(",(%-?%d+)$"))
            if sy and (not blockBottom or sy > blockBottom) then blockBottom = sy end
        end
    end
    for id in pairs(pinned) do
        local p = result.layout[id]
        local bottom = p.cell.y + p.d - 1
        if not blockBottom or bottom > blockBottom then blockBottom = bottom end
    end
    if blockBottom then
        local shift = blockBottom + 1 + ROW_GUTTER
        for id, placed in pairs(result.layout) do
            if not pinned[id] then placed.cell.y = placed.cell.y + shift end
        end
        HDG.Log:Warn("autolayout", "grid-pack shifted below projected/pinned cells (dy=" .. shift .. ")")
    end
    return result
end
