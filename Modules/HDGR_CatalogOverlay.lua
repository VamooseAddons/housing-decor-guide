-- HDGR_CatalogOverlay.lua
-- ============================================================================
-- Marks UNCOLLECTED decor in Blizzard's Housing catalog grid with a small red
-- plus in the top-right corner of the cell -- the collection gaps in your own
-- browser. Companion to the catalog tooltip (which adds sourcing on hover).
--
-- Why this isn't redundant with Blizzard's corner number: that number is the
-- *storage* count only. A decor you own but have PLACED shows no number (Total
-- Owned 1 / Placed 1 / Storage 0), so "no number" does NOT mean uncollected.
-- HDG's IsOwned (placed + stored + redeemable) is the correct signal, so the
-- plus lands only on decor you genuinely don't have yet.
--
-- Surface: Blizzard_HousingTemplates' HousingCatalogDecorEntryMixin (loads on
-- demand when the catalog opens). Hooks UpdateTypeSpecificVisuals -- the decor
-- cell's own per-cell paint, the SAME method Blizzard uses to toggle the dye
-- palette badge (CustomizeIcon), so it fires reliably for every decor cell. Reads
-- ownership from the catalog observer. Gated by CATALOG_DECOR_OVERLAY.

HDG = HDG or {}

local CO = {}
HDG.CatalogOverlay = CO

local MARK_SIZE    = 14
local ATLAS_NEEDED = "common-icon-plus"

-- Live cells seen via the hook, so a catalog-ready / counts dispatch can repaint
-- the ones already on screen (they won't re-fire UpdateVisuals on their own).
-- Pooled Blizzard frames -> bounded set, reused across scrolls.
local _cells = {}

local function enabled()
    return HDG.Config:Get("CATALOG_DECOR_OVERLAY") == true
end

-- True only for a decor cell whose item HDG knows AND the player has not
-- collected. GetRow is nil while the catalog is still loading, so an unwarmed
-- catalog marks nothing rather than wrongly flagging owned decor as needed.
local function _needsMark(cell)
    local vid = cell.entryVariantID
    local recordID = vid and vid.recordID
    if not recordID then return false end
    local Obs    = HDG.HousingCatalogObserver
    local itemID = Obs:GetItemIDByDecorID(recordID)
    if not itemID then return false end
    local row = Obs:GetRow(itemID)
    if not row then return false end
    return not row.isOwned
end
CO._needsMark = _needsMark   -- exposed for tests

local function _ensureMark(cell)
    local mark = cell._hdgrCatalogMark
    if not mark then
        mark = cell:CreateTexture(nil, "OVERLAY", nil, 7)   -- above icon/border/count
        mark:SetSize(MARK_SIZE, MARK_SIZE)
        mark:SetPoint("TOPRIGHT", cell, "TOPRIGHT", 1, 1)
        mark:SetAtlas(ATLAS_NEEDED, false)
        mark:SetVertexColor(1, 0.10, 0.10)   -- red (gold plus tints to red, pops vs the gold UI)
        cell._hdgrCatalogMark = mark
    end
    return mark
end

local function _paint(cell)
    if enabled() and _needsMark(cell) then
        _ensureMark(cell):Show()
    elseif cell._hdgrCatalogMark then
        cell._hdgrCatalogMark:Hide()
    end
end

local function _onCellPaint(cell)
    _cells[cell] = true
    _paint(cell)
end

function CO:RepaintAll()
    for cell in pairs(_cells) do _paint(cell) end
end

function CO:Install()
    if self._installed then return end
    if not (HousingCatalogDecorEntryMixin and HousingCatalogDecorEntryMixin.UpdateTypeSpecificVisuals) then return end
    self._installed = true
    hooksecurefunc(HousingCatalogDecorEntryMixin, "UpdateTypeSpecificVisuals", _onCellPaint)
    -- Warm the catalog so the plus shows without opening the HDG window first
    -- (idempotent cold-start, no-op unless idle).
    if enabled() then HDG.HousingCatalogObserver:RequestLoad() end
end

HDG.Modules:Declare({
    name = "CatalogOverlay",
    dependencies = {},
    onEnable = function()
        -- HousingCatalogDecorEntryMixin lives in Blizzard_HousingTemplates, loaded
        -- on demand when the catalog first opens. Install once it's present (the
        -- cell template is in that addon, so the hook always beats cell creation).
        HDG.BlizzardEvents:_internalSubscribe("ADDON_LOADED", function()
            CO:Install()
        end)
        if HousingCatalogDecorEntryMixin then CO:Install() end   -- already loaded

        -- Live refresh: repaint on-screen cells the instant a decor is collected
        -- (or when the first sweep lands), so the plus clears without scrolling.
        local A = HDG.Constants.ACTIONS
        CO._storeToken = HDG.Store:Subscribe(function(actionType)
            if actionType == A.COLLECTION_CATALOG_ROW_COUNTS_UPDATED
               or actionType == A.DECOR_CATALOG_READY then
                CO:RepaintAll()
            end
        end)
    end,
    onShutdown = function()
        if CO._storeToken then
            HDG.Store:Unsubscribe(CO._storeToken)
            CO._storeToken = nil
        end
    end,
})
