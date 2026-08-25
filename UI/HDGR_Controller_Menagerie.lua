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
local _voiceCycle = {}   -- per-voice click cycle (keyed by first kit id); session-local, not state

-- Sound-bar affordance: a thin accent line along the chip's bottom fills over
-- the clip's baked length (OGG durations from the sound pipeline; PlaySound
-- picks a random entry inside the kit, so the length is that kit's weighted
-- mean -- an affordance, not a promise). OnUpdate only runs WHILE playing.
local function _sndTick(chip)
    local frac = (GetTime() - chip._sndStart) / chip._sndDur
    if frac >= 1 then
        chip._sndFill:Hide()
        chip:SetScript("OnUpdate", nil)
        return
    end
    chip._sndFill:SetWidth(math.max(1, (chip:GetWidth() - 8) * frac))
end

local function _startSoundBar(chip, dur)
    if not chip._sndFill then
        local fill = chip:CreateTexture(nil, "OVERLAY")
        fill:SetColorTexture(1, 1, 1, 1)   -- white base; painted from the theme token per play (accentBar pattern)
        fill:SetHeight(2)
        fill:SetPoint("BOTTOMLEFT", 4, 2)
        chip._sndFill = fill
    end
    local accent = HDG.Theme:GetColor("semantic.accent")
    chip._sndFill:SetVertexColor(accent.r, accent.g, accent.b, 0.9)
    chip._sndFill:SetWidth(1)
    chip._sndFill:Show()
    chip._sndStart, chip._sndDur = GetTime(), dur
    chip:SetScript("OnUpdate", _sndTick)
end

local function _stopSoundBar(chip)
    if chip._sndFill then chip._sndFill:Hide() end
    chip:SetScript("OnUpdate", nil)
end

local function _set(key, value)
    HDG.Store:Dispatch({ type = A.UI_SET_TRANSIENT,
        payload = { view = "menagerie", key = key, value = value } })
end

local function _ui()
    return HDG.Store:GetState().session.ui.menagerie  -- exception(false-positive): top-level controller read, not a row factory
end

-- Resolved at CLICK time, not Wire time: the card has two hosts and the active
-- view names whose stage this click drives. HDG.UI:PetStage is the one answer.
local function _stage() return HDG.UI:PetStage() end

