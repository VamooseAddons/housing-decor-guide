-- HDGR_MerchantObserver.lua -- session.merchant snapshot for the vendor-buying
-- surface (spec docs/HDGR_VENDOR_BUYING_SPEC.md). Owns C_MerchantFrame + the
-- MERCHANT_* events. READ side only: scans the open merchant and dispatches the
-- snapshot. The BUY side (paced queue) lives in HDGR_BuyQueue.lua and consumes
-- this state; the right-click override (Task 6) also installs from here.
HDG = HDG or {}
HDG.MerchantObserver = HDG.MerchantObserver or {}
local MO = HDG.MerchantObserver
local A   -- ACTIONS alias, bound lazily in handlers (Constants loads before Modules)

-- NB: no merchant npcID. UnitGUID("npc") is a SECRET string at instanced vendors
-- (e.g. MOTHER in the Chamber of Heart) and throws on :match under addon taint
-- (Reference/MIDNIGHT_SECRET_VALUES.md). The scan keys everything off itemID, so
-- npcID was never read -- don't reintroduce the GUID parse.
-- Coupons per unit, or nil when this slot is not bought with them.
--
-- Deliberately narrow: EXACTLY ONE cost component, and that component is the
-- Community Coupons currency. A slot with two components, or an item-token cost,
-- returns nil and stays out of the bulk-buy path -- the point of this gate is
-- that HDG never spends a currency it did not recognise. Asked for by
-- madaileinhatter (Discord 2026-08-12); the picker previously refused every
-- coupon-priced item because it tested for gold.
--
-- GetMerchantItemCostItem(index, costIndex) -> texture, value, link, currencyName.
-- A currency component carries currencyName and a currency link; an item
-- component carries an item link and no currencyName (Blizzard's own test,
-- MerchantFrame.lua:692).
local function _couponCost(index, costCount)
    if costCount ~= 1 then return nil end   -- exception(nullable): gold-only or a multi-part cost
    local _, value, link, currencyName = GetMerchantItemCostItem(index, 1)  -- exception(boundary): classic non-namespaced merchant global
    if not (link and currencyName and value and value > 0) then return nil end  -- exception(boundary): item-token cost, or a slot still streaming in
    local currencyID = _G.C_CurrencyInfo.GetCurrencyIDFromLink(link)
    if currencyID ~= HDG.Constants.COUPON_CURRENCY_ID then return nil end   -- exception(nullable): some other currency
    return value
end

local function _scan()
    local byItemID = {}
    for i = 1, GetMerchantNumItems() do
        local itemID = GetMerchantItemID(i)
        local info   = C_MerchantFrame.GetItemInfo(i)
        if itemID and info then   -- exception(boundary): slots stream in; nil rows on an early MERCHANT_UPDATE
            local costCount = GetMerchantItemCostInfo(i) or 0   -- exception(boundary): classic non-namespaced merchant global
            byItemID[itemID] = { index = i, price = info.price,
                                 name = info.name, numAvailable = info.numAvailable,
                                 -- goldOnly: positive gold price AND zero extended-cost
                                 -- components -> bulk-buyable. hasCost: has a currency/token
                                 -- cost -> distinguishes currency items from free ones so
                                 -- Buy All's "sold for a currency" skip note is accurate.
                                 -- numAvailable is carried for display only. Do NOT
                                 -- cap a bulk buy with it: housing decor is
                                 -- unlimited stock (see HDGR_QuantityPicker:Open).
                                 goldOnly    = (info.price or 0) > 0 and costCount == 0,
                                 hasCost     = costCount > 0,
                                 couponPrice = _couponCost(i, costCount) }
        end
    end
    return byItemID
end

function MO:ScanNow()
    A = HDG.Constants.ACTIONS
    HDG.Store:Dispatch({ type = A.MERCHANT_SET_STATE, payload = {
        open = true, byItemID = _scan(),
    }})
end

