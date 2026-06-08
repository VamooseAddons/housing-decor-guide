-- HDG.Memo
--
-- Selector memoization (Reselect-style). Two entry points:
--   Memo({ inputs = {fn1, fn2, ...}, compute = fn })  -- 1-entry cache; inputs must return stable references.
--   MakeFactory({ inputs, compute })                   -- per-key cache; use when N callers key by ID.
-- Reselect rules: stable input refs; only memoize non-trivial compute; use MakeFactory for per-instance.

HDG = HDG or {}
HDG.Memo = HDG.Memo or {}

local M = HDG.Memo

-- ===== Single-entry Memo (reselect style) =================================
-- Inputs called with selector args; compared by reference (Lua 5.1 == checks identity).
-- compute runs only on cache miss.
function M.Memo(spec)
    if type(spec) ~= "table" then
        error("HDG.Memo.Memo: expected a spec table", 2)
    end
    if type(spec.compute) ~= "function" then
        error("HDG.Memo.Memo: spec.compute must be a function", 2)
    end
    local inputs = spec.inputs or {}
    if type(inputs) ~= "table" then
        error("HDG.Memo.Memo: spec.inputs must be a list of functions", 2)
    end
    for i, inputFn in ipairs(inputs) do
        if type(inputFn) ~= "function" then
            error(("HDG.Memo.Memo: spec.inputs[%d] must be a function"):format(i), 2)
        end
    end

    local cachedInputs = nil  -- nil = no cache yet
    local cachedResult = nil
    local n = #inputs

    local function call(...)
        -- Zero inputs = always recompute (no memoization; allowed for API consistency).
        if n == 0 then
            return spec.compute(...)
        end

        local currentInputs = {}
        for i = 1, n do
            currentInputs[i] = inputs[i](...)
        end

        -- Reference equality: contract is that input selectors return stable references.
        local hit = cachedInputs ~= nil
        if hit then
            for i = 1, n do
                if cachedInputs[i] ~= currentInputs[i] then
                    hit = false
                    break
                end
            end
        end

        if hit then
            return cachedResult
        end

        cachedInputs = currentInputs
        cachedResult = spec.compute(unpack(currentInputs, 1, n))
        return cachedResult
    end

    -- Callable table with :Clear() so path-based InvalidateMemos can wipe the cache.
    -- Without :Clear() the reactive invalidation system can't drop cached values.
    return setmetatable({
        Clear = function() cachedInputs = nil; cachedResult = nil end,
    }, { __call = function(_self, ...) return call(...) end })
end

-- ===== Factory (per-instance memoization) =================================
-- Returns factory(key) -> selector, each with its own 1-entry cache.
-- Without this, a shared selector thrashes across N differently-keyed callers.
-- spec.inputs are (state, key, ...) -> value; factory partial-applies key.
function M.MakeFactory(spec)
    if type(spec) ~= "table" then
        error("HDG.Memo.MakeFactory: expected a spec table", 2)
    end
    if type(spec.compute) ~= "function" then
        error("HDG.Memo.MakeFactory: spec.compute must be a function", 2)
    end
    local inputs = spec.inputs or {}

    -- Strong cache (not weak-value): a weak cache can evict selectors still referenced only by
    -- a local var, rebuilding with empty cache and silently defeating memoization.
    local cache = {}

    local function makeSelector(key)
        if cache[key] then return cache[key] end

        -- Build a Memo selector that captures `key` in its input/compute
        -- closures.
        local boundInputs = {}
        for i, inputFn in ipairs(inputs) do
            boundInputs[i] = function(...) return inputFn(key, ...) end
        end

        local selector = M.Memo({
            inputs = boundInputs,
            compute = function(...) return spec.compute(key, ...) end,
        })

        cache[key] = selector
        return selector
    end

    -- Callable table: factory(key) -> selector + :Evict/:EvictAll for explicit cache management.
    local factory = setmetatable({
        Evict = function(_self, key) cache[key] = nil end,
        EvictAll = function() cache = {} end,
    }, {
        __call = function(_self, key) return makeSelector(key) end,
    })
    return factory
end

-- ===== Helpers ============================================================

-- Identity: returns first arg unchanged. Use as input when compute should receive state directly.
function M.Identity(...)
    return (...)
end

-- Path("account.sets") -> function(state) -> state.account.sets. Dotted string, O(n) segs.
function M.Path(path)
    if type(path) ~= "string" or path == "" then
        error("HDG.Memo.Path: expected non-empty dotted string", 2)
    end
    local segments = {}
    for seg in path:gmatch("[^%.]+") do segments[#segments + 1] = seg end
    return function(state)
        local cur = state
        for _, seg in ipairs(segments) do
            if type(cur) ~= "table" then return nil end
            cur = cur[seg]
        end
        return cur
    end
end
