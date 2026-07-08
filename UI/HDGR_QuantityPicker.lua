-- HDGR_QuantityPicker.lua -- combination-lock quantity dialog for buying decor
-- at a vendor (spec s5). Right-click a decor merchant row -> three 0-9 wheels
-- (no carry), a live total vs gold + decor-storage headroom, and a Buy button
-- that enqueues the paced BuyQueue. Bespoke frame (AcqMapWidget precedent);
-- built once on first Open and reused.
HDG = HDG or {}
HDG.QuantityPicker = HDG.QuantityPicker or {}
local QP = HDG.QuantityPicker

-- ===== Pure math (headless-tested) ==========================================
function QP.Digits(n)
    n = math.max(0, math.min(999, math.floor(n or 0)))
    return { math.floor(n / 100) % 10, math.floor(n / 10) % 10, n % 10 }
end

function QP.FromDigits(h, t, o) return h * 100 + t * 10 + o end

-- Returns (ok, reasonString). cap = math.huge means "storage data unavailable".
function QP.Validate(price, qty, money, owned, cap)
    if qty <= 0 then return false, "Pick a quantity" end
    if price * qty > money then return false, "Not enough gold" end
    if owned + qty > cap then return false, "Not enough decor storage" end
    return true, nil
end

-- ===== Dialog =================================================================
local WHEEL_COUNT = 3   -- 100s / 10s / 1s

local function _digitColumn(parent, onStep, index)
    local col = CreateFrame("Frame", nil, parent)
    col:SetSize(44, 80)
    col:EnableMouseWheel(true)
    col:SetScript("OnMouseWheel", function(_, dir) onStep(index, dir) end)

    local up = HDG.UI:Button(col, "+", "body")
    up:SetSize(30, 20); up:SetPoint("TOP")
    up:SetScript("OnClick", function() onStep(index, 1) end)

    local num = HDG.UI:Label(col, "0", "heading", "CENTER", { role = "Text" })
    num:SetPoint("CENTER")

    local down = HDG.UI:Button(col, "-", "body")
    down:SetSize(30, 20); down:SetPoint("BOTTOM")
    down:SetScript("OnClick", function() onStep(index, -1) end)

    return col, num
end

local FRAME_W = 360
local function _build()
    local f = HDG.UI:Frame(_G.UIParent)
    f:SetSize(FRAME_W, 244)
    f:SetPoint("CENTER")
    f:SetFrameStrata("DIALOG")
    f:EnableMouse(true)                     -- swallow clicks so the merchant behind doesn't get them
    f:Hide()
    HDG.Theme:Register(f, "Canvas")   -- window-body backdrop, matches the main frame (Raised was the too-light card surface)

    local title = HDG.UI:Label(f, "", "heading", "CENTER", { role = "TextHeading" })
    title:SetPoint("TOP", 0, -12)
    title:SetWidth(FRAME_W - 32)   -- constrain + wrap long decor names instead of overflowing
    title:SetWordWrap(true)
    f._title = title

    -- Three digit wheels, centered as a row; anchored below the title so a
    -- wrapped (two-line) name pushes them down instead of overlapping.
    local wheels = CreateFrame("Frame", nil, f)
    wheels:SetSize(WHEEL_COUNT * 44 + (WHEEL_COUNT - 1) * 8, 80)
    wheels:SetPoint("TOP", title, "BOTTOM", 0, -12)
    f._digits = { 0, 0, 0 }
    f._numFS  = {}
    local function step(i, dir)
        if f._buying or f._done then return end   -- wheels inert during a buy AND after one completes (button stays "Close")
        local v = f._digits[i] + (dir > 0 and 1 or -1)
        f._digits[i] = (v < 0) and 0 or (v > 9 and 9 or v)   -- clamp 0-9, no carry
        f._refresh()
    end
    for i = 1, WHEEL_COUNT do
        local col, num = _digitColumn(wheels, step, i)
        col:SetPoint("LEFT", (i - 1) * 52, 0)
        f._numFS[i] = num
    end

    local total = HDG.UI:Label(f, "", "body", "CENTER", { role = "Text" })
    total:SetPoint("TOP", wheels, "BOTTOM", 0, -10)
    f._total = total

    local info = HDG.UI:Label(f, "", "small", "CENTER", { role = "TextInfo" })
    info:SetPoint("TOP", total, "BOTTOM", 0, -4)
    f._info = info

    -- Live progress line ("N items purchased in T.TTs"); empty until buying.
    local stats = HDG.UI:Label(f, "", "small", "CENTER", { role = "TextDim" })
    stats:SetPoint("TOP", info, "BOTTOM", 0, -4)
    f._stats = stats

    local buy = HDG.UI:Button(f, "", "body")
    buy:SetSize(110, 24); buy:SetPoint("BOTTOMLEFT", 24, 16)
    buy:SetScript("OnClick", function() f._onBuy() end)
    f._buy = buy

    local cancel = HDG.UI:Button(f, _G.CANCEL, "body")
    cancel:SetSize(90, 24); cancel:SetPoint("BOTTOMRIGHT", -24, 16)
    cancel:SetScript("OnClick", function() QP:_Close(true) end)   -- stop any running buy, then close

    -- Defensive: any hide path stops the timer + clears buying state.
    f:SetScript("OnHide", function(self)
        self:SetScript("OnUpdate", nil)
        self._buying, self._done = false, false
    end)

    QP._frame = f
    return f
