-- HDG.Selectors -- Shopping list (multi-list per-account).
--
-- Selector graph:
--   shopping.activeList          -> active list record or nil
--   shopping.activeListId        -> primitive id ("" or "Lnnn")
--   shopping.activeListMenuItems -> dropdown menu items for the switcher
--   shopping.summary             -> { itemCount, vendorCount, wishCount, goldCost }
--   shopping.summaryText         -> display text for header
--   shopping.attribution         -> { source, url, desc, date, author } from list.meta
--   shopping.hasAttribution      -> bool (visibility gate for banner)
--   shopping.attributionText     -> display text for banner
--   shopping.activeListEntries   -> flat list enriched with vendor info
--   shopping.entriesByZone       -> tree-via-flat-projection for scrollbox
--
-- Vendor coords from VendorAugment:Get(npcID). All selectors strict-read.

HDG = HDG or {}
local Selectors = HDG.Selectors

-- Window visibility (account.ui.shoppingWidgetShown, flipped by SHOPPING_WIDGET_TOGGLE).
Selectors:Register("shopping.windowVisible", {
    reads = { "account.ui.shoppingWidgetShown" },
    fn = function(state)
        return state.account.ui.shoppingWidgetShown == true
    end,
})

-- Active list record or nil when no list active.
Selectors:Register("shopping.activeList", {
    reads = { "account.vendorShoppingLists", "account.activeShoppingListId" },
    fn = function(state)
        local id = state.account.activeShoppingListId
        if id == "" then return nil end
        return state.account.vendorShoppingLists[id]
    end,
})

-- Active list ID as bare primitive for dropdown binding.current.
Selectors:Register("shopping.activeListId", {
    reads = { "account.activeShoppingListId" },
    fn = function(state) return state.account.activeShoppingListId end,
})

-- True when the account has >1 shopping list -> gates the Delete-List button
-- (you can't delete your only list, which keeps activeShoppingListId non-empty
-- so "Add to Cart" never dead-ends).
Selectors:Register("shopping.hasMultipleLists", {
    reads = { "account.vendorShoppingLists" },
    fn = function(state)
        local n = 0
        for _ in pairs(state.account.vendorShoppingLists) do
            n = n + 1
            if n > 1 then return true end
        end
        return false
    end,
})

