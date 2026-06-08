-- HDGR_LayoutConfig_Projects.lua
-- ============================================================================
-- Per-tab LayoutConfig for the Projects feature.
--   projectsLanding   -- dashboard (capture CTA or house summary + room lists)
--   projectsArchitect -- blueprint canvas (budget strip + floor tabs + canvas + detail rail)
--   projectsLayouts   -- browse / preview / share saved build layouts (versions)
--   projectsPicker    -- decor picker (category rail + list + 3D preview)

HDG = HDG or {}
local LC = HDG.LayoutConfig

-- ===== Views =================================================================

LC.window.views.projectsLanding = {
    explicit = true,
    width    = "auto",
    height   = "auto",
    columns  = { 760 },
    rows     = { 600 },
    cells    = { body = { col = 1, row = 1, colSpan = 1, rowSpan = 1 } },
}

-- Architect: picker | canvas | detail (col 3 dropped when no room selected, HouseTab pattern).
LC.window.views.projectsArchitect = {
    explicit       = true,
    width          = "auto",
    height         = "auto",
    columns        = { 170, 620 },         -- fallback; projects.architectColumns takes over
    dynamicColumns = "projects.architectColumns",
    rows           = { 30, 28, 542 },
    cells    = {
        bar    = { col = 1, row = 1, colSpan = 3, rowSpan = 1 },
        nav    = { col = 1, row = 2, colSpan = 3, rowSpan = 1 },
        picker = { col = 1, row = 3, colSpan = 1, rowSpan = 1 },
        canvas = { col = 2, row = 3, colSpan = 1, rowSpan = 1 },
        detail = { col = 3, row = 3, colSpan = 1, rowSpan = 1 },
    },
}

-- Layouts: left scrollable version list | right detail (header + preview + stats).
-- Columns {280, 470}; right column rows {34, 490, 110} = header | preview | stats.
LC.window.views.projectsLayouts = {
    explicit = true,
    width    = "auto",
    height   = "auto",
    columns  = { 280, 470 },
    rows     = { 600 },
    cells    = {
        list   = { col = 1, row = 1, colSpan = 1, rowSpan = 1 },
        detail = { col = 2, row = 1, colSpan = 1, rowSpan = 1 },
    },
}

-- Decor picker: category rail | catalog list | 3D preview. Opened from "+ Add decor".
LC.window.views.projectsPicker = {
    explicit = true,
    width    = "auto",
    height   = "auto",
    columns  = { 44, 440, 320 },   -- category rail | decor list | 3D preview
    rows     = { 600 },
    cells    = {
        rail    = { col = 1, row = 1, colSpan = 1, rowSpan = 1 },
        list    = { col = 2, row = 1, colSpan = 1, rowSpan = 1 },
        preview = { col = 3, row = 1, colSpan = 1, rowSpan = 1 },
    },
}

-- ===== Panels ================================================================

LC.panels.projectsLandingPanel = {
    kind = "panel",
    cell = { projectsLanding = "body" },
    visibleInViews = { "projectsLanding" },
    slots = {
        header = {
            height = 34, layout = "horizontal", gap = "md",
            padding = { top = 0, right = "xl", bottom = 0, left = "xl" },
            chrome = "PanelHeader",
        },
    },
}

