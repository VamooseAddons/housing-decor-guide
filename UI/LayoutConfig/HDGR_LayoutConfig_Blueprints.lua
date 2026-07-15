-- HDGR_LayoutConfig_Blueprints.lua
-- ============================================================================
-- Blueprints tab (Projects child, 12.1): master-detail. Left = paste field +
-- collection browser; right = inspector (name/code header, house picker,
-- budget meters, fit verdict, missing filter, content groups, action row,
-- guidance strip). Mirrors the projectsLayouts master-detail idiom.
--
-- 12.1-only: with the whole file gated, the view/panels/widgets simply don't
-- exist on live -- matching the conditional TABS/nav insert in Constants, so a
-- persisted account.ui.view can never land on a dead panel.
if not HDG.Constants.IS_121 then return end  -- exception(boundary): 12.1-only view

local LC = HDG.LayoutConfig

-- Master-detail: left browser 280 | right inspector 560.
LC.window.views.projectsBlueprints = {
    explicit = true,
    width    = "auto",
    height   = "auto",
    columns  = { 280, 560 },
    rows     = { 600 },
    cells    = {
        list   = { col = 1, row = 1, colSpan = 1, rowSpan = 1 },
        detail = { col = 2, row = 1, colSpan = 1, rowSpan = 1 },
    },
}

-- ===== Panels ================================================================

LC.panels.blueprintsListPanel = {
    kind = "panel",
    cell = { projectsBlueprints = "list" },
    visibleInViews = { "projectsBlueprints" },
    slots = {
        header = {
            height = 34, layout = "horizontal", gap = "sm",
            padding = { top = 0, right = "lg", bottom = 0, left = "lg" },
            chrome = "PanelHeader",
        },
        body = { layout = "vertical", gap = "sm", padding = "lg" },
    },
}

LC.panels.blueprintsDetailPanel = {
    kind = "panel",
    cell = { projectsBlueprints = "detail" },
    visibleInViews = { "projectsBlueprints" },
    slots = {
        header = {
            height = 34, layout = "horizontal", gap = "sm",
            padding = { top = 0, right = "lg", bottom = 0, left = "lg" },
            chrome = "PanelHeader",
        },
        body = { layout = "vertical", gap = "sm", padding = "lg" },
    },
}

-- ===== Left: paste + collection browser =====================================

LC.widgets["blueprintsListPanel.titleIcon"] = {
    tooltip = false, kind = "label", ["in"] = "blueprintsListPanel", slot = "header",
    text = "|A:common-icons-blueprints:18:18|a", font = "heading", height = 18, width = "auto", order = 3,
}
LC.widgets["blueprintsListPanel.title"] = {
    tooltip = false, kind = "label", ["in"] = "blueprintsListPanel", slot = "header",
    text = "locale:BP_TITLE", font = "heading", height = 18, width = "auto", order = 5,
}
LC.widgets["blueprintsListPanel.headerSpacer"] = {
    tooltip = false, kind = "spacer", ["in"] = "blueprintsListPanel", slot = "header",
    width = "fill", height = 14, order = 8,
}
LC.widgets["blueprintsListPanel.saveBtn"] = {
    tooltip = { recipe = "BlueprintSave" }, kind = "button", ["in"] = "blueprintsListPanel", slot = "header",
    font = "body", text = "locale:BP_SAVE", width = 104, height = 22, order = 10,
}

LC.sections["blueprintsListPanel.pasteRow"] = {
    ["in"] = "blueprintsListPanel", layout = "horizontal", height = 22, gap = "sm", order = 5,
}
LC.widgets["blueprintsListPanel.pasteBox"] = {
    tooltip = false, kind = "editbox", ["in"] = "blueprintsListPanel.pasteRow", font = "body",
    height = 22, width = "fill", order = 5, multiline = false,
    placeholder = "locale:BP_PASTE_PLACEHOLDER",
}
LC.widgets["blueprintsListPanel.inspectBtn"] = {
    tooltip = { recipe = "BlueprintInspect" }, kind = "button", ["in"] = "blueprintsListPanel.pasteRow",
    font = "body", text = "locale:BP_INSPECT", width = 64, height = 22, order = 10,
}

-- Collection: pasted & shared first, then the player's saved groups.
LC.widgets["blueprintsListPanel.list"] = {
    tooltip = false, kind = "scrollbox", ["in"] = "blueprintsListPanel",
    binding = "blueprints.collectionRows", rowKind = "blueprintCollectionRow",
    spacing = 1, width = "fill", height = "fill", order = 20,
}

