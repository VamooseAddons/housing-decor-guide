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
    self._dots = {}
    for _, id in ipairs(DOT_IDS) do
        local d = HDG.UI.W(rootFrame, id)
        if d and d.SetAlpha then self._dots[#self._dots + 1] = d end  -- exception(boundary): W returns a stub without SetAlpha in the headless mock
    end
    self._loading = false
    self._t       = 0

    -- Dot wave: a gated OnUpdate (only animates while phase=="loading"; rootFrame
    -- itself stops ticking when the HDG window is hidden). Hooked once per frame.
    if not rootFrame._catalogIntroHooked then
        rootFrame._catalogIntroHooked = true
        rootFrame:HookScript("OnUpdate", function(_, elapsed)
            if not IntroController._loading then return end
            IntroController._t = (IntroController._t or 0) + elapsed
            for i, d in ipairs(IntroController._dots or {}) do
                d:SetAlpha(_dotAlpha(IntroController._t, i))   -- _dots only holds real textures (filtered in Wire)
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
    self._loading = (state.session.ui.catalogIntro.phase == "loading")
    -- Reset dots to full when not animating so the success flash / hidden states
    -- never freeze a dot mid-fade.
    if not self._loading then
        for _, d in ipairs(self._dots) do d:SetAlpha(1) end
    end
end

HDG.Controllers:Register("catalogIntro", IntroController)
