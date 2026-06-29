-- HDGR_DecorDumpCodec.lua -- DD2 owned-decor export codec. Byte-compatible with
-- the DumpDecor addon's "DD2:" string so housing.wowdb.com's decor-sync parser
-- accepts HDG's export unchanged. e-only: no pi/po (placed-location is
-- underivable and the per-instance enumeration taints -- see
-- docs/HDGR_WOWDB_DECOR_DUMP_FORMAT.md for the full investigation).
--
-- Wire format:
--   "DD2:" .. LibDeflate:EncodeForPrint(LibDeflate:CompressDeflate(
--               AceSerializer:Serialize(payload), {level=9}))
-- Payload (short keys, matching DumpDecor): v av ts wb wv wd wr wi wt e
--   e entries are trailing-zero-omitted arrays; we carry {decorID, total} only.
HDG = HDG or {}
HDG.DecorDumpCodec = HDG.DecorDumpCodec or {}
local C = HDG.DecorDumpCodec

local EXPORT_VERSION = 3
local AceSerializer = LibStub("AceSerializer-3.0")
local LibDeflate    = LibStub("LibDeflate")

local REGION_NAMES = { [1] = "US", [2] = "KR", [3] = "EU", [4] = "TW", [5] = "CN" }

-- version, build, buildDate, tocVersion, regionID, regionName
local function buildInfo()
    local version, build, date, toc = GetBuildInfo()
    local regionID = GetCurrentRegion and GetCurrentRegion() or 0  -- exception(boundary): GetCurrentRegion absent in test harness
    return version, build, date, toc, regionID, (REGION_NAMES[regionID] or "Unknown")
end

local function addonVersion()
    if C_AddOns and C_AddOns.GetAddOnMetadata then  -- exception(boundary): C_AddOns absent in test harness
        return C_AddOns.GetAddOnMetadata("HousingDecorGuide", "Version") or "?"
    end
    return "?"
end

-- entries: array of { decorID = <int>, count = <int> }. opts.av overrides version.
-- Pure (no lib calls) so the payload shape is testable without the codec chain.
function C.BuildPayload(entries, opts)
    opts = opts or {}
    local wv, wb, wd, wt, wi, wr = buildInfo()
    local payload = {
        v  = EXPORT_VERSION,
        av = opts.av or addonVersion(),
        ts = time(),
        wb = wb, wv = wv, wd = wd, wt = wt, wi = wi, wr = wr,
        e  = {},
    }
    for _, ent in ipairs(entries) do
        payload.e[#payload.e + 1] = { ent.decorID, ent.count or 0 }
    end
    return payload
end

function C.Encode(entries, opts)
    local serialized = AceSerializer:Serialize(C.BuildPayload(entries, opts))
    local compressed = LibDeflate:CompressDeflate(serialized, { level = 9 })
    return "DD2:" .. LibDeflate:EncodeForPrint(compressed)
end

-- Round-trip / verification helper: "DD2:..." -> payload table, or nil on any
-- malformed input (the website owns the real consumer; this is for our tests).
function C.Decode(str)
    local enc = type(str) == "string" and str:match("^DD2:(.+)$")
    if not enc then return nil end  -- exception(boundary): untrusted / round-trip input
    local compressed = LibDeflate:DecodeForPrint(enc)
    if not compressed then return nil end  -- exception(boundary): malformed input
    local serialized = LibDeflate:DecompressDeflate(compressed)
    if not serialized then return nil end  -- exception(boundary): malformed input
    local ok, payload = AceSerializer:Deserialize(serialized)
    if not ok then return nil end  -- exception(boundary): malformed input
    return payload
end
