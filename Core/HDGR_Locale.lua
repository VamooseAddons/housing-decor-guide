-- HDG.Locale
-- ============================================================================
-- Key-value locale registry with enUS fallback chain. Used by `binding = "locale:KEY"` widgets.
-- Missing keys return the literal key (visible to translators; never error).

HDG = HDG or {}
HDG.Locale = HDG.Locale or {
    _locale = "enUS",
    _tables = {},   -- [locale] = { [key] = text }
}

local L = HDG.Locale

-- Initialize from persisted state or GetLocale(). Installs a Store subscriber for CONFIG_SET locale
-- so the dropdown's pure-dispatch click path works (Iron Invariant section 6).
function L:Initialize()
    -- Prefer the persisted locale slot if it's been set; fall back to the
    -- client locale, then enUS for headless tests. Empty-string default
    -- ("not yet set by user") routes to the client locale.
    local persisted = HDG.Store
        and HDG.Store.state
        and HDG.Store.state.account
        and HDG.Store.state.account.config
        and HDG.Store.state.account.config.locale
    if type(persisted) == "string" and persisted ~= "" then
        self._locale = persisted
    else
        self._locale = (_G.GetLocale and _G.GetLocale()) or "enUS"
    end
    self:_InstallLocaleSubscriber()
end

function L:_InstallLocaleSubscriber()
    if self._localeSubscriberInstalled then return end
    if not (HDG.Store and HDG.Store.Subscribe) then return end  -- exception(boundary): tests partial
    self._localeSubscriberInstalled = true
    local A = HDG.Constants.ACTIONS
    HDG.Store:Subscribe(function(actionType, invalidation)
        if actionType ~= A.CONFIG_SET then return end
        if not HDG.Paths.MatchesAny({ "account.config.locale" }, invalidation) then return end
        local loc = HDG.Store:GetState().account.config.locale
        if type(loc) ~= "string" or loc == "" then return end
        if self._locale == loc then return end   -- idempotent
        self._locale = loc
        -- locale:KEY bindings pull from in-memory table, not state -- force a full refresh to repaint.
        if HDG.RefreshMainWindow then HDG:RefreshMainWindow("*") end  -- exception(boundary): load-order partial in tests
        HDG.Log:Info("theme", "Locale set to " .. loc)
    end)
end

function L:SetLocale(loc)
    self._locale = loc or "enUS"
end

function L:GetLocale()
    return self._locale
end

-- Register a locale table. Multiple calls merge (later keys win). Modules ship their own keys.
function L:Register(loc, t)
    if type(loc) ~= "string" or type(t) ~= "table" then return end
    self._tables[loc] = self._tables[loc] or {}
    for k, v in pairs(t) do
        self._tables[loc][k] = v
    end
end

-- Look up a key. Order: current locale -> enUS -> key string (loud-fail per ADR-006).
function L:Get(key)
    if type(key) ~= "string" or key == "" then return tostring(key or "") end
    local t = self._tables[self._locale]
    if t and t[key] ~= nil then return t[key] end
    local enUS = self._tables.enUS
    if enUS and enUS[key] ~= nil then return enUS[key] end
    return key
end

-- Test helper -- wipe between cases.
function L:_Reset()
    self._tables = {}
    self._locale = "enUS"
end
