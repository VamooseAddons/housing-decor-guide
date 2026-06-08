-- HDG.Selectors -- Removalist family
-- ============================================================================
-- Pure selectors over session.ui.removalist + the static HDG.NeighborhoodDB
-- (a module global -- constant data, so it carries no `reads` path).
--   removalist.faction          -> "alliance" | "horde"   (dropdown current)
--   removalist.factionMenuItems -> { {value,text}, ... }   (dropdown menu)
--   removalist.plotListRows     -> { { plot, letter, label }, ... } for the selected faction

HDG = HDG or {}
HDG.Selectors = HDG.Selectors or {}
local Selectors = HDG.Selectors

-- Neighborhood RENDER uiMapIDs per faction. CONFIRMED in-game -- both have map art that
-- is queryable client-side regardless of faction/location, so R1 (cross-faction render)
-- is SOLVED. NOTE: the DB2 NeighborhoodMap.MapID (2735/2736) are NOT uiMaps (no GetMapInfo).
--   alliance = 2352  "Founder's Point"
--   horde    = 2351  "Razorwind Shores"
local NEIGHBORHOOD_UIMAP = { alliance = 2352, horde = 2351 }

-- Community orientation buckets -> degrees clockwise.
local LETTER_DEG = { A = 0, B = 90, C = 180, D = 270 }

local function _letterOf(faction, plot)
    if not plot then return nil end
    local list = HDG.NeighborhoodDB[faction]
    for i = 1, #list do
        if list[i].plot == plot then return list[i].letter end
    end
    return nil
end

local function _plotData(faction, plot)
    if not plot then return nil end
    local list = HDG.NeighborhoodDB[faction]
    for i = 1, #list do
        if list[i].plot == plot then return list[i] end
    end
    return nil
end

Selectors:Register("removalist.faction", {
    reads = { "session.ui.removalist.faction" },
    fn = function(state, ctx)
        return state.session.ui.removalist.faction
    end,
})

-- Faction dropdown menu choices ({value, text}); static, so no state reads.
Selectors:Register("removalist.factionMenuItems", {
    reads = {},
    fn = function(state, ctx)
        return {
            { value = "alliance", text = "Alliance" },
            { value = "horde",    text = "Horde" },
        }
    end,
})

-- Plot rows for the selected faction's neighborhood. `letter` is nil until the
-- community A/B/C/D list is merged into HDG.NeighborhoodDB (a later step).
Selectors:Register("removalist.plotListRows", {
    reads = { "session.ui.removalist.faction",
              "session.ui.removalist.sourcePlot",
              "session.ui.removalist.targetPlot",
              "session.ui.removalist.letterFilter" },
    fn = function(state, ctx)
        local ui = state.session.ui.removalist
        local plots = HDG.NeighborhoodDB[ui.faction]
        local filter = ui.letterFilter
        local rows = {}
        for i = 1, #plots do
            local p = plots[i]
            if not filter or p.letter == filter then
                local isSource = p.plot == ui.sourcePlot
                local isTarget = p.plot == ui.targetPlot
                local label = "Plot " .. p.plot
                if p.letter then label = label .. "  (" .. p.letter .. ")" end
                rows[#rows + 1] = { plot = p.plot, letter = p.letter, label = label,
                                    isSource = isSource, isTarget = isTarget }
            end
        end
        return rows
    end,
})

-- Active letter filter ("A".."D" or nil) -- drives the colour-strip highlight.
Selectors:Register("removalist.letterFilter", {
    reads = { "session.ui.removalist.letterFilter" },
    fn = function(state, ctx)
        return state.session.ui.removalist.letterFilter
    end,
})

-- Map-canvas model: the neighborhood uiMap for the selected faction. The render
-- (controller-side, not here) does the Blizzard C_Map calls. Source + target maps
-- share this for now; they split (zoom-to-plot) once selection lands in Phase 3.
-- Source/Target map models: same neighborhood + picks, but each carries its own
-- `focusPlot` so the controller auto-zooms that side to the relevant plot.
local function _mapModel(ui, focusPlot, role)
    return {
        uiMap      = NEIGHBORHOOD_UIMAP[ui.faction],
        plots      = HDG.NeighborhoodDB[ui.faction],
        sourcePlot = ui.sourcePlot,
        targetPlot = ui.targetPlot,
        focusPlot  = focusPlot,
        role       = role,        -- which pick a click on this map sets ("source"/"target")
    }
end

local MAP_READS = { "session.ui.removalist.faction",
                    "session.ui.removalist.sourcePlot",
                    "session.ui.removalist.targetPlot" }

Selectors:Register("removalist.sourceMapModel", {
    reads = MAP_READS,
    fn = function(state, ctx)
        local ui = state.session.ui.removalist
        return _mapModel(ui, ui.sourcePlot, "source")
    end,
})

Selectors:Register("removalist.targetMapModel", {
    reads = MAP_READS,
    fn = function(state, ctx)
        local ui = state.session.ui.removalist
        return _mapModel(ui, ui.targetPlot, "target")
    end,
})

-- Facing-diagram models: the picked plot's yaw + letter (or nil when unpicked).
Selectors:Register("removalist.sourceFacing", {
    reads = { "session.ui.removalist.faction", "session.ui.removalist.sourcePlot" },
    fn = function(state, ctx)
        local ui = state.session.ui.removalist
        local p = _plotData(ui.faction, ui.sourcePlot)
        return p and { plot = p.plot, yaw = p.yaw, letter = p.letter, which = "source" } or nil
    end,
})
Selectors:Register("removalist.targetFacing", {
    reads = { "session.ui.removalist.faction", "session.ui.removalist.targetPlot" },
    fn = function(state, ctx)
        local ui = state.session.ui.removalist
        local p = _plotData(ui.faction, ui.targetPlot)
        return p and { plot = p.plot, yaw = p.yaw, letter = p.letter, which = "target" } or nil
    end,
})