LC.widgets["blueprintsListPanel.slots"] = {
    tooltip = false, kind = "label", ["in"] = "blueprintsListPanel",
    binding = "blueprints.slotsText", font = "caption", height = 16, width = "fill", order = 30,
}

-- ===== Right: inspector ======================================================

-- Header: display name (label; inline rename lands via the name editbox next
-- to it), house picker on the right.
LC.widgets["blueprintsDetailPanel.name"] = {
    tooltip = false, kind = "label", ["in"] = "blueprintsDetailPanel", slot = "header",
    binding = "blueprints.displayName", font = "heading", height = 18, width = "fill", order = 5,
}
LC.widgets["blueprintsDetailPanel.housePicker"] = {
    tooltip = { recipe = "BlueprintTargetHouse" }, kind = "dropdown", ["in"] = "blueprintsDetailPanel", slot = "header",
    width = 190, height = 22, order = 10, minWidth = 160,
    placeholder = "locale:BP_PICK_HOUSE",
    binding = { menu = "blueprints.houseMenuItems", current = "blueprints.targetHouse" },
    dispatch = { type = "BLUEPRINT_SET_TARGET_HOUSE", payloadKey = "houseGUID" },
}

-- Code row: the share code verbatim in a quiet read-only editbox (click ->
-- select-all -> Ctrl+C; the standard WoW share-code pattern) + rename box.
LC.sections["blueprintsDetailPanel.codeRow"] = {
    ["in"] = "blueprintsDetailPanel", layout = "horizontal", height = 22, gap = "sm", order = 4,
}
LC.widgets["blueprintsDetailPanel.codeBox"] = {
    tooltip = { recipe = "BlueprintCopyCode" }, kind = "editbox", ["in"] = "blueprintsDetailPanel.codeRow",
    font = "small", height = 20, width = 200, order = 5, multiline = false,
}
LC.widgets["blueprintsDetailPanel.linkBtn"] = {
    tooltip = { recipe = "BlueprintLink" }, kind = "button", ["in"] = "blueprintsDetailPanel.codeRow",
    font = "small", text = "locale:BP_LINK", width = 46, height = 20, order = 7,
}
LC.widgets["blueprintsDetailPanel.renameLabel"] = {
    tooltip = false, kind = "label", ["in"] = "blueprintsDetailPanel.codeRow",
    text = "locale:BP_RENAME_LABEL", font = "small", role = "TextDim",
    width = "auto", height = 14, order = 9,
}
LC.widgets["blueprintsDetailPanel.nameBox"] = {
    tooltip = { recipe = "BlueprintRename" }, kind = "editbox", ["in"] = "blueprintsDetailPanel.codeRow",
    font = "small", height = 20, width = "fill", order = 10, multiline = false,
    placeholder = "locale:BP_NAME_PLACEHOLDER",
}

-- Status line (pending count-up / friendly failure), then fit verdict.
LC.widgets["blueprintsDetailPanel.status"] = {
    tooltip = false, kind = "label", ["in"] = "blueprintsDetailPanel",
    binding = "blueprints.statusLine", font = "caption", height = 14, width = "fill", order = 6,
}
-- Fit verdict as a card badge (mockup pill): accent bar + washed fill; the
-- label's text role tones success/blocked in Refresh. Hidden with no verdict.
LC.sections["blueprintsDetailPanel.verdictBand"] = {
    ["in"] = "blueprintsDetailPanel", layout = "horizontal", chrome = "card",
    padding = { top = 2, right = "sm", bottom = 2, left = "sm" },
    height = 22, order = 8, visible = "blueprints.hasVerdict",
}
LC.widgets["blueprintsDetailPanel.verdict"] = {
    tooltip = false, kind = "label", ["in"] = "blueprintsDetailPanel.verdictBand",
    binding = "blueprints.fitVerdict", font = "body", height = 16, width = "fill", order = 5,
}