LC.panels.projectsBarPanel = {
    kind = "panel",
    cell = { projectsArchitect = "bar" },
    visibleInViews = { "projectsArchitect" },
    slots = {
        body = { layout = "horizontal", gap = "md", padding = { top = 2, right = "lg", bottom = 2, left = "lg" } },
    },
}
LC.panels.projectsNavPanel = {
    kind = "panel",
    cell = { projectsArchitect = "nav" },
    visibleInViews = { "projectsArchitect" },
    slots = {
        body = { layout = "horizontal", gap = "sm", padding = { top = 1, right = "lg", bottom = 1, left = "lg" } },
    },
}
-- Picker panel: room palette + plan status footer.
LC.panels.projectsPickerPanel = {
    kind = "panel",
    cell = { projectsArchitect = "picker" },
    visibleInViews = { "projectsArchitect" },
    slots = {
        header = { height = 30, layout = "horizontal", gap = "sm",
            padding = { top = 0, right = "md", bottom = 0, left = "md" }, chrome = "PanelHeader" },
        body   = { layout = "vertical", gap = "sm", padding = "md" },
    },
}
LC.panels.projectsCanvasPanel = {
    kind = "panel",
    cell = { projectsArchitect = "canvas" },
    visibleInViews = { "projectsArchitect" },
}
-- Detail (right rail): crate management for the selected room.
LC.panels.projectsDetailPanel = {
    kind = "panel",
    cell = { projectsArchitect = "detail" },
    visibleInViews = { "projectsArchitect" },
    visible = "projects.sidePanelOpen",
    slots = {
        header = { height = 30, layout = "horizontal", gap = "sm",
            padding = { top = 0, right = "lg", bottom = 0, left = "lg" }, chrome = "PanelHeader" },
        body   = { layout = "vertical", gap = "sm", padding = "lg" },
    },
}

-- Layouts panels.
LC.panels.projectsLayoutsListPanel = {
    kind = "panel",
    cell = { projectsLayouts = "list" },
    visibleInViews = { "projectsLayouts" },
    slots = {
        header = {
            height = 34, layout = "horizontal", gap = "sm",
            padding = { top = 0, right = "lg", bottom = 0, left = "lg" },
            chrome = "PanelHeader",
        },
        body = { layout = "vertical", gap = "sm", padding = "lg" },
    },
}
-- Right detail: inner vertical layout for header strip | preview | stats.
LC.panels.projectsLayoutsDetailPanel = {
    kind = "panel",
    cell = { projectsLayouts = "detail" },
    visibleInViews = { "projectsLayouts" },
    slots = {
        header = {
            height = 34, layout = "horizontal", gap = "sm",
            padding = { top = 0, right = "lg", bottom = 0, left = "lg" },
            chrome = "PanelHeader",
        },
        body   = { layout = "vertical", gap = "sm", padding = "lg" },
    },
}

-- Picker panels.
-- Category rail: skin="Raised" lifts the rail off the surrounding panels so it reads as nav.
LC.panels.projectsPickerRailPanel = {
    kind = "panel",
    skin = "Raised",
    cell = { projectsPicker = "rail" },
    visibleInViews = { "projectsPicker" },
    slots = {
        -- 1px L/R: 42px icons nearly fill the 44px column; buffer preferred over widening.
        body = { layout = "vertical", gap = 0, padding = { top = 4, right = 1, bottom = 4, left = 1 } },
    },
}
LC.panels.projectsPickerListPanel = {
    kind = "panel",
    cell = { projectsPicker = "list" },
    visibleInViews = { "projectsPicker" },
    slots = {
        header = { height = 34, layout = "horizontal", gap = "sm",
            padding = { top = 0, right = "lg", bottom = 0, left = "lg" }, chrome = "PanelHeader" },
        body   = { layout = "vertical", gap = "sm", padding = "lg" },
    },
}
LC.panels.projectsPickerPreviewPanel = {
    kind = "panel",
    cell = { projectsPicker = "preview" },
    visibleInViews = { "projectsPicker" },
    slots = {
        body = { layout = "vertical", gap = "sm", padding = "md" },
    },
}

-- ===== Landing widgets =======================================================

