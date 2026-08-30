-- HDG.ProjectsSectionController + the "projectsSection" WidgetType
-- ============================================================================
-- The Architect's SECTION view: the whole house as one isometric drawing,
-- floors stacked in place with dashed stair shafts threading them. Read-only by
-- design -- an angled room has no axis-aligned hit area, so editing stays in the
-- plan canvas; the per-floor tag is the one clickable thing and it jumps you
-- there.
--
-- Pure geometry (footprint edges in cell space) arrives from
-- `projects.sectionModel`; projection + fit live here because both depend on the
-- host's size, which is not state -- the same split the plan canvas uses.

HDG = HDG or {}
HDG.ProjectsSectionController = HDG.ProjectsSectionController or {}
local C = HDG.ProjectsSectionController

-- Iso basis, in "cell units": a cell steps +ISO_X across and +ISO_Y down-screen,
-- so a square footprint reads as a 2:1 rhombus (the classic game-iso ratio).
local ISO_X, ISO_Y = 0.5, 0.25
local MIN_SCALE, MAX_SCALE = 4, 30          -- px per cell unit
-- The floor lift is in PIXELS, deliberately NOT cell-units-times-scale: a wide
-- house shrinks the fit scale, and a scale-coupled lift collapses the stack into
-- a flat smear exactly when there is most to separate. The stack claims a share
-- of the viewport height and the footprints fit in what's left.
local LIFT_SHARE = 0.55                     -- fraction of viewport height the stack spends on lifts
local MIN_LIFT, MAX_LIFT = 26, 120          -- px between plates
local PAD, TAG_GAP = 26, 14                 -- viewport padding; plate-to-tag gap
local TAG_W = 96                            -- tag width; also the right-edge clamp
local DASH_LEN, DASH_GAP = 5, 4             -- stair shaft dashes (px)

local _beginPass = HDG.UI.BeginPoolPass
local _endPass   = HDG.UI.EndPoolPass
local _acquire   = HDG.UI.AcquirePooled

-- ===== factories ============================================================
local function _lineFactory(host)
    local ln = host:CreateLine(nil, "ARTWORK")
    ln:SetThickness(1.5)
    return ln
end

local function _tagFactory(host)
    local btn = CreateFrame("Button", nil, host)
    btn:SetSize(96, 26)
    local title = btn:CreateFontString(nil, "OVERLAY")
    HDG.UI.applyFontRole(title, "caption")
    title:SetPoint("TOPLEFT")
    title:SetJustifyH("LEFT")
    btn._title = title
    local sub = btn:CreateFontString(nil, "OVERLAY")
    HDG.UI.applyFontRole(sub, "caption")
    sub:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -1)
    sub:SetJustifyH("LEFT")
    HDG.Theme:Register(sub, "TextDim")
    btn._sub = sub
    btn:SetScript("OnClick", function(self)
        -- Jump to that floor AND back to the plan canvas: the section view is the
        -- overview, the plan is where you work.
        HDG.Store:Dispatch({ type = HDG.Constants.ACTIONS.UI_SET_TRANSIENT,
            payload = { view = "projects", key = "selectedFloor", value = self._floor } })
        HDG.Store:Dispatch({ type = HDG.Constants.ACTIONS.UI_SET_TRANSIENT,
            payload = { view = "projects", key = "canvasMode", value = "plan" } })
    end)
    return btn
end

-- ===== render ===============================================================
-- One footprint diamond, in cell units. Its iso width and height are what the
-- fit solves against; the lifts are added in pixels on top (see LIFT_SHARE).
local function _diamondSpan(bbox)
    local d = (bbox.maxX - bbox.minX) + (bbox.maxY - bbox.minY)
    return math.max(0.001, d * ISO_X), math.max(0.001, d * ISO_Y)
end

