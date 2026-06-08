-- HDG.Projects.FloorMap
-- ============================================================================
-- Per-floor occupancy + projection, DERIVED from version.rooms (the SSoT).
-- Nothing is stored: a garden is ONE record on its floor and GetFloors gives its
-- vertical span, so both the cells it blocks above AND the ghost it renders above
-- are recomputed on demand. This is why what-if versions need no extra copy --
-- the map derives from whichever version's rooms are passed in.
--
--   OccupiedCells(rooms, floor, exclude?)  -> { ["x,y"]=true }   (collision)
--   ProjectedRooms(rooms, floor)           -> { {roomID,shape,cell}, ... } (render ghosts)
--   CanMoveTo(rooms, roomID, x, y)         -> bool                (drag/move guard)
--
-- Stairs/tall carry a real linked record per floor (occupy their own floor only);
-- gardens (circle) are a single record that projects up its span.

HDG = HDG or {}
HDG.Projects = HDG.Projects or {}
HDG.Projects.FloorMap = HDG.Projects.FloorMap or {}
local M = HDG.Projects.FloorMap

-- A room's vertical span: an explicit per-room override (set by "Expand stairwell
-- up") else the shape default. The SINGLE source for how many floors a room occupies
-- -- every multi-floor room is ONE record that derives its span here (no linked
-- per-floor records, no stairsLink).
local function _effectiveSpan(room)
    return room.floors or HDG.Projects.ShapeAtlas.GetFloors(room.shape)
end

-- Cells occupied on `floor`. A CAPTURED multi-floor room (single record, no
-- stairsLink -- garden / stairwell / tall) projects its footprint UP its full span;
-- a PLACED linked stack marks each floor via its own per-floor record (so it's
-- excluded from projection here). `exclude` (set of roomIDs) is skipped -- the move
-- guard passes the moving room + its links so it can't collide with itself.
function M.OccupiedCells(rooms, floor, exclude)
    local SA, IDs, occ = HDG.Projects.ShapeAtlas, HDG.Projects.IDs, {}
    for rid, room in pairs(rooms) do
        if not (exclude and exclude[rid]) then
            local p = IDs.parsePath(rid)
            local span = _effectiveSpan(room)
            local top = p and (span > 1 and (p.floor + span - 1) or p.floor)
            if p and floor >= p.floor and floor <= top then
                local cells = SA.GetCells(room.shape)
                for _, m in ipairs(SA.RotateMask(SA.GetMask(room.shape), room.cell.rotation or 0, cells[1], cells[2])) do
                    occ[(room.cell.x + m[1]) .. "," .. (room.cell.y + m[2])] = true
                end
            end
        end
    end
    return occ
end

-- Multi-floor rooms (garden / stairwell / tall -- one record each) from LOWER floors
-- whose span reaches `floor`, rendered as dimmed footprints so they "show through" to
-- the floors above their own. Every multi-floor room is a single record (the SSoT
-- derives its span), so there's no double-render to guard against.
function M.ProjectedRooms(rooms, floor)
    local IDs, out = HDG.Projects.IDs, {}
    for rid, room in pairs(rooms) do
        local p, span = IDs.parsePath(rid), _effectiveSpan(room)
        if p and span > 1 and p.floor < floor and floor <= p.floor + span - 1 then
            out[#out + 1] = { roomID = rid, shape = room.shape, cell = room.cell }
        end
    end
    return out
end

-- True if `roomID` can sit at (x,y) without overlapping anything else, on EVERY
-- floor it occupies (its full span). One record per room -> the span comes from
-- _effectiveSpan, not from linked counterparts.
function M.CanMoveTo(rooms, roomID, x, y)
    local SA, IDs = HDG.Projects.ShapeAtlas, HDG.Projects.IDs
    local room = rooms[roomID]
    if not room then return false end
    local p = IDs.parsePath(roomID)
    if not p then return false end
    local span    = _effectiveSpan(room)
    local cells   = SA.GetCells(room.shape)
    local mask    = SA.RotateMask(SA.GetMask(room.shape), room.cell.rotation or 0, cells[1], cells[2])
    local exclude = { [roomID] = true }
    for f = p.floor, p.floor + span - 1 do
        local occ = M.OccupiedCells(rooms, f, exclude)
        for _, m in ipairs(mask) do
            if occ[(x + m[1]) .. "," .. (y + m[2])] then return false end
        end
    end
    return true
end

-- A single-door room's door floats to the room it's placed next to on ANY cardinal:
-- scans outward on all four sides of the BASE (ground) floor and faces the side whose
-- nearest room is CLOSEST (ties: N,S,E,W); an island falls back to the shape's default
-- door side. Shared by gardens AND stairwells:
--   * Garden    -> door renders on the GROUND level only (upper floors are open sky).
--   * Stairwell -> the SAME cardinal renders on every floor it spans, so the upper level
--                  inherits whatever side connected on the ground floor (canvasModel).
function M.FloatingDoorCardinal(rooms, roomID)
    local SA, IDs = HDG.Projects.ShapeAtlas, HDG.Projects.IDs
    local room    = rooms[roomID]
    local default = SA.GetDoors(room.shape)[1]
    local c       = room.cell
    local rc      = SA.RotateCells(SA.GetCells(room.shape), c.rotation or 0)
    local w, d    = rc[1], rc[2]
    local base    = IDs.parsePath(roomID).floor or 1
    local exclude = { [roomID] = true }
    local SCAN    = 64   -- max cells to look outward for the nearest neighbour

    -- Ground-level neighbours only -- the garden door doesn't project up its span.
    local occ = M.OccupiedCells(rooms, base, exclude)

    -- Distance to the nearest occupied cell off a given edge (nil if none within SCAN).
    local function gap(card)
        local along = (card == "N" or card == "S") and w or d
        for dist = 1, SCAN do
            for j = 0, along - 1 do
                local k
                if     card == "W" then k = (c.x - dist)         .. "," .. (c.y + j)
                elseif card == "E" then k = (c.x + w - 1 + dist) .. "," .. (c.y + j)
                elseif card == "N" then k = (c.x + j)            .. "," .. (c.y - dist)
                else                    k = (c.x + j)            .. "," .. (c.y + d - 1 + dist)  -- S
                end
                if occ[k] then return dist end
            end
        end
        return nil
    end

    local best, bestCard
    for _, card in ipairs({ "N", "S", "E", "W" }) do
        local g = gap(card)
        if g and (not best or g < best) then best, bestCard = g, card end
    end
    return bestCard or default
end
