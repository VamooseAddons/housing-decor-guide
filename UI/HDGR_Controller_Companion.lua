-- HDG.CompanionController
-- ============================================================================
-- Companion satellite: click/search wiring + companionSidebarRow factory.
-- Placement lifecycle lives in Modules/HDGR_HouseEditorCompanion.lua.

HDG = HDG or {}
HDG.CompanionController = HDG.CompanionController or {}
local CompanionController = HDG.CompanionController

local A = HDG.Constants.ACTIONS

-- Mode chip keys (order = chip order in the toolbar). Drives the click wiring
-- here; the matching companion.isMode_<key> active bindings live in Selectors.
local MODE_KEYS = { "styles", "rooms", "snapshots", "themes", "collections", "recent" }

-- ===== Sidebar row factory ==================================================

-- Relative-time label for a recent session row (impure -- needs time(); not a selector).
local function _formatSessionLabel(ed)
    local n = ed.eventCount or 0  -- exception(boundary): session may lack eventCount
    if ed.isActive then return "Now (" .. n .. ")" end
    local ts      = ed.endedAt or ed.startedAt or 0  -- exception(nullable): timestamp fallback chain
    local elapsed = math.max(0, _G.time() - ts)  -- exception(boundary): time() is impure
    if elapsed < 60        then return "Just now (" .. n .. ")" end
    if elapsed < 3600      then return _G.string.format("%dm ago (%d)", math.floor(elapsed / 60), n) end
    if elapsed < 86400     then return _G.string.format("%dh ago (%d)", math.floor(elapsed / 3600), n) end
    if elapsed < 7 * 86400 then return _G.date("%a", ts) .. " (" .. n .. ")" end
    return _G.date("%b %d", ts) .. " (" .. n .. ")"
end

-- One-time chrome: optional shape icon + label (left) + count (right).
local function _layoutSidebarRow(row)
    local icon = row:CreateTexture(nil, "ARTWORK", nil, 2)   -- rooms-mode blueprint tile
    icon:SetPoint("LEFT", row, "LEFT", 4, 0)
    icon:SetSize(18, 18)
    icon:Hide()
    row._iconTex = icon

    local fs = HDG.UI.RowText(row, "body", "Text", "LEFT")
    fs:SetPoint("LEFT", row, "LEFT", 6, 0)
    fs:SetPoint("RIGHT", row, "RIGHT", -34, 0)   -- leave room for the count
    fs:SetWordWrap(false)   -- long names (e.g. shopping lists) truncate, not wrap into the next row
    row._labelFs = fs

    local cfs = HDG.UI.RowText(row, "small", "TextDim", "RIGHT")
    cfs:SetPoint("RIGHT", row, "RIGHT", -6, 0)
    row._countFs = cfs

    -- Hairline divider (vertically centred), shown only for isDivider rows. Themed
    -- via the Divider skinner so it repaints on scheme switch.
    local div = row:CreateTexture(nil, "ARTWORK", nil, 2)
    div:SetHeight(1)
    div:SetPoint("LEFT", row, "LEFT", 6, 0)
    div:SetPoint("RIGHT", row, "RIGHT", -6, 0)
    HDG.Theme:Register(div, "Divider")
    div:Hide()
    row._dividerTex = div
end

-- Divider row: a centred hairline, no label, non-interactive.
local function _paintDividerRow(row)
    row._labelFs:SetText("")
    row._countFs:SetText("")
    if row._dividerTex then row._dividerTex:Show() end
    HDG.Theme:Register(row, "RowChrome", { selected = false })
    row:SetScript("OnClick", nil)
    row:EnableMouse(false)
end

-- Header row: dimmed section divider, non-interactive.
local function _paintHeaderRow(row, ed)
    if row._dividerTex then row._dividerTex:Hide() end
    row._labelFs:SetText(ed.displayName)
    HDG.Theme:Register(row._labelFs, "TextDim")
    row._countFs:SetText("")
    HDG.Theme:Register(row, "RowChrome", { selected = false })
    row:SetScript("OnClick", nil)
    row:EnableMouse(false)
end

