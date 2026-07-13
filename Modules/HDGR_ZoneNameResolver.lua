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
    -- Midnight (12.0.7 vendor zones). Naigtal + Val are the weekly-rotating
    -- housing zones; the catalog lists BOTH statically on a rotating vendor's
    -- items (e.g. Zuronar), so both must resolve to draw the zone map.
    ["Naigtal"]                     = 2600,  -- verified in-game 2026-07-12; NOT 2623 (System=2 variant) or 924 (Legion "Invasion Point: Naigtal")
    ["Val"]                         = 2599,  -- verified 2026-07-13 (Zuronar's other rotation; catalog zone string "Val")
}

-- Zone NAME -> uiMapID. Curated table first (disambiguates duals like
-- Silvermoon), else a lazy one-time C_Map scan index. Catalog zone strings and
-- GetMapInfo names are both client-locale, so the index matches on any locale
-- (unlike the enUS-keyed curated table). First-wins on duplicate names, so
-- old-world maps shadow same-named newer ones -- add a curated entry when a
-- specific dual matters. Used for un-augmented vendors (e.g. 12.0.7 additions):
-- the catalog gives only a zone STRING, this recovers a map to draw.
local SCAN_MAX_UIMAP = 3500   -- 12.x uiMapIDs top out ~2800; headroom for new patches

function R:MapIDForName(zoneName)
    if not zoneName or zoneName == "" then return nil end  -- exception(nullable): vendors can lack a zone string
    local curated = self.ZONE_MAP_IDS[zoneName]
    if curated then return curated end
    if not self._nameIndex then
        local ZONE = Enum.UIMapType and Enum.UIMapType.Zone or 3  -- exception(boundary): headless mock lacks Enum.UIMapType
        local idx, types = {}, {}
        for id = 1, SCAN_MAX_UIMAP do
            local info = C_Map.GetMapInfo(id)  -- exception(boundary): uiMapIDs are sparse; gaps return nil
            if info and info.name and info.name ~= "" then
                -- A real ZONE map always beats a same-named continent/dungeon/
                -- orphan map (duplicate names are common; the lowest ID is often
                -- an old or non-zone variant). Within a type, first-wins.
                local have = idx[info.name]
                if not have or (types[info.name] ~= ZONE and info.mapType == ZONE) then
                    idx[info.name], types[info.name] = id, info.mapType
                end
            end
        end
        self._nameIndex = idx
    end
    return self._nameIndex[zoneName]  -- exception(nullable): sub-zone strings have no uiMap
end

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
