-- HDGR_LayoutConfig_Menagerie.lua
-- ============================================================================
-- The Menagerie (House > Pets) -- its own view, a nav child under House beside
-- Blueprints. Spec rulings 9-14; plan HDGR_MENAGERIE_LATTICE_PLAN_2026-08-24.
--
-- Shape: list column (mode switch, the two-row identity filter OR the By Spot
-- needs-vocabulary, the pet list) + detail column (the scene with its strip,
-- the four card facts, the behaviour flowchart, the hidden Described block).
-- Behaviours render EXACTLY ONCE (ruling 10) -- the flowchart is the surface.

HDG = HDG or {}
local LC = HDG.LayoutConfig

LC.window.views.menagerie = {
    explicit = true,
    width    = "auto",
    height   = "auto",
    columns  = { 300, 540 },
    rows     = { 680 },
    cells    = {
        list   = { col = 1, row = 1, colSpan = 1, rowSpan = 1 },
        detail = { col = 2, row = 1, colSpan = 1, rowSpan = 1 },
    },
}

-- ===== Panels ================================================================

LC.panels.menagerieListPanel = {
    kind = "panel",
    cell = { menagerie = "list" },
    visibleInViews = { "menagerie" },
    slots = {
        header = {
            height = 34, layout = "horizontal", gap = "md",
            padding = { top = 0, right = "xl", bottom = 0, left = "xl" },
            chrome = "PanelHeader",
        },
    },
}

LC.panels.menagerieDetailPanel = {
    kind = "panel",
    cell = { menagerie = "detail" },
    visibleInViews = { "menagerie" },
    slots = {
        header = {
            height = 34, layout = "horizontal", gap = "md",
            padding = { top = 0, right = "xl", bottom = 0, left = "xl" },
            chrome = "PanelHeader",
        },
    },
}

-- ===== Sections: list column ================================================

LC.sections["menagerie.body"] = {
    ["in"] = "menagerieListPanel", layout = "vertical", padding = "lg", gap = "sm", order = 10,
}
LC.sections["menagerie.modeRow"] = {
    ["in"] = "menagerie.body", layout = "vertical", order = 5, height = 30,
}
-- The two-row identity filter (By Pet) and the needs-vocabulary (By Spot) are
-- sibling stacks gated by mode -- no axis appears in both (ruling 14).
LC.sections["menagerie.byPetFilters"] = {
    ["in"] = "menagerie.body", layout = "vertical", gap = "xs", order = 10, height = 144,
    visible = "menagerie.isByPet",
}
LC.sections["menagerie.bySpotFilters"] = {
    ["in"] = "menagerie.body", layout = "vertical", gap = "xs", order = 11, height = 82,
    visible = "menagerie.isBySpot",
}
LC.sections["menagerie.list"] = {
    ["in"] = "menagerie.body", layout = "fill", order = 20, chrome = "inset",
}
LC.sections["menagerie.statusRail"] = {
    ["in"] = "menagerie.body", layout = "horizontal", height = 16, order = 30,
}

-- ===== Sections: detail column ==============================================

LC.sections["menagerie.detailBody"] = {
    ["in"] = "menagerieDetailPanel", layout = "vertical", padding = "lg", gap = "sm", order = 10,
}
LC.sections["menagerie.stageSlot"] = {
    ["in"] = "menagerie.detailBody", layout = "vertical", height = 300, order = 10, chrome = "inset",
}
LC.sections["menagerie.sceneStrip"] = {
    ["in"] = "menagerie.detailBody", layout = "vertical", order = 20, height = 28,
}
LC.sections["menagerie.facts"] = {
    ["in"] = "menagerie.detailBody", layout = "vertical", gap = "xs", order = 30, chrome = "inset",
    padding = "md", height = 96,
}
LC.sections["menagerie.flowBlock"] = {
    ["in"] = "menagerie.detailBody", layout = "vertical", gap = "xs", order = 40,
}
LC.sections["menagerie.describedBlock"] = {
    ["in"] = "menagerie.detailBody", layout = "vertical", order = 50,
    visible = "menagerie.hasDescription",   -- ruling: Described ships HIDDEN in v1
}

-- ===== Widgets: list column =================================================

