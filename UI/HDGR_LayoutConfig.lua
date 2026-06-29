-- HDG.LayoutConfig
-- ============================================================================
-- Declarative spec for the entire UI tree. One file describes the SHARED
-- (cross-tab) shape; per-tab files in UI/LayoutConfig/ mutate this table
-- after it is assembled.
--
-- Tab system. Views share a chrome strip at the top with tab buttons.
-- Each tab's content lives in its own view's cells. Tab clicks dispatch
-- UI_SET_PERSISTENT view=<name>; PrepareContext resolves and Layout swaps
-- panels.
--
-- Per-tab files (loaded after this file in the TOC):
--   UI\LayoutConfig\HDGR_LayoutConfig_Decor.lua
--   UI\LayoutConfig\HDGR_LayoutConfig_Acquisition.lua
--   UI\LayoutConfig\HDGR_LayoutConfig_Recipes.lua
--   UI\LayoutConfig\HDGR_LayoutConfig_Alts.lua
--   UI\LayoutConfig\HDGR_LayoutConfig_Mogul.lua
--   UI\LayoutConfig\HDGR_LayoutConfig_Styles.lua
--   UI\LayoutConfig\HDGR_LayoutConfig_Trainers.lua
--   UI\LayoutConfig\HDGR_LayoutConfig_HouseTab.lua
--   UI\LayoutConfig\HDGR_LayoutConfig_Debug.lua
--   UI\LayoutConfig\HDGR_LayoutConfig_Config.lua
--
-- Cross-tab content that stays in this file:
--   chromePanel     -- tab-bar strip visible in every view
--   statusRailPanel -- bottom status bar visible in every view
--   chrome.body / chrome.spacer sections
--   status.body section
--   Chrome tab strip + close button (generated from HDG.Constants.TABS)

HDG = HDG or {}

-- CHROME_HEIGHT 32: MinimalTabTemplate native is 37px; 32 clips slightly
-- but reads compact. Bump to 38 for full-native chrome.
local CHROME_HEIGHT = 32
local STATUS_RAIL_HEIGHT = 22   -- Bottom-row status surface
local NAV_WIDTH = 150           -- sidebar width (spec section 5)

