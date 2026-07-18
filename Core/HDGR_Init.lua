HDG = HDG or {}

-- Action metadata for the middleware chain. Single source of truth that the
-- CombatMiddleware + PersistenceMiddleware consult. Keep aligned with the
-- reducer chain in Core/Store.lua:_RawDispatch -- when an action mutates
-- account state, mark it persists=true; when it touches secure frames,
-- combatUnsafe=true. HDG's UI is non-secure today, so no actions are
-- combat-unsafe at the state-mutation level (the combat queue applies to
-- UI refresh in MainFrame, not to dispatches).
local function BuildActionMeta()
    -- Every action self-registers its meta + reduce in one HDG.Actions block
    -- (SELFREG_RESOLVER_DESIGN; the per-domain blocks live with their
    -- reducers). This just adopts the registry as the meta surface --
    -- ValidateActionMetaExhaustiveness below enforces full coverage.
    local meta = {}
    for value, entry in pairs(HDG.Actions._entries) do
        meta[value] = entry
    end
    return meta
end

-- Exhaustiveness check: every action in Constants.ACTIONS must have a meta row with `invalidates`.
local function ValidateActionMetaExhaustiveness(actionMeta)
    local A = HDG.Constants.ACTIONS
    local missingMeta, missingInvalidates, missingReduce = {}, {}, {}
    for name, value in pairs(A) do
        local row = actionMeta[value]
        if row == nil then
            missingMeta[#missingMeta + 1] = name
        else
            local inv = row.invalidates
            local invType = type(inv)
            -- Valid: table (list), function (dynamic), or sentinel "*".
            if not (invType == "table" or invType == "function"
                    or (invType == "string" and inv == "*")) then
                missingInvalidates[#missingInvalidates + 1] = name
            end
            if type(row.reduce) ~= "function" then
                missingReduce[#missingReduce + 1] = name
            end
        end
    end
    if #missingMeta > 0 then
        error(("HDG action meta missing entries for: %s"):format(
            table.concat(missingMeta, ", ")), 2)
    end
    if #missingInvalidates > 0 then
        error(("HDG action meta missing `invalidates` field for: %s"):format(
            table.concat(missingInvalidates, ", ")), 2)
    end
    if #missingReduce > 0 then
        error(("HDG actions missing `reduce` in their Register block: %s"):format(
            table.concat(missingReduce, ", ")), 2)
    end
end

-- Central environment slot catalog. Addon-level slots here; modules may add module-specific
-- slots via Environment:Declare in their onInitialize.
HDG.Environment.SLOTS = {
    {
        name        = "scheme",
        default     = (HDG.Theme:GetScheme()) or {},
        validator   = function(v) return type(v) == "table" end,
        description = "Active colour scheme + fonts + backdrops",
    },
    {
        name        = "locale",
        default     = HDG.L or {},
        validator   = function(v) return type(v) == "table" end,
        description = "Localisation strings (GetLocale-keyed)",
    },
    {
        name        = "debug",
        default     = function()
            local cfg = HDG.Store:GetState().account.config
            return cfg and cfg.debug == true or false
        end,
        validator   = function(v) return type(v) == "function" end,
        description = "Live debug-mode predicate read from account.config.debug",
    },
    {
        name        = "layer",
        default     = "main",
        validator   = function(v) return type(v) == "string" end,
        description = "Render layer identifier (main / preview / tooltip)",
    },
}

function HDG:OnInitialize()
    -- Stamp t-zero for perf timeline. Marks self-gate on the perf SV internally.
    if HDG.Perf then  -- exception(false-positive): boot orchestrator; Perf is removable instrumentation, absent in minimal/headless test harnesses
        HDG.Perf:SetEpoch()
        HDG.Perf:Mark("HDG:OnInitialize (boot start)", nil, "event")
    end
    HDG_DB = HDG_DB or {}
    HDG.Store:LoadFromSavedVariables()
    HDG.Theme:Initialize()
    -- Snapshot WoW client locale for `binding = "locale:KEY"` resolution.
    HDG.Locale:Initialize()

    -- Boot-time ADR-023 backstop: Theme + Palette must own disjoint color namespaces.
    if HDG.Theme.OWNED_COLOR_NAMESPACES and HDG.Palette and HDG.Palette.OWNED_NAMESPACES then   -- exception(boundary): ADR-023 validator; both modules must be loaded
        for ns in pairs(HDG.Theme.OWNED_COLOR_NAMESPACES) do
            if HDG.Palette.OWNED_NAMESPACES[ns] then
                error(("Theme/Palette namespace collision: %q owned by both (ADR-023)"):format(ns))
            end
        end
    end

    -- Build + validate action metadata. Exhaustiveness check: every action must have a meta entry.
    local actionMeta = BuildActionMeta()
    ValidateActionMetaExhaustiveness(actionMeta)
    -- Stash on Store so _RawDispatch can read `invalidates` per action.
    HDG.Store._actionMeta = actionMeta

    -- Resolver reads cross-check: any selector read under session.resolvers.<X>
    -- must name a registered resolver -- a typo'd resolver path is a boot error
    -- exactly like a typo'd action name. (The inverse direction -- a facade
    -- call without the required reads -- is scripts/semantic_sweep.lua rule 4c.)
    HDG.Resolver:ValidateSelectorReads(HDG.Selectors:GetRegistry())

    -- Config layer. MUST run after actionMeta stash: _RunMigrations dispatches CONFIG_SET
    -- and the reducer needs meta. Theme already initialized; Config re-hydrates from Profiles.
    HDG.Config:Initialize()

    -- Boot sequence (spec section 15.4):
    --   1. BlizzardEvents:OnInitialize  2. Modules:Topo  3. BlizzardEvents:Boot
    --   4. Environment.DeclareAll       5. Modules:Phase1 (onInitialize)
    --   6. Environment:Build            7. Middleware.Apply
    --   8. Modules:Phase2 (onEnable)    9. WidgetTypes:Flush  10. FlowRunner:Boot

    HDG.BlizzardEvents:OnInitialize()

    HDG.Modules:Topo()

    -- Pass module data explicitly (engine-to-engine isolation).
    do
        local order = HDG.Modules:GetOrder()
        local defs  = {}
        for _, name in ipairs(order) do defs[name] = HDG.Modules:Get(name) end
        HDG.BlizzardEvents:Boot({ order = order, defs = defs })
    end

    HDG.Environment:DeclareAll()

    HDG.Modules:Phase1()

    local env = HDG.Environment:Build()

    HDG.Middleware.Apply(HDG.Store, HDG.Middleware.StandardChain({
        actionMeta = actionMeta,
        env        = env,
    }))

    -- Trace consumer subscribes after middleware so its own log entries flow through the chain.
    HDG.Log:AttachTraceConsumer()

    HDG.Modules:Phase2()

    HDG.WidgetTypes:Flush()
    if HDG.FlowRunner and HDG.FlowRunner.Boot then  -- optional; not in TOC  -- exception(boundary): optional module / not yet built
        HDG.FlowRunner:Boot()
    end

    -- Apply the saved scheme before any widgets are built.
    local cfg = HDG.Store:GetState().account.config
    local schemeName = cfg.scheme
    if schemeName and schemeName ~= "" and HDGR_SchemeConstants[schemeName] then
        HDG.Theme:LoadScheme(schemeName)
    end

    -- Register Blizzard Settings panel at ADDON_LOADED (infra is ready; no PLAYER_LOGIN race).
    if HDG.InitSettingsPanel then  -- exception(boundary): file may not be loaded in minimal test builds
        HDG.InitSettingsPanel()
    end
    -- Boot bookend (debug-gated by tag level) + one-shot migration breadcrumb:
    -- HDG.Migration:Run returns true only when a v2 SavedVariables actually migrated.
    if HDG.Migration and HDG.Migration.lastResult == true then
        HDG.Log:Info("boot", "SavedVariables migrated from HDG v2 -- collection/notes/favorites kept; caches + settings reset to fresh defaults")
    end
    HDG.Log:Debug("boot", "OnInitialize complete")
end

function HDG:OnEnable()
    HDG:CreateMainWindow()
    -- Floating windows: CreateAll builds one frame per registered entry, wires Store for
    -- visibility/position reconciliation, and does an initial paint from SavedVariables state.
    if HDG.Window then HDG.Window:CreateAll() end  -- exception(false-positive): boot orchestrator; the UI/Window engine is absent in minimal/headless test harnesses, strict-read would force every boot-test to load the full UI stack
    -- Restore main window open/closed state (FrameVisibility reads account.ui.mainWindowShown).
    HDG:RefreshMainWindow()

    -- One-time HDG->HDGR v3.0 upgrade notice. Migration.lastResult is a table only when a
    -- migration actually ran this load; gate on a RAW SV flag (not reactive state) so it
    -- shows ONCE ever -- surviving reloads AND future schema-bump re-runs.
    local mig = HDG.Migration and HDG.Migration.lastResult
    if mig and _G.HDG_DB and not _G.HDG_DB.upgradeNoticeShown then  -- exception(boundary): one-time raw SV marker
        local P = HDG.Format.BRAND_PREFIX
        print(P .. " Updated to |cFF14b8a6v3.0|r -- your favorites, notes, styles, shopping lists and history all carried over.")
        print(P .. " Settings were reset to new defaults; saved snapshots and smart-sets now live in their own tabs. Type /hdg to explore.")
        _G.HDG_DB.upgradeNoticeShown = true  -- exception(boundary): one-time raw SV marker, not reactive state
    end

    -- Housing catalog work is gated by HousingCatalogObserver's MAIN_WINDOW_OPENING subscriber.
    -- Per ADR-043: no work at PLAYER_LOGIN.

    -- Deferred AddDataProvider: without the 2s defer, it runs inside a click trace
    -- which taints WorldMapFrame -> AreaPOI tooltip errors after combat. boundary
    if HDG.Waypoints and HDG.Waypoints.InitMapPins then  -- exception(boundary): optional module / not yet built
        C_Timer.After(2, function() HDG.Waypoints:InitMapPins() end)
    end    HDG.Log:Debug("boot", "OnEnable complete")
end

-- Lifecycle bootstrap via BlizzardEvents._internalSubscribe (spec section 15).
-- Lifecycle events (ADDON_LOADED/PLAYER_LOGIN/LOGOUT) can't use declarative
-- blizzardEvents because BE:Boot() runs inside OnInitialize.
HDG.BlizzardEvents:_internalSubscribe("ADDON_LOADED", function(name)
    if name == "HousingDecorGuide" then HDG:OnInitialize() end
end)
HDG.BlizzardEvents:_internalSubscribe("PLAYER_LOGIN", function()
    HDG:OnEnable()
end)
-- Scale/display changes: re-run the layout pipeline so "auto"-width widgets repaint at new dimensions.
local function _refreshOnScale()
    HDG:RefreshMainWindow("*")
end
HDG.BlizzardEvents:_internalSubscribe("UI_SCALE_CHANGED",   _refreshOnScale)
HDG.BlizzardEvents:_internalSubscribe("DISPLAY_SIZE_CHANGED", _refreshOnScale)
HDG.BlizzardEvents:_internalSubscribe("PLAYER_LOGOUT", function()
    -- Finalize active lumber session so its haul is recorded to history, not left dangling.
    if HDG.LumberObserver then HDG.LumberObserver:FinalizeSession() end  -- exception(boundary): module optional
    -- SESSION_END closes every window. FlushNotifications drains the deferred queue
    -- synchronously so subscribers actually run before client unloads.
    HDG.Store:Dispatch({ type = HDG.Constants.ACTIONS.SESSION_END })
    HDG.Store:FlushNotifications()
    -- Shutdown in reverse dependency order, before Store:Flush so teardown state lands in SavedVars.
    HDG.Modules:Shutdown()
    HDG.Store:Flush()
end)

SLASH_HDG1 = "/hdg"
SLASH_HDG2 = "/hdgr"
SlashCmdList["HDG"] = function(msg)
    msg = strtrim(msg or "")
    local lower = msg:lower()
    local first, rest = lower:match("^(%S+)%s*(.*)$")
    local D = HDG.Debug
    if lower == "help" or lower == "?" then
        D:Help()
    -- ===== Developer / debug commands -> HDG.Debug + folded dev tools =======
    elseif lower == "debug" then
        D:Toggle()
    elseif lower == "mocktsm" then
        D:MockTSM()
    elseif first == "trace" then
        D:Trace(rest)
    elseif first == "log" then
        D:Log(rest)
    elseif lower == "house" then
        D:House()
    elseif first == "costdump" then
        D:CostDump(rest)
    elseif first == "dumpdecor" then
        D:DumpDecor(rest)
    elseif first == "sl" then
        HDG.SelectorCallLog:Command(rest)   -- was /hdgrsl
    elseif first == "perf" then
        HDG.Perf:Command(rest)              -- was /hdgr perf
    elseif lower == "doors" then
        HDG.ProjectsCanvasController:DoorAudit()  -- was /hdgr doors
    -- ===== User-facing features (stay in Init) ==============================
    elseif lower == "minimap" then
        local cfg = HDG.Store:GetState().account.config
        HDG.Store:Dispatch({
            type = HDG.Constants.ACTIONS.CONFIG_SET,
            payload = { key = "showMinimapButton", value = not cfg.showMinimapButton },
        })
    elseif lower == "hardreset" then
        HDG.Store:Dispatch({ type = HDG.Constants.ACTIONS.HARD_RESET })
        HDG.Log:Success("migration", "HDG has been hard-reset")
    elseif lower == "resetlayout" then
        -- Clears account.ui.houseTab.* overrides; dashboard renders from WidgetDefaults.
        HDG.Store:Dispatch({ type = HDG.Constants.ACTIONS.HOUSETAB_RESET_LAYOUT })
        HDG.Log:Notify("info", "HouseTab layout reset to defaults")
    elseif lower == "refresh" then
        -- Force a fresh catalog sweep.
        HDG.HousingCatalogObserver:ReconcileFull()
        HDG.Log:Notify("info", "catalog refresh started")
    elseif first == "theme" then
        -- /hdgr theme         -- list available themes
        -- /hdgr theme <name>  -- switch theme (case-insensitive prefix match)
        local meta = HDGR_SchemeMeta
        if rest == "" then
            print(HDG.Format.BRAND_PREFIX .. " Available themes:")
            local cur = HDG.Store:GetState().account.config.scheme
            for _, name in ipairs(meta.order) do
                local marker = (name == cur) and "|cffffb060*|r " or "  "
                print(("%s|cffcdd6f4%s|r  |cff999999%s|r"):format(marker, name, meta.labels[name] or ""))
            end
            print("|cff666666Usage: /hdgr theme <Name>|r")
        else
            local match
            local lowerArg = rest:lower():gsub("%s", "")
            for _, name in ipairs(meta.order) do
                if name:lower():sub(1, #lowerArg) == lowerArg then match = name; break end
            end
            if not match then
                HDG.Log:Notify("error", ("unknown theme %q -- run /hdgr theme to list"):format(rest))
            else
                HDG.Store:Dispatch({
                    type = HDG.Constants.ACTIONS.CONFIG_SET,
                    payload = { key = "scheme", value = match },
                })
                HDG.Theme:LoadScheme(match)
                HDG.Log:Notify("info", ("theme -> %s"):format(match))
                HDG.Log:Info("theme", "Theme changed to " .. match)  -- status-rail toast
            end
        end
    elseif first == "view" then
        local views   = HDG.LayoutConfig.window.views
        local current = HDG.Store:GetState().account.ui.view
        local arg     = rest:gsub("%s", "")
        if arg == "" then
            print(HDG.Format.BRAND_PREFIX .. " Views:")
            for name in pairs(views) do
                local marker = (name == current) and "|cffffb060*|r " or "  "
                print(("%s|cffcdd6f4%s|r"):format(marker, name))
            end
            print("|cff666666Usage: /hdgr view <name>|r")
        elseif not views[arg] then
            HDG.Log:Notify("error", ("unknown view %q -- run /hdgr view to list"):format(arg))
        else
            HDG.Store:Dispatch({
                type    = HDG.Constants.ACTIONS.UI_SET_PERSISTENT,
                payload = { key = "view", value = arg },
            })
            HDG.Log:Info("ui_action", "View: " .. arg)
        end
    else
        HDG:ToggleMainWindow()
    end
end
