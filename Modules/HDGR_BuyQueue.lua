-- HDGR_BuyQueue.lua -- paced merchant purchase queue (spec s6). The ONE buy
-- path: both Buy All and the quantity picker enqueue here. Pacing is mandatory --
-- a tight loop blows the server burst cap (~13-15) AND strands items in real bag
-- slots; paced buys go straight to decor storage (spec s2.1/s2.2 live probes).
--
-- Default pacing is EVENT-DRIVEN (MERCHANT_BUY_TICK_SECS == 0): buy one unit, then
-- buy the next only when the previous LANDS in decor storage -- signalled by HDG's
-- COLLECTION_CATALOG_ROW_COUNTS_UPDATED dispatch (which rides Blizzard's
-- HOUSING_STORAGE_ENTRY_UPDATED). Only ever one buy in flight, so it can't outrun
-- the server (burst cap) or strand items in bags, and it wastes no fixed delay.
-- A stall WATCHDOG (MERCHANT_BUY_TIMEOUT_SECS) only guards against a genuinely dropped
-- landed signal hanging the picker: if nothing lands for that long it STOPS the batch
-- (it never advances -- advancing with a buy in flight is what stranded items in bags).
-- Set MERCHANT_BUY_TICK_SECS > 0 to fall back to the legacy fixed-interval ticker.
-- C_Timer here is a functional throttle, not a UI transition (allowed).
--
-- Scope: gold-priced decor only (spec: decor vendors sell for gold). An item with
-- extended cost (currency/token) reports price 0 here; Enqueue rejects any batch
-- containing a <=0 price rather than risk mis-spending currency.
HDG = HDG or {}
HDG.BuyQueue = HDG.BuyQueue or {}
local Q = HDG.BuyQueue

local function _dispatchProgress(total, done)
    HDG.Store:Dispatch({ type = HDG.Constants.ACTIONS.MERCHANT_BUY_PROGRESS,
                         payload = total and { total = total, done = done } or {} })
end

function Q:IsRunning() return self._running == true end

local function _stop(self)
    self._running     = false
    self._awaitingLand = false
    if self._ticker  then self._ticker:Cancel();  self._ticker  = nil end
    if self._timeout then self._timeout:Cancel(); self._timeout = nil end
end

function Q:Cancel(reason)
    if not self._running then return end
    _stop(self)
    _dispatchProgress(nil)
    HDG.Log:Warn("merchant_buy", ("Buying stopped (%s) -- %d of %d bought")
        :format(reason or "cancelled", self._done, self._total))
end

-- rows: { {index, qty, price, name}, ... }. Returns true, or false + reason.
function Q:Enqueue(rows)
    if self._running then return false, "a purchase is already running" end
    local total, cost = 0, 0
    for _, r in ipairs(rows) do
        if not r.price or r.price <= 0 then
            -- exception(boundary): extended-cost / free merchant item -- out of Phase-1 scope.
            return false, "some items are not sold for gold"
        end
        total = total + r.qty
        cost  = cost + r.price * r.qty
    end
    if total == 0 then return false, "nothing to buy" end
    if cost > GetMoney() then   -- exception(boundary): live money check at the buy moment
        return false, "not enough gold (" .. HDG.Format.FormatGold(cost) .. " needed)"
    end
    -- Flatten to single (index) calls: stackCount==1 decor -> qty>maxStack is
    -- server-REJECTED (spec s2), so every unit is its own BuyMerchantItem(idx, 1).
    -- Each unit carries its source (itemID/npcID) so a landed buy can decrement
    -- the shopping-list entry it fulfils (Buy All). Picker rows omit itemID -> no-op.
    local flat, n = {}, 0
    for _, r in ipairs(rows) do
        for _ = 1, r.qty do
            n = n + 1
            flat[n] = { index = r.index, itemID = r.itemID, npcID = r.npcID }
        end
    end
    self._flat, self._total, self._done, self._running = flat, total, 0, true
    _dispatchProgress(total, 0)
    if HDG.Constants.MERCHANT_BUY_TICK_SECS > 0 then
        self._ticker = C_Timer.NewTicker(HDG.Constants.MERCHANT_BUY_TICK_SECS, function() Q:_TimerTick() end)
    else
        Q:_BuyNext()   -- event-driven: buy one, then wait for the landed signal
    end
    return true
