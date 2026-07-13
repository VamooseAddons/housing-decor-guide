-- HDG.ControllerHelpers.Mechanics
-- State readers + dispatch wrappers. All Store mutation goes through here.
-- No widget access, no paint, no UI workflow.

HDG = HDG or {}
HDG.ControllerHelpers = HDG.ControllerHelpers or {}
HDG.ControllerHelpers.Mechanics = HDG.ControllerHelpers.Mechanics or {}

local Mech = HDG.ControllerHelpers.Mechanics

-- ===== State readers ======================================================

function Mech.GetState()
    return HDG.Store:GetState()  -- exception(false-positive): top-level controller method (not a row factory)
end

-- Per-view scratch state at state.session.ui[view][key].
function Mech.GetUIView(view)
    return Mech.GetState().session.ui[view] or {}
end

function Mech.GetConfigValue(key, fallback)
    local v = Mech.GetState().account.config[key]
    if v == nil then return fallback end
    return v
end

-- ===== Dispatch wrappers + domain actions =================================
-- Wall-clock seconds for stamps (createdAt / lastCapturedAt). One annotated
-- boundary instead of 13 hand-rolled copies (hygiene review A2).
function Mech.Now()
    return (time and time()) or 0  -- exception(boundary): time() is a Lua/WoW global
end

-- Dispatch by ACTION NAME (resolves through the closed taxonomy).
function Mech.DispatchNamed(actionType, payload)
    HDG.Store:Dispatch({ type = HDG.Constants.ACTIONS[actionType], payload = payload })
end

function Mech.Dispatch(actionType, payload)
    HDG.Store:Dispatch({ type = actionType, payload = payload })
end

-- account.ui: persists across /reload. session.ui: cleared on /reload.
-- Bucket choice is at the call site.
function Mech.SetUIPersistent(key, value)
    HDG.Store:Dispatch({
        type = HDG.Constants.ACTIONS.UI_SET_PERSISTENT,
        payload = { key = key, value = value },
    })
end

function Mech.SetUITransient(key, value)
    HDG.Store:Dispatch({
        type = HDG.Constants.ACTIONS.UI_SET_TRANSIENT,
        payload = { key = key, value = value },
    })
end

-- Per-view variant: payload.view picks the sub-bucket.
function Mech.SetUITransientView(view, key, value)
    HDG.Store:Dispatch({
        type = HDG.Constants.ACTIONS.UI_SET_TRANSIENT,
        payload = { view = view, key = key, value = value },
    })
end

-- Cross-window vendor deep-link: open the main window on Acquire > Shop by
-- Vendor with this vendor selected. Callable from any window (shopping widget /
-- zone popup vendor rows). Clears the vendor search so the list actually shows
-- the selection; the search editbox reconciles from state in acquisition
-- Refresh. npcID is authoritative when set; (name, zone) is the fallback
-- identity for npcID-less vendors (mirrors acq.selectedVendor).
-- Select a vendor in the acquisition view: the five-transient sequence every
-- selection path shares (row click, auto-select, cross-window jump). npcID is
-- authoritative; (name, zone) is the npcID-less fallback identity (hygiene A23).
function Mech.SelectVendor(npcID, name, zone)
    Mech.SetUITransientView("acquisition", "selectedNpcID", npcID)
    Mech.SetUITransientView("acquisition", "selectedVendorName", name)
    Mech.SetUITransientView("acquisition", "selectedVendorZone", zone)
    Mech.SetUITransientView("acquisition", "selectedItemID", nil)
    Mech.SetUITransientView("acquisition", "selectedRecipeItemID", nil)
end

function Mech.JumpToVendor(npcID, name, zone)
    if Mech.GetState().account.ui.mainWindowShown ~= true then
        Mech.Dispatch(HDG.Constants.ACTIONS.MAIN_WINDOW_TOGGLE)
    end
    Mech.SetUIPersistent("view", "acquisition")
    Mech.SetUITransientView("acquisition", "viewMode", "vendor")
    Mech.SetUITransientView("acquisition", "searchQuery", "")
    Mech.SelectVendor(npcID, name, zone)
end


-- Race-guarded note editbox (hygiene A4 -- Decor item notes + Acquisition
-- vendor notes shared this control flow verbatim). The binding-driven SetText
-- lands a frame AFTER the selected id flips, so a hooksecurefunc stamps which
-- id's note the box is DISPLAYING; OnTextChanged skips when the displayed id
-- no longer matches the selection (else a fast selection switch writes one
-- entity's note onto another). getSelectedID returns the current id;
-- clearAction/setAction are ACTION NAMES; idField keys the payload.
function Mech.WireNoteBox(noteBox, getSelectedID, idField, clearAction, setAction)
    if not (noteBox and noteBox.SetScript) then return end  -- exception(boundary): widget may be absent in this window
    noteBox._lastBoundNoteID = nil
    if not noteBox._setTextHooked then
        hooksecurefunc(noteBox, "SetText", function(self)
            self._lastBoundNoteID = getSelectedID()
        end)
        noteBox._setTextHooked = true
    end
    noteBox:SetScript("OnTextChanged", function(self, userInput)
        if not userInput then return end
        local id = getSelectedID()
        if not id then return end
        if self._lastBoundNoteID ~= nil and self._lastBoundNoteID ~= id then return end  -- selection switch in progress
        local text = (self.GetText and self:GetText()) or ""
        if text == "" then
            Mech.DispatchNamed(clearAction, { [idField] = id })
        else
            Mech.DispatchNamed(setAction, { [idField] = id, text = text })
        end
    end)
end

-- Resolve a Projects target house then invoke onPick(houseID, houseName): the
-- only owned house goes straight through; 2+ show a titled chooser menu (the
-- Alliance/Horde picker) anchored on `owner`. Returns false without calling
-- onPick when there are no houses -- the caller surfaces its own "visit a house
-- first" message (each uses a different channel). Shared by the Layouts importer
-- and the Blueprints "Open in Architect" flow (hygiene A19).
function Mech.PromptHouseTarget(owner, title, onPick)
    local houses = HDG.Selectors:Call("projects.houseMenuItems", Mech.GetState(), {})
    if #houses == 0 then return false end
    if #houses == 1 then onPick(houses[1].value, houses[1].text); return true end
    local menu = { { isTitle = true, text = title } }
    for _, h in ipairs(houses) do
        local hid, hname = h.value, h.text
        menu[#menu + 1] = { text = h.text, callback = function() onPick(hid, hname) end }
    end
    HDG.UI.ShowMenu(owner, menu)
    return true
end
