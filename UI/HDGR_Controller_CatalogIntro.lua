-- HDGR_Controller_CatalogIntro.lua
-- ============================================================================
-- Visuals for the catalog initial-load overlay: the animated blip-dot "wave"
-- and the Refresh button. The phase machine itself lives in
-- Modules/HDGR_CatalogIntro.lua; this only paints/animates from the phase.
HDG = HDG or {}

local IntroController = {}

local DOT_IDS    = { "catalogIntroPanel.dot1", "catalogIntroPanel.dot2", "catalogIntroPanel.dot3" }
local DOT_PERIOD = 1.1   -- seconds per pulse cycle

-- Phase-shifted triangle pulse (0.25..1.0). Staggering by dot index makes the
-- three read as a left-to-right wave -- the "Loading . .. ..." in blip form.
local function _dotAlpha(t, i)
    local p   = (t / DOT_PERIOD + (i - 1) * 0.22) % 1
    local tri = (p < 0.5) and (p * 2) or (2 - p * 2)
    return 0.25 + 0.75 * tri
end

function IntroController:Wire(rootFrame)
    -- Animation state lives on the rootFrame, NOT the controller singleton:
    -- WireAll runs once per window (main + each satellite), and a singleton
    -- bucket gets clobbered to empty by whichever dot-less satellite wires last.
    local dots = {}
    for _, id in ipairs(DOT_IDS) do
        local d = HDG.UI.W(rootFrame, id)
        if d and d.SetAlpha then dots[#dots + 1] = d end  -- exception(boundary): W returns a stub without SetAlpha in the headless mock
    end
    rootFrame._catalogIntro = { dots = dots, loading = false, t = 0 }

    -- Dot wave: a gated OnUpdate (only animates while phase=="loading"; rootFrame
    -- itself stops ticking when the HDG window is hidden). Hooked once per frame,
    -- and only on frames that actually compose the dots (satellites never do).
    if #dots > 0 and not rootFrame._catalogIntroHooked then
        rootFrame._catalogIntroHooked = true
        rootFrame:HookScript("OnUpdate", function(_, elapsed)
            local ci = rootFrame._catalogIntro   -- re-read: Wire replaces the bucket on rewire
            if not ci.loading then return end
            ci.t = ci.t + elapsed
            for i, d in ipairs(ci.dots) do
                d:SetAlpha(_dotAlpha(ci.t, i))   -- dots only holds real textures (filtered in Wire)
            end
        end)
    end

    -- Refresh: force a fresh sweep past the in-flight coalesce + idle guard.
    HDG.UI.OnClick(rootFrame, "catalogIntroPanel.refresh", function()
        HDG.Store:Dispatch({ type = HDG.Constants.ACTIONS.CATALOG_FORCE_RELOAD })
    end)
end

function IntroController:Refresh(rootFrame, ctx)
    local state = HDG.Store:GetState()  -- exception(false-positive): top-level controller Refresh, not a row factory
    local ci = rootFrame._catalogIntro
    ci.loading = (state.session.ui.catalogIntro.phase == "loading")
    -- Reset dots to full when not animating so the success flash / hidden states
    -- never freeze a dot mid-fade.
    if not ci.loading then
        for _, d in ipairs(ci.dots) do d:SetAlpha(1) end
    end
end

HDG.Controllers:Register("catalogIntro", IntroController)
