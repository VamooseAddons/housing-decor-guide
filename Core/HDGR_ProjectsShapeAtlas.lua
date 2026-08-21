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
    -- ===== Themed rooms (12.1) ==========================================
    -- Generated from DB2, not typed: HouseRoom.RoomWmoDataID -> RoomWmoData
    -- BoundingBox/Height for dims, cells = round(yards/6), budget = WeightCost,
    -- atlas = UiTextureAtlasElement.Name. The same derivation reproduces every
    -- shape above to the yard. Full tables + method:
    -- docs/HDGR_ROOM_CATALOG_GAP_2026-08-21.md
    --
    -- ONE DOOR EACH, and the room rotates to whatever door you connect it to
    -- (owner, in-game 2026-08-21) -- the same model as the circle gardens above.
    -- This is why they are separate entries rather than aliases of square_s/m/l:
    -- those carry four doors, and each themed room has its own real height, which
    -- the palette tooltip prints.
    --
    -- floors: a storey is ~21yd, CONFIRMED in-game 2026-08-21 -- the five rooms
    -- carrying floors = 2 below (22/27/27/31/33yd) are the ones the owner saw
    -- spanning two floors, and no others. That also rules out the 11yd-per-storey
    -- reading, which would have made ten more rooms multi-floor and the circle
    -- gardens six. Everything at or under one storey omits the field (= 1).
    org_stonepitroom         = { atlas = "org_stonepitRoom",                   dims = {24,23,18},  cells = {4, 4}, doors = {"N"}, budget = 5   },  -- 151 Orgrimmar Stone Pit Room
    stormwind_kitchen        = { atlas = "stormwind_kitchen",                  dims = {24,23,10},  cells = {4, 4}, doors = {"N"}, budget = 5   },  -- 277 Stormwind Kitchen
    stormwind_displayroom    = { atlas = "stormwind_displayroom",              dims = {24,23,7},  cells = {4, 4}, doors = {"N"}, budget = 5   },  -- 281 Stormwind Display Room
    silvermoon_displayroom   = { atlas = "silvermoon_displayroom",             dims = {25,23,14},  cells = {4, 4}, doors = {"N"}, budget = 5   },  -- 286 Silvermoon Display Room
    belameth_theater         = { atlas = "belameth_theater",                   dims = {24,23,17},  cells = {4, 4}, doors = {"N"}, budget = 5   },  -- 289 Bel'ameth Theater
    belameth_bedroom         = { atlas = "belameth_bedroom",                   dims = {25,24,14},  cells = {4, 4}, doors = {"N"}, budget = 5   },  -- 290 Bel'ameth Nestled Bedroom
    org_displayroom          = { atlas = "org_displayroom",                    dims = {23,23,16},  cells = {4, 4}, doors = {"N"}, budget = 5   },  -- 294 Orgrimmar Display Room
    silvermoon_smallstudy    = { atlas = "silvermoon_smallstudy",              dims = {24,23,13},  cells = {4, 4}, doors = {"N"}, budget = 5   },  -- 307 Silvermoon Small Study
    stormwind_armory         = { atlas = "stormwind_armory",                   dims = {36,37,12},  cells = {6, 6}, doors = {"N"}, budget = 12  },  -- 273 Stormwind Armory
    silvermoon_armory        = { atlas = "silvermoon_armory",                  dims = {36,34,13},  cells = {6, 6}, doors = {"N"}, budget = 12  },  -- 283 Silvermoon Armory
    belameth_meetingroom     = { atlas = "belameth_meetingroom",               dims = {36,34,18},  cells = {6, 6}, doors = {"N"}, budget = 12  },  -- 288 Bel'ameth Meeting Room
    org_theaterroom          = { atlas = "org_theaterRoom",                    dims = {37,37,19},  cells = {6, 6}, doors = {"N"}, budget = 12  },  -- 292 Orgrimmar Theater
    org_councilroom          = { atlas = "org_councilroom",                    dims = {48,48,33},  cells = {8, 8}, doors = {"N"}, budget = 20, floors = 2 },  -- 132 Orgrimmar Council Room
    stormwind_grandhall      = { atlas = "stormwind_grandhall",                dims = {47,45,11},  cells = {8, 8}, doors = {"N"}, budget = 20  },  -- 282 Stormwind Grand Hall
    silvermoon_loftystudy    = { atlas = "silvermoon_loftystudy",              dims = {49,48,31},  cells = {8, 8}, doors = {"N"}, budget = 20, floors = 2 },  -- 285 Silvermoon Lofty Study
    belameth_templeroom      = { atlas = "belameth_templeroom",                dims = {49,47,22},  cells = {8, 8}, doors = {"N"}, budget = 20, floors = 2 },  -- 287 Bel'ameth Temple Room
    -- The two barns are the SAME layout and height, only the theme differs
    -- (owner, in-game 2026-08-21) -- so they share geometry, and stay two entries
    -- because a player picks between them by theme. DB2 disagrees with itself by
    -- one yard on width (45 vs 44), which straddles the cell boundary (7.5 vs
    -- 7.33) and would otherwise have given identical rooms 8x7 and 7x7. Both take
    -- the larger measurement: a footprint that under-reserves overlaps its
    -- neighbour, which is not something a player can drag straight.
    westfall_barn_autumnal   = { atlas = "Full_Layout_Fall_Prefab_L01",        dims = {45,43,27},  cells = {8, 7}, doors = {"N"}, budget = 18, floors = 2 },  -- 400 Autumnal Westfall Barn
    westfall_barn_springtime = { atlas = "Full_Layout_Fall_Prefab_L02",        dims = {45,43,27},  cells = {8, 7}, doors = {"N"}, budget = 18, floors = 2 },  -- 401 Springtime Westfall Barn

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
    -- Themed rooms, in Blizzard's own HouseRoom.SortPriority order so the palette
    -- reads the way the in-game catalog does. Being absent here is why they could
    -- only ever arrive via a capture -- projects.paletteShapes walks ListShapes,
    -- so a player had no way to PLACE one.
    -- Autumnal
    "westfall_barn_autumnal",
    -- Springtime
    "westfall_barn_springtime",
    -- Orgrimmar
    "org_displayroom",
    "org_stonepitroom",
    "org_theaterroom",
    "org_councilroom",
    -- Stormwind
    "stormwind_displayroom",
    "stormwind_kitchen",
    "stormwind_armory",
    "stormwind_grandhall",
    -- Silvermoon
    "silvermoon_displayroom",
    "silvermoon_smallstudy",
    "silvermoon_armory",
    "silvermoon_loftystudy",
    -- Bel'ameth
    "belameth_bedroom",
    "belameth_theater",
    "belameth_meetingroom",
    "belameth_templeroom",
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
    -- Themed rooms: Blizzard's own names, verbatim from HouseRoom.Name_lang.
    -- Without an entry here GetLabel falls through to the shapeID, and a slug is
    -- one unbroken token -- so the canvas truncated "belameth_bedr..." where a
    -- real name would simply wrap, the way "Stairwell Room (Empty)" does.
    westfall_barn_autumnal   = "Autumnal Westfall Barn",
    westfall_barn_springtime = "Springtime Westfall Barn",
    org_displayroom          = "Orgrimmar Display Room",
    org_stonepitroom         = "Orgrimmar Stone Pit Room",
    org_theaterroom          = "Orgrimmar Theater",
    org_councilroom          = "Orgrimmar Council Room",
    stormwind_displayroom    = "Stormwind Display Room",
    stormwind_kitchen        = "Stormwind Kitchen",
    stormwind_armory         = "Stormwind Armory",
    stormwind_grandhall      = "Stormwind Grand Hall",
    silvermoon_displayroom   = "Silvermoon Display Room",
    silvermoon_smallstudy    = "Silvermoon Small Study",
    silvermoon_armory        = "Silvermoon Armory",
    silvermoon_loftystudy    = "Silvermoon Lofty Study",
    belameth_bedroom         = "Bel'ameth Nestled Bedroom",
    belameth_theater         = "Bel'ameth Theater",
    belameth_meetingroom     = "Bel'ameth Meeting Room",
    belameth_templeroom      = "Bel'ameth Temple Room",
}
function M.GetLabel(shapeID) return NAME_OVERRIDES[shapeID] or shapeID end

