-- HDGR_LayoutConfig_Shopping.lua
-- Standalone floating window (HDG.Window) for the Shopping List (HDG-ADR-025 step 5).
--
-- View: shoppingList
--   columns: { 480 }
--   rows:    { 28 (header), 650 (body) }
--   cells:   header / body
--
-- Panels:
--   shoppingHeaderPanel  -- floating-window chrome: title + close button
--   shoppingPanel        -- content: list switcher + entries + action bar
--
-- Sections (shopping.*):
--   shopping.body              vertical container (everything below header)
--   shopping.attribution       horizontal banner row (visible: shopping.hasAttribution)
--   shopping.entries           scrollbox container (height = fill)
--   shopping.actionBar         horizontal action row

HDG = HDG or {}
local LC = HDG.LayoutConfig

-- ===== View ==================================================================

LC.window.views.shoppingList = {
    explicit    = true,
    standalone  = true,        -- HDG.Window floating frame; not in main window
    width       = "auto",      -- 4 + 480 + 4 = 488
    height      = "auto",      -- 4 + 28 + 4 + 650 + 4 = 690
    columns     = { 480 },
    rows        = { 28, 650 },
    cells       = {
        header = { col = 1, row = 1, colSpan = 1, rowSpan = 1 },
        body   = { col = 1, row = 2, colSpan = 1, rowSpan = 1 },
    },
}

-- ===== Panels ================================================================
LC.panels.shoppingHeaderPanel = {
    kind = "panel",
    cell = { shoppingList = "header" },
    visibleInViews = { "shoppingList" },
    slots = {
        header = {
            height = 28, layout = "horizontal", gap = "md",
            padding = { top = 0, right = "md", bottom = 0, left = "md" },
            chrome = "PanelHeader",
        },
    },
}

-- Content panel: list switcher + body sections.
LC.panels.shoppingPanel = {
    kind = "panel",
    cell = { shoppingList = "body" },
    visibleInViews = { "shoppingList" },
    slots = {
        header = {
            height = 34, layout = "horizontal", gap = "md",
            padding = { top = 0, right = "xl", bottom = 0, left = "xl" },
            chrome = "PanelHeader",
        },
    },
}

-- ===== Sections ==============================================================

LC.sections["shopping.body"] = {
    ["in"]  = "shoppingPanel",
    layout  = "vertical",
    padding = "lg",
    gap     = "sm",
    order   = 10,
}

-- Attribution banner: visible when list has meta.source or meta.attribution (external sources).
LC.sections["shopping.attribution"] = {
    ["in"]   = "shopping.body",
    layout   = "horizontal",
    height   = 28,
    gap      = "sm",
    order    = 10,
    chrome   = "card",
    -- Left inset clears the card chrome's accent stripe so "Imported from ..."
    -- doesn't clash with it (right "sm" keeps the Open button off the edge).
    padding  = { top = 0, right = "sm", bottom = 0, left = "md" },
    visible  = "shopping.hasAttribution",
}

LC.sections["shopping.entries"] = {
    ["in"]   = "shopping.body",
    layout   = "fill",
    height   = "fill",
    order    = 20,
    chrome   = "inset",
}

LC.sections["shopping.actionBar"] = {
    ["in"]   = "shopping.body",
    layout   = "horizontal",
    height   = 24,
    gap      = "md",
    order    = 30,
}

-- ===== Widgets -- window chrome header =======================================
-- Icon mirrors NAV_TREE's "Shopping" launcher glyph.
LC.widgets["shoppingHeaderPanel.icon"] = {
    tooltip = false,
    kind = "atlas", ["in"] = "shoppingHeaderPanel", slot = "header",
    atlas = HDG.Constants.SHOPPING_LIST_ICON_ATLAS,
    width = 16, height = 16, order = 5,
}
LC.widgets["shoppingHeaderPanel.title"] = {
    tooltip = false,
    kind = "label", role = "TextHeading", ["in"] = "shoppingHeaderPanel", slot = "header",
    text = "locale:SHOP_TITLE", font = "heading",
    height = 18, width = "auto", order = 10,
}
LC.widgets["shoppingHeaderPanel.spacer"] = {
    tooltip = false,
    kind = "spacer", ["in"] = "shoppingHeaderPanel", slot = "header",
    width = "fill", height = 18, order = 15,
}
-- Mouse-action hints: right of the slack spacer, just left of [X].
LC.widgets["shoppingHeaderPanel.clickHints"] = {
    tooltip = false,   -- self-owned tooltip, composed from leftText/rightText
    kind = "clickHints", ["in"] = "shoppingHeaderPanel", slot = "header",
    leftText  = "locale:SHOP_HINT_LEFT",
    rightText = "locale:SHOP_HINT_RIGHT",
    width = 34, height = 16, order = 90,
}
LC.widgets["shoppingHeaderPanel.close"] = {
    tooltip = { recipe = "Close" },
    kind = "button", ["in"] = "shoppingHeaderPanel", slot = "header",
    width = 22, height = 22, order = 95,
    close = true,
    size = 22,
    iconSize = 14,
}

