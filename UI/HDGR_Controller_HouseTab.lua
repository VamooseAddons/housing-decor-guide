-- HDG.HouseTabController
-- ============================================================================
-- Dashboard tab: bin-packed widget cells (house.widgetRows) + picker side panel
-- (house.pickerRows) with toggle + order buttons.

HDG = HDG or {}
HDG.Rows = HDG.Rows or {}
HDG.HouseTabController = HDG.HouseTabController or {}

local HouseTabController = HDG.HouseTabController
local Constants = HDG.Constants

local _attachPickerDrag  -- forward declaration; defined at bottom of file

local function _itemTooltipDef(self)
    return self._itemID and { itemID = self._itemID } or nil
end

-- ===== Controller wiring ===================================================

function HouseTabController:Wire(rootFrame)
    HDG.UI.OnClick(rootFrame, "houseTabPanel.pickerBtn", function()
        HDG.Store:Dispatch({
            type    = Constants.ACTIONS.HOUSETAB_TOGGLE_PICKER,
            payload = {},
        })
    end)
    HDG.UI.OnClick(rootFrame, "houseTabPanel.designBtn", function()
        HDG.Store:Dispatch({
            type    = Constants.ACTIONS.HOUSETAB_TOGGLE_DESIGN_MODE,
            payload = {},
        })
    end)

    -- Drag-to-reorder: uses ScrollUtil.AddLinearDragBehavior for candidate machinery + visuals,
    -- but REPLACES OnDragStop so the data provider is never mutated (dispatches HOUSETAB_SET_ORDERS).
    local pickerHost = rootFrame.widgets and rootFrame.widgets["houseTabPickerPanel.list"]
    if pickerHost and pickerHost.scrollBox and _G.ScrollUtil and _G.ScrollUtil.AddLinearDragBehavior then
        _attachPickerDrag(pickerHost.scrollBox)
    end
end

function HouseTabController:Refresh(rootFrame, ctx)
    -- All rendering flows through bindings + row factories.
end

HDG.Controllers:Register("houseTab", HouseTabController)

-- ============================================================================
-- Dashboard row factory: multi-cell row. ed = { cells, units, height, id }.
-- ============================================================================

-- Inter-cell gap: same value used for both horizontal gap and LayoutConfig row spacing.
local CELL_GAP = 1

-- =============================================================================
-- Donut: 90 textures, each painted as a wedge via SetVertexOffset (quad -> triangle).
-- Inner hole = CircleMaskScalable-masked WHITE8x8 tinted to the panel bg.
-- =============================================================================

local DONUT_WEDGES = 90

local function _buildDonut(parent, size, holeSize)
    local frame = CreateFrame("Frame", nil, parent)
    frame:SetSize(size, size)
    frame.wedges = {}
    for i = 1, DONUT_WEDGES do
        local tex = frame:CreateTexture(nil, "ARTWORK")
        tex:SetTexture("Interface\\Buttons\\WHITE8X8")
        tex:SetSize(0.001, 0.001)
        tex:SetPoint("CENTER", frame, "CENTER")
        tex:Hide()
        frame.wedges[i] = tex
    end
    frame.hole = frame:CreateTexture(nil, "OVERLAY")
    frame.hole:SetTexture("Interface\\Buttons\\WHITE8X8")
    frame.hole:SetSize(holeSize, holeSize)
    frame.hole:SetPoint("CENTER", frame, "CENTER")
    HDG.UI._TintTexture(frame.hole, HDG.Theme:GetColor("surface.panel"))
    HDG.UI.CircleMask(frame.hole)
    return frame
end

-- =============================================================================
-- Segment bar: N gradient pips (warning -> success). Used by capacity/closeCards/themedSets.
-- =============================================================================

local SEG_DEFAULT = 10

-- segments: pip count. pct: 0..1. gradient: { from, to } (default warning -> success).
local function _buildSegmentBar(parent, width, height, segments, pct, gradient)
    segments = segments or SEG_DEFAULT
    pct = math.max(0, math.min(1, pct or 0))  -- exception(boundary): caller may pass nil
    local from = gradient and gradient.from or HDG.Theme:GetColor("semantic.warning")
    local to   = gradient and gradient.to   or HDG.Theme:GetColor("semantic.success")

    local frame = CreateFrame("Frame", nil, parent)
    frame:SetSize(width, height)

    local gap = 2
    local pipW = math.max(2, (width - gap * (segments - 1)) / segments)
    local filled = pct * segments
    for i = 1, segments do
        local pip = frame:CreateTexture(nil, "ARTWORK")
        pip:SetTexture("Interface\\Buttons\\WHITE8X8")
        pip:SetSize(pipW, height)
        pip:SetPoint("LEFT", frame, "LEFT", (i - 1) * (pipW + gap), 0)
        -- Gradient ramp position for this pip.
        local t = (segments == 1) and 1 or ((i - 1) / (segments - 1))
        local r = from.r + (to.r - from.r) * t
        local g = from.g + (to.g - from.g) * t
        local b = from.b + (to.b - from.b) * t
        local fillPortion = math.max(0, math.min(1, filled - (i - 1)))
        local alpha = (fillPortion > 0) and (0.85 * fillPortion + 0.15) or 0.18
        pip:SetVertexColor(r, g, b, alpha)
    end
    return frame
end

local function _paintDonut(donut, segments)
    local total = 0
    for _, s in ipairs(segments) do total = total + s.value end
    if total <= 0 then
        for _, w in ipairs(donut.wedges) do w:Hide() end
        return
    end
    local radius   = donut:GetWidth() / 2
    local wedgeAng = 2 * math.pi / DONUT_WEDGES
    local accum, segIdx = 0, 1
    for i = 1, DONUT_WEDGES do
        local mid = (i - 0.5) / DONUT_WEDGES
        while segIdx <= #segments and (accum + segments[segIdx].value) / total < mid do
            accum  = accum + segments[segIdx].value
            segIdx = segIdx + 1
        end
        local seg = segments[segIdx]
        local w   = donut.wedges[i]
        if seg and seg.color then
            HDG.UI._TintTexture(w, seg.color, 0.95)  -- data: per-segment Palette brand color (pie chart)
            local a1 = (i - 1) * wedgeAng - math.pi / 2   -- start at 12 o'clock
            local a2 = a1 + wedgeAng
            local p1x, p1y =  math.cos(a1) * radius, -math.sin(a1) * radius
            local p2x, p2y =  math.cos(a2) * radius, -math.sin(a2) * radius
            w:SetVertexOffset(1, p1x, p1y)   -- UL=1 LL=2 UR=3 LR=4
            w:SetVertexOffset(3, p2x, p2y)
            w:SetVertexOffset(2, 0, 0)
            w:SetVertexOffset(4, 0, 0)
            w:Show()
        else
            w:Hide()
        end
    end
end

-- =============================================================================
-- Per-widget renderers: (cell, ed) where cell is the sized+themed BackdropTemplate Frame.
-- =============================================================================

-- decoratorProfile: level ring (HDGRHousingLevelRingTemplate) + title/house/bar/trophy.
local LEFT_ZONE_W = 256   -- ring template native width
local LEFT_ZONE_H = 158   -- ring template native height

-- Ring math: bottom 22% covered (laurel gap); visible band = 78%; half-gap offsets "empty" to bottom.
local BAR_PERCENTAGE_COVERED = 0.22
local BAR_VISIBLE_BAND       = 1 - BAR_PERCENTAGE_COVERED   -- 0.78
local BAR_HALF_GAP           = BAR_PERCENTAGE_COVERED / 2   -- 0.11
local BAR_ANIM_TIME          = 1.0

-- Wrap HDGRHousingLevelRingTemplate with SetLevel/SetProgress/UpdateFill/ResetForReplay.
-- exception(false-positive): sweep nesting-cliff hit -- the depth is nested function
-- DEFINITIONS (SetLevel/UpdateFill/SetProgress/ResetForReplay as behavioral units),
-- not control-flow nesting; applyDisplayPct/UpdateBar are closures over Blizzard frame
-- children and not decomposable without losing the capture. Pass-2 verified 2026-06-10:
-- no shared consumers (_adoptLevelRing / ScriptAnimationUtil / CooldownFrame_* appear
-- only in this file).
local function _adoptLevelRing(ringFrame)
    local cd       = ringFrame.HouseBarFrame and ringFrame.HouseBarFrame.Bar
                     and ringFrame.HouseBarFrame.Bar.BarFill
    local lead     = cd and cd.LeadEdge
    local thresh   = cd and cd.Threshold
    local flipbook = cd and cd.Flipbook

    ringFrame.currentPercentage = BAR_HALF_GAP
    ringFrame.targetPercentage  = BAR_HALF_GAP

    local function applyDisplayPct(finalPct)
        if cd and _G.CooldownFrame_SetDisplayAsPercentage then
            _G.CooldownFrame_SetDisplayAsPercentage(cd, finalPct)
        end
        local rot = (0.5 - finalPct) * 2 * math.pi
        if lead     then lead:SetRotation(rot)     end
        if thresh   then thresh:SetRotation(rot)   end
        if flipbook then flipbook:SetRotation(rot) end
    end

    function ringFrame:SetLevel(lvl)
        if self.HouseLevelText then  -- exception(boundary): adopted Blizzard ringFrame sub-widget; may be absent in different Blizzard versions
            self.HouseLevelText:SetText(tostring(lvl or 0))
        end
    end

    function ringFrame:StopCurrentAnimation()
        if self._cancelAnim then
            self._cancelAnim()
            self._cancelAnim = nil
        end
    end

    -- Animate currentPercentage -> targetPercentage (mirrors HouseUpgradeProgressBarMixin:UpdateFill).
    function ringFrame:UpdateFill()
        local startingPct = self.currentPercentage
        local endingPct   = self.targetPercentage
        if startingPct == endingPct then
            self:StopCurrentAnimation()
            return
        end

        local function UpdateBar(elapsed, duration)
            local t = elapsed / duration
            local easeFn = (_G.EasingUtil and _G.EasingUtil.InOutQuartic)
                            or function(x) return x end
            local newPct = math.min(startingPct + easeFn(t) * (endingPct - startingPct), 1.0)
            applyDisplayPct(newPct)
            self.currentPercentage = newPct
        end

        self:StopCurrentAnimation()
        if _G.ScriptAnimationUtil and _G.ScriptAnimationUtil.StartScriptAnimation then  -- exception(boundary): ScriptAnimationUtil is FrameXML; absent in headless mock
            self._cancelAnim = _G.ScriptAnimationUtil.StartScriptAnimation(
                self, UpdateBar, BAR_ANIM_TIME,
                function() self._cancelAnim = nil end)
            if cd and cd.BarAnimation and cd.BarAnimation.Restart then
                cd.BarAnimation:Restart()
            end
        else
            applyDisplayPct(endingPct)
            self.currentPercentage = endingPct
        end
    end

    function ringFrame:SetProgress(basePct)
        basePct = math.max(0, math.min(1, basePct or 0))  -- exception(boundary): caller may pass nil
        self.targetPercentage = basePct * BAR_VISIBLE_BAND + BAR_HALF_GAP
        self:UpdateFill()
    end

    function ringFrame:ResetForReplay()
        self:StopCurrentAnimation()
        self.currentPercentage = BAR_HALF_GAP
        applyDisplayPct(BAR_HALF_GAP)
    end

    return ringFrame
