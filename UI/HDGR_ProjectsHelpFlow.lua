-- HDGR_ProjectsHelpFlow.lua
-- ============================================================================
-- "projectsHelpFlow" WidgetType: the Projects workflow cycle diagram for the
-- Help view. Six stage cards in a rectangular loop (top row left-to-right,
-- down, bottom row right-to-left, up) with line connectors + glyph arrowheads
-- -- the same visual language as the Architect canvas (cards outlined like
-- rooms, RoomOutline lines). Clicking a card selects the stage; the detail
-- copy below the diagram is a separate bound label (projects.helpStageBody).
--
-- Geometry is a FIXED inner diagram centered in the host (no rotated
-- textures, no diagonal lines -- every connector is axis-aligned, arrowheads
-- are ASCII fontstring glyphs), so it renders identically at any window size.

HDG = HDG or {}

local L = HDG.Locale

-- Stage order IS the loop order: 1-4 across the top, 5-6 back along the bottom.
local STAGE_KEYS = {
    "PROJ_HELP_S1_NAME", "PROJ_HELP_S2_NAME", "PROJ_HELP_S3_NAME",
    "PROJ_HELP_S4_NAME", "PROJ_HELP_S5_NAME", "PROJ_HELP_S6_NAME",
}

local DIAGRAM_W, DIAGRAM_H = 640, 180
local CARD_W, CARD_H       = 130, 44
local CARD_GAP             = 40    -- horizontal gap between top-row cards
local LINE_PX              = 2

-- Card top-left offsets inside the diagram (y grows downward).
local CARD_POS = {
    [1] = { x = 0,   y = 0 },                      -- Capture
    [2] = { x = 170, y = 0 },                      -- Assign
    [3] = { x = 340, y = 0 },                      -- Furnish
    [4] = { x = 510, y = 0 },                      -- Plan
    [5] = { x = 510, y = DIAGRAM_H - CARD_H },     -- Shop (under Plan)
    [6] = { x = 0,   y = DIAGRAM_H - CARD_H },     -- Build (under Capture)
}

local function _line(diagram, x1, y1, x2, y2)
    local ln = diagram:CreateLine(nil, "ARTWORK")
    ln:SetThickness(LINE_PX)
    ln:SetStartPoint("TOPLEFT", diagram, x1, -y1)
    ln:SetEndPoint("TOPLEFT", diagram, x2, -y2)
    HDG.Theme:Register(ln, "RoomOutline")
    return ln
end

local function _arrow(diagram, glyph, x, y)
    local fs = diagram:CreateFontString(nil, "OVERLAY")
    HDG.UI.applyFontRole(fs, "caption")
    HDG.Theme:Register(fs, "TextDim")
    fs:SetText(glyph)
    fs:SetPoint("CENTER", diagram, "TOPLEFT", x, -y)
    return fs
end

local function _card(diagram, i, label)
    local pos  = CARD_POS[i]
    local card = CreateFrame("Button", nil, diagram, "BackdropTemplate")
    card:SetSize(CARD_W, CARD_H)
    card:SetPoint("TOPLEFT", diagram, "TOPLEFT", pos.x, -pos.y)
    HDG.Theme:Register(card, "Raised")

    local num = card:CreateFontString(nil, "OVERLAY")
    HDG.UI.applyFontRole(num, "heading")
    HDG.Theme:Register(num, "TextNumeric")
    num:SetText(tostring(i))
    num:SetPoint("LEFT", card, "LEFT", 10, 0)

    local name = card:CreateFontString(nil, "OVERLAY")
    HDG.UI.applyFontRole(name, "body")
    HDG.Theme:Register(name, "Text")
    name:SetText(label)
    name:SetPoint("LEFT", num, "RIGHT", 8, 0)
    card._nameFs = name   -- push re-reads the locale label (locale switch repaints via "*")

    -- Selected stage marker: 3px accent bar along the card's bottom edge
    -- (same selection vocabulary as RowChrome). Visibility is widget state;
    -- color comes from the AccentBar skinner on every theme repaint.
    local bar = card:CreateTexture(nil, "OVERLAY")
    bar:SetHeight(3)
    bar:SetPoint("BOTTOMLEFT", card, "BOTTOMLEFT", 1, 1)
    bar:SetPoint("BOTTOMRIGHT", card, "BOTTOMRIGHT", -1, 1)
    HDG.Theme:Register(bar, "AccentBar")
    bar:Hide()
    card._selectedBar = bar

    card:SetScript("OnClick", function()
        HDG.Store:Dispatch({
            type    = HDG.Constants.ACTIONS.UI_SET_TRANSIENT,
            payload = { view = "projects", key = "helpStage", value = i },
        })
    end)
    return card
end

local function buildProjectsHelpFlow(parent, _spec)
    local host = CreateFrame("Frame", nil, parent)

    -- Fixed-size diagram centered in the fill-width host.
    local diagram = CreateFrame("Frame", nil, host)
    diagram:SetSize(DIAGRAM_W, DIAGRAM_H)
    diagram:SetPoint("CENTER")

    host._cards = {}
    for i, key in ipairs(STAGE_KEYS) do
        host._cards[i] = _card(diagram, i, L:Get(key))
    end

    local midTop = CARD_H / 2                  -- top-row card centerline
    local midBot = DIAGRAM_H - CARD_H / 2      -- bottom-row card centerline
    local colL   = CARD_W / 2                  -- Capture/Build column center
    local colR   = 510 + CARD_W / 2            -- Plan/Shop column center
    -- Top row: 1 -> 2 -> 3 -> 4.
    for i = 1, 3 do
        local x1 = CARD_POS[i].x + CARD_W
        _line(diagram, x1, midTop, x1 + CARD_GAP, midTop)
        _arrow(diagram, ">", x1 + CARD_GAP / 2, midTop)
    end
    -- Down the right: 4 -> 5.
    _line(diagram, colR, CARD_H, colR, DIAGRAM_H - CARD_H)
    _arrow(diagram, "v", colR, DIAGRAM_H / 2)
    -- Bottom row: 5 -> 6.
    _line(diagram, 510, midBot, CARD_W, midBot)
    _arrow(diagram, "<", (510 + CARD_W) / 2, midBot)
    -- Up the left: 6 -> 1 (the loop closes -- recapture).
    _line(diagram, colL, DIAGRAM_H - CARD_H, colL, CARD_H)
    _arrow(diagram, "^", colL, DIAGRAM_H / 2)

    return host
end

local function pushProjectsHelpFlow(widget, values)
    local stage = values and values.model and values.model.stage
    for i, card in ipairs(widget._cards) do
        card._selectedBar:SetShown(i == stage)
        card._nameFs:SetText(L:Get(STAGE_KEYS[i]))   -- labels follow a live locale switch
    end
end

HDG.WidgetTypes:Register("projectsHelpFlow", {
    build        = buildProjectsHelpFlow,
    dispatch     = { fields = { "model" }, push = pushProjectsHelpFlow },
    requiresFont = function() return false end,
    specFields   = {},   -- stage flows via binding; no kind-specific spec fields
})
