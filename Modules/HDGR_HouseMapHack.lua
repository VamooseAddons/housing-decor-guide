-- HDG.HouseMapHack
-- ============================================================================
-- THROWAWAY PROTOTYPE -- "you are here" inside a house, drawn on the CAPTURED
-- Projects floor plan. Deliberately NOT Lattice-wired (no LayoutConfig, no
-- registered selectors, no reducer, no Modules lifecycle): it is one standalone
-- frame that reads state and draws, so it deletes in a single commit.
--
-- WHY THIS CAN WORK AT ALL
--   * The real Minimap is blank inside a house because a house interior has NO
--     uiMapID. C_Map.GetBestMapForUnit("player") returns nil there, so
--     C_Map.GetPlayerMapPosition returns nil too (Reference/HOUSING_API.md:751-756).
--     Every normal map/radar path dies at that boundary -- including HDG's own
--     LumberRadar, which is built on GetPlayerMapPosition.
--   * BUT UnitPosition("player") DOES return live coords inside a house
--     (x, y, z=0, instanceID -- verified in-game, HOUSING_API.md:753) and
--     GetPlayerFacing() works. Raw world yards, no map rect needed.
--   * ShapeAtlas dims are YARDS and its grid is cells = round(yards / 6), so the
--     world<->grid SCALE is already known (6 yd/cell). That leaves only ORIGIN
--     and ROTATION unknown -> one calibration click plus a rotate button.
--
-- WHAT IS FAKE / HACK ABOUT IT
--   * Calibration is manual and MEMORY-ONLY (a /reload drops it -- re-click).
--   * Rotation is a 4-way eyeball toggle, not derived. The house's grid north is
--     not known to be world north; this is the knob that finds out.
--   * Floor follows the Projects tab's selected floor (no floor control here).
--   * Plain CreateFrame + SetColorTexture, NOT the UI factory / theme registry.
--
-- USAGE: /hdg housemap
--   1. Capture layout in the addon first (Projects -> Architect) so a plan exists.
--   2. Stand in a room, click "Set Origin" -- anchors your current world position
--      to the selected room's centre (or the plan centre if nothing is selected).
--   3. Click "Rotate" until the dot tracks the same way you walk.

HDG = HDG or {}
HDG.HouseMapHack = HDG.HouseMapHack or {}
local H = HDG.HouseMapHack

local CONFIG = {
    W = 470, H = 596,   -- 2-line readout + up to 2 button rows + 3-line hint
    PAD = 12,
    CANVAS_H = 400,
    MIN_TILE = 5, MAX_TILE = 36,
    UPDATE = 0.1,               -- 10 fps is plenty for a walking player
    YARDS_PER_CELL = 6,         -- ShapeAtlas: cells = round(yards / 6)
    DOT = 9,
    ARROW_LEN = 16,
}

-- Calibration: world anchor <-> grid anchor, plus the grid rotation guess.
-- Memory-only on purpose (see header).
local CAL = { wx = nil, wy = nil, cx = 0, cy = 0, rot = 0, label = nil }

local COLOR = {
    ROOM      = { 0.22, 0.30, 0.38, 0.90 },
    ROOM_SEL  = { 0.30, 0.44, 0.30, 0.95 },
    ROOM_PICK = { 0.55, 0.45, 0.15, 0.95 },   -- the room you clicked = calibration anchor
    ROOM_DERIVED = { 0.20, 0.40, 0.50, 0.95 },-- preview mode: positions derived from the walk
    CANVAS_BG = { 0.05, 0.05, 0.07, 0.85 },
    FRAME_BG  = { 0.08, 0.08, 0.10, 0.95 },
    DOT       = { 0.40, 1.00, 0.40, 1.00 },
}

-- Click feedback. Direct print, NOT HDG.Log: this module is intentionally not a
-- registered Module, so it has no `logTags` entry and Log:Push would reject the
-- tag. Prints also survive the 10 fps render loop, which overwrites the readout.
local function _say(msg)
    print("|cff33ff99HDG|r HouseMap: " .. msg)
end

-- ===== Blizzard boundary =====================================================

