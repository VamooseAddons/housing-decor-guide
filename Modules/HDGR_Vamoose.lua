-- HDG.Vamoose
-- ============================================================================
-- Daily-rotating "bestowed title" for the DecoratorProfile widget + a
-- per-session Orc quote for the status rail footer. Captured once at onEnable;
-- session-long staleness (WoW past midnight) is acceptable.
-- exception(boundary): date() / math.random() are impure; owned here so selectors stay pure.

-- 20 Orc quotes ported from HDG modules/HDG_UI.lua ORC_QUOTES table.
-- ASCII only -- no unicode per project style.
local ORC_QUOTES = {
    "Zug zug.",
    "Lok'tar ogar!",
    "Me smash!",
    "Work is da poop!",
    "Blood and Thunder!",
    "Dabu.",
    "Time to kill?",
    "For the Horde!",
    "Me busy!",
    "Axe hungry.",
    "Crush them all!",
    "Why you poke me?",
    "Strength and Honor.",
    "Me not that kind of orc.",
    "You weak. Me strong.",
    "More wood? Ugh.",
    "Me hit it now?",
    "Victory or death!",
    "Small talk is for elves.",
    "Something need doing?",
}

HDG = HDG or {}
HDG.Vamoose = HDG.Vamoose or {}
local V = HDG.Vamoose

-- Pick today's title by deterministic hash of YYYYMMDD (same algorithm
-- as HDG so both rotate to the same title on the same day).
function V:PickForToday()
    local titles = _G.HDGR_HouseTab_DailyTitles
    if not (titles and #titles > 0) then return nil, nil end
    local today = _G.date and _G.date("%Y%m%d") or "00000000"
    local seed  = tonumber(today) or 0  -- exception(boundary): parse date string
    local idx   = (seed % #titles) + 1
    local entry = titles[idx]
    return entry.name, entry.quote, today
end

HDG.Modules:Declare({
    name         = "Vamoose",
    dependencies = {},

    onEnable = function(self)
        local name, quote, dateKey = V:PickForToday()
        if not name then return end
        HDG.Store:Dispatch({
            type    = HDG.Constants.ACTIONS.DAILY_BESTOWED_UPDATED,
            payload = { name = name, quote = quote, dateKey = dateKey },
        })

        -- Boundary: math.random() is impure (session wall-clock seed).
        -- Pick one of the 20 Orc quotes and dispatch so selectors stay pure.
        local idx = math.random(#ORC_QUOTES)
        HDG.Store:Dispatch({
            type    = HDG.Constants.ACTIONS.DAILY_ORC_QUOTE_SET,
            payload = { quote = ORC_QUOTES[idx] },
        })
    end,
})