HDG.LayoutConfig = {
    -- Public re-exports of the chrome heights. Selectors that build
    -- dynamic row arrays (mogul.dynamicRows) read these so the view
    -- specs + the dynamic overrides share a single source of truth.
    -- All layout dimensions live in LayoutConfig.
    CHROME_HEIGHT      = CHROME_HEIGHT,
    STATUS_RAIL_HEIGHT = STATUS_RAIL_HEIGHT,
    NAV_WIDTH          = NAV_WIDTH,

    window = {
        padding = "sm",
        gap     = "sm",
        views = {
            -- Per-tab views are declared in UI/LayoutConfig/ files.
            -- "houseTab" view lives in HDGR_LayoutConfig_HouseTab.lua.
        },
        defaultView = "decor",
    },

    panels = {
        -- Chrome strip: title + close button. Window composition (HDG-ADR-025):
        -- this panel is the content of the `chrome` slot-view, placed by the
        -- `main` window's `top` slot -- NOT a per-view cell. One slot entry on
        -- the window covers every view; new views need no chrome wiring.
        chromePanel = {
            kind = "panel",
            -- Title FRAME band: surface.panel_header + 1px border.subtle hairline
            -- (PanelHeaderMain skinner -- no foliage; the wordmark + close button
            -- occupy the ends. Per-view header bars use PanelHeader = +foliage.)
            skin = "PanelHeaderMain",
            cell = { chrome = "body" },
            visibleInViews = { "chrome" },
        },

        -- Status rail: bottom-of-window log surface. Content of the `status`
        -- slot-view, placed by the `main` window's `bottom` slot.
        statusRailPanel = {
            kind = "panel",
            -- Status FRAME band: surface.statusline + 1px border.subtle hairline
            -- (StatusRail skinner). Full-bleed window bottom frame.
            skin = "StatusRail",
            cell = { status = "body" },
            visibleInViews = { "status" },
        },

        -- Per-tab panels live in UI/LayoutConfig/ files:
        --   decorFilterPanel, decorPanel, decorDetailPanel  -> HDGR_LayoutConfig_Decor.lua
        --   acquisitionListPanel, acquisitionDetailPanel    -> HDGR_LayoutConfig_Acquisition.lua
        --   recipesProfPanel, recipesListPanel, ...         -> HDGR_LayoutConfig_Recipes.lua
        --   altsPanel                                       -> HDGR_LayoutConfig_Alts.lua
        --   mogulPanel                                      -> HDGR_LayoutConfig_Mogul.lua
        --   stylesPanel                                     -> HDGR_LayoutConfig_Styles.lua
        --   trainersPanel                                   -> HDGR_LayoutConfig_Trainers.lua
        --   houseTabPanel, houseTabPickerPanel              -> HDGR_LayoutConfig_HouseTab.lua
        --   debugPanel                                      -> HDGR_LayoutConfig_Debug.lua
        --   configPanel                                     -> HDGR_LayoutConfig_Config.lua
    },

    sections = {
        -- ===== Chrome strip body =====
        ["chrome.body"] = {
            ["in"] = "chromePanel",
            layout = "horizontal",
            padding = "sm",
            gap = "sm",
            order = 10,
        },
        -- Spacer absorbs the slack between left-anchored tabs (order 1..N)
        -- and the right-anchored close button (order 100). Implemented as
        -- width=fill slack absorber so the close button stays right-anchored.
        -- Always present (no compact mode; Shopping/Zone are separate windows).
        ["chrome.spacer"] = {
            ["in"]   = "chrome.body",
            layout   = "horizontal",
            width    = "fill",
            height   = 22,
            order    = 50,
        },

        -- ===== Status rail body =====
        -- Overlay (fill): all children get the full rect. statusRail auto-hides
        -- when idle; status.persistent is always visible underneath.
        ["status.body"] = {
            ["in"] = "statusRailPanel",
            layout = "fill",
            order = 10,
        },
        -- Persistent house-info bar (right-aligned). The quote is a SEPARATE
        -- full-rail overlay (status.quoteLabel, below) so it centres dead-centre
        -- independent of this label's width. align=right pins house-info to the
        -- right edge; top/bottom padding stays 0 so it sits inside the 22px slot
        -- (exception(boundary)); right=6 keeps it off the window border.
        ["status.persistent"] = {
            ["in"]    = "status.body",
            layout    = "horizontal",
            align     = "right",
            padding   = { top = 0, bottom = 0, left = 0, right = 6 },
            gap       = 4,
            order     = 1,
        },

        -- Per-tab sections live in UI/LayoutConfig/ files.
    },

    widgets = {
        -- ===== Status rail widget =====
        -- Bound to status.current (most-recent user-visible log entry; nil = idle).
        ["statusRailPanel.rail"] = {
            tooltip = false,
            kind = "statusRail",
            ["in"] = "status.body",
            order   = 10,  -- overlay over the persistent bar (order 1)
            binding = { entry = "status.current" },
        },

        -- Quote label: a full-rail OVERLAY (sibling of the persistent bar + the log
        -- rail in the fill section status.body), so width=fill gives it the whole rail
        -- and justifyH=CENTER lands it dead-centre -- independent of the house-info
        -- label's width. Being centred also clears the left-aligned log overlay, so the
        -- two no longer collide ("doubling"). order 5: above the persistent bar (1),
        -- below the transient log rail (10).
        ["status.quoteLabel"] = {
            tooltip  = false,
            kind     = "label",
            ["in"]   = "status.body",
            font     = "small",
            justifyH = "CENTER",
            width    = "fill",
            height   = 14,
            order    = 5,
            binding  = { text = "status.quoteText" },
        },
        -- House info label: right side, sized to its intrinsic text width (width="auto"
        -- -- WITHOUT it the label has no declared size and the stack treats it as flex,
        -- eating half the rail). justifyH=RIGHT pins text to the right of its slot.
        ["status.houseInfoLabel"] = {
            tooltip  = false,
            kind     = "label",
            ["in"]   = "status.persistent",
            font     = "small",
            justifyH = "RIGHT",
            width    = "auto",
            height   = 14,
            order    = 2,
            binding  = { text = "status.houseInfo" },
        },

        -- Per-tab widgets live in UI/LayoutConfig/ files.
    },
}

-- ============================================================================
-- Windows (HDG-ADR-025: window composition)
-- ============================================================================
-- A flat table. Each window owns placement via a `slots` map over
-- placement-agnostic layout configs, and (later steps) carries `shown` +
-- `position`. layout.lua composes via Layout:ComposeWindow.
--
-- STEP 1: only `main`, with a single `fill` slot bound to "@view" (the active
-- view, account.ui.view). Chrome slots (top/left/bottom/corner) + the
-- satellite windows (lumber/shopping/zone) land in later steps. This step is
-- additive -- the live render path is unchanged until step 2 migrates onto it.
-- Chrome slot-views. per ADR-025. width is a placeholder; ComposeWindow spans
-- it to window width for top/bottom slots. Only height matters.
HDG.LayoutConfig.window.views.chrome = {
    standalone = true,
    width   = 420,                  -- placeholder; ComposeWindow spans to window width at runtime.
                                    -- Sized past the logo(246)+version+gap+close(22) fixed widths so
                                    -- the static over-spec check passes (only height matters live).
    height  = CHROME_HEIGHT,
    padding = 0,                    -- title bar fills the slot flush (same fix as status: window "sm" pad pushed it 4px low + overflowed the slot)
    columns = { "fill" },
    rows    = { CHROME_HEIGHT },
    cells   = { body = { col = 1, row = 1, colSpan = 1, rowSpan = 1 } },
}
HDG.LayoutConfig.window.views.status = {
    standalone = true,
    width   = 100,                  -- placeholder; ComposeWindow spans to window width
    height  = STATUS_RAIL_HEIGHT,
    padding = 0,                    -- rail fills the slot flush (window "sm" pad would push it 4px low + overflow)
    columns = { "fill" },
    rows    = { STATUS_RAIL_HEIGHT },
    cells   = { body = { col = 1, row = 1, colSpan = 1, rowSpan = 1 } },
}

