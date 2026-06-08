-- HDG.ZoneNameResolver
-- ============================================================================
-- Maps English zone names (as stored in HDGR_TrainersDB) to the client
-- locale via C_Map.GetMapInfo. Trainers tab uses this for non-enUS clients.
-- Silvermoon: mapID 2393 (retail Midnight Silvermoon; avoids the old 110/2393
-- ambiguity where HDG's behavior depended on dict iteration order).
-- Selectors declare calls = {"ZoneNameResolver:Localize"}.

HDG = HDG or {}
HDG.ZoneNameResolver = HDG.ZoneNameResolver or {}
local R = HDG.ZoneNameResolver

-- Log tag for C_Map.GetMapInfo boundary failures (invalid mapID etc).
HDG.Log:RegisterTags({ map_api = { user = false, level = "warn" } })

R._cache = R._cache or {}   -- [enUSName] = localizedName

R.ZONE_MAP_IDS = {
    -- Classic capitals
    ["Stormwind City"]              = 84,
    ["Orgrimmar"]                   = 85,
    ["Ironforge"]                   = 87,
    ["Thunder Bluff"]               = 88,
    ["Darnassus"]                   = 89,
    ["Undercity"]                   = 90,
    ["Silvermoon City"]             = 2393,  -- 12.0 Midnight (was dual 110/2393)
    ["The Exodar"]                  = 103,
    -- Classic / Cataclysm zones used as trainer locations
    ["Elwynn Forest"]               = 37,
    -- TBC
    ["Hellfire Peninsula"]          = 100,
    ["Shattrath City"]              = 111,
    -- Wrath
    ["Dalaran (Northrend)"]         = 125,
    -- MoP
    ["Jade Forest"]                 = 371,
    ["Valley of the Four Winds"]    = 376,
    ["Kun-Lai Summit"]              = 379,
    -- WoD
    ["Stormshield"]                 = 622,
    ["Warspear"]                    = 624,
    -- Legion
    ["Dalaran (Broken Isles)"]      = 627,
    -- BfA
    ["Boralus"]                     = 1161,
    ["Dazar'alor"]                  = 1165,
    -- Shadowlands
    ["Oribos"]                      = 1670,
    -- Dragonflight
    ["Valdrakken"]                  = 2112,
    -- The War Within
    ["Dornogal"]                    = 2339,
}

-- Localize enUS zone name. Falls back to enUS when mapID unknown or GetMapInfo nil.
function R:Localize(enUSName)
    if not enUSName then return "" end
    local cached = self._cache[enUSName]
    if cached then return cached end

    local mapID = self.ZONE_MAP_IDS[enUSName]
    if not mapID then
        self._cache[enUSName] = enUSName  -- cache passthrough to avoid repeated lookups
        return enUSName
    end

    local info = C_Map.GetMapInfo(mapID)
    if info and info.name and info.name ~= "" then
        self._cache[enUSName] = info.name
        return info.name
    end

    return enUSName
end

HDG.Modules:Declare({
    name = "ZoneNameResolver",
    dependencies = {},
    -- per ADR-011: sole owner of C_Map.GetMapInfo (trainers-tab localization).
    -- C_Map partitioned at sub-API; see ZoneObserver / LumberObserver for the rest.
    ownsBlizzardNamespaces = { "C_Map.GetMapInfo" },
})