end

-- Event-driven: buy the next unit; wait for its "landed in storage" signal (or the
-- safety timeout) before buying the following one.
function Q:_BuyNext()
    if not self._running then return end
    if not HDG.Store:GetState().session.merchant.open then Q:Cancel("vendor closed"); return end
    if self._done >= self._total then Q:_Finish(); return end
    self._done = self._done + 1
    self._awaitingLand = true
    BuyMerchantItem(self._flat[self._done].index, 1)
    _dispatchProgress(self._total, self._done)
    -- Stall watchdog: if NOTHING lands for this long, STOP (never advance -- advancing
    -- with a buy still in flight is what strands items in bags).
    self._timeout = C_Timer.NewTimer(HDG.Constants.MERCHANT_BUY_TIMEOUT_SECS, function()
        self._timeout = nil
        Q:Cancel("stalled -- no confirmation (an item may have gone to bags)")
    end)
end

-- COLLECTION_CATALOG_ROW_COUNTS_UPDATED = a purchase landed in decor storage.
-- _awaitingLand gates to exactly one advance per buy (a single buy can fan out to
-- several count dispatches). Deferred a frame so _BuyNext's progress dispatch is
-- not nested inside this subscriber's dispatch cycle.
function Q:_OnLanded()
    if not (self._running and self._awaitingLand) then return end
    self._awaitingLand = false
    if self._timeout then self._timeout:Cancel(); self._timeout = nil end
    local landed = self._flat[self._done]   -- the unit whose storage-arrival this confirms
    C_Timer.After(0, function()
        Q:_ReflectToList(landed)
        Q:_BuyNext()
    end)
end

-- Buy All is shopping-list-driven: as each purchased unit lands in decor storage,
-- decrement the shopping-list entry it fulfilled (ADJUST_QTY removes it at 0), so
-- the list tracks what's still needed. Quantity-picker buys carry no itemID, so
-- this is a no-op for them. Dispatched a frame later (from _OnLanded's deferral),
-- never nested inside the landed-signal subscriber.
function Q:_ReflectToList(unit)
    if not (unit and unit.itemID) then return end
    HDG.Store:Dispatch({
        type    = HDG.Constants.ACTIONS.SHOPPING_ITEM_ADJUST_QTY,
        payload = { itemID = unit.itemID, npcID = unit.npcID, delta = -1 },
    })
end

function Q:_Finish()
    _stop(self)
    _dispatchProgress(nil)
    HDG.Log:Success("merchant_buy", ("Bought %d item(s)"):format(self._total))
end

-- Legacy fixed-interval path (MERCHANT_BUY_TICK_SECS > 0).
function Q:_TimerTick()
    if not HDG.Store:GetState().session.merchant.open then
        Q:Cancel("vendor closed"); return
    end
    local k = HDG.Constants.MERCHANT_BUY_TICK_QTY
    while k > 0 and self._done < self._total do
        self._done = self._done + 1; k = k - 1
        BuyMerchantItem(self._flat[self._done].index, 1)
        Q:_ReflectToList(self._flat[self._done])
    end
    if self._done >= self._total then Q:_Finish()
    else _dispatchProgress(self._total, self._done) end
end

-- Drive event-driven pacing off the decor-landed dispatch. React to the ACTION --
-- do NOT re-register HOUSING_STORAGE_ENTRY_UPDATED (the catalog observer owns that
-- namespace). Cheap no-op check when idle.
HDG.Store:Subscribe(function(actionType)
    if actionType == HDG.Constants.ACTIONS.COLLECTION_CATALOG_ROW_COUNTS_UPDATED then
        Q:_OnLanded()
    end
end)
