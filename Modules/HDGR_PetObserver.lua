-- HDG.PetObserver
-- ============================================================================
-- Sole owner of the C_PetJournal namespace (invariant 13). Holds the module-local
-- index of the player's DECOR-ATTACHABLE pets and bumps
-- session.resolvers.pets.tick so pure selectors re-pull it. Species-A
-- facade-poll per HDGR_Resolvers.lua's taxonomy.
--
--   PET_JOURNAL_LIST_UPDATE -> (debounced) Rebuild -> dispatch PETS_LIST_CHANGED
--      -> session.resolvers.pets.tick++ -> pets.* selectors re-run
--      -> selectors call GetAttachable() / GetFamilies() (live index read)
--
-- Public API:
--   :GetAttachable()          -> array of entries, height-ascending
--   :GetFamilies()            -> localized family names, indexed by petType
--   :GetBySpecies(speciesID)  -> one entry, or nil
--   :Resolve(speciesID)       -> modelPreview info table, or nil
--
-- ============================================================================
-- DO NOT CALL ANY C_PetJournal SETTER, FROM HERE OR ANYWHERE ELSE.
--
-- The pet journal's filters are ONE GLOBAL CACHE shared by every consumer.
-- Blizzard's own housing pet picker
-- (Blizzard_HouseEditorCustomizationPetTemplates.lua) caches and restores them
-- around its pane, and its comment says that only works "since the pet journal
-- UI can't be open in house edit mode". HDG's Companion CAN be open in house
-- edit mode, so that precondition does not hold for us: setting a filter here
-- would fight Blizzard's save/restore and corrupt the player's journal state.
--
-- GetNumPets / GetPetInfoByIndex are FILTERED and therefore banned too -- they
-- return whatever Blizzard's pane last set. GetOwnedPetIDs is verified NOT
-- filter-affected and is the only sanctioned enumeration.
-- tests/test_pets.lua asserts no setter is ever called.
-- ============================================================================

HDG = HDG or {}
HDG.PetObserver = HDG.PetObserver or {}
local P = HDG.PetObserver

-- PET_JOURNAL_LIST_UPDATE arrives in bursts at login and on every
-- cage / learn / rename; one rebuild per burst is enough.
local REBUILD_DEBOUNCE = 0.4

P._attachable = {}
P._bySpecies  = {}
P._families   = {}
P._pending    = false
P._summonedGUID = nil

-- One owned pet -> index entry, or nil when it cannot ride decor.
local function _entryFor(petID)
    local info = _G.C_PetJournal.GetPetInfoTableByPetID(petID)
    if not info then return nil end   -- exception(boundary): journal miss on a GUID that just went stale
    if not info.canAttachToDecor then return nil end
    return {
        petID      = petID,
        speciesID  = info.speciesID,
        name       = info.name,
        customName = info.customName,   -- exception(boundary): nil unless the player renamed it
        -- The name the player actually SEES, derived once. It is the list's sort
        -- key and its search key, and four call sites used to each re-derive it --
        -- one of them disagreeing would sort a renamed pet away from where the
        -- eye looks for it.
        displayName = info.customName or info.name,
        icon       = info.icon,
        petType    = info.petType,
        displayID  = info.displayID,    -- exception(boundary): nil for a species with no display
        -- nil for a species that was never measured. NOT defaulted: see
        -- StaticData.PetSizes -- there is nothing honest to substitute.
        height     = HDG.StaticData.PetSizes:Get(info.speciesID),
        -- Menagerie taxonomy baked at row build (_bakeSourceTypes for pets --
        -- plan section 2): selectors strict-read these, no per-paint joins.
        -- nil,nil = a species newer than the last data build; the card shows "?".
        kind       = HDG.StaticData.PetFacts:Taxonomy(info.speciesID),
        clade      = select(2, HDG.StaticData.PetFacts:Taxonomy(info.speciesID)),
    }
end

-- Alphabetical by the DISPLAYED name. The list was height-ascending while the row
-- carried a size bar and the ordering was itself the reading -- ruling 13 took the
-- bar off the row and moved scale into the card's scene, which left the order
-- saying nothing a player could use. A browse surface of ~2,000 rows that you
-- arrive at knowing the name you want sorts by that name.
--
-- displayName, not name: a renamed pet must sit where its rendered label puts it.
--
-- speciesID is the final tie-break so this is a TOTAL order. The list is built by
-- iterating a species-keyed table, and pairs() order is not deterministic under
-- LuaJIT -- without a total order, table.sort (which is not stable) would let that
-- non-determinism surface as rows shuffling between reloads.
local function _byDisplayName(a, b)
    if a.displayName ~= b.displayName then return a.displayName < b.displayName end
    return a.speciesID < b.speciesID
