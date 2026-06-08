-- HDG.Codec -- shared pure-Lua serialization primitives.
-- ============================================================================
-- ONE copy of the base64 + urlencode helpers used by every HDG export/import
-- codec (CrateCodec, LayoutCodec). Pure Lua 5.1, no state, no WoW API -- testable
-- in vanilla Lua. The base64 alphabet is the standard one so codes interoperate
-- with other addons using the same routine. Loads before any codec consumer.

HDG = HDG or {}
HDG.Codec = HDG.Codec or {}
local M = HDG.Codec

local b64chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"

function M.b64encode(data)
    return ((data:gsub('.', function(x)
        local r, b = '', x:byte()
        for i = 8, 1, -1 do r = r .. (b % 2 ^ i - b % 2 ^ (i - 1) > 0 and '1' or '0') end
        return r
    end) .. '0000'):gsub('%d%d%d?%d?%d?%d?', function(x)
        if (#x < 6) then return '' end
        local c = 0
        for i = 1, 6 do c = c + (x:sub(i, i) == '1' and 2 ^ (6 - i) or 0) end
        return b64chars:sub(c + 1, c + 1)
    end) .. ({ '', '==', '=' })[#data % 3 + 1])
end

function M.b64decode(data)
    data = string.gsub(data, '[^' .. b64chars .. '=]', '')
    return (data:gsub('.', function(x)
        if (x == '=') then return '' end
        local r, f = '', (b64chars:find(x) - 1)
        for i = 6, 1, -1 do r = r .. (f % 2 ^ i - f % 2 ^ (i - 1) > 0 and '1' or '0') end
        return r
    end):gsub('%d%d%d?%d?%d?%d?%d?%d?', function(x)
        if (#x ~= 8) then return '' end
        local c = 0
        for i = 1, 8 do c = c + (x:sub(i, i) == '1' and 2 ^ (8 - i) or 0) end
        return string.char(c)
    end))
end

function M.urlencode(str)
    if type(str) ~= "string" then return "" end
    return (str:gsub("([^%w%-_%.~])", function(c) return string.format("%%%02X", string.byte(c)) end))
end

function M.urldecode(str)
    if type(str) ~= "string" then return "" end
    return (str:gsub("%%(%x%x)", function(hex) return string.char(tonumber(hex, 16)) end))
end
