-- HDGR_RecipeSourceParse -- how you get an unlearned recipe, from the
-- profession book's own hover text.
--
-- C_TradeSkillUI.GetRecipeSourceText(spellID) returns the string behind the
-- prof book's "Recipe Unlearned" tooltip ("Vendor: Arras|nZone: Dalaran|nCost:
-- 4<gold>"). It is UNDOCUMENTED -- absent from the generated API docs, but
-- called by Blizzard's live ProfessionsRecipeSchematicForm -- and it answers
-- COLD, with no tradeskill session open. The tokenizer is ported from
-- VamoosesWorkbench's Study view, which is where the traps below were found.
--
-- PURE, and a Core file rather than a method on ProfessionScanner: it is string
-- work with no Blizzard call in it, and the scanner is stubbed out across most
-- of the test suite. Here it loads with the Core engines, so the SHIPPED
-- tokenizer is the one under test -- against the 305 real strings HDG's own
-- decor recipes return (tests/fixtures/recipe_source_corpus.lua).
--
-- THE TRAPS, all of them found live rather than reasoned about:
--
--   * The separator is `|n`, the WoW escape -- NOT a newline. A FontString
--     RENDERS it as a line break, so the tooltip looks multi-line and a
--     `\n` split silently never fires. Worse, naive label matching reads
--     "Arras|nZone:" as the word "nZone" and the zone is lost: 2184 of 2193
--     vendors parsed zoneless before this was understood. Normalise FIRST.
--   * A few strings use a real CR instead (corpus 2165), so those normalise too.
--   * `|n|n` opens a NEW source. One recipe can list several vendors.
--   * The label's colour code wraps the COLON, and the space lands on either
--     side of the reset: both "Vendor: |rName" and "Drop:|r Name" occur.
--   * Values legitimately contain colons ("World Quest: Work Order: Contract:
--     Order of Embers"), so a value runs to the next KNOWN label, not to the
--     next colon.
--   * One vendor can carry TWO Zone fields.
--   * Cost carries money textures AND currency hyperlinks
--     (`|Hcurrency:3379|h|T...|t|h`). Those are the "currencies" the tooltip
--     exists to show, so cost is stripped of COLOUR only -- never of art.

HDG = HDG or {}
HDG.RecipeSourceParse = HDG.RecipeSourceParse or {}

local P = HDG.RecipeSourceParse

-- Longest-first so "Profession Trainer" masks "Profession", and "World Quest"
-- masks "Quest". `Gather` is NOT in the donor addon's list: HDG's own decor
-- corpus contains one ("Gather: World Nodes"), which would otherwise degrade to
-- a generic source.
local SOURCE_LABELS = {
    "Profession Trainer", "World Quest", "Specialization", "Discovery",
    "Profession", "Treasure", "Trainer", "Vendor", "Gather", "Drop",
    "Quest", "Recipe",
}

-- Fields attach to the source that opened before them.
local FIELD_LABELS = { Zone = "zone", Cost = "cost", Faction = "faction", Requires = "requires" }

-- Colour codes only. Textures (|T..|t) and hyperlinks (|H..|h) are CONTENT --
-- they are the currency icons -- so stripping them here would delete the thing
-- the Cost field exists to show.
local function stripColour(s)
    return (s:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|cn[^:]+:", ""):gsub("|r", ""))
end

local function trim(s)
    return (s:gsub("^%s+", ""):gsub("%s+$", ""))
end

-- Every label occurrence in the line, as { pos, len, label, isSource }.
-- Word-frontier anchored and longest-first, so a short label cannot match
-- inside a long one.
local function findLabels(line)
    local hits = {}
    local function scan(label, isSource)
        local init = 1
        while true do
            local s, e = line:find(label .. "%s*:", init)
            if not s then break end
            -- A label must start the line or follow whitespace; otherwise
            -- "Contract:" inside a value would open a phantom source. Colour
            -- codes are already gone by here -- they sit flush against the
            -- label ("|cFFFFD200Vendor:"), so finding labels before stripping
            -- them rejects every real one.
            local prev = s > 1 and line:sub(s - 1, s - 1) or " "
            if prev:match("%s") then
                hits[#hits + 1] = { pos = s, fin = e, label = label, isSource = isSource }
            end
            init = e + 1
        end
    end
    for _, l in ipairs(SOURCE_LABELS) do scan(l, true) end
    for l in pairs(FIELD_LABELS) do scan(l, false) end
    table.sort(hits, function(x, y)
        if x.pos ~= y.pos then return x.pos < y.pos end
        return (x.fin - x.pos) > (y.fin - y.pos)   -- longest wins at the same spot
    end)
    -- Drop any hit that starts inside the previous one's own label span.
    local out, guard = {}, 0
    for _, h in ipairs(hits) do
        if h.pos > guard then out[#out + 1] = h; guard = h.fin end
    end

    -- UNKNOWN LABEL AT THE LINE START opens a source named after itself.
    --
    -- Without this the line is dropped in silence, which is what happened to
    -- Aetherlume Field Lamp: a 12.1 recipe whose text leads "Fishing:", a label
    -- no list here or in the donor addon contains. The list will always trail
    -- the game, so the parser must not depend on it being complete.
    --
    -- LINE START ONLY. A colon mid-value is ordinary ("World Quest: Work Order:
    -- Contract: Order of Embers"), so a generic label there would shred the
    -- value into phantom sources. And a known FIELD at the line start is a
    -- field, not a source -- "Zone:" on its own line still belongs to the
    -- vendor above it.
    local firstIsSource = out[1] and out[1].isSource
                          and line:sub(1, out[1].pos - 1):match("^%s*$") ~= nil
    if not firstIsSource then
        local label = line:match("^%s*([%a][%a%s]-)%s*:")
        if label and not FIELD_LABELS[label] then
            local s, e = line:find(label .. "%s*:")
            table.insert(out, 1, { pos = s, fin = e, label = label, isSource = true })
        end
    end
    return out
end

-- Parse one block (a run between |n|n) into sources, appending to `acc`.
local function parseBlock(block, acc)
    local current = nil
    for raw in block:gmatch("[^\n]+") do
        -- Colour goes FIRST, for the whole line: labels are wrapped flush
        -- ("|cFFFFD200Vendor: |r"), so every offset below is into the clean
        -- line. Textures and hyperlinks survive -- they are the currency art.
        local line = stripColour(raw)
        local hits = findLabels(line)
        if #hits == 0 then
            -- No label at all: a continuation of the value we are inside.
            if current then
                current.name = trim((current.name or "") .. " " .. trim(line))
            end
        else
            for i, h in ipairs(hits) do
                local stop  = hits[i + 1] and (hits[i + 1].pos - 1) or #line
                local value = trim(line:sub(h.fin + 1, stop))
                if h.isSource then
                    current = { kind = h.label, name = value }
                    acc[#acc + 1] = current
                elseif current then
                    local field = FIELD_LABELS[h.label]
                    -- A second Zone does not overwrite the first; one vendor
                    -- standing in two places keeps both, joined for display.
                    if field == "zone" and current.zone and current.zone ~= "" then
                        current.zone = current.zone .. ", " .. value
                    elseif field == "cost" then
                        current.cost = value
                    else
                        current[field] = value
                    end
                end
            end
        end
    end
end

-- Parse the raw string into an ordered source list, or nil when there is
-- nothing to say. nil AND "" both mean "no acquisition data" -- and "" is
-- truthy in Lua, which is why the empty case is handled explicitly here rather
-- than left to a caller's `if text then`.
function P.Parse(text)
    if text == nil or text == "" then return nil end
    -- Normalise the separators BEFORE anything looks for a label.
    local norm = text:gsub("|n", "\n"):gsub("\r\n", "\n"):gsub("\r", "\n")
    local acc = {}
    -- A BLANK line is the |n|n block break, so split on it and let parseBlock
    -- walk the lines within one block. The trailing sentinel makes the last
    -- block match the same pattern as the rest.
    for block in (norm .. "\n\n"):gmatch("(.-)\n\n") do
        if block:match("%S") then parseBlock(block, acc) end
    end
    if #acc == 0 then return nil end
    return acc
end

-- The one source worth putting on a single line: the first that names a place
-- you can go. A block leading with a synthetic grouping ("World Vendors",
-- "World Nodes") is the same shape as the decor catalog's, and the same answer
-- applies -- prefer the one carrying a zone, fall back to the first.
function P.Best(sources)
    if not sources or #sources == 0 then return nil end
    for _, s in ipairs(sources) do
        if s.zone and s.zone ~= "" then return s end
    end
    return sources[1]
end