-- ===== Right-click quantity-picker override (spec s5.1) =====================
-- Wrap each merchant item button's OnClick: a right-click on a DECOR slot opens
-- HDG's quantity picker; everything else (left-click pickup, non-decor rows)
-- delegates to Blizzard's original handler. Restored verbatim on close so the
-- frame is never left altered. Gated behind MERCHANT_QTY_PICKER so a patch that
-- re-templates the buttons can be worked around with one toggle.
local MERCHANT_PAGE_BUTTONS = 10   -- MerchantItem1..10ItemButton (Blizzard fixed set)

local function _installClickOverrides()
    if not HDG.Config:Get("MERCHANT_QTY_PICKER") then return end
    MO._origClicks = MO._origClicks or {}
    for i = 1, MERCHANT_PAGE_BUTTONS do
        local btn = _G["MerchantItem" .. i .. "ItemButton"]
        if btn and not MO._origClicks[btn] then   -- exception(boundary): Blizzard may re-template merchant buttons in a patch
            local orig = btn:GetScript("OnClick")
            MO._origClicks[btn] = orig or false   -- false = "had no handler" (still restore to nil)
            btn:SetScript("OnClick", function(self, mouseButton, down)
                local itemID = GetMerchantItemID(self:GetID())
                local stock  = itemID and HDG.Store:GetState().session.merchant.byItemID[itemID]
                local buyable = stock and (stock.goldOnly or (stock.couponPrice or 0) > 0)
                    and not HDG.QuantityPicker:IsOptedOut()                    -- X'd away at this vendor -> Blizzard's own buying
                if mouseButton == "RightButton" and buyable                    -- gold- or coupon-priced decor -> picker
                   and HDG.HousingCatalogObserver:GetRow(itemID) then          -- exception(nullable): non-decor rows delegate to Blizzard
                    HDG.QuantityPicker:Open(itemID)
                elseif orig then
                    orig(self, mouseButton, down)
                end
            end)
        end
    end
end

local function _removeClickOverrides()
    if not MO._origClicks then return end
    for btn, orig in pairs(MO._origClicks) do
        btn:SetScript("OnClick", orig or nil)   -- restore Blizzard's handler (or clear ours)
    end
    MO._origClicks = nil
end

function MO:OnMerchantShow()   MO:ScanNow(); _installClickOverrides() end
function MO:OnMerchantUpdate() if HDG.Store:GetState().session.merchant.open then MO:ScanNow() end end
function MO:OnMerchantClosed()
    _removeClickOverrides()
    A = HDG.Constants.ACTIONS
    HDG.Store:Dispatch({ type = A.MERCHANT_SET_STATE, payload = { open = false } })
end

HDG.Modules:Declare({
    name = "MerchantObserver",
    ownsBlizzardNamespaces = { "C_MerchantFrame" },
    dependencies = {},
    logTags = {
        -- Declared here so the buy queue (Task 4) can log without its own Declare.
        merchant_buy = { user = true, level = "info", duration = 3 },
    },
    blizzardEvents = {
        MERCHANT_SHOW   = { handler = "OnMerchantShow" },
        MERCHANT_UPDATE = { handler = "OnMerchantUpdate", debounce = 0.3 },   -- filter/page changes fire bursts
        MERCHANT_CLOSED = { handler = "OnMerchantClosed" },
        -- Coupon-bought decor lands in BAGS, not decor storage, so the buy queue
        -- has no storage row to wait on. This is its confirmation signal, and it
        -- lives here rather than on BagObserver because that module gates its bag
        -- scan on requiresMainWindow -- and buying at a vendor with the main
        -- window closed is the normal case. Debounced: a purchase fires a burst.
        -- 0.1s, not BagObserver's 0.2: this debounce is the per-item WAIT in a
        -- coupon buy, so it sets the pace of the whole run. Halving it halves the
        -- run without giving up the confirmation.
        BAG_UPDATE      = { handler = "OnBagUpdate", debounce = 0.1 },
    },
    OnMerchantShow   = function(self) MO:OnMerchantShow() end,
    OnMerchantUpdate = function(self) MO:OnMerchantUpdate() end,
    OnMerchantClosed = function(self) MO:OnMerchantClosed() end,
    OnBagUpdate      = function(self) HDG.BuyQueue:_OnBagLanded() end,
})