end

-- Localized family names, indexed by petType. Read once per rebuild so selectors
-- never touch the FrameXML globals themselves (invariant 1).
local function _families()
    local out = {}
    for i = 1, _G.C_PetJournal.GetNumPetTypes() do
        out[i] = _G["BATTLE_PET_NAME_" .. i]   -- exception(boundary): FrameXML localized global
    end
    return out
end

-- ONE ROW PER SPECIES, and the exemplar is the lowest petID.
--
-- Placing a pet on decor does NOT consume it: one pet can sit on as many decor as
-- you own, so a collector's second and third copy of a species add nothing to
-- browse. (The row key is the speciesID besides, so duplicates would also hand the
-- scrollbox colliding keys.)
--
-- Lowest petID rather than first-seen because GetOwnedPetIDs' order is not a
-- documented guarantee -- an order-dependent exemplar could change the displayed
-- name between sessions when one copy is renamed and another is not.
local function _keepAsExemplar(existing, candidate)
    if not existing then return true end
    return candidate.petID < existing.petID
end

-- Rebuild the whole index. Wholesale is cheap enough: one GetOwnedPetIDs plus a
-- table read per pet, against a collection that tops out in the low thousands.
function P:Rebuild()
    local ids = _G.C_PetJournal.GetOwnedPetIDs() or {}  -- exception(boundary): nil before the journal populates
    local bySpecies = {}
    for i = 1, #ids do
        local entry = _entryFor(ids[i])
        if entry and _keepAsExemplar(bySpecies[entry.speciesID], entry) then
            bySpecies[entry.speciesID] = entry
        end
    end
    local list = {}
    for _, entry in pairs(bySpecies) do list[#list + 1] = entry end
    table.sort(list, _byDisplayName)
    self._attachable = list
    self._bySpecies  = bySpecies
    self._families   = _families()
end

-- ===== what is out ==========================================================
-- LATCHED, never passed through. C_PetJournal.GetSummonedPetGUID() reads nil for
-- up to 1.5s after a summon, so a paint triggered by the click itself would read
-- the window rather than the result -- VPP shipped a button saying "Summon" with
-- the pet already out. COMPANION_UPDATE is the client saying its companion state
-- has settled, and is the only honest moment to read it.
function P:GetSummonedGUID()
    return self._summonedGUID   -- exception(nullable): nil is "nothing is out"
end

-- Live read behind the facade, gated by session.resolvers.pets.tick -- the same
-- sanctioned shape as AchievementObserver:IsEarned. Asked rather than assumed:
-- the client refuses a summon in a pet battle, on a vehicle, or in a restricted
-- area, and a control that cannot work should say so rather than eat the click.
function P:IsSummonable(petID)
    if not petID then return false end
    return _G.C_PetJournal.PetIsSummonable(petID) and true or false
end

-- TOGGLE: SummonPetByGUID with the GUID that is already out DISMISSES it (the
-- wow-api entry is verified with exactly that gotcha). So the guard is not
-- politeness -- without it, clicking Summon on the pet already out dismisses it.
function P:Summon(petID)
    if not petID then return false end
    if _G.C_PetJournal.GetSummonedPetGUID() == petID then return false end
    _G.C_PetJournal.SummonPetByGUID(petID)
    return true
end

function P:Dismiss()
    local out = _G.C_PetJournal.GetSummonedPetGUID()
    if not out then return false end
    _G.C_PetJournal.SummonPetByGUID(out)   -- same GUID = dismiss
    return true
end

-- companionType is "CRITTER" / "MOUNT" / ... -- Blizzard's own pet collection filters
-- on it. Without the filter, mounting up re-ran every pets.* selector for a summoned
-- GUID that had not changed.
function P:OnCompanionUpdate(companionType)
    if companionType and companionType ~= "CRITTER" then return end  -- exception(boundary): arg absent on some fires
    self._summonedGUID = _G.C_PetJournal.GetSummonedPetGUID()
    HDG.Store:Dispatch({ type = HDG.Constants.ACTIONS.PETS_SUMMONED_CHANGED, payload = {} })
end

function P:GetAttachable() return self._attachable end
function P:GetFamilies()   return self._families end

function P:GetBySpecies(speciesID)
    return self._bySpecies[speciesID]   -- exception(nullable): the player may not own that species
end

-- Widget-seam resolve for modelPreview's pet path, mirroring
-- HousingCatalogObserver:Resolve(itemID): the live read happens HERE, behind the
-- module boundary, so the selector supplying speciesID stays pure. nil for a
-- species the player does not own or that cannot ride decor -- the preview then
-- shows its placeholder.
function P:Resolve(speciesID)
    if not speciesID then return nil end
    local entry = self._bySpecies[speciesID]
    if not entry then return nil end   -- exception(nullable): unowned / non-attachable species
    -- First return is the CARD scene, the one Blizzard's own pet grid uses. It is
    -- a REGISTERED scene, which is what makes the modelPreview camera work at all.
    local cardSceneID = _G.C_PetJournal.GetPetModelSceneInfoBySpeciesID(speciesID)
    return {
        petDisplayID   = entry.displayID,
        uiModelSceneID = cardSceneID,
        name           = entry.displayName,
        iconTexture    = entry.icon,
    }
end

-- Widget-seam resolve for petScene: the animation kit the species' authored
-- card scene drives its actor with. A raw created actor loops sequence 0 by
-- restarting it, which re-fires one-shot particle emitters -- a pet whose idle
-- is one short sequence (Mote of Nasz'uro: 334ms Stand) strobes ~3x/sec.
-- PlayAnimationKit(kit) is what stops it (isolated via /papro reg/regscene/kit,
-- 2026-08-24: the C_ModelInfo registrations changed nothing; the kit did).
-- Memoized: authored data, stable for the session.
function P:CardAnimKit(speciesID)
    if not speciesID then return nil end
    local memo = self._kitBySpecies
    if not memo then memo = {}; self._kitBySpecies = memo end
    if memo[speciesID] ~= nil then
        return memo[speciesID] or nil   -- false memoizes "no kit"
    end
    local kit = false
    local sceneID = _G.C_PetJournal.GetPetModelSceneInfoBySpeciesID(speciesID)
    if sceneID then
        local _, _, actorIDs = _G.C_ModelInfo.GetModelSceneInfoByID(sceneID)
        for _, aid in ipairs(actorIDs or {}) do
            local info = _G.C_ModelInfo.GetModelSceneActorInfoByID(aid)
            if info and info.scriptTag == "unwrapped" and info.modelActorDisplayID then
                local disp = _G.C_ModelInfo.GetModelSceneActorDisplayInfoByID(info.modelActorDisplayID)
                kit = (disp and disp.animationKitID) or false
                break
            end
        end
    end
    memo[speciesID] = kit
    return kit or nil
end

-- PET_JOURNAL_LIST_UPDATE -> debounced rebuild + tick bump.
function P:OnListUpdate()
    if self._pending then return end
    self._pending = true
    _G.C_Timer.After(REBUILD_DEBOUNCE, function()
        self._pending = false
        self:Rebuild()
        HDG.Store:Dispatch({ type = HDG.Constants.ACTIONS.PETS_LIST_CHANGED, payload = {} })
    end)
end

HDG.Modules:Declare({
    name = "PetObserver",
    -- Sole owner for the production path. Core/HDGR_Debug.lua's /hdg petscale probe
    -- reads the namespace directly and is the one annotated carve-out.
    ownsBlizzardNamespaces = { "C_PetJournal", "C_ModelInfo" },
    dependencies = {},
    blizzardEvents = {
        PET_JOURNAL_LIST_UPDATE = { handler = "OnListUpdate" },
        COMPANION_UPDATE        = { handler = "OnCompanionUpdate" },
    },
    onEnable = function()
        P:Rebuild()
        -- Seed it: a pet already out at login must paint "Dismiss" before any
        -- COMPANION_UPDATE arrives.
        P._summonedGUID = _G.C_PetJournal.GetSummonedPetGUID()
    end,
    -- BlizzardEvents resolves handlers on this def table (module = the def), so the
    -- first arg is the def and the event payload follows. Forward it: COMPANION_UPDATE's
    -- companionType is the whole point of the filter in P:OnCompanionUpdate.
    OnListUpdate      = function(_, ...) P:OnListUpdate(...) end,
    OnCompanionUpdate = function(_, ...) P:OnCompanionUpdate(...) end,
})
