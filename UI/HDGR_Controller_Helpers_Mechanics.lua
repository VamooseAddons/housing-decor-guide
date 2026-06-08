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

-- Merged read-only UI view: union of account.ui + session.ui.
-- Writes go through SetUIPersistent / SetUITransient / SetUITransientView (bucket-aware at call site).
-- Typical callers prefer Mech.GetUIView(view) for per-view scratch state.
function Mech.GetUI()
    local s = Mech.GetState()
    local merged = {}
    for k, v in pairs(s.account.ui) do merged[k] = v end
    for k, v in pairs(s.session.ui) do merged[k] = v end
    return merged
end

-- Per-view scratch state at state.session.ui[view][key].
function Mech.GetUIView(view)
    return Mech.GetState().session.ui[view] or {}
end

function Mech.GetSelectedSet()
    local s = Mech.GetState()
    local selectedSetID = s.account.ui.selectedSetID
    local set = selectedSetID and s.account.sets[selectedSetID] or nil
    if not set or set.deletedAt then return nil, nil, s end
    return selectedSetID, set, s
end

-- Player map ID. Returns nil in test environments without C_Map.
function Mech.GetCurrentMapID()
    local C_MapAPI = _G and _G.C_Map
    return C_MapAPI and C_MapAPI.GetBestMapForUnit and C_MapAPI.GetBestMapForUnit("player") or nil  -- exception(boundary): C_Map nil off-map / no zone
end

function Mech.GetConfigValue(key, fallback)
    local v = Mech.GetState().account.config[key]
    if v == nil then return fallback end
    return v
end

-- ===== Dispatch wrappers + domain actions =================================
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


-- ===== Cycle helpers ======================================================
function Mech.CycleConfigValue(key, order, fallback)
    local current = Mech.GetConfigValue(key, fallback)
    local nextIndex = 1
    for index, value in ipairs(order) do
        if value == current then nextIndex = index + 1; break end
    end
    if nextIndex > #order then nextIndex = 1 end
    local nextValue = order[nextIndex]
    Mech.Dispatch(HDG.Constants.ACTIONS.CONFIG_SET, { key = key, value = nextValue })
    return nextValue
end

-- Same shape for transient UI keys. Reads session.ui; writes via SetUITransient.
function Mech.CycleUIValue(key, order)
    local current = HDG.Store:GetState().session.ui[key]  -- exception(false-positive): top-level controller read
    local nextIndex = 1
    for index, value in ipairs(order) do
        if value == current then nextIndex = index + 1; break end
    end
    if nextIndex > #order then nextIndex = 1 end
    Mech.SetUITransient(key, order[nextIndex])
end
