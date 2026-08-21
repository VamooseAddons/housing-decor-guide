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
-- Scope: decor priced in GOLD or in Community Coupons. Anything else -- a free
-- slot, an item-token cost, a currency we do not recognise -- is still refused
-- by Enqueue rather than risk mis-spending it.
HDG = HDG or {}
HDG.BuyQueue = HDG.BuyQueue or {}
local Q = HDG.BuyQueue

local function _dispatchProgress(total, done)
    HDG.Store:Dispatch({ type = HDG.Constants.ACTIONS.MERCHANT_BUY_PROGRESS,
                         payload = total and { total = total, done = done } or {} })
end

function Q:IsRunning() return self._running == true end

-- Why the last run stopped, or nil if it finished. The picker shows this: the
-- dialog is what the player is looking at, and leaving the reason only in the
-- chat log meant a stopped run read as a miscount.
function Q:LastStopReason() return self._stopReason end

-- The run's final tally, readable after it ends. The picker used to accumulate
-- this from progress dispatches and read its own cache when the run finished --
-- so a dispatch it missed was lost for good, and a 5-of-5 run displayed 4 while
-- the queue had counted correctly (owner, in-game 2026-08-21). Asking the queue
-- cannot drift: there is one number and it is the queue's.
function Q:LastResult() return self._landed or 0, self._total or 0 end

local function _stop(self)
    self._running     = false
    self._awaitingLand = false
    if self._ticker  then self._ticker:Cancel();  self._ticker  = nil end
    if self._timeout then self._timeout:Cancel(); self._timeout = nil end
end

function Q:Cancel(reason)
    if not self._running then return end
    _stop(self)
    self._stopReason = reason or "cancelled"
    _dispatchProgress(nil)
    HDG.Log:Warn("merchant_buy", ("Buying stopped (%s) -- %d of %d bought")
        :format(self._stopReason, self._done, self._total))
end

-- Live Community Coupons balance. Its own function so the picker and the queue
-- read the wallet the same way.
function Q.CouponBalance()
    local info = _G.C_CurrencyInfo.GetCurrencyInfo(HDG.Constants.COUPON_CURRENCY_ID)  -- exception(boundary): nil before the currency is discovered
    return (info and info.quantity) or 0
end

