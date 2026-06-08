-- HDG.Middleware
--
-- Action-stream middleware chain (cross-cutting concerns: logging, combat, persistence, errors).
-- Each middleware: function(nextDispatch, store) -> function(action). Rodux two-curry shape.
-- Registration order = execution order (outermost = index 1). Right-fold over the list.

HDG = HDG or {}
HDG.Middleware = HDG.Middleware or {}

local M = HDG.Middleware

-- ===== Chain construction =================================================

-- Apply an ordered middleware list. Replaces store.Dispatch; future calls traverse the chain.
function M.Apply(store, middlewares)
    if type(middlewares) ~= "table" or #middlewares == 0 then return end

    local baseDispatch = function(action)
        return store:_RawDispatch(action)
    end

    -- Right-fold: iterate backwards so middlewares[1] wraps everything inside.
    local dispatch = baseDispatch
    for i = #middlewares, 1, -1 do
        local mw = middlewares[i]
        if type(mw) ~= "function" then
            error(("HDG.Middleware.Apply: middleware at index %d is not a function"):format(i), 2)
        end
        dispatch = mw(dispatch, store)
        if type(dispatch) ~= "function" then
            error(("HDG.Middleware.Apply: middleware at index %d did not return a dispatch function"):format(i), 2)
        end
    end

    -- Replace store.Dispatch; raw method preserved as _RawDispatch for the chain's base.
    store.Dispatch = function(self, action)
        return dispatch(action)
    end
end

-- ===== Standard middlewares ===============================================

-- LoggerMiddleware: dev-mode dispatch log. Gated by config.debug. First in chain.
-- HDGR_ prefix is stripped. Pad format: [HDG][Debug][Dispatch] <action>  <payload>
local LOGGER_NAME_WIDTH = 22  -- pad action names to this width (most are <= 20)
local LOGGER_MAX_KEYS   = 6   -- payload keys shown before truncating
local LOGGER_MAX_STR    = 80  -- string-value chars shown before "..."
local LOGGER_MAX_ARRAY  = 10  -- array elements shown inline before "[N items]"
local LOGGER_MAX_DEPTH  = 1   -- nested levels expanded (payload values -> their
                              -- own fields); deeper tables collapse to a size
                              -- summary so big/recursive payloads stay bounded

