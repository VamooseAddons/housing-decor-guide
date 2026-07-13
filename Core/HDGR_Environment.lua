-- HDG.Environment
--
-- Ambient values threaded through build walk + thunk dispatches via EnvMiddleware.
-- Missing slot access errors loudly ("undeclared env slot 'foo'" not silent nil).
-- Rules: static slots only; every slot has a valid default; read-only projection (writes via Dispatch).

HDG = HDG or {}
HDG.Environment = HDG.Environment or {
    _slots     = {},        -- [name] = { default, validator?, description? }
    _current   = nil,       -- the assembled env table, populated by Build()
    _sealed    = false,     -- once Build() runs, Declare() errors
}

local E = HDG.Environment

-- Declare a slot. Sealed after Build(); Declare() after that errors.
-- def = { name (required), default (required, valid standalone), description?, validator? }
function E:Declare(def)
    if self._sealed then
        error(("HDG.Environment:Declare(%q) called after Build()"):format(
            tostring(def and def.name)), 2)
    end
    if type(def) ~= "table" then
        error("HDG.Environment:Declare expected a table", 2)
    end
    if type(def.name) ~= "string" or def.name == "" then
        error("HDG.Environment:Declare missing required field 'name'", 2)
    end
    if def.default == nil then
        error(("HDG.Environment:Declare(%q) missing required 'default'"):format(def.name), 2)
    end
    if def.validator and not def.validator(def.default) then
        error(("HDG.Environment:Declare(%q): default value failed validator"):format(def.name), 2)
    end
    if self._slots[def.name] then
        error(("HDG.Environment:Declare(%q) duplicate slot"):format(def.name), 2)
    end
    self._slots[def.name] = def
end

-- Build the env table. Called once per session after all slots declared. Re-Build() for scheme swap.
-- overrides: non-default values for specific slots (preview/test mocks).
function E:Build(overrides)
    overrides = overrides or {}
    local env = {}
    for name, def in pairs(self._slots) do
        local v = overrides[name]
        if v == nil then v = def.default end
        if def.validator and not def.validator(v) then
            error(("HDG.Environment:Build: slot %q failed validator"):format(name), 2)
        end
        env[name] = v
    end

    -- Catch overrides for undeclared slots ("skinner reads env.foo but slot 'foo' not declared").
    for name in pairs(overrides) do
        if not self._slots[name] then
            error(("HDG.Environment:Build: override for undeclared slot %q"):format(name), 2)
        end
    end

    self._current = env
    self._sealed = true
    return env
end

-- Strict slot read. Errors on unknown slot; use when slot existence must be verified.
function E:Get(name)
    if not self._current then
        error("HDG.Environment: not built yet (call Build() in OnEnable)", 2)
    end
    if not self._slots[name] then
        error(("HDG.Environment:Get(%q): undeclared slot"):format(tostring(name)), 2)
    end
    return self._current[name]
end

-- ===== Introspection / test helpers =======================================

function E:_Reset()
    self._slots = {}
    self._current = nil
    self._sealed = false
end

-- Central slot catalog. Addon-level slots here; modules may add module-specific via Declare.
E.SLOTS = E.SLOTS or {}

-- Register central slots into the runtime. Called by Init.lua. Idempotent.
function E:DeclareAll()
    for _, def in ipairs(self.SLOTS) do
        if not self._slots[def.name] then
            self:Declare(def)
        end
    end
end