-- Live catalog recordID (DB2 HouseRoom id) -> ShapeAtlas shapeID. The Layout-mode
-- catalog searcher returns rooms keyed by recordID; this bridges them to the geometry
-- here (geometry stays in ShapeAtlas; the catalog supplies live name/icon/stock/cost --
-- which is why a themed room needs no atlas entry of its own, only a mapping).
-- Entry is the structural anchor, NOT a catalog entry. recordIDs are stable DB2 ids.
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

    -- ===== Themed rooms (12.1) ==========================================
    -- Added 2026-08-21 after reganart asked why they were missing from the
    -- Architect. Analysis + DB2 tables: docs/HDGR_ROOM_CATALOG_GAP_2026-08-21.md
    --
    -- `HouseRoom.Field_12_0_0_63967_001` is a ROOM CLASS and answers "is this a
    -- room at all" from data rather than from a hand-kept skip list:
    --   1 = standard modular room, 3 = themed room, 0 = whole-house layout.
    -- Worth re-reading it when a patch adds rooms -- class 3 is the set below.
    --
    -- !! FLOORS ARE UNVERIFIED. Every entry defaults to a 1-floor span, but the
    -- heights say some of these are taller: 22yd (Bel'ameth Temple), 27 (both
    -- barns), 31 (Silvermoon Lofty Study), 33 (Orgrimmar Council) against 11 for
    -- a standard square. DB2 has no floor-span column -- the class field is not
    -- one (it reads 3 for a 7yd room) -- and the two candidate rules disagree:
    -- height/11 makes the circle gardens 6 floors when they are known to be 3,
    -- height/21 fits the gardens exactly. One in-game look settles it. Left at 1
    -- meanwhile because under-reserving lets a player drag a bad placement
    -- straight, while over-reserving makes valid layouts impossible to express.
    [151] = "org_stonepitroom",         -- Orgrimmar Stone Pit Room
    [277] = "stormwind_kitchen",        -- Stormwind Kitchen
    [281] = "stormwind_displayroom",    -- Stormwind Display Room
    [286] = "silvermoon_displayroom",   -- Silvermoon Display Room
    [289] = "belameth_theater",         -- Bel'ameth Theater
    [290] = "belameth_bedroom",         -- Bel'ameth Nestled Bedroom
    [294] = "org_displayroom",          -- Orgrimmar Display Room
    [307] = "silvermoon_smallstudy",    -- Silvermoon Small Study
    [273] = "stormwind_armory",         -- Stormwind Armory
    [283] = "silvermoon_armory",        -- Silvermoon Armory
    [288] = "belameth_meetingroom",     -- Bel'ameth Meeting Room
    [292] = "org_theaterroom",              -- Orgrimmar Theater
    [132] = "org_councilroom",          -- Orgrimmar Council Room
    [282] = "stormwind_grandhall",      -- Stormwind Grand Hall
    [285] = "silvermoon_loftystudy",    -- Silvermoon Lofty Study
    [287] = "belameth_templeroom",      -- Bel'ameth Temple Room
    [400] = "westfall_barn_autumnal",   -- Autumnal Westfall Barn
    [401] = "westfall_barn_springtime", -- Springtime Westfall Barn

    -- DELIBERATELY UNMAPPED, do not "fix" these by adding geometry:
    --   113 Full_Layout_Prefab_S  / 291 Full_Layout_Rugged_Prn -- WeightCost 100.
    --     That is a whole-house layout, not a room; it does not belong in the
    --     room palette. Ruling still open.
    --   296 Sky Blue Riverside Room / 297 Verdant Riverside Room -- WeightCost 20
    --     but NO RoomWmoDataID and NO atlas element in DB2. Unreleased, or a data
    --     gap. Nothing to derive from, so nothing is invented.
}
function M.ShapeForRecordID(recordID) return RECORD_TO_SHAPE[recordID] end
