-- HDG.Actions -- action self-registration registry.
-- ============================================================================
-- Design: Lattice/docs/SELFREG_RESOLVER_DESIGN_2026-06-11.md. One block per
-- action -- name + reduce(state, payload) + invalidates (+ persists /
-- combatUnsafe flags) -- declared where the domain lives. Boot merges these
-- into the action meta (Init.BuildActionMeta) with a duplicate-source error,
-- and Store:_RawDispatch is a pure registry lookup: resolve invalidation
-- from the entry, run its reduce, notify. ALL 258 actions are registered
-- blocks; the old 240-branch elseif chain is gone.
--
-- The closed taxonomy survives: Register validates the name against
-- Constants.ACTIONS, so a typo'd registration is a load-time error exactly
-- like a typo'd dispatch.

HDG = HDG or {}
HDG.Actions = HDG.Actions or { _entries = {} }
local Act = HDG.Actions

-- Register one action block. Required: name (Constants.ACTIONS key), reduce
-- (function(state, payload)), invalidates (list | function(action) | "*").
-- Optional: persists (default true), combatUnsafe (default false).
function Act:Register(block)
    if type(block) ~= "table" or type(block.name) ~= "string" then
        error("Actions:Register requires { name = <ACTIONS key>, ... }", 2)
    end
    local value = HDG.Constants.ACTIONS[block.name]
    if not value then
        error(("Actions:Register: %q is not in Constants.ACTIONS (closed taxonomy)"):format(block.name), 2)
    end
    if self._entries[value] then
        error(("Actions:Register: duplicate registration for %s"):format(block.name), 2)
    end
    if type(block.reduce) ~= "function" then
        error(("Actions:Register(%s): reduce function required"):format(block.name), 2)
    end
    if block.invalidates == nil then
        error(("Actions:Register(%s): invalidates required (list, function, or \"*\")"):format(block.name), 2)
    end
    if block.persists == nil then block.persists = true end
    if block.combatUnsafe == nil then block.combatUnsafe = false end
    self._entries[value] = block
end

function Act:Get(actionType)
    return self._entries[actionType]
end

-- Registered-count introspection (validators / tests).
function Act:Count()
    local n = 0
    for _ in pairs(self._entries) do n = n + 1 end
    return n
end

-- Test helper -- wipe between harness cases.
function Act:_Reset()
    self._entries = {}
end