-- rows: { {index, qty, price, name, couponPrice?}, ... }. Returns true, or false + reason.
--
-- A row is priced in gold (`price`) OR in Community Coupons (`couponPrice`),
-- never both, and a row priced in neither is still refused: the guard exists so
-- HDG cannot spend a currency it did not recognise, and widening it to coupons
-- must not weaken that. Costs are summed per wallet and checked separately.
function Q:Enqueue(rows)
    if self._running then return false, "a purchase is already running" end
    local total, cost, coupons = 0, 0, 0
    for _, r in ipairs(rows) do
        local couponPrice = r.couponPrice or 0   -- exception(optional): gold rows carry no coupon price
        if couponPrice > 0 then
            coupons = coupons + couponPrice * r.qty
        elseif r.price and r.price > 0 then
            cost = cost + r.price * r.qty
        else
            -- exception(boundary): free item, or an extended cost we do not recognise.
            return false, "some items are not sold for gold or coupons"
        end
        total = total + r.qty
    end
    if total == 0 then return false, "nothing to buy" end
    if cost > GetMoney() then   -- exception(boundary): live money check at the buy moment
        return false, "not enough gold (" .. HDG.Format.FormatGold(cost) .. " needed)"
    end
    if coupons > 0 and coupons > Q.CouponBalance() then
        return false, ("not enough Community Coupons (%d needed)"):format(coupons)
    end
    -- Flatten to single (index) calls: stackCount==1 decor -> qty>maxStack is
    -- server-REJECTED (spec s2), so every unit is its own BuyMerchantItem(idx, 1).
    -- Each unit carries its source (itemID/npcID) so a landed buy can decrement
    -- the shopping-list entry it fulfils (Buy All). Picker rows omit itemID -> no-op.
    local flat, n = {}, 0
    for _, r in ipairs(rows) do
        for _ = 1, r.qty do
            n = n + 1
            flat[n] = { index = r.index, itemID = r.itemID, npcID = r.npcID,
                        -- Separate from itemID on purpose: itemID drives the
                        -- shopping-list decrement, bagItemID only counts bags.
                        bagItemID = r.bagItemID or r.itemID,
                        -- toBags: coupon-bought decor arrives in BAGS, not decor
                        -- storage (owner, in-game 2026-08-21), so this unit's
                        -- confirmation is a bag-count rise, not a storage row.
                        toBags = (r.couponPrice or 0) > 0 }
        end
    end
    self._flat, self._total, self._done, self._running = flat, total, 0, true
    self._stopReason = nil   -- a fresh run owns its own outcome
    -- Coupon runs are COUNTED, not confirmed unit-by-unit. One item per run (the
    -- picker is the only caller that prices in coupons), so how many arrived is
    -- just "how many are in bags now, minus how many were there when we started".
    self._bagItemID = flat[1] and flat[1].toBags and flat[1].bagItemID or nil  -- exception(nullable): gold run, counted from storage signals
    self._bagStart  = self._bagItemID and HDG.BagObserver:GetBagCount(self._bagItemID) or 0
    self._landed = 0   -- units CONFIRMED in storage; _done is units INITIATED
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
    -- Done when the ITEMS ARE HERE, not when the buys were fired. Keying this on
    -- _done meant a run could end with everything sent and the last arrival still
    -- outstanding -- which is the accounting that reported 18 of 19.
    if self._landed >= self._total then Q:_Finish(); return end
    if not HDG.Store:GetState().session.merchant.open then Q:Cancel("vendor closed"); return end
    if self._done < self._total then
        self._done = self._done + 1
        BuyMerchantItem(self._flat[self._done].index, 1)
    end
    -- Waiting either way: for the unit just fired, or -- when everything has been
    -- fired and an arrival is still outstanding -- for that one. Dropping the wait
    -- state in the second case would leave the run hung with no watchdog.
    self._awaitingLand = true
    -- No progress dispatch here. _done is the unit now IN FLIGHT, not a finished
    -- one, and reporting it as done told the picker "1 of 1" the instant a single
    -- buy was fired: the wheels hit 0 remaining while the button still said Stop,
    -- and a stall or a user Stop then satisfied done >= total and was reported as
    -- a completed purchase. Progress is dispatched from _OnLanded, on confirmation.
    -- Stall watchdog: if NOTHING lands for this long, STOP (never advance -- advancing
    -- with a buy still in flight is what strands items in bags).
    self._timeout = C_Timer.NewTimer(HDG.Constants.MERCHANT_BUY_TIMEOUT_SECS, function()
        self._timeout = nil
        -- LOOK BEFORE GIVING UP. The watchdog used to treat "no confirmation" as
        -- "did not happen", and that is not the same thing: a 13-item coupon run
        -- spent 26 coupons and put 13 items in the player's bags while the picker
        -- reported 12, because the last item's BAG_UPDATE never reached us
        -- (owner, in-game 2026-08-21). The item was there the whole time -- only
        -- the signal was missing, and the bag count says so plainly.
        --
        -- So a late confirmation is still a confirmation. Only a unit that really
        -- is absent stops the run.
        local counted = Q._running and Q._awaitingLand and Q:_BagLandedCount()
        if counted and counted > Q._landed then
            HDG.Log:Debug("merchant_buy", "landing signal missed -- counted from bags instead")
            Q:_Confirm(counted)
            return
        end
        -- Name the destination the unit was actually waiting on: for a coupon
        -- buy "may have gone to bags" is the EXPECTED path, so it reads as a
        -- non-answer.
        local stalled = Q._flat[Q._done]
        Q:Cancel(stalled and stalled.toBags
            and "stalled -- the purchase never reached your bags"
            or  "stalled -- no confirmation (an item may have gone to bags)")
    end)
end

