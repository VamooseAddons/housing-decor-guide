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
            local base = room.floor or ((IDs.parsePath(rid) or {}).floor)   -- v7 entries carry .floor; legacy keys encode it
            local span = _effectiveSpan(room)
            local top = base and (span > 1 and (base + span - 1) or base)
            if base and floor >= base and floor <= top then
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
        local base = room.floor or ((IDs.parsePath(rid) or {}).floor)   -- v7 entries carry .floor
        local span = _effectiveSpan(room)
        if base and span > 1 and base < floor and floor <= base + span - 1 then
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
    local base = room.floor or ((IDs.parsePath(roomID) or {}).floor)   -- v7 entries carry .floor
    if not base then return false end
    local span    = _effectiveSpan(room)
    local cells   = SA.GetCells(room.shape)
    local mask    = SA.RotateMask(SA.GetMask(room.shape), room.cell.rotation or 0, cells[1], cells[2])
    local exclude = { [roomID] = true }
    for f = base, base + span - 1 do
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
    local base    = room.floor or (IDs.parsePath(roomID) or {}).floor or 1   -- v7 entries carry .floor
    local exclude = { [roomID] = true }
    local SCAN    = 64   -- max cells to look outward for the nearest neighbour

    -- Ground-level neighbours only -- the garden door doesn't project up its span.
    local occ = M.OccupiedCells(rooms, base, exclude)

    -- Cell key `dist` cells off `card`, at offset `j` along that edge.
    local function edgeKey(card, dist, j)
        if     card == "W" then return (c.x - dist)         .. "," .. (c.y + j)
        elseif card == "E" then return (c.x + w - 1 + dist) .. "," .. (c.y + j)
        elseif card == "N" then return (c.x + j)            .. "," .. (c.y - dist)
        else                    return (c.x + j)            .. "," .. (c.y + d - 1 + dist)  -- S
        end
    end
    local function alongOf(card) return (card == "N" or card == "S") and w or d end

    -- Pass 1: a door sits at the CENTRE of an edge, never a corner -- so a side can only
    -- connect if a neighbour occupies the cell(s) at that edge's MIDPOINT. Rank each
    -- cardinal by (1) neighbour-at-midpoint, then (2) total adjacent overlap. This beats
    -- the old "smallest gap, ties N>S>E>W", which floated a door to a 1-cell CORNER kiss
    -- (Garden Eve's SE corner) over the full shared wall where the door actually lives.
    local best, bestCard   -- best = { atMidpoint(0/1), overlapCells }
    for _, card in ipairs({ "N", "S", "E", "W" }) do
        local along    = alongOf(card)
        local m1, m2   = math.floor((along - 1) / 2), math.ceil((along - 1) / 2)
        local atMid    = (occ[edgeKey(card, 1, m1)] or occ[edgeKey(card, 1, m2)]) and 1 or 0
        local overlap  = 0
        for j = 0, along - 1 do if occ[edgeKey(card, 1, j)] then overlap = overlap + 1 end end
        if overlap > 0 and (not best or atMid > best[1]
                            or (atMid == best[1] and overlap > best[2])) then
            best, bestCard = { atMid, overlap }, card
        end
    end
    if bestCard then return bestCard end

    -- Pass 2: nothing adjacent -> float toward the NEAREST neighbour within SCAN (ties N first).
    local bestGap, gapCard
    for _, card in ipairs({ "N", "S", "E", "W" }) do
        local along = alongOf(card)
        for dist = 1, SCAN do
            local hit = false
            for j = 0, along - 1 do if occ[edgeKey(card, dist, j)] then hit = true; break end end
            if hit then
                if not bestGap or dist < bestGap then bestGap, gapCard = dist, card end
                break
            end
        end
    end
    return gapCard or default
end
