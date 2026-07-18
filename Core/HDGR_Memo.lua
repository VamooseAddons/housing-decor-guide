-- HDG.Memo
--
-- Selector memoization (Reselect-style). Two entry points:
--   Memo({ inputs = {fn1, fn2, ...}, compute = fn })  -- 1-entry cache; inputs must return stable references.
-- Reselect rules: stable input refs; only memoize non-trivial compute.
-- (A per-key MakeFactory variant was once advertised here but never built; add it
-- with (state, ctx) input signature if a per-instance cache is ever needed.)

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

-- ===== Helpers ============================================================
