-- HDG.Config
-- ============================================================================
-- Facade over ConfigSchema + SavedVariables. Hand-rolled (no AceDB) to keep
-- one SSoT in the Lattice Store.
--
-- Config:Get(OPTION)   -- typed read; resolves scope to the right SV slot.
-- Config:Set(OPTION,V) -- dispatches CONFIG_SET; Store IS the bus.
-- Profile management   -- NewProfile / SwitchProfile / DeleteProfile (all dispatched).
-- Config:Initialize    -- called from Init.lua after Store:LoadFromSavedVariables.
--
-- state.account.config is a READ MIRROR of the active profile + character overlays.
-- _HydrateMirror refreshes it at boot and on PROFILE_SWITCH so selectors' `reads`
-- declarations stay stable. See: HDGR_CONFIG_DESIGN.md.

HDG = HDG or {}

HDG.Config = {
    -- Set by _initProfileStructure -- the active profile name. Backed by
    -- HDG_DB_CURRENT_PROFILE (per-character SV).
    _activeProfile = nil,
    -- Initialize() sets this true -- prevents Set/Get use before boot.
    _initialized   = false,
}

local Config = HDG.Config
local Scope  = HDG.Constants.ConfigScope
local DEFAULT_PROFILE_NAME = "DEFAULT"

-- ===== Internal helpers =====================================================

-- Resolve the SV-backing table for a given scope. Lazy-creates the
-- character bucket on first read so we never write into a nil table.
function Config:_GetSourceForScope(scope)
    if scope == Scope.Character then
        local guid = (UnitGUID and UnitGUID("player")) or "_unknown_"
        HDG_DB.characterSpecific[guid] = HDG_DB.characterSpecific[guid] or {}
        return HDG_DB.characterSpecific[guid]
    end
    if scope == Scope.Account then
        return HDG_DB
    end
    return HDG_DB.profiles[self._activeProfile]
end

-- Resolve the effective value for an option, honouring scope precedence:
-- Character overlay first (if set), then Profile, then schema default.
-- This is what Config:Get returns and what _HydrateMirror writes into
-- state.account.config[key].
function Config:_ResolveValue(key)
    local scope = HDG.ConfigSchema.ScopeBy[key]
    local src   = self:_GetSourceForScope(scope)
    if src[key] ~= nil then return src[key] end
    return HDG.ConfigSchema.Defaults[key]
end

-- Rebuild state.account.config from the active profile + character overlays.
-- Iterates the schema (not the SV table) so deleted settings drop out cleanly.
function Config:_HydrateMirror()
    local config = HDG.Store:GetState().account.config
    for key in pairs(HDG.ConfigSchema.Defaults) do
        -- Account-scoped flags (MIGRATED_*) don't belong in the per-profile mirror.
        if HDG.ConfigSchema.ScopeBy[key] ~= Scope.Account then
            config[key] = self:_ResolveValue(key)
        end
    end
end

-- Ensure HDG_DB.profiles + characterSpecific exist. Picks active profile from
-- HDG_DB_CURRENT_PROFILE; falls back to DEFAULT if the recorded profile was deleted.
function Config:_InitProfileStructure()
    HDG_DB.profiles          = HDG_DB.profiles          or { [DEFAULT_PROFILE_NAME] = {} }
    HDG_DB.characterSpecific = HDG_DB.characterSpecific or {}
    if not HDG_DB.profiles[DEFAULT_PROFILE_NAME] then
        HDG_DB.profiles[DEFAULT_PROFILE_NAME] = {}
    end
    HDG_DB_CURRENT_PROFILE = HDG_DB_CURRENT_PROFILE or DEFAULT_PROFILE_NAME
    if not HDG_DB.profiles[HDG_DB_CURRENT_PROFILE] then
        HDG_DB_CURRENT_PROFILE = DEFAULT_PROFILE_NAME
    end
    self._activeProfile = HDG_DB_CURRENT_PROFILE
end

-- Pre-seed missing Profile-scoped settings with their schema defaults.
-- Character + Account values fill in lazily via Config:Get's default fallback.
function Config:_ImportDefaultsToActiveProfile()
    local profile = HDG_DB.profiles[self._activeProfile]
    for key, default in pairs(HDG.ConfigSchema.Defaults) do
        if HDG.ConfigSchema.ScopeBy[key] == Scope.Profile and profile[key] == nil then
            if type(default) == "table" then
                local copy = {}
                for k, v in pairs(default) do copy[k] = v end
                profile[key] = copy
            else
                profile[key] = default
            end
        end
    end