-- ===== "Pets for this room" =================================================
-- The sanctioned imperative moment (plan section 6): on click, read the room
-- HERE -- current area's placed decor votes through its FacetDB mood facets --
-- and dispatch the RESULT as a snapshot. Selectors stay pure; the capture is
-- deliberately a snapshot, labeled, so staleness is visible rather than silent.
local function _captureRoom()
    local state = HDG.Store:GetState()
    if state.session.ui.menagerie.roomQuery then
        _set("roomQuery", nil)
        return
    end
    local area = state.session.styles.currentArea
    local counts = {}
    for _, entry in pairs(state.session.styles.placedDecor) do
        if entry.areaID == area and entry.itemID then
            local f = HDG.StaticData.Facets:Get(entry.itemID)  -- exception(nullable): unfaceted decor casts no vote
            local mods = f and f.mod
            if mods then
                for _, moodID in ipairs(mods) do
                    local motif = HDG.Constants.MENAGERIE.MOOD_MOTIFS[moodID]
                    if motif then counts[motif] = (counts[motif] or 0) + 1 end
                end
            end
        end
    end
    local ranked = {}
    for motif, n in pairs(counts) do
        if n >= 2 then ranked[#ranked + 1] = { motif = motif, n = n } end
    end
    table.sort(ranked, function(a, b) return a.n > b.n end)
    if #ranked == 0 then
        HDG.Log:Notify("info", HDG.Locale:Get("MENAGERIE_ROOM_EMPTY"))
        return
    end
    local motifs = {}
    for i = 1, math.min(3, #ranked) do motifs[i] = ranked[i].motif end
    _set("mode", "bySpot")
    _set("roomQuery", { label = table.concat(motifs, "/"), motifs = motifs })
end

-- ===== chip cell kind: every plain chip strip ===============================
-- One kind serves mode / axes / axis values / spot rows / scene strip / also --
-- the item's fields say which dispatch it is. Immutable table rebuilds for the
-- spot group (RMW discipline: build next value, then dispatch).
-- Every chip stream stamps its own `group`, so this dispatches on ONE field.
-- It used to fall through a chain of shape guesses -- "a string value with no
-- count that equals one of four axis names" -- which is a rule about what the
-- data happens to look like rather than what it IS, and it broke the moment a
-- value collided.
local function _chipClick(item)
    local g = item.group
    if g == "mode" then
        _set("mode", item.value)

    elseif g == "axis" then
        _set("axis", item.value); _set("axval", "all")

    elseif g == "axval" then
        _set("axval", item.value)

    elseif g == "suggest" then
        -- Fill the box with the picked kind rather than inventing a second
        -- filter concept: search already matches kind, so one control owns the
        -- narrowing and the text always says what the list is doing.
        _set("search", item.value)
        if C._searchBox then
            C._searchBox:SetText(item.value)
            C._searchBox:ClearFocus()
            if C._searchBox._hdgrPlaceholderRefresh then C._searchBox._hdgrPlaceholderRefresh() end
            if C._searchBox._hdgrSearchRefresh then C._searchBox._hdgrSearchRefresh() end
        end

    elseif g == "surface" or g == "size" then
        local spot = _ui().spot
        local next_ = { surface = spot.surface, size = spot.size, wants = spot.wants }
        next_[g] = item.value
        _set("spot", next_)

    elseif g == "wants" then
        local spot, wants = _ui().spot, {}
        for k in pairs(_ui().spot.wants) do wants[k] = true end
        if wants[item.value] then wants[item.value] = nil else wants[item.value] = true end
        _set("spot", { surface = spot.surface, size = spot.size, wants = wants })

    elseif g == "scene" then
        local scene = _ui().scene
        if item.value == "you" then
            _set("scene", { decorID = scene.decorID, withYou = not scene.withYou })
        else
            _set("scene", { decorID = item.value ~= "none" and item.value or nil,
                            withYou = scene.withYou })
        end

    elseif g == "also" then                       -- play, not state
        local stage = _stage()
        if stage then stage:PlayPhase(item.animID, 0) end
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
        local txt = "Sounds -- " .. item.cadence
        -- sharedWith counts the OTHER species on this voice. Zero is a voice of
        -- its own and says nothing; anything above it is the surprise -- your
        -- bunny borrowed a crab's throat.
        local n = item.sharedWith
        if n == 1 then return txt .. ", shared with 1 other" end
        if n > 1 then return txt .. ", shared with " .. n .. " others" end
        return txt
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
        _stopSoundBar(chip)   -- pooled: a bar mid-fill must not survive a rebind
        if not item then chip:Hide(); chip:SetScript("OnClick", nil); return end
        HDG.UI:EnsureChipChrome(chip)
        chip:Show()
        chip:SetText(_flowLabel(item))
        HDG.Theme:Register(chip, "Button",
            { variant = "chip", active = item.nodeType == "voice" })
        chip:RegisterForClicks("LeftButtonUp")
        chip:SetScript("OnClick", function()
            if item.nodeType == "voice" then
                -- Imperative moment: playing is not state. The kit set is
                -- sorted, so a fixed kits[1] was often the ambient LOOP -- near
                -- silent as a one-shot. Cycle instead: every click plays the
                -- NEXT sound in the pet's set.
                if item.kits and #item.kits > 0 then
                    local key = item.kits[1]
                    local i = (_voiceCycle[key] or 0) % #item.kits + 1
                    _voiceCycle[key] = i
                    -- PlaySound IS C_Sound.PlaySound (Blizzard_SharedXML/Mainline/
                    -- Sound.lua: `PlaySound = C_Sound.PlaySound`), whose contract is
                    -- `success, handle = PlaySound(kitID, ...)`. It REPORTS a kit it
                    -- would not play; it does not raise. The pcall that used to wrap
                    -- this caught an error that cannot happen and discarded the one
                    -- signal worth having -- so a refused kit still drew a bar
                    -- filling over silence. Every voice in the DB carries one
                    -- duration per kit (513/513, verified), so durs[i] is a strict read.
                    local played = PlaySound(item.kits[i])
                    local dur = item.durs[i]
                    if played and dur > 0 then _startSoundBar(chip, dur) end
                end
            else
                local stage = _stage()
                if stage then stage:PlayPhase(item.animID, item.variation)
                elseif HDG.Store:GetState().account.config.debug then
                    _G.print("[HDG petscene] flow-node click: stage widget NOT FOUND (mainFrame=" .. tostring(HDG.mainFrame ~= nil) .. ")")
                end
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
-- Nothing is wired at Wire() time. The rootFrame handed in here proved to be a
-- DIFFERENT frame whose .widgets never held these ids (the same discovery that
-- moved _stage onto HDG.mainFrame), so anything looked up from it silently
-- returns nil and the handler is never attached. Wiring is LAZY against
-- HDG.mainFrame on first Refresh instead, where the widget table is populated.
local LAZY = {
    roomBtn = { id = "menagerieListPanel.roomBtn", attach = function(w)
        w:SetScript("OnClick", _captureRoom)
    end },
    search = { id = "menagerieListPanel.search", attach = function(w)
        local function set(text)
            HDG.ControllerHelpers.Mechanics.SetUITransientView("menagerie", "search", text)
        end
        C._searchBox = w          -- a suggestion click writes the picked kind back into it
        HDG.UI.WireTextChanged(w, set)
        -- The clear "x" calls SetText(""), which fires OnTextChanged WITHOUT
        -- userInput -- so the guarded handler above ignores it and the state
        -- would keep the old needle while the box read empty. The x reports
        -- itself instead.
        w._hdgrOnClear = function() set("") end
    end },
}

function C:Wire(_rootFrame)
    -- Chips and rows wire themselves in their cell binders; the two frame-level
    -- widgets wire lazily below. Required by the Controllers registry contract.
end

function C:Refresh(_rootFrame, _ctx)
    if not HDG.mainFrame then return end   -- exception(boundary): no frame before first open
    self._wired = self._wired or {}
    for key, spec in pairs(LAZY) do
        if not self._wired[key] then
            local w = HDG.mainFrame.widgets[spec.id]   -- exception(nullable): not in this window's layout
            if w then
                spec.attach(w)
                self._wired[key] = true
            end
        end
    end
end

HDG.Controllers:Register("menagerie", C)