end

function QP:_RenderStats()
    local f = self._frame
    if not f then return end
    local t = (f._buyEnd or GetTime()) - (f._buyStart or GetTime())
    f._stats:SetText(("%d items purchased in %.2fs"):format(f._buyDone or 0, t))
end

function QP:_Close(cancelQueue)
    local f = self._frame
    if not f then return end
    if cancelQueue and HDG.BuyQueue:IsRunning() then HDG.BuyQueue:Cancel("picker closed") end
    f._buying, f._done = false, false
    f:SetScript("OnUpdate", nil)
    f:Hide()
end

-- Drive the countdown wheels + stats line from MERCHANT_BUY_PROGRESS.
function QP:_OnProgress()
    local f = self._frame
    if not (f and f._buying) then return end
    local b = HDG.Store:GetState().session.merchant.buying
    if not b then
        -- Buying ended. Completed -> freeze at 0 with the final tally + Close;
        -- cancelled/interrupted -> just close.
        f:SetScript("OnUpdate", nil)
        f._buyEnd = GetTime()
        if (f._buyDone or 0) >= (f._buyTotal or 0) then
            f._buying, f._done = false, true
            for i = 1, WHEEL_COUNT do f._numFS[i]:SetText("0") end
            f._buy:SetText(_G.CLOSE or "Close")
            QP:_RenderStats()
        else
            -- Stopped/stalled mid-batch: stay open, pre-fill the wheels with the
            -- REMAINING count so one more Buy click continues from here.
            f._buying = false
            f._digits = QP.Digits((f._buyTotal or 0) - (f._buyDone or 0))
            QP:_RenderStats()   -- freeze the partial tally under the gold line
            f._refresh()        -- wheels -> remaining, button -> "Buy N"
        end
        return
    end
    f._buyDone, f._buyTotal = b.done, b.total
    local d = QP.Digits(b.total - b.done)   -- remaining, counting down
    for i = 1, WHEEL_COUNT do f._numFS[i]:SetText(tostring(d[i])) end
    QP:_RenderStats()
end

-- Resolve current decor-storage (owned, cap). Live snapshot if this session has
-- one, else the persisted cache, else unknown. A max of 0 is a cold/uninitialised
-- reading -- treated as UNKNOWN (math.huge = no storage gate), NOT a real zero cap
-- (which would block every quantity behind "Not enough decor storage"). Read live
-- on every refresh so a paced buy's landed units (resume) reflect in the headroom.
function QP.ResolveCapacity(st)
    local capData = HDG.Selectors:Call("house.capacityData", st, {})
    if capData.available and capData.max > 0 then
        return capData.owned, capData.max
    end
    local cache = st.account.houseCapacityCache   -- exception(nullable): false until first house snapshot captures capacity
    if cache and cache.max and cache.max > 0 then
        return cache.owned, cache.max
    end
    return 0, math.huge