-- The ONLY position source that survives inside a house (C_Map has no uiMapID
-- there). Returns nil outside a house, mid-loading-screen, or on taxi.
local function _snapshot()
    -- exception(boundary): bare FrameXML globals, absent in the test mock harness
    if not (_G.UnitPosition and _G.GetPlayerFacing) then return nil end
    local wx, wy, _, instance = _G.UnitPosition("player")
    if not wx then return nil end                  -- exception(boundary): nil mid-loading-screen
    local facing = _G.GetPlayerFacing()
    if not facing then return nil end              -- exception(boundary): nil on taxi / loading
    return { wx = wx, wy = wy, instance = instance, facing = facing }
end

-- ===== World -> grid =========================================================

-- WoW world axes: +x = NORTH, +y = WEST (same convention LumberRadar documents).
-- Canvas axes: +cellX = right (east), +cellY = DOWN (south).
-- So east = -dy and south = -dx before the grid-rotation guess is applied.
local function _rotateDelta(ex, sy, rot)
    if rot == 90  then return -sy, ex  end
    if rot == 180 then return -ex, -sy end
    if rot == 270 then return  sy, -ex end
    return ex, sy
end

-- Player position in GRID CELL space, or nil when uncalibrated.
local function _playerCell(snap)
    if not CAL.wx then return nil end              -- exception(nullable): not calibrated yet
    local yc = CONFIG.YARDS_PER_CELL
    local ex, sy = -(snap.wy - CAL.wy) / yc, -(snap.wx - CAL.wx) / yc
    local rx, ry = _rotateDelta(ex, sy, CAL.rot)
    return CAL.cx + rx, CAL.cy + ry
end

-- Calibration anchor, best-first: the room you CLICKED on the canvas, else the
-- room selected over in the Projects tab, else the plan's bounding-box centre.
-- The click is what makes calibration accurate -- falling through to "plan
-- centre" while you stand in some corner room offsets the dot by exactly that
-- distance, so the readout names which anchor it used.
local function _anchorCell(f, model)
    for _, r in ipairs(model.rooms) do
        if r.roomID == f.pickedRoomID then
            return r.x + r.w / 2, r.y + r.d / 2, (r.name or r.shape)
        end
    end
    for _, r in ipairs(model.rooms) do
        if r.isSelected then
            return r.x + r.w / 2, r.y + r.d / 2, (r.name or r.shape) .. " (tab)"
        end
    end
    local bb = model.bbox
    return (bb.minX + bb.maxX + 1) / 2, (bb.minY + bb.maxY + 1) / 2, "|cffff8080plan centre|r"
end

-- Cursor -> grid cell, for picking the room you're standing in.
local function _cursorCell(f, model, tile)
    local scale = f.canvas:GetEffectiveScale()
    local mx, my = GetCursorPosition()
    local left, top = f.canvas:GetLeft(), f.canvas:GetTop()
    if not (left and top) then return nil end   -- exception(boundary): unanchored frame pre-layout
    local cx = (mx / scale - left) / tile + model.bbox.minX
    local cy = (top - my / scale) / tile + model.bbox.minY
    return cx, cy
end

-- The room whose footprint contains (cx, cy), or nil for empty grid.
local function _roomAtCell(rooms, cx, cy)
    for _, r in ipairs(rooms) do
        if cx >= r.x and cx < r.x + r.w and cy >= r.y and cy < r.y + r.d then
            return r
        end
    end
    return nil   -- exception(nullable): clicked bare grid
end

-- ===== 12.1: native room identity + auto-calibration =========================
-- C_HousingLayout.GetRoomPlayerIsIn() (12.1 only) answers "which room am I in"
-- outright. Joined to the plan via placement.capturedID, which HousingObserver
-- stamps from pinFrame:GetRoomGUID() at capture (HDGR_HousingObserver.lua:485).
-- Read from the RAW placements: LayoutView/canvasModel both drop capturedID, and
-- a throwaway has no business widening a production selector to get it.

local ROTATIONS = { 0, 90, 180, 270 }

-- Running mean of world position per room slot. A mean over a walked-through
-- room converges toward its centre, which is what the solver assumes.
local SAMPLES = {}