-- Budget meters: three text+bar pairs on one row.
LC.sections["blueprintsDetailPanel.meters"] = {
    ["in"] = "blueprintsDetailPanel", layout = "horizontal", height = 34, gap = "lg", order = 10,
}
LC.sections["blueprintsDetailPanel.meterRoomCol"] = {
    ["in"] = "blueprintsDetailPanel.meters", layout = "vertical", width = "fill", gap = "xs", order = 5,
}
LC.widgets["blueprintsDetailPanel.meterRoomText"] = {
    tooltip = false, kind = "label", ["in"] = "blueprintsDetailPanel.meterRoomCol",
    binding = "blueprints.meterTextRoom", font = "caption", height = 14, width = "fill", order = 5,
}
LC.widgets["blueprintsDetailPanel.meterRoomBar"] = {
    tooltip = { recipe = "BlueprintMeterRoom" }, kind = "progressbar", ["in"] = "blueprintsDetailPanel.meterRoomCol",
    binding = { progress = "blueprints.meterFracRoom" }, width = "fill", height = 8, order = 10,
}
LC.sections["blueprintsDetailPanel.meterIntCol"] = {
    ["in"] = "blueprintsDetailPanel.meters", layout = "vertical", width = "fill", gap = "xs", order = 10,
}
LC.widgets["blueprintsDetailPanel.meterIntText"] = {
    tooltip = false, kind = "label", ["in"] = "blueprintsDetailPanel.meterIntCol",
    binding = "blueprints.meterTextInterior", font = "caption", height = 14, width = "fill", order = 5,
}
LC.widgets["blueprintsDetailPanel.meterIntBar"] = {
    tooltip = { recipe = "BlueprintMeterInterior" }, kind = "progressbar", ["in"] = "blueprintsDetailPanel.meterIntCol",
    binding = { progress = "blueprints.meterFracInterior" }, width = "fill", height = 8, order = 10,
}
LC.sections["blueprintsDetailPanel.meterExtCol"] = {
    ["in"] = "blueprintsDetailPanel.meters", layout = "vertical", width = "fill", gap = "xs", order = 15,
}
LC.widgets["blueprintsDetailPanel.meterExtText"] = {
    tooltip = false, kind = "label", ["in"] = "blueprintsDetailPanel.meterExtCol",
    binding = "blueprints.meterTextExterior", font = "caption", height = 14, width = "fill", order = 5,
}
LC.widgets["blueprintsDetailPanel.meterExtBar"] = {
    tooltip = { recipe = "BlueprintMeterExterior" }, kind = "progressbar", ["in"] = "blueprintsDetailPanel.meterExtCol",
    binding = { progress = "blueprints.meterFracExterior" }, width = "fill", height = 8, order = 10,
}
-- Pet decor budgets (12.1): interior + exterior. Deliberately NARROWER than the
-- three main meters (fixed width vs "fill") -- pet budgets are small and secondary.
LC.sections["blueprintsDetailPanel.meterIntPetCol"] = {
    ["in"] = "blueprintsDetailPanel.meters", layout = "vertical", width = 56, gap = "xs", order = 20,
}
LC.widgets["blueprintsDetailPanel.meterIntPetText"] = {
    tooltip = false, kind = "label", ["in"] = "blueprintsDetailPanel.meterIntPetCol",
    binding = "blueprints.meterTextInteriorPet", font = "caption", height = 14, width = "fill", order = 5,
}
LC.widgets["blueprintsDetailPanel.meterIntPetBar"] = {
    tooltip = { recipe = "BlueprintMeterInteriorPet" }, kind = "progressbar", ["in"] = "blueprintsDetailPanel.meterIntPetCol",
    binding = { progress = "blueprints.meterFracInteriorPet" }, width = "fill", height = 8, order = 10,
}
LC.sections["blueprintsDetailPanel.meterExtPetCol"] = {
    ["in"] = "blueprintsDetailPanel.meters", layout = "vertical", width = 56, gap = "xs", order = 25,
}
LC.widgets["blueprintsDetailPanel.meterExtPetText"] = {
    tooltip = false, kind = "label", ["in"] = "blueprintsDetailPanel.meterExtPetCol",
    binding = "blueprints.meterTextExteriorPet", font = "caption", height = 14, width = "fill", order = 5,
}
LC.widgets["blueprintsDetailPanel.meterExtPetBar"] = {
    tooltip = { recipe = "BlueprintMeterExteriorPet" }, kind = "progressbar", ["in"] = "blueprintsDetailPanel.meterExtPetCol",
    binding = { progress = "blueprints.meterFracExteriorPet" }, width = "fill", height = 8, order = 10,
}