-- Menu items for the list-switcher dropdown. Alphabetical by name.
Selectors:Register("shopping.activeListMenuItems", {
    reads = { "account.vendorShoppingLists" },
    fn = function(state)
        local items = {}
        local sorted = {}
        for id, list in pairs(state.account.vendorShoppingLists) do
            sorted[#sorted + 1] = { id = id, name = list.name or "Unnamed" }
        end
        table.sort(sorted, function(a, b) return a.name < b.name end)
        for _, entry in ipairs(sorted) do
            items[#items + 1] = { text = entry.name, value = entry.id }
        end
        return items
    end,
})

-- Summary stats for the header. goldCost = 0 (cost integration deferred;
-- VendorDB lookup per item would couple this to the static data tick).
Selectors:Register("shopping.summary", {
    -- Counts from FILTERED entries (decor-only) so header tallies match shown rows.
    -- Raw list.items may carry non-decor stacks from pre-decor-filter imports.
    calls = { "shopping.activeListEntries" },
    fn = function(state, ctx)
        local entries = Selectors:Call("shopping.activeListEntries", state, ctx)
        local out = { itemCount = 0, vendorCount = 0, wishCount = 0, goldCost = 0 }
        local vendors = {}
        for _, entry in ipairs(entries) do
            local qty = entry.qty or 1   -- migration: legacy imports may omit qty
            out.itemCount = out.itemCount + qty
            if entry.npcID then
                vendors[entry.npcID] = true
            else
                out.wishCount = out.wishCount + qty
            end
        end
        for _ in pairs(vendors) do out.vendorCount = out.vendorCount + 1 end
        return out
    end,
})

-- Display text: "12 items - 3 vendors - 5 wish" or "0 items". Reads scheme for future color.
Selectors:Register("shopping.summaryText", {
    reads = { "account.config.scheme" },
    calls = { "shopping.summary" },
    fn = function(state, ctx)
        local s = Selectors:Call("shopping.summary", state, ctx)
        if s.itemCount == 0 then return "0 items" end
        local parts = { string.format("%d items", s.itemCount) }
        if s.vendorCount > 0 then
            parts[#parts + 1] = string.format("%d vendor%s",
                s.vendorCount, s.vendorCount == 1 and "" or "s")
        end
        if s.wishCount > 0 then
            parts[#parts + 1] = string.format("%d wish", s.wishCount)
        end
        return table.concat(parts, "  -  ")
    end,
})

-- Attribution metadata from list.meta: source, url, desc, date, author.
-- Five fields from the HDG-interop format. Open button needs url specifically.
Selectors:Register("shopping.attribution", {
    calls = { "shopping.activeList" },
    fn = function(state, ctx)
        local list = Selectors:Call("shopping.activeList", state, ctx)
        if not list or not list.meta then
            return { source = nil, url = nil, desc = nil, date = nil, author = nil }
        end
        return {
            source = list.meta.source,
            url    = list.meta.url,
            desc   = list.meta.desc,
            date   = list.meta.date,
            author = list.meta.author,
        }
    end,
})

-- "player" lists are author-created and don't show the attribution banner.
Selectors:Register("shopping.hasAttribution", {
    calls = { "shopping.attribution" },
    fn = function(state, ctx)
        local a = Selectors:Call("shopping.attribution", state, ctx)
        return a.source ~= nil and a.source ~= "" and a.source ~= "player"
    end,
})

-- URL gate: Open button hidden when no source URL (banner text still shows).
Selectors:Register("shopping.hasUrl", {
    calls = { "shopping.attribution" },
    fn = function(state, ctx)
        local a = Selectors:Call("shopping.attribution", state, ctx)
        return type(a.url) == "string" and a.url ~= ""
    end,
})

-- Banner text: "Imported from <Source>: <desc>  <date>".
Selectors:Register("shopping.attributionText", {
    calls = { "shopping.attribution" },
    fn = function(state, ctx)
        local a = Selectors:Call("shopping.attribution", state, ctx)
        if not a.source or a.source == "" or a.source == "player" then return "" end
        local sourceName = a.source:sub(1, 1):upper() .. a.source:sub(2)
        local label = "Imported from " .. sourceName
        if a.desc and a.desc ~= "" and a.desc:lower() ~= a.source:lower() then
            label = label .. ": " .. a.desc
        end
        local d = HDG.Format.FriendlyDate(a.date)
        if d then label = label .. "  " .. d end
        return label
    end,
})

-- Per-item enrichment with vendor name/zone/mapID/coords.
-- Wishlist entries (npcID nil) carry vendor = nil.
-- Icon resolved via ItemNameResolver:ResolveIcon (boundary); nil on cache miss
-- queues warm-up; session.itemNames.tick bump re-fires this selector.
local function resolveIconID(itemID)
    return HDG.ItemNameResolver:ResolveIcon(itemID)
end

-- (gateFlagsForItem retired: replaced by HousingCatalogObserver._bakeSourceFlags.
--  Chip rendering reads row.sourceFlags via UI.GateChips(itemID).)

-- Catalog decor guard (ADR-003a: byItemID is module-internal, not a Blizzard API call).
-- sweepGeneration == 0 (cold): pass all through to avoid discarding decor pre-load.
local function _isCatalogDecor(itemID, sweepGeneration)
    if sweepGeneration == 0 then return true end  -- cold: pass through until sweep
    return HDG.HousingCatalogObserver.byItemID[itemID] ~= nil
end

-- Display-time vendor resolution for wishlist items (no stored npcID): the live
-- catalog's first vendor + VendorAugment, mirroring FindFirstVendorForItem. Never
-- written to state -- this is a render hint so vendor-buyable wishlist items can
-- show "where to buy" without freezing a (possibly wrong / multi-vendor) npcID.
-- Returns a coords-bearing table, a name/zone-only table, or nil (drop/quest/ach
-- items with no vendor).
local function _resolveWishlistVendor(itemID)
    local crow = HDG.HousingCatalogObserver:GetRow(itemID)
    local cv = crow and crow.vendors and crow.vendors[1]
    if not cv then return nil end
    local npc = HDG.StaticData.VendorAugment:ResolveName(cv.name, cv.zone)
    local aug = npc and HDG.StaticData.VendorAugment:Get(npc)
    if aug and aug.mapID and aug.mapID > 0 then
        -- Coords resolved: mapID present == waypointable (consumers key on it).
        return { npcID = npc, name = aug.name, zone = aug.zone,
                 mapID = aug.mapID, x = aug.x, y = aug.y }
    end
    -- Augment missing / coordless: catalog name+zone only (no mapID -> no waypoint).
    local name = (aug and aug.name) or cv.name
    if name and name ~= "" then return { name = name, zone = (aug and aug.zone) or cv.zone } end
    return nil
end

Selectors:Register("shopping.activeListEntries", {
    reads = { "session.itemNames.tick", "session.catalog.sweepGeneration" },
    calls = { "shopping.activeList" },
    fn = function(state, ctx)
        local list = Selectors:Call("shopping.activeList", state, ctx)
        if not list then return {} end
        local sweep = state.session.catalog.sweepGeneration
        local out = {}
        for _, entry in ipairs(list.items) do
            -- Drop non-housing items (reagents, crafting mats) that may have
            -- been imported via Wowdb or pushed from the Recipes materials panel.
            -- The shopping list is decor-only; non-catalog itemIDs are silent noise.
            -- Cold-start (sweep == 0): pass through until catalog loads.
            if _isCatalogDecor(entry.itemID, sweep) then
                -- Vendor coords from VendorAugment; wishlist (no npcID) meta is nil.
                local meta = entry.npcID and HDG.StaticData.VendorAugment:Get(entry.npcID) or nil
                out[#out + 1] = {
                    itemID      = entry.itemID,
                    npcID       = entry.npcID,
                    qty         = entry.qty or 1,   -- migration (legacy import tolerance)
                    addedAt     = entry.addedAt,
                    iconID      = resolveIconID(entry.itemID),
                    gold        = 0,  -- cost not derivable from catalog alone
                    -- VendorAugment row: name/zone/mapID/x/y/faction per npcID.
                    -- nil when entry is wishlist (no npcID) or npcID not yet in augment.
                    vendor = meta and {
                        name    = meta.name,
                        zone    = meta.zone,
                        mapID   = meta.mapID,
                        x       = meta.x,
                        y       = meta.y,
                        faction = meta.faction,
                    } or nil,
                    -- Wishlist (no npcID) render hint: where the catalog says it sells.
                    availableFrom = (not entry.npcID) and _resolveWishlistVendor(entry.itemID) or nil,
                    -- BoE = crafted (Professions) = the only AH-tradeable decor -> Auction House lane.
                    isTradeable = HDG.HousingCatalogObserver:GetBindTypeForItem(entry.itemID) == "BoE",
                }
            end
        end
        return out
    end,
})

-- Bucket entries into three lanes: vendor (npcID -> zone>vendor>items), Auction
-- House (no vendor but BoE/crafted), and wishlist (everything else -- the
-- non-purchasable drops/quests/achievements). Vendor wins over AH: a crafted item
-- a vendor also sells is something you can physically buy, so it routes to the vendor.
local function _bucketShoppingEntries(entries)
    local wish, ah, zones, zoneOrder = {}, {}, {}, {}
    for _, entry in ipairs(entries) do
        if not entry.npcID then
            if entry.isTradeable then ah[#ah + 1] = entry else wish[#wish + 1] = entry end
        else
            local zoneName = entry.vendor and entry.vendor.zone or "Unknown"
            local z = zones[zoneName]
            if not z then
                z = { _vendors = {}, _vendorList = {} }
                zones[zoneName] = z
                zoneOrder[#zoneOrder + 1] = zoneName
            end
            local v = z._vendors[entry.npcID]
            if not v then
                v = { vendor = entry.vendor, items = {} }
                z._vendors[entry.npcID] = v
                z._vendorList[#z._vendorList + 1] = entry.npcID
            end
            v.items[#v.items + 1] = entry
        end
    end
    table.sort(zoneOrder)
    for _, zoneName in ipairs(zoneOrder) do
        local z = zones[zoneName]
        table.sort(z._vendorList, function(a, b)
            local va = z._vendors[a].vendor
            local vb = z._vendors[b].vendor
            return (va and va.name or "") < (vb and vb.name or "")
        end)
    end
    return wish, ah, zones, zoneOrder
end

-- Per-item row envelope. Source chips via GateChips(itemID); no per-source flags in envelope.
local function _buildShoppingItemRow(item, npcID)
    return {
        kind   = "item", itemID = item.itemID, npcID = npcID,
        qty    = item.qty,
        iconID = item.iconID,
        gold   = item.gold,
        requiresRep = item.requiresRep,
    }
end

-- Append wishlist header (always) + items (when expanded).
-- Even empty wishlist shows a header so the user knows where items would land.
local function _appendWishSection(rows, wish, wishCollapsed)
    rows[#rows + 1] = { kind = "wishHeader", collapsed = wishCollapsed, count = #wish }
    if wishCollapsed then return end
    for _, w in ipairs(wish) do
        rows[#rows + 1] = {
            kind = "wishItem", itemID = w.itemID, qty = w.qty,
            addedAt = w.addedAt, iconID = w.iconID,
            availableFrom = w.availableFrom,   -- catalog "where to buy" hint (display only)
        }
    end
end

-- Append Auction House header + items (when expanded). Crafted/BoE decor: bought
-- off the AH (or crafted). Header omitted entirely when empty (unlike wishlist,
-- which has a manual add button -- the AH lane is purely auto-populated).
local function _appendAhSection(rows, ah, ahCollapsed)
    if #ah == 0 then return end
    rows[#rows + 1] = { kind = "ahHeader", collapsed = ahCollapsed, count = #ah }
    if ahCollapsed then return end
    for _, a in ipairs(ah) do
        rows[#rows + 1] = {
            kind = "ahItem", itemID = a.itemID, qty = a.qty,
            addedAt = a.addedAt, iconID = a.iconID,
        }
    end
end

-- Append vendor header + (when expanded) per-item rows for one vendor.
local function _appendVendorSection(rows, npcID, v, zoneName, vendorCollapsed)
    local vCollapsed = vendorCollapsed[npcID] == true
    rows[#rows + 1] = {
        kind = "vendor", npcID = npcID,
        name = v.vendor and v.vendor.name or "?",
        zone = zoneName, collapsed = vCollapsed,
        itemCount = #v.items,
    }
    if vCollapsed then return end
    for _, item in ipairs(v.items) do
        rows[#rows + 1] = _buildShoppingItemRow(item, npcID)
    end
end

-- Append zone header + (when expanded) per-vendor sections for one zone.
local function _appendZoneSection(rows, zoneName, z, zoneCollapsed, vendorCollapsed)
    local zCollapsed = zoneCollapsed[zoneName] == true
    rows[#rows + 1] = {
        kind = "zone", zone = zoneName, collapsed = zCollapsed,
        vendorCount = #z._vendorList,
    }
    if zCollapsed then return end
    for _, npcID in ipairs(z._vendorList) do
        _appendVendorSection(rows, npcID, z._vendors[npcID], zoneName, vendorCollapsed)
    end
end

-- Tree-via-flat-projection: wishHeader -> wishItem* -> zone* -> vendor* -> item*.
-- Collapsed state from session.ui.shoppingList.expanded (zones/vendors map; wishList scalar).
Selectors:Register("shopping.entriesByZone", {
    reads = {
        "session.ui.shoppingList.expanded",
        "session.itemNames.tick",
        "session.catalog.sweepGeneration",
    },
    calls = { "shopping.activeListEntries" },
    fn = function(state, ctx)
        local entries  = Selectors:Call("shopping.activeListEntries", state, ctx)
        local expanded = state.session.ui.shoppingList.expanded
        local wishCollapsed   = expanded.wishList == true
        local ahCollapsed     = expanded.ahList   == true
        local zoneCollapsed   = expanded.zones    -- map
        local vendorCollapsed = expanded.vendors  -- map

        local wish, ah, zones, zoneOrder = _bucketShoppingEntries(entries)

        -- Order: Wishlist -> Auction House -> vendor zones.
        local rows = {}
        _appendWishSection(rows, wish, wishCollapsed)
        _appendAhSection(rows, ah, ahCollapsed)
        for _, zoneName in ipairs(zoneOrder) do
            _appendZoneSection(rows, zoneName, zones[zoneName], zoneCollapsed, vendorCollapsed)
        end
        return rows
    end,
})