-- Selectable row: displayName + count (or time label for recent sessions).
-- Click dispatches COMPANION_SELECT_ITEM.
local function _paintSelectableRow(row, ed)
    if row._dividerTex then row._dividerTex:Hide() end
    row:EnableMouse(true)
    HDG.Theme:Register(row._labelFs, "Text")
    if ed.isRecentSession then
        row._labelFs:SetText(_formatSessionLabel(ed))   -- count baked into the label
        row._countFs:SetText("")
    else
        row._labelFs:SetText(ed.displayName or ed.id)
        row._countFs:SetText(ed.count and tostring(ed.count) or "")
    end
    -- Rooms-mode rows carry the shape's blueprint tile; label shifts right.
    row._labelFs:ClearAllPoints()
    if ed.iconAtlas then
        row._iconTex:SetAtlas(ed.iconAtlas, false); row._iconTex:Show()
        row._labelFs:SetPoint("LEFT", row._iconTex, "RIGHT", 4, 0)
    else
        row._iconTex:Hide()
        row._labelFs:SetPoint("LEFT", row, "LEFT", 6, 0)
    end
    row._labelFs:SetPoint("RIGHT", row, "RIGHT", -34, 0)
    HDG.Theme:Register(row, "RowChrome", { selected = ed.isSelected == true })
    local id = ed.id
    row:SetScript("OnClick", function()
        HDG.Store:Dispatch({ type = A.COMPANION_SELECT_ITEM, payload = { itemID = id } })
    end)
end

local function _companionRowFactory(_def)
    return {
        Configure = function(row, ed)
            HDG.UI:RowFirstPaint(row, "_companionLaidOut", function()
                _layoutSidebarRow(row)
            end)
            row:RegisterForClicks("LeftButtonUp")
            if ed.isDivider then
                _paintDividerRow(row)
            elseif ed.isHeader then
                _paintHeaderRow(row, ed)
            else
                _paintSelectableRow(row, ed)
            end
        end,
        Reset = function(row)
            if row._labelFs    then row._labelFs:SetText("") end
            if row._countFs    then row._countFs:SetText("") end
            if row._dividerTex then row._dividerTex:Hide()   end
            row:SetScript("OnClick", nil)
        end,
    }
end

HDG.Rows:Register("companionSidebarRow", {
    font    = "body",
    height  = 24,
    factory = _companionRowFactory,
    key     = function(ed)
        if ed.isDivider       then return "d:" .. tostring(ed.id or "x") end
        if ed.isHeader        then return "h:" .. tostring(ed.displayName) end
        if ed.isRecentSession then return "s:" .. tostring(ed.id) end
        return "r:" .. tostring(ed.id)
    end,
})

-- ===== Controller lifecycle =================================================

function CompanionController:Wire(rootFrame)
    -- Mode chips -> COMPANION_SET_MODE { mode }. OnClick no-ops when the widget
    -- isn't in this frame, so wiring against the main window / other satellites
    -- is a safe no-op (only the companion frame carries these ids).
    for _, key in ipairs(MODE_KEYS) do
        local mode = key
        HDG.UI.OnClick(rootFrame, "companionPanel.mode_" .. key, function()
            HDG.Store:Dispatch({ type = A.COMPANION_SET_MODE, payload = { mode = mode } })
        end)
    end

    -- Cost-badge toggle: state-dependent tooltip (read fresh on hover; not a static recipe).
    HDG.UI.OnClick(rootFrame, "companionPanel.costToggle", function()
        HDG.Store:Dispatch({ type = A.COMPANION_TOGGLE_COST, payload = {} })
    end)
    local costBtn = HDG.UI.W(rootFrame, "companionPanel.costToggle")
    if costBtn then
        HDG.TooltipEngine:Attach(costBtn, function()
            local showing = HDG.Store:GetState().session.ui.companion.showCost  -- exception(false-positive): tooltip callback, not a row factory
            return { title = showing and "Hide placement cost" or "Show placement cost" }
        end)
    end

    -- Indoor/Outdoor 3-state cycle (all -> indoor -> outdoor -> all).
    HDG.UI.OnClick(rootFrame, "companionPanel.ioToggle", function()
        HDG.Store:Dispatch({ type = A.COMPANION_CYCLE_IO, payload = {} })
    end)

    -- Close [X]: HDG.Window reconciler owns Hide() via shown="companion.windowShown" binding.
    HDG.UI.OnClick(rootFrame, "companionPanel.close", function()
        HDG.Store:Dispatch({ type = A.COMPANION_TOGGLE, payload = {} })
    end)

    -- Search: userInput guard inside WireSearchBox prevents binding-push loops.
    HDG.UI.WireSearchBox(rootFrame, "companionPanel.search", "companion", "search")
end

function CompanionController:Refresh(_rootFrame, _ctx)
    -- Bindings handle every paint surface; nothing imperative.
end

HDG.Controllers:Register("companion", CompanionController)
