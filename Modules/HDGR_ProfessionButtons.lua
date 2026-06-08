-- HDGR_ProfessionButtons.lua
-- ============================================================================
-- Injects two buttons into ProfessionsFrame:
--   "Decor Guide"  -- opens the HDG main window
--   "Filter Decor" -- calls C_TradeSkillUI.SetRecipeItemNameFilter to narrow
--                     recipes to "House Decor" items; click again to clear.
--
-- Gate: account.config.showProfessionButtons. False = hidden; not created.
--
-- Lifecycle: Blizzard_Professions loads on demand; listen for ADDON_LOADED,
-- then hook ProfessionsFrame.OnShow for per-open updates. Store subscriber
-- applies visibility changes to already-created buttons.

HDG = HDG or {}
HDG.ProfessionButtons = HDG.ProfessionButtons or {}
local PB = HDG.ProfessionButtons

local _decorBtn  -- "Decor Guide" button
local _filterBtn -- "Filter Decor" button
local _filterActive = false

-- ===== Button factory ========================================================

local function _createButton(name, parent, width, label)
    local btn = CreateFrame("Button", name, parent, "BackdropTemplate")
    btn:SetSize(width, 22)
    btn:SetBackdrop({
        bgFile   = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
    })
    local c = HDG.Theme:GetColor("semantic.accent")
    btn:SetBackdropColor(c.r, c.g, c.b, 0.9)
    btn:SetBackdropBorderColor(c.r, c.g, c.b, 1)
    btn.text = btn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    btn.text:SetAllPoints()
    btn.text:SetText(label)
    return btn
end

local function _applyFilterState()
    if not _filterBtn then return end
    if _filterActive then
        _filterBtn.text:SetText(HDG.Theme:ColorCode("semantic.warning") .. "Filter Decor|r")
    else
        _filterBtn.text:SetText("Filter Decor")
    end
end

-- ===== Create (called once Blizzard_Professions is loaded) ===================

local function _createButtons()
    if _decorBtn then return end -- idempotent
    if HDG.Config:Get("SHOW_PROFESSION_BUTTONS") == false then return end
    local parent = _G.ProfessionsFrame
    if not parent then return end

    -- "Decor Guide" button: opens HDG main window
    _decorBtn = _createButton("HDGR_ProfessionDecorBtn", parent, 90, "Decor Guide")
    _decorBtn:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -110, -1)
    _decorBtn:SetScript("OnClick", function()
        HDG.Store:Dispatch({ type = HDG.Constants.ACTIONS.MAIN_WINDOW_TOGGLE })
    end)
    _decorBtn:SetScript("OnEnter", function(self)
        local c = HDG.Theme:GetColor("semantic.accent")
        self:SetBackdropColor(c.r * 1.3, c.g * 1.3, c.b * 1.3, 1)
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOMRIGHT")
        GameTooltip:AddLine(HDG.Theme:ColorCode("semantic.warning") .. "Open Decor Guide|r")
        GameTooltip:AddLine("View housing decor for your professions.", 0.7, 0.7, 0.7)
        GameTooltip:Show()
    end)
    _decorBtn:SetScript("OnLeave", function(self)
        local c = HDG.Theme:GetColor("semantic.accent")
        self:SetBackdropColor(c.r, c.g, c.b, 0.9)
        GameTooltip:Hide()
    end)

    -- "Filter Decor" button: filters recipe list to House Decor items
    _filterBtn = _createButton("HDGR_ProfessionFilterBtn", parent, 85, "Filter Decor")
    _filterBtn:SetPoint("RIGHT", _decorBtn, "LEFT", -4, 0)
    _filterBtn:SetScript("OnClick", function()
        local CT = _G.C_TradeSkillUI
        if CT and CT.SetRecipeItemNameFilter then                -- exception(boundary): Blizz API
            if _filterActive then
                CT.SetRecipeItemNameFilter("")
                _filterActive = false
            else
                CT.SetRecipeItemNameFilter("House Decor")
                _filterActive = true
            end
            _applyFilterState()
        end
    end)
    _filterBtn:SetScript("OnEnter", function(self)
        if not _filterActive then
            local c = HDG.Theme:GetColor("semantic.accent")
            self:SetBackdropColor(c.r * 1.3, c.g * 1.3, c.b * 1.3, 1)
        end
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOMRIGHT")
        if _filterActive then
            GameTooltip:AddLine(HDG.Theme:ColorCode("semantic.warning") .. "Clear Filter|r")
            GameTooltip:AddLine("Click to show all recipes again.", 0.7, 0.7, 0.7)
        else
            GameTooltip:AddLine(HDG.Theme:ColorCode("semantic.warning") .. "Filter House Decor|r")
            GameTooltip:AddLine("Narrow recipe list to house decor items.", 0.7, 0.7, 0.7)
        end
        GameTooltip:Show()
    end)
    _filterBtn:SetScript("OnLeave", function(self)
        _applyFilterState()
        if not _filterActive then
            local c = HDG.Theme:GetColor("semantic.accent")
            self:SetBackdropColor(c.r, c.g, c.b, 0.9)
        end
        GameTooltip:Hide()
    end)

    -- Per-open hook: reset filter state, re-gate on config.
    parent:HookScript("OnShow", function()
        _filterActive = false
        _applyFilterState()
        PB:ApplyVisibility()
    end)
end

-- ===== Visibility ============================================================

function PB:ApplyVisibility()
    local show = HDG.Config:Get("SHOW_PROFESSION_BUTTONS")
    if _decorBtn  then if show then _decorBtn:Show()  else _decorBtn:Hide()  end end
    if _filterBtn then if show then _filterBtn:Show() else _filterBtn:Hide() end end
end

-- ===== Module registration ===================================================
HDG.Modules:Declare({
    name         = "ProfessionButtons",
    dependencies = {},
    onEnable     = function()
        HDG.BlizzardEvents:_internalSubscribe("ADDON_LOADED", function(name)
            if name == "Blizzard_Professions" then _createButtons() end
        end)
        -- TRADE_SKILL_SHOW catches the case where Blizzard_Professions loaded
        -- before onEnable ran (belt-and-suspenders).
        HDG.BlizzardEvents:_internalSubscribe("TRADE_SKILL_SHOW", function()
            if _G.ProfessionsFrame then _createButtons() end
        end)

        -- Live config subscriber: gate existing buttons without recreating.
        HDG.Store:Subscribe(function(_, invalidation)
            if HDG.Paths.MatchesAny({ "account.config.showProfessionButtons" }, invalidation) then
                PB:ApplyVisibility()
            end
        end)
    end,
})
