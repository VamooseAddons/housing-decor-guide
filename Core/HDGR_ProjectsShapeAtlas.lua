-- HDG.Projects.ShapeAtlas
-- ============================================================================
-- Pure data: room shape ID -> atlas element + real dimensions + footprint cells
-- + door cardinals + placement budget. No WoW API.

HDG = HDG or {}
HDG.Projects = HDG.Projects or {}
HDG.Projects.ShapeAtlas = HDG.Projects.ShapeAtlas or {}
local M = HDG.Projects.ShapeAtlas

-- NOTE: Blizzard misspells "Octogon" (Octagon). Atlas names use the misspelling.
--
-- dims = {width, depth, height} in YARDS, from DB2 RoomWmoData.BoundingBox
-- (HouseRoom.RoomWmoDataID -> RoomWmoData, build 12.0.7.67808, wago.tools).
-- cells = {w, d} canvas-grid BOUNDING BOX at HALF-MODULE resolution (round(yards/6);
-- a square module = 2 cells: Tiny~2, Small~4, Med~6, Large~8). The half-module grid
-- makes closet/entry a natural 2x1 (1 module wide x half-module tall) -- so "half
-- height" falls out of the footprint, no special-case render. mask = the OCCUPIED
-- cells within the bbox (canonical orientation, origin top-left, +x East/+y South);
-- omitted = the shape fills its bbox (every convex room). Non-convex (cross/L/T)
-- carry an explicit {x,y} cell mask.
-- budget = DB2 HouseRoom.WeightCost. circle = true => render as a disc (gardens).