LC.widgets["projectsLandingPanel.title"] = {
    tooltip = false, kind = "label", ["in"] = "projectsLandingPanel", slot = "header",
    text = "locale:PROJ_TITLE", font = "heading", height = 18, width = "auto", order = 5,
}
-- House switcher (same self-wired dropdown as the Architect bar). Orients the ledger.
LC.widgets["projectsLandingPanel.houseDropdown"] = {
    tooltip = false, kind = "dropdown", ["in"] = "projectsLandingPanel", slot = "header",
    binding   = { menu = "projects.houseMenuItems", current = "projects.activeHouseID" },
    dispatch  = { type = "PROJECTS_FOCUS_HOUSE", payloadKey = "houseID" },
    placeholder = "locale:PROJ_HOUSE_DROPDOWN_PLACEHOLDER", width = 200, height = 24, order = 6,
    visible = "projects.hasRooms",
}
LC.widgets["projectsLandingPanel.headerSpacer"] = {
    tooltip = false, kind = "spacer", ["in"] = "projectsLandingPanel", slot = "header",
    width = "fill", height = 14, order = 8,
}
-- Orphan alert: "! N orphaned" -- shown only when orphan crates exist.
LC.widgets["projectsLandingPanel.orphanAlert"] = {
    tooltip = false, kind = "label", ["in"] = "projectsLandingPanel", slot = "header",
    binding = "projects.orphanAlertText", font = "caption", height = 16, width = "auto",
    order = 9, visible = "projects.hasOrphans",
}
LC.widgets["projectsLandingPanel.openArchitect"] = {
    tooltip = false, kind = "button", ["in"] = "projectsLandingPanel", slot = "header",
    font = "body", text = "locale:PROJ_OPEN_ARCHITECT", width = 120, height = 22, order = 10,
    visible = "projects.hasRooms",
}
LC.widgets["projectsLandingPanel.newWhatIf"] = {
    tooltip = false, kind = "button", ["in"] = "projectsLandingPanel", slot = "header",
    font = "body", text = "locale:PROJ_NEW_WHATIF", width = 90, height = 22, order = 12,
    visible = "projects.hasRooms",
}
-- Standalone planning (Phase G): design a layout WITHOUT capturing a house first --
-- mocks up a from-scratch what-if (no live cap; the shopping list is "all to build").
LC.widgets["projectsLandingPanel.newDesign"] = {
    tooltip = false, kind = "button", ["in"] = "projectsLandingPanel", slot = "header",
    font = "body", text = "locale:PROJ_START_DESIGN", width = 120, height = 22, order = 22,
    visible = "projects.noRooms",
}
-- First-time CTA (no rooms captured): centered prompt.
LC.widgets["projectsLandingPanel.cta"] = {
    tooltip = false, kind = "label", ["in"] = "projectsLandingPanel",
    text = "locale:PROJ_NO_ROOMS_CTA",
    font = "body", width = "fill", height = 40, order = 10,
    visible = "projects.noRooms",
}
-- Crate ledger: orphan bay (reclaim/discard) + crate inventory (rooms holding decor).
LC.widgets["projectsLandingPanel.list"] = {
    tooltip = false, kind = "scrollbox", ["in"] = "projectsLandingPanel",
    binding = "projects.crateLedgerRows", rowKind = "projectsLedgerRow",
    spacing = 2, order = 20, visible = "projects.hasRooms",
    selection = { deselectable = true },
}

-- ===== Architect widgets =====================================================