local function _resetSamples()
    SAMPLES = {}
end

-- (slotKey, roomGUID). slotKey nil = player is in a room absent from the plan
-- (captured before it was built -> recapture). Both nil = no native API / no room.
local function _nativeRoom(state)
    -- exception(boundary): 12.1-only API, absent on 12.0.x clients
    if not (_G.C_HousingLayout and _G.C_HousingLayout.GetRoomPlayerIsIn) then return nil, nil end
    local guid = _G.C_HousingLayout.GetRoomPlayerIsIn()
    if not guid then return nil, nil end   -- exception(nullable): outside any room
    local lid = HDG.Selectors:Call("projects.activeVersionID", state, {})
    local layout = lid and state.account.projects.layouts[lid]   -- exception(nullable): pre-capture
    if not layout then return nil, guid end
    for slotKey, pl in pairs(layout.placements) do
        if pl.capturedID == guid then return slotKey, guid end
    end
    return nil, guid
end

-- Mean AND extent. The mean anchors calibration (one number per room, stable).
-- The extent midpoint estimates the room's CENTRE for layout derivation, which
-- the mean does badly: cut one corner of a big room and the mean sits in that
-- corner, while the midpoint of where you actually reached still straddles it.
local function _collectSample(slotKey, snap)
    local s = SAMPLES[slotKey]
    if not s then
        s = { sx = 0, sy = 0, n = 0,
              minx = snap.wx, maxx = snap.wx, miny = snap.wy, maxy = snap.wy }
        SAMPLES[slotKey] = s
    end
    s.sx, s.sy, s.n = s.sx + snap.wx, s.sy + snap.wy, s.n + 1
    s.minx, s.maxx = math.min(s.minx, snap.wx), math.max(s.maxx, snap.wx)
    s.miny, s.maxy = math.min(s.miny, snap.wy), math.max(s.maxy, snap.wy)
end

-- The grid-space constant C such that playerCell = C + rotate(worldCell).
-- Identical algebra to _playerCell with a zero world-anchor, so the solved
-- values drop straight into CAL with wx/wy = 0.
local function _originFor(sample, room, rot)
    local yc = CONFIG.YARDS_PER_CELL
    local wx, wy = sample.sx / sample.n, sample.sy / sample.n
    local rx, ry = _rotateDelta(-wy / yc, -wx / yc, rot)
    return (room.x + room.w / 2) - rx, (room.y + room.d / 2) - ry
end