end

-- One-time per-version migrations. Each is idempotent via its own MIGRATED_* flag.
-- Runs inside Initialize before any dispatch, so writes go directly to SV slots.
function Config:_RunMigrations()
    -- Migration 1: copy legacy HDG_DB.account.config into HDG_DB.profiles.DEFAULT (pre-profile shape).
    local flagKey = HDG.ConfigSchema.ByOption.MIGRATED_LEGACY_CONFIG_TO_PROFILE
    if not HDG_DB[flagKey] then
        local legacy = HDG_DB.account and HDG_DB.account.config  -- exception(boundary): HDG_DB.account is the SV root for legacy pre-Config shape; may be absent on first install
        if type(legacy) == "table" and next(legacy) ~= nil then
            local target = HDG_DB.profiles[DEFAULT_PROFILE_NAME]
            for k, v in pairs(legacy) do
                if target[k] == nil then target[k] = v end
            end
            -- Legacy slot kept intact for one release as a rollback safety net.
        end
        HDG_DB[flagKey] = true
    end
end

-- ===== Public API ===========================================================

-- Read a setting. Returns the schema default if unset.
function Config:Get(optionName)
    local key = HDG.ConfigSchema.ByOption[optionName]
    if not key then
        error(("HDG.Config:Get unknown option %q"):format(tostring(optionName)), 2)
    end
    return self:_ResolveValue(key)
end

-- Write a setting. Dispatches CONFIG_SET; reducer applies to the right scope-backed table.
function Config:Set(optionName, value)
    local key = HDG.ConfigSchema.ByOption[optionName]
    if not key then
        error(("HDG.Config:Set unknown option %q"):format(tostring(optionName)), 2)
    end
    HDG.Store:Dispatch({
        type    = HDG.Constants.ACTIONS.CONFIG_SET,
        payload = {
            key   = key,
            value = value,
            scope = HDG.ConfigSchema.ScopeBy[key],
        },
    })
end

-- ===== Profile management ==================================================

function Config:GetActiveProfile()
    return self._activeProfile
end

function Config:GetProfileNames()
    local names = {}
    for name in pairs(HDG_DB.profiles) do
        names[#names + 1] = name
    end
    table.sort(names)
    return names
end

function Config:NewProfile(name, cloneFromCurrent)
    assert(type(name) == "string" and name ~= "", "Profile name must be a non-empty string")
    assert(not HDG_DB.profiles[name], ("Profile %q already exists"):format(name))
    HDG.Store:Dispatch({
        type    = HDG.Constants.ACTIONS.PROFILE_CREATE,
        payload = {
            name      = name,
            cloneFrom = cloneFromCurrent and self._activeProfile or nil,
        },
    })
end

function Config:SwitchProfile(name)
    assert(HDG_DB.profiles[name], ("Profile %q does not exist"):format(name))
    if name == self._activeProfile then return end
    HDG.Store:Dispatch({
        type    = HDG.Constants.ACTIONS.PROFILE_SWITCH,
        payload = { name = name },
    })
end

function Config:DeleteProfile(name)
    assert(name ~= DEFAULT_PROFILE_NAME, "Cannot delete the DEFAULT profile")
    assert(name ~= self._activeProfile,
           ("Cannot delete the active profile %q -- switch first"):format(name))
    assert(HDG_DB.profiles[name], ("Profile %q does not exist"):format(name))
    HDG.Store:Dispatch({
        type    = HDG.Constants.ACTIONS.PROFILE_DELETE,
        payload = { name = name },
    })
end

-- ===== Boot ================================================================

-- Called from Init.lua after Store:LoadFromSavedVariables, before Theme:Initialize.
-- Order: _InitProfileStructure -> _RunMigrations (before defaults, so legacy values aren't overwritten)
-- -> _ImportDefaultsToActiveProfile -> _HydrateMirror.
function Config:Initialize()
    assert(HDG.Store and HDG.Store.state,  -- exception(false-positive): assert IS fail-loud; the cascade is the assertion predicate, not a silent guard
           "HDG.Config:Initialize requires Store loaded first")
    HDG_DB = HDG_DB or {}
    self:_InitProfileStructure()
    self:_RunMigrations()
    self:_ImportDefaultsToActiveProfile()
    self:_HydrateMirror()
    self._initialized = true
end