-- Bar: house dropdown (left) + spacer + budget text + progress (right).
-- The dropdown lists ALL owned houses + switches which one the Architect edits
-- (self-wired via the binding + dispatch shortcut, like the Config theme picker).
LC.widgets["projectsBarPanel.houseDropdown"] = {
    tooltip = false, kind = "dropdown", ["in"] = "projectsBarPanel",
    binding   = { menu = "projects.houseMenuItems", current = "projects.activeHouseID" },
    dispatch  = { type = "PROJECTS_FOCUS_HOUSE", payloadKey = "houseID" },
    placeholder = "locale:PROJ_HOUSE_DROPDOWN_PLACEHOLDER", width = 220, height = 25, order = 10,
}
LC.widgets["projectsBarPanel.spacer"] = {
    tooltip = false, kind = "spacer", ["in"] = "projectsBarPanel",
    width = "fill", height = 6, order = 20,
}
-- Room placement budget: planned weight vs live cap. Left of decor budget.
LC.widgets["projectsBarPanel.roomBudgetText"] = {
    tooltip = false, kind = "label", ["in"] = "projectsBarPanel",
    binding = "projects.roomBudgetText", font = "caption", height = 16, width = "auto", order = 24,
}
LC.widgets["projectsBarPanel.roomBudgetBar"] = {
    tooltip = false, kind = "progressbar", ["in"] = "projectsBarPanel",
    binding = { progress = "projects.roomBudgetProgress" }, width = 90, height = 8, order = 26,
}
LC.widgets["projectsBarPanel.budgetText"] = {
    tooltip = false, kind = "label", ["in"] = "projectsBarPanel",
    binding = "projects.budgetText", font = "caption", height = 16, width = "auto", order = 30,
}
LC.widgets["projectsBarPanel.budgetBar"] = {
    tooltip = false, kind = "progressbar", ["in"] = "projectsBarPanel",
    binding = { progress = "projects.budgetProgress" }, width = 120, height = 8, order = 40,
}
-- Mouse-action hints: right of decor budget (breadcrumb | rooms | decor | hints).
LC.widgets["projectsBarPanel.clickHints"] = {
    tooltip = false,   -- self-owned tooltip composed from leftText/rightText
    kind = "clickHints", ["in"] = "projectsBarPanel",
    leftText  = "locale:PROJ_CANVAS_LEFT_HINT",
    rightText = "locale:PROJ_CANVAS_RIGHT_HINT",
    title     = "locale:PROJ_CANVAS_TITLE",
    width = 34, height = 16, order = 50,
}

-- Nav: version switcher + floor tabs + capture-all + dashboard.
-- (House switching lives in the bar dropdown -- projectsBarPanel.houseDropdown.)
-- Version switcher: opens menu to switch / branch / delete house versions.
LC.widgets["projectsNavPanel.versionMenu"] = {
    tooltip = false, kind = "button", ["in"] = "projectsNavPanel",
    font = "body", binding = { text = "projects.activeVersionLabel" },
    width = 150, height = 22, order = 5,
}
LC.widgets["projectsNavPanel.floors"] = {
    tooltip = false, kind = "chipStrip", ["in"] = "projectsNavPanel",
    binding = "projects.floorTabs", cellKind = "projectsFloorChip",
    width = "fill", height = "fill", order = 10,
}
-- What-if floor controls (what-if mode only, max 3 floors). "+ Floor" is the
-- rightmost of the pair (order 18) so it stays put; "- Floor" (order 17) appears
-- to its LEFT when removable, instead of pushing "+ Floor" left.
LC.widgets["projectsNavPanel.addFloor"] = {
    tooltip = false, kind = "button", ["in"] = "projectsNavPanel",
    font = "body", text = "locale:PROJ_ADD_FLOOR", width = 72, height = 22, order = 18,
    visible = "projects.canAddWhatIfFloor",
}
LC.widgets["projectsNavPanel.removeFloor"] = {
    tooltip = false, kind = "button", ["in"] = "projectsNavPanel",
    font = "body", text = "locale:PROJ_REMOVE_FLOOR", width = 72, height = 22, order = 17,
    visible = "projects.canRemoveWhatIfFloor",
}
LC.widgets["projectsNavPanel.captureAll"] = {
    tooltip = { recipe = "ProjectsCaptureAll" }, kind = "button", ["in"] = "projectsNavPanel",
    font = "body", text = "locale:PROJ_CAPTURE_ALL_FLOORS", width = 130, height = 22, order = 20,
}
-- (Dashboard button dropped 2026-06-07 -- the "Projects" parent nav node already
--  navigates to projectsLanding, so the button was a redundant second route.)

-- Canvas: blueprint widget (auto-fit tiling in controller).
LC.widgets["projectsCanvasPanel.canvas"] = {
    tooltip = false, kind = "projectsCanvas", ["in"] = "projectsCanvasPanel",
    binding = { model = "projects.canvasModel" }, width = "fill", height = "fill", order = 10,
}

