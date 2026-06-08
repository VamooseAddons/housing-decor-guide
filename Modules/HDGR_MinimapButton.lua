-- HDGR_MinimapButton.lua
-- ============================================================================
-- LibDBIcon minimap button + AddonCompartment hooks.
-- LibDBIcon owns positioning/dragging; we control show/hide via config flags.
-- showCompartment gates our click/enter handlers only; TOC always registers
-- the compartment icon (Blizzard limitation -- user hides via Edit Mode).

HDG = HDG or {}
HDG.MinimapButton = HDG.MinimapButton or {}
local MB = HDG.MinimapButton

local ADDON_KEY  = "HousingDecorGuideR"
local ICON_PATH  = "Interface/AddOns/HousingDecorGuide/textures/HousingDecorIcon"

-- LibStub references resolved at onEnable time (libs loaded by TOC ordering).
local _ldb    -- LibDataBroker-1.1 object
local _dbicon -- LibDBIcon-1.0 object
local _launcher

-- ===== Visibility logic ======================================================

local function _applyVisibility()
    if not (_dbicon and _dbicon:IsRegistered(ADDON_KEY)) then return end
    -- Single flag, toggled by both the Settings-panel checkbox and /hdgr minimap.
    local show = HDG.Config:Get("SHOW_MINIMAP_BUTTON")
    -- exception(boundary): minimapPos.hide is LibDBIcon's contract; syncing .hide here is
    -- the external-library handshake, not an HDG-state mutation (ADR-006).
    HDG.Store:GetState().account.config.minimapPos.hide = not show
    if show then _dbicon:Show(ADDON_KEY) else _dbicon:Hide(ADDON_KEY) end
end

-- ===== Right-click context menu =============================================
-- Quick toggles for standalone windows (Store as SSoT via dispatch).
local function _showContextMenu(owner)
    MenuUtil.CreateContextMenu(owner, function(_, root)
        root:CreateTitle("Housing Decor Guide")
        root:CreateButton("Shopping List", function()
            HDG.Store:Dispatch({ type = HDG.Constants.ACTIONS.SHOPPING_WIDGET_TOGGLE })
        end)
        root:CreateButton("Zone Scanner", function()
            HDG.Store:Dispatch({ type = HDG.Constants.ACTIONS.ZONE_POPUP_TOGGLE })
        end)
        root:CreateButton("Lumber Tracker", function()
            HDG.Store:Dispatch({ type = HDG.Constants.ACTIONS.LUMBER_WINDOW_TOGGLE })
        end)
    end)
end

-- ===== Init ==================================================================

function MB:Init()
    if not LibStub then return end                              -- exception(boundary): LibStub absent

    local LDB = LibStub("LibDataBroker-1.1", true)
    if not LDB then return end                                  -- exception(boundary): lib absent

    _launcher = LDB:NewDataObject(ADDON_KEY, {
        type  = "launcher",
        icon  = ICON_PATH,
        label = "Housing Decor Guide",
        OnClick = function(self, button)
            if button == "LeftButton" then
                HDG.Store:Dispatch({ type = HDG.Constants.ACTIONS.MAIN_WINDOW_TOGGLE })
            elseif button == "RightButton" then
                _showContextMenu(self)
            end
        end,
        OnTooltipShow = function(tooltip)
            tooltip:AddLine(HDG.Theme:ColorCode("semantic.accent") .. "Housing Decor Guide|r")
            tooltip:AddLine("Left-click: Toggle window", 0.7, 0.7, 0.7)
            tooltip:AddLine("Right-click: Menu", 0.7, 0.7, 0.7)
            tooltip:AddLine("Drag: Move button", 0.7, 0.7, 0.7)
        end,
    })

    local DBIcon = LibStub("LibDBIcon-1.0", true)
    if not DBIcon then return end                               -- exception(boundary): lib absent
    _dbicon = DBIcon

    -- Point LibDBIcon at account.config.minimapPos so position survives /reload.
    local cfg = HDG.Store:GetState().account.config  -- minimapPos seeded in NewConfig

    DBIcon:Register(ADDON_KEY, _launcher, cfg.minimapPos)

    _applyVisibility()
end

-- ===== Module registration ===================================================
HDG.Modules:Declare({
    name         = "MinimapButton",
    dependencies = {},
    onEnable     = function()
        MB:Init()

        -- Subscribe to both visibility config flags.
        local watched = { "account.config.showMinimapButton" }
        HDG.Store:Subscribe(function(_, invalidation)
            if HDG.Paths.MatchesAny(watched, invalidation) then _applyVisibility() end
        end)
    end,
})

-- ============================================================================
-- ADDON COMPARTMENT (referenced by TOC AddonCompartmentFunc directives)
-- Blizzard always shows the icon in the compartment drawer regardless of
-- config (cannot be hidden via API -- Edit Mode is the only user mechanism).
-- These handlers no-op when account.config.showCompartment == false.
-- ============================================================================

function HDGR_OnAddonCompartmentClick(_, buttonName)
    if HDG.Config:Get("SHOW_COMPARTMENT") == false then return end
    if buttonName == "LeftButton" then
        HDG.Store:Dispatch({ type = HDG.Constants.ACTIONS.MAIN_WINDOW_TOGGLE })
    end
end

function HDGR_OnAddonCompartmentEnter(_, menuItem)
    if HDG.Config:Get("SHOW_COMPARTMENT") == false then return end
    GameTooltip:SetOwner(menuItem, "ANCHOR_RIGHT")
    GameTooltip:AddLine(HDG.Theme:ColorCode("semantic.accent") .. "Housing Decor Guide|r", 1, 1, 1)
    GameTooltip:AddLine("Track and craft housing decor items", 0.7, 0.7, 0.7)
    GameTooltip:AddLine(" ")
    GameTooltip:AddLine("|cFFFFFFFFClick:|r Toggle window", 0.7, 0.7, 0.7)
    GameTooltip:Show()
end

function HDGR_OnAddonCompartmentLeave()
    GameTooltip:Hide()
end