LC.widgets["menagerieListPanel.title"] = {
    tooltip = false,
    kind = "label", ["in"] = "menagerieListPanel", slot = "header",
    text = "locale:MENAGERIE_TITLE", font = "heading",
    height = 18, width = "auto", order = 10,
}
LC.widgets["menagerieListPanel.headerSpacer"] = {
    tooltip = false, kind = "spacer", ["in"] = "menagerieListPanel", slot = "header",
    width = "fill", height = 14, order = 50,
}
LC.widgets["menagerieListPanel.modeStrip"] = {
    tooltip = false,
    kind = "chipStrip", ["in"] = "menagerie.modeRow",
    binding = "menagerie.modeChips", cellKind = "menagerieChip",
    chipHeight = 22, order = 10, height = 26,
}
LC.widgets["menagerieListPanel.axes"] = {
    tooltip = false,
    kind = "chipStrip", ["in"] = "menagerie.byPetFilters",
    binding = "menagerie.axes", cellKind = "menagerieChip",
    chipHeight = 20, order = 10, height = 24,
}
LC.widgets["menagerieListPanel.axisValues"] = {
    tooltip = false,
    kind = "chipStrip", ["in"] = "menagerie.byPetFilters",
    binding = "menagerie.axisValues", cellKind = "menagerieChip",
    chipHeight = 20, order = 20, height = 116,
}
LC.widgets["menagerieListPanel.spotSurface"] = {
    tooltip = false,
    kind = "chipStrip", ["in"] = "menagerie.bySpotFilters",
    binding = "menagerie.spotSurfaceChips", cellKind = "menagerieChip",
    chipHeight = 20, order = 10, height = 24,
}
LC.widgets["menagerieListPanel.spotSize"] = {
    tooltip = false,
    kind = "chipStrip", ["in"] = "menagerie.bySpotFilters",
    binding = "menagerie.spotSizeChips", cellKind = "menagerieChip",
    chipHeight = 20, order = 20, height = 24,
}
LC.widgets["menagerieListPanel.spotWants"] = {
    tooltip = false,
    kind = "chipStrip", ["in"] = "menagerie.bySpotFilters",
    binding = "menagerie.spotWantChips", cellKind = "menagerieChip",
    chipHeight = 20, order = 30, height = 24,
}
LC.widgets["menagerieListPanel.list"] = {
    tooltip = false,
    kind = "scrollbox", ["in"] = "menagerie.list",
    binding = "menagerie.items",
    rowKind = "menagerieRow",
    spacing = 1,
    selection = { deselectable = false },
    order = 10,
}
LC.widgets["menagerieListPanel.count"] = {
    tooltip = false,
    kind = "label", role = "TextInfo", ["in"] = "menagerie.statusRail",
    text = "", font = "small", justifyH = "LEFT",
    width = "fill", height = 14, order = 10,
    binding = "menagerie.headerLabel",
}

-- ===== Widgets: detail column ===============================================

LC.widgets["menagerieDetailPanel.title"] = {
    tooltip = false,
    kind = "label", ["in"] = "menagerieDetailPanel", slot = "header",
    text = "locale:MENAGERIE_DETAIL_TITLE", font = "heading",
    height = 18, width = "auto", order = 10,
    binding = "menagerie.card.title",
}
LC.widgets["menagerieDetailPanel.headerSpacer"] = {
    tooltip = false, kind = "spacer", ["in"] = "menagerieDetailPanel", slot = "header",
    width = "fill", height = 14, order = 40,
}
LC.widgets["menagerieDetailPanel.family"] = {
    tooltip = false,
    kind = "label", role = "TextInfo", ["in"] = "menagerieDetailPanel", slot = "header",
    text = "", font = "small", justifyH = "RIGHT",
    height = 14, width = "auto", order = 50,
    binding = "menagerie.card.family",
}
LC.widgets["menagerieDetailPanel.stage"] = {
    tooltip = false,
    kind = "petScene", ["in"] = "menagerie.stageSlot",
    binding = "menagerie.scene",
    width = "fill", height = 300, order = 10,
}
LC.widgets["menagerieDetailPanel.sceneChips"] = {
    tooltip = false,
    kind = "chipStrip", ["in"] = "menagerie.sceneStrip",
    binding = "menagerie.sceneChips", cellKind = "menagerieChip",
    chipHeight = 20, order = 10, height = 24,
}
-- The four card facts (ruling 10 shrank the grid to these).
LC.widgets["menagerieDetailPanel.howBig"] = {
    tooltip = false,
    kind = "label", ["in"] = "menagerie.facts", font = "body", justifyH = "LEFT",
    text = "", width = "fill", height = 16, order = 10,
    binding = "menagerie.card.howBig",
}
LC.widgets["menagerieDetailPanel.needs"] = {
    tooltip = false,
    kind = "label", ["in"] = "menagerie.facts", font = "body", justifyH = "LEFT",
    text = "", width = "fill", height = 16, order = 20,
    binding = "menagerie.card.needs",
}
LC.widgets["menagerieDetailPanel.matches"] = {
    tooltip = false,
    kind = "label", role = "TextInfo", ["in"] = "menagerie.facts", font = "body",
    justifyH = "LEFT", text = "", width = "fill", height = 16, order = 30,
    binding = "menagerie.card.matches",
}
LC.widgets["menagerieDetailPanel.light"] = {
    tooltip = false,
    kind = "label", role = "TextInfo", ["in"] = "menagerie.facts", font = "body",
    justifyH = "LEFT", text = "", width = "fill", height = 16, order = 40,
    binding = "menagerie.card.light",
}
LC.widgets["menagerieDetailPanel.flowHeader"] = {
    tooltip = false,
    kind = "label", ["in"] = "menagerie.flowBlock", font = "heading", justifyH = "LEFT",
    text = "locale:MENAGERIE_FLOW_HEADER", width = "fill", height = 18, order = 10,
}
LC.widgets["menagerieDetailPanel.flow"] = {
    tooltip = false,
    kind = "chipStrip", ["in"] = "menagerie.flowBlock",
    binding = "menagerie.flowChips", cellKind = "menagerieFlowNode",
    chipHeight = 34, order = 20, height = 72,
}
LC.widgets["menagerieDetailPanel.also"] = {
    tooltip = false,
    kind = "chipStrip", ["in"] = "menagerie.flowBlock",
    binding = "menagerie.alsoChips", cellKind = "menagerieChip",
    chipHeight = 18, order = 30, height = 36,
}
-- Described: hidden until a description DB exists (v1 ruling); no layout change
-- needed to light it up.
LC.widgets["menagerieDetailPanel.described"] = {
    tooltip = false,
    kind = "label", role = "TextDim", ["in"] = "menagerie.describedBlock",
    font = "body", justifyH = "LEFT", text = "",
    width = "fill", height = 40, order = 10,
}
