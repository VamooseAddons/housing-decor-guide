-- HDG.MenagerieController
-- ============================================================================
-- The Menagerie (House > Pets): thin glue. Every gesture is one UI_SET_TRANSIENT
-- (view="menagerie") -- zero feature actions by design. The two sanctioned
-- imperative moments live here (plan section 6): playing a phase / voice on the
-- scene widget, and (phase 5) capturing the room query. Cell kinds for every
-- chip strip and the menagerieRow factory also live here, per house pattern.

HDG = HDG or {}
HDG.MenagerieController = HDG.MenagerieController or {}
local C = HDG.MenagerieController

local A = HDG.Constants.ACTIONS
local _root   -- stamped by Wire(); the scene-widget lookup needs it at click time

local function _set(key, value)
    HDG.Store:Dispatch({ type = A.UI_SET_TRANSIENT,
        payload = { view = "menagerie", key = key, value = value } })
end

local function _ui()
    return HDG.Store:GetState().session.ui.menagerie  -- exception(false-positive): top-level controller read, not a row factory
end

local function _stage()
    return _root and HDG.UI.W(_root, "menagerieDetailPanel.stage")
end

-- ===== chip cell kind: every plain chip strip ===============================
-- One kind serves mode / axes / axis values / spot rows / scene strip / also --
-- the item's fields say which dispatch it is. Immutable table rebuilds for the
-- spot group (RMW discipline: build next value, then dispatch).
local function _chipClick(item)
    if item.group == "wants" then
        local spot, wants = _ui().spot, {}
        for k in pairs(_ui().spot.wants) do wants[k] = true end
        if wants[item.value] then wants[item.value] = nil else wants[item.value] = true end
        _set("spot", { surface = spot.surface, size = spot.size, wants = wants })
    elseif item.group == "surface" or item.group == "size" then
        local spot = _ui().spot
        local next_ = { surface = spot.surface, size = spot.size, wants = spot.wants }
        next_[item.group] = item.value
        _set("spot", next_)
    elseif item.value == "byPet" or item.value == "bySpot" then
        _set("mode", item.value)
    elseif item.animID then                       -- "Also knows" chip: play, not state
        local stage = _stage()
        if stage then stage:PlayPhase(item.animID, 0) end
    elseif item.value == "you" then               -- scene strip toggle
        local scene = _ui().scene
        _set("scene", { decorID = scene.decorID, withYou = not scene.withYou })
    elseif item.value == "none" or type(item.value) == "number" and item.label ~= nil
           and HDG.StaticData.PetFacts:SceneDecor()[item.value] then
        local scene = _ui().scene
        _set("scene", { decorID = item.value ~= "none" and item.value or nil,
                        withYou = scene.withYou })
    elseif item.group == nil and type(item.value) == "string" and item.count == nil
           and (item.value == "kind" or item.value == "clade"
                or item.value == "family" or item.value == "size") then
        _set("axis", item.value); _set("axval", "all")
    else                                          -- axis VALUE chip
        _set("axval", item.value)
    end
end

local function _chipLabel(item)
    if item.count then return (item.label or "?") .. " (" .. item.count .. ")" end
    return item.label or "?"
end

HDG.ChipStrip:RegisterCellKind("menagerieChip", {
    constructor = function(parent, cfg)
        return HDG.ChipStrip:DefaultChipConstructor(parent, cfg)
    end,
    binder = function(chip, item, cfg)
        if not item then chip:Hide(); chip:SetScript("OnClick", nil); return end
        HDG.UI:EnsureChipChrome(chip)
        chip:Show()
        chip:SetText(_chipLabel(item))
        HDG.Theme:Register(chip, "Button", { variant = "chip", active = item.active == true })
        chip:RegisterForClicks("LeftButtonUp")
        chip:SetScript("OnClick", function() _chipClick(item) end)
    end,
    sizer = function(item, cfg)
        return HDG.ChipStrip:DefaultChipSizer({ label = _chipLabel(item) }, cfg)
    end,
})