-- ============================================================================
-- Catalog initial-load overlay (HDGR_Layout "introOverlay" slot, main window)
-- ============================================================================
-- A window-wide overlay shown ONLY during the first catalog load this session.
-- It spans the content rect (not the nav) and its panel hides via
-- `visible = catalog.intro.isVisible`, so it sits invisible until the first load.
-- Centered headline + animated blip dots + a Refresh button (loading phase only).
HDG.LayoutConfig.window.views.catalogIntro = {
    standalone = true,
    width   = 400, height = 400,   -- placeholders; the overlay spans to the content rect at runtime
    padding = 0,
    columns = { "fill" },
    rows    = { "fill" },
    cells   = { body = { col = 1, row = 1, colSpan = 1, rowSpan = 1 } },
}
HDG.LayoutConfig.panels.catalogIntroPanel = {
    kind = "panel",
    skin = "Frame",                       -- opaque stone surface: covers the tab content beneath
    cell = { catalogIntro = "body" },
    visibleInViews = { "catalogIntro" },
    visible = "catalog.intro.isVisible",
}
-- Vertical centering: fill spacers bracket the center group.
HDG.LayoutConfig.sections["catalogIntro.body"] = {
    ["in"] = "catalogIntroPanel", layout = "vertical", order = 10,
}
HDG.LayoutConfig.sections["catalogIntro.spacerTop"] = {
    ["in"] = "catalogIntro.body", layout = "vertical", height = "fill", order = 10,
}
HDG.LayoutConfig.sections["catalogIntro.center"] = {
    ["in"] = "catalogIntro.body", layout = "vertical", gap = "lg", order = 20,
}
HDG.LayoutConfig.sections["catalogIntro.dotsRow"] = {
    ["in"] = "catalogIntro.center", layout = "horizontal", height = 16, gap = "sm", order = 20,
}
HDG.LayoutConfig.sections["catalogIntro.refreshRow"] = {
    ["in"] = "catalogIntro.center", layout = "horizontal", height = 24, order = 30,
    visible = "catalog.intro.isLoading",   -- hide during the success flash
}
HDG.LayoutConfig.sections["catalogIntro.spacerBottom"] = {
    ["in"] = "catalogIntro.body", layout = "vertical", height = "fill", order = 30,
}
-- Headline (large, centered both axes).
HDG.LayoutConfig.widgets["catalogIntroPanel.headline"] = {
    tooltip = false,
    kind = "label", ["in"] = "catalogIntro.center",
    font = "heading", justifyH = "CENTER",
    width = "fill", height = 32, order = 10,
    binding = "catalog.intro.headline",
}
-- Animated blip dots (3), centered via fill spacers. Controller pulses their alpha.
HDG.LayoutConfig.widgets["catalogIntroPanel.dotsLeftSpacer"] = {
    tooltip = false, kind = "spacer", ["in"] = "catalogIntro.dotsRow", width = "fill", height = 14, order = 5,
}
HDG.LayoutConfig.widgets["catalogIntroPanel.dot1"] = {
    tooltip = false, kind = "atlas", ["in"] = "catalogIntro.dotsRow",
    atlas = "PlayerPartyBlip", tone = "semantic.accent", width = 12, height = 12, order = 10,
}
HDG.LayoutConfig.widgets["catalogIntroPanel.dot2"] = {
    tooltip = false, kind = "atlas", ["in"] = "catalogIntro.dotsRow",
    atlas = "PlayerPartyBlip", tone = "semantic.accent", width = 12, height = 12, order = 12,
}
HDG.LayoutConfig.widgets["catalogIntroPanel.dot3"] = {
    tooltip = false, kind = "atlas", ["in"] = "catalogIntro.dotsRow",
    atlas = "PlayerPartyBlip", tone = "semantic.accent", width = 12, height = 12, order = 14,
}
HDG.LayoutConfig.widgets["catalogIntroPanel.dotsRightSpacer"] = {
    tooltip = false, kind = "spacer", ["in"] = "catalogIntro.dotsRow", width = "fill", height = 14, order = 20,
}
-- Refresh button (centered; loading phase only, row hides during success).
HDG.LayoutConfig.widgets["catalogIntroPanel.refreshLeftSpacer"] = {
    tooltip = false, kind = "spacer", ["in"] = "catalogIntro.refreshRow", width = "fill", height = 22, order = 5,
}
HDG.LayoutConfig.widgets["catalogIntroPanel.refresh"] = {
    tooltip = false, kind = "button", ["in"] = "catalogIntro.refreshRow", font = "small",
    text = "locale:CATALOG_INTRO_REFRESH", width = "auto", height = 22, order = 10, variant = "tertiary",
}
HDG.LayoutConfig.widgets["catalogIntroPanel.refreshRightSpacer"] = {
    tooltip = false, kind = "spacer", ["in"] = "catalogIntro.refreshRow", width = "fill", height = 22, order = 20,
}

