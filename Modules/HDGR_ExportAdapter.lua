-- HDGR_ExportAdapter.lua -- maps an export source (shopping list / style /
-- furnishing set / owned collection) to a flat { {decorID, count}, ... } list,
-- the shape HDG.DecorDumpCodec.Encode consumes for DD2 output.
--
-- Source item shapes differ (verified in HDGR_Selectors_Styles / StoreFurnishings):
--   vsl:*    -> account.vendorShoppingLists[id].items = { {itemID, npcID, qty}, ... }
--   set:*    -> account.furnishingSets[key].items     = { {id=decorID, count}, ... }
--   style:*  -> StyleResolve.ItemsFor -> array of bare itemIDs (1 each)
--   collection -> HousingCatalogObserver owned rows (real owned counts)
HDG = HDG or {}
HDG.ExportAdapter = HDG.ExportAdapter or {}
local A = HDG.ExportAdapter

-- bare itemID array (styles/concepts via StyleResolve) -> {decorID, count=1}
local function fromItemIDs(itemIDs)
    local obs, out = HDG.HousingCatalogObserver, {}
    for _, itemID in ipairs(itemIDs) do
        local decorID = obs:GetDecorIDByItemID(itemID)
        if decorID then out[#out + 1] = { decorID = decorID, count = 1 } end  -- exception(nullable): non-decor items have no decorID; skip
    end
    return out
end

-- shopping-list items {itemID, npcID, qty} -> {decorID, count=qty}
local function fromShoppingItems(items)
    local obs, out = HDG.HousingCatalogObserver, {}
    for _, it in ipairs(items) do
        local decorID = obs:GetDecorIDByItemID(it.itemID)
        if decorID then out[#out + 1] = { decorID = decorID, count = it.qty or 1 } end  -- exception(optional): qty optional, default 1
    end
    return out
end

-- furnishing-set items {id=decorID, count} -> {decorID, count} (already decorIDs)
local function fromSetItems(items)
    local out = {}
    for _, it in ipairs(items) do
        out[#out + 1] = { decorID = it.id, count = it.count or 1 }  -- exception(optional): count optional, default 1
    end
    return out
end

-- whole owned-decor collection: observer rows, owned-only, real owned counts
-- (quantity + remainingRedeemable + numPlaced, matching IsOwned).
local function fromCollection()
    local obs, out = HDG.HousingCatalogObserver, {}
    obs:IterateRows(function(_itemID, row)  -- IterateRows yields (itemID, row)
        if row.decorID and obs:IsOwned(row) then
            out[#out + 1] = { decorID = row.decorID,
                count = (row.quantity or 0) + (row.remainingRedeemable or 0) + (row.numPlaced or 0) }  -- exception(boundary): catalog struct fields sparse
        end
    end)
    return out
end

function A.Entries(key, state)
    if key == "collection" then return fromCollection() end
    if key:match("^vsl:") then
        local list = state.account.vendorShoppingLists[key:sub(5)]  -- exception(nullable): list may be deleted under a stale UI key
        if not list then return {} end
        return fromShoppingItems(list.items)
    end
    if key:match("^set:") then
        local set = state.account.furnishingSets[key]  -- exception(nullable): set may be deleted under a stale UI key
        if not set then return {} end
        return fromSetItems(set.items)
    end
    return fromItemIDs(HDG.StyleResolve.ItemsFor(key, state))
end