-- Detail panel: selected room title.
LC.widgets["projectsDetailPanel.title"] = {
    tooltip = false, kind = "label", ["in"] = "projectsDetailPanel", slot = "header",
    text = "locale:PROJ_DETAIL_ROOM_TITLE", font = "heading", height = 18, width = "fill", order = 5,
}
-- Picker (left rail): room palette (what-if) or Live-mode CTA (stock).
-- Placing rooms only makes sense on a what-if; editing Live gets wiped on recapture.
LC.widgets["projectsPickerPanel.title"] = {
    tooltip = false, kind = "label", ["in"] = "projectsPickerPanel", slot = "header",
    text = "locale:PROJ_PICKER_ROOMS_TITLE", font = "heading", height = 18, width = "fill", order = 5,
}
LC.widgets["projectsPickerPanel.hint"] = {
    tooltip = false, kind = "label", ["in"] = "projectsPickerPanel",
    text = "locale:PROJ_PICKER_WHATIF_HINT", font = "caption", width = "fill", height = 16, order = 2,
    visible = "projects.isWhatIfMode",
}
-- Stock (Live) mode: palette locked; branch a what-if to redesign.
LC.widgets["projectsPickerPanel.stockHint"] = {
    tooltip = false, kind = "label", ["in"] = "projectsPickerPanel",
    text = "locale:PROJ_PICKER_STOCK_HINT",
    font = "caption", width = "fill", height = 96, order = 3, visible = "projects.isStockMode",
}
LC.widgets["projectsPickerPanel.newWhatIf"] = {
    tooltip = false, kind = "button", ["in"] = "projectsPickerPanel",
    font = "body", text = "locale:PROJ_NEW_WHATIF_PICKER", width = "fill", height = 24, order = 4,
    visible = "projects.isStockMode",
}
LC.widgets["projectsPickerPanel.list"] = {
    tooltip = false, kind = "scrollbox", ["in"] = "projectsPickerPanel",
    binding = "projects.paletteShapes", rowKind = "projectsRoomListRow",
    spacing = 2, width = "fill", height = "fill", order = 10,
    visible = "projects.isWhatIfMode",
}
LC.widgets["projectsPickerPanel.planValidation"] = {
    tooltip = false, kind = "label", ["in"] = "projectsPickerPanel",
    binding = "projects.planValidationSummary", font = "caption", width = "fill", height = 28, order = 20,
}
-- Room shopping list: what-if vs reality delta. Hidden when the active version is Live.
LC.widgets["projectsPickerPanel.shoppingLabel"] = {
    tooltip = false, kind = "label", ["in"] = "projectsPickerPanel",
    text = "locale:PROJ_SHOPPING_LIST_LABEL", font = "caption", width = "fill", height = 16, order = 22,
    visible = "projects.hasShoppingList",
}
LC.widgets["projectsPickerPanel.shoppingList"] = {
    tooltip = false, kind = "scrollbox", ["in"] = "projectsPickerPanel",
    binding = "projects.shoppingListRows", rowKind = "projectsShoppingRow",
    spacing = 1, width = "fill", height = 110, order = 24,
    visible = "projects.hasShoppingList",
}

