-- HDGR_Selectors_Menagerie.lua
-- ============================================================================
-- Pure selectors for the Menagerie (House > Pets). Spec: HDGR_PET_TAXONOMY_SPEC
-- rulings 1-14; architecture: HDGR_MENAGERIE_LATTICE_PLAN_2026-08-24.
--
-- Namespaced `menagerie.*` (not `pets.*`) because the shipped Decor-tab pets
-- mode owns those names; the two surfaces converge at plan phase 5.
--
-- The impure edges live in the CONTROLLER by design: playing an animation or a
-- voice (SetAnimation / PlaySound) and capturing the room query. Selectors here
-- emit ids and data only. PetFacts rides the staticData tick; the journal rides
-- the pets tick.

local Selectors = HDG.Selectors
local M = function() return HDG.Constants.MENAGERIE end

-- ===== small pure helpers (no Selectors:Call inside -- keep `calls` honest) ==

local function _bucketOf(height)
    if not height then return nil end   -- exception(nullable): unmeasured species; card shows "?"
    for _, b in ipairs(M().SIZE_BUCKETS) do
        if height <= b.max then return b end
    end
end

-- The join keys a pet contributes (spec section 5, v1 subset): clade motif +
-- family motif where the family genuinely adds one. Pure data from baked fields.
local function _motifsOf(row)
    local out, meta = {}, row.clade and M().CLADE_META[row.clade]
    if meta then out[#out + 1] = meta.motif end
    local fam = M().FAMILY_MOTIF[row.petType]
    if fam and fam ~= (meta and meta.motif) then out[#out + 1] = fam end
    return out
end

local function _matchesSpot(row, ui, PF)
    if ui.roomQuery then
        local motifs = _motifsOf(row)
        for _, m in ipairs(motifs) do
            for _, want in ipairs(ui.roomQuery.motifs) do
                if m == want then return true, m end
            end
        end
        return false
    end
    local bucket = _bucketOf(row.height)
    if ui.spot.surface ~= "any" then
        local meta = row.clade and M().CLADE_META[row.clade]
        if ui.spot.surface == "water" then
            if not (meta and meta.needs:find("water", 1, true)) then return false end
        elseif not bucket or bucket.key ~= ui.spot.surface then
            return false
        end
    end
    if ui.spot.size ~= "any" and (not bucket or bucket.key ~= ui.spot.size) then return false end
    for want in pairs(ui.spot.wants) do
        if want == "quiet" and PF:Voice(row.speciesID) then return false end
        if want == "glow" then
            local prof = PF:AnimProfile(row.speciesID)
            local g = prof and prof.glow
            if not (g and (g[1] > 0 or g[3] > 0 or g[2] >= 3)) then return false end
        end
    end
    return true
end

local function _matchesAxis(row, ui)
    if ui.axval == "all" then return true end
    if ui.axis == "kind" then return row.kind == ui.axval end
    if ui.axis == "clade" then return row.clade == ui.axval end
    if ui.axis == "family" then return row.petType == ui.axval end
    if ui.axis == "size" then
        local b = _bucketOf(row.height)
        return b ~= nil and b.key == ui.axval
    end
    return false
end

-- ===== the list =============================================================
-- Row envelopes carry name + kind ONLY (ruling 13: no size on rows; scale lives
-- in the scene). `why` appears only under a room query, naming the matched motif.
Selectors:Register("menagerie.items", {
    memoized = true,
    reads = { "session.ui.menagerie.mode", "session.ui.menagerie.axis",
              "session.ui.menagerie.axval", "session.ui.menagerie.spot",
              "session.ui.menagerie.roomQuery", "session.ui.menagerie.selectedSpeciesID",
              "session.resolvers.pets.tick", "session.resolvers.staticData.tick" },
    fn = function(state)
        local ui = state.session.ui.menagerie
        local PF = HDG.StaticData.PetFacts
        local out = {}
        for _, row in ipairs(HDG.PetObserver:GetAttachable()) do
            local keep, why
            if ui.mode == "byPet" then
                keep = _matchesAxis(row, ui)
            else
                keep, why = _matchesSpot(row, ui, PF)
            end
            if keep then
                out[#out + 1] = {
                    kind      = "menagerieRow",
                    speciesID = row.speciesID,
                    name      = row.customName or row.name,
                    kindLabel = row.kind or "?",   -- exception(nullable): post-build species -- "?" is the honest mark
                    selected  = row.speciesID == ui.selectedSpeciesID,
                    why       = why,
                }
            end
        end
        return out
    end,
})

Selectors:Register("menagerie.headerLabel", {
    calls = { "menagerie.items" },
    reads = { "session.resolvers.pets.tick" },
    fn = function(state, ctx)
        local shown = #Selectors:Call("menagerie.items", state, ctx)
        local total = #HDG.PetObserver:GetAttachable()
        return string.format("%d of %d", shown, total)
    end,
})

-- ===== the two-row filter ===================================================
Selectors:Register("menagerie.axes", {
    reads = { "session.ui.menagerie.axis" },
    fn = function(state)
        local out = {}
        for _, a in ipairs(M().AXES) do
            out[#out + 1] = { value = a.value, label = a.label,
                              active = a.value == state.session.ui.menagerie.axis }
        end
        return out
    end,
})

Selectors:Register("menagerie.axisValues", {
    memoized = true,
    reads = { "session.ui.menagerie.axis", "session.ui.menagerie.axval",
              "session.resolvers.pets.tick", "session.resolvers.staticData.tick" },
    fn = function(state)
        local ui  = state.session.ui.menagerie
        local out = { { value = "all", label = "All", active = ui.axval == "all" } }
        local function add(value, label, n)
            out[#out + 1] = { value = value, label = label, count = n,
                              active = ui.axval == value }
        end
        if ui.axis == "kind" then
            -- Top-N kinds AMONG THE PLAYER'S attachable pets (not the global
            -- collection): counts the player can act on.
            local counts = {}
            for _, row in ipairs(HDG.PetObserver:GetAttachable()) do
                if row.kind then counts[row.kind] = (counts[row.kind] or 0) + 1 end
            end
            local keys = {}
            for k in pairs(counts) do keys[#keys + 1] = k end
            table.sort(keys, function(a, b)
                if counts[a] ~= counts[b] then return counts[a] > counts[b] end
                return a < b
            end)
            for i = 1, math.min(#keys, M().KIND_CHIP_MAX) do
                add(keys[i], (keys[i]:gsub("^%l", string.upper)), counts[keys[i]])
            end
        elseif ui.axis == "clade" then
            local counts = {}
            for _, row in ipairs(HDG.PetObserver:GetAttachable()) do
                if row.clade then counts[row.clade] = (counts[row.clade] or 0) + 1 end
            end
            local keys = {}
            for k in pairs(counts) do keys[#keys + 1] = k end
            table.sort(keys)
            for _, k in ipairs(keys) do add(k, (k:gsub("^%l", string.upper)), counts[k]) end
        elseif ui.axis == "family" then
            for i, name in ipairs(HDG.PetObserver:GetFamilies()) do
                add(i, name)
            end
        elseif ui.axis == "size" then
            for _, b in ipairs(M().SIZE_BUCKETS) do add(b.key, b.label) end
        end
        return out
    end,
})

-- ===== the card =============================================================
Selectors:Register("menagerie.selected", {
    memoized = true,
    reads = { "session.ui.menagerie.selectedSpeciesID",
              "session.resolvers.pets.tick", "session.resolvers.staticData.tick" },
    fn = function(state)
        local sid = state.session.ui.menagerie.selectedSpeciesID
        if not sid then return nil end            -- exception(nullable): nothing picked yet
        local row = HDG.PetObserver:GetBySpecies(sid)
        if not row then return nil end            -- exception(nullable): selection outlived a journal rebuild
        return row
    end,
})

Selectors:Register("menagerie.hasSelection", {
    calls = { "menagerie.selected" },
    fn = function(state, ctx)
        return Selectors:Call("menagerie.selected", state, ctx) ~= nil
    end,
})

Selectors:Register("menagerie.card.title", {
    calls = { "menagerie.selected" },
    fn = function(state, ctx)
        local p = Selectors:Call("menagerie.selected", state, ctx)
        if not p then return "Pick a pet" end
        return p.customName or p.name
    end,
})

Selectors:Register("menagerie.card.family", {
    calls = { "menagerie.selected" },
    reads = { "session.resolvers.pets.tick" },
    fn = function(state, ctx)
        local p = Selectors:Call("menagerie.selected", state, ctx)
        if not p then return "" end
        local fam = HDG.PetObserver:GetFamilies()[p.petType]  -- exception(nullable): unknown petType
        return fam and ("Family: " .. fam) or ""
    end,
})

Selectors:Register("menagerie.card.howBig", {
    calls = { "menagerie.selected" },
    fn = function(state, ctx)
        local p = Selectors:Call("menagerie.selected", state, ctx)
        if not p then return "" end
        local b = _bucketOf(p.height)
        if not b then return "?" end   -- unmeasured: the honest mark, never a guess (spec ruling 6)
        return string.format("%s -- height %.2f (you are 2.242)", b.label, p.height)
    end,
})

Selectors:Register("menagerie.card.needs", {
    calls = { "menagerie.selected" },
    fn = function(state, ctx)
        local p = Selectors:Call("menagerie.selected", state, ctx)
        if not p then return "" end
        local meta = p.clade and M().CLADE_META[p.clade]
        return meta and meta.needs or "?"
    end,
})

Selectors:Register("menagerie.card.matches", {
    calls = { "menagerie.selected" },
    fn = function(state, ctx)
        local p = Selectors:Call("menagerie.selected", state, ctx)
        if not p then return "" end
        return table.concat(_motifsOf(p), "  ")
    end,
})

Selectors:Register("menagerie.card.light", {
    calls = { "menagerie.selected" },
    reads = { "session.resolvers.staticData.tick" },
    fn = function(state, ctx)
        local p = Selectors:Call("menagerie.selected", state, ctx)
        if not p then return "" end
        local prof = HDG.StaticData.PetFacts:AnimProfile(p.speciesID)
        local g = prof and prof.glow   -- exception(nullable): 6 unparsed models
        if not g then return "?" end
        if g[1] > 0 then return "carries a light -- it will illuminate its spot" end
        if g[3] > 0 or g[2] >= 3 then return "glows" end
        return "no glow"
    end,
})

-- ===== the behaviour flowchart (ruling 10: THE one behaviour surface) =======
-- Data only. Node labels come from the curated per-model table when eyeballed;
-- otherwise the honest fallback "Stand (variation N)" with unverified = true.
Selectors:Register("menagerie.flow", {
    memoized = true,
    calls = { "menagerie.selected" },
    reads = { "session.resolvers.staticData.tick" },
    fn = function(state, ctx)
        local p = Selectors:Call("menagerie.selected", state, ctx)
        if not p then return nil end   -- exception(nullable): card empty pre-selection
        local PF   = HDG.StaticData.PetFacts
        local prof = PF:AnimProfile(p.speciesID)
        if not prof then return nil end  -- exception(nullable): unparsed model; section hides
        local nodes = {}
        for _, e in ipairs(prof.idle) do
            local id, var, pct, ms = e[1], e[2], e[3], e[4]
            local key   = id .. ":" .. var
            local label = prof.labels and prof.labels[key]
            nodes[#nodes + 1] = {
                animID = id, variation = var, pct = pct, seconds = ms / 1000,
                label = label or (var == 0 and "Stand" or ("Stand (variation " .. var .. ")")),
                unverified = label == nil and var ~= 0,
            }
        end
        local voice = PF:Voice(p.speciesID)
        local voiceNode
        if voice then
            local cadence = voice.delayMin
                and string.format("every %d-%ds", voice.delayMin, voice.delayMax)
                or "now and then"
            voiceNode = { word = voice.word or "sound", cadence = cadence,
                          kits = voice.kits, sharedWith = voice.sharedWith }
        end
        return { nodes = nodes, voice = voiceNode, also = prof.also }
    end,
})

-- ===== the scene ============================================================
Selectors:Register("menagerie.scene", {
    calls = { "menagerie.selected" },
    reads = { "session.ui.menagerie.scene", "session.resolvers.staticData.tick" },
    fn = function(state, ctx)
        local p = Selectors:Call("menagerie.selected", state, ctx)
        if not p then return nil end   -- exception(nullable): empty stage pre-selection
        local ui = state.session.ui.menagerie.scene
        local decor
        if ui.decorID then
            local d = HDG.StaticData.PetFacts:SceneDecor()[ui.decorID]
            decor = { decorID = ui.decorID, file = d.file, name = d.name }
        end
        return {
            speciesID    = p.speciesID,
            petDisplayID = p.displayID,   -- exception(nullable): a species with no display renders 2D fallback
            petHeight    = p.height,
            petScale     = HDG.StaticData.PetFacts:SceneScale(p.speciesID),
            petLift      = HDG.StaticData.PetFacts:SceneLift(p.speciesID),
            petGirth     = HDG.StaticData.PetFacts:SceneGirth(p.speciesID),
            decor        = decor,
            withYou      = ui.withYou == true,
        }
    end,
})

-- ===== scene strip chips ====================================================
Selectors:Register("menagerie.sceneChips", {
    reads = { "session.ui.menagerie.scene", "session.resolvers.staticData.tick" },
    fn = function(state)
        local ui = state.session.ui.menagerie.scene
        local out = { { value = "none", label = "--", active = ui.decorID == nil } }
        local decor = HDG.StaticData.PetFacts:SceneDecor()
        for _, did in ipairs(M().SCENE_CHIP_DECOR) do
            out[#out + 1] = { value = did, label = decor[did].name, active = ui.decorID == did }
        end
        out[#out + 1] = { value = "you", label = "You", active = ui.withYou == true }
        return out
    end,
})

-- ===== chip-strip adapters ==================================================
-- ChipStrip wants a FLAT items[]; these project the richer selectors above into
-- chip streams. Cell kinds (and their click dispatches) live in the controller.

Selectors:Register("menagerie.isByPet", {
    reads = { "session.ui.menagerie.mode" },
    fn = function(state) return state.session.ui.menagerie.mode == "byPet" end,
})
Selectors:Register("menagerie.isBySpot", {
    reads = { "session.ui.menagerie.mode" },
    fn = function(state) return state.session.ui.menagerie.mode == "bySpot" end,
})

Selectors:Register("menagerie.modeChips", {
    reads = { "session.ui.menagerie.mode" },
    fn = function(state)
        local mode = state.session.ui.menagerie.mode
        return {
            { value = "byPet",  label = "By Pet",  active = mode == "byPet" },
            { value = "bySpot", label = "By Spot", active = mode == "bySpot" },
        }
    end,
})

-- The By Spot needs-vocabulary (ruling 14: exclusive to this mode).
local SPOT_CHIPS = {
    surface = { { "any", "Anywhere" }, { "shelf", "Shelf" }, { "table", "Table" },
                { "floor", "Floor" }, { "water", "Water" } },
    size    = { { "any", "Any size" }, { "shelf", "Small" }, { "table", "Medium" },
                { "floor", "Large" } },
}
local WANT_CHIPS = { { "glow", "Glow" }, { "quiet", "Stay quiet" } }

local function _spotChipRow(state, group)
    local spot, out = state.session.ui.menagerie.spot, {}
    for _, c in ipairs(SPOT_CHIPS[group]) do
        out[#out + 1] = { group = group, value = c[1], label = c[2],
                          active = spot[group] == c[1] }
    end
    return out
end
Selectors:Register("menagerie.spotSurfaceChips", {
    reads = { "session.ui.menagerie.spot" },
    fn = function(state) return _spotChipRow(state, "surface") end,
})
Selectors:Register("menagerie.spotSizeChips", {
    reads = { "session.ui.menagerie.spot" },
    fn = function(state) return _spotChipRow(state, "size") end,
})
Selectors:Register("menagerie.spotWantChips", {
    reads = { "session.ui.menagerie.spot" },
    fn = function(state)
        local wants, out = state.session.ui.menagerie.spot.wants, {}
        for _, c in ipairs(WANT_CHIPS) do
            out[#out + 1] = { group = "wants", value = c[1], label = c[2],
                              active = wants[c[1]] == true }
        end
        return out
    end,
})

-- The flowchart as one chip stream: phases in idle-mix order, then the voice.
Selectors:Register("menagerie.flowChips", {
    calls = { "menagerie.flow" },
    fn = function(state, ctx)
        local flow = Selectors:Call("menagerie.flow", state, ctx)
        if not flow then return {} end   -- exception(nullable): empty strip pre-selection
        local out = {}
        for _, n in ipairs(flow.nodes) do
            out[#out + 1] = { nodeType = "phase", label = n.label, pct = n.pct,
                              seconds = n.seconds, unverified = n.unverified,
                              animID = n.animID, variation = n.variation }
        end
        if flow.voice then
            out[#out + 1] = { nodeType = "voice", label = flow.voice.word,
                              cadence = flow.voice.cadence, kits = flow.voice.kits,
                              sharedWith = flow.voice.sharedWith }
        end
        return out
    end,
})

Selectors:Register("menagerie.alsoChips", {
    calls = { "menagerie.flow" },
    fn = function(state, ctx)
        local flow = Selectors:Call("menagerie.flow", state, ctx)
        if not flow or not flow.also then return {} end  -- exception(nullable): empty pre-selection
        -- SHOWABLE only: the repertoire carries dozens of combat/movement ids a
        -- player has no reason to click; unfiltered, Pandaren Monk's 40 chips
        -- overflowed the window (in-game smoke, 2026-08-24). Dedupe by verb --
        -- 71 and 100 are both "sleeps"; one chip serves.
        local out, seen = {}, {}
        for _, id in ipairs(flow.also) do
            local verb = M().SHOWABLE_ANIMS[id]
            if verb and not seen[verb] then
                seen[verb] = true
                out[#out + 1] = { animID = id, label = verb }
            end
        end
        return out
    end,
})

-- Described ships HIDDEN in v1 (plan ruling): the gate is honest -- it opens when
-- a description DB exists, with no layout change. Today there is none.
Selectors:Register("menagerie.hasDescription", {
    reads = { "session.resolvers.staticData.tick" },
    fn = function() return false end,
})
