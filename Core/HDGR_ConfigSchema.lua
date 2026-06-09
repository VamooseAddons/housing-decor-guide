-- HDG.ConfigSchema
-- ============================================================================
-- Declarative settings table. Single source of truth for every config field
-- HDG persists. Pattern from Baganator (Core/Config.lua's `local settings`):
-- each entry is { key, default, scope }; compile-time loops produce lookup
-- maps (ByOption / ByKey / Defaults / ScopeBy).
--
-- Pure-value defaults only. No functions, no closures, no factory references.
-- Inspectable at runtime via /dump HDG.ConfigSchema.Defaults.
--
-- Scope decisions per HDGR_CONFIG_DESIGN.md Resolved Question #2:
--   * Everything decor-related (incl. THEME + DECOR_PREVIEW_BG) is
--     Profile-scoped: shared across every character on the DEFAULT profile,
--     per-character only when the user creates a separate profile. (Theme +
--     preview-bg were briefly Character-scoped, which reset them on every alt;
--     the resolved design is account-wide-by-default, opt-in per-char via profile.)
--   * MIGRATED_* one-time flags are Account-scoped (cross-profile, persist
--     across profile switches/deletions)
--
-- Adding a setting: one table entry. The compile loop wires it into all
-- lookup maps. No other file changes required for the setting itself
-- (consumers obviously still need to call Config:Get(NEW_NAME) to use it).

HDG = HDG or {}

local Scope = HDG.Constants.ConfigScope

-- Source-of-truth table. Entries follow { key, default, scope } shape.
-- Migration flags (MIGRATED_*) live at the bottom so future devs can see
-- which one-time migrations have been performed at a glance.
local schema = {
    -- ===== Appearance ======================================================
    THEME              = { key = "scheme",            default = HDG.Constants.DEFAULT_SCHEME, scope = Scope.Profile },
    -- Decor browser 3D-preview background. "default" = the dark bgTile backdrop (no atlas
    -- override); other values are housing background atlas names applied over it.
    DECOR_PREVIEW_BG   = { key = "decorPreviewBg",    default = "default",  scope = Scope.Profile },
    SCALE              = { key = "scale",             default = 1.0,        scope = Scope.Profile },
    FONT               = { key = "fontFamily",        default = "default",  scope = Scope.Profile },

    -- ===== Locale ==========================================================
    -- Sentinel "" means "use GetLocale() at first read". A player picking a
    -- locale from the Config dropdown stamps a real string here.
    LOCALE             = { key = "locale",            default = "",         scope = Scope.Profile },

    -- ===== Debug ===========================================================
    DEBUG              = { key = "debug",             default = false,      scope = Scope.Profile },
    MOCK_TSM           = { key = "mockTSM",           default = false,      scope = Scope.Profile },
    -- NOTE: perf instrumentation (HDG.Perf) is gated by HDG_DB.perf (raw account SV, not a config
    -- field) -- must be readable before Config hydrates + independent of profile. Toggle: /hdgr perf on|off.

    -- ===== Minimap / AddonCompartment / Interface ==========================
    SHOW_MINIMAP_BUTTON  = { key = "showMinimapButton", default = true,  scope = Scope.Profile },
    SHOW_COMPARTMENT     = { key = "showCompartment",   default = true,  scope = Scope.Profile },
    SHOW_PROFESSION_BUTTONS = { key = "showProfessionButtons", default = true, scope = Scope.Profile },
    TOOLTIP_DECOR_TAG    = { key = "tooltipDecorTag",   default = true,  scope = Scope.Profile },
    -- Auto-hide all HDG windows on entering combat; restored on combat end.
    HIDE_IN_COMBAT       = { key = "hideInCombat",      default = true,  scope = Scope.Profile },

    -- ===== Price source ====================================================
    -- preferredPriceAddon: nil = fallback chain (TSM > Auctionator > Direct > Vendor); string forces that source.
    PREFERRED_PRICE_ADDON = { key = "preferredPriceAddon", default = nil,    scope = Scope.Profile },
    TSM_PRICE_MODE        = { key = "tsmPriceMode",        default = "min",  scope = Scope.Profile },

    -- ===== Zone Scanner =====================================================
    ZONE_SCANNER_ENABLED = { key = "zoneScannerEnabled", default = true,  scope = Scope.Profile },
    ZONE_SCANNER_POPUP   = { key = "zoneScannerPopup",   default = false, scope = Scope.Profile },
    ZONE_SCANNER_POPUP_SHOPPING = { key = "zoneScannerPopupShopping", default = false, scope = Scope.Profile },
    ZONE_SCANNER_CHAT    = { key = "zoneScannerChat",    default = true,  scope = Scope.Profile },
    ZONE_SCANNER_SOUND   = { key = "zoneScannerSound",   default = false, scope = Scope.Profile },

    -- ===== Waypoint provider ===============================================
    WAYPOINT_PROVIDER  = { key = "waypointProvider",  default = "auto",  scope = Scope.Profile },

    -- ===== One-time migration flags ========================================
    -- Each migration sets its flag true after running so it doesn't repeat.
    -- See HDGR_Config:_runMigrations.
    MIGRATED_LEGACY_CONFIG_TO_PROFILE = { key = "migrated_legacyConfig", default = false, scope = Scope.Account },
}

HDG.ConfigSchema = {
    -- Raw schema table exposed for slash-command-style introspection.
    Raw       = schema,
    -- ENUM_NAME -> "sv_key" (option lookup at Config:Get / Config:Set sites)
    ByOption  = {},
    -- "sv_key" -> { default, scope, optionName } (used by the reducer)
    ByKey     = {},
    -- "sv_key" -> default value (used by ImportDefaultsToProfile)
    Defaults  = {},
    -- "sv_key" -> Scope constant (used by Config:_GetSourceForScope)
    ScopeBy   = {},
}

-- Compile lookup maps at file-load. Each entry contributes to 4 indexes.
for optionName, entry in pairs(schema) do
    if type(optionName) ~= "string" then
        error(("ConfigSchema: option name must be string, got %s"):format(type(optionName)), 2)
    end
    if type(entry) ~= "table" or type(entry.key) ~= "string" then
        error(("ConfigSchema entry %q: must be { key, default, scope }"):format(optionName), 2)
    end
    if entry.scope == nil then
        error(("ConfigSchema entry %q: missing scope field"):format(optionName), 2)
    end
    HDG.ConfigSchema.ByOption[optionName] = entry.key
    HDG.ConfigSchema.ByKey[entry.key]     = {
        default    = entry.default,
        scope      = entry.scope,
        optionName = optionName,
    }
    HDG.ConfigSchema.Defaults[entry.key]  = entry.default
    HDG.ConfigSchema.ScopeBy[entry.key]   = entry.scope
end
