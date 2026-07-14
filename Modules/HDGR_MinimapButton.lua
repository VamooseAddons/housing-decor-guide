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
local ICON_PATH  = "Interface/AddOns/HousingDecorGuide/textures/Vamoose_HDG_400_trans"

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

-- LibDBIcon wraps the icon in the minimap tracking-border ring (file 136430) plus
-- a round background (136467), and circle-crops the icon via UpdateCoord. Strip
-- both textures and drop the crop so just the emblem shows -- no button frame.
-- They're locals inside the lib's createButton, so find them by file id.
local function _stripBorder()
    local button = _dbicon:GetMinimapButton(ADDON_KEY)
    if not button then return end   -- exception(boundary): LibDBIcon button not built
    for _, region in ipairs({ button:GetRegions() }) do
        if region:IsObjectType("Texture") then
            local tex = region:GetTexture()
            if tex == 136430 or tex == 136467 then region:Hide() end  -- TrackingBorder + Background
        end
    end
    local icon = button.icon
    icon.UpdateCoord = function(self) self:SetTexCoord(0, 1, 0, 1) end  -- emblem is round; no crop
    icon:UpdateCoord()
    icon:SetSize(28, 28)                                                -- fill the button (no frame to inset for)
end

-- ===== Position recovery =====================================================
-- Reseed the button's angle to a known, visible default. Removes the nil-angle
-- state (LibDBIcon then falls back to its 225-deg lower-left default) that a
-- SavedVariables loss -- e.g. an unclean client exit that never flushed HDG_DB
-- -- can leave behind. Writes the persisted config table AND the live LibDBIcon
-- db (same table in the normal case; set both so a divergence can't leave one
-- stale), then re-show + reposition via _applyVisibility. NOT LibDBIcon Refresh:
-- Refresh obeys the button's stored .hide flag, which reads stale-true under a
-- db/config divergence and hides a button the user just asked to reposition.
-- Exposed for the Settings "reset" button.
local DEFAULT_ANGLE = 45  -- upper-right; clear of the crowded lower-left cluster
function MB:ResetPosition()
    if not (_dbicon and _dbicon:IsRegistered(ADDON_KEY)) then return end  -- exception(boundary): LibDBIcon not up yet
    HDG.Store:GetState().account.config.minimapPos.minimapPos = DEFAULT_ANGLE  -- exception(boundary): LibDBIcon position field (ADR-006)
    local button = _dbicon:GetMinimapButton(ADDON_KEY)
    if button then button.db.minimapPos = DEFAULT_ANGLE end  -- exception(boundary): live db may diverge from the config ref after an SV reload
    _applyVisibility()   -- unconditional Show + reposition; re-asserts the shown state
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
    _stripBorder()

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