-- Render one value for the dispatch log. Bounded recursion: past LOGGER_MAX_DEPTH tables summarize.
local function renderValue(v, depth)
    local t = type(v)
    if t == "string" then
        return (#v > LOGGER_MAX_STR) and (v:sub(1, LOGGER_MAX_STR - 3) .. "...") or v
    elseif t == "number" or t == "boolean" then
        return tostring(v)
    elseif t ~= "table" then
        return "<" .. t .. ">"
    end
    local n = #v
    if n > 0 then   -- array
        if depth > LOGGER_MAX_DEPTH or n > LOGGER_MAX_ARRAY then return "[" .. n .. " items]" end
        local elems = {}
        for i = 1, n do elems[i] = renderValue(v[i], depth + 1) end
        return "[" .. table.concat(elems, ",") .. "]"
    end
    -- map (or empty table)
    if depth > LOGGER_MAX_DEPTH then
        local kc = 0
        for _ in pairs(v) do kc = kc + 1 end
        return (kc == 0) and "{}" or ("{" .. kc .. " keys}")
    end
    local parts, kc = {}, 0
    for kk, vv in pairs(v) do
        kc = kc + 1
        if kc <= LOGGER_MAX_KEYS then parts[kc] = tostring(kk) .. "=" .. renderValue(vv, depth + 1) end
    end
    if kc == 0 then return "{}" end
    if kc > LOGGER_MAX_KEYS then parts[#parts + 1] = "+" .. (kc - LOGGER_MAX_KEYS) .. " more" end
    return "{" .. table.concat(parts, ",") .. "}"
end

-- Compact key=value list for the payload's top-level keys (capped at LOGGER_MAX_KEYS).
local function formatPayload(payload)
    if type(payload) ~= "table" then return "" end
    local parts, count = {}, 0
    for k, v in pairs(payload) do
        count = count + 1
        if count > LOGGER_MAX_KEYS then
            parts[#parts + 1] = "..."
            break
        end
        parts[#parts + 1] = tostring(k) .. "=" .. renderValue(v, 1)
    end
    return table.concat(parts, " ")
end

function M.LoggerMiddleware(nextDispatch, store)
    return function(action)
        -- Skip LOG_PUSH self-logging (would recurse). Other LOG_* actions flow through.
        local actionType = action and action.type
        if actionType == HDG.Constants.ACTIONS.LOG_PUSH then
            return nextDispatch(action)
        end

        -- noisy=true in action meta opts out of dispatch-log chat spam (hover, keystroke, etc.).
        local actionMeta = store._actionMeta and store._actionMeta[actionType]
        if actionMeta and actionMeta.noisy then
            return nextDispatch(action)
        end

        local state = store:GetState()
        if state.account.config.debug then
            local short = tostring(actionType or "?"):gsub("^HDGR_", "")
            local padded = short  -- pad so payload column lands at the same X each line
            if #padded < LOGGER_NAME_WIDTH then
                padded = padded .. string.rep(" ", LOGGER_NAME_WIDTH - #padded)
            end
            local payload = action and action.payload
            local payloadStr = formatPayload(payload)
            HDG.Log:Debug("dispatch", padded, { payloadStr = payloadStr })
        end
        return nextDispatch(action)
    end
end

-- CombatMiddleware: queues combat-unsafe actions (ACTION_META[type].combatUnsafe).
-- Drains on PLAYER_REGEN_ENABLED. Owns the regen events (modules cannot subscribe).
function M.MakeCombatMiddleware(actionMeta)
    actionMeta = actionMeta or {}
    return function(nextDispatch, store)
        -- Wire once per store. State mutation goes through public Dispatch so reducer owns inLockdown.
        if not store._combatListenersWired and HDG.BlizzardEvents then
            store._combatListenersWired = true
            local A = HDG.Constants.ACTIONS
            HDG.BlizzardEvents:_internalSubscribe("PLAYER_REGEN_DISABLED", function()
                store:Dispatch({ type = A.COMBAT_ENTER })
            end)
            HDG.BlizzardEvents:_internalSubscribe("PLAYER_REGEN_ENABLED", function()
                -- 1. Snapshot queued  2. COMBAT_EXIT clears queue (single mutation)  3. Replay.
                local queued = store:GetState().session.combat.queued
                local snapshot = {}
                for i, a in ipairs(queued) do snapshot[i] = a end
                store:Dispatch({ type = A.COMBAT_EXIT })
                for _, queuedAction in ipairs(snapshot) do
                    store:Dispatch(queuedAction)
                end
            end)
        end

        return function(action)
            local meta = actionMeta[action and action.type or nil]
            local inLockdown = store:GetState().session.combat.inLockdown == true

            if meta and meta.combatUnsafe and inLockdown then
                -- Queue via reducer (single mutation point, per ADR-004).
                local A = HDG.Constants.ACTIONS
                store:Dispatch({
                    type    = A.COMBAT_QUEUE_ACTION,
                    payload = { action = action },
                })
                return  -- deferred; no result for caller
            end
            return nextDispatch(action)
        end
    end
end

-- EnvMiddleware: injects env as second arg to thunk-typed actions (Rodux makeThunkMiddleware pattern).
function M.MakeEnvMiddleware(env)
    return function(nextDispatch, store)
        return function(action)
            if type(action) == "function" then
                return action(store, env)
            end
            return nextDispatch(action)
        end
    end
end

-- PersistenceMiddleware: queues a SV save when action meta has persists=true.
function M.MakePersistenceMiddleware(actionMeta)
    actionMeta = actionMeta or {}
    return function(nextDispatch, store)
        return function(action)
            local result = nextDispatch(action)
            local meta = actionMeta[action and action.type or nil]
            if meta and meta.persists then
                store:QueueSave()
            end
            return result
        end
    end
end

-- ErrorBoundaryMiddleware: OUTERMOST middleware (index 1). pcall isolates reducer failures.
-- On catch: Log:Error (Debug Tab) + geterrorhandler() (BugSack/BugGrabber surface). per ADR-021.
function M.ErrorBoundaryMiddleware(nextDispatch, store)
    return function(action)
        local ok, result = pcall(nextDispatch, action)
        if not ok then
            local actionType = action and action.type or "?"
            local text = ("dispatch error (action=%s): %s"):format(
                tostring(actionType), tostring(result))
            HDG.Log:Error("error", text)
            if _G.geterrorhandler then  -- pcall geterrorhandler to guard against misbehaving handlers
                pcall(_G.geterrorhandler(), text)  -- exception(fire-forget): guard against misbehaving handler
            end
            return nil
        end
        return result
    end
end

-- ===== Standard chain assembly =============================================
-- Order: Error -> Logger -> Combat -> Env -> Persistence.
function M.StandardChain(opts)
    opts = opts or {}
    return {
        M.ErrorBoundaryMiddleware,
        M.LoggerMiddleware,
        M.MakeCombatMiddleware(opts.actionMeta),
        M.MakeEnvMiddleware(opts.env),
        M.MakePersistenceMiddleware(opts.actionMeta),
    }
end
