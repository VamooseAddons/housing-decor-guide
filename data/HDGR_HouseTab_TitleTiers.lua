-- HDGR_HouseTab_TitleTiers.lua
-- ============================================================================
-- Decorator title ladder for the HouseTab DecoratorProfile widget. Tier is
-- assigned by `snap.collectedAll` count (decor items owned). `vamoose=true`
-- entries are the high-tier Vamoose-flagged titles that surface a small
-- crown atlas in the profile chrome.
--
-- Verbatim port of HDG's TITLE_TIERS (HousingDecorGuide/UI/HouseTab/
-- HDG_HT_Aggregator.lua lines 547-557). Exposed via
-- HDG.StaticData.TitleTiers:GetAll(); consumed by the `house.titleTier`
-- selector to compute { current, prev, next } for the in-tier progress bar.

HDGR_HouseTab_TitleTiers = {
    { threshold = 0,    name = "Aspiring Decorator" },
    { threshold = 1,    name = "Score a Decor" },
    { threshold = 100,  name = "Casual Collector" },
    { threshold = 250,  name = "Well-Travelled Collection" },
    { threshold = 500,  name = "Fully Furnished" },
    { threshold = 750,  name = "Decor Maven",         vamoose = true },
    { threshold = 1000, name = "Decor Master",        vamoose = true },
    { threshold = 1500, name = "Grand Curator",       vamoose = true },
    { threshold = 2000, name = "Legendary Decorator", vamoose = true },
}