end

-- Trophy shelf: inline (single consumer). Shadow colors are baked physical values, not theme tokens.
local TROPHY_ICON_SIZE = 28
local TROPHY_ICON_GAP  = 2
local TROPHY_ICON_DROP = 2     -- icon overlap onto the wood shelf
local TROPHY_PAD_X     = 6     -- inset between wood frame and first/last icon
local TROPHY_PAD_Y     = 4

local function _renderTrophyShelf(parent, items, _collected, _total)
    -- ScrollFrame clips overflow; wood plank = bottom half; icons overlap 2px onto the shelf.
    local shelfFrame = CreateFrame("Frame", nil, parent)
    shelfFrame:SetPoint("TOPLEFT",     parent, "TOPLEFT",     0, 0)
    shelfFrame:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", 0, 0)

    local woodBg = shelfFrame:CreateTexture(nil, "BACKGROUND", nil, 1)
    woodBg:SetPoint("BOTTOMLEFT",  shelfFrame, "BOTTOMLEFT",  0, 0)
    woodBg:SetPoint("BOTTOMRIGHT", shelfFrame, "BOTTOMRIGHT", 0, 0)
    woodBg:SetHeight(1)   -- live-sized in OnSizeChanged
    woodBg:SetAtlas("housing-woodsign")
    woodBg:SetAlpha(0.65)

    -- Shelf-edge shadow at ARTWORK (BACKGROUND matched wood sublevel and vanished on some hosts).
    local edgeShadow = shelfFrame:CreateTexture(nil, "ARTWORK", nil, 1)
    HDG.Theme:Register(edgeShadow, "Shadow")

    local scroll = CreateFrame("ScrollFrame", nil, shelfFrame)
    scroll:SetPoint("TOPLEFT",     shelfFrame, "TOPLEFT",     TROPHY_PAD_X,  -TROPHY_PAD_Y)
    scroll:SetPoint("BOTTOMRIGHT", shelfFrame, "BOTTOMRIGHT", -TROPHY_PAD_X,  TROPHY_PAD_Y)

    local scrollContent = CreateFrame("Frame", nil, scroll)
    scrollContent:SetSize(1, TROPHY_ICON_SIZE)
    scroll:SetScrollChild(scrollContent)

    -- One-icon-per-step horizontal mouse-wheel scroll.
    shelfFrame:EnableMouseWheel(true)
    shelfFrame:SetScript("OnMouseWheel", function(_, delta)
        local cur  = scroll:GetHorizontalScroll()
        local max  = scroll:GetHorizontalScrollRange() or 0  -- exception(boundary): frame geometry nil before first layout
        local step = TROPHY_ICON_SIZE + TROPHY_ICON_GAP
        local off  = math.max(0, math.min(max, cur - delta * step))
        scroll:SetHorizontalScroll(off)
    end)

    -- Icon buttons: built once (cell rebuilt on every dispatch in the row factory).
    local iconBtns = {}
    for i, item in ipairs(items) do
        local b = CreateFrame("Button", nil, scrollContent)
        b:SetSize(TROPHY_ICON_SIZE, TROPHY_ICON_SIZE)

        -- Contact shadow: oval that OVERLAPS the icon base by 1px so the
        -- shadow reads as the trophy resting ON the shelf, not casting
        -- through air. Width ~85% icon, height ~20%, alpha 0.65.
        local shadow = b:CreateTexture(nil, "BACKGROUND", nil, 2)
        shadow:SetAtlas("groupfinder-eye-highlight")   -- set before Register so Shadow tints via vertex color
        HDG.Theme:Register(shadow, "Shadow")
        shadow:SetBlendMode("BLEND")
        shadow:SetSize(TROPHY_ICON_SIZE * 0.85,
                       math.max(3, math.floor(TROPHY_ICON_SIZE * 0.20)))
        shadow:SetPoint("BOTTOM", b, "BOTTOM", -3, -2)

        local tex = b:CreateTexture(nil, "ARTWORK")
        tex:SetAllPoints()
        tex:SetTexCoord(unpack(HDG.Constants.ICON_CROP))
        if item.iconID then tex:SetTexture(item.iconID) end
        b._itemID = item.itemID
        HDG.TooltipEngine:Attach(b, _itemTooltipDef)
        iconBtns[i] = b
    end

    local function _layoutIcons()
        local shelfH  = shelfFrame:GetHeight() or 0  -- exception(boundary): frame geometry nil before first layout
        local woodH   = math.floor(shelfH / 2)
        local yOff    = math.max(0, woodH - TROPHY_ICON_DROP)
        local stripY  = math.max(0, TROPHY_PAD_Y + yOff - 1)

        edgeShadow:ClearAllPoints()
        edgeShadow:SetPoint("BOTTOMLEFT",  shelfFrame, "BOTTOMLEFT",  TROPHY_PAD_X,  stripY)
        edgeShadow:SetPoint("BOTTOMRIGHT", shelfFrame, "BOTTOMRIGHT", -TROPHY_PAD_X, stripY)
        edgeShadow:SetHeight(2)

        for i, b in ipairs(iconBtns) do
            b:ClearAllPoints()
            b:SetPoint("BOTTOMLEFT", scrollContent, "BOTTOMLEFT",
                       (i - 1) * (TROPHY_ICON_SIZE + TROPHY_ICON_GAP), yOff)
        end

        local count = #iconBtns
        local contentW = math.max(1,
            count * TROPHY_ICON_SIZE + math.max(0, count - 1) * TROPHY_ICON_GAP)
        scrollContent:SetSize(contentW, math.max(TROPHY_ICON_SIZE, shelfH))
        scroll:SetHorizontalScroll(0)
    end

    -- OnSizeChanged: keep wood = half height + reposition icons. Fires once anchors resolve.
    shelfFrame:SetScript("OnSizeChanged", function(_, _, h)
        local woodH = math.max(1, math.floor((h or 0) / 2))
        woodBg:SetHeight(woodH)
        _layoutIcons()
    end)
end