-- Filter row: segmented All / Missing-only pair + item counts right.
LC.sections["blueprintsDetailPanel.filterRow"] = {
    ["in"] = "blueprintsDetailPanel", layout = "horizontal", height = 22, gap = "sm", order = 15,
}
LC.widgets["blueprintsDetailPanel.filterAll"] = {
    tooltip = false, kind = "button", ["in"] = "blueprintsDetailPanel.filterRow", variant = "tertiary",
    font = "small", text = "locale:BP_FILTER_ALL", width = 76, height = 20, order = 5,
    binding = { active = "blueprints.filterAllActive" },
}
LC.widgets["blueprintsDetailPanel.filterMissing"] = {
    tooltip = { recipe = "BlueprintMissingOnly" }, kind = "button", ["in"] = "blueprintsDetailPanel.filterRow", variant = "tertiary",
    font = "small", text = "locale:BP_FILTER_MISSING", width = 92, height = 20, order = 10,
    binding = { active = "blueprints.filterMissingActive" },
}
LC.widgets["blueprintsDetailPanel.filterSpacer"] = {
    tooltip = false, kind = "spacer", ["in"] = "blueprintsDetailPanel.filterRow",
    width = "fill", height = 14, order = 15,
}
LC.widgets["blueprintsDetailPanel.counts"] = {
    tooltip = false, kind = "label", ["in"] = "blueprintsDetailPanel.filterRow",
    binding = "blueprints.itemCountText", font = "caption", height = 14, width = "auto", order = 20,
}

-- Blank state: first open / nothing selected (UX review #1; Acquisition idiom).
LC.widgets["blueprintsDetailPanel.blankIcon"] = {
    tooltip = false, kind = "atlas", ["in"] = "blueprintsDetailPanel",
    visible = "blueprints.blankDetail",
    atlas = "housing-map-plot-player-house", tone = "text.dim",
    width = 26, height = 26, order = 17,
}
LC.widgets["blueprintsDetailPanel.blank"] = {
    tooltip = false, kind = "label", ["in"] = "blueprintsDetailPanel",
    visible = "blueprints.blankDetail", role = "TextDim",
    text = "locale:BP_BLANK", font = "body", justifyH = "CENTER",
    width = "fill", height = 22, order = 18,
}

-- Content groups (collapsible headers + item rows, flat projection).
LC.widgets["blueprintsDetailPanel.content"] = {
    tooltip = false, kind = "scrollbox", ["in"] = "blueprintsDetailPanel",
    binding = "blueprints.contentRows", rowKind = "blueprintContentRow",
    spacing = 1, width = "fill", height = "fill", order = 20,
}

-- Action row: Route to Shopping | Import as Set | Architect (House/Interior) | Apply to House.
-- All enable only with a selection -- ungated they looked clickable over a blank panel.
LC.sections["blueprintsDetailPanel.actions"] = {
    ["in"] = "blueprintsDetailPanel", layout = "horizontal", height = 22, gap = "sm", order = 30,
}
LC.widgets["blueprintsDetailPanel.routeBtn"] = {
    tooltip = { recipe = "BlueprintRoute" }, kind = "button", ["in"] = "blueprintsDetailPanel.actions",
    font = "body", text = "locale:BP_ROUTE_SHOPPING", width = 120, height = 22, order = 5,
    variant = "primary",   -- the tab's primary CTA (design fact 10; mockup .primary)
    binding = { enabled = "blueprints.hasSelection" },
}
LC.widgets["blueprintsDetailPanel.setBtn"] = {
    tooltip = { recipe = "BlueprintImportSet" }, kind = "button", ["in"] = "blueprintsDetailPanel.actions",
    font = "body", text = "locale:BP_IMPORT_SET", width = 100, height = 22, order = 10,
    binding = { enabled = "blueprints.hasSelection" },
}
LC.widgets["blueprintsDetailPanel.architectBtn"] = {
    tooltip = { recipe = "BlueprintArchitect" }, kind = "button", ["in"] = "blueprintsDetailPanel.actions",
    font = "body", text = "locale:BP_OPEN_ARCHITECT", width = 84, height = 22, order = 15,
    visible = "blueprints.selectedIsArchitectable",  -- interior room layout: House/Interior only
}
LC.widgets["blueprintsDetailPanel.importBtn"] = {
    tooltip = { recipe = "BlueprintImportHouse" }, kind = "button", ["in"] = "blueprintsDetailPanel.actions",
    font = "body", text = "locale:BP_IMPORT_HOUSE", width = 108, height = 22, order = 22,
    binding = { enabled = "blueprints.hasSelection" },
}
LC.widgets["blueprintsDetailPanel.actionsSpacer"] = {
    tooltip = false, kind = "spacer", ["in"] = "blueprintsDetailPanel.actions",
    width = "fill", height = 14, order = 25,
}

-- Guidance strip: ABOVE the action row so the save-after-apply reminder is
-- read before the buttons get clicked (UX review #11).
LC.widgets["blueprintsDetailPanel.guidance"] = {
    tooltip = false, kind = "label", ["in"] = "blueprintsDetailPanel",
    text = "locale:BP_GUIDANCE", font = "caption", height = 32, width = "fill", order = 28,
}
