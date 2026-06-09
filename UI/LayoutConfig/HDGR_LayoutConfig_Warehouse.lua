-- HDG.LayoutConfig -- Warehouse view (extracted from the Recipes tab).
-- Sections: lumber stocks (top) + All Materials + Used-In (horizontal split, bottom).
-- Selectors: HDGR_Selectors_Warehouse.lua; wiring: HDGR_Controller_Warehouse.lua.

local LC = HDG.LayoutConfig

-- ===== View ==================================================================
-- 854px wide matches Crafting so the window doesn't resize on tab switch.
LC.window.views.warehouse = {
    explicit = true,
    width    = "auto",
    height   = "auto",
    columns  = { 854 },
    rows     = { 600 },      -- raised 500->600 so the nav column fills (no nav scroll)
    cells    = {
        main = { col = 1, row = 1, colSpan = 1, rowSpan = 1 },
    },
}

-- ===== Panel =================================================================
LC.panels.warehousePanel = {
    kind = "panel",
    cell = { warehouse = "main" },
    visibleInViews = { "warehouse" },
    slots = {
        header = {
            height = 26, layout = "horizontal", gap = "md",
            padding = { top = 0, right = "xl", bottom = 0, left = "xl" },
            chrome = "PanelHeader",
        },
    },
}
LC.widgets["warehousePanel.title"] = {
    tooltip = false,
    kind = "label", ["in"] = "warehousePanel", slot = "header",
    text = "locale:WARE_PANEL_TITLE", font = "heading",
    height = 18, width = "fill", order = 10,   -- fill absorbs slack -> toggle right-aligns
}
-- Auto-show toggle, right of the title bar: pop the lumber tracker on harvest,
-- or keep it out of the way (LumberObserver reads account.lumber.config.autoShowOnHarvest).
LC.widgets["warehousePanel.autoShowToggle"] = {
    tooltip = { recipe = "LumberAutoShow" },
    kind = "checkbox", ["in"] = "warehousePanel", slot = "header", font = "button",
    text = "locale:WARE_AUTOSHOW_TOGGLE", width = 200, height = 22, order = 20,
    binding = { checked = "warehouse.autoShowLumber" },
}

-- ===== Sections ==============================================================

LC.sections["warehouse.body"] = {
    ["in"] = "warehousePanel",
    layout = "vertical",
    padding = "md",
    gap = "sm",
    order = 10,
}
-- Lumber stocks: 270px = 12 rows * 20 + gaps + header; matsRow absorbs remainder.
LC.sections["warehouse.lumberSection"] = {
    ["in"] = "warehouse.body",
    layout = "horizontal",   -- lumber stock (left) + farming history (right)
    height = 270,
    gap = "sm",
    order = 10,
}
-- Lumber stock column (left, 392px). farming-history panel fills the remainder.
LC.sections["warehouse.lumberStock"] = {
    ["in"] = "warehouse.lumberSection",
    layout = "vertical",
    width = 392,
    gap = "xs",
    order = 10,
}
-- Column header: widths match LUMBER_COLS in Controller_Warehouse.
LC.sections["warehouse.lumberHeader"] = {
    ["in"] = "warehouse.lumberStock",
    layout = "horizontal",
    height = 14,
    gap = "xs",
    order = 10,
}
LC.sections["warehouse.lumberList"] = {
    ["in"] = "warehouse.lumberStock",
    layout = "fill",
    order = 20,
    chrome = "inset",
}
-- Lumber farming history (right): newest-first scrollbox.
LC.sections["warehouse.lumberHistory"] = {
    ["in"] = "warehouse.lumberSection",
    layout = "vertical",
    width = "fill",
    gap = "xs",
    order = 20,
}
LC.sections["warehouse.lumberHistoryHeader"] = {
    ["in"] = "warehouse.lumberHistory",
    layout = "horizontal",
    height = 14,
    order = 10,
}
LC.sections["warehouse.lumberHistoryList"] = {
    ["in"] = "warehouse.lumberHistory",
    layout = "fill",
    order = 20,
    chrome = "inset",
}
-- All Materials + Used-In: horizontal split, fills remaining vertical.
LC.sections["warehouse.matsRow"] = {
    ["in"] = "warehouse.body",
    layout = "horizontal",
    gap = "sm",
    order = 20,
}
LC.sections["warehouse.allMats"] = {
    ["in"] = "warehouse.matsRow",
    layout = "vertical",
    width = "fill",
    gap = "xs",
    order = 10,
}
LC.sections["warehouse.allMatsHeader"] = {
    ["in"] = "warehouse.allMats",
    layout = "horizontal",
    height = 14,
    order = 10,
}
-- Materials search row (independent of Recipes search).
LC.sections["warehouse.allMatsSearch"] = {
    ["in"] = "warehouse.allMats",
    layout = "horizontal",
    height = 22,
    order = 15,
}
LC.sections["warehouse.allMatsList"] = {
    ["in"] = "warehouse.allMats",
    layout = "fill",
    order = 20,
    chrome = "inset",
}
LC.sections["warehouse.usedIn"] = {
    ["in"] = "warehouse.matsRow",
    layout = "vertical",
    width = "fill",
    gap = "xs",
    order = 20,
}
LC.sections["warehouse.usedInHeader"] = {
    ["in"] = "warehouse.usedIn",
    layout = "horizontal",
    height = 14,
    order = 10,
}
LC.sections["warehouse.usedInList"] = {
    ["in"] = "warehouse.usedIn",
    layout = "fill",
    order = 20,
    chrome = "inset",
}

