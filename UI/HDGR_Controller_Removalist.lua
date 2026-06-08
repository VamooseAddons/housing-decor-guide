-- HDG.RemovalistController
-- ============================================================================
-- Removalist plot-move orientation planner (Projects sub-view).
-- PHASE 1: Alliance/Horde faction toggle + plot list. The map canvas, facing
-- diagrams, source/target selection and the rotation result land in later phases
-- (see docs/REMOVALIST_DESIGN.md).

HDG = HDG or {}
HDG.Rows = HDG.Rows or {}
HDG.RemovalistController = HDG.RemovalistController or {}

local RemovalistController = HDG.RemovalistController
local A = HDG.Constants.ACTIONS

-- ===== Plot row =============================================================
-- "Plot N" today. The A/B/C/D letter chip + source/target selection highlight
-- come in later phases (selection state already reserved in the Store bucket).

local SRC_RGB = { 0.25, 0.85, 0.35 }   -- source = green (matches the map pin)
local TGT_RGB = { 0.95, 0.75, 0.20 }   -- target = gold  (matches the map pin)

-- Community "PLOT ORIENTATION KEY" letter colors (AoA reference) -- used for the plot-list
-- letter swatch and the non-selected map pins, so both mirror the community key.
local LETTER_RGB = {
    A = { 0.27, 0.53, 0.93 },   -- blue   (0 deg)
    B = { 0.93, 0.80, 0.28 },   -- yellow (90 deg CW)
    C = { 0.45, 0.78, 0.37 },   -- green  (180 deg)
    D = { 0.94, 0.42, 0.80 },   -- pink   (270 deg CW)
}
local UNLETTERED_RGB = { 0.60, 0.60, 0.60 }   -- plot with no community letter yet

-- A/B/C/D -> degrees. Shared by the map house-arrow + the facing diagram.
local LETTER_DEG = { A = 0, B = 90, C = 180, D = 270 }

-- Cornerstone atlas -- marks the stone on the map AND in the facing diagram.
local CORNERSTONE_ATLAS = "housefinder_forsale-plot-icon-highlight"