local SHAPES = {
    closet_xs        = { atlas = "Layout_Closet_XS_Icon",                 dims = {5,11,7},   cells = {2, 1}, doors = {"N","S"},          budget = 1  },
    square_xs        = { atlas = "Layout_Square_XS_Icon",                 dims = {11,11,7},  cells = {2, 2}, doors = {"N","E","S","W"},  budget = 2  },
    square_s         = { atlas = "Layout_Square_S_Icon",                  dims = {23,23,11}, cells = {4, 4}, doors = {"N","E","S","W"},  budget = 5  },
    square_m         = { atlas = "Layout_Square_M_Icon",                  dims = {35,35,11}, cells = {6, 6}, doors = {"N","E","S","W"},  budget = 12 },
    square_l         = { atlas = "Layout_Square_L_Icon",                  dims = {47,47,11}, cells = {8, 8}, doors = {"N","E","S","W"},  budget = 20 },
    octagon_s        = { atlas = "Layout_Octogon_S_Icon",                 dims = {24,24,11}, cells = {4, 4}, doors = {"N","E","S","W"},  budget = 4  },
    octagon_m        = { atlas = "Layout_Octogon_M_Icon",                 dims = {36,36,11}, cells = {6, 6}, doors = {"N","E","S","W"},  budget = 8  },
    octagon_l        = { atlas = "Layout_Octogon_L_Icon",                 dims = {48,48,11}, cells = {8, 8}, doors = {"N","E","S","W"},  budget = 16 },
    -- Non-convex: explicit {x,y} footprint mask.
    -- doors at the two OPEN ENDS of the L (tall-arm top N + foot right E), NOT the long
    -- left side -- so rot=2 -> {S,W}: spine-bottom + bar-left (verified in-game).
    l_shape          = { atlas = "Layout_L-Shape_S_Icon",                 dims = {17,17,7},  cells = {3, 3}, doors = {"N","E"},          budget = 3,
                         -- 3x3 L (was 4x4): tall arm cols0-1 + foot row1-2 to col2. Door N = tall-arm top, E = foot right.
                         mask = { {0,0},{1,0}, {0,1},{1,1},{2,1}, {0,2},{1,2},{2,2} } },
    -- doors: bar-left (W) + bar-right (E) + STEM-BOTTOM (S). The wide bar's TOP is a
    -- solid wall -- the door is on the spine, NOT the bar top (verified in-game).
    t_shape          = { atlas = "Layout_T-Shape_S_Icon",                 dims = {17,23,7},  cells = {4, 3}, doors = {"S","E","W"},      budget = 3,
                         -- 4w x 3h T (was 6x4): bar rows0-1 (top wall = N), stem row2 cols1-2 (S door). E/W = bar ends.
                         mask = { {0,0},{1,0},{2,0},{3,0}, {0,1},{1,1},{2,1},{3,1}, {1,2},{2,2} } },
    -- 4x4 plus (total width 4 cells): 2x2 center + 1-deep arms. Was 6x6
    -- (2-deep arms) -- 2 cells too wide on both axes (verified in-game by Regan).
    cross_shape      = { atlas = "Layout_Cross_S_Icon",                   dims = {23,23,7},  cells = {4, 4}, doors = {"N","E","S","W"},  budget = 4,
                         mask = { {1,0},{2,0}, {0,1},{1,1},{2,1},{3,1}, {0,2},{1,2},{2,2},{3,2}, {1,3},{2,3} } },
    hallway          = { atlas = "Layout_Hallway_S_Icon",                 dims = {23,11,7},  cells = {4, 2}, doors = {"E","W"},          budget = 3  },
    -- floors = vertical span of ONE RECORD (omitted = 1). SECTIONS model
    -- (owner-ruled + capture-verified 2026-08-10, solver spec SS10): the three
    -- stair shapes materialize IN-GAME as one section record per floor, each with
    -- its own roomGUID, each occupying only its own floor -- so their span here
    -- is 1. (Placing one in-game creates 2 sections at once; "Expand Stairwell
    -- up" mints another. The PLANNER mirrors that by stamping floors=2 on the
    -- single planned record.) Gardens are genuinely ONE record whose volume
    -- projects up 3 floors (open sky above -- no upper sections, no support).
    tall_room        = { atlas = "Layout_TallRoom_S_Icon",                dims = {23,23,14}, cells = {4, 4}, doors = {"N","E","S","W"},  budget = 6 },
    -- Stairwell: ONE door -- the connecting side (mirror flips it W<->E). Every
    -- section shares the shape, so the door lands at the same position upstairs.
    -- (The empty "Stairwell Room" with doors on all 4 sides is tall_room above.)
    staircase        = { atlas = "Layout_Staircase_S_Icon",               dims = {23,23,15}, cells = {4, 4}, doors = {"W"},              budget = 7 },
    staircase_mirror = { atlas = "Layout_Staircase_Mirrored_S_Icon",      dims = {23,23,15}, cells = {4, 4}, doors = {"E"},              budget = 7 },
    circle_evening   = { atlas = "Full_Layout_Artisinal_Garden_Evening",  dims = {48,50,64}, cells = {8, 8}, doors = {"N"},              budget = 8, circle = true, floors = 3 },
    circle_daylight  = { atlas = "Full_Layout_Artisinal_Garden_Daylight", dims = {48,50,64}, cells = {8, 8}, doors = {"N"},              budget = 8, circle = true, floors = 3 },
    -- Entry is the structural anchor -- no placement budget. 2x1 like the closet.
    entry            = { atlas = "Layout_Closet_XS_Icon",                 dims = {5,11,7},   cells = {2, 1}, doors = {"N"},              budget = 0  },
}

function M.GetShape(shapeID)  return SHAPES[shapeID] end
function M.GetBudget(shapeID) local s = SHAPES[shapeID]; return s and s.budget or 0 end
function M.GetAtlas(shapeID)  local s = SHAPES[shapeID]; return s and s.atlas end
function M.GetCells(shapeID)  local s = SHAPES[shapeID]; return s and s.cells or { 1, 1 } end
function M.GetDims(shapeID)   local s = SHAPES[shapeID]; return s and s.dims end   -- {w,d,h} yards (DB2 RoomWmoData)
function M.GetFloors(shapeID) local s = SHAPES[shapeID]; return (s and s.floors) or 1 end  -- one RECORD's vertical span (stair sections = 1; gardens = 3)

-- The stair family (sections model, solver spec SS10): the ONE predicate every
-- consumer shares -- pin matching, planned-span stamping, the expand menu.
-- Adding a stair-like shape here updates all of them together.
local STAIR_SHAPES = { staircase = true, staircase_mirror = true, tall_room = true }
function M.IsStairShape(shapeID) return STAIR_SHAPES[shapeID] == true end