local function _renderDecoratorProfile(cell, ed)
    local d = ed.data   -- selector contract; nil = selector bug, not a fallback case

    -- Left zone: Blizzard-templated level ring. Native 256x158; do NOT scale or re-anchor children.
    local ring = _adoptLevelRing(CreateFrame("Frame", nil, cell, "HDGRHousingLevelRingTemplate"))
    ring:SetPoint("LEFT", cell, "LEFT", 0, 0)

    -- Replay animation on each Show (window close + reopen).
    cell:HookScript("OnShow", function()
        ring:ResetForReplay()
    end)

    -- Drive ring from selector data. nil before HOUSE_LEVEL_UPDATED lands; SetLevel(nil) -> "0".
    ring:SetLevel(d.houseLevel)
    if d.houseLevel and d.houseFavor and d.houseThresholds then
        local cur = d.houseThresholds[d.houseLevel]
        local nxt = d.houseThresholds[d.houseLevel + 1]
        if cur and nxt and nxt > cur then
            local within = math.max(0, math.min(nxt - cur, d.houseFavor - cur))
            ring:SetProgress(within / (nxt - cur))
        else
            ring:SetProgress(1)   -- max level: ring full
        end
    else
        ring:SetProgress(0)
    end

    -- Right zone: titleLabel + houseName + progressChip + bar + ladder.
    local rightZone = CreateFrame("Frame", nil, cell)
    rightZone:SetPoint("TOPLEFT",     ring, "TOPRIGHT", 8, 0)
    rightZone:SetPoint("BOTTOMRIGHT", cell, "BOTTOMRIGHT", -6, 6)

    -- Big tier title: TextStatus = semantic.accent; TextShadow stacks independently.
    local titleLbl = rightZone:CreateFontString(nil, "OVERLAY")
    HDG.UI.applyFontRole(titleLbl, "heading")
    -- TextStatus paints `semantic.accent` (matches HDG's `scheme.accent`
    -- on the title label). TextShadow stacks on top -- both Skinners are
    -- independent (one sets fg color, the other sets shadow color +
    -- offset). Theme:Reload repaints both on scheme switch.
    HDG.Theme:Register(titleLbl, "TextStatus")
    HDG.Theme:Register(titleLbl, "TextShadow")
    titleLbl:SetPoint("TOPLEFT", rightZone, "TOPLEFT", 4, -4)
    titleLbl:SetJustifyH("LEFT")
    titleLbl:SetText(string.upper(d.title))

    -- House name: right-aligned, text.primary (faction tint deferred; not a scheme token yet).
    local houseLbl = HDG.UI.RowText(rightZone, "subheading", "Text", "RIGHT")
    houseLbl:SetPoint("TOPRIGHT", rightZone, "TOPRIGHT", -4, -4)
    houseLbl:SetWordWrap(false)
    if d.houseName then
        houseLbl:SetText(d.houseName)
    else
        houseLbl:SetText("")
    end

    -- Progress chip: right-anchored, below house name.
    local chip = HDG.UI.RowText(rightZone, "small", "TextDim", "RIGHT")
    chip:SetPoint("TOPRIGHT", houseLbl, "BOTTOMRIGHT", 0, -2)
    if d.totalAll > 0 then
        local cText = HDG.Theme:ColorCode("text.primary")
        local cDim  = HDG.Theme:ColorCode("text.dim")
        local pct = math.floor(d.collectedAll / d.totalAll * 100 + 0.5)
        chip:SetText(string.format("%s%d|r %s/ %d  (%d%%)|r",
            cText, d.collectedAll, cDim, d.totalAll, pct))
    end

    -- Within-tier progress bar.
    local bar = CreateFrame("StatusBar", nil, rightZone)
    bar:SetHeight(6)
    bar:SetPoint("TOPLEFT", titleLbl, "BOTTOMLEFT", 0, -4)
    bar:SetPoint("RIGHT",   chip, "LEFT", -10, 0)   -- stop short of the right-side progress numbers (no overlap)
    bar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
    HDG.Theme:Register(bar, "progressbar", { variant = "success" })
    local t = d.titleTier
    if t and t.next and t.current then
        -- HouseAggregator titleTier always stamps .threshold on current+next
        local prev = t.current.threshold
        local nxt  = t.next.threshold
        local span = math.max(1, nxt - prev)
        local within = math.max(0, math.min(span, d.collectedAll - prev))
        bar:SetMinMaxValues(0, span)
        bar:SetValue(within)
        bar:Show()
    else
        bar:Hide()
    end

    -- Tier ladder line: "prev > CURRENT > next" with theme-token color codes.
    local ladder = HDG.UI.RowText(rightZone, "small", "TextDim", "LEFT")
    ladder:SetPoint("TOPLEFT", titleLbl, "BOTTOMLEFT", 0, -14)
    ladder:SetPoint("RIGHT",   rightZone, "RIGHT", -4, 0)
    ladder:SetWordWrap(false)
    if t then
        local cAccent = HDG.Theme:ColorCode("semantic.accent")
        local cDim    = HDG.Theme:ColorCode("text.dim")
        local cText   = HDG.Theme:ColorCode("text.primary")
        local parts = {}
        if t.prev then parts[#parts + 1] = cDim  .. t.prev.name .. "|r" end
        if t.current then parts[#parts + 1] = cText .. t.current.name .. "|r" end
        if t.next then parts[#parts + 1] = cDim  .. t.next.name .. "|r" end
        local line = table.concat(parts, "  " .. cDim .. ">|r  ")
        if not t.next then line = line .. "   " .. cAccent .. "max rank|r" end
        ladder:SetText(line)
    else
        ladder:SetText("")
    end

    -- Bestowed-title: populated by Modules/HDGR_Vamoose at onEnable. Hide when nil.
    local bestowed = HDG.UI.RowText(rightZone, "small", "TextDim", "LEFT")
    bestowed:SetPoint("TOPLEFT", ladder, "BOTTOMLEFT", 0, -8)
    bestowed:SetPoint("RIGHT",   rightZone, "RIGHT", -4, 0)
    bestowed:SetWordWrap(false)
    if d.bestowedName then
        local cAccent = HDG.Theme:ColorCode("semantic.accent")
        local cDim    = HDG.Theme:ColorCode("text.dim")
        bestowed:SetText(string.format("%s%s|r  %s%s|r",
            cAccent, d.bestowedName, cDim, d.bestowedQuote))
    else
        bestowed:SetText("")
    end

    -- Trophy shelf zone: bottom of right zone, ~56-60px height (icon 28 + overlap + wood + pads).
    local trophyZone = CreateFrame("Frame", nil, rightZone)
    trophyZone:SetPoint("BOTTOMLEFT",  rightZone, "BOTTOMLEFT",  0, 4)
    trophyZone:SetPoint("BOTTOMRIGHT", rightZone, "BOTTOMRIGHT", 0, 4)
    trophyZone:SetHeight(60)
    _renderTrophyShelf(trophyZone, d.trophies, d.trophiesCollected, d.trophiesTotal)
end

-- styleAffinity: top-5 tags joined "NAME N/M (PCT%) - ..."
local function _renderStyleAffinity(cell, ed)
    local d = ed.data
    local fs = HDG.UI.RowText(cell, "small", "TextDim", "LEFT")
    fs:SetPoint("TOPLEFT", cell, "TOPLEFT", 4, -2)
    fs:SetPoint("RIGHT",   cell, "RIGHT",  -2, 0)
    fs:SetWordWrap(false)

    local cAccent = HDG.Theme:ColorCode("semantic.accent")
    local cText   = HDG.Theme:ColorCode("text.primary")
    local cDim    = HDG.Theme:ColorCode("text.dim")
    local parts = {}
    parts[#parts + 1] = cDim .. "Your style:|r"
    for _, t in ipairs(d.tags) do
        local pct = math.floor((t.pct or 0) + 0.5)
        parts[#parts + 1] = string.format("%s%s|r %s%d/%d|r %s(%d%%)|r",
            cAccent, t.name, cText, t.collected, t.total, cDim, pct)
    end
    fs:SetText(table.concat(parts, "  " .. cDim .. "-|r  "))
end

-- Shared donut+legend renderer factory. paletteToken/labelFor/centerMain/centerSub closures.
-- Card title: the top-left subheading every HouseTab card starts with
-- (hygiene A3 -- this exact block appeared 16x in this file).
local function _cardTitle(cell, ed)
    local title = HDG.UI.RowText(cell, "subheading", "Text")
    title:SetPoint("TOPLEFT", cell, "TOPLEFT", 8, -6)
    title:SetText(ed.title)
    return title
end

local function _renderDonutCard(cell, ed, paletteToken, labelFor, centerMain, centerSub)
    local d = ed.data
    _cardTitle(cell, ed)

    -- Donut: 40% of cell width, 50% inner hole (room for 13-entry legend).
    local cellH      = cell:GetHeight()
    local donutSize  = math.max(80, math.min(cellH - 28, cell:GetWidth() * 0.40))
    local holeSize   = math.floor(donutSize * 0.5)
    local donut = _buildDonut(cell, donutSize, holeSize)
    donut:SetPoint("TOPLEFT", cell, "TOPLEFT", 6, -22)

    local segments = {}
    for _, b in ipairs(d.buckets) do
        if b.collected and b.collected > 0 then
            local color = HDG.Palette:GetColor(paletteToken(b))
            segments[#segments + 1] = { value = b.collected, color = color, bucket = b }
        end
    end
    _paintDonut(donut, segments)

    -- Center text: parented on DONUT frame (cell would bury them behind OVERLAY).
    local mainText = centerMain and centerMain(d) or ""
    local subText  = centerSub  and centerSub(d)  or nil

    local centerFs = HDG.UI.RowText(donut, "heading", "Text")
    centerFs:SetPoint("CENTER", donut, "CENTER", 0, subText and 6 or 0)
    centerFs:SetText(mainText)

    if subText then
        local sub = HDG.UI.RowText(donut, "small", "TextDim")
        sub:SetPoint("CENTER", donut, "CENTER", 0, -10)
        sub:SetText(subText)
    end

    -- Legend on the right: tight rows so all expansions fit (13 needed).
    local legendX = 8 + donutSize + 8
    local rowH    = 11
    for i, b in ipairs(d.buckets) do
        if i > 14 then break end
        local y = -22 - (i - 1) * rowH
        if -y > cellH - 4 then break end
        local color = HDG.Palette:GetColor(paletteToken(b))

        local swatch = cell:CreateTexture(nil, "ARTWORK")
        swatch:SetTexture("Interface\\Buttons\\WHITE8x8")
        swatch:SetSize(7, 7)
        swatch:SetPoint("TOPLEFT", cell, "TOPLEFT", legendX, y - 2)
        HDG.UI._TintTexture(swatch, color)

        local lbl = HDG.UI.RowText(cell, "small", "Text")
        lbl:SetPoint("TOPLEFT", cell, "TOPLEFT", legendX + 11, y)
        local labelW = cell:GetWidth() - legendX - 11 - 38
        lbl:SetWidth(labelW); lbl:SetJustifyH("LEFT"); lbl:SetWordWrap(false)
        lbl:SetText(labelFor(b))

        local count = HDG.UI.RowText(cell, "small", "TextDim")
        count:SetPoint("TOPRIGHT", cell, "TOPRIGHT", -8, y)
        count:SetText(tostring(b.collected))   -- HouseAggregator bySource/byExp guarantees b.collected
    end
end

local function _renderSourceDonut(cell, ed)
    _renderDonutCard(cell, ed,
        function(b) return "source." .. tostring(b.sourceType) end,
        function(b)
            local k = HDG.Constants.SOURCE_KIND_BY_DONOR[b.sourceType]
            return (k and k.label) or ("src " .. tostring(b.sourceType))
        end,
        -- d is the donut data from HouseAggregator's donut selector, which
        -- always stamps collectedAll + totalAll. Strict reads here.
        function(d)
            if d.totalAll > 0 then
                return string.format("%d%%",
                    math.floor(d.collectedAll / d.totalAll * 100 + 0.5))
            end
            return "0%"
        end,
        function(d)
            if d.totalAll > 0 then
                return string.format("%d / %d", d.collectedAll, d.totalAll)
            end
            return nil
        end)
end

-- expansionDonut: same stacked-bar layout as sourceDonut. Center text =
-- collected total (not pct). Uses Palette.expansion.<name> color codes.
local function _renderExpansionDonut(cell, ed)
    _renderDonutCard(cell, ed,
        function(b) return "expansion." .. b.expansion end,
        function(b) return b.expansion end,   -- full name, not short code
        function(d) return tostring(d.collectedAll) end,
        function(_) return "collected" end)
end

-- closeCards: top-3 subcategories with progress bars + "N to go" tail.
local function _renderCloseCards(cell, ed)
    local d = ed.data
    _cardTitle(cell, ed)

    for i, b in ipairs(d.rows) do
        local y = -28 - (i - 1) * 32
        local lbl = HDG.UI.RowText(cell, "body", "Text")
        lbl:SetPoint("TOPLEFT", cell, "TOPLEFT", 8, y)
        lbl:SetText(string.format("%s > %s", b.categoryName, b.subcategoryName))

        local bar = _buildSegmentBar(cell, cell:GetWidth() - 80, 8, 10, b.pct)  -- aggregator-stamped
        bar:SetPoint("TOPLEFT", lbl, "BOTTOMLEFT", 0, -3)

        local tail = HDG.UI.RowText(cell, "small", "TextDim")
        tail:SetPoint("LEFT", bar, "RIGHT", 6, 0)
        tail:SetText(string.format("%d to go", b.gap))
    end
end

-- hotPicks: top-5 list with iconID + name + XP value.
local function _renderHotPicks(cell, ed)
    local d = ed.data
    _cardTitle(cell, ed)

    for i, item in ipairs(d.items) do
        local y = -28 - (i - 1) * 22
        local row = CreateFrame("Button", nil, cell)
        row:SetSize(cell:GetWidth() - 16, 20)
        row:SetPoint("TOPLEFT", cell, "TOPLEFT", 8, y)
        row:RegisterForClicks("LeftButtonUp")

        local icon = HDG.UI.MakeCellIcon(row, 18)  -- chrome-less: locally-created cell child, not a pooled row
        icon:SetPoint("LEFT", row, "LEFT", 0, 0)
        if item.iconID then icon:SetTexture(item.iconID) end

        local name = HDG.UI.RowText(row, "small", "Text")
        name:SetPoint("LEFT", icon, "RIGHT", 4, 0)
        name:SetWidth(row:GetWidth() - 72); name:SetJustifyH("LEFT")
        name:SetWordWrap(false)
        name:SetText(item.name or "?")

        local xp = HDG.UI.RowText(row, "small", "TextStatus")
        xp:SetPoint("RIGHT", row, "RIGHT", -2, 0)
        xp:SetText("+" .. tostring(item.xp or 0))

        if item.itemID and _G.SetItemRef then
            row:SetScript("OnClick", function()
                local link = "item:" .. tostring(item.itemID)
                _G.SetItemRef(link, link, "LeftButton")
            end)
            row._itemID = item.itemID
            HDG.TooltipEngine:Attach(row, _itemTooltipDef)
        end
    end
end

-- velocity: centered label. String composition happens in the renderer (not the selector).
local function _renderVelocity(cell, ed)
    local d = ed.data
    _cardTitle(cell, ed)

    local fs = HDG.UI.RowText(cell, "body", "Text", "CENTER")
    fs:SetPoint("LEFT",  cell, "LEFT",   8, 0)   -- span the cell width so the long
    fs:SetPoint("RIGHT", cell, "RIGHT", -8, 0)   -- "(N days to ...)" line wraps instead of clipping
    fs:SetWordWrap(true)

    if not d.hasActivity then
        fs:SetText("No recent activity")
    else
        local label = string.format("%.1f items/week", d.perWeek)
        if d.daysToNextTier and d.nextTierName then
            label = label .. string.format("  (%d days to %s)",
                d.daysToNextTier, d.nextTierName)
        end
        fs:SetText(label)
    end
end

-- Capacity fill colour as a function of how full you are (disk-usage style): green while
-- there's plenty of space, easing through amber, to red near the cap. Stops anchored to the
-- warn (0.80) / full (0.95) tiers so the colour change lands where the warning matters.
local function _capacityColor(pct)
    local function lerp(a, b, t)
        return { r = a.r + (b.r - a.r) * t, g = a.g + (b.g - a.g) * t, b = a.b + (b.b - a.b) * t }
    end
    local green = HDG.Theme:GetColor("semantic.success")
    local amber = HDG.Theme:GetColor("semantic.warning")
    local red   = HDG.Theme:GetColor("semantic.error")
    if pct <= 0.5 then
        return green
    elseif pct <= 0.8 then
        return lerp(green, amber, (pct - 0.5) / 0.3)
    else
        return lerp(amber, red, math.min(1, (pct - 0.8) / 0.2))
    end
end

-- capacity: 10-segment bar (fill colour tracks how full you are) + label.
local function _renderCapacity(cell, ed)
    local d = ed.data
    _cardTitle(cell, ed)

    -- Whole fill is one pct-driven colour (green -> amber -> red as you near the cap).
    local col = _capacityColor(d.pct)
    local bar = _buildSegmentBar(cell, cell:GetWidth() - 16, 12, 10,
        d.pct, { from = col, to = col })   -- decorOwn selector stamps pct
    bar:SetPoint("CENTER", cell, "CENTER", 0, 4)

    local lbl = HDG.UI.RowText(cell, "small", "Text")
    lbl:SetPoint("TOP", bar, "BOTTOM", 0, -2)
    if d.available then
        lbl:SetText(string.format("%d / %d (%.0f%%)", d.owned, d.max, d.pct * 100))
    else
        lbl:SetText("...")
    end
end

-- featured: 4 icon tiles in a horizontal row.
local function _renderFeatured(cell, ed)
    _cardTitle(cell, ed)

    local d = ed.data
    local tileSize = 56
    local tileGap  = 8
    for i, item in ipairs(d.items) do
        local x = 8 + (i - 1) * (tileSize + tileGap)
        local btn = CreateFrame("Button", nil, cell)
        btn:SetSize(tileSize, tileSize)
        btn:SetPoint("TOPLEFT", cell, "TOPLEFT", x, -28)

        local tex = btn:CreateTexture(nil, "ARTWORK")
        tex:SetAllPoints(); tex:SetTexCoord(unpack(HDG.Constants.ICON_CROP))
        if item.iconID then tex:SetTexture(item.iconID) end

        btn._itemID = item.itemID
        HDG.TooltipEngine:Attach(btn, _itemTooltipDef)

        local lbl = HDG.UI.RowText(cell, "small", "TextDim")
        lbl:SetPoint("TOP", btn, "BOTTOM", 0, -2)
        lbl:SetWidth(tileSize); lbl:SetJustifyH("CENTER")
        lbl:SetWordWrap(true)
        lbl:SetMaxLines(2)   -- cap long names to 2 lines so they can't overflow into the rewards box; full name is in the tile tooltip
        lbl:SetText(item.name or "?")
    end
end

-- multiHouse: 1-3 stacked cards. Each: faction-tinted 2px stripe + name + level + favor bar.
local function _renderMultiHouse(cell, ed)
    _cardTitle(cell, ed)

    local d = ed.data
    if #d.houses == 0 then
        local empty = HDG.UI.RowText(cell, "small", "TextDim")
        empty:SetPoint("CENTER", cell, "CENTER", 0, 0)
        empty:SetText("No owned houses")
        return
    end

    local cardH    = 34
    local cardGap  = 4
    local cardW    = cell:GetWidth() - 16
    local cellH    = cell:GetHeight()
    local startY   = -24
    for i, h in ipairs(d.houses) do
        if i > 3 then break end
        local y = startY - (i - 1) * (cardH + cardGap)
        if -y + cardH > cellH then break end  -- runs out of room

        local card = CreateFrame("Frame", nil, cell, "BackdropTemplate")
        card:SetSize(cardW, cardH)
        card:SetPoint("TOPLEFT", cell, "TOPLEFT", 8, y)
        card:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8x8",
            edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1,
        })
        HDG.Theme:Register(card, "ScrimCard")

        -- Faction stripe (2px left edge), tinted from the Palette faction brand
        -- colors via the shared _TintTexture rail (scheme-invariant brand identity).
        local stripe = card:CreateTexture(nil, "ARTWORK")
        stripe:SetTexture("Interface\\Buttons\\WHITE8x8")
        stripe:SetPoint("TOPLEFT", card, "TOPLEFT", 0, 0)
        stripe:SetPoint("BOTTOMLEFT", card, "BOTTOMLEFT", 0, 0)
        stripe:SetWidth(2)
        HDG.UI._TintTexture(stripe,
            HDG.Palette:GetColor("faction." .. (h.faction or "")) or HDG.Palette:GetColor("faction.Neutral"))

        -- House name (top line)
        local name = HDG.UI.RowText(card, "small", "Text")
        name:SetPoint("TOPLEFT", card, "TOPLEFT", 8, -4)
        name:SetWidth(cardW - 60); name:SetJustifyH("LEFT"); name:SetWordWrap(false)
        name:SetText(h.name or "?")

        -- Level badge (top right)
        local level = HDG.UI.RowText(card, "small", "TextStatus")
        level:SetPoint("TOPRIGHT", card, "TOPRIGHT", -6, -4)
        level:SetText(h.level and ("Lvl " .. tostring(h.level)) or "...")

        local bar = CreateFrame("StatusBar", nil, card)
        bar:SetSize(cardW - 14, 6)
        bar:SetPoint("BOTTOMLEFT", card, "BOTTOMLEFT", 7, 4)
        bar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
        local pct = 0
        if h.level and h.maxLevel and h.thresholds and h.level < h.maxLevel then
            -- h.thresholds is a sparse map [level] = required favor.
            -- The outer guard ensures level < maxLevel; absent keys at
            -- the boundary edges resolve to 0 (clamps pct to 0%).
            local thisLvl = h.thresholds[h.level] or 0      -- exception(boundary): sparse map
            local nextLvl = h.thresholds[h.level + 1] or 0  -- exception(boundary): sparse map
            local span = nextLvl - thisLvl
            if span > 0 then pct = math.min(1, math.max(0, ((h.favor or 0) - thisLvl) / span)) end
        elseif h.level and h.maxLevel and h.level >= h.maxLevel then
            pct = 1
        end
        bar:SetMinMaxValues(0, 1); bar:SetValue(pct)
        HDG.Theme:Register(bar, "progressbar", { variant = (pct >= 1) and "success" or "accent" })
    end
end

-- favorites: top 5 favorited items; icon + name; collected items are
-- normal text, uncollected are dim. Empty state when no favorites.
local function _renderFavorites(cell, ed)
    local d = ed.data
    _cardTitle(cell, ed)

    local items = d.items
    if #items == 0 then
        local empty = HDG.UI.RowText(cell, "small", "TextDim")
        empty:SetPoint("CENTER", cell, "CENTER", 0, 0)
        empty:SetText("No favorites yet")
        return
    end

    for i, item in ipairs(items) do
        local y = -28 - (i - 1) * 22
        if item.iconID then
            local icon = cell:CreateTexture(nil, "ARTWORK")
            icon:SetSize(16, 16)
            icon:SetPoint("TOPLEFT", cell, "TOPLEFT", 8, y)
            icon:SetTexture(item.iconID)
        end
        local name = HDG.UI.RowText(cell, "small", item.isCollected and "Text" or "TextDim")
        name:SetPoint("TOPLEFT", cell, "TOPLEFT", 28, y - 1)
        name:SetWidth(cell:GetWidth() - 36); name:SetJustifyH("LEFT")
        name:SetWordWrap(false)
        name:SetText(item.name)
    end
end

-- themedSets: top 4 buckets; name + segment bar + N/M label.
local function _renderThemedSets(cell, ed)
    local d = ed.data
    _cardTitle(cell, ed)

    local sets = d.sets
    if #sets == 0 then
        local empty = HDG.UI.RowText(cell, "small", "TextDim")
        empty:SetPoint("CENTER", cell, "CENTER", 0, 0)
        empty:SetText("No themed sets meet the threshold")
        return
    end

    local barW = math.floor((cell:GetWidth() - 16) / math.min(4, #sets)) - 4
    for i, s in ipairs(sets) do
        if i > 4 then break end
        local x = 8 + (i - 1) * (barW + 4)

        local name = HDG.UI.RowText(cell, "small", "Text")
        name:SetPoint("TOPLEFT", cell, "TOPLEFT", x, -28)
        name:SetWidth(barW); name:SetJustifyH("LEFT")
        name:SetWordWrap(false)
        name:SetText(s.name)

        -- 10-segment bar: warning -> success (amber fills up to green).
        local bar = _buildSegmentBar(cell, barW, 8, 10, s.pct)   -- HouseAggregator topStyles stamps pct
        bar:SetPoint("TOPLEFT", cell, "TOPLEFT", x, -46)

        local count = HDG.UI.RowText(cell, "small", "TextDim")
        count:SetPoint("TOPLEFT", cell, "TOPLEFT", x, -58)
        count:SetText(string.format("%d / %d", s.collected, s.total))
    end
end

-- topVendors: top 3 vendors by uncollected count; name + zone + count.
local function _renderTopVendors(cell, ed)
    local d = ed.data
    _cardTitle(cell, ed)

    local rows = d.rows
    if #rows == 0 then
        local empty = HDG.UI.RowText(cell, "small", "TextDim")
        empty:SetPoint("CENTER", cell, "CENTER", 0, 0)
        empty:SetText("All vendor items collected")
        return
    end

    for i, r in ipairs(rows) do
        local y = -28 - (i - 1) * 32
        local name = HDG.UI.RowText(cell, "small", "Text")
        name:SetPoint("TOPLEFT", cell, "TOPLEFT", 8, y)
        name:SetWidth(cell:GetWidth() - 56); name:SetJustifyH("LEFT")
        name:SetWordWrap(false)
        name:SetText(r.name)

        if r.zone then
            local zone = HDG.UI.RowText(cell, "small", "TextDim")
            zone:SetPoint("TOPLEFT", cell, "TOPLEFT", 8, y - 14)
            zone:SetWidth(cell:GetWidth() - 56); zone:SetJustifyH("LEFT")
            zone:SetWordWrap(false)
            zone:SetText(r.zone)
        end

        local count = HDG.UI.RowText(cell, "body", "TextStatus")
        count:SetPoint("TOPRIGHT", cell, "TOPRIGHT", -8, y - 4)
        count:SetText(tostring(r.uncollected))
    end
end

-- recentActivity: last 5 learned entries; icon + name (pre-joined by selector into ed.data).
local function _renderRecentActivity(cell, ed)
    local d = ed.data
    _cardTitle(cell, ed)

    local entries = d.entries
    if #entries == 0 then
        local empty = HDG.UI.RowText(cell, "small", "TextDim")
        empty:SetPoint("CENTER", cell, "CENTER", 0, 0)
        empty:SetText("No recent decor learns")
        return
    end
    for i, e in ipairs(entries) do
        local y = -28 - (i - 1) * 20
        if e.iconID then
            local icon = cell:CreateTexture(nil, "ARTWORK")
            icon:SetSize(14, 14)
            icon:SetPoint("TOPLEFT", cell, "TOPLEFT", 8, y - 1)
            icon:SetTexture(e.iconID)
        end
        local fs = HDG.UI.RowText(cell, "small", "Text")
        fs:SetPoint("TOPLEFT", cell, "TOPLEFT", 26, y - 1)
        fs:SetWidth(cell:GetWidth() - 34); fs:SetJustifyH("LEFT")
        fs:SetWordWrap(false)
        fs:SetText(e.name)
    end
end

-- Chip strip: pills wrapping across rows, "label: count" with optional
-- expansion-tinted label + green checkmark when need is satisfied. Ported
-- from HDG's Patterns.ChipStrip (HDG_HT_Patterns.lua:664). Chip backdrop
-- uses the "Frame" Skinner so it picks up surface.panel + border.default
-- on every scheme. Overflow that runs past the cell height is hidden via
-- SetClipsChildren -- no bleed into the row below.
local function _renderChipStrip(cell, title, chips, opts)
    opts = opts or {}
    local chipH   = opts.chipHeight or 18  -- exception(optional): option default
    local chipGap = opts.chipGap or 4  -- exception(optional): option default

    local titleFS = HDG.UI.RowText(cell, "subheading", "Text")
    titleFS:SetPoint("TOPLEFT", cell, "TOPLEFT", 8, -6)
    titleFS:SetText(title)

    if #chips == 0 then
        local empty = HDG.UI.RowText(cell, "small", "TextDim")
        empty:SetPoint("CENTER", cell, "CENTER", 0, 0)
        empty:SetText(opts.emptyLabel or "Empty")
        return
    end

    local availW = (cell:GetWidth() or 100) - 16
    local maxY   = -((cell:GetHeight() or 100) - 6)
    local x, y   = 8, -26

    if cell.SetClipsChildren then cell:SetClipsChildren(true) end  -- exception(boundary): SetClipsChildren may not exist on all WoW frame types

    for _, c in ipairs(chips) do
        local chip = CreateFrame("Frame", nil, cell, "BackdropTemplate")
        chip:SetHeight(chipH)
        HDG.Theme:Register(chip, "Frame")

        local fs = HDG.UI.RowText(chip, "small", c.sufficient and "TextStatus" or "Text")
        fs:SetWordWrap(false)
        fs:SetPoint("LEFT",  chip, "LEFT",   6, 0)
        fs:SetPoint("RIGHT", chip, "RIGHT", -6, 0)

        local label = c.color and (c.color .. c.label .. "|r") or c.label
        local mark  = c.sufficient and "  |TInterface\\RAIDFRAME\\ReadyCheck-Ready:0|t" or ""
        fs:SetText(string.format("%s: %s%s", label, c.count, mark))

        local w = (fs.GetUnboundedStringWidth and fs:GetUnboundedStringWidth() or 80) + 16
        chip:SetWidth(w)

        if x + w > availW + 8 and x > 8 then
            x = 8; y = y - chipH - chipGap
        end
        if y < maxY then chip:Hide(); break end
        chip:SetPoint("TOPLEFT", cell, "TOPLEFT", x, y)
        x = x + w + chipGap
    end
end

-- lumberWallet: per-lumber-type counts as chips. Name tinted by expansion.
local function _renderLumberWallet(cell, ed)
    local d   = ed.data
    local fmt = _G.BreakUpLargeNumbers or tostring
    local chips = {}
    for _, t in ipairs(d.types) do
        chips[#chips + 1] = {
            label = t.name,
            count = fmt(t.count),
            color = t.expansion and HDG.Palette:ColorCode("expansion." .. t.expansion) or nil,
        }
    end
    _renderChipStrip(cell, ed.title, chips, { emptyLabel = "No lumber in bags" })
    -- Top-right shortcut to the Crafting > Warehouse tab (where lumber is managed).
    -- Created per render (cell is rebuilt + released on Reset, like the chips above).
    local toWarehouse = HDG.UI:Button(cell, "Warehouse", "small")
    toWarehouse:SetSize(72, 18)
    toWarehouse:SetPoint("TOPRIGHT", cell, "TOPRIGHT", -6, -5)
    toWarehouse:SetScript("OnClick", function()
        HDG.Store:Dispatch({ type = HDG.Constants.ACTIONS.UI_SET_PERSISTENT,
            payload = { key = "view", value = "warehouse" } })
    end)
end

-- decorCurrency: housing currencies as chips. Name tinted by expansion;
-- "have / need" ratio + green checkmark when need is set and satisfied.
-- Until the needs-walk lands (parse cost from row.vendors[].cost), needed
-- is always 0 -- chips render as plain "have" without sufficient highlight.
local function _renderDecorCurrency(cell, ed)
    local d   = ed.data
    local fmt = _G.BreakUpLargeNumbers or tostring
    local chips = {}
    for _, c in ipairs(d.currencies) do
        local need = c.needed or 0
        local countText, sufficient
        if need > 0 then
            countText  = string.format("%s / %s", fmt(c.count), fmt(need))
            sufficient = c.count >= need
        else
            countText  = fmt(c.count)
            sufficient = false  -- no need data -> no green highlight
        end
        chips[#chips + 1] = {
            label = c.name,
            count = countText,
            color = c.expansion and HDG.Palette:ColorCode("expansion." .. c.expansion) or nil,
            sufficient = sufficient,
        }
    end
    _renderChipStrip(cell, ed.title, chips, { emptyLabel = "No housing currencies tracked" })
end

-- Shared event-card renderer: title + icon shelf (collected full-alpha,
-- uncollected dim) + N/M (P%) progress strip on the bottom. Used for
-- ritualSites / abyssAnglers / decorDuels.
local function _renderEventCard(cell, ed)
    local d = ed.data
    _cardTitle(cell, ed)

    if d.total == 0 then
        local empty = HDG.UI.RowText(cell, "small", "TextDim")
        empty:SetPoint("CENTER", cell, "CENTER", 0, 0)
        empty:SetText("Vendor data not loaded")
        return
    end

    local iconSize = 28
    local gap      = 4
    local maxX     = cell:GetWidth() - 8
    local x, y     = 8, -28
    for i, item in ipairs(d.items) do
        if y - iconSize < -(cell:GetHeight() - 18) then break end
        local icon = HDG.UI.MakeCellIcon(cell, iconSize)
        icon:SetPoint("TOPLEFT", cell, "TOPLEFT", x, y)
        icon:SetTexture(item.iconID or "Interface\\Icons\\INV_Misc_QuestionMark")
        icon:SetAlpha(item.owned and 1.0 or 0.35)
        if not item.owned then icon:SetDesaturated(true) end
        x = x + iconSize + gap
        if x + iconSize > maxX then
            x = 8; y = y - iconSize - gap
        end
        if i >= 36 then break end
    end

    local prog = HDG.UI.RowText(cell, "small", "TextDim")
    prog:SetPoint("BOTTOMLEFT", cell, "BOTTOMLEFT", 8, 4)
    prog:SetText(string.format("%d / %d  (%d%%)",
        d.collected, d.total, math.floor(d.pct * 100 + 0.5)))
end

-- nextRewards: value-type rewards render "Bonus name: old -> new"; object
-- rewards render "Icon Name". At max level, shows the final-level recap.
local VALUE_TYPE_LABELS = {}
-- VALUE-type budget rewards ship with empty icon; map each valueType to a real atlas.
local VALUE_TYPE_ATLAS = {}

local function _ensureValueLabels()
    if next(VALUE_TYPE_LABELS) then return end
    local E = _G.Enum and _G.Enum.HouseLevelRewardValueType
    if not E then return end
    VALUE_TYPE_LABELS[E.InteriorDecor] = _G.HOUSING_DASHBOARD_REWARD_INTERIOR_BUDGET or "Interior Decor Budget"
    VALUE_TYPE_LABELS[E.ExteriorDecor] = _G.HOUSING_DASHBOARD_REWARD_EXTERIOR_BUDGET or "Exterior Decor Budget"
    VALUE_TYPE_LABELS[E.Rooms]         = _G.HOUSING_DASHBOARD_REWARD_ROOM_BUDGET     or "Room Budget"
    VALUE_TYPE_LABELS[E.Fixtures]      = _G.HOUSING_DASHBOARD_REWARD_FIXTURE_BUDGET  or "Fixture Budget"
    VALUE_TYPE_ATLAS[E.Rooms]          = "house-room-limit-icon"
    VALUE_TYPE_ATLAS[E.InteriorDecor]  = "house-decor-budget-icon"
    VALUE_TYPE_ATLAS[E.ExteriorDecor]  = "house-decor-budget-icon"
    VALUE_TYPE_ATLAS[E.Fixtures]       = "house-decor-budget-icon"
end

local function _renderNextRewards(cell, ed)
    local d = ed.data
    _cardTitle(cell, ed)

    if not d then
        local fs = HDG.UI.RowText(cell, "small", "TextDim")
        fs:SetPoint("CENTER", cell, "CENTER", 0, 0)
        fs:SetText("No active house yet")
        return
    end

    local chipText = d.atMax and string.format("Max Level (%d)", d.maxLevel)
                     or string.format("Lvl %d ->", d.targetLevel)
    local chip = HDG.UI.RowText(cell, "small", "TextStatus")
    chip:SetPoint("TOPRIGHT", cell, "TOPRIGHT", -8, -8)
    chip:SetText(chipText)

    if not d.rewards then
        local fs = HDG.UI.RowText(cell, "small", "TextDim")
        fs:SetPoint("CENTER", cell, "CENTER", 0, 0)
        fs:SetText("Loading rewards...")
        return
    end

    _ensureValueLabels()
    local VALUE_TYPE = (_G.Enum and _G.Enum.HouseLevelRewardType
                         and _G.Enum.HouseLevelRewardType.Value) or 0
    local accent  = HDG.Theme:ColorCode("semantic.accent")
    local success = HDG.Theme:ColorCode("semantic.success")

    local rowH    = 28
    local iconSz  = 22
    for i, r in ipairs(d.rewards) do
        if i > 4 then break end
        local y = -28 - (i - 1) * rowH

        local icon = HDG.UI.MakeCellIcon(cell, iconSz)
        icon:SetPoint("TOPLEFT", cell, "TOPLEFT", 8, y)
        if r.iconTexture then
            icon:SetTexture(r.iconTexture)
        elseif r.iconAtlas and icon.SetAtlas then
            icon:SetAtlas(r.iconAtlas)
        elseif r.type == VALUE_TYPE and VALUE_TYPE_ATLAS[r.valueType] then
            icon:SetAtlas(VALUE_TYPE_ATLAS[r.valueType])  -- budget rewards ship no icon
        else
            icon:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
        end

        local lineA = HDG.UI.RowText(cell, "small", "Text")
        lineA:SetPoint("TOPLEFT", icon, "TOPRIGHT", 6, 0)
        lineA:SetPoint("RIGHT", cell, "RIGHT", -8, 0)
        lineA:SetJustifyH("LEFT"); lineA:SetWordWrap(false)

        local lineB = HDG.UI.RowText(cell, "small", "TextDim")
        lineB:SetPoint("TOPLEFT", lineA, "BOTTOMLEFT", 0, -1)
        lineB:SetPoint("RIGHT", cell, "RIGHT", -8, 0)
        lineB:SetJustifyH("LEFT"); lineB:SetWordWrap(false)

        if r.type == VALUE_TYPE then
            local label = VALUE_TYPE_LABELS[r.valueType] or ("Bonus " .. tostring(r.valueType or "?"))
            lineA:SetText(label)
            local oldV, newV = r.oldValue or 0, r.newValue or 0  -- exception(boundary): Blizz review record fields are optional
            if newV ~= oldV then
                lineB:SetText(string.format("%s%d|r -> %s%d|r", accent, oldV, success, newV))
            else
                lineB:SetText(string.format("%s%d|r", accent, newV))
            end
        else
            lineA:SetText(r.objectName or "Reward")
            lineB:SetText("")
        end
    end
end

-- craftableNow: big number + "decor items now" + "+N almost craftable".
local function _renderCraftableNow(cell, ed)
    local d = ed.data
    _cardTitle(cell, ed)

    local n = d.canCraftNow  -- recipes.almostCraftable stamps canCraftNow (0-default fallback)
    local big = HDG.UI.RowText(cell, "heading", n > 0 and "TextStatus" or "TextDim")
    big:SetPoint("CENTER", cell, "CENTER", 0, 6)
    big:SetText(tostring(n))

    local sub = HDG.UI.RowText(cell, "small", "Text")
    sub:SetPoint("TOP", big, "BOTTOM", 0, -2)
    sub:SetText(n > 0 and "decor items now" or "nothing in your bags")

    if (d.almostCraftable or 0) > 0 then
        local extra = HDG.UI.RowText(cell, "small", "TextDim")
        extra:SetPoint("TOP", sub, "BOTTOM", 0, -2)
        extra:SetText(string.format("+%d almost craftable", d.almostCraftable))
    end
end

-- goblinTopLumber: top-5 rows; name colored by expansion + gold-per-lumber chip.
local function _renderGoblinTopLumber(cell, ed)
    local d = ed.data
    _cardTitle(cell, ed)

    local items = d.items
    if #items == 0 then
        local empty = HDG.UI.RowText(cell, "small", "TextDim")
        empty:SetPoint("CENTER", cell, "CENTER", 0, 0)
        empty:SetText("No profit data yet")
        return
    end

    local rowH    = 22
    local iconSz  = 18
    for i, it in ipairs(items) do
        local y = -28 - (i - 1) * rowH
        local icon = HDG.UI.MakeCellIcon(cell, iconSz)
        icon:SetPoint("TOPLEFT", cell, "TOPLEFT", 8, y)
        icon:SetTexture(it.iconID or "Interface\\Icons\\INV_Misc_QuestionMark")

        local name = HDG.UI.RowText(cell, "small", "Text")
        name:SetPoint("LEFT", icon, "RIGHT", 4, 0)
        name:SetPoint("RIGHT", cell, "RIGHT", -50, 0)
        name:SetJustifyH("LEFT"); name:SetWordWrap(false)
        local label = it.name or ("Item " .. tostring(it.itemID or "?"))
        if it.expansion then
            local hex = HDG.Expansion.GetColorHex(it.expansion)   -- nil for unknown expansion names
            if hex then label = hex .. label .. "|r" end
        end
        name:SetText(label)

        -- Gold-per-lumber chip: copper -> compact gold/silver/copper.
        local v = it.lumberValue  -- topByValue list filtered to lumberValue>0 (HouseAggregator:274/288)
        local chipText
        if v >= 10000 then chipText = string.format("%dg/lum", math.floor(v / 10000))
        elseif v >= 100  then chipText = string.format("%ds/lum", math.floor(v / 100))
        else                  chipText = string.format("%dc/lum", v) end
        local chip = HDG.UI.RowText(cell, "small", "TextStatus")
        chip:SetPoint("RIGHT", cell, "RIGHT", -8, 0)
        chip:SetPoint("TOP", icon, "TOP", 0, 0)
        chip:SetText(chipText)
    end
end

-- records: stat-line widget. Each stat is a labelled value row.
local function _renderRecords(cell, ed)
    local d = ed.data
    _cardTitle(cell, ed)

    local lines = {}
    local function fmt(n) return (_G.BreakUpLargeNumbers and _G.BreakUpLargeNumbers(n)) or tostring(n) end
    if d.bestDay > 0 then
        local lbl = "Best day"
        if d.bestDate then
            local m, dy = d.bestDate:match("%d+-(%d+)-(%d+)")
            if m and dy then lbl = lbl .. "  (" .. m .. "/" .. dy .. ")" end
        end
        lines[#lines + 1] = { label = lbl, value = fmt(d.bestDay) .. " events" }
    end
    if d.longestStreak > 0 then
        lines[#lines + 1] = { label = "Longest streak", value = d.longestStreak .. " days" }
    end
    if d.houseAgeDays > 0 then
        lines[#lines + 1] = { label = "Activity age", value = d.houseAgeDays .. " days" }
    end
    if d.totalLearned > 0 then
        lines[#lines + 1] = { label = "Decor learned", value = fmt(d.totalLearned) }
    end
    if d.totalCrafted > 0 then
        lines[#lines + 1] = { label = "Decor crafted", value = fmt(d.totalCrafted) }
    end
    if #lines == 0 then
        lines[1] = { label = "Records", value = "no data yet" }
    end

    for i, line in ipairs(lines) do
        local y = -28 - (i - 1) * 16
        local lbl = HDG.UI.RowText(cell, "small", "TextDim")
        lbl:SetPoint("TOPLEFT", cell, "TOPLEFT", 8, y)
        lbl:SetText(line.label)

        local val = HDG.UI.RowText(cell, "small", "TextStatus")
        val:SetPoint("TOPRIGHT", cell, "TOPRIGHT", -8, y)
        val:SetText(line.value)
    end
end

local function _renderEmptyCard(cell, ed)
    local title = HDG.UI.RowText(cell, "subheading", "Text", "LEFT")
    title:SetPoint("TOPLEFT", cell, "TOPLEFT", 8, -6)
    title:SetText(ed.title or ed.id)

    local badge = HDG.UI.RowText(cell, "small", "TextDim", "RIGHT")
    badge:SetPoint("TOPRIGHT", cell, "TOPRIGHT", -8, -8)
    -- Placeholder debug badge -- "?" and 0 are visible missing-data
    -- markers so a future spec-fill pass can target the gaps.
    badge:SetText(string.format("%s  %dh", ed.width or "?", ed.height or 0))  -- exception(nullable): missing-data display marker
    local idFs = HDG.UI.RowText(cell, "small", "TextDim")
    idFs:SetPoint("BOTTOMLEFT", cell, "BOTTOMLEFT", 8, 6)
    idFs:SetText(ed.id or "?")
end

local function _initDashboardRow(row, ed)
    -- Clear children from prior elementData (frame reuse).
    if row._cells then
        for _, c in ipairs(row._cells) do c:Hide(); c:SetParent(nil) end
    end
    row._cells = {}

    HDG.Theme:Register(row, "RowChrome")

    -- Cell sizing: subtract actual gap budget for THIS row (one gap per join), divide by 3.
    -- Result: every row's last cell aligns to the panel right edge.
    local rowW       = row:GetWidth() or 0  -- exception(boundary): frame geometry nil before first layout
    local rowH       = ed.height or 100  -- exception(optional): row height 100px fallback when def omits defaultHeight
    local numCells   = #ed.cells
    local gapBudget  = math.max(0, numCells - 1) * CELL_GAP
    local available  = math.max(0, rowW - gapBudget)
    local unitW      = available / 3

    local cursorX = 0
    for i, cellSpec in ipairs(ed.cells) do
        local w = unitW * cellSpec.units
        local cell = CreateFrame("Frame", nil, row, "BackdropTemplate")
        cell:SetSize(w, rowH)
        cell:SetPoint("TOPLEFT", row, "TOPLEFT", cursorX, 0)
        cell:SetBackdrop({
            bgFile   = "Interface\\Tooltips\\UI-Tooltip-Background",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            tile     = true, tileSize = 16, edgeSize = 10,
            insets   = { left = 3, right = 3, top = 3, bottom = 3 },
        })
        HDG.Theme:Register(cell, "Frame")
        -- Dispatch on cell.id; unknown ids fall through to empty-card placeholder.
        local id = cellSpec.id
        if     id == "decoratorProfile" then _renderDecoratorProfile(cell, cellSpec)
        elseif id == "styleAffinity"    then _renderStyleAffinity(cell, cellSpec)
        elseif id == "sourceDonut"      then _renderSourceDonut(cell, cellSpec)
        elseif id == "expansionDonut"   then _renderExpansionDonut(cell, cellSpec)
        elseif id == "closeCards"       then _renderCloseCards(cell, cellSpec)
        elseif id == "hotPicks"         then _renderHotPicks(cell, cellSpec)
        elseif id == "velocity"         then _renderVelocity(cell, cellSpec)
        elseif id == "capacity"         then _renderCapacity(cell, cellSpec)
        elseif id == "featured"         then _renderFeatured(cell, cellSpec)
        elseif id == "multiHouse"       then _renderMultiHouse(cell, cellSpec)
        elseif id == "favorites"        then _renderFavorites(cell, cellSpec)
        elseif id == "themedSets"       then _renderThemedSets(cell, cellSpec)
        elseif id == "topVendors"       then _renderTopVendors(cell, cellSpec)
        elseif id == "recentActivity"   then _renderRecentActivity(cell, cellSpec)
        elseif id == "lumberWallet"     then _renderLumberWallet(cell, cellSpec)
        elseif id == "decorCurrency"    then _renderDecorCurrency(cell, cellSpec)
        elseif id == "ritualSites"      then _renderEventCard(cell, cellSpec)
        elseif id == "abyssAnglers"     then _renderEventCard(cell, cellSpec)
        elseif id == "decorDuels"       then _renderEventCard(cell, cellSpec)
        elseif id == "nextRewards"      then _renderNextRewards(cell, cellSpec)
        elseif id == "craftableNow"     then _renderCraftableNow(cell, cellSpec)
        elseif id == "goblinTopLumber"  then _renderGoblinTopLumber(cell, cellSpec)
        elseif id == "records"          then _renderRecords(cell, cellSpec)
        else _renderEmptyCard(cell, cellSpec)
        end
        row._cells[#row._cells + 1] = cell
        cursorX = cursorX + w + CELL_GAP
    end
end

HDG.Rows:Register("houseTabWidgetRow", {
    font   = "body",
    height = function(_index, ed)
        return (ed and ed.height) or 100
    end,
    factory = function(_def)
        return {
            Configure = _initDashboardRow,
            Reset     = function(row)
                if row._cells then
                    for _, c in ipairs(row._cells) do c:Hide(); c:SetParent(nil) end
                    row._cells = nil
                end
            end,
        }
    end,
    key = function(ed)
        if not ed then return "?" end
        return ed.id or "?"
    end,
})

-- ============================================================================
-- Picker row factory: [toggle] [title fill] [width btns] [up] [down].
-- ============================================================================

local PICKER_ROW_H     = 22
local PICKER_BTN_W     = 22
local PICKER_TOGGLE_W  = 18
local PICKER_WIDTH_BTN = 28   -- 1/3 / 2/3 / Full buttons

local WIDTH_OPTIONS = {
    { label = "1/3",  value = "third"     },
    { label = "2/3",  value = "twoThirds" },
    { label = "Full", value = "full"      },
}

local function _swapOrder(thisID, thisOrder, otherID, otherOrder)
    if not (otherID and otherOrder and thisOrder) then return end
    HDG.Store:Dispatch({
        type    = Constants.ACTIONS.HOUSETAB_SET_ORDER,
        payload = { widgetID = thisID,  order = otherOrder },
    })
    HDG.Store:Dispatch({
        type    = Constants.ACTIONS.HOUSETAB_SET_ORDER,
        payload = { widgetID = otherID, order = thisOrder },
    })
end

local function _initPickerRow(row, ed)
    if not row._pickerLaidOut then
        row._pickerLaidOut = true

        -- Toggle: a tiny square. Filled when enabled, hollow when not.
        local toggle = CreateFrame("Button", nil, row, "BackdropTemplate")
        toggle:SetSize(PICKER_TOGGLE_W, PICKER_TOGGLE_W)
        toggle:SetPoint("LEFT", row, "LEFT", 4, 0)
        toggle:SetBackdrop({
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            edgeSize = 8,
            insets   = { left = 2, right = 2, top = 2, bottom = 2 },
        })
        local fill = toggle:CreateTexture(nil, "ARTWORK")
        fill:SetPoint("TOPLEFT", toggle, "TOPLEFT", 3, -3)
        fill:SetPoint("BOTTOMRIGHT", toggle, "BOTTOMRIGHT", -3, 3)
        toggle._fill = fill
        HDG.Theme:Register(toggle, "Frame")
        row._toggle = toggle

        -- Title (anchors range set below once we know the width-buttons cluster).
        local title = HDG.UI.RowText(row, "body", "Text", "LEFT")
        title:SetPoint("LEFT", toggle, "RIGHT", 6, 0)
        title:SetWordWrap(false)
        row._title = title

        -- Down arrow (rightmost). Themed tertiary button -- SetButtonState/Enable
        -- (used per-bind below) are base Button methods, so the pressed/disabled
        -- atlases drive the active/disabled look (no raw Blizzard-template gold).
        local down = HDG.UI:Button(row, "v", "small")
        down:SetSize(PICKER_BTN_W, PICKER_ROW_H - 4)
        down:SetPoint("RIGHT", row, "RIGHT", -4, 0)
        row._down = down

        -- Up arrow (left of Down).
        local up = HDG.UI:Button(row, "^", "small")
        up:SetSize(PICKER_BTN_W, PICKER_ROW_H - 4)
        up:SetPoint("RIGHT", down, "LEFT", -2, 0)
        row._up = up

        -- Width selector cluster: 3 small buttons (1/3 / 2/3 / Full).
        -- Anchor right-to-left from the Up arrow so the title's right
        -- edge stops at the leftmost width button.
        row._widthBtns = {}
        local anchor = up
        for i = #WIDTH_OPTIONS, 1, -1 do
            local opt = WIDTH_OPTIONS[i]
            local btn = HDG.UI:Button(row, opt.label, "small")
            btn:SetSize(PICKER_WIDTH_BTN, PICKER_ROW_H - 4)
            btn:SetPoint("RIGHT", anchor, "LEFT", -2, 0)
            btn._value = opt.value
            row._widthBtns[i] = btn
            anchor = btn
        end

        -- Title's right edge stops at the leftmost width button.
        title:SetPoint("RIGHT", row._widthBtns[1], "LEFT", -4, 0)
    end

    -- Re-bind per row.
    row._title:SetText(ed.title or ed.id)

    -- Toggle fill state.
    if ed.enabled then
        row._toggle._fill:SetColorTexture(0.2, 0.8, 0.4, 0.9)
    else
        row._toggle._fill:SetColorTexture(0, 0, 0, 0)
    end
    row._toggle:SetScript("OnClick", function()
        HDG.Store:Dispatch({
            type    = Constants.ACTIONS.HOUSETAB_TOGGLE_WIDGET,
            payload = { widgetID = ed.id },
        })
    end)

    for _, btn in ipairs(row._widthBtns) do
        if btn._value == ed.width then
            btn:SetButtonState("PUSHED", true)
        else
            btn:SetButtonState("NORMAL", false)
        end
        local value = btn._value
        btn:SetScript("OnClick", function()
            HDG.Store:Dispatch({
                type    = Constants.ACTIONS.HOUSETAB_SET_WIDTH,
                payload = { widgetID = ed.id, width = value },
            })
        end)
    end

    -- Arrow handlers. Disable when no neighbour.
    if ed.prevID then
        row._up:Enable()
        row._up:SetScript("OnClick", function()
            _swapOrder(ed.id, ed.order, ed.prevID, ed.prevOrder)
        end)
    else
        row._up:Disable()
        row._up:SetScript("OnClick", nil)
    end
    if ed.nextID then
        row._down:Enable()
        row._down:SetScript("OnClick", function()
            _swapOrder(ed.id, ed.order, ed.nextID, ed.nextOrder)
        end)
    else
        row._down:Disable()
        row._down:SetScript("OnClick", nil)
    end

    HDG.Theme:Register(row._title, ed.enabled and "Text" or "TextDim")
end

HDG.Rows:Register("houseTabPickerRow", {
    font    = "body",
    height  = PICKER_ROW_H,
    factory = function(_def)
        return {
            Configure = _initPickerRow,
            Reset     = function(row)
                if row._up    then row._up:SetScript("OnClick", nil) end
                if row._down  then row._down:SetScript("OnClick", nil) end
                if row._toggle then row._toggle:SetScript("OnClick", nil) end
            end,
        }
    end,
    key = function(ed)
        if not ed then return "?" end
        return "pick:" .. (ed.id or "?")
    end,
})

-- ============================================================================
-- Picker drag-to-reorder. AddLinearDragBehavior for candidate + visuals; OnDragStop
-- REPLACED (never mutates data provider; dispatches HOUSETAB_REORDER_WIDGET instead).
-- ============================================================================

-- Visual config (mirrors ConfigureDragBehavior without the default OnDragStop).
-- Cursor factory uses BackdropTemplate (not "Button" -- pool chokes on non-XML templates).
local function _setupPickerDragVisuals(behavior)
    behavior:SetDragRelativeToCursor(true)
    behavior:SetNotifyDragStart(function(sourceFrame, dragging)
        sourceFrame:SetAlpha(dragging and 0.5 or 1)
        sourceFrame:SetMouseMotionEnabled(not dragging)
    end)
    behavior:SetNotifyDropCandidates(function(candidateFrame, dragging, _sourceED)
        candidateFrame:SetMouseMotionEnabled(not dragging)
    end)
    behavior:SetCursorFactory(function(_elementData)
        return "BackdropTemplate", function(cursorFrame, candidateFrame, _ed)
            cursorFrame:SetSize(candidateFrame:GetSize())
            if not cursorFrame._hdgrCursorPainted then
                cursorFrame._hdgrCursorPainted = true
                cursorFrame:SetBackdrop({
                    bgFile   = "Interface\\Tooltips\\UI-Tooltip-Background",
                    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
                    edgeSize = 8, tileSize = 16, tile = true,
                    insets   = { left = 2, right = 2, top = 2, bottom = 2 },
                })
                cursorFrame:SetBackdropColor(0.20, 0.50, 0.90, 0.55)
                cursorFrame:SetBackdropBorderColor(0.40, 0.70, 1.00, 0.85)
            end
        end
    end)
end

-- Blue drop-line indicator above/below the candidate frame.
local function _attachPickerDropLinePreview(behavior)
    behavior:SetDropEnter(function(factory, candidate)
        local DIA = _G.DragIntersectionArea
        if not (DIA and candidate and candidate.frame) then return end
        if candidate.area == DIA.Above then
            local line = factory("ScrollBoxDragLineTemplate")
            line:SetPoint("BOTTOMLEFT",  candidate.frame, "TOPLEFT",  0,  3)
            line:SetPoint("BOTTOMRIGHT", candidate.frame, "TOPRIGHT", 0,  3)
        elseif candidate.area == DIA.Below then
            local line = factory("ScrollBoxDragLineTemplate")
            line:SetPoint("TOPLEFT",     candidate.frame, "BOTTOMLEFT",  0, -3)
            line:SetPoint("TOPRIGHT",    candidate.frame, "BOTTOMRIGHT", 0, -3)
        end
    end)
end

-- Cleanup matches OnDragStopInternal up to the "handled" branch; skips data-provider mutation.
local function _cleanupPickerDragState(behavior)
    behavior.delegate:SetScript("OnUpdate", nil)
    behavior:DropLeave()
    behavior:NotifyStates(false)
    behavior.delegate.pools:ReleaseAll()
    behavior.dropPreview = nil
    behavior.cursorFrame = nil
    behavior:SetDragging(false)
end

-- Resolve (srcID, srcIdx, dstIdx, area). Returns nil on any missing piece (drag aborted).
local function _resolvePickerDropTarget(behavior)
    local DIA = _G.DragIntersectionArea
    if not DIA then return nil end
    local candidate  = behavior.candidate
    local sourceData = behavior.sourceData
    if not (candidate and candidate.elementData and candidate.frame and sourceData) then
        return nil
    end
    local srcID  = sourceData.elementData and sourceData.elementData.id
    local srcIdx = sourceData.elementDataIndex
    local dstIdx = candidate.frame.GetElementDataIndex
        and candidate.frame:GetElementDataIndex() or nil
    if not (srcID and srcIdx and dstIdx) then return nil end
    return srcID, srcIdx, dstIdx, candidate.area
end


-- OnDragStop replacement: cleanup + dispatch HOUSETAB_REORDER_WIDGET (no data-provider mutation).
local function _onPickerDragStop(behavior)
    _cleanupPickerDragState(behavior)
    local srcID, srcIdx, dstIdx, area = _resolvePickerDropTarget(behavior)
    if srcID and dstIdx ~= srcIdx then
        local insertIdx = (area == _G.DragIntersectionArea.Below) and (dstIdx + 1) or dstIdx
        -- Source removed first; if it sat before the insert target,
        -- every subsequent index slides up by 1.
        if srcIdx < insertIdx then insertIdx = insertIdx - 1 end
        local picks = HDG.Selectors:Call("house.pickerRows", HDG.Store:GetState(), {})  -- exception(false-positive): top-level controller method (not a row factory)
        local ids = {}
        for _, p in ipairs(picks) do ids[#ids + 1] = p.id end
        HDG.Store:Dispatch({
            type    = Constants.ACTIONS.HOUSETAB_REORDER_WIDGET,
            payload = { orderedIDs = ids, srcID = srcID, insertIdx = insertIdx },
        })
    end
    behavior:ClearCandidate()
end

_attachPickerDrag = function(scrollBox)
    local behavior = _G.ScrollUtil.AddLinearDragBehavior(scrollBox)

    -- CRITICAL: Reorderable defaults nil. Blizzard's OnUpdate bails before updating the candidate
    -- when false; drop candidate stays empty and our OnDragStop sees no elementData. Must set true.
    behavior:SetReorderable(true)

    _setupPickerDragVisuals(behavior)
    _attachPickerDropLinePreview(behavior)
    behavior.delegate:SetScript("OnDragStop", function() _onPickerDragStop(behavior) end)

    return behavior
end
