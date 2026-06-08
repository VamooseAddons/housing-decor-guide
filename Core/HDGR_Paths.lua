-- HDG.Paths
-- ============================================================================
-- State-path notation + matching. See ADR-011.
-- Paths are dotted strings ("account.collection.decorCatalog"). "*" matches everything.
-- Match rule: either path is a segment-aware prefix of the other (not raw-string prefix).

HDG = HDG or {}
HDG.Paths = HDG.Paths or {}

local Paths = HDG.Paths

-- Returns true when a == b OR one is a segment-aware prefix of the other. "*" = universal match.
function Paths.Matches(a, b)
    if a == nil or b == nil then return false end
    if a == "*" or b == "*" then return true end
    if a == b then return true end
    -- Swap so `a` is the shorter; check b starts with a .. "."
    if #a > #b then a, b = b, a end
    return b:sub(1, #a + 1) == (a .. ".")
end

-- Returns true when any readsList element intersects any invalidationList element.
-- Empty list matches nothing (no-op action / constant selector).
function Paths.MatchesAny(readsList, invalidationList)
    if readsList == "*" or invalidationList == "*" then return true end
    if type(readsList) ~= "table" or type(invalidationList) ~= "table" then
        return false
    end
    for _, r in ipairs(readsList) do
        for _, i in ipairs(invalidationList) do
            if Paths.Matches(r, i) then return true end
        end
    end
    return false
end

-- Build a dotted path from segments. Nil/empty segments are skipped silently.
function Paths.Join(...)
    local n = select("#", ...)
    local parts = {}
    for i = 1, n do
        local seg = select(i, ...)
        if seg ~= nil and seg ~= "" then
            parts[#parts + 1] = tostring(seg)
        end
    end
    return table.concat(parts, ".")
end

-- Split a dotted path into segments. "*" returns { "*" }.
function Paths.Parse(path)
    if type(path) ~= "string" or path == "" then return {} end
    local out = {}
    for segment in path:gmatch("([^%.]+)") do
        out[#out + 1] = segment
    end
    return out
end

-- Merge multiple reads lists without duplicates. Any "*" collapses result to "*".
local function _unionAppend(list, out, seen)
    if type(list) ~= "table" then return end
    for _, p in ipairs(list) do
        if type(p) == "string" and not seen[p] then
            seen[p] = true
            out[#out + 1] = p
        end
    end
end

function Paths.Union(...)
    local n = select("#", ...)
    local seen, out = {}, {}
    for i = 1, n do
        local list = select(i, ...)
        if list == "*" then return "*" end
        _unionAppend(list, out, seen)
    end
    return out
end