-- ===== Widgets -- content panel header slot ==================================

LC.widgets["shoppingPanel.title"] = {
    tooltip = false,
    kind = "label", role = "TextHeading", ["in"] = "shoppingPanel", slot = "header",
    text = "locale:SHOP_PANEL_TITLE", font = "heading",
    height = 18, width = "auto", order = 10,
}
-- Summary: width="fill" absorbs slack and truncates gracefully
-- (auto+spacer shrank to 0 on long text, pushing the dropdown out of the slot).
LC.widgets["shoppingPanel.summary"] = {
    tooltip = false,
    kind = "label", role = "Text", ["in"] = "shoppingPanel", slot = "header",
    text = "", font = "small", justifyH = "LEFT",
    height = 14, width = "fill", order = 12,
    binding = "shopping.summaryText",
}
-- List switcher dropdown. Dispatches SHOPPING_LIST_ACTIVATE { id = value }.
LC.widgets["shoppingPanel.listSwitcher"] = {
    tooltip = false,
    kind = "dropdown", ["in"] = "shoppingPanel", slot = "header",
    -- height=25: WowStyle2DropdownTemplate native height; shrinking misaligns the Background atlas.
    width = 180, height = 25, order = 20, minWidth = 140,
    placeholder = "locale:SHOP_NO_LIST",
    binding  = { menu = "shopping.activeListMenuItems",
                 current = "shopping.activeListId" },
    dispatch = { type = "SHOPPING_LIST_ACTIVATE", payloadKey = "id" },
}

-- ===== Widgets -- attribution banner =========================================

LC.widgets["shoppingPanel.attributionText"] = {
    tooltip = false,
    kind = "label", role = "TextStatus", ["in"] = "shopping.attribution",
    font = "small", text = "", width = "fill", height = 14, order = 10,
    binding = "shopping.attributionText",
}
LC.widgets["shoppingPanel.attributionOpenBtn"] = {
    tooltip = false,
    kind = "button", ["in"] = "shopping.attribution",
    font = "small", text = "locale:SHOP_OPEN_BTN", width = "auto", height = 20,
    order = 20, variant = "tertiary",
    visible = "shopping.hasUrl",
}

-- ===== Widgets -- entries scrollbox ==========================================

LC.widgets["shoppingPanel.entries"] = {
    tooltip = false,
    kind = "scrollbox", ["in"] = "shopping.entries",
    binding = "shopping.entriesByZone",
    -- Heterogeneous row factory (wishHeader/wishItem/zone/vendor/item).
    rowKind   = "shoppingRow",
    spacing   = 1,
    order     = 10,
}

-- ===== Widgets -- action bar =================================================

LC.widgets["shoppingPanel.waypointAllBtn"] = {
    tooltip = false,
    kind = "button", ["in"] = "shopping.actionBar",
    font = "body", text = "locale:SHOP_WAYPOINT_ALL", width = "auto", height = 22,
    order = 10, variant = "tertiary",
}
LC.widgets["shoppingPanel.clearBtn"] = {
    tooltip = false,
    kind = "button", ["in"] = "shopping.actionBar",
    font = "body", text = "locale:COMMON_CLEAR", width = "auto", height = 22,
    order = 20, variant = "tertiary",
}
LC.widgets["shoppingPanel.exportBtn"] = {
    tooltip = false,
    kind = "button", ["in"] = "shopping.actionBar",
    font = "body", text = "locale:COMMON_EXPORT", width = "auto", height = 22,
    order = 30, variant = "tertiary",
}
LC.widgets["shoppingPanel.importBtn"] = {
    tooltip = false,
    kind = "button", ["in"] = "shopping.actionBar",
    font = "body", text = "locale:COMMON_IMPORT", width = "auto", height = 22,
    order = 40, variant = "tertiary",
}
LC.widgets["shoppingPanel.actionBarSpacer"] = {
    tooltip = false,
    kind = "spacer", ["in"] = "shopping.actionBar",
    width = "fill", height = 22, order = 45,
}
-- Delete the active list. Hidden when only one list exists (can't delete your
-- only list -> deleting always leaves >=1, so activeShoppingListId is never "").
LC.widgets["shoppingPanel.deleteListBtn"] = {
    tooltip = false,
    kind = "button", ["in"] = "shopping.actionBar",
    font = "body", text = "locale:COMMON_DELETE", width = "auto", height = 22,
    order = 48, variant = "tertiary",
    visible = "shopping.hasMultipleLists",
}
LC.widgets["shoppingPanel.newListBtn"] = {
    tooltip = false,
    kind = "button", ["in"] = "shopping.actionBar",
    font = "body", text = "locale:SHOP_NEW_LIST", width = "auto", height = 22,
    order = 50, variant = "tertiary",
}

-- ===== Satellite window (HDG-ADR-025 step 5) ===============================
-- shown = shopping.windowVisible (SHOPPING_WIDGET_TOGGLE). No position persistence.
LC.windows.shoppingWindow = {
    slots    = { fill = "shoppingList" },
    shown    = "shopping.windowVisible",
    position = { default = { x = 250, y = -180 }, movable = true },
}
