-- HDGR_LayoutConfig_Pets.lua
-- ============================================================================
-- Pets browser: a top-filter MODE of the decor view, so it borrows that view's
-- `body` and `detail` cells rather than declaring a view of its own.
--
-- Sibling panels gated by `visible`, NOT a re-used scrollbox: `rowKind` is
-- consumed at build time to pick the row factory and the element extent, and each
-- scrollbox owns its own frame pool, so swapping the kind live would mean tearing
-- that pool down mid-paint. The decor body cell already holds four gated siblings
-- (decorPanel / Loading / Error / Blank); these are the fifth and sixth.

HDG = HDG or {}
local LC = HDG.LayoutConfig

-- ===== Panels ================================================================

LC.panels.petPanel = {
    kind = "panel",
    cell = { decor = "body" },
    visibleInViews = { "decor" },
    visible = "decor.showPetBrowser",
    slots = {
        header = {
            height = 34, layout = "horizontal", gap = "md",
            padding = { top = 0, right = "xl", bottom = 0, left = "xl" },
            chrome = "PanelHeader",
        },
    },
}

-- Blank overlay: pets mode with no matches (search or family narrowed to nothing).
-- Same body cell; showPetBrowser goes false at the same moment this goes true.
LC.panels.petBlankPanel = {
    kind = "panel",
    cell = { decor = "body" },
    visibleInViews = { "decor" },
    visible = "pets.isBlank",
}

LC.panels.petDetailPanel = {
    kind = "panel",
    cell = { decor = "detail" },
    visibleInViews = { "decor" },
    visible = "pets.isMode",
    slots = {
        header = {
            height = 34, layout = "horizontal", gap = "md",
            padding = { top = 0, right = "xl", bottom = 0, left = "xl" },
            chrome = "PanelHeader",
        },
    },
}

-- ===== Sections ==============================================================

LC.sections["pets.body"] = {
    ["in"] = "petPanel", layout = "vertical", padding = "lg", gap = "sm", order = 10,
}
LC.sections["pets.list"] = {
    ["in"] = "pets.body", layout = "fill", order = 10, chrome = "inset",
}
LC.sections["pets.statusRail"] = {
    ["in"] = "pets.body", layout = "horizontal", height = 16, order = 20,
}
LC.sections["pets.detailBody"] = {
    ["in"] = "petDetailPanel", layout = "vertical", padding = "lg", gap = "md", order = 10,
}
-- 410h matches decor.previewSlot so switching modes does not resize the column.
LC.sections["pets.previewSlot"] = {
    ["in"] = "pets.detailBody", layout = "vertical", height = 410, order = 10,
}
LC.sections["pets.detailCard"] = {
    ["in"]  = "pets.detailBody", layout = "vertical", padding = "lg",
    gap = "sm", width = "fill", order = 20, chrome = "inset",
}

-- ===== Widgets ===============================================================

LC.widgets["petPanel.title"] = {
    tooltip = false,
    kind = "label", ["in"] = "petPanel", slot = "header",
    text = "locale:PETS_BROWSER_TITLE", font = "heading",
    height = 18, width = "auto", order = 10,
}
LC.widgets["petPanel.headerSpacer"] = {
    tooltip = false, kind = "spacer", ["in"] = "petPanel", slot = "header",
    width = "fill", height = 14, order = 50,
}
LC.widgets["petPanel.list"] = {
    tooltip = false,
    kind = "scrollbox", ["in"] = "pets.list",
    binding = "pets.items",
    rowKind = "petRow",
    spacing = 1,
    selection = { deselectable = false },
    order = 10,
}
LC.widgets["petPanel.count"] = {
    tooltip = false,
    kind = "label", role = "TextInfo", ["in"] = "pets.statusRail",
    text = "", font = "small", justifyH = "LEFT",
    width = "fill", height = 14, order = 10,
    binding = "pets.headerLabel",
}
LC.widgets["petBlankPanel.icon"] = {
    tooltip = false,
    kind = "atlas", ["in"] = "petBlankPanel",
    atlas = HDG.Constants.BULLET_DOT_ATLAS, tone = "text.dim",
    width = 24, height = 24, order = 5,
}
LC.widgets["petBlankPanel.label"] = {
    tooltip = false,
    kind = "label", ["in"] = "petBlankPanel", role = "TextDim",
    text = "locale:PETS_BLANK",
    font = "body", justifyH = "CENTER",
    width = "fill", height = 22, order = 10,
}

-- Pets search sibling. The decor search box lives in the shared
-- decor.filterRowBottom section and its placeholder names decor, so pets gets its
-- own gated twin: one widget with two identities reads worse than two widgets with
-- one each. Both write the same transient, so the query survives a mode switch.
LC.widgets["petPanel.search"] = {
    tooltip = false,
    kind = "editbox", ["in"] = "decor.filterRowBottom", font = "body",
    height = 22, width = 240, order = 10,
    multiline = false,
    placeholder = "locale:PETS_SEARCH_PLACEHOLDER",
    visible = "pets.isMode",
}

-- ===== Detail pane ===========================================================

LC.widgets["petDetailPanel.title"] = {
    tooltip = false,
    kind = "label", ["in"] = "petDetailPanel", slot = "header",
    text = "locale:PETS_CLICK_A_PET", font = "heading",
    height = 18, width = "auto", order = 10,
    binding = "pets.selectedPet.name",
}
-- The large preview. Reuses modelPreview whole: same registered-scene transition,
-- orbit camera, inverted-pitch hook, background options and 2D fallback as decor.
-- No defaultSceneID -- the pet path always resolves its scene from
-- GetPetModelSceneInfoBySpeciesID, so there is nothing to fall back to.
LC.widgets["petDetailPanel.preview"] = {
    tooltip = false,
    kind = "modelPreview", ["in"] = "pets.previewSlot", order = 10,
    binding = { speciesID = "pets.selectedSpeciesID", bg = "decor.previewBg" },
    showControls = true,
    showCorbels  = false,
    showAtlas    = false,
    bgTile         = true,
    configurableBg = true,
    placeholder  = "locale:PETS_PREVIEW_PLACEHOLDER",
    sceneInsets  = { top = 2, right = 2, bottom = 2, left = 2 },
}
LC.widgets["petDetailPanel.family"] = {
    tooltip = false,
    kind = "label", ["in"] = "pets.detailCard", font = "small",
    text = "", height = 14, order = 10,
    binding = "pets.selectedPet.familyLabel",
}
-- Summon / Dismiss. ONE button whose label flips, matching VPP: two buttons would
-- mean one is always dead, and the state is binary. `enabled` is bound because the
-- client refuses a summon in a pet battle, on a vehicle or in a restricted area --
-- and the button widget fades a disabled control, so it reads at a glance.
LC.widgets["petDetailPanel.summonBtn"] = {
    tooltip = false,
    kind = "button", ["in"] = "pets.detailCard", font = "small",
    text = "locale:PETS_SUMMON", width = "auto", height = 22, order = 30, variant = "tertiary",
    binding = { text = "pets.summonLabel", enabled = "pets.summonEnabled" },
    visible = "pets.hasSelection",
}

LC.widgets["petDetailPanel.size"] = {
    tooltip = false,
    kind = "label", ["in"] = "pets.detailCard", font = "small",
    text = "", height = 14, order = 20,
    binding = "pets.selectedPet.sizeLabel",
}
