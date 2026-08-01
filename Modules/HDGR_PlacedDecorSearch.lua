-- HDG.PlacedDecorSearch
-- ============================================================================
-- Adds a search box to Blizzard's Placed Decor panel
-- (HouseEditorFrame.ExpertDecorModeFrame.PlacedDecorList) so a buried piece can
-- be found and then selected / moved / removed with Blizzard's own controls.
--
-- WHY IT DIMS INSTEAD OF FILTERING -- this is the whole design, do not "improve" it:
--
-- Every addon touch of that panel's DATA or VIEW STATE taints its protected
-- interaction chain. After that, BLIZZARD'S OWN rows fail with
-- ADDON_ACTION_FORBIDDEN on SetPlacedDecorEntryHovered -- blamed on us, though
-- their code made the call. You would trade their working hover/select for search.
-- All three tested live on 12.0.7 (2026-07-26):
--   * ScrollBox:SetDataProvider()          -- replace the provider   -> taints
--   * provider:RemoveAllByPredicate()/Sort -- mutate it in place     -> taints
--     (credit: the DoorSearch addon, which documents testing this)
--   * ScrollBox:ScrollToElementDataIndex() -- pure view movement     -> taints
--
-- So this never touches the DataProvider or ScrollBox API. It walks the RENDERED
-- row buttons and calls SetAlpha + EnableMouse -- plain unprotected Frame methods.
-- The rows keep Blizzard's own element data, so hover, select and remove all keep
-- working. Non-matches stay in place, dimmed and unclickable, rather than
-- disappearing: the list is not shortened, but a match is instantly obvious.
--
-- TECHNIQUE CREDIT: Liberty, author of the DoorSearch addon, who found the
-- dim-instead-of-filter approach and documented the taint testing behind it.
-- Reused here with their express permission (2026-07-26): "1000%, if that method
-- will work on your end, ur welcome to it". Liberty independently hit the same
-- wall we did -- eliminating non-matching rows left the remaining ones
-- unselectable -- which is the same taint we measured from three other angles.
--
-- Written strict here -- no pcall wrappers, unlike DoorSearch. The
-- children of a ScrollTarget and the DecorNameText on Blizzard's row template are
-- guaranteed; if Blizzard renames either we want the error, not silent no-op search.

HDG = HDG or {}
HDG.PlacedDecorSearch = HDG.PlacedDecorSearch or {}
local PDS = HDG.PlacedDecorSearch

-- Own log tag: install/dim activity on a Blizzard frame is exactly what needs a
-- trail when their template changes under us. Not user-facing.
HDG.Log:RegisterTags({ placed_search = { user = false, level = "debug" } })

local DIM_ALPHA  = 0.15
local POLL_EVERY = 0.1    -- ScrollBox recycles rows on scroll; recycled frames keep our alpha

local _query   = ""
local _chrome            -- container: search box + counter (parented to HouseEditorFrame)
local _box               -- the EditBox inside it
local _countFs           -- "Total: n    Found: n"
local _poller

-- ============================================================================
-- Blizzard frame access (reads only)
-- ============================================================================

local function _panel()
    local expert = _G.HouseEditorFrame and _G.HouseEditorFrame.ExpertDecorModeFrame  -- exception(boundary): Blizzard_HouseEditor is load-on-demand
    return expert and expert.PlacedDecorList
end

-- The rendered row buttons. ScrollTarget's children ARE the pooled rows; reading
-- them is free, and SetAlpha/EnableMouse on them is never protected.
local function _rows()
    local p = _panel()
    local target = p and p.ScrollBox and p.ScrollBox.ScrollTarget
    if not target then return nil end
    return { target:GetChildren() }
end

-- Authoritative row count + how many match, straight from Blizzard's provider.
-- Their secure code already paid for GetAllPlacedDecor; reading the result costs
-- nothing and never taints (only writes do).
local function _counts()
    local p = _panel()
    local dp = p and p.ScrollBox and p.ScrollBox:GetDataProvider()
    if not dp then return 0, 0 end
    local total, found = 0, 0
    for _, e in dp:EnumerateEntireRange() do
        total = total + 1
        local name = e.name
        if _query == "" or (name and name:lower():find(_query, 1, true)) then
            found = found + 1
        end
    end
    return total, found
end

local function _refreshCount()
    if not _countFs then return end
    local total, found = _counts()
    if _query == "" then
        _countFs:SetText(("Total: %d"):format(total))
    else
        _countFs:SetText(("Total: %d    Found: %d"):format(total, found))
    end
end

-- ============================================================================
-- Dim pass
-- ============================================================================

local function _applyDim()
    local rows = _rows()
    if not rows then return end
    for _, row in ipairs(rows) do
        -- Blizzard's HouseEditorPlacedDecorEntryTemplate carries DecorNameText.
        -- Pooled-but-unused rows have no elementData and no text yet.
        -- DecorNameText is a real field on Blizzard's
        -- HouseEditorPlacedDecorEntryTemplate that the stub set does not model.
        local fs = row.DecorNameText  ---@diagnostic disable-line: undefined-field
        if fs then
            local name = fs:GetText()
            local matches = _query == ""
                or (name and name:lower():find(_query, 1, true) ~= nil)
            row:SetAlpha(matches and 1 or DIM_ALPHA)
            row:EnableMouse(matches and true or false)
        end
    end