-- Rooms on this floor that have samples, paired with them.
local function _solvable(model)
    local out = {}
    for _, r in ipairs(model.rooms) do
        local s = SAMPLES[r.roomID]
        if s then out[#out + 1] = { s = s, r = r } end
    end
    return out
end

-- Score one rotation: the spread of the per-room origin estimates. The true
-- rotation makes every room agree on one origin; wrong ones scatter.
local function _scoreRotation(obs, rot)
    local cx, cy, os = 0, 0, {}
    for i, p in ipairs(obs) do
        local ox, oy = _originFor(p.s, p.r, rot)
        os[i] = { ox, oy }
        cx, cy = cx + ox, cy + oy
    end
    cx, cy = cx / #os, cy / #os
    local err = 0
    for _, o in ipairs(os) do
        err = err + (o[1] - cx) ^ 2 + (o[2] - cy) ^ 2
    end
    return err, cx, cy
end

-- Best-fitting rotation + origin over every sampled room, or nil below 2 rooms
-- (one room fixes an origin but leaves all four rotations equally good).
local function _solve(model)
    local obs = _solvable(model)
    if #obs < 2 then return nil, #obs end
    local best, bestErr
    for _, rot in ipairs(ROTATIONS) do
        local err, cx, cy = _scoreRotation(obs, rot)
        if not bestErr or err < bestErr then
            bestErr, best = err, { rot = rot, cx = cx, cy = cy }
        end
    end
    return best, #obs, math.sqrt(bestErr / #obs)
end

-- ===== Layout derivation (the run-through -> real arrangement) ===============
-- AutoLayout packs captured rooms into tidy wrapped rows by capture order and
-- says so: "There's no position API, so rather than GUESS the real arrangement
-- ... A clean starting canvas the player drags to match their real house."
-- That premise is dead -- UnitPosition works in here. A walk-through gives each
-- room a real position, so the arrangement can be DERIVED instead of dragged.
--
-- Preview only: this computes and draws, it never writes to the plan.

-- Sampled centre of a room, in grid cells, under the current rotation.
local function _sampledCentreCell(s, rot)
    local yc = CONFIG.YARDS_PER_CELL
    local mx, my = (s.minx + s.maxx) / 2, (s.miny + s.maxy) / 2
    local ex, sy = -my / yc, -mx / yc
    return _rotateDelta(ex, sy, rot)
end

-- Derived top-left cell per sampled room, normalised so the result starts at
-- (0,0). Rooms never walked through have no position and are reported, not
-- invented -- they keep whatever the current plan says.
-- Returns { items, offX, offY, cols, rows, missing } or nil with nothing sampled.
-- offX/offY are the normalisation shift, kept so the player dot can be placed in
-- the SAME derived frame. Note this needs no CAL origin at all: rooms and player
-- are both expressed straight from sampled world coords.
local function _deriveLayout(model)
    local items, minX, minY, missing = {}, nil, nil, 0
    for _, r in ipairs(model.rooms) do
        local s = SAMPLES[r.roomID]
        if not s then
            missing = missing + 1
        else
            local cx, cy = _sampledCentreCell(s, CAL.rot)
            local x, y = cx - r.w / 2, cy - r.d / 2
            items[#items + 1] = { roomID = r.roomID, name = r.name, shape = r.shape,
                                  w = r.w, d = r.d, fx = x, fy = y }
            minX = math.min(minX or x, x)
            minY = math.min(minY or y, y)
        end
    end
    if #items == 0 then return nil end
    local cols, rows = 1, 1
    for _, it in ipairs(items) do
        it.x = math.floor(it.fx - minX + 0.5)
        it.y = math.floor(it.fy - minY + 0.5)
        cols = math.max(cols, it.x + it.w)
        rows = math.max(rows, it.y + it.d)
    end
    return { items = items, offX = minX, offY = minY,
             cols = cols, rows = rows, missing = missing }
end

-- Overlapping pairs in a derived layout. Non-zero means the derivation is off
-- (bad rotation, too little walking, or a room sampled through a doorway) --
-- real rooms never overlap, so this is the honest self-check.
local function _countOverlaps(items)
    local n = 0
    for i = 1, #items do
        for j = i + 1, #items do
            local a, b = items[i], items[j]
            if a.x < b.x + b.w and b.x < a.x + a.w
               and a.y < b.y + b.d and b.y < a.y + a.d then
                n = n + 1
            end
        end
    end
    return n
end

-- How far each derived room sits from where the plan currently puts it, in cells.
local function _driftFromPlan(model, items)
    local by, total = {}, 0
    for _, r in ipairs(model.rooms) do by[r.roomID] = r end
    for _, it in ipairs(items) do
        local r = by[it.roomID]
        if r then total = total + math.abs(it.x - r.x) + math.abs(it.y - r.y) end
    end
    return total
end

-- Tile px that fits the whole plan in the canvas.
local function _fitTile(bbox, canvasW, canvasH)
    local byW = canvasW / math.max(bbox.cols, 1)
    local byH = canvasH / math.max(bbox.rows, 1)
    return math.max(CONFIG.MIN_TILE, math.min(CONFIG.MAX_TILE, math.min(byW, byH)))
end

-- ===== Tile pool =============================================================

local function _acquireTile(f, i)
    local t = f.tiles[i]
    if not t then
        t = f.canvas:CreateTexture(nil, "ARTWORK")
        local fs = f.canvas:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        fs:SetPoint("CENTER", t, "CENTER")
        t._label = fs
        f.tiles[i] = t
    end
    return t
end

local function _hideTilesFrom(f, first)
    for i = first, #f.tiles do
        f.tiles[i]:Hide()
        f.tiles[i]._label:Hide()
    end
end

-- ===== Paint =================================================================

local function _roomColor(f, r)
    if f.showDerived then return COLOR.ROOM_DERIVED end
    if r.roomID == f.pickedRoomID then return COLOR.ROOM_PICK end
    if r.isSelected then return COLOR.ROOM_SEL end
    return COLOR.ROOM
end

local function _paintRooms(f, rooms, bb, tile)
    local n = 0
    for _, r in ipairs(rooms) do
        n = n + 1
        local t = _acquireTile(f, n)
        local c = _roomColor(f, r)
        t:ClearAllPoints()
        t:SetPoint("TOPLEFT", f.canvas, "TOPLEFT",
            (r.x - bb.minX) * tile + 1, -((r.y - bb.minY) * tile + 1))
        t:SetSize(math.max(r.w * tile - 2, 1), math.max(r.d * tile - 2, 1))
        t:SetColorTexture(c[1], c[2], c[3], c[4])
        t:Show()
        t._label:SetText(r.name or r.shape or "")
        t._label:SetShown(tile >= 14)
    end
    _hideTilesFrom(f, n + 1)
end

-- " | game says: X" on 12.1, empty string elsewhere. Names the room from the
-- slot the native GUID resolved to, so a mismatch with the hit-test is visible.
local function _nativeSuffix(f, model)
    if not f.nativeGUID then return "" end
    if not f.nativeSlot then return "   |cffff8080| game says: a room not in the plan (recapture)|r" end
    for _, r in ipairs(model.rooms) do
        if r.roomID == f.nativeSlot then
            return "   |cff80c0ff| game says: " .. (r.name or r.shape) .. "|r"
        end
    end
    return "   |cff80c0ff| game says: (room on another floor)|r"
end

-- Player cell in the DERIVED frame. Needs no CAL: same rotation, same
-- normalisation shift the rooms went through.
local function _playerCellDerived(snap, derived)
    local yc = CONFIG.YARDS_PER_CELL
    local ex, sy = -snap.wy / yc, -snap.wx / yc
    local rx, ry = _rotateDelta(ex, sy, CAL.rot)
    return rx - derived.offX, ry - derived.offY
end

-- Place the dot + facing arrow, or park them and explain why.
local function _paintPlayer(f, model, bb, tile, snap)
    if not snap then
        f.dot:Hide(); f.arrow:Hide()
        f.readout:SetText("|cffff8080No position|r -- UnitPosition returned nil (loading screen, or not in a house?)")
        return
    end
    local cx, cy
    if f.showDerived and f.derived then
        cx, cy = _playerCellDerived(snap, f.derived)
    else
        cx, cy = _playerCell(snap)
    end
    if not cx then
        f.dot:Hide(); f.arrow:Hide()
        f.readout:SetText(("Uncalibrated. Stand in a room and click Set Origin.  world %.1f, %.1f"):format(snap.wx, snap.wy))
        return
    end
    local px, py = (cx - bb.minX) * tile, (cy - bb.minY) * tile
    f.dot:ClearAllPoints()
    f.dot:SetPoint("CENTER", f.canvas, "TOPLEFT", px, -py)
    f.dot:Show()
    f.arrow:ClearAllPoints()
    f.arrow:SetPoint("BOTTOM", f.dot, "CENTER", 0, 2)
    f.arrow:SetRotation(-snap.facing - math.rad(CAL.rot))
    f.arrow:Show()
    -- "Which room am I in" WITHOUT any room API: once calibrated, the dot's cell
    -- hit-tests against the captured footprints. Same helper the anchor click uses.
    -- On 12.1 the native answer is shown beside it -- a free accuracy check on
    -- both the calibration and the hit-test.
    local here = _roomAtCell((f.showDerived and f.derived) and f.derived.items or model.rooms, cx, cy)
    f.readout:SetText(("|cffffd100In room: %s|r%s\nworld %.1f, %.1f   cell %.1f, %.1f   rot %d   anchor: %s")
        :format(here and (here.name or here.shape) or "|cff808080-- (outside any room)|r",
                _nativeSuffix(f, model),
                snap.wx, snap.wy, cx, cy, CAL.rot, CAL.label or "-"))
end

-- ===== Render tick ===========================================================

-- The panel's custom fields, declared for the type checker. They are attached in
-- the builder near the bottom of this file, which is AFTER every read up here --
-- and the LSP resolves in file order, so without this it reports `dot`/`arrow`/
-- `readout`/`canvas` as undefined fields on Frame. Pure annotation, no runtime
-- effect; it also serves as the one place the panel's shape is written down.
---@class HDG.HouseMapPanel : Frame
---@field canvas Frame
---@field dot Texture
---@field arrow Texture
---@field readout FontString
---@field model table|nil        rendered layout model for the current floor
---@field derived table|nil      preview layout when showDerived is on
---@field showDerived boolean|nil
---@field nativeSlot any         12.1 room sampling: current slot / GUID
---@field nativeGUID any
---@field tile number|nil        live tile size, read by the canvas click handler

function H:Render()
    local f = self.frame --[[@as HDG.HouseMapPanel]]
    if not (f and f:IsShown()) then return end
    local state = HDG.Store:GetState()
    local model = HDG.Selectors:Call("projects.canvasModel", state, {})
    f.model = model
    if model.empty then
        _hideTilesFrom(f, 1)
        f.dot:Hide(); f.arrow:Hide()
        f.readout:SetText("|cffff8080No captured layout for this floor.|r Capture in Projects -> Architect first.")
        return
    end
    local snap = _snapshot()
    -- Sampling runs whether or not auto-cal has been clicked: the samples have to
    -- exist BEFORE any solve, and walking around is what collects them.
    f.nativeSlot, f.nativeGUID = nil, nil
    if snap then
        f.nativeSlot, f.nativeGUID = _nativeRoom(state)
        if f.nativeSlot then _collectSample(f.nativeSlot, snap) end
    end

    -- Preview mode swaps the room set AND the frame the dot is placed in.
    if f.showDerived then f.derived = _deriveLayout(model) end
    local rooms, bb = model.rooms, model.bbox
    if f.showDerived and f.derived then
        rooms = f.derived.items
        bb = { minX = 0, minY = 0, cols = f.derived.cols, rows = f.derived.rows }
    end

    local tile = _fitTile(bb, f.canvas:GetWidth(), f.canvas:GetHeight())
    f.tile = tile   -- the canvas click handler needs the live tile size
    _paintRooms(f, rooms, bb, tile)
    _paintPlayer(f, model, bb, tile, snap)
end

-- ===== Actions ===============================================================

local function _setOrigin(f)
    local snap = _snapshot()
    if not snap then
        _say("no UnitPosition -- can't set origin here.")
        return
    end
    if not (f.model and not f.model.empty) then
        _say("no captured layout to anchor to. Capture in Projects -> Architect first.")
        return
    end
    local cx, cy, label = _anchorCell(f, f.model)
    CAL.wx, CAL.wy, CAL.cx, CAL.cy, CAL.label = snap.wx, snap.wy, cx, cy, label
    _say(("origin set -- world %.1f,%.1f = cell %.1f,%.1f (%s)")
        :format(snap.wx, snap.wy, cx, cy, label))
end

local function _cycleRotation()
    CAL.rot = (CAL.rot + 90) % 360
end

-- Tag the highlighted room with where you're standing. This is the LIVE (12.0.x)
-- substitute for GetRoomPlayerIsIn: the solver only ever needed "which room is
-- this sample from", and a click answers that just as well as the API does.
local function _addPoint(f)
    local snap = _snapshot()
    if not snap then
        _say("no UnitPosition -- can't add a point here.")
        return
    end
    if not f.pickedRoomID then
        _say("click the room you are standing in first, then Add Point.")
        return
    end
    _collectSample(f.pickedRoomID, snap)
    local n = 0
    for _ in pairs(SAMPLES) do n = n + 1 end
    _say(("point added (%d room%s tagged). "):format(n, n == 1 and "" or "s")
        .. (n >= 2 and "Press Solve." or "Walk to a different room, click it, Add Point again."))
end

-- Solve origin AND rotation from the tagged rooms. Beats rotate-and-eyeball: the
-- plan supplies each room's cell, the samples supply its world position, and two
-- of those pin the transform outright. Samples come from clicks on live, or
-- automatically from GetRoomPlayerIsIn on 12.1.
local function _autoCal(f)
    if not (f.model and not f.model.empty) then
        _say("no captured layout to solve against.")
        return
    end
    local best, n, residual = _solve(f.model)
    if not best then
        _say(("auto-cal needs 2+ visited rooms on this floor -- have %d. Walk through another.")
            :format(n))
        return
    end
    CAL.wx, CAL.wy = 0, 0   -- solved origin is absolute; _playerCell needs no world anchor
    CAL.cx, CAL.cy, CAL.rot = best.cx, best.cy, best.rot
    CAL.label = ("auto, %d rooms, %.2f fit"):format(n, residual)
    _say(("auto-calibrated from %d rooms -- rotation %d, residual %.2f cells (%.1f yd). "):format(
        n, best.rot, residual, residual * CONFIG.YARDS_PER_CELL)
        .. (residual > 1.5 and "|cffff8080High residual -- walk more rooms and redo.|r" or "Looks clean."))
end

-- Toggle the derived-layout preview and report how it compares to the plan.
local function _toggleDerived(f)
    f.showDerived = not f.showDerived
    if not f.showDerived then
        _say("preview off -- showing the saved plan.")
        return
    end
    local d = _deriveLayout(f.model)
    f.derived = d
    if not d then
        f.showDerived = false
        _say("nothing sampled yet -- walk through some rooms first.")
        return
    end
    local overlaps = _countOverlaps(d.items)
    _say(("derived %d room(s) from the walk-through, %d not yet visited. Drift vs plan: %d cells.")
        :format(#d.items, d.missing, _driftFromPlan(f.model, d.items)))
    if overlaps > 0 then
        _say(("|cffff8080%d overlapping pair(s)|r -- real rooms never overlap, so the derivation is off. "
            .. "Walk each room more fully, or try Rotate."):format(overlaps))
    else
        _say("|cff80ff80No overlaps|r -- the derived arrangement is self-consistent.")
    end
end

-- ===== Construction ==========================================================

local function _makeButton(parent, text, width, onClick)
    local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    b:SetSize(width, 22)
    b:SetText(text)
    b:SetScript("OnClick", onClick)
    return b
end

local function _buildChrome(f)
    local bg = f:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(COLOR.FRAME_BG[1], COLOR.FRAME_BG[2], COLOR.FRAME_BG[3], COLOR.FRAME_BG[4])

    local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOPLEFT", CONFIG.PAD, -CONFIG.PAD)
    title:SetText("House Map (hack)")

    local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -2, -2)
    close:SetScript("OnClick", function() f:Hide() end)
end

local function _buildCanvas(f)
    local canvas = CreateFrame("Frame", nil, f)
    canvas:SetPoint("TOPLEFT", CONFIG.PAD, -(CONFIG.PAD + 22))
    canvas:SetPoint("TOPRIGHT", -CONFIG.PAD, -(CONFIG.PAD + 22))
    canvas:SetHeight(CONFIG.CANVAS_H)
    local cbg = canvas:CreateTexture(nil, "BACKGROUND")
    cbg:SetAllPoints()
    cbg:SetColorTexture(COLOR.CANVAS_BG[1], COLOR.CANVAS_BG[2], COLOR.CANVAS_BG[3], COLOR.CANVAS_BG[4])
    f.canvas = canvas
    f.tiles = {}

    local dot = canvas:CreateTexture(nil, "OVERLAY", nil, 2)
    dot:SetSize(CONFIG.DOT, CONFIG.DOT)
    dot:SetColorTexture(COLOR.DOT[1], COLOR.DOT[2], COLOR.DOT[3], COLOR.DOT[4])
    dot:Hide()
    f.dot = dot

    local arrow = canvas:CreateTexture(nil, "OVERLAY", nil, 1)
    arrow:SetSize(2, CONFIG.ARROW_LEN)
    arrow:SetColorTexture(COLOR.DOT[1], COLOR.DOT[2], COLOR.DOT[3], 0.85)
    arrow:Hide()
    f.arrow = arrow

    -- Click a room to make it the calibration anchor (see _anchorCell).
    canvas:EnableMouse(true)
    canvas:SetScript("OnMouseUp", function()
        if not (f.model and not f.model.empty and f.tile) then return end
        local cx, cy = _cursorCell(f, f.model, f.tile)
        if not cx then return end
        local room = _roomAtCell(f.model.rooms, cx, cy)
        f.pickedRoomID = room and room.roomID or nil
        _say(room
            and ("anchor room = " .. (room.name or room.shape) .. " -- now click Set Origin while standing in it.")
            or "anchor cleared (clicked empty grid).")
    end)
end

local function _buildFooter(f)
    local readout = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    readout:SetPoint("TOPLEFT", f.canvas, "BOTTOMLEFT", 0, -10)
    readout:SetPoint("TOPRIGHT", f.canvas, "BOTTOMRIGHT", 0, -10)
    readout:SetJustifyH("LEFT")
    readout:SetWordWrap(true)
    f.readout = readout

    -- Row 1: the eyeball path. Kept as a fallback, but Solve beats it.
    local setBtn = _makeButton(f, "Set Origin", 92, function() _setOrigin(f) end)
    setBtn:SetPoint("TOPLEFT", readout, "BOTTOMLEFT", 0, -10)
    local rotBtn = _makeButton(f, "Rotate", 70, _cycleRotation)
    rotBtn:SetPoint("LEFT", setBtn, "RIGHT", 6, 0)

    -- Row 1 cont: the solved path. NOT 12.1-gated -- the solver needs room
    -- identity per sample, and on live a click supplies it (see _addPoint).
    local addBtn = _makeButton(f, "Add Point", 90, function() _addPoint(f) end)
    addBtn:SetPoint("LEFT", rotBtn, "RIGHT", 6, 0)
    local solveBtn = _makeButton(f, "Solve", 64, function() _autoCal(f) end)
    solveBtn:SetPoint("LEFT", addBtn, "RIGHT", 6, 0)
    local clearBtn = _makeButton(f, "Reset", 60, function()
        _resetSamples()
        f.showDerived, f.derived = false, nil
        _say("tagged points cleared.")
    end)
    clearBtn:SetPoint("LEFT", solveBtn, "RIGHT", 6, 0)

    -- Row 2.
    local derBtn = _makeButton(f, "Preview derived layout", 170, function() _toggleDerived(f) end)
    derBtn:SetPoint("TOPLEFT", setBtn, "BOTTOMLEFT", 0, -6)
    f.derivedBtn = derBtn

    local hint = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    hint:SetPoint("TOPLEFT", f.derivedBtn or setBtn, "BOTTOMLEFT", 0, -8)
    hint:SetPoint("RIGHT", f, "RIGHT", -CONFIG.PAD, 0)
    hint:SetJustifyH("LEFT")
    hint:SetWordWrap(true)
    hint:SetText("Walk through 2+ rooms, then Solve -- the client tags rooms automatically."
        .. "\nFallback: click your room -> Set Origin -> Rotate until the dot tracks you."
        .. "\nFloor follows the Projects tab. Calibration is memory-only -- a /reload clears it.")
end

local function _buildFrame()
    local f = CreateFrame("Frame", "HDGHouseMapHackFrame", UIParent)
    f:SetSize(CONFIG.W, CONFIG.H)
    f:SetPoint("CENTER")
    f:SetFrameStrata("HIGH")
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    _buildChrome(f)
    _buildCanvas(f)
    _buildFooter(f)

    f._accum = 0
    f:SetScript("OnUpdate", function(self, elapsed)
        self._accum = self._accum + elapsed
        if self._accum < CONFIG.UPDATE then return end
        self._accum = 0
        H:Render()
    end)
    f:Hide()
    return f
end

-- ===== Entry point ===========================================================

function H:Toggle()
    self.frame = self.frame or _buildFrame()
    if self.frame:IsShown() then
        self.frame:Hide()
    else
        self.frame:Show()
        self:Render()
    end
end