-- ===== flow node cell kind ==================================================
-- The behaviour flowchart's nodes (ruling 10): "label  NN% - N.Ns" for phases,
-- "word -- cadence" for the voice. Unverified labels carry the amber "?".
-- Clicking a phase drives the scene actor; clicking the voice plays a kit.
local function _flowLabel(item)
    if item.nodeType == "voice" then
        return (item.label or "sound") .. " sounds -- " .. (item.cadence or "")
    end
    local txt = string.format("%s  %d%% - %.1fs", item.label, item.pct or 0, item.seconds or 0)
    if item.unverified then txt = txt .. " ?" end
    return txt
end

HDG.ChipStrip:RegisterCellKind("menagerieFlowNode", {
    constructor = function(parent, cfg)
        return HDG.ChipStrip:DefaultChipConstructor(parent, cfg)
    end,
    binder = function(chip, item, cfg)
        if not item then chip:Hide(); chip:SetScript("OnClick", nil); return end
        HDG.UI:EnsureChipChrome(chip)
        chip:Show()
        chip:SetText(_flowLabel(item))
        HDG.Theme:Register(chip, "Button",
            { variant = "chip", active = item.nodeType == "voice" })
        chip:RegisterForClicks("LeftButtonUp")
        chip:SetScript("OnClick", function()
            if item.nodeType == "voice" then
                -- Imperative moment: playing is not state. PlaySound takes the
                -- kit id directly; first kit is the canonical sample.
                if item.kits and item.kits[1] then
                    pcall(PlaySound, item.kits[1])  -- exception(boundary): kit may be invalid on this client build
                end
            else
                local stage = _stage()
                if stage then stage:PlayPhase(item.animID, item.variation) end
            end
        end)
    end,
    sizer = function(item, cfg)
        return HDG.ChipStrip:DefaultChipSizer({ label = _flowLabel(item) }, cfg)
    end,
})

-- ===== menagerieRow =========================================================
-- Name + kind ONLY (ruling 13: scale lives in the scene, not on rows). The
-- why-line appears under a room query, naming the matched motif.
local function _layoutMenagerieRow(row)
    local name = row:CreateFontString(nil, "OVERLAY")
    HDG.UI.applyFontRole(name, "body")
    name:SetPoint("LEFT", 6, 0)
    name:SetJustifyH("LEFT")
    HDG.Theme:Register(name, "Text")
    row._nameFs = name

    local kind = row:CreateFontString(nil, "OVERLAY")
    HDG.UI.applyFontRole(kind, "small")
    kind:SetPoint("RIGHT", -6, 0)
    kind:SetJustifyH("RIGHT")
    HDG.Theme:Register(kind, "TextInfo")
    row._kindFs = kind

    name:SetPoint("RIGHT", kind, "LEFT", -8, 0)
end

local function _paintMenagerieRow(row, ed)
    row._nameFs:SetText(ed.name)
    local k = ed.kindLabel
    if ed.why then k = ed.why .. "  " .. k end
    row._kindFs:SetText(k)
    row._speciesID = ed.speciesID
end

local function _wireMenagerieRowClicks(row, ed)
    local speciesID = ed.speciesID
    row:SetScript("OnClick", function()
        HDG.Store:Dispatch({ type = A.UI_SET_TRANSIENT,
            payload = { view = "menagerie", key = "selectedSpeciesID", value = speciesID } })
    end)
end

local function _resetMenagerieRow(row)
    row._speciesID = nil
end

HDG.Rows:Register("menagerieRow", {
    font    = "body",
    height  = 22,
    key     = function(ed) return "sp" .. ed.speciesID end,
    factory = HDG.UI.MakeRowFactory({
        layout     = _layoutMenagerieRow,
        paint      = _paintMenagerieRow,
        laidOutTag = "_menagerieLaidOut",
        selectable = true,
        clicks     = "LeftButtonUp",
        wire       = _wireMenagerieRowClicks,
        resetText  = { "_nameFs", "_kindFs" },
        reset      = _resetMenagerieRow,
    }),
})

-- ===== Wire =================================================================
function C:Wire(rootFrame)
    _root = rootFrame
    -- Everything is chips and rows; their handlers are wired in the binders
    -- above. The room-query button ("Pets for this room") arrives with the
    -- Styles-join session (plan phase 5) -- deliberately absent, not hidden.
end

function C:Refresh(_rootFrame, _ctx)
    -- Bindings handle paint; nothing imperative. Required by the Controllers
    -- registry contract (RefreshAll calls every controller unconditionally).
end

HDG.Controllers:Register("menagerie", C)