-- COLLECTION_CATALOG_ROW_COUNTS_UPDATED = a purchase landed in decor storage.
-- _awaitingLand gates to exactly one advance per buy (a single buy can fan out to
-- several count dispatches). Deferred a frame so _BuyNext's progress dispatch is
-- not nested inside this subscriber's dispatch cycle.
function Q:_OnLanded()
    if not (self._running and self._awaitingLand) then return end
    self:_Confirm()
end

-- Bag-side landing. Coupon-bought decor arrives in BAGS, so
-- COLLECTION_CATALOG_ROW_COUNTS_UPDATED never fires for it and the queue used to
-- sit until the stall watchdog gave up -- the picker read "0 items purchased"
-- while the purchases were, in fact, happening (owner, in-game 2026-08-21).
--
-- This is an ADDITIONAL confirmation, not a replacement: a coupon unit accepts
-- either a bag-count rise or a storage landing, whichever arrives first. The
-- in-game evidence showed the decor-storage total moving during a coupon run
-- too, so treating "coupon" as strictly "bags" would stall on whichever items go
-- the other way. Both signals mean the same thing -- the purchase arrived -- and
-- accepting either fails safe, where accepting only one fails shut.
--
-- Driven from MerchantObserver's BAG_UPDATE rather than BAG_INVENTORY_UPDATED:
-- BagObserver gates its bag scan on requiresMainWindow, and buying at a vendor
-- with the main window closed is the normal case, so that dispatch cannot be
-- relied on here. Counts still come from BagObserver -- it owns
-- C_Item.GetItemCount (ADR-011).
-- How many of this run's item are in bags beyond what we started with, capped at
-- what we asked for. THE count -- not a tally of individually-confirmed units.
--
-- It used to be a per-unit ledger: each unit captured its own "before" count and
-- was confirmed when that count rose. That lost exactly one item per run, every
-- run -- 19 bought/18 counted, 13/12, 5/4 -- because each _BuyNext re-read the
-- count as the NEXT unit's baseline, so anything arriving between a confirmation
-- and that re-read was absorbed into the baseline and never counted again
-- (owner, in-game 2026-08-21).
--
-- A count cannot drift like that. It is recomputed from scratch every time, so a
-- missed, coalesced or doubled event costs nothing: the next look is still right,
-- and two items arriving in one window are both seen.
function Q:_BagLandedCount()
    if not self._bagItemID then return nil end   -- exception(nullable): gold run
    local gained = HDG.BagObserver:GetBagCount(self._bagItemID) - self._bagStart
    if gained < 0 then return 0 end   -- exception(boundary): player moved items mid-buy
    return math.min(gained, self._total)
end

-- Book an arrival and move on. Shared by both landing signals and the watchdog,
-- so it is recorded identically however it was noticed. `landed` is an absolute
-- count when the caller has one; storage signals still step by one.
function Q:_Confirm(landed)
    local unit = self._flat[self._done]
    self._awaitingLand = false
    if self._timeout then self._timeout:Cancel(); self._timeout = nil end
    self._landed = landed or (self._landed + 1)
    C_Timer.After(0, function()
        Q:_ReflectToList(unit)
        _dispatchProgress(self._total, self._landed)
        Q:_BuyNext()
    end)
end

function Q:_OnBagLanded()
    if not (self._running and self._awaitingLand) then return end
    local landed = self:_BagLandedCount()
    if not landed then return end   -- exception(nullable): gold run, counted from storage signals
    if landed <= self._landed then return end   -- nothing new arrived
    self:_Confirm(landed)
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
    self._stopReason = nil   -- completed, not stopped
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
    -- Legacy path gets no landed signal, so initiated is the only count it has.
    self._landed = self._done
    if self._done >= self._total then Q:_Finish()
    else _dispatchProgress(self._total, self._landed) end
end

-- Drive event-driven pacing off the decor-landed dispatch. React to the ACTION --
-- do NOT re-register HOUSING_STORAGE_ENTRY_UPDATED (the catalog observer owns that
-- namespace). Cheap no-op check when idle.
HDG.Store:Subscribe(function(actionType)
    if actionType == HDG.Constants.ACTIONS.COLLECTION_CATALOG_ROW_COUNTS_UPDATED then
        Q:_OnLanded()
    end
end)
