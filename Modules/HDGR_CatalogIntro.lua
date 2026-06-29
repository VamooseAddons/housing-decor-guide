-- HDGR_CatalogIntro.lua
-- ============================================================================
-- Phase machine for the catalog initial-load overlay (the "catalogIntro" view).
-- Runs at boot (onEnable) so it's listening before the first MAIN_WINDOW_OPENING.
--
--   window opens, catalog not ready  -> phase "loading"  (animated dots + Refresh)
--   first DECOR_CATALOG_READY commit  -> phase "success"  (0.5s "loaded" flash)
--   0.5s later                        -> phase "hidden"   (real content shows)
--   window opens, catalog ready       -> phase "hidden"   (cached; no intro)
--
-- The overlay panel's visibility + headline are binding-driven off this phase
-- (catalog.intro.* selectors); this module only OWNS the phase transitions.
HDG = HDG or {}

local SUCCESS_HOLD = 0.5   -- seconds the "Catalog loaded!" flash lingers before content

HDG.Modules:Declare({
    name = "CatalogIntro",
    dependencies = {},
    onEnable = function()
        -- PARKED: the initial-load overlay is disabled (introOverlay slot is off in
        -- HDGR_Layout) pending a render fix -- the panel composes but doesn't paint.
        -- Skip the phase machine so it dispatches nothing. Remove this return to revive.
        do return end
        local A = HDG.Constants.ACTIONS
        HDG.Store:Subscribe(function(actionType)
            if actionType == A.MAIN_WINDOW_OPENING then
                -- First open this session (catalog not ready) -> show the loading
                -- overlay; a later reopen with a warm catalog goes straight to content.
                local ready = HDG.HousingCatalogObserver:IsReady()
                HDG.Store:Dispatch({ type = A.CATALOG_INTRO_SET_PHASE,
                                     payload = { phase = ready and "hidden" or "loading" } })
            elseif actionType == A.DECOR_CATALOG_READY then
                if HDG.Store:GetState().session.ui.catalogIntro.phase == "loading" then
                    HDG.Store:Dispatch({ type = A.CATALOG_INTRO_SET_PHASE, payload = { phase = "success" } })
                    C_Timer.After(SUCCESS_HOLD, function()
                        -- Only clear if still showing success (a force-reload could have
                        -- re-entered loading); never stomp a fresh loading phase.
                        if HDG.Store:GetState().session.ui.catalogIntro.phase == "success" then
                            HDG.Store:Dispatch({ type = A.CATALOG_INTRO_SET_PHASE, payload = { phase = "hidden" } })
                        end
                    end)
                end
            end
        end)
    end,
})