-- Detail (right rail): room info + crate management.
LC.widgets["projectsDetailPanel.name"] = {
    tooltip = false, kind = "label", ["in"] = "projectsDetailPanel",
    binding = "projects.roomDetailName", font = "subheading", height = 20, width = "fill", order = 10,
}
LC.widgets["projectsDetailPanel.meta"] = {
    tooltip = false, kind = "label", ["in"] = "projectsDetailPanel",
    binding = "projects.roomDetailMeta", font = "caption", height = 16, width = "fill", order = 20,
}
LC.widgets["projectsDetailPanel.note"] = {
    tooltip = false, kind = "label", ["in"] = "projectsDetailPanel",
    text = "locale:PROJ_ROOM_CONNECT_HINT",
    font = "caption", width = "fill", height = 28, order = 30, visible = "projects.sidePanelOpen",
}
-- Crate detail: room's crate decor list + add-crate CTA.
LC.widgets["projectsDetailPanel.crateTitle"] = {
    tooltip = false, kind = "label", ["in"] = "projectsDetailPanel",
    binding = "projects.crateDetailTitle", font = "subheading", width = "fill", height = 20, order = 40,
    visible = "projects.crateDetailHasCrate",
}
LC.widgets["projectsDetailPanel.addDecor"] = {
    tooltip = false, kind = "button", ["in"] = "projectsDetailPanel",
    font = "body", text = "locale:PROJ_ADD_DECOR", width = 120, height = 24, order = 42,
    visible = "projects.crateDetailHasCrate",
}
-- Export / Import in the header (fill title pushes them right).
LC.widgets["projectsDetailPanel.exportCrate"] = {
    tooltip = false, kind = "button", ["in"] = "projectsDetailPanel", slot = "header",
    font = "body", text = "locale:PROJ_EXPORT_BTN", width = 62, height = 22, order = 6,
    visible = "projects.crateDetailHasCrate",
}
LC.widgets["projectsDetailPanel.importCrate"] = {
    tooltip = false, kind = "button", ["in"] = "projectsDetailPanel", slot = "header",
    font = "body", text = "locale:COMMON_IMPORT", width = 62, height = 22, order = 7,
    visible = "projects.sidePanelOpen",
}
-- Orphaned crates: rooms removed on recapture; re-attach to selected room or delete.
LC.widgets["projectsDetailPanel.orphanLabel"] = {
    tooltip = false, kind = "label", ["in"] = "projectsDetailPanel",
    text = "locale:PROJ_ORPHAN_REATTACH_LABEL", font = "caption",
    width = "fill", height = 28, order = 46, visible = "projects.orphansAttachable",
}
LC.widgets["projectsDetailPanel.orphanList"] = {
    tooltip = false, kind = "scrollbox", ["in"] = "projectsDetailPanel",
    binding = "projects.orphanRows", rowKind = "projectsOrphanRow",
    spacing = 2, width = "fill", height = 90, order = 48,
    visible = "projects.orphansAttachable", selection = { deselectable = true },
}
LC.widgets["projectsDetailPanel.addCrate"] = {
    tooltip = { recipe = "ProjectsAddCrate" }, kind = "button", ["in"] = "projectsDetailPanel",
    font = "body", text = "locale:PROJ_ADD_CRATE", width = 120, height = 24, order = 45,
    visible = "projects.crateDetailNeedsCrate",
}
LC.widgets["projectsDetailPanel.crateList"] = {
    tooltip = false, kind = "scrollbox", ["in"] = "projectsDetailPanel",
    binding = "projects.crateDetailRows", rowKind = "projectsCrateRow",
    spacing = 2, width = "fill", height = "fill", order = 50,
    visible = "projects.crateDetailHasCrate", selection = { deselectable = true },
}
-- Bottom action: detach the crate from this room -> it falls to the orphan bay
-- (reattachable). Sits below the fill crateList. Shown only when a crate exists.
LC.widgets["projectsDetailPanel.detachCrate"] = {
    tooltip = { recipe = "ProjectsDetachCrate" }, kind = "button", ["in"] = "projectsDetailPanel",
    font = "body", text = "locale:PROJ_DETACH_CRATE", width = "fill", height = 24, order = 60,
    variant = "tertiary", visible = "projects.crateDetailHasCrate",
}

-- ===== Layouts widgets =======================================================

-- Left list panel header: title + spacer + Import button.
LC.widgets["projectsLayoutsListPanel.title"] = {
    tooltip = false, kind = "label", ["in"] = "projectsLayoutsListPanel", slot = "header",
    text = "locale:PROJ_LAYOUTS_TITLE", font = "heading", height = 18, width = "auto", order = 5,
}
LC.widgets["projectsLayoutsListPanel.headerSpacer"] = {
    tooltip = false, kind = "spacer", ["in"] = "projectsLayoutsListPanel", slot = "header",
    width = "fill", height = 14, order = 8,
}
LC.widgets["projectsLayoutsListPanel.importBtn"] = {
    tooltip = { recipe = "LayoutImport" }, kind = "button", ["in"] = "projectsLayoutsListPanel", slot = "header",
    font = "body", text = "locale:COMMON_IMPORT", width = 72, height = 22, order = 10,
}
-- Version list: house group headers interleaved with version rows (flat projection).
LC.widgets["projectsLayoutsListPanel.list"] = {
    tooltip = false, kind = "scrollbox", ["in"] = "projectsLayoutsListPanel",
    binding = "projects.layoutListRows", rowKind = "projectsLayoutGroupRow",
    spacing = 1, width = "fill", height = "fill", order = 20,
}