-- Planned-record span for a shape the PLANNER places as a single record: the
-- in-game placement action creates this many floors at once (sections model,
-- solver spec SS10). Captured records never use this -- their sections arrive
-- one per floor.
function M.GetPlannedSpan(shapeID)
    if STAIR_SHAPES[shapeID] then return 2 end
    return M.GetFloors(shapeID)
end
function M.GetDoors(shapeID)  local s = SHAPES[shapeID]; return s and s.doors or {} end
function M.IsKnown(shapeID)   return SHAPES[shapeID] ~= nil end
function M.IsCircle(shapeID)  local s = SHAPES[shapeID]; return (s and s.circle) == true end

-- Footprint mask: {x,y} occupied cells in canonical orientation (origin top-left,
-- +x East / +y South). Convex shapes (no explicit mask) fill their whole bbox.
function M.GetMask(shapeID)
    local s = SHAPES[shapeID]
    if not s then return { { 0, 0 } } end
    if s.mask then return s.mask end
    local w, d, out = s.cells[1], s.cells[2], {}
    for y = 0, d - 1 do for x = 0, w - 1 do out[#out + 1] = { x, y } end end
    return out
end

-- Clockwise quarter-turn primitives (r in 0..3).
local CW = { N = "E", E = "S", S = "W", W = "N" }
function M.RotateCardinal(card, r)
    for _ = 1, (r % 4) do card = CW[card] end
    return card
end

-- Rotate a {w,d} bbox -- odd quarter-turns swap the axes.
function M.RotateCells(cells, r)
    if (r % 2) == 1 then return { cells[2], cells[1] } end
    return { cells[1], cells[2] }
end

-- Rotate a mask CW by r quarter-turns inside its (w x d) bbox -> new {x,y} list.
function M.RotateMask(mask, r, w, d)
    r = r % 4
    if r == 0 then return mask end
    local out = {}
    for _, c in ipairs(mask) do
        local x, y, cw, cd = c[1], c[2], w, d
        for _ = 1, r do
            x, y  = cd - 1 - y, x   -- one CW step in a (cw x cd) grid
            cw, cd = cd, cw          -- bbox axes swap after each turn
        end
        out[#out + 1] = { x, y }
    end
    return out
end

-- Smallest CW quarter-turn whose rotated canonical door-set equals the room's
-- captured door cardinals; 0 if none match (symmetric shapes, or capture noise --
-- exception(boundary): rotation is cosmetic, never inferred past a clean set-equality).
local function _setEq(a, b)
    if #a ~= #b then return false end
    local seen = {}
    for _, v in ipairs(a) do seen[v] = true end
    for _, v in ipairs(b) do if not seen[v] then return false end end
    return true
end
function M.InferRotation(shapeID, capturedCardinals)
    local s = SHAPES[shapeID]
    if not s or not s.doors or not capturedCardinals then return 0 end
    for r = 0, 3 do
        local rot = {}
        for _, c in ipairs(s.doors) do rot[#rot + 1] = M.RotateCardinal(c, r) end
        if _setEq(rot, capturedCardinals) then return r end
    end
    return 0
end

-- Door midpoint in CELL-BOUNDARY coords: center of the shape's outer edge facing
-- `cardinal`, read from the (rotated) mask so non-convex shapes land on the real
-- footprint edge (not the bounding-box side midpoint). Two opposite-facing doors
-- sharing a midpoint = connected. Shared by the canvas orb render AND the
-- connectivity solver's door-to-door alignment.
-- Every shipped shape's door-run has EVEN length (integer midpoints) -- asserted:
-- an odd run means a new shape broke the invariant the solver's alignment needs.
function M.DoorMid(cardinal, x, y, w, d, mask)
    -- math.floor keeps midpoints INTEGER in Lua 5.4 (where 4/2 is the float 2.0
    -- and would poison "x,y" cell keys); the even-run invariant makes it exact.
    if not mask or #mask == 0 then
        if cardinal == "N" then return x + math.floor(w / 2), y end
        if cardinal == "S" then return x + math.floor(w / 2), y + d end
        if cardinal == "E" then return x + w, y + math.floor(d / 2) end
        return x, y + math.floor(d / 2)   -- W
    end
    local vertical = (cardinal == "E" or cardinal == "W")   -- door on a vertical (E/W) edge?
    local outward  = (cardinal == "E" or cardinal == "S")   -- extreme is a MAX (else MIN)?
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
    if ((hi - lo) % 2) ~= 0 then
        error(("ShapeAtlas.DoorMid: odd door-run (%d) on %s edge -- even-run atlas invariant broken"):format(hi - lo, cardinal))
    end
    local mid = math.floor((lo + hi) / 2)
    if cardinal == "N" then return x + mid,      y + rank end
    if cardinal == "S" then return x + mid,      y + rank + 1 end
    if cardinal == "E" then return x + rank + 1, y + mid end
    return x + rank, y + mid   -- W
end

-- Rotated footprint for a room from its shape + captured door cardinals (nil ->
-- rotation 0). Shared by AutoLayout's grid-pack and the Connectivity solver.
function M.FootprintFor(shape, cardinals)
    local cells = M.GetCells(shape)
    local rot   = M.InferRotation(shape, cardinals)
    local rc    = M.RotateCells(cells, rot)
    local mask  = M.RotateMask(M.GetMask(shape), rot, cells[1], cells[2])
    return rc[1], rc[2], mask, rot
end

-- Stable palette display order, grouped by family. Entry (the structural anchor) is
-- listed first, but the palette selector filters it out -- it's captured, never placed.
local PALETTE_ORDER = {
    "entry",
    "closet_xs",
    "square_xs", "square_s", "square_m", "square_l",
    "octagon_s", "octagon_m", "octagon_l",
    "l_shape", "t_shape", "cross_shape",
    "hallway", "tall_room",
    "staircase", "staircase_mirror",
    "circle_evening", "circle_daylight",
}
function M.ListShapes() return PALETTE_ORDER end

local NAME_OVERRIDES = {
    entry = "Entry",
    closet_xs = "Closet", square_xs = "Square XS", square_s = "Square S",
    square_m = "Square M", square_l = "Square L", octagon_s = "Octagon S",
    octagon_m = "Octagon M", octagon_l = "Octagon L", l_shape = "L-Shape",
    t_shape = "T-Shape", cross_shape = "Cross", hallway = "Hallway",
    tall_room = "Stairwell Room (Empty)", staircase = "Stairwell (Left)", staircase_mirror = "Stairwell (Right)",
    circle_evening = "Garden (Eve)", circle_daylight = "Garden (Day)",
}
function M.GetLabel(shapeID) return NAME_OVERRIDES[shapeID] or shapeID end

-- Live catalog recordID (DB2 HouseRoom id) -> ShapeAtlas shapeID. The Layout-mode
-- catalog searcher returns rooms keyed by recordID; this bridges them to the geometry
-- here (geometry stays in ShapeAtlas; the catalog supplies live name/icon/stock/cost).
-- The 20 placeable rooms -- Entry is the structural anchor, NOT a catalog entry. The 3
-- prefab rooms (113/132/151) have no ShapeAtlas geometry -> nil (the catalog's own
-- iconAtlas is the render fallback). recordIDs are stable DB2 ids.
local RECORD_TO_SHAPE = {
    [1]   = "square_s",        [2]   = "hallway",          [3]   = "closet_xs",
    [6]   = "t_shape",         [7]   = "square_xs",        [8]   = "l_shape",
    [9]   = "octagon_m",       [10]  = "staircase",        [11]  = "square_m",
    [12]  = "square_l",        [13]  = "cross_shape",      [14]  = "octagon_s",
    [15]  = "octagon_l",       [48]  = "tall_room",        [50]  = "staircase_mirror",
    [223] = "circle_daylight", [233] = "circle_evening",
    -- Entry is not a catalog room, but it DOES carry a HouseRoom recordID in its
    -- roomGUID (Housing-2-46-0, verified live 2026-08-10 via the capture tap).
    [46]  = "entry",
}
function M.ShapeForRecordID(recordID) return RECORD_TO_SHAPE[recordID] end