function C:Render(host, model)
    host._lastModel = model   -- OnSizeChanged re-renders from this
    _beginPass(host, "_secLine")
    _beginPass(host, "_secTag")
    if not model or model.empty then
        if host._emptyLabel then host._emptyLabel:Show() end
        _endPass(host, "_secLine"); _endPass(host, "_secTag")
        return
    end
    if host._emptyLabel then host._emptyLabel:Hide() end

    local vw, vh = host:GetWidth(), host:GetHeight()
    if not vw or not vh or vw <= 1 or vh <= 1 then   -- exception(boundary): geometry not settled; OnSizeChanged re-fires
        _endPass(host, "_secLine"); _endPass(host, "_secTag")
        return
    end

    local bbox = model.bbox
    local diaW, diaH = _diamondSpan(bbox)
    local gaps = math.max(1, #model.floors - 1)
    local usableW, usableH = vw - PAD * 2 - TAG_W, vh - PAD * 2

    -- Lift first (pixels, independent of scale), then fit the footprints into
    -- whatever height is left. Clamped so two floors never fuse and a tall stack
    -- never runs off the top.
    local lift = (usableH * LIFT_SHARE) / gaps
    if lift < MIN_LIFT then lift = MIN_LIFT end
    if lift > MAX_LIFT then lift = MAX_LIFT end
    local scale = math.min(usableW / diaW, math.max(1, usableH - gaps * lift) / diaH)
    if scale < MIN_SCALE then scale = MIN_SCALE end
    if scale > MAX_SCALE then scale = MAX_SCALE end
    -- A house wide enough to be clamped at MIN_SCALE can still overflow; give the
    -- height back from the lifts rather than letting the drawing leave the frame.
    local overflow = (diaH * scale + gaps * lift) - usableH
    if overflow > 0 then
        lift = math.max(MIN_LIFT, lift - overflow / gaps)
    end

    local drawW = diaW * scale
    local drawH = diaH * scale + gaps * lift
    -- Origin: the TOP floor's plate top-corner. +y downward, floors lift upward.
    local ox = (vw - TAG_W - drawW) / 2 - (bbox.minX - bbox.maxY) * ISO_X * scale
    local oy = (vh - drawH) / 2 - (bbox.minX + bbox.minY) * ISO_Y * scale + gaps * lift

    -- Cell (cx, cy) on `floor` -> host-relative px, TOPLEFT origin, +y downward.
    local function project(cx, cy, floor)
        return ox + (cx - cy) * ISO_X * scale,
               oy + (cx + cy) * ISO_Y * scale - (floor - model.floorMin) * lift
    end

    local lineN = 0
    local function line(x1, y1, x2, y2, role, roleCtx)
        lineN = lineN + 1
        local ln = _acquire(host, "_secLine", lineN, _lineFactory)
        HDG.Theme:Register(ln, role, roleCtx)
        ln:ClearAllPoints()
        ln:SetStartPoint("TOPLEFT", host, x1, -y1)
        ln:SetEndPoint("TOPLEFT", host, x2, -y2)
        ln:Show()
    end

    -- Painter's order: every other floor first, the focused floor last, so the one
    -- you are reading is on top of the pile rather than under it.
    local order = {}
    for _, fl in ipairs(model.floors) do
        if fl.floor ~= model.selectedFloor then order[#order + 1] = fl end
    end
    for _, fl in ipairs(model.floors) do
        if fl.floor == model.selectedFloor then order[#order + 1] = fl end
    end
    for _, fl in ipairs(order) do
        -- Plate: the floor's footprint diamond, faint -- it reads as ground and
        -- makes an empty floor legible instead of invisible.
        local p1x, p1y = project(bbox.minX, bbox.minY, fl.floor)
        local p2x, p2y = project(bbox.maxX, bbox.minY, fl.floor)
        local p3x, p3y = project(bbox.maxX, bbox.maxY, fl.floor)
        local p4x, p4y = project(bbox.minX, bbox.maxY, fl.floor)
        line(p1x, p1y, p2x, p2y, "SectionPlate")
        line(p2x, p2y, p3x, p3y, "SectionPlate")
        line(p3x, p3y, p4x, p4y, "SectionPlate")
        line(p4x, p4y, p1x, p1y, "SectionPlate")

        -- The floor in focus is drawn at full strength, the rest muted. Without this
        -- a floor whose rooms cluster in one corner is indistinguishable from the
        -- floors it overlaps, and "where is floor 1" has no answer on screen.
        local inFocus = (fl.floor == model.selectedFloor)
        for _, room in ipairs(fl.rooms) do
            local role = (inFocus or room.selected) and "RoomOutline" or "SectionRoomMuted"
            for _, e in ipairs(room.edges) do
                local ax, ay = project(e[1], e[2], fl.floor)
                local bx, by = project(e[3], e[4], fl.floor)
                line(ax, ay, bx, by, role, { selected = room.selected })
            end
        end

        -- Floor tag, off the plate's east corner. The one interactive element.
        local tag = _acquire(host, "_secTag", fl.floor, _tagFactory)
        tag._floor = fl.floor
        tag._title:SetText(HDG.Locale:Get("PROJ_SECTION_FLOOR"):format(fl.floor))
        tag._sub:SetText(HDG.Locale:Get("PROJ_SECTION_ROOMS"):format(#fl.rooms))
        -- The floor you are editing reads bright; the rest recede.
        HDG.Theme:Register(tag._title, fl.floor == model.selectedFloor and "Text" or "TextDim")
        tag:ClearAllPoints()
        local tagX = math.min(p2x + TAG_GAP, vw - TAG_W - 4)
        tag:SetPoint("TOPLEFT", host, "TOPLEFT", math.max(0, tagX), -(p2y - 8))
        tag:Show()
    end

    -- Stair shafts: dashed verticals from each stair's centroid to the same
    -- point one floor up. These are what make the stack read as ONE house.
    for _, sh in ipairs(model.shafts) do
        local sx, sy = project(sh.cx, sh.cy, sh.floor)
        local ex, ey = project(sh.cx, sh.cy, sh.floor + 1)
        local total  = sy - ey
        if total > 0 then
            local step, drawn = DASH_LEN + DASH_GAP, 0
            while drawn < total do
                local segEnd = math.min(drawn + DASH_LEN, total)
                line(sx, sy - drawn, ex, sy - segEnd, "AccentBar")
                drawn = drawn + step
            end
        end
    end

    _endPass(host, "_secLine")
    _endPass(host, "_secTag")
end

-- ===== widget-kind: thin host frame =========================================
local function buildProjectsSection(parent, _spec)
    local host = CreateFrame("Frame", nil, parent)
    local empty = host:CreateFontString(nil, "OVERLAY", "GameFontDisableLarge")
    empty:SetPoint("CENTER")
    empty:SetText(HDG.Locale:Get("PROJ_SECTION_EMPTY"))
    host._emptyLabel = empty
    host:SetScript("OnSizeChanged", function(self)
        if self._lastModel then C:Render(self, self._lastModel) end   -- re-fit on resize / late geometry
    end)
    return host
end

HDG.WidgetTypes:Register("projectsSection", {
    build        = buildProjectsSection,
    dispatch     = { fields = { "model" }, push = function(widget, values) C:Render(widget, values and values.model) end },
    requiresFont = function() return false end,
    specFields   = {},   -- model flows via binding; no kind-specific spec fields
})