-- ===== Widgets ===============================================================
LC.widgets["warehousePanel.lumberHdr.name"] = {
    tooltip = false,
    kind = "label", ["in"] = "warehouse.lumberHeader",
    font = "caption", text = "locale:WARE_LUMBER_HDR_NAME",
    width = 90, height = 12, order = 10,
}
LC.widgets["warehousePanel.lumberHdr.exp"] = {
    tooltip = false,
    kind = "label", ["in"] = "warehouse.lumberHeader",
    font = "caption", text = "locale:WARE_LUMBER_HDR_EXP",
    width = 44, height = 12, order = 15,
}
LC.widgets["warehousePanel.lumberHdr.bag"] = {
    tooltip = false,
    kind = "label", ["in"] = "warehouse.lumberHeader",
    font = "caption", text = "locale:WARE_LUMBER_HDR_BAG", justifyH = "RIGHT",
    width = 36, height = 12, order = 20,
}
LC.widgets["warehousePanel.lumberHdr.bank"] = {
    tooltip = false,
    kind = "label", ["in"] = "warehouse.lumberHeader",
    font = "caption", text = "locale:WARE_LUMBER_HDR_BANK", justifyH = "RIGHT",
    width = 36, height = 12, order = 30,
}
LC.widgets["warehousePanel.lumberHdr.warband"] = {
    tooltip = false,
    kind = "label", ["in"] = "warehouse.lumberHeader",
    font = "caption", text = "locale:WARE_LUMBER_HDR_WARBAND", justifyH = "RIGHT",
    width = 44, height = 12, order = 40,
}
LC.widgets["warehousePanel.lumberHdr.needed"] = {
    tooltip = false,
    kind = "label", ["in"] = "warehouse.lumberHeader",
    font = "caption", text = "locale:WARE_LUMBER_HDR_NEED", justifyH = "RIGHT",
    width = 42, height = 12, order = 50,
}
LC.widgets["warehousePanel.lumberHdr.stock"] = {
    tooltip = false,
    kind = "label", ["in"] = "warehouse.lumberHeader",
    font = "caption", text = "locale:WARE_LUMBER_HDR_STOCK", justifyH = "RIGHT",
    width = 64, height = 12, order = 60,
}
LC.widgets["warehousePanel.lumberList"] = {
    tooltip = false,
    kind = "scrollbox", ["in"] = "warehouse.lumberList",
    binding = "warehouse.lumberRows",
    rowKind = "lumberRow",
    spacing = 1,
    order = 10,
}
-- Lumber farming history: reuses "dataRow" factory (farmHistRow / emptyRow).
LC.widgets["warehousePanel.lumberHistoryHeader"] = {
    tooltip = false,
    kind = "label", ["in"] = "warehouse.lumberHistoryHeader",
    font = "caption", text = "locale:WARE_LUMBER_HISTORY_HDR",
    width = "fill", height = 12, order = 10,
}
LC.widgets["warehousePanel.lumberHistoryList"] = {
    tooltip = false,
    kind = "scrollbox", ["in"] = "warehouse.lumberHistoryList",
    binding = "warehouse.farmingHistoryRows",
    rowKind = "dataRow",
    spacing = 1,
    order = 10,
}
-- Sub-panel headers: "Materials" + selection-aware "Used In: X".
LC.widgets["warehousePanel.allMatsHeader"] = {
    tooltip = false,
    kind = "label", ["in"] = "warehouse.allMatsHeader",
    font = "caption", text = "locale:WARE_ALL_MATS_HDR",
    width = "fill", height = 12, order = 10,
}
LC.widgets["warehousePanel.usedInHeader"] = {
    tooltip = false,
    kind = "label", ["in"] = "warehouse.usedInHeader",
    font = "caption", text = "locale:WARE_USED_IN_HDR",
    width = "fill", height = 12, order = 10,
    binding = "warehouse.usedInTitle",
}
LC.widgets["warehousePanel.allMatsSearch"] = {
    tooltip = false,
    kind = "editbox", ["in"] = "warehouse.allMatsSearch", font = "body",
    height = 22, width = "fill", order = 10,
    multiline   = false,
    placeholder = "locale:WARE_MAT_SEARCH_PLACEHOLDER",
    binding = { text = "warehouse.matSearch" },
}
LC.widgets["warehousePanel.allMatsList"] = {
    tooltip = false,
    kind = "scrollbox", ["in"] = "warehouse.allMatsList",
    binding = "warehouse.allMaterialsRows",
    rowKind  = "warehouseMatRow",
    spacing  = 1,
    -- SelectionBehavior: highlight via behavior; selectedMaterialID dropped from reads.
    selection = { deselectable = false },
    order = 10,
}
LC.widgets["warehousePanel.usedInList"] = {
    tooltip = false,
    kind = "scrollbox", ["in"] = "warehouse.usedInList",
    binding = "warehouse.usedInRows",
    rowKind = "usedInRow",
    spacing = 1,
    order = 10,
}
