-- HDG.Modules
--
-- Module declaration registry + dependency topo-sort + two-phase loader.
-- Modules declare via Modules:Declare(def) at file-load time.
-- Init.lua drives the interleaved boot (see Core/HDGR_Init.lua).
-- Knit invariant: onInitialize MUST NOT call other modules; use onEnable for cross-module wiring.

HDG = HDG or {}
HDG.Modules = HDG.Modules or {
    _registry = {},                 -- [name] = def
    _order    = nil,                -- topo-sorted list, populated by Boot()
    _booted   = false,
    _initDone = false,
    _started  = false,
}

local M = HDG.Modules

-- ===== Topological sort (AwesomeWM-derived) ===============================
-- DFS with HANDLING (in current path -> cycle) and DONE (already emitted)
-- sentinel states. Returns (orderedList, nil) on success or (nil, cycleNode)
-- on cycle detection.

local HANDLING, DONE = 1, 2

local function visit(result, edges, state, node)
    if state[node] == DONE then return end
    if state[node] == HANDLING then
        result._cycle = node
        return true
    end

    state[node] = HANDLING
    for dep in pairs(edges[node] or {}) do
        if visit(result, edges, state, dep) then return true end
    end
    state[node] = DONE
    result[#result + 1] = node
end

local function toposort(registry)
    local edges = {}
    for name, def in pairs(registry) do
        edges[name] = {}
        for _, dep in ipairs(def.dependencies or {}) do
            edges[name][dep] = true
        end
    end
    local result, state = {}, {}
    for node in pairs(edges) do
        if visit(result, edges, state, node) then
            return nil, result._cycle
        end
    end
    return result
end

-- ===== Public API =========================================================

-- Register a module. Called from each module file at TOC load time.
-- def = {
--     name         = "ModuleName",           -- required, unique
--     dependencies = { "Other", "Module" },  -- list of module names
--     onInitialize = function(self) end,     -- lifecycle 1: self-setup only
--     onEnable     = function(self) end,     -- lifecycle 2: cross-module wiring
--     onShutdown   = function(self) end,     -- lifecycle 3 (optional, v0.7): teardown on PLAYER_LOGOUT
-- }
function M:Declare(def)
    if type(def) ~= "table" then
        error("HDG.Modules:Declare expected a table, got " .. type(def), 2)
    end
    if type(def.name) ~= "string" or def.name == "" then
        error("HDG.Modules:Declare missing required field 'name'", 2)
    end
    -- Closed registry: reject late declarations once topology is sealed. The
    -- production path seals via Topo() (_topoSorted); the legacy Boot() sets _booted.
    if self._booted or self._topoSorted then
        error(("HDG.Modules:Declare(%q) called after topology was sealed"):format(def.name), 2)
    end
    if self._registry[def.name] then
        error(("HDG.Modules:Declare(%q) duplicate registration"):format(def.name), 2)
    end
    if def.dependencies ~= nil and type(def.dependencies) ~= "table" then
        error(("HDG.Modules:Declare(%q): dependencies must be a list"):format(def.name), 2)
    end
    self._registry[def.name] = def
end

-- Boot is split so Init.lua can interleave engine work between topology and lifecycle.
-- BlizzardEvents:Boot must run AFTER Topo but BEFORE Phase1 so subscriptions are live.
function M:Topo()
    if self._topoSorted then return end

    -- Verify all referenced dependencies are registered.
    for name, def in pairs(self._registry) do
        for _, dep in ipairs(def.dependencies or {}) do
            if not self._registry[dep] then
                error(("Module %q depends on unregistered module %q"):format(name, dep), 2)
            end
        end
    end

    -- Blizzard-namespace ownership disjoint check (Iron Invariant section 9).
    self:ValidateOwnership()

    local order, cycle = toposort(self._registry)
    if not order then
        error(("HDG.Modules: dependency cycle involving %q"):format(tostring(cycle)), 2)
    end
    self._order = order
    self._topoSorted = true
end

-- Boot-time disjoint check for Blizzard API ownership.
function M:ValidateOwnership()
    local owner = {}
    for name, def in pairs(self._registry) do
        for _, ns in ipairs(def.ownsBlizzardNamespaces or {}) do
            if owner[ns] then
                error(("HDG.Modules: Blizzard namespace %q claimed by both %q and %q"):format(
                    ns, owner[ns], name), 2)
            end
            owner[ns] = name
        end
    end
end

-- Synchronous Init in dependency order. All Init calls complete before any onEnable.
-- Modules may declare env slots here; Environment:Build runs after this phase.
function M:Phase1()
    if self._initDone then return end
    if not self._topoSorted then self:Topo() end

    -- Collect logTags BEFORE onInitialize so modules can push entries from lifecycle hooks.
    for _, name in ipairs(self._order) do
        local def = self._registry[name]
        if def and type(def.logTags) == "table" then
            HDG.Log:RegisterTags(def.logTags)
        end
    end

    for _, name in ipairs(self._order) do
        local def = self._registry[name]
        if def.onInitialize then
            local ok, err = pcall(def.onInitialize, def)
            if not ok then
                local msg = ("Module %q onInitialize failed: %s"):format(name, tostring(err))
                -- Log AND re-raise: Log entry surfaces even if ErrorBoundary swallows the re-raise.
                -- Re-raise halts boot (onInitialize failures mean the module cannot continue).
                HDG.Log:Error("modules", msg)
                error(msg, 2)
            end
        end
    end
    self._initDone = true
end

-- Start. Synchronous onEnable in dependency order. Same fail-loud shape as
-- Phase1: log with module-name context, then re-raise -- a half-enabled addon
-- that quietly logs is worse than a loud halt (ADR-042; the old
-- continue-for-siblings isolation was the removed pcall class, 2026-06-12).
function M:Phase2()
    if self._started then return end
    if not self._initDone then self:Phase1() end
    for _, name in ipairs(self._order) do
        local def = self._registry[name]
        if def.onEnable then
            local ok, err = pcall(def.onEnable, def)
            if not ok then
                local msg = ("Module %q onEnable failed: %s"):format(name, tostring(err))
                HDG.Log:Error("modules", msg)
                error(msg, 2)
            end
        end
    end
    self._started = true
end

-- Legacy Boot: DEPRECATED per ADR-020. Production Init.lua interleaves the phases with engine work.
-- Kept functional until all callers migrate to Topo()+Phase1()+Phase2() or BootHDGREngine().
function M:Boot()
    if self._booted then return end
    self._booted = true
    self:Topo()
    self:Phase1()
    self:Phase2()
end

-- Get a registered module's definition. Safe after Phase 1 completes.
function M:Get(name)
    local def = self._registry[name]
    if not def then
        error(("HDG.Modules:Get(%q): module not registered. Check spelling or TOC order."):format(tostring(name)), 2)
    end
    return def
end

-- Fires onShutdown in REVERSE dependency order; pcall-wrapped. Called before Store:Flush.
function M:Shutdown()
    if not self._order then return end
    for i = #self._order, 1, -1 do
        local name = self._order[i]
        local def  = self._registry[name]
        if def and def.onShutdown then
            local ok, err = pcall(def.onShutdown, def)  -- exception(fire-forget): logout path -- sibling shutdown (SV finalization) must complete even if one module throws
            if not ok then
                HDG.Log:Error("modules",
                    ("Module %q onShutdown failed: %s"):format(name, tostring(err)))
            end
        end
    end
end

-- Test/debug helper. Returns the topo-sorted order (or nil if Boot hasn't run).
function M:GetOrder()
    return self._order
end

-- Test helper: reset registry between test runs. NEVER call in production.
function M:_Reset()
    self._registry   = {}
    self._order      = nil
    self._booted     = false
    self._topoSorted = false
    self._initDone   = false
    self._started    = false
end