-- House-facing arrow on the map (atlas). Facing = the cornerstone direction rotated by
-- the letter (A faces the cornerstone, +1 quarter-turn CW per letter). Two flippable
-- knobs if the in-game read is reversed: MAP_ARROW_TURN (letter turn sign) and
-- MAP_ARROW_BASE (the atlas's own default heading; +pi/2 assumes it points DOWN).
local MAP_ARROW_ATLAS = "housing-floor-arrow-down-default"
local MAP_ARROW_TURN  = -1
local MAP_ARROW_BASE  = math.pi / 2

local function _layoutPlotRow(row)
    HDG.UI:EnsureRowChrome(row)
    row._letterSwatch = row:CreateTexture(nil, "OVERLAY")   -- community letter color, left edge
    row._letterSwatch:SetSize(11, 11)
    row._letterSwatch:SetPoint("LEFT", row, "LEFT", 8, 0)
    row._nameFs = HDG.UI.RowText(row, "body", "Text", "LEFT")
    row._nameFs:SetWordWrap(false)   -- single line; long labels truncate rather than wrap
    row._dot = row:CreateTexture(nil, "OVERLAY")
    row._dot:SetSize(9, 9)
    row._dot:SetPoint("RIGHT", row, "RIGHT", -8, 0)
end

local function _paintPlotRow(row, ed)
    row._nameFs:SetPoint("LEFT",  row, "LEFT",  26, 0)    -- after the letter swatch
    row._nameFs:SetPoint("RIGHT", row, "RIGHT", -22, 0)   -- leave room for the source/target dot
    row._nameFs:SetText(ed.label)
    local lc = LETTER_RGB[ed.letter]                      -- exception(nullable): plot may be unlettered (community gap)
    if lc then
        row._letterSwatch:SetColorTexture(lc[1], lc[2], lc[3], 1); row._letterSwatch:Show()  -- scheme-invariant: community letter color
    else
        row._letterSwatch:Hide()
    end
    if ed.isSource then
        row._dot:SetColorTexture(SRC_RGB[1], SRC_RGB[2], SRC_RGB[3], 1); row._dot:Show()  -- scheme-invariant: source marker, mirrors the map pin
    elseif ed.isTarget then
        row._dot:SetColorTexture(TGT_RGB[1], TGT_RGB[2], TGT_RGB[3], 1); row._dot:Show()  -- scheme-invariant: target marker, mirrors the map pin
    else
        row._dot:Hide()
    end
end

HDG.Rows:Register("removalistPlotRow", {
    font    = "body",
    height  = 22,
    factory = HDG.UI.MakeRowFactory({
        laidOutTag = "_removalistRowLaidOut",
        layout     = _layoutPlotRow,
        paint      = _paintPlotRow,
        selectedFn = function(ed) return ed.isSource or ed.isTarget end,
        wire       = function(row, ed)
            row:SetScript("OnClick", function()
                HDG.Store:Dispatch({ type = A.REMOVALIST_PICK_PLOT, payload = { plot = ed.plot } })
            end)
        end,
        resetText  = { "_nameFs" },
    }),
    key     = function(ed) return tostring(ed.plot) end,
})

-- ===== Map canvas (Phase 2) =================================================
-- Custom widget kind "removalistMap": a host frame that MapRenderer tiles the
-- neighborhood uiMap into, then we project the plots onto the returned canvas.
-- Driven by binding { model = removalist.mapModel }; dispatch.push re-renders on
-- model change (same pattern as projectsCanvas). 2b = plot pins; 2c = rects+arrows.

-- ----- Projection: world coords -> canvas pixels (ported from VN_PlotMap) ----
-- C_Map.GetWorldPosFromMapPos returns worldPos.x = world Y axis, .y = world X
-- axis -- so a plot's world Y maps to the map's X, its world X to the map's Y.
local CORNERSTONE_TO_CENTER = 35   -- yards: cornerstone -> plot centre, along yaw

local function _worldBoundsForMap(uiMap)
    local _, p00 = C_Map.GetWorldPosFromMapPos(uiMap, CreateVector2D(0, 0))   -- exception(boundary): Blizzard map API
    local _, p11 = C_Map.GetWorldPosFromMapPos(uiMap, CreateVector2D(1, 1))   -- exception(boundary): Blizzard map API
    if not (p00 and p11) then return nil end
    return { wY_top = p00.x, wY_bot = p11.x, wX_lft = p00.y, wX_rgt = p11.y }
end

-- Plot CENTRE in normalized map coords (0..1, top-left origin).
local function _projectNorm(plot, bounds)
    local cx = plot.x + CORNERSTONE_TO_CENTER * math.cos(plot.yaw)   -- world X of plot centre
    local cy = plot.y + CORNERSTONE_TO_CENTER * math.sin(plot.yaw)   -- world Y of plot centre
    local spanX = bounds.wX_rgt - bounds.wX_lft
    local spanY = bounds.wY_bot - bounds.wY_top
    if spanX == 0 or spanY == 0 then return 0.5, 0.5 end
    return (cy - bounds.wX_lft) / spanX,    -- world Y -> map X (nx)
           (cx - bounds.wY_top) / spanY     -- world X -> map Y (ny)
end

-- ----- Per-plot draw. Each plot = a bounding-rect OUTLINE (letter-coloured; source =
-- green, target = gold) + a house-facing arrow + an INVISIBLE click Button (tooltip
-- "Plot N (L)", clicks to set this map's pick). No central fill -- the outline IS the
-- plot. Robust projection (VN's note: derive from projected points, never yaw). Pools
-- live on the persistent canvas (MapRenderer reuses host._mapCanvas), so they never leak.
local function _projWXY(wx, wy, bounds, layerW, layerH)
    local spanX, spanY = bounds.wX_rgt - bounds.wX_lft, bounds.wY_bot - bounds.wY_top
    return ((wy - bounds.wX_lft) / spanX) * layerW, -((wx - bounds.wY_top) / spanY) * layerH
end

local function _acquireRect(canvas, idx)
    canvas._rects = canvas._rects or {}
    local r = canvas._rects[idx]
    if not r then
        -- OVERLAY (not ARTWORK): the map's explored overlay is ARTWORK sublevel 1 and would
        -- otherwise bury the rect on revealed tiles (only the OVERLAY arrows would show).
        r = { canvas:CreateLine(nil, "OVERLAY"), canvas:CreateLine(nil, "OVERLAY"),
              canvas:CreateLine(nil, "OVERLAY"), canvas:CreateLine(nil, "OVERLAY") }
        canvas._rects[idx] = r
    end
    return r
end

local function _acquireArrow(canvas, idx)
    canvas._arrows = canvas._arrows or {}
    local a = canvas._arrows[idx]
    if not a then
        a = canvas:CreateTexture(nil, "OVERLAY")
        a:SetAtlas(MAP_ARROW_ATLAS)   -- exception(boundary): atlas may be unknown -> blank
        canvas._arrows[idx] = a
    end
    return a
end

-- Click target: a Button (only a hover HIGHLIGHT, no persistent fill) over each plot, so
-- clicks + tooltip keep working with just the outline shown.
local function _acquirePin(canvas, idx)
    canvas._pins = canvas._pins or {}
    local pin = canvas._pins[idx]
    if not pin then
        pin = CreateFrame("Button", nil, canvas)
        local hl = pin:CreateTexture(nil, "HIGHLIGHT")
        hl:SetAllPoints(pin)
        hl:SetColorTexture(1, 1, 1, 0.22)
        pin:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(self._label)
            local hc = (self._role == "source") and SRC_RGB or TGT_RGB
            GameTooltip:AddLine("Click to set as " .. self._role, hc[1], hc[2], hc[3])
            GameTooltip:Show()
        end)
        pin:SetScript("OnLeave", function() GameTooltip:Hide() end)
        pin:SetScript("OnClick", function(self)
            HDG.Store:Dispatch({ type = A.REMOVALIST_SET_PLOT, payload = { role = self._role, plot = self._plot } })
        end)
        canvas._pins[idx] = pin
    end
    pin:Show()
    return pin
end

local function _hideFrom(pool, n) if pool then for i = n + 1, #pool do pool[i]:Hide() end end end

-- `eff` = the canvas's current scale. Rect + arrow scale with the projected plot size;
-- the click target has a screen-constant floor so it stays easy to hit when zoomed out.
local function _drawPlots(canvas, model, bounds, layerW, layerH, eff)
    local plots = model.plots
    local inv = 1 / (eff > 0 and eff or 1)
    if canvas._csMark then canvas._csMark:Hide() end   -- shown again below only for the focus plot
    for i = 1, #plots do
        local p = plots[i]
        local col
        if     p.plot == model.sourcePlot then col = SRC_RGB
        elseif p.plot == model.targetPlot then col = TGT_RGB
        else   col = LETTER_RGB[p.letter] or UNLETTERED_RGB end   -- exception(nullable): plot may be unlettered
        local isSel = (p.plot == model.sourcePlot) or (p.plot == model.targetPlot)

        -- bounding-rect corners (projected from the real yaw)
        local yaw  = p.yaw
        local ctrx = p.x + CORNERSTONE_TO_CENTER * math.cos(yaw)
        local ctry = p.y + CORNERSTONE_TO_CENTER * math.sin(yaw)
        local ux, uy = math.cos(yaw), math.sin(yaw)
        local sx, sy = -math.sin(yaw), math.cos(yaw)
        local function corner(sl, ss)
            return _projWXY(ctrx + sl * 35 * ux + ss * 30 * sx, ctry + sl * 35 * uy + ss * 30 * sy, bounds, layerW, layerH)
        end
        local a1, b1 = corner(1, 1);   local a2, b2 = corner(1, -1)
        local a3, b3 = corner(-1, -1); local a4, b4 = corner(-1, 1)
        local rect = _acquireRect(canvas, i)
        local lw   = (isSel and 2.4 or 1.6) * inv
        local function edge(ln, x1, y1, x2, y2)
            ln:SetThickness(lw)
            ln:SetColorTexture(col[1], col[2], col[3], isSel and 1 or 0.95)
            ln:SetStartPoint("TOPLEFT", canvas, x1, y1)
            ln:SetEndPoint("TOPLEFT", canvas, x2, y2)
            ln:Show()
        end
        edge(rect[1], a1, b1, a2, b2); edge(rect[2], a2, b2, a3, b3)
        edge(rect[3], a3, b3, a4, b4); edge(rect[4], a4, b4, a1, b1)

        -- house-facing arrow, centred, scaled to the rect short axis
        local cnx, cny = _projWXY(ctrx, ctry, bounds, layerW, layerH)   -- pad centre (canvas)
        local csx, csy = _projWXY(p.x, p.y, bounds, layerW, layerH)     -- cornerstone (canvas)
        local vx, vy = csx - cnx, csy - cny
        local th = math.rad(MAP_ARROW_TURN * (LETTER_DEG[p.letter] or 0))   -- exception(nullable): unlettered
        local cosT, sinT = math.cos(th), math.sin(th)
        local hx, hy = vx * cosT - vy * sinT, vx * sinT + vy * cosT
        local mx, my = corner(0, 1)
        local rad = math.sqrt((mx - cnx) * (mx - cnx) + (my - cny) * (my - cny))   -- rect short half-extent
        local arrow = _acquireArrow(canvas, i)
        arrow:SetSize(rad * 1.5, rad * 1.5)
        arrow:ClearAllPoints()
        arrow:SetPoint("CENTER", canvas, "TOPLEFT", cnx, cny)
        arrow:SetRotation(math.atan2(hy, hx) + MAP_ARROW_BASE)
        arrow:Show()

        -- invisible click target over the plot (floor of ~14px so it's hittable when small)
        local pin = _acquirePin(canvas, i)
        local clickSz = math.max(rad * 2, 14 * inv)
        pin:SetSize(clickSz, clickSz)
        pin:ClearAllPoints()
        pin:SetPoint("CENTER", canvas, "TOPLEFT", cnx, cny)
        pin._plot, pin._role = p.plot, model.role
        local lbl = "Plot " .. p.plot
        if p.letter then lbl = lbl .. "  (" .. p.letter .. ")" end
        pin._label = lbl

        -- cornerstone marker for the focused plot only (reference for the arrow direction)
        if p.plot == model.focusPlot then
            if not canvas._csMark then
                canvas._csMark = canvas:CreateTexture(nil, "OVERLAY", nil, 7)   -- sublevel 7: above the rect border (also OVERLAY)
                canvas._csMark:SetAtlas(CORNERSTONE_ATLAS)   -- exception(boundary): atlas may be unknown -> blank
            end
            local csz = 11 * inv
            canvas._csMark:SetSize(csz, csz)
            canvas._csMark:ClearAllPoints()
            canvas._csMark:SetPoint("CENTER", canvas, "TOPLEFT", csx, csy)
            canvas._csMark:Show()
        end
    end
    _hideFrom(canvas._pins, #plots)
    _hideFrom(canvas._arrows, #plots)
    if canvas._rects then
        for i = #plots + 1, #canvas._rects do for k = 1, 4 do canvas._rects[i][k]:Hide() end end
    end
end

local function buildRemovalistMap(parent, _spec)
    local host = CreateFrame("Frame", nil, parent)
    host:SetClipsChildren(true)
    local empty = host:CreateFontString(nil, "OVERLAY", "GameFontDisableLarge")
    empty:SetPoint("CENTER")
    empty:SetText("No map art")
    host._emptyLabel = empty
    -- The panel often has 0 size at build time; re-render when geometry settles.
    host:SetScript("OnSizeChanged", function(self)
        if self._lastModel then RemovalistController:RenderMap(self, self._lastModel) end
    end)
    return host
end

-- Focus zoom is NORMALISED to a fixed screen px per world yard (not a multiple of each map's
-- fit-scale), so a plot is the SAME size on the Alliance + Horde maps despite their different
-- art dimensions / world spans. Tune if the focused plot feels too big/small.
local FOCUS_PX_PER_YARD = 0.42

function RemovalistController:RenderMap(host, model)
    host._lastModel = model
    local uiMap = model and model.uiMap
    if not uiMap then
        HDG.MapRenderer:Clear(host)
        host._emptyLabel:Show()
        return
    end
    local canvas = HDG.MapRenderer:Render(host, uiMap)   -- (re)fits + centres each call
    if not canvas then host._emptyLabel:Show(); return end
    host._emptyLabel:Hide()

    local bounds = model.plots and _worldBoundsForMap(uiMap)
    if not bounds then return end
    local hostW, hostH   = host:GetWidth(), host:GetHeight()
    local layerW, layerH = canvas:GetWidth(), canvas:GetHeight()
    if hostW <= 0 or layerW <= 0 or layerH <= 0 then return end
    local fitScale = math.min(hostW / layerW, hostH / layerH)

    -- Framing. Default = fit the plot CLUSTER to the panel (plots fill only the middle of
    -- the zone). A pick overrides to a NORMALISED focus zoom (same scale on both factions).
    local minNx, maxNx, minNy, maxNy = 1, 0, 1, 0
    for i = 1, #model.plots do
        local px, py = _projectNorm(model.plots[i], bounds)
        if px < minNx then minNx = px end
        if px > maxNx then maxNx = px end
        if py < minNy then minNy = py end
        if py > maxNy then maxNy = py end
    end
    local padN = 0.08
    local clW  = math.max(maxNx - minNx + 2 * padN, 0.01)
    local clH  = math.max(maxNy - minNy + 2 * padN, 0.01)
    local eff  = math.max(math.min(hostW / (clW * layerW), hostH / (clH * layerH)), fitScale)
    eff = math.min(eff, fitScale * 3.5)   -- don't over-zoom on a tight cluster
    local tcx, tcy = (minNx + maxNx) / 2, (minNy + maxNy) / 2

    if model.focusPlot then
        for i = 1, #model.plots do
            if model.plots[i].plot == model.focusPlot then
                tcx, tcy = _projectNorm(model.plots[i], bounds)
                -- |spanX| (yards) / layerW (art px) -> canvas-units per yard; * px/yard = scale.
                -- abs: the world coord can decrease from map-corner (0,0)->(1,1) (negative span).
                eff = math.max(FOCUS_PX_PER_YARD * math.abs(bounds.wX_rgt - bounds.wX_lft) / layerW, fitScale)
                break
            end
        end
    end

    -- Apply scale + centre. Clamp (per axis -- the letterboxed axis has a different
    -- half-window) so the view never pans off the map edge.
    canvas:SetScale(eff)
    local halfX = math.min(0.5, hostW / (2 * layerW * eff))
    local halfY = math.min(0.5, hostH / (2 * layerH * eff))
    local cx = math.max(halfX, math.min(1 - halfX, tcx))
    local cy = math.max(halfY, math.min(1 - halfY, tcy))
    canvas:ClearAllPoints()
    canvas:SetPoint("CENTER", host, "CENTER", layerW * (0.5 - cx), layerH * (cy - 0.5))

    _drawPlots(canvas, model, bounds, layerW, layerH, eff)
end

HDG.WidgetTypes:Register("removalistMap", {
    build        = buildRemovalistMap,
    dispatch     = { fields = { "model" }, push = function(widget, values) RemovalistController:RenderMap(widget, values and values.model) end },
    requiresFont = function() return false end,
    specFields   = {},
})

-- ===== Facing diagram (letter-schematic) ====================================
-- "removalistFacing" widget: the ABSTRACT orientation key (the maps carry the real
-- geometry). The house is drawn UPRIGHT in every panel; orientation is read from
-- which SIDE the cornerstone sits on. The panel is HOUSE-RELATIVE: the house always
-- faces the viewer (front = down), and the cornerstone sits at the letter's offset
-- around it -- A=in front (below), B=right, C=behind (above), D=left. So A faces the
-- cornerstone and C has its back to it. Letter-driven, not the raw yaw; every A renders
-- identically, matching the Move verdict.
--   house       = house-outdoor-budget-icon (centred, always upright)
--   cornerstone = housefinder_forsale-plot-icon-highlight (upright, hugs the faced edge)
-- Bound to removalist.source/targetFacing.

local HOUSE_ATLAS       = "house-outdoor-budget-icon"

local function _facLine(host, idx, x1, y1, x2, y2, col, w)
    host._flines = host._flines or {}
    local ln = host._flines[idx]
    if not ln then ln = host:CreateLine(nil, "OVERLAY"); host._flines[idx] = ln end
    ln:SetThickness(w)
    ln:SetColorTexture(col[1], col[2], col[3], col[4] or 1)
    ln:SetStartPoint("CENTER", host, x1, y1)
    ln:SetEndPoint("CENTER", host, x2, y2)
    ln:Show()
    return idx + 1
end

local function buildRemovalistFacing(parent, _spec)
    local host = CreateFrame("Frame", nil, parent)
    local lbl = host:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    lbl:SetPoint("TOPRIGHT", host, "TOPRIGHT", -10, -8)   -- plot id, right side; tinted to the blip
    lbl:SetJustifyH("RIGHT")
    host._facingLabel = lbl
    host._houseIcon = host:CreateTexture(nil, "ARTWORK")
    host._houseIcon:SetAtlas(HOUSE_ATLAS)                  -- exception(boundary): atlas may be unknown -> blank
    host._csIcon = host:CreateTexture(nil, "OVERLAY", nil, 7)   -- sublevel 7: above the pad-rect border
    host._csIcon:SetAtlas(CORNERSTONE_ATLAS)               -- exception(boundary): atlas may be unknown -> blank
    host:SetScript("OnSizeChanged", function(self) RemovalistController:RenderFacing(self, self._lastFacing) end)
    return host
end

function RemovalistController:RenderFacing(host, model)
    host._lastFacing = model
    local lines = host._flines
    if not (model and model.plot) then
        if lines then for i = 1, #lines do lines[i]:Hide() end end
        host._houseIcon:Hide(); host._csIcon:Hide()
        host._facingLabel:SetTextColor(0.7, 0.7, 0.7)   -- scheme-invariant: neutral placeholder
        host._facingLabel:SetText("Pick a plot.")
        return
    end
    local lblCol = (model.which == "source") and SRC_RGB or TGT_RGB
    host._facingLabel:SetTextColor(lblCol[1], lblCol[2], lblCol[3])   -- scheme-invariant: matches the source/target blip
    host._facingLabel:SetText(("Plot %d   (%s)"):format(model.plot, model.letter or "?"))
    local hw, hh = host:GetWidth(), host:GetHeight()
    if hw <= 1 or hh <= 1 then return end
    local R   = math.min(hw, hh) * 0.30           -- facing radius (px)
    local th  = math.rad(LETTER_DEG[model.letter] or 0)
    -- House-relative placement: the house front = down (toward viewer); the cornerstone
    -- sits at the letter's offset around it -- A=front (below), B=right, C=behind (above),
    -- D=left (= letter*90 CCW from the front). The house stays upright in every panel.
    local hx, hy = math.sin(th), -math.cos(th)

    -- Pad outline (dim, upright frame around the house).
    local L, S = R * 1.00, R * 0.78
    local rectCol = { 0.55, 0.50, 0.34, 0.9 }
    local idx = 1
    idx = _facLine(host, idx, -S,  L,  S,  L, rectCol, 2)
    idx = _facLine(host, idx,  S,  L,  S, -L, rectCol, 2)
    idx = _facLine(host, idx,  S, -L, -S, -L, rectCol, 2)
    idx = _facLine(host, idx, -S, -L, -S,  L, rectCol, 2)
    if lines then for i = idx, #lines do lines[i]:Hide() end end

    -- House icon: always upright, centred.
    local iconSz = R * 1.00
    host._houseIcon:SetSize(iconSz, iconSz)
    host._houseIcon:ClearAllPoints()
    host._houseIcon:SetPoint("CENTER", host, "CENTER", 0, 0)
    host._houseIcon:SetRotation(0)
    host._houseIcon:Show()
    -- Cornerstone icon: upright, hugging the edge the house faces (encodes the letter).
    local pad = R * 0.22
    local csSz = R * 0.50
    host._csIcon:SetSize(csSz, csSz)
    host._csIcon:ClearAllPoints()
    host._csIcon:SetPoint("CENTER", host, "CENTER", hx * (S + pad), hy * (L + pad))
    host._csIcon:SetRotation(0)
    host._csIcon:Show()
end

HDG.WidgetTypes:Register("removalistFacing", {
    build        = buildRemovalistFacing,
    dispatch     = { fields = { "model" }, push = function(widget, values) RemovalistController:RenderFacing(widget, values and values.model) end },
    requiresFont = function() return false end,
    specFields   = {},
})

-- ===== Letter filter strip ==================================================
-- "removalistLetterStrip": four colour-coded A/B/C/D chips + a refresh icon, under the
-- faction dropdown. Clicking a chip filters the plot list to that letter (re-clicking the
-- active chip, or the refresh, clears). Bound to removalist.letterFilter -> the active chip
-- lights up, the rest dim. Colours mirror the map pins / list swatches (LETTER_RGB).

local STRIP_LETTERS = { "A", "B", "C", "D" }

local function _stripChip(host, L, x, sz)
    local chip = CreateFrame("Button", nil, host)
    chip:SetSize(sz, sz)
    chip:SetPoint("LEFT", host, "LEFT", x, 0)
    chip._bg = chip:CreateTexture(nil, "BACKGROUND")
    chip._bg:SetAllPoints(chip)
    local lc = LETTER_RGB[L]
    chip._bg:SetColorTexture(lc[1], lc[2], lc[3], 1)
    local fs = chip:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    fs:SetPoint("CENTER")
    fs:SetText(L)
    chip:SetScript("OnClick", function()
        HDG.Store:Dispatch({ type = A.REMOVALIST_SET_LETTER_FILTER, payload = { letter = L } })
    end)
    return chip
end

local function buildRemovalistLetterStrip(parent, _spec)
    local host = CreateFrame("Frame", nil, parent)
    host._chips = {}
    local SZ, GAP = 20, 3
    local x = 0
    for _, L in ipairs(STRIP_LETTERS) do
        host._chips[L] = _stripChip(host, L, x, SZ)
        x = x + SZ + GAP
    end
    local refresh = CreateFrame("Button", nil, host)
    refresh:SetSize(SZ, SZ)
    refresh:SetPoint("LEFT", host, "LEFT", x + GAP + 3, 0)
    refresh._tex = refresh:CreateTexture(nil, "ARTWORK")
    refresh._tex:SetAllPoints(refresh)
    refresh._tex:SetAtlas("uitools-icon-refresh")   -- exception(boundary): atlas may be unknown -> blank
    refresh:SetScript("OnClick", function()
        HDG.Store:Dispatch({ type = A.REMOVALIST_SET_LETTER_FILTER, payload = { letter = nil } })
    end)
    host._refresh = refresh
    return host
end

function RemovalistController:PaintLetterStrip(host, active)
    for L, chip in pairs(host._chips) do
        if not active then        chip._bg:SetAlpha(0.85)
        elseif L == active then   chip._bg:SetAlpha(1.0)
        else                      chip._bg:SetAlpha(0.30) end
    end
    host._refresh:SetAlpha(active and 1.0 or 0.45)
end

HDG.WidgetTypes:Register("removalistLetterStrip", {
    build        = buildRemovalistLetterStrip,
    dispatch     = { fields = { "active" }, push = function(widget, values) RemovalistController:PaintLetterStrip(widget, values and values.active) end },
    requiresFont = function() return false end,
    specFields   = {},
})

-- ===== Community rotation-key chip grid =====================================
-- "removalistRotationKey": a static 2x2 grid of A/B/C/D chips (soft cell + the community
-- colour square with the letter + the turn amount + a descriptor), replacing the old text
-- legend. Colours mirror the map pins / list swatches (LETTER_RGB). No binding -- static.

local KEY_CHIPS = {
    { L = "A", turn = "0 turns",     desc = "aligned" },
    { L = "B", turn = "+90 deg CW",  desc = "9 o'clock" },
    { L = "C", turn = "+180 deg",    desc = "opposite" },
    { L = "D", turn = "+270 deg CW", desc = "3 o'clock" },
}

local function _buildKeyCell(host, spec)
    local cell = CreateFrame("Frame", nil, host)
    local bg = cell:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(cell)
    HDG.Theme:Register(bg, "SectionBgTint", { token = "surface.panel_soft" })
    local sw = cell:CreateTexture(nil, "ARTWORK")
    sw:SetSize(18, 18)
    sw:SetPoint("LEFT", cell, "LEFT", 5, 0)
    local lc = LETTER_RGB[spec.L]
    sw:SetColorTexture(lc[1], lc[2], lc[3], 1)        -- scheme-invariant community colour
    local lg = cell:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    lg:SetPoint("CENTER", sw, "CENTER", 0, 0)
    lg:SetText("|cff11161a" .. spec.L .. "|r")        -- dark glyph on the colour square
    local turn = cell:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    turn:SetPoint("LEFT", cell, "LEFT", 28, 7)
    turn:SetText(spec.turn)
    HDG.Theme:Register(turn, "Text")
    local desc = cell:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    desc:SetPoint("LEFT", cell, "LEFT", 28, -7)
    desc:SetText(spec.desc)
    HDG.Theme:Register(desc, "TextDim")
    return cell
end

local function _layoutKeyGrid(host)
    local w, h = host:GetWidth(), host:GetHeight()
    if w <= 1 or h <= 1 then return end
    local gap = 4
    local cw, ch = (w - gap) / 2, (h - gap) / 2
    local c = host._cells
    c[1]:ClearAllPoints(); c[1]:SetPoint("TOPLEFT",     host, "TOPLEFT",     0, 0)
    c[2]:ClearAllPoints(); c[2]:SetPoint("TOPRIGHT",    host, "TOPRIGHT",    0, 0)
    c[3]:ClearAllPoints(); c[3]:SetPoint("BOTTOMLEFT",  host, "BOTTOMLEFT",  0, 0)
    c[4]:ClearAllPoints(); c[4]:SetPoint("BOTTOMRIGHT", host, "BOTTOMRIGHT", 0, 0)
    for i = 1, 4 do c[i]:SetSize(cw, ch) end
end

local function buildRemovalistRotationKey(parent, _spec)
    local host = CreateFrame("Frame", nil, parent)
    host._cells = {}
    for i = 1, 4 do host._cells[i] = _buildKeyCell(host, KEY_CHIPS[i]) end
    host:SetScript("OnSizeChanged", function(self) _layoutKeyGrid(self) end)
    _layoutKeyGrid(host)
    return host
end

HDG.WidgetTypes:Register("removalistRotationKey", {
    build        = buildRemovalistRotationKey,
    requiresFont = function() return false end,
    specFields   = {},
})

-- ===== Controller wiring ====================================================

function RemovalistController:Wire(rootFrame)
    -- The faction dropdown + plot rows dispatch via their own declarative/factory
    -- wiring; only the Move-panel Swap/Clear buttons need imperative hookup.
    HDG.UI.OnClick(rootFrame, "removalistInfoPanel.swapBtn",  function()
        HDG.Store:Dispatch({ type = A.REMOVALIST_SWAP })
    end)
    HDG.UI.OnClick(rootFrame, "removalistInfoPanel.clearBtn", function()
        HDG.Store:Dispatch({ type = A.REMOVALIST_CLEAR })
    end)
end

function RemovalistController:Refresh(rootFrame, ctx)
    -- Plot list + dropdown state flow through bindings; nothing imperative.
end

HDG.Controllers:Register("removalist", RemovalistController)
