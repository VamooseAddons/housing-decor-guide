-- HDGR_LayoutConfig_Zone.lua
-- Zone Scanner standalone floating window (HDG.Window, HDG-ADR-025 step 5).
--
-- View: zoneScanner
--   columns: { 320 }
--   rows:    { 28 (header), 500 (body) }
--   cells:   header / body
--
-- Panels:
--   zoneHeaderPanel   -- floating-window chrome: title + close button
--   zonePanel         -- content: filter bar + entries + action bar
--
-- Sections (zone.*):
--   zone.body             vertical container
--   zone.filterBar        search + showCollected toggle row
--   zone.entries          scrollbox container (height = fill)
--   zone.actionBar        bottom action row (Map All)

HDG = HDG or {}
local LC = HDG.LayoutConfig

-- ===== View =================================================================

LC.window.views.zoneScanner = {
    explicit    = true,
    standalone  = true,
    width       = "auto",
    height      = "auto",
    columns     = { 320 },
    rows        = { 28, 500 },           -- static fallback; dynamicRows hugs the list
    dynamicRows = "zone.windowRows",     -- body row auto-sizes to the vendor list (HDG parity)
    cells       = {
        header = { col = 1, row = 1, colSpan = 1, rowSpan = 1 },
        body   = { col = 1, row = 2, colSpan = 1, rowSpan = 1 },
    },
}

-- ===== Panels ===============================================================
-- Header title is static "Zone Scanner"; zone name + summary display inside the content area.
LC.panels.zoneHeaderPanel = {
    kind = "panel",
    cell = { zoneScanner = "header" },
    visibleInViews = { "zoneScanner" },
    slots = {
        header = {
            height = 28, layout = "horizontal", gap = "md",
            padding = { top = 0, right = "md", bottom = 0, left = "md" },
            chrome = "PanelHeader",
        },
    },
}

-- Content panel: filter bar + entries + action bar.
LC.panels.zonePanel = {
    kind = "panel",
    cell = { zoneScanner = "body" },
    visibleInViews = { "zoneScanner" },
}

-- ===== Sections =============================================================

LC.sections["zone.body"] = {
    ["in"]  = "zonePanel",
    layout  = "vertical",
    padding = "lg",
    gap     = "sm",
    order   = 10,
}

LC.sections["zone.filterBar"] = {
    ["in"]   = "zone.body",
    layout   = "horizontal",
    height   = 26,
    gap      = "md",
    order    = 10,
}

LC.sections["zone.entries"] = {
    ["in"]   = "zone.body",
    layout   = "fill",
    height   = "fill",
    order    = 20,
    chrome   = "inset",
}

LC.sections["zone.actionBar"] = {
    ["in"]   = "zone.body",
    layout   = "horizontal",
    height   = 24,
    gap      = "md",
    order    = 30,
}

-- ===== Widgets -- window chrome header =======================================
-- Icon mirrors NAV_TREE's "Zone" launcher glyph.
LC.widgets["zoneHeaderPanel.icon"] = {
    tooltip = false,
    kind = "atlas", ["in"] = "zoneHeaderPanel", slot = "header",
    atlas = "UI-WorldMapArrow",
    width = 16, height = 16, order = 5,
}
LC.widgets["zoneHeaderPanel.title"] = {
    tooltip = false,
    kind = "label", role = "TextHeading", ["in"] = "zoneHeaderPanel", slot = "header",
    text = "Zone Scanner", font = "heading",
    height = 18, width = "auto", order = 10,
}
LC.widgets["zoneHeaderPanel.spacer"] = {
    tooltip = false,
    kind = "spacer", ["in"] = "zoneHeaderPanel", slot = "header",
    width = "fill", height = 18, order = 15,
}
LC.widgets["zoneHeaderPanel.close"] = {
    tooltip = { recipe = "Close" },
    kind = "button", ["in"] = "zoneHeaderPanel", slot = "header",
    width = 22, height = 22, order = 95,
    close = true,
    size = 22,
    iconSize = 14,
}

-- ===== Widgets -- filter bar ================================================

LC.widgets["zonePanel.searchBox"] = {
    tooltip = false,
    kind = "editbox", ["in"] = "zone.filterBar",
    font = "body", width = "fill", height = 22, order = 10,
    placeholder = "Search vendors...",
    binding = { text = "zone.search" },
}

LC.widgets["zonePanel.showCollectedBtn"] = {
    tooltip = false,
    kind = "button", ["in"] = "zone.filterBar",
    font = "small", text = "Show Collected", width = "auto", height = 22,
    order = 20, variant = "tertiary",
    binding = { active = "zone.showCollected" },
}

-- ===== Widgets -- entries scrollbox =========================================

LC.widgets["zonePanel.entries"] = {
    tooltip = false,
    kind = "scrollbox", ["in"] = "zone.entries",
    binding = "zone.entriesByVendor",
    -- Heterogeneous row factory (vendor / item); see HDGR_Controller_Zone.
    rowKind   = "zoneRow",
    spacing   = 1,
    order     = 10,
}

-- ===== Widgets -- action bar =================================================

LC.widgets["zonePanel.mapAllBtn"] = {
    tooltip = false,
    kind = "button", ["in"] = "zone.actionBar",
    font = "body", text = "Map All", width = "auto", height = 22,
    order = 10, variant = "tertiary",
}
LC.widgets["zonePanel.actionSpacer"] = {
    tooltip = false,
    kind = "spacer", ["in"] = "zone.actionBar",
    width = "fill", height = 22, order = 20,
}

-- ===== Satellite window (HDG-ADR-025 step 5) ===============================
-- shown = zone.popupShown (ZONE_POPUP_TOGGLE). No position persistence.
LC.windows.zoneWindow = {
    slots    = { fill = "zoneScanner" },
    shown    = "zone.popupShown",
    position = { default = { x = 200, y = -160 }, movable = true },
}
