-- HDG.ZoneAlertEngine
-- ============================================================================
-- Subscribes to ZONE_CHANGED dispatches (from HDGR_ZoneObserver) and reads
-- the current zone's vendor data via zone selectors. When a fresh zone has
-- uncollected items OR items on the active shopping list, fires the
-- configured alert surfaces:
--
--   * Chat message  (config.zoneScannerChat)   -- always prints if enabled
--   * Sound cue     (config.zoneScannerSound)  -- PlaySound
--   * Popup show    (config.zoneScannerPopup)  -- dispatches ZONE_POPUP_TOGGLE
--                                                  if popup currently hidden
--
-- Master gate: config.zoneScannerEnabled -- when false, the engine skips the
-- entire check (no selector calls, no dispatch). Combat-safe: in lockdown we
-- skip popup-show too (no protected frame ops).
--
-- HDG parity:
--   * Two alert paths -- uncollected items + shopping-list items. Both
--     check independently; both can fire on the same zone change.
--   * shoppingList alert reuses the chat message but does NOT play the
--     sound twice (avoids stacking).
--   * Skips when the zone has zero qualifying vendors (no noisy "empty zone"
--     alerts).

HDG = HDG or {}
HDG.ZoneAlertEngine = HDG.ZoneAlertEngine or {}
local Z = HDG.ZoneAlertEngine

-- Log tag registration -- file-load so the first ZONE_CHANGED dispatch can
-- log immediately without waiting for the module's onEnable. Matches the
-- pattern in HDGR_Controller_Shopping (`shopping` tag).
-- Chat-link click: open HDG on the Zone tab. hooksecurefunc posthook = taint-safe;
-- unknown addon: links are no-ops for Blizzard, so we only ever ADD behavior.
_G.hooksecurefunc("SetItemRef", function(link)
    if link ~= "addon:HDGZone" then return end
    -- Zone Scanner is the standalone popup (account.ui.zonePopupShown), not a
    -- main-window view -- open it if closed, no-op if already up.
    if not HDG.Store:GetState().account.ui.zonePopupShown then
        HDG.Store:Dispatch({ type = HDG.Constants.ACTIONS.ZONE_POPUP_TOGGLE })
    end
end)

if HDG.Log and not HDG.Log:HasTag("zone_scanner") then
    HDG.Log:RegisterTags({
        zone_scanner = { user = true, level = "info", duration = 4 },
    })
end

HDG.Modules:Declare({
    name = "ZoneAlertEngine",
    dependencies = { "ZoneObserver" },
    -- Subscribes to Store, not Blizzard events. No namespace ownership.
    onEnable = function(self)
        self._storeToken = HDG.Store:Subscribe(function(actionType)
            if actionType == HDG.Constants.ACTIONS.ZONE_CHANGED then
                Z._alertedThisZone = false   -- new zone entry -> allow one alert
                Z:CheckAlerts()
            elseif actionType == HDG.Constants.ACTIONS.DECOR_CATALOG_READY then
                -- Catalog finished its async sweep. On /reload (or login) the zone is
                -- set BEFORE the sweep lands, so the ZONE_CHANGED check ran with no
                -- vendor data and bailed. Re-check now that the catalog is ready (the
                -- _alertedThisZone dedup stops a double-alert when both fire in order).
                Z:CheckAlerts()
            end
        end)
    end,
    onShutdown = function(self)
        if self._storeToken and HDG.Store.Unsubscribe then
            HDG.Store:Unsubscribe(self._storeToken)
        end
        self._storeToken = nil
    end,
})

-- Run all alert checks against the current state. Called from the Store
-- subscriber after ZONE_CHANGED lands -- by then session.zone.currentMapID
-- and session.ui.zoneScanner.expanded have been updated by the reducer.
function Z:CheckAlerts()
    local state = HDG.Store:GetState()
    local cfg   = state.account.config
    if not cfg.zoneScannerEnabled then return end
    -- Dedup: one alert per zone entry. Reset on ZONE_CHANGED; this guard stops the
    -- DECOR_CATALOG_READY re-check (and any repeat ZONE_CHANGED) from re-alerting.
    if Z._alertedThisZone then return end
    -- InCombatLockdown read deferred to fire-time: combat-safe gate for
    -- popup-show. boundary -- single Blizzard API call in this module.
    local inCombat = _G.InCombatLockdown and _G.InCombatLockdown() or false

    -- Catalog is load-on-demand: on a fresh login nothing sweeps it until HDG
    -- opens, so a cold catalog would silence zone alerts entirely. Request the
    -- sweep (idempotent) and let the DECOR_CATALOG_READY re-check below fire the
    -- alert -- same self-warming as the recipe capture.
    if not HDG.HousingCatalogObserver:IsReady() then
        HDG.HousingCatalogObserver:RequestLoad("zoneScanner")
        return
    end
    local hasUnc  = HDG.Selectors:Call("zone.hasUncollectedItems", state, {})
    local hasSL   = HDG.Selectors:Call("zone.hasShoppingListItems", state, {})
    -- Catalog swept but zone has nothing -- bail WITHOUT marking, so a
    -- DECOR_CATALOG_READY re-check (fresh data) can still alert later.
    if not hasUnc and not hasSL then return end
    Z._alertedThisZone = true   -- commit: this zone entry is handled

    local summary = HDG.Selectors:Call("zone.summary", state, {})

    -- Chat alert: direct print to DEFAULT_CHAT_FRAME (Log routes to status rail,
    -- not chat). Also emit via Log:Info so the rail shows it for scrollback.
    if cfg.zoneScannerChat then
        local prefix = hasSL and "shopping list" or "uncollected"
        local line = ("Zone has %s items -- %s"):format(prefix, summary)
        if _G.print then
            -- User-facing alert, dressed up: vendor-pin atlas icon + gold brand +
            -- warm headline + dimmed detail + clickable [View] (|Haddon:...|h link;
            -- SetItemRef posthook below opens the Zone Scanner popup).
            local headline = hasSL and "Shopping-list decor in this zone!"
                                   or  "Uncollected decor in this zone!"
            _G.print(("|A:housing-decor-vendor_32:16:16|a |cffffd700[HDG]|r |cffffe29a%s|r |cffaaaaaa(%s)|r |Haddon:HDGZone|h|cff71d5ff[View]|r|h")
                :format(headline, summary))
        end
        HDG.Log:Info("zone_scanner", line)
    end

    -- Sound: one cue per zone change regardless of which path triggered.
    if cfg.zoneScannerSound and _G.PlaySound and _G.SOUNDKIT then
        _G.PlaySound(_G.SOUNDKIT.IG_MAINMENU_OPEN)
    end

    -- Popup auto-show on zone change.
    --   Window closed -> auto-open to Zone view (popup slot).
    --   Window open   -> no-op (alert is passive).
    -- Combat-safe: skip visibility changes in lockdown (protected-frame ops).
    -- Two independent flags: uncollected vs shopping-list matches.
    local wantPopup = (cfg.zoneScannerPopup and hasUnc)
                   or (cfg.zoneScannerPopupShopping and hasSL)
    if wantPopup and not inCombat then
        local windowOpen = state.account.ui.mainWindowShown == true
                        or state.account.ui.zonePopupShown == true
                        or state.account.ui.shoppingWidgetShown == true
        if not windowOpen then
            -- Window closed: auto-open via the popup slot (PrepareContext
            -- override flips activeView to zoneScanner).
            HDG.Store:Dispatch({
                type    = HDG.Constants.ACTIONS.ZONE_POPUP_TOGGLE,
                payload = nil,
            })
        end
    end
end
