-- HDGR_HouseTab_WidgetDefaults.lua
-- ============================================================================
-- Default per-widget configuration for the HouseTab dashboard. Ordering +
-- width + initial enabled state. Players override via the in-game picker
-- (HOUSETAB_SET_ORDER / SET_WIDTH / TOGGLE_WIDGET); account.ui.houseTab.*
-- slots hold the overrides. Selector `house.widgetList` composes defaults
-- + overrides into the final render list.
--
-- Mirrors HDG's HDG_HT_LayoutConfig ordering.
-- Widths: "third" (1/3 col) / "twoThirds" (2/3 cols) / "fill" (all cols).

HDGR_HouseTab_WidgetDefaults = {
    -- Phase A widgets (foundation: no async; bind directly to snapshot fields).
    { id = "decoratorProfile",  title = "Decorator Profile", order = 1,  width = "fill",      enabled = true,  defaultHeight = 180 },
    { id = "styleAffinity",     title = "Your Style",         order = 2,  width = "fill",      enabled = true,  defaultHeight = 60  },
    { id = "sourceDonut",       title = "By Source",          order = 3,  width = "third",     enabled = true,  defaultHeight = 160 },
    { id = "expansionDonut",    title = "By Expansion",       order = 4,  width = "third",     enabled = true,  defaultHeight = 176 },
    { id = "hotPicks",          title = "Hot Picks",          order = 5,  width = "third",     enabled = true,  defaultHeight = 160 },
    { id = "lumberWallet",      title = "Lumber Stock",       order = 6,  width = "third",     enabled = true,  defaultHeight = 120 },
    { id = "decorCurrency",     title = "Decor Currencies",   order = 7,  width = "twoThirds", enabled = true,  defaultHeight = 120 },
    { id = "multiHouse",        title = "My Homes",           order = 8,  width = "third",     enabled = true,  defaultHeight = 140 },
    { id = "recentActivity",    title = "Recent Activity",    order = 9,  width = "third",     enabled = true,  defaultHeight = 140 },
    { id = "capacity",          title = "Decor Capacity",     order = 10, width = "third",     enabled = true,  defaultHeight = 100 },
    { id = "velocity",          title = "Collection Velocity", order = 11, width = "third",     enabled = true,  defaultHeight = 100 },
    { id = "closeCards",        title = "Closest to Complete", order = 12, width = "fill",      enabled = true,  defaultHeight = 130 },

    -- Phase B widgets.
    { id = "ritualSites",       title = "Ritual Sites",       order = 13, width = "third",     enabled = true,  defaultHeight = 140 },
    { id = "abyssAnglers",      title = "Abyss Anglers",      order = 14, width = "third",     enabled = true,  defaultHeight = 140 },
    { id = "decorDuels",        title = "Decor Duels",        order = 15, width = "third",     enabled = true,  defaultHeight = 140 },
    { id = "featured",          title = "Featured of the Week", order = 16, width = "fill",      enabled = true,  defaultHeight = 130 },
    { id = "nextRewards",       title = "Current Level Rewards", order = 17, width = "third",     enabled = true,  defaultHeight = 140 },
    { id = "craftableNow",      title = "Craftable Now",      order = 18, width = "third",     enabled = true,  defaultHeight = 100 },
    { id = "goblinTopLumber",   title = "Top $/Lumber",       order = 19, width = "third",     enabled = true,  defaultHeight = 160 },
    { id = "topVendors",        title = "Top Vendors",        order = 20, width = "third",     enabled = true,  defaultHeight = 160 },
    { id = "favorites",         title = "Favorites",          order = 21, width = "third",     enabled = true,  defaultHeight = 160 },

    -- Phase C/D + tail widgets (off by default; reveal via picker).
    { id = "records",           title = "Personal Records",   order = 22, width = "third",     enabled = false, defaultHeight = 140 },
    { id = "themedSets",        title = "Themed Sets",        order = 23, width = "fill",      enabled = true,  defaultHeight = 130 },
}
