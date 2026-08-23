-- HDGR_Controller_Pets.lua
-- ============================================================================
-- petRow factory + click wiring for the Pets browser mode of the Decor tab.
--
-- The row's new axis is SIZE: a height and a bar whose reference mark is the
-- player character. There is deliberately NO fit verb. A pet at a water dish
-- (0.263) should tower over it while the same pet in a dog house (2.181) should
-- fit inside, so no single relation word is honest across the host set -- and
-- these are bind-pose heights besides. The bar supplies the ruler; the eye judges.

HDG = HDG or {}
HDG.Controller_Pets = HDG.Controller_Pets or {}
local PetsController = HDG.Controller_Pets

-- Bar geometry. CHARACTER_FRACTION marks the player on the SAME axis
-- pets.items computed barFraction against, so both read Constants rather than
-- each carrying a copy of the denominator.
local BAR_W, BAR_H = 90, 6
local CHARACTER_FRACTION =
    HDG.Constants.PET_CHARACTER_HEIGHT / HDG.Constants.PET_BAR_MAX

-- ===== Row: layout (first paint only) ========================================
local function _layoutPetRow(row)
    local icon = row:CreateTexture(nil, "ARTWORK")
    icon:SetSize(18, 18)
    icon:SetPoint("LEFT", 2, 0)
    row._iconTex = icon

    local name = row:CreateFontString(nil, "OVERLAY")
    HDG.UI.applyFontRole(name, "body")
    name:SetPoint("LEFT", icon, "RIGHT", 6, 0)
    name:SetJustifyH("LEFT")
    HDG.Theme:Register(name, "Text")
    row._nameFs = name

    local height = row:CreateFontString(nil, "OVERLAY")
    HDG.UI.applyFontRole(height, "small")
    height:SetPoint("RIGHT", -4, 0)
    height:SetJustifyH("RIGHT")
    height:SetWidth(34)
    HDG.Theme:Register(height, "TextInfo")
    row._heightFs = height

    -- Track / fill / player mark. InsetBg is the documented trough role;
    -- ProgressBarFill and AccentBar are distinct semantic tokens so the pet's
    -- height and the player's mark never read as the same thing.
    local track = row:CreateTexture(nil, "ARTWORK")
    track:SetSize(BAR_W, BAR_H)
    track:SetPoint("RIGHT", height, "LEFT", -6, 0)
    HDG.Theme:Register(track, "InsetBg")
    row._barTrack = track

    local fill = row:CreateTexture(nil, "OVERLAY")
    fill:SetHeight(BAR_H)
    fill:SetPoint("LEFT", track, "LEFT", 0, 0)
    HDG.Theme:Register(fill, "ProgressBarFill")
    row._barFill = fill

    local mark = row:CreateTexture(nil, "OVERLAY")
    mark:SetSize(1, BAR_H + 2)
    mark:SetPoint("LEFT", track, "LEFT", BAR_W * CHARACTER_FRACTION, 0)
    HDG.Theme:Register(mark, "AccentBar")
    row._barMark = mark

    -- Name fills the gap between icon and bar.
    name:SetPoint("RIGHT", track, "LEFT", -8, 0)

    HDG.TooltipEngine:Attach(row, function(self)
        if not self._tipName then return nil end
        local lines = {}
        if self._tipFamily and self._tipFamily ~= "" then
            lines[#lines + 1] = self._tipFamily
        end
        lines[#lines + 1] = self._tipHeight
            and ("Height %s -- you are %.2f")
                :format(self._tipHeight, HDG.Constants.PET_CHARACTER_HEIGHT)
            or "Size not measured"
        return { title = self._tipName, extraLines = lines }
    end)
end

-- ===== Row: paint (every bind) ===============================================
local function _paintPetRow(row, ed)
    row._iconTex:SetTexture(ed.icon)
    row._nameFs:SetText(ed.displayName)
    row._heightFs:SetText(ed.heightLabel)

    -- A zero-width texture still draws a hairline, so an unmeasured species hides
    -- the fill outright rather than setting width 0.
    if ed.barFraction > 0 then
        row._barFill:SetWidth(BAR_W * ed.barFraction)
        row._barFill:Show()
    else
        row._barFill:Hide()
    end

    row._speciesID = ed.speciesID
    row._tipName   = ed.displayName
    row._tipFamily = ed.familyLabel
    row._tipHeight = ed.heightLabel ~= "" and ed.heightLabel or nil
end

-- ===== Row: clicks ===========================================================
local function _wirePetRowClicks(row, ed)
    local speciesID = ed.speciesID
    row:SetScript("OnClick", function()
        HDG.Store:Dispatch({
            type    = HDG.Constants.ACTIONS.UI_SET_TRANSIENT,
            payload = { view = "decor", key = "selectedSpeciesID", value = speciesID },
        })
    end)
end

-- ===== Row: reset ============================================================
local function _resetPetRow(row)
    row._speciesID = nil
    row._tipName, row._tipFamily, row._tipHeight = nil, nil, nil
    -- Strict: _layoutPetRow creates both unconditionally and every row reaching Reset
    -- has been through it. Guarding here would swallow a rename instead of surfacing it.
    row._iconTex:SetTexture(nil)
    row._barFill:Hide()
end

HDG.Rows:Register("petRow", {
    font    = "body",
    height  = 24,
    factory = HDG.UI.MakeRowFactory({
        layout     = _layoutPetRow,
        paint      = _paintPetRow,
        laidOutTag = "_petLaidOut",
        selectable = true,
        clicks     = "LeftButtonUp",
        wire       = _wirePetRowClicks,
        resetText  = { "_nameFs", "_heightFs" },
        reset      = _resetPetRow,
    }),
    -- One row per species: a player can own several of the same pet, but they are
    -- the same size and the same picture, so the list shows one.
    key     = function(ed) return ed.speciesID end,
})

-- ===== Controller ============================================================
-- The contract is Wire AND Refresh: Controllers:RefreshAll calls Refresh on every
-- registered controller with no guard (HDGR_Controllers.lua:58), so a controller
-- missing either one takes down the whole refresh pass.
--
-- The search box writes the SAME transient the decor search does, so flipping to
-- Pets mid-search keeps what you typed -- which is what you want, because the
-- thing you were looking for is often in both lists.
function PetsController:Wire(rootFrame)
    HDG.UI.WireSearchBox(rootFrame, "petPanel.search", "decor", "searchQuery")

    -- Summon / Dismiss. Read the LATCHED summon state, not the live API: after a
    -- summon GetSummonedPetGUID reads nil for up to 1.5s, so deciding here from the
    -- live call would toggle the wrong way. The observer latches on
    -- COMPANION_UPDATE and the selector reports it.
    --
    -- AND NO REFRESH AFTER THE CLICK. COMPANION_UPDATE fires in the same frame
    -- carrying the new state -- VPP measured this with /vppr summonprobe -- so
    -- repainting here would paint the state we are leaving. The dispatch that the
    -- observer raises is what repaints the button.
    HDG.UI.OnClick(rootFrame, "petDetailPanel.summonBtn", function()
        local state = HDG.Store:GetState()
        local petID = HDG.Selectors:Call("pets.selectedPetID", state, {})
        if not petID then return end
        if HDG.Selectors:Call("pets.isSelectedSummoned", state, {}) then
            HDG.PetObserver:Dismiss()
        else
            HDG.PetObserver:Summon(petID)
        end
    end)
end

function PetsController:Refresh(_rootFrame, _ctx)
    -- Bindings handle paint; nothing imperative.
end

HDG.Controllers:Register("pets", PetsController)