-- Plot # + letter for the map panel HEADERS (tinted to the blip: source green / target gold).
Selectors:Register("removalist.sourcePlotTitle", {
    reads = { "session.ui.removalist.faction", "session.ui.removalist.sourcePlot" },
    fn = function(state, ctx)
        local p = _plotData(state.session.ui.removalist.faction, state.session.ui.removalist.sourcePlot)
        if not p then return "" end
        return ("|cff40d959Plot %d%s|r"):format(p.plot, p.letter and ("  (" .. p.letter .. ")") or "")
    end,
})
Selectors:Register("removalist.targetPlotTitle", {
    reads = { "session.ui.removalist.faction", "session.ui.removalist.targetPlot" },
    fn = function(state, ctx)
        local p = _plotData(state.session.ui.removalist.faction, state.session.ui.removalist.targetPlot)
        if not p then return "" end
        return ("|cfff2bf33Plot %d%s|r"):format(p.plot, p.letter and ("  (" .. p.letter .. ")") or "")
    end,
})

-- Community letter hexes (mirror LETTER_RGB in HDGR_Controller_Removalist -- keep in
-- sync if a hue is tweaked). Tints A/B/C/D inline in the result-card pair line.
-- (The orientation-key legend is now the removalistRotationKey chip grid, not text.)
local LETTER_HEX = { A = "4587ED", B = "EDCC47", C = "73C75E", D = "F06BCC" }
local function _ckey(l) return "|cff" .. LETTER_HEX[l] .. l .. "|r" end

-- ===== Result card -- structured fields for the Move panel (mockup style) =====
-- Big rotation number + direction + the move pair, as separate widgets. Colours are
-- inline |cff codes: green for the degrees, community letter hexes via _ckey, muted
-- grey for the prompt / no-rotation states.
local RESULT_DIM = "8794a0"   -- muted grey (prompts / no-rotation)
local RESULT_OK  = "73c75e"   -- green (the rotation degrees)

local function _resultDeg(ui)
    -- degrees (0..270) + source/target letters, or nil when not both picked / unknown.
    if not (ui.sourcePlot and ui.targetPlot) then return nil end
    local sl = _letterOf(ui.faction, ui.sourcePlot)
    local tl = _letterOf(ui.faction, ui.targetPlot)
    if not (sl and tl) then return nil end
    return (LETTER_DEG[tl] - LETTER_DEG[sl]) % 360, sl, tl
end

Selectors:Register("removalist.resultCardLead", {
    reads = {},
    fn = function(state, ctx) return "HOUSE & LANDSCAPING ROTATE" end,
})

Selectors:Register("removalist.resultCardDegrees", {
    reads = MAP_READS,
    fn = function(state, ctx)
        local ui = state.session.ui.removalist
        if not ui.sourcePlot then return "|cff" .. RESULT_DIM .. "Pick a source plot|r" end
        if not ui.targetPlot then return "|cff" .. RESULT_DIM .. "Now pick a target plot|r" end
        local deg = _resultDeg(ui)
        if not deg then return "|cff" .. RESULT_DIM .. "Orientation unknown.|r" end
        if deg == 0 then return "|cff" .. RESULT_DIM .. "No rotation|r" end
        return ("|cff" .. RESULT_OK .. "%d deg|r"):format(deg)
    end,
})

Selectors:Register("removalist.resultCardDirection", {
    reads = MAP_READS,
    fn = function(state, ctx)
        local ui = state.session.ui.removalist
        -- Idle states double as the how-to: pick from the list OR click it on the map.
        if not ui.sourcePlot then return "from the list, or click it on the Source map" end
        if not ui.targetPlot then return "from the list, or click it on the Target map" end
        local deg = _resultDeg(ui)
        if not deg then return "" end
        if deg == 0 then return "both plots face the same way" end
        return "clockwise (relative)"
    end,
})

Selectors:Register("removalist.resultCardPair", {
    reads = MAP_READS,
    fn = function(state, ctx)
        local ui = state.session.ui.removalist
        local deg, sl, tl = _resultDeg(ui)
        if not deg then return "" end
        local line1 = ("Plot %d (%s) -> Plot %d (%s)"):format(ui.sourcePlot, _ckey(sl), ui.targetPlot, _ckey(tl))
        if deg == 0 then return line1 end
        local turns = deg / 90
        return ("%s\n%s -> %s = +%d quarter-turn%s"):format(line1, _ckey(sl), _ckey(tl), turns, turns == 1 and "" or "s")
    end,
})

-- Explanatory notes under the chip grid (the "how a move's rotation is read" text that
-- the chips alone don't convey). Letters tinted via _ckey. Static.
Selectors:Register("removalist.rotationNotes", {
    reads = {},
    fn = function(state, ctx)
        local A, B, C, D = _ckey("A"), _ckey("B"), _ckey("C"), _ckey("D")
        return table.concat({
            "Same letter = same orientation: moving keeps your house facing the same way. A different letter rotates your house & landscaping to the new orientation.",
            "",
            "Facing diagrams: your house always faces the bottom edge of the rectangle.",
            "",
            "Examples:",
            B .. " to " .. C .. " = 90 deg clockwise",
            B .. " to " .. D .. " = 180 deg clockwise",
            B .. " to " .. A .. " = 90 deg counter-clockwise",
            "Any letter to the same letter = no rotation",
        }, "\n")
    end,
})
