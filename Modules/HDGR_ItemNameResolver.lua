-- HDG.ItemNameResolver
-- ============================================================================
-- Catalog items resolve from HousingCatalogObserver.byItemID (fast path).
-- This resolver handles non-catalog items: recipe reagents, lumber, mogul materials.
-- GetItemInfo/GetItemInfoInstant return nil on first call for uncached items;
-- async ItemEventListener + batch dispatch handles the cold-load race.
--
-- Async: Blizzard's ItemEventListener (AsyncCallbackSystemMixin) wraps the
-- RequestLoadItemDataByID + ITEM_DATA_LOAD_RESULT pair. One callback per itemID;
-- coalesced into one ITEM_INFO_RESOLVED dispatch per BATCH_WINDOW (avoids 50 fan-outs
-- on cold load). `_pending` = deduped batch; `_callbacks` = in-flight guards.

HDG = HDG or {}
HDG.ItemNameResolver = HDG.ItemNameResolver or {}
local R = HDG.ItemNameResolver

R._pending          = R._pending          or {}     -- [itemID] = true (deduped batch)
R._callbacks        = R._callbacks        or {}     -- [itemID] = true while ItemEventListener cb in flight
R._tick             = R._tick             or 0  -- exception(false-positive): idempotent module-load init
R._timerScheduled   = R._timerScheduled   or false  -- one drain timer pending

R.BATCH_WINDOW = 0.5

-- Cache-miss: register a per-itemID ItemEventListener callback if not already in flight.
-- Fires once on success; listener clears on failure without firing.
function R:_Request(itemID)
    if not itemID then return end
    if self._callbacks[itemID] then return end
    if not (_G.ItemEventListener and _G.ItemEventListener.AddCallback) then return end
    self._callbacks[itemID] = true
    _G.ItemEventListener:AddCallback(itemID, function()
        self._callbacks[itemID] = nil
        self:OnItemInfoReceived(itemID, true)
    end)
    -- Trigger the async load: AddCallback only subscribes, doesn't initiate.
    -- Without RequestLoadItemDataByID, callbacks only fire if another path queries the same itemID.
    -- Idempotent: already-cached items trigger GET_ITEM_INFO_RECEIVED synchronously next frame.
    if _G.C_Item and _G.C_Item.RequestLoadItemDataByID then
        _G.C_Item.RequestLoadItemDataByID(itemID)  -- exception(boundary): C_Item nil for uncached / invalid item
    end
end

function R:GetTick()    return self._tick    end
function R:GetPending() return self._pending end

-- ResolveName: catalog row -> reagent DB -> Blizzard live cache -> async load.
-- Returns (name, resolved); resolved=false means "item N" placeholder (load pending).
function R:ResolveName(itemID)
    if not itemID then return "?", false end
    -- 1. Catalog row (fast path: sync, no API call).
    local obs = HDG.HousingCatalogObserver
    local row = obs and obs.byItemID and obs.byItemID[itemID]
    if row and row.name then return row.name, true end
    -- 2. State cache (survives Blizzard cache eviction across long sessions).
    local cache = HDG.Store:GetState().session.itemNames.names
    local cached = cache[itemID]
    if cached then return cached, true end
    -- 3. Static reagent DB (pre-baked names from build pipeline).
    local rdb = HDG.StaticData.Reagents:GetAll()
    if rdb and rdb[itemID] and rdb[itemID].name then
        return rdb[itemID].name, true
    end
    -- 4. Blizzard's live cache (warm if user has seen the item recently).
    if _G.C_Item and _G.C_Item.GetItemInfo then
        local name = _G.C_Item.GetItemInfo(itemID)
        if name then return name, true end
    end
    -- 5. Cold cache: register ItemEventListener callback -> batch -> Drain -> ITEM_INFO_RESOLVED.
    self:_Request(itemID)
    return "item " .. tostring(itemID), false
end

-- ResolveIcon: mirrors ResolveName's boundary contract for icons.
-- C_Item.GetItemIconByID is sync DBC (always cached, preferred over GetItemInfoInstant).
-- On miss, shares _Request(itemID) with ResolveName (one callback warms both).
function R:ResolveIcon(itemID)
    if not itemID then return nil end
    -- Fast path: catalog rows carry iconTexture (skip API entirely).
    local obs = HDG.HousingCatalogObserver
    local row = obs and obs.byItemID and obs.byItemID[itemID]
    if row and row.iconTexture then return row.iconTexture end
    -- exception(boundary): GetItemIconByID is sync DBC (always cached); any valid itemID returns a fileID.
    -- GetItemInfoInstant can miss for items without full client data (correct for names, wrong for icons).
    if _G.C_Item and _G.C_Item.GetItemIconByID then
        local icon = _G.C_Item.GetItemIconByID(itemID)  -- exception(boundary): sync DBC lookup, always cached
        if icon then return icon end
    end
    -- Fallback: GetItemInfoInstant, then async for deleted/server-only IDs.
    if _G.C_Item and _G.C_Item.GetItemInfoInstant then
        local _id, _type, _subType, _equipLoc, icon = _G.C_Item.GetItemInfoInstant(itemID)
        if icon then return icon end
    end
    self:_Request(itemID)
    return nil
end

-- GetSellPrice: GetItemInfo's 11th return via the resolver boundary (ADR-003b).
-- On cold miss: _Request + return 0; drain bumps tick so mogul.plan re-runs.
-- 0 is the fail-safe (mogul treats 0 as "ineligible").
function R:GetSellPrice(itemID)
    if not itemID then return 0 end
    if _G.C_Item and _G.C_Item.GetItemInfo then
        local _, _, _, _, _, _, _, _, _, _, sellPrice = _G.C_Item.GetItemInfo(itemID)
        if sellPrice then return sellPrice end  -- exception(boundary): sparse tuple on cold cache
    end
    self:_Request(itemID)
    return 0
end

-- OnItemInfoReceived: called from ItemEventListener callback + test seam.
-- Adds itemID to pending batch; schedules drain (explicit boolean: C_Timer.After returns nil).
function R:OnItemInfoReceived(itemID, success)
    if not (itemID and success) then return end
    self._pending[itemID] = true
    if self._timerScheduled then return end
    if not (_G.C_Timer and _G.C_Timer.After) then return end
    self._timerScheduled = true
    _G.C_Timer.After(self.BATCH_WINDOW, function() R:Drain() end)
end

-- Drain: resolve all pending itemIDs (cache warm after ItemEventListener fired) and
-- dispatch one ITEM_INFO_RESOLVED bulk. Reducer writes to session.itemNames.names.
function R:Drain()
    self._timerScheduled = false
    local batch = self._pending
    self._pending = {}
    self._tick = self._tick + 1
    local entries, count = {}, 0
    for itemID in pairs(batch) do
        -- GetItemInfo should be warm (ItemEventListener fired). nil = race or missing; skip.
        local name = _G.C_Item and _G.C_Item.GetItemInfo and _G.C_Item.GetItemInfo(itemID)
        if name then
            count = count + 1
            entries[count] = { itemID = itemID, name = name }
        end
    end
    -- Drain fires post-init; Store + Constants always present.
    if count > 0 then
        HDG.Store:Dispatch({
            type    = HDG.Constants.ACTIONS.ITEM_INFO_RESOLVED,
            payload = { entries = entries, count = count },
        })
    end
    return batch
end

-- ===== Module registration ===================================================
-- No blizzardEvents: cache misses register ItemEventListener callbacks directly.
HDG.Modules:Declare({
    name = "ItemNameResolver",
    dependencies = {},
})
