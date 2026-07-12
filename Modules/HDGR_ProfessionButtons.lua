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

local ICON_HDG    = "Interface\\AddOns\\HousingDecorGuide\\textures\\Vamoose_HDG_400_trans"
local ICON_FILTER = "housing-decor-vendor_32"

local function _createButton(name, parent, frameType, icon, isAtlas)
    local btn = CreateFrame(frameType, name, parent)
    btn:SetSize(22, 22)
    btn:SetFrameStrata("HIGH")  -- ProfessionsFrame chrome renders at HIGH; inherited strata leaves buttons occluded
    btn:SetFrameLevel(500)
    btn.icon = btn:CreateTexture(nil, "ARTWORK")
    btn.icon:SetAllPoints()
    if isAtlas then btn.icon:SetAtlas(icon) else btn.icon:SetTexture(icon) end
    btn:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
    return btn
end

local function _applyFilterState()
    _filterBtn:SetChecked(_filterActive) -- persistent glow while the decor filter is applied
end

-- ===== Create (called once Blizzard_Professions is loaded) ===================

local function _createButtons()
    if _decorBtn then return end -- idempotent
    if HDG.Config:Get("SHOW_PROFESSION_BUTTONS") == false then return end
    local parent = _G.ProfessionsFrame
    if not parent then return end

    -- "Decor Guide" button: opens HDG main window
    _decorBtn = _createButton("HDGR_ProfessionDecorBtn", parent, "Button", ICON_HDG, false)
    _decorBtn:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -110, -1)
    _decorBtn:SetScript("OnClick", function()
        HDG.Store:Dispatch({ type = HDG.Constants.ACTIONS.MAIN_WINDOW_TOGGLE })
    end)
    _decorBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOMRIGHT")
        GameTooltip:AddLine(HDG.Theme:ColorCode("semantic.warning") .. "Open Decor Guide|r")
        GameTooltip:AddLine("View housing decor for your professions.", 0.7, 0.7, 0.7)
        GameTooltip:Show()
    end)
    _decorBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)

    -- "Filter Decor" button: filters recipe list to House Decor items.
    -- CheckButton so the active filter reads as a persistent glow.
    _filterBtn = _createButton("HDGR_ProfessionFilterBtn", parent, "CheckButton", ICON_FILTER, true)
    _filterBtn:SetPoint("RIGHT", _decorBtn, "LEFT", -4, 0)
    _filterBtn:SetCheckedTexture("Interface\\Buttons\\CheckButtonHilight")
    _filterBtn:GetCheckedTexture():SetBlendMode("ADD")
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
        end
        _applyFilterState() -- outside the guard: CheckButton self-toggles on click, resync to _filterActive
    end)
    _filterBtn:SetScript("OnEnter", function(self)
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
    _filterBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)

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