-- Right detail header: version name + LIVE/what-if badge (string selector).
LC.widgets["projectsLayoutsDetailPanel.name"] = {
    tooltip = false, kind = "label", ["in"] = "projectsLayoutsDetailPanel", slot = "header",
    binding = "projects.layoutDetailHeader", font = "heading", height = 18, width = "auto", order = 5,
}
LC.widgets["projectsLayoutsDetailPanel.headerSpacer"] = {
    tooltip = false, kind = "spacer", ["in"] = "projectsLayoutsDetailPanel", slot = "header",
    width = "fill", height = 14, order = 8,
}
-- Detail body: preview canvas (controller-managed), stats, action buttons.
-- Preview: a plain Frame the controller renders floors into.
LC.widgets["projectsLayoutsDetailPanel.preview"] = {
    tooltip = false, kind = "layoutPreview", ["in"] = "projectsLayoutsDetailPanel",
    binding = { model = "projects.layoutPreviewModel" },
    -- FLEX height: absorbs whatever's left after the fixed stats + action buttons,
    -- so the controls always sit inside the panel (a fixed 490 overflowed the body
    -- once the selection-gated buttons appeared -- the overspec check can't see
    -- conditionally-visible widgets, so flex is the robust fix).
    width = "fill", height = "fill", order = 10,
}
-- Stats line: Rooms / Floors / Budget (string selector).
LC.widgets["projectsLayoutsDetailPanel.stats"] = {
    tooltip = false, kind = "label", ["in"] = "projectsLayoutsDetailPanel",
    binding = "projects.layoutDetailStats", font = "caption", height = 16, width = "fill", order = 20,
}
-- Action buttons in two horizontal rows: primary (Load/Share) + secondary
-- (Rename/Duplicate/Delete). The buttons keep their visible gate; the rows are
-- fixed-height (the preview flexes above them, so they never overflow the body).
LC.sections["projectsLayoutsDetailPanel.actions1"] = {
    ["in"] = "projectsLayoutsDetailPanel", layout = "horizontal",
    height = 24, gap = "sm", order = 30,
}
LC.sections["projectsLayoutsDetailPanel.actions2"] = {
    ["in"] = "projectsLayoutsDetailPanel", layout = "horizontal",
    height = 22, gap = "sm", order = 32,
}
-- Primary row.
LC.widgets["projectsLayoutsDetailPanel.loadBtn"] = {
    tooltip = { recipe = "LayoutLoad" }, kind = "button", ["in"] = "projectsLayoutsDetailPanel.actions1",
    font = "body", text = "locale:PROJ_LOAD_IN_ARCHITECT", width = 140, height = 24, order = 10,
    visible = "projects.hasLayoutSelection",
}
LC.widgets["projectsLayoutsDetailPanel.shareBtn"] = {
    tooltip = { recipe = "LayoutShare" }, kind = "button", ["in"] = "projectsLayoutsDetailPanel.actions1",
    font = "body", text = "locale:PROJ_SHARE_CODE", width = 100, height = 24, order = 20,
    visible = "projects.hasLayoutSelection",
}
-- Secondary row.
LC.widgets["projectsLayoutsDetailPanel.renameBtn"] = {
    tooltip = false, kind = "button", ["in"] = "projectsLayoutsDetailPanel.actions2",
    font = "body", text = "locale:PROJ_RENAME_BTN", width = 80, height = 22, order = 10,
    visible = "projects.hasLayoutSelection",
}
LC.widgets["projectsLayoutsDetailPanel.duplicateBtn"] = {
    tooltip = { recipe = "LayoutDuplicate" }, kind = "button", ["in"] = "projectsLayoutsDetailPanel.actions2",
    font = "body", text = "locale:PROJ_DUPLICATE_BTN", width = 90, height = 22, order = 20,
    visible = "projects.hasLayoutSelection",
}
LC.widgets["projectsLayoutsDetailPanel.deleteBtn"] = {
    tooltip = false, kind = "button", ["in"] = "projectsLayoutsDetailPanel.actions2",
    font = "body", text = "locale:COMMON_DELETE", width = 80, height = 22, order = 30,
    visible = "projects.hasLayoutSelection",
}