HDG.LayoutConfig.windows = {
    main = {
        -- top/bottom = chrome + status rail. left = sidebar nav. fill = active view.
        -- Close button lives inside chrome strip; no corner slot needed.
        slots = { top = "chrome", bottom = "status", left = "nav", fill = "@view" },
    },
}

-- ============================================================================
-- Chrome strip widgets
-- ============================================================================
-- Window title: the brand logo (textures/title_logo.tga, art by boggle). Main-window
-- only; standalone windows carry their own headers. Source 1520x148 -- the logo is
-- trimmed then given 12px of transparent TOP padding (gravity north) so it sits a
-- touch lower in the 32px strip; width tracks the aspect (1520/148) so it isn't squished.
-- Left buffer: a small spacer before the wordmark so it clears the Housing
-- theme's wood-frame corner (the frame overlay draws inside the panel edge).
-- 2px = the 'xs' spacing step; harmless (and barely visible) on non-atlas themes.
HDG.LayoutConfig.widgets["chromePanel.titleBuffer"] = {
    tooltip = false,
    kind    = "spacer", ["in"] = "chrome.body",
    width   = 2, height = 1, order = 0,
}
HDG.LayoutConfig.widgets["chromePanel.title"] = {
    tooltip  = false,
    kind     = "atlas", ["in"] = "chrome.body",
    texture  = "Interface/AddOns/HousingDecorGuide/textures/title_logo",
    width    = 246, height = 24, order = 1,
}

-- Version: right-aligned, just left of the close button (chrome.spacer pushes both right).
-- exception(boundary): C_AddOns.GetAddOnMetadata guarded for headless / pre-load.
local _hdgrVersion = (C_AddOns and C_AddOns.GetAddOnMetadata
    and C_AddOns.GetAddOnMetadata("HousingDecorGuide", "Version")) or nil
HDG.LayoutConfig.widgets["chromePanel.version"] = {
    tooltip  = false,
    kind     = "label", role = "TextDim", ["in"] = "chrome.body",
    font     = "caption", justifyH = "RIGHT",
    text     = _hdgrVersion and ("v" .. _hdgrVersion) or "",
    height   = 14, order = 90,
}

-- Lumber Tracker toggle: the Find Lumber glyph, just left of the close button.
-- Click opens/closes the floating Lumber Tracker. LUMBER_WINDOW_TOGGLE auto-flips
-- when dispatched without `visible`; ChromeController wires the OnClick.
HDG.LayoutConfig.widgets["chromePanel.lumberToggle"] = {
    tooltip = { recipe = "LumberToggle" },
    kind = "button", ["in"] = "chrome.body",
    normalAtlas = "Lumber_Tracking", highlightAtlas = "Lumber_Tracking",
    width = 20, height = 20, size = 20, order = 95,
}

-- Shopping List toggle: the cart glyph (same atlas the Shopping window title uses),
-- next to the lumber toggle. Click opens/closes the floating Shopping List window;
-- SHOPPING_WIDGET_TOGGLE auto-flips. ChromeController wires the OnClick.
HDG.LayoutConfig.widgets["chromePanel.shoppingToggle"] = {
    tooltip = { recipe = "ShoppingToggle" },
    kind = "button", ["in"] = "chrome.body",
    normalAtlas = HDG.Constants.SHOPPING_LIST_ICON_ATLAS,
    highlightAtlas = HDG.Constants.SHOPPING_LIST_ICON_ATLAS,
    width = 20, height = 20, size = 20, order = 96,
}

-- Close button: right-anchored via chrome.spacer slack absorber. Dispatches
-- MAIN_WINDOW_TOGGLE so the window can be reopened from the slash command.
HDG.LayoutConfig.widgets["chromePanel.close"] = {
    tooltip = { recipe = "Close" },
    kind = "button", ["in"] = "chrome.body",
    -- Raised: lifts the close control off the title band; overrides Button skin's bg-skip.
    skin = "Raised",
    width = 22, height = 22, order = 100,
    close = true,
    size = 22,
    iconSize = 14,
}
