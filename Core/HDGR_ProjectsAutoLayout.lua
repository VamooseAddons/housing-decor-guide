-- HDG.Projects.AutoLayout
-- ============================================================================
-- Pure deterministic GRID-PACK for captured rooms. There's no position API, so
-- rather than GUESS the real arrangement from reconstructed door connections (which
-- read rough), we lay the rooms out in tidy rows by capture order -- each as its
-- rotated footprint (doors face the captured way via InferRotation), never
-- overlapping. A clean starting canvas the player drags to match their real house.
-- No connectivity reconstruction, no WoW API.
--
-- The ENTRY (anchor) room is placed last, at bottom-centre -- mirroring the real
-- house entrance -- below the packed rows, centred on their width.
--
-- Input:  { rooms = { [id] = { shape, doorCardinals?, isBase?, captureIndex? } } }
-- Output: { layout = { [id] = { cell = {x,y}, w, d, rotation, mask } } }
-- Convention: +x East, +y South. Origin (0,0) top-left.

HDG = HDG or {}
HDG.Projects = HDG.Projects or {}
HDG.Projects.AutoLayout = HDG.Projects.AutoLayout or {}
local M = HDG.Projects.AutoLayout

local ROW_GUTTER = 1     -- blank cells between rooms + between rows
local MAX_ROW_W  = 22    -- wrap to a new row once a row would exceed this width

-- Rotated footprint for a captured room. Rotation is inferred from the captured door
-- cardinals so doors face the right way out of the box.
local function _footprint(room)
    local A     = HDG.Projects.ShapeAtlas
    local cells = A.GetCells(room.shape)
    local rot   = A.InferRotation(room.shape, room.doorCardinals)
    local rc    = A.RotateCells(cells, rot)
    local mask  = A.RotateMask(A.GetMask(room.shape), rot, cells[1], cells[2])
    return rc[1], rc[2], mask, rot
end

local function _isEntry(room) return room.shape == "entry" or room.isBase end

-- Non-entry rooms in deterministic order: capture order, then id (stable memo/test).
local function _packOrder(rooms)
    local ids = {}
    for id, room in pairs(rooms) do
        if not _isEntry(room) then ids[#ids + 1] = id end
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

    -- Grid-pack the non-entry rooms in rows; track the overall span.
    local x, y, rowMaxD, maxRight, maxBottom = 0, 0, 0, 0, 0
    for _, id in ipairs(_packOrder(rooms)) do
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
    return result
end