-- ===== Picker widgets ========================================================
LC.widgets["projectsPickerListPanel.title"] = {
    tooltip = false, kind = "label", ["in"] = "projectsPickerListPanel", slot = "header",
    text = "locale:PROJ_PICKER_TITLE", font = "heading", height = 18, width = "auto", order = 5,
}
LC.widgets["projectsPickerListPanel.search"] = {
    tooltip = false, kind = "editbox", ["in"] = "projectsPickerListPanel", slot = "header",
    font = "body", width = "fill", height = 22, order = 10, multiline = false,
    placeholder = "locale:DECOR_SEARCH_PLACEHOLDER",
}
LC.widgets["projectsPickerListPanel.back"] = {
    tooltip = false, kind = "button", ["in"] = "projectsPickerListPanel", slot = "header",
    font = "body", text = "locale:COMMON_BACK", width = 60, height = 22, order = 20,
}
-- Import from a saved Style: a single menu button (was a stacked scrollbox) -> opens
-- a per-style menu (Add all / Add missing). Frees the panel for one decor list.
LC.widgets["projectsPickerListPanel.styleImport"] = {
    tooltip = false, kind = "button", ["in"] = "projectsPickerListPanel",
    font = "body", text = "locale:PROJ_IMPORT_FROM_STYLE", width = "auto", height = 22, order = 1,
    variant = "tertiary", visible = "projects.pickerHasStyles",
}
-- Gated bulk-add above the list (picker is owned-only; filterChips removed).
LC.widgets["projectsPickerListPanel.addAll"] = {
    tooltip = false, kind = "button", ["in"] = "projectsPickerListPanel",
    font = "body", text = "locale:PROJ_ADD_ALL", binding = { text = "projects.pickerBulkAddLabel" },
    width = 130, height = 22, order = 7, visible = "projects.pickerCanBulkAdd",
}
LC.widgets["projectsPickerListPanel.list"] = {
    tooltip = false, kind = "scrollbox", ["in"] = "projectsPickerListPanel",
    binding = "projects.pickerResults", rowKind = "projectsPickerRow",
    spacing = 2, width = "fill", height = "fill", order = 30, selection = { deselectable = true },
}
LC.widgets["projectsPickerPreviewPanel.preview"] = {
    tooltip = false, kind = "modelPreview", ["in"] = "projectsPickerPreviewPanel",
    binding = { itemID = "projects.pickerSelectedItemID" },
    width = "fill", height = "fill", order = 10,
    showControls = true, bgTile = true, placeholder = "locale:DECOR_PREVIEW_PLACEHOLDER",
    sceneInsets = { top = 8, right = 8, bottom = 8, left = 8 },
    defaultSceneID = 859,   -- HOUSING_CATALOG_DECOR_MODELSCENEID_DEFAULT (12.0.5)
}
-- Vertical category rail: in-situ category -> subcategory drill-down.
-- chipPadH=0 so 42px icon cells fit the 44px column without overflowing.
LC.widgets["projectsPickerRailPanel.rail"] = {
    tooltip = false, kind = "chipStrip", ["in"] = "projectsPickerRailPanel",
    binding = "projects.pickerRail", cellKind = "projectsRailIcon",
    orientation = "vertical",
    chipHeight = 42, chipMinWidth = 42, chipPadH = 0, horizontalSpacing = 2, verticalSpacing = 2,
    width = "fill", height = "fill", order = 10,
}
