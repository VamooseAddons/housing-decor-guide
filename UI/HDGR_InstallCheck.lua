-- HDG install check
-- ============================================================================
-- Incomplete-install tripwire. This is NOT a defensive guard -- it exists to
-- make one specific SILENT failure loud.
--
-- WoW skips a TOC entry whose file is absent WITHOUT raising an error. So an
-- addon folder that has lost a subfolder still "loads": every UI\ file runs,
-- finds the tables Core\ and Modules\ were supposed to define missing, and
-- throws its own nil-index error. The player gets ~27 cryptic "attempt to index
-- field 'Constants' (a nil value)" errors, no minimap icon, and not one line
-- pointing at the actual problem -- an empty folder on disk.
--
-- Known cause (diagnosed 2026-08-02 with vectality): a WoW install inside a
-- cloud-synced folder. The CurseForge app stages and moves files while the sync
-- client watches the tree; folders end up empty, and the sync client then
-- reports them as fully synced -- a green check mark on a folder holding zero
-- files. Reinstalling re-triggers it, so the player has no reason to suspect
-- their install and every reason to blame the addon.
--
-- One sentinel per Lua-bearing folder. This file is LAST in the TOC, so every
-- folder has had its chance to run and the check is a plain file-scope read --
-- no polling, no deferred re-check. textures\ carries no Lua; Locale\ degrades
-- to enUS on its own, so neither is worth a sentinel.
--
-- A healthy install costs four table lookups and stops: no frame, no event, no
-- print. The event frame below is created ONLY on an install already known to
-- be broken -- reporting has to wait for a chat frame, and the engine that
-- normally owns event registration (Core\HDGR_BlizzardEvents) is precisely what
-- is missing in that case. If UI\ itself is the empty folder, nothing loads at
-- all, this file included; that case is unreachable from inside the addon.

HDG = HDG or {}

-- folder -> the global/table its files leave behind once they have run.
local SENTINELS = {
    { folder = "Libs",    loaded = function() return _G.LibStub    ~= nil end },
    { folder = "Core",    loaded = function() return HDG.Constants ~= nil end },
    { folder = "Modules", loaded = function() return HDG.TreeList  ~= nil end },
    { folder = "data",    loaded = function() return _G.HDGR_DecorDB ~= nil end },
}

local function _emptyFolders()
    local missing = {}
    for _, s in ipairs(SENTINELS) do
        if not s.loaded() then missing[#missing + 1] = s.folder end
    end
    return missing
end

-- Exposed for tests.
HDG._EmptyInstallFolders = _emptyFolders

local function _reportBrokenInstall(missing)
    print("|cffff4040Vamoose's Housing Decor Guide: your install is incomplete.|r")
    print("Empty or missing: |cffffd100" .. table.concat(missing, ", ")
        .. "|r -- any Lua errors you are seeing come from this, not from a bug.")
    print("Fix: close WoW, delete the HousingDecorGuide folder, reinstall it.")
    print("If WoW lives in Dropbox or OneDrive, move it out of the synced folder "
        .. "first -- cloud sync can report a folder as fully synced while leaving it empty.")
end

-- Broken installs only. Healthy ones never reach past this line.
local broken = _emptyFolders()
if #broken > 0 then
    local checkFrame = CreateFrame("Frame")
    -- The engine that normally owns event registration lives in Core\, which is
    -- one of the folders this branch exists to report as EMPTY. Routing through
    -- BlizzardEvents:_internalSubscribe would silence the message in the only
    -- case it is ever reached. No second event frame on a healthy install --
    -- this whole block is unreachable there.
    checkFrame:RegisterEvent("PLAYER_LOGIN")  -- exception(false-positive): reporting a missing Core\, so Core\HDGR_BlizzardEvents cannot be the transport
    checkFrame:SetScript("OnEvent", function(self)
        self:UnregisterEvent("PLAYER_LOGIN")
        _reportBrokenInstall(broken)
    end)
end