end

function QP:Open(itemID)
    if HDG.BuyQueue:IsRunning() then return end   -- a buy is mid-flight; keep its picker
    local st    = HDG.Store:GetState()   -- exception(false-positive): top-level dialog open, not a row factory
    local stock = st.session.merchant.byItemID[itemID]
    if not stock then return end          -- exception(nullable): slot vanished (page change) between right-click and open

    local f = QP._frame or _build()
    f._buying, f._done = false, false   -- fresh dialog: not in a buy
    f:SetScript("OnUpdate", nil)
    f._stats:SetText("")
    f._title:SetText(stock.name or "?")
    f._digits = { 0, 0, 0 }

    f._refresh = function()
        for i = 1, WHEEL_COUNT do f._numFS[i]:SetText(tostring(f._digits[i])) end
        local qty   = QP.FromDigits(f._digits[1], f._digits[2], f._digits[3])
        local money = GetMoney()   -- exception(boundary): live wallet at the moment of pick
        local owned, cap = QP.ResolveCapacity(HDG.Store:GetState())   -- live: reflects landed units on resume + guards cold max==0
        local ok    = QP.Validate(stock.price, qty, money, owned, cap)
        f._total:SetText(("x %d  =  %s"):format(qty, HDG.Format.FormatGold(stock.price * qty)))
        HDG.Theme:Register(f._total, ok and "Text" or "TextError")   -- re-skin on validity flip
        -- Show PROJECTED storage (current + this purchase), so it climbs toward
        -- the cap as you dial the wheels -- and reads red-over-cap via the total.
        local storageStr = (cap == math.huge) and ""
            or ("   .   " .. HDG.Locale:Get("QTYPICKER_STORAGE")):format(owned + qty, cap)
        f._info:SetText((HDG.Locale:Get("QTYPICKER_HAVE")):format(HDG.Format.FormatGold(money)) .. storageStr)
        f._buy:SetText((HDG.Locale:Get("QTYPICKER_BUY")):format(qty))
        f._buy:SetEnabled(ok)
    end

    f._onBuy = function()
        if f._done   then QP:_Close(false); return end                       -- "Close" after a completed buy
        if f._buying then HDG.BuyQueue:Cancel("stopped by user"); return end  -- "Stop" -> halt; picker refills with the remainder
        local qty = QP.FromDigits(f._digits[1], f._digits[2], f._digits[3])
        local owned, cap = QP.ResolveCapacity(HDG.Store:GetState())
        local okv = QP.Validate(stock.price, qty, GetMoney(), owned, cap)
        if not okv then return end
        local ok, why = HDG.BuyQueue:Enqueue({ { index = stock.index, qty = qty,
                                                 price = stock.price, name = stock.name } })
        if not ok then HDG.Log:Warn("merchant_buy", why); return end   -- reject: stay open to adjust
        -- Buying mode: keep the dialog, wheels count DOWN to remaining, Buy -> Stop.
        f._buying, f._buyTotal, f._buyDone = true, qty, 0
        f._buyStart, f._buyEnd, f._acc = GetTime(), nil, 0
        f._buy:SetText(_G.STOP or "Stop")
        f:SetScript("OnUpdate", function(self, dt)
            self._acc = (self._acc or 0) + dt
            if self._acc >= 0.1 then self._acc = 0; QP:_RenderStats() end
        end)
        QP:_OnProgress()   -- seed the countdown + stats immediately
    end

    f._refresh()
    f:Show()
end

-- React to the buy queue's progress (live countdown/timer) + vendor close (dismiss
-- the picker when the merchant window goes away). Cheap no-op check when hidden.
HDG.Store:Subscribe(function(actionType)
    local f = QP._frame
    if not (f and f:IsShown()) then return end
    local A = HDG.Constants.ACTIONS
    if actionType == A.MERCHANT_BUY_PROGRESS then
        QP:_OnProgress()
    elseif actionType == A.MERCHANT_SET_STATE
       and not HDG.Store:GetState().session.merchant.open then
        QP:_Close(true)
    end
end)
