-- HDG locale table -- enUS (reference locale)
-- ============================================================================
-- The complete set of user-facing strings HDG ships with. Other locales
-- (deDE, frFR, ...) override keys from this table; missing keys fall back
-- to enUS automatically (HDG.Locale:Get).
--
-- Key naming: SCREAMING_SNAKE_CASE. Group by namespace prefix matching the
-- consuming widget cluster (DECOR_*, ACQ_*, STATUS_*, DEBUG_*).

HDG = HDG or {}
if not HDG.Locale then return end

HDG.Locale:Register("enUS", {
    -- ===== Chrome / tabs =====
    TAB_DECOR              = "Decor",
    TAB_ACQUISITION        = "Acquire",
    TAB_DEBUG              = "Debug",

    -- ===== Decor browser =====
    DECOR_BROWSER_TITLE    = "Decor Browser",
    DECOR_SELECTED_ITEM    = "Selected Item",
    DECOR_CLICK_AN_ITEM    = "Click an item",
    DECOR_PROFESSION_LABEL = "Profession:",
    DECOR_EXPANSION_LABEL  = "Expansion:",
    DECOR_ITEM_ID_LABEL    = "itemID:",
    DECOR_SEARCH_PLACEHOLDER = "Search decor by name...",

    -- ===== Acquisition =====
    ACQ_VENDORS_TITLE      = "Vendors",
    ACQ_ITEMS_TITLE        = "Items",
    ACQ_SELECTED_VENDOR    = "Selected Vendor",
    ACQ_SELECTED_ITEM      = "Selected Item",
    ACQ_CLICK_VENDOR       = "Click a vendor",
    ACQ_CLICK_ITEM         = "Click an item",
    ACQ_SEARCH_PLACEHOLDER = "Search vendors by name or zone...",
    ACQ_ALL_FACTIONS       = "All factions",
    ACQ_ALL_EXPANSIONS     = "All Expansions",
    ACQ_ALL_ZONES          = "All Zones",
    ACQ_ALL_REPS           = "All Reps",
    ACQ_FACTION_LABEL      = "Faction:",
    ACQ_ITEMS_LABEL        = "Items:",
    ACQ_ITEMS_NONE         = "Items: none",
    ACQ_VIEW_VENDORS       = "Shop by Vendor",
    ACQ_VIEW_ITEMS         = "Find by Item",
    ACQ_ADVANCED_OPEN      = "- Advanced Filters",
    ACQ_ADVANCED_CLOSED    = "+ Advanced Filters",
    ACQ_ACTIVE_FILTERS     = "Active filters:",
    ACQ_NO_ACTIVE_FILTERS  = "No active filters",
    ACQ_RESET_FILTERS      = "Reset",
    ACQ_PREVIEW_PLACEHOLDER = "Click an item to preview",

    -- ===== Debug tab =====
    DEBUG_TITLE            = "Debug Log",
    DEBUG_TAG_ALL          = "All tags",
    DEBUG_LEVEL_ALL        = "All levels",
    DEBUG_CLEAR            = "Clear",
    DEBUG_COPY             = "Copy",
    DEBUG_COPIED           = "Selected -- press Ctrl+C to copy",
    DEBUG_AUTOSCROLL       = "Auto-scroll",

    -- ===== Status rail / general =====
    STATUS_READY           = "Ready",

    -- ===== Errors =====
    ERROR_GENERIC          = "An error occurred",
})