end

-- Rows recycle as the player scrolls and do not reset our alpha, so keep
-- correcting whatever is currently rendered. Only while their panel is open.
local function _startPolling()
    if _poller then _poller:Show() return end
    _poller = CreateFrame("Frame")
    local elapsed = 0
    _poller:SetScript("OnUpdate", function(_, dt)
        elapsed = elapsed + dt
        if elapsed < POLL_EVERY then return end
        elapsed = 0
        local p = _panel()
        local up = p and p:IsShown()
        if _chrome then _chrome:SetShown(up and true or false) end
        if not up then return end
        _applyDim()
        _refreshCount()   -- list changes when decor is placed/removed
    end)
end

-- ============================================================================
-- Search box
-- ============================================================================

local function _createChrome(panel)
    -- NOT a child of the panel: its OnLoad runs ClickToDragMixin, which eats
    -- mouse-down, so a child EditBox never takes focus. Parent to HouseEditorFrame
    -- (visible in edit mode) and merely ANCHOR to the panel. Anchoring across
    -- frames is free; parenting or hooking is not.
    local f = CreateFrame("Frame", "HDGR_PlacedDecorSearchChrome", _G.HouseEditorFrame)
    f:SetPoint("TOPLEFT",  panel.Background, "BOTTOMLEFT",  0, -2)
    f:SetPoint("TOPRIGHT", panel.Background, "BOTTOMRIGHT", 0, -2)
    f:SetHeight(74)   -- room to breathe under the counter
    f:SetFrameStrata("DIALOG")
    f:SetFrameLevel(panel:GetFrameLevel() + 20)

    -- Blizzard's own container art, matching Blizzard_HouseEditorPlacedDecorList.xml
    -- exactly -- same atlas, same -10/+10 overhang -- so this reads as one more
    -- section of their panel rather than an addon window parked underneath it.
    local bg = f:CreateTexture(nil, "BACKGROUND")
    bg:SetAtlas("housing-basic-container")
    bg:SetAllPoints()   -- the frame IS the art now, so no overhang to reproduce

    local box = CreateFrame("EditBox", "HDGR_PlacedDecorSearchBox", f, "SearchBoxTemplate")
    box:SetPoint("TOPLEFT",  f, "TOPLEFT",  16, -14)
    box:SetPoint("TOPRIGHT", f, "TOPRIGHT", -14, -14)
    box:SetHeight(20)
    box:SetAutoFocus(false)
    box:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    box:SetScript("OnTextChanged", function(self, isUserInput)
        _G.SearchBoxTemplate_OnTextChanged(self)
        if not isUserInput then return end
        _query = self:GetText():lower()
        _applyDim()
        _refreshCount()
    end)

    -- GameFontHighlight: the exact font their HeaderText and every row uses.
    local fs = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    fs:SetPoint("TOPLEFT", box, "BOTTOMLEFT", 2, -12)
    fs:SetJustifyH("LEFT")

    -- Provenance. This section is grafted onto a Blizzard panel, so it should be
    -- obvious at a glance which addon put it there -- otherwise a player debugging
    -- their UI has no way to attribute it.
    local logo = f:CreateTexture(nil, "OVERLAY")
    logo:SetTexture("Interface\\AddOns\\HousingDecorGuide\\textures\\Vamoose_HDG_400_trans")
    logo:SetSize(20, 20)
    logo:SetPoint("BOTTOMRIGHT", -12, 10)
    logo:SetAlpha(0.7)

    -- Tooltip on the box: the dim-don't-filter behaviour is surprising unless
    -- explained, and the reason is Blizzard's, not a shortcoming to hide.
    box:HookScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText("Search placed decor", 1, 1, 1)
        GameTooltip:AddLine("Type part of a name. Entries that do not match fade back;"
            .. " matches stay clickable.", 0.9, 0.9, 0.9, true)
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine("The list is faded rather than shortened, because Blizzard does"
            .. " not let addons change what this panel contains.", 0.7, 0.7, 0.7, true)
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine("Added by Housing Decor Guide", 0.4, 0.8, 1)
        GameTooltip:Show()
    end)
    box:HookScript("OnLeave", function() GameTooltip:Hide() end)

    f:Hide()
    _box, _countFs = box, fs
    return f
end

-- Idempotent: safe to call on every editor open.
function PDS:Install()
    local panel = _panel()
    if not panel then return end          -- exception(boundary): editor addon not loaded yet
    if not _chrome then
        _chrome = _createChrome(panel)
        HDG.Log:Debug("placed_search", "search box installed on Blizzard's Placed Decor panel")
    end
    _startPolling()   -- the poller owns chrome visibility from here
end

HDG.Modules:Declare({
    name = "PlacedDecorSearch",
    dependencies = {},
    onEnable = function()
        -- Blizzard_HouseEditor is load-on-demand; the panel only exists once the
        -- player has entered the editor. HouseEditorCompanion already detects that
        -- and calls Install() from its _onEditorShown.
        HDG.Log:Debug("placed_search", "armed -- installs on editor open")
    end,
})
