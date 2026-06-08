-- HDG.ProjectsController
-- ============================================================================
-- Projects views (landing / architect). Registers floor-tab chip +
-- row factories. Canvas renders via HDG.ProjectsCanvasController.

HDG = HDG or {}
HDG.ProjectsController = HDG.ProjectsController or {}
local PC = HDG.ProjectsController

local A = HDG.Constants.ACTIONS

-- ===== helpers =============================================================
local function _dispatchTransient(key, value)
    HDG.Store:Dispatch({ type = A.UI_SET_TRANSIENT, payload = { view = "projects", key = key, value = value } })
end
-- Switch the rendered top-level view. Uses UI_SET_PERSISTENT (same as NavController.setView).
-- UI_SET_VIEW writes session.ui.view which the window does NOT render.
local function _setView(view)
    HDG.Store:Dispatch({ type = A.UI_SET_PERSISTENT, payload = { key = "view", value = view } })
end

-- Active version from projects.activeVersionID selector. Returns (versionID, version) or nil,nil.
local function _activeVersion()
    local state   = HDG.Store:GetState()  -- exception(false-positive): top-level controller helper, not a row factory
    local vid     = HDG.Selectors:Call("projects.activeVersionID", state, {})
    local version = vid and state.account.projects.versions[vid]
    return vid, version
end

-- ===== Version switcher: switch / branch / delete house versions ==============
local function _branchWhatIf(houseID, basedOn)
    if not (houseID and basedOn) then return end
    local tabs, n = HDG.Selectors:Call("projects.versionTabs", HDG.Store:GetState(), {}), 0  -- exception(false-positive): top-level controller helper, not a row factory
    for _, v in ipairs(tabs) do if not v.isCurrent then n = n + 1 end end
    HDG.Store:Dispatch({ type = A.PROJECTS_CREATE_VERSION, payload = {
        houseID = houseID,   -- versionID minted reducer-side from the counter
        name = "What-if " .. (n + 1), basedOn = basedOn, createdAt = (time and time()) or 0 } })  -- exception(boundary): time()
end
local function _deleteWhatIf(houseID, versionID)
    if not (houseID and versionID) then return end
    HDG.Store:Dispatch({ type = A.PROJECTS_DELETE_VERSION,
        payload = { houseID = houseID, versionID = versionID, ts = (time and time()) or 0 } })  -- exception(boundary): time()
end
-- Build + show the version menu: a radio per version (switch on pick), then New / Delete.
local function _openVersionMenu(owner)
    local tabs = HDG.Selectors:Call("projects.versionTabs", HDG.Store:GetState(), {})  -- exception(false-positive): top-level controller helper, not a row factory
    if #tabs == 0 then return end   -- no house captured yet
    local houseID = tabs[1].houseID
    local activeVid, activeIsCurrent
    local items = { { isTitle = true, text = "House version" } }
    for _, v in ipairs(tabs) do
        if v.isActive then activeVid, activeIsCurrent = v.versionID, v.isCurrent end
        local vid = v.versionID
        items[#items + 1] = { kind = "radio", text = v.name .. (v.isCurrent and "  (Live)" or ""),
            selected = v.isActive, value = vid,
            callback = function()
                HDG.Store:Dispatch({ type = A.PROJECTS_SET_ACTIVE_VERSION, payload = { houseID = houseID, versionID = vid } })
            end }
    end
    items[#items + 1] = { isDivider = true }
    items[#items + 1] = { text = "New what-if (copy current)", callback = function() _branchWhatIf(houseID, activeVid) end }
    if not activeIsCurrent then
        items[#items + 1] = { text = "Delete this what-if", callback = function() _deleteWhatIf(houseID, activeVid) end }
    end
    HDG.UI.ShowMenu(owner, items)
end
-- New what-if: branch from live version (designing never touches reality).
local function _newWhatIfFromPicker()
    local tabs = HDG.Selectors:Call("projects.versionTabs", HDG.Store:GetState(), {})  -- exception(false-positive): top-level controller helper, not a row factory
    if #tabs == 0 then return end
    local houseID = tabs[1].houseID
    local liveVid
    for _, v in ipairs(tabs) do if v.isCurrent then liveVid = v.versionID end end
    _branchWhatIf(houseID, liveVid)
end

-- What-if floor count: version.numFloors if set, else scan room IDs.
local function _whatIfFloorCount(version)
    if not version then return 1 end
    if version.numFloors then return version.numFloors end
    local IDs, maxFloor = HDG.Projects.IDs, 1
    for roomID in pairs(version.rooms or {}) do
        local p = IDs.parsePath(roomID)
        if p and p.floor and p.floor > maxFloor then maxFloor = p.floor end
    end
    return maxFloor
end
-- Dispatch a floor-count change for the active what-if version (clamped 1..3 here too).
local function _setWhatIfFloors(delta)
    local vid, version = _activeVersion()
    if not (vid and version) then return end
    local n = math.max(1, math.min(3, _whatIfFloorCount(version) + delta))
    HDG.Store:Dispatch({ type = A.PROJECTS_SET_VERSION_FLOORS, payload = { versionID = vid, numFloors = n } })
end

-- Resolve which house a new design targets WITHOUT requiring you to stand inside it:
--   1. the currently-focused house (if you've already picked one), else
--   2. your current faction's owned house -- identity minted from session.house.ownedHouses
--      using the SAME (neighborhoodName:plotID) hash capture/CurrentHouseID mint, so a
--      pre-capture design unifies with a later capture under one houseID, else
--   3. a synthetic "scratch" house (own no plot yet -> still mock up a layout you don't own).
-- Returns houseID, displayName.
local function _resolveDesignHouse()
    local state = HDG.Store:GetState()
    local focusedID = HDG.Selectors:Call("projects.activeHouseID", state, {})  -- exception(false-positive): top-level controller helper, not a row factory
    if focusedID then
        local h = state.account.projects.houses[focusedID]
        return focusedID, (h and h.name) or "My House"
    end
    local IDs   = HDG.Projects.IDs
    local myFac = _G.UnitFactionGroup and _G.UnitFactionGroup("player") or nil  -- exception(boundary): Blizzard API
    local pick, fallback
    for _, h in pairs(state.session.house.ownedHouses) do
        if h.name and h.plotID then
            fallback = fallback or h
            if myFac and h.faction == myFac then pick = h; break end
        end
    end
    pick = pick or fallback
    if pick then
        return IDs.makeHouseID(IDs.hashToken(pick.name .. ":" .. tostring(pick.plotID))),
               pick.houseName or pick.name or "My House"
    end
    return IDs.makeHouseID(IDs.hashToken("scratch")), "Scratch Design"
end

-- Start new design: target the focused / current-faction house -- NO "be inside" gate.
-- The data model keys houses by a (name:plotID) hash and already supports uncaptured
-- houses (focus stub + empty canvas). FOCUS_HOUSE makes the target the Architect's
-- active house; CREATE_VERSION(basedOn=nil) mints an empty "from scratch" version.
local function _startNewDesign()
    local houseID, houseName = _resolveDesignHouse()
    HDG.Store:Dispatch({ type = A.PROJECTS_UPSERT_HOUSE, payload = { houseID = houseID, fields = { name = houseName } } })
    HDG.Store:Dispatch({ type = A.PROJECTS_FOCUS_HOUSE,  payload = { houseID = houseID } })
    local tabs, n = HDG.Selectors:Call("projects.versionTabs", HDG.Store:GetState(), {}), 0  -- exception(false-positive): top-level controller helper, not a row factory
    for _, v in ipairs(tabs) do if not v.isCurrent then n = n + 1 end end
    HDG.Store:Dispatch({ type = A.PROJECTS_CREATE_VERSION, payload = {
        houseID = houseID,   -- versionID minted reducer-side from the counter
        name = "Design " .. (n + 1), basedOn = nil, createdAt = (time and time()) or 0 } })  -- exception(boundary): time()
    _setView("projectsArchitect")
end

-- ===== Place a room: mint collision-free roomID, then dispatch PROJECTS_UPSERT_ROOM. ====
local function _mintRoomID(rooms, floorID)
    local IDs = HDG.Projects.IDs
    for _ = 1, 32 do
        local id = IDs.makeRoomID(floorID, IDs.shortUUID(4))
        if id and not rooms[id] then return id end
    end
    return IDs.makeRoomID(floorID, IDs.shortUUID(8))
end
-- Occupied cells on a floor -> HDG.Projects.FloorMap (the SSoT collision +
-- projection derivation, shared with the canvas render + drag/move guard).
local function _occupiedCells(rooms, floor) return HDG.Projects.FloorMap.OccupiedCells(rooms, floor) end
-- A room occupies the same x,y on floor .. floor+span-1 (span=1 for single-floor);
-- the footprint must be clear on every floor it spans. nil when the grid is full.
local function _findFreeCellSpanning(rooms, floor, shape, span)
    local mask = HDG.Projects.ShapeAtlas.GetMask(shape)
    local occ = {}
    for i = 0, span - 1 do occ[i] = _occupiedCells(rooms, floor + i) end
    for y = 0, 40 do
        for x = 0, 40 do
            local clear = true
            for _, m in ipairs(mask) do
                local k = (x + m[1]) .. "," .. (y + m[2])
                for i = 0, span - 1 do if occ[i][k] then clear = false; break end end
                if not clear then break end
            end
            if clear then return x, y end
        end
    end
    return nil  -- no free cell across the span -> caller declines to place
end
-- Place a room: ONE record on the selected floor. A multi-floor shape (stairs/tall =
-- 2, garden = 3) is STILL a single record -- FloorMap derives its vertical span and
-- projects it up. The cell must be free across that whole span.
local function _placePlannedRoom(shape)
    if shape == "entry" then return end   -- Entry is the anchor room; never placed
    -- What-if mode only: palette hidden on Live; this is defense-in-depth.
    if not HDG.Selectors:Call("projects.isWhatIfMode", HDG.Store:GetState(), {}) then return end  -- exception(false-positive): top-level controller helper, not a row factory
    local vid, version = _activeVersion()
    if not version then return end
    local SA    = HDG.Projects.ShapeAtlas
    local floor = HDG.Store:GetState().session.ui.projects.selectedFloor  -- exception(false-positive): top-level controller read
    local span  = SA.GetFloors(shape)
    if floor + span - 1 > 3 then return end   -- the span would exceed the 3-floor cap
    local x, y = _findFreeCellSpanning(version.rooms, floor, shape, span)
    if not x then return end   -- exception(nullable): no cell free across the span
    HDG.Store:Dispatch({ type = A.PROJECTS_UPSERT_ROOM, payload = {
        versionID = vid,
        roomID = _mintRoomID(version.rooms, HDG.Projects.IDs.makeFloorID(version.houseID, floor)),
        fields = { shape = shape, name = SA.GetLabel(shape),
                   cell = { x = x, y = y, rotation = 0, locked = false } },
    } })
end

-- "Expand Stairwell up": grow a stairwell one floor (the in-game push-up). Single
-- record -> just bump its `floors` override (capped at the 3-floor house limit), if
-- the cell directly above is clear. FloorMap projects the new span automatically.
function PC:ExpandStackUp(roomID)
    local vid, version = _activeVersion()
    if not (vid and version) then return end
    local SA, IDs = HDG.Projects.ShapeAtlas, HDG.Projects.IDs
    local room = version.rooms[roomID]
    if not room then return end
    local p = IDs.parsePath(roomID)
    if not p then return end
    local span     = room.floors or SA.GetFloors(room.shape)
    local topFloor = p.floor + span - 1
    if topFloor + 1 > 3 then return end   -- 3-floor cap

    -- Cell directly above must be clear (exclude self).
    local cells = SA.GetCells(room.shape)
    local mask  = SA.RotateMask(SA.GetMask(room.shape), room.cell.rotation or 0, cells[1], cells[2])
    local occ   = HDG.Projects.FloorMap.OccupiedCells(version.rooms, topFloor + 1, { [roomID] = true })
    for _, m in ipairs(mask) do
        if occ[(room.cell.x + m[1]) .. "," .. (room.cell.y + m[2])] then return end   -- blocked above
    end

    HDG.Store:Dispatch({ type = A.PROJECTS_UPSERT_ROOM,
        payload = { versionID = vid, roomID = roomID, fields = { floors = span + 1 } } })
end

-- Relative time for "captured/packed Xh ago". time() is a boundary read.
local function _relTime(epoch)
    if not epoch or epoch <= 0 then return "never" end
    local now = (time and time()) or 0  -- exception(boundary): GetTime/time absent in headless harness
    return HDG.Format.RelativeTime(now - epoch)
end

-- Kick the multi-floor capture sweep; surface its failure reason.
local function _captureHouse()
    local ok, err = HDG.HousingObserver:CaptureAllFloors()
    if not ok and _G.UIErrorsFrame then
        _G.UIErrorsFrame:AddMessage("Projects: " .. tostring(err), 1, 0.3, 0.3)   -- exception(boundary): Blizzard toast
    end
end


-- ===== Floor-tab chip + category rail ==============================================
HDG.ChipStrip:RegisterCellKind("projectsFloorChip", {
    constructor = function(parent, cfg) return HDG.ChipStrip:DefaultChipConstructor(parent, cfg) end,
    binder = function(chip, item, _cfg)
        if not item then
            chip:Hide(); chip:SetScript("OnClick", nil); return
        end
        HDG.UI:EnsureChipChrome(chip)
        chip:Show()
        chip:SetText("Floor " .. item.floor)
        HDG.Theme:Register(chip, "Button", { variant = "chip", active = item.isActive })
        chip:RegisterForClicks("LeftButtonUp")
        local floor = item.floor
        chip:SetScript("OnClick", function() _dispatchTransient("selectedFloor", floor) end)
    end,
    sizer = function(item, cfg)
        return HDG.ChipStrip:DefaultChipSizer({ label = "Floor " .. (item and item.floor or "?") }, cfg)
    end,
})


-- Decor-picker category rail: bare icon (no button box). Click mirrors OnCategoryClicked:
--   BACK -> clear cat+subcat | subcategory -> set subcat | category -> focus cat + reset subcat.
local function _railCellLabel(item)
    if item.isBack then return "Back" end   -- text (no dedicated back atlas yet)
    return item.atlas and ("|A:" .. item.atlas .. ":42:42|a") or (item.name or "")
end
local function _onRailClick(item)
    if item.isBack then
        _dispatchTransient("focusedCategoryID", nil)
        _dispatchTransient("focusedSubcategoryID", nil)
    elseif item.level == "subcategory" then
        -- Real branch, NOT `isAll and nil or id` -- Lua 5.1 trap returns id when isAll (ALL_ID=0 reads as Uncategorized).
        local subID; if not item.isAll then subID = item.id end
        _dispatchTransient("focusedSubcategoryID", subID)
    else  -- category
        local catID; if not item.isAll then catID = item.id end
        _dispatchTransient("focusedCategoryID", catID)
        _dispatchTransient("focusedSubcategoryID", nil)
    end
end
HDG.ChipStrip:RegisterCellKind("projectsRailIcon", {
    constructor = function(parent, cfg) return HDG.ChipStrip:IconChipConstructor(parent, cfg) end,
    binder = function(chip, item, _cfg)
        if not item then
            chip:Hide()
            chip:SetScript("OnClick", nil)
            -- Do NOT clear OnEnter/OnLeave: the chip is hidden (no hover), and clearing
            -- them clobbers TooltipEngine:Attach's once-installed HookScript -> no tooltip
            -- after the chip is re-shown (pooled re-acquire).
            return
        end
        chip:Show()
        chip:SetText(_railCellLabel(item))
        chip:RegisterForClicks("LeftButtonUp")
        chip:SetScript("OnClick", function() _onRailClick(item) end)
        chip._tooltipName = item.isBack and "Back" or item.name
        HDG.TooltipEngine:Attach(chip, function(self) return { title = self._tooltipName } end)
    end,
    sizer = function(item, cfg)
        return HDG.ChipStrip:DefaultChipSizer({ label = _railCellLabel(item) }, cfg)
    end,
})

-- Bulk-add: all shown, not-in-crate picker items. Gated by pickerCanBulkAdd (non-empty search).
local function _bulkAddPicker()
    local state   = HDG.Store:GetState()  -- exception(false-positive): top-level controller helper, not a row factory
    local crateID = state.session.ui.projects.pickerCrateID
    if not crateID then return end
    for _, r in ipairs(HDG.Selectors:Call("projects.pickerResults", state, {})) do
        if not r.inCrate then
            HDG.Store:Dispatch({ type = A.CRATE_ADD_DECOR, payload = { crateID = crateID, decorID = r.itemID } })
        end
    end
end

-- Import a saved Style's decor into the open crate. missingOnly skips existing crate items.
local function _importStyle(styleID, missingOnly)
    local state   = HDG.Store:GetState()  -- exception(false-positive): top-level controller helper, not a row factory
    local crateID = state.session.ui.projects.pickerCrateID
    local style   = state.account.collections[styleID]
    if not (crateID and style and style.items) then return end
    local inCrate, crate = {}, state.account.collections[crateID]
    if crate and crate.decor then for _, d in ipairs(crate.decor) do inCrate[d.id] = true end end
    for _, itemID in ipairs(style.items) do
        if not (missingOnly and inCrate[itemID]) then
            HDG.Store:Dispatch({ type = A.CRATE_ADD_DECOR, payload = { crateID = crateID, decorID = itemID } })
        end
    end
end

-- ===== Crate ledger (landing): orphan bay + crate inventory ================
-- One pooled row template, five kinds (orphanHeader/orphan/orphanEmpty/
-- inventoryHeader/inventoryRoom); per-kind paint shows/hides + re-anchors.

-- Reclaim menu: pick a target room (grouped by floor) for one orphan crate, or for ALL
-- (bulk, when orphanIDs given). Re-attach targets the active version.
local function _openReclaimMenu(owner, crateID, orphanIDs)
    local vid = _activeVersion()
    if not vid then return end
    local targets = HDG.Selectors:Call("projects.reclaimTargets", HDG.Store:GetState(), {})  -- exception(false-positive): top-level controller helper, not a row factory
    if #targets == 0 then return end
    local items, lastFloor = {}, nil
    for _, t in ipairs(targets) do
        if t.floor ~= lastFloor then
            items[#items + 1] = { isTitle = true, text = "Floor " .. t.floor }
            lastFloor = t.floor
        end
        local roomID = t.roomID
        items[#items + 1] = { text = t.label, callback = function()
            for _, cid in ipairs(orphanIDs or { crateID }) do
                HDG.Store:Dispatch({ type = A.CRATE_REATTACH,
                    payload = { crateID = cid, versionID = vid, roomID = roomID } })
            end
        end }
    end
    HDG.UI.ShowMenu(owner, items)
end

-- Discard confirm: %s placeholders are baked once; crate name/count come via textArgs,
-- crateID via data (so the same dialog serves every orphan row -- no stale closure).
local function _confirmDiscard(crateID, name, count)
    HDG.UI.Confirm({
        id       = "HDGR_PROJECTS_DISCARD_CRATE",
        text     = "Discard \"%s\"? It holds %s decor and can't be recovered.",
        accept   = "Discard", cancel = "Cancel",
        textArg1 = name or "Crate", textArg2 = tostring(count or 0), data = crateID,
        onAccept = function(_, data)
            if data then HDG.Store:Dispatch({ type = A.CRATE_DELETE, payload = { crateID = data } }) end
        end,
    })
end

local function _openRoomInArchitect(roomID)
    if not roomID then return end
    local p = HDG.Projects.IDs.parsePath(roomID)
    if p then _dispatchTransient("selectedFloor", p.floor) end
    _dispatchTransient("selectedRoomID", roomID)
    _setView("projectsArchitect")
end

local function _layoutLedgerRow(row)
    HDG.UI:EnsureRowChrome(row)
    local del = CreateFrame("Button", nil, row)
    del:SetSize(16, 16); del:SetPoint("RIGHT", row, "RIGHT", -6, 0); del:RegisterForClicks("LeftButtonUp")
    local dx = del:CreateFontString(nil, "OVERLAY"); HDG.UI.applyFontRole(dx, "body")
    dx:SetPoint("CENTER"); dx:SetText("x"); HDG.Theme:Register(dx, "TextDim")
    row._delBtn = del
    local action = HDG.UI.RowButton(row, "", 110, 18); action:RegisterForClicks("LeftButtonUp")
    row._actionBtn = action
    row._metaFs = HDG.UI.RowText(row, "caption", "TextDim", "RIGHT")
    row._nameFs = HDG.UI.RowText(row, "body", "Text", "LEFT")
    row._ledgerLaidOut = true
end

-- Hide all optional bits; each kind re-shows + re-anchors what it needs.
local function _ledgerClear(row)
    row._metaFs:SetText(""); row._metaFs:Hide()
    row._actionBtn:Hide(); row._actionBtn:SetScript("OnClick", nil)
    row._delBtn:Hide();    row._delBtn:SetScript("OnClick", nil)
    row:SetScript("OnClick", nil)
    row._roomID = nil
end

local function _nameFull(row)
    row._nameFs:ClearAllPoints()
    row._nameFs:SetPoint("LEFT", row, "LEFT", 8, 0)
    row._nameFs:SetPoint("RIGHT", row, "RIGHT", -8, 0)
end

local function _paintLedgerHeader(row, text)
    HDG.UI.applyFontRole(row._nameFs, "caption")
    row._nameFs:SetText(text)
    _nameFull(row)
end

local function _paintOrphanHeaderRow(row, ed)
    HDG.UI.applyFontRole(row._nameFs, "caption")
    row._nameFs:SetText("ORPHANED CRATES (" .. ed.count .. ")")
    row._actionBtn:SetText("Reclaim all into..."); row._actionBtn:SetWidth(130); row._actionBtn:Show()
    row._actionBtn:ClearAllPoints(); row._actionBtn:SetPoint("RIGHT", row, "RIGHT", -8, 0)
    local ids = ed.orphanIDs
    row._actionBtn:SetScript("OnClick", function(self) _openReclaimMenu(self, nil, ids) end)
    row._nameFs:ClearAllPoints()
    row._nameFs:SetPoint("LEFT", row, "LEFT", 8, 0)
    row._nameFs:SetPoint("RIGHT", row._actionBtn, "LEFT", -8, 0)
end

local function _paintOrphanRowL(row, ed)
    HDG.UI.applyFontRole(row._nameFs, "body")
    row._nameFs:SetText(ed.name)
    local meta = ed.decorCount .. " decor"
    if ed.was then meta = meta .. "  -  was " .. ed.was end
    if ed.orphanedAt then meta = meta .. "  -  " .. _relTime(ed.orphanedAt) end
    row._metaFs:SetText(meta); row._metaFs:Show()
    row._delBtn:Show()
    row._actionBtn:SetText("Reclaim into..."); row._actionBtn:SetWidth(110); row._actionBtn:Show()
    row._actionBtn:ClearAllPoints(); row._actionBtn:SetPoint("RIGHT", row._delBtn, "LEFT", -6, 0)
    row._metaFs:ClearAllPoints(); row._metaFs:SetPoint("RIGHT", row._actionBtn, "LEFT", -8, 0)
    row._nameFs:ClearAllPoints()
    row._nameFs:SetPoint("LEFT", row, "LEFT", 8, 0)
    row._nameFs:SetPoint("RIGHT", row._metaFs, "LEFT", -8, 0)
    local crateID, name, count = ed.crateID, ed.name, ed.decorCount
    row._actionBtn:SetScript("OnClick", function(self) _openReclaimMenu(self, crateID, nil) end)
    row._delBtn:SetScript("OnClick", function() _confirmDiscard(crateID, name, count) end)
end

local function _paintInventoryRoomRow(row, ed)
    HDG.UI.applyFontRole(row._nameFs, "body")
    row._nameFs:SetText(ed.label)
    row._metaFs:SetText("F" .. ed.floor .. "  -  " .. ed.decorCount .. " decor"); row._metaFs:Show()
    row._actionBtn:SetText("Open >"); row._actionBtn:SetWidth(64); row._actionBtn:Show()
    row._actionBtn:ClearAllPoints(); row._actionBtn:SetPoint("RIGHT", row, "RIGHT", -8, 0)
    row._metaFs:ClearAllPoints(); row._metaFs:SetPoint("RIGHT", row._actionBtn, "LEFT", -8, 0)
    row._nameFs:ClearAllPoints()
    row._nameFs:SetPoint("LEFT", row, "LEFT", 8, 0)
    row._nameFs:SetPoint("RIGHT", row._metaFs, "LEFT", -8, 0)
    local roomID = ed.roomID
    row._roomID = roomID
    row._actionBtn:SetScript("OnClick", function() _openRoomInArchitect(roomID) end)
    row:RegisterForClicks("LeftButtonUp")
    row:SetScript("OnClick", function() _openRoomInArchitect(roomID) end)
end

local function _paintLedgerRow(row, ed, template)
    HDG.Theme:Register(row, "RowChrome", { selected = false })
    _ledgerClear(row)
    if ed.kind == "orphanHeader" then
        _paintOrphanHeaderRow(row, ed)
    elseif ed.kind == "orphan" then
        _paintOrphanRowL(row, ed)
    elseif ed.kind == "orphanEmpty" then
        _paintLedgerHeader(row, "All clear -- nothing orphaned")
    elseif ed.kind == "inventoryHeader" then
        _paintLedgerHeader(row, "CRATE INVENTORY (" .. ed.count .. (ed.count == 1 and " room packed)" or " rooms packed)"))
    else  -- inventoryRoom
        _paintInventoryRoomRow(row, ed)
    end
    row:SetHeight(template.height)
end

local function _ledgerRowFactory(template)
    return {
        Configure = function(row, ed)
            if not row._ledgerLaidOut then _layoutLedgerRow(row) end
            _paintLedgerRow(row, ed, template)
        end,
        Reset = function(row)
            HDG.UI.ClearRowText(row, "_nameFs", "_metaFs")
            if row._actionBtn then row._actionBtn:SetScript("OnClick", nil) end
            if row._delBtn then row._delBtn:SetScript("OnClick", nil) end
            if row.SetScript then row:SetScript("OnClick", nil) end  -- exception(false-positive): Frame always has SetScript; mock-fidelity guard
            row._roomID = nil
        end,
    }
end

HDG.Rows:Register("projectsLedgerRow", {
    font = "body", height = 24, factory = _ledgerRowFactory,
    key  = function(ed)
        if not ed then return "ledger:?" end
        return "ledger:" .. tostring(ed.kind) .. ":" .. tostring(ed.crateID or ed.roomID or "")
    end,
})

-- ===== Crate-detail decor row factory (icon + name + count + remove) ========
local function _layoutCrateRow(row)
    local icon = row:CreateTexture(nil, "ARTWORK", nil, 2)
    icon:SetPoint("LEFT", row, "LEFT", 6, 0)
    icon:SetSize(18, 18)
    row._iconTex = icon
    -- Quantity stepper [- nn +] at the right edge. Button frames capture their own
    -- clicks so +/- don't trigger the row select. Defaults: rightInset=-4, size=16.
    HDG.UI.WireStepperCluster(row)
    local name = HDG.UI.RowText(row, "body", "Text", "LEFT")
    name:SetPoint("LEFT", icon, "RIGHT", 6, 0)
    name:SetPoint("RIGHT", row._minusBtn, "LEFT", -6, 0)
    row._nameFs = name
end

local function _paintCrateRow(row, ed)
    row._nameFs:SetText(ed.name or ("item " .. tostring(ed.decorID)))
    -- ed.icon is stamped by the crateDetail selector (NOT resolved here) so the
    -- async-load -> session.itemNames.tick -> selector re-run -> row re-bind cycle
    -- works -- same contract as Lumber/Shopping. Resolving at paint breaks it.
    if ed.icon then row._iconTex:SetTexture(ed.icon); row._iconTex:Show() else row._iconTex:Hide() end
    row._crateID, row._decorID = ed.crateID, ed.decorID

    -- Stepper: + = +1 (CRATE_ADD_DECOR no-count increments); - = -1 (removes at 0).
    -- A crate entry is always >= 1, so the full [- nn +] always shows.
    row._qtyFs:SetText(tostring(ed.count))
    row._plusBtn:Show()
    row._plusBtn:SetScript("OnClick", function()
        if not (row._crateID and row._decorID) then return end
        HDG.Store:Dispatch({ type = A.CRATE_ADD_DECOR,
            payload = { crateID = row._crateID, decorID = row._decorID } })
    end)
    row._minusBtn:Show()
    row._minusBtn:SetScript("OnClick", function()
        if not (row._crateID and row._decorID) then return end
        HDG.Store:Dispatch({ type = A.CRATE_DECREMENT_DECOR,
            payload = { crateID = row._crateID, decorID = row._decorID } })
    end)
end

HDG.Rows:Register("projectsCrateRow", {
    font = "body", height = 22,
    factory = HDG.UI.MakeRowFactory({
        layout     = _layoutCrateRow,
        paint      = _paintCrateRow,
        laidOutTag = "_crateLaidOut",
        resetText  = { "_nameFs", "_qtyFs" },
        reset      = function(row)
            row._iconTex:Hide()
            row._plusBtn:SetScript("OnClick", nil)
            row._minusBtn:SetScript("OnClick", nil)
            row._crateID, row._decorID = nil, nil
        end,
    }),
    key = function(ed) return "crate:" .. tostring(ed and ed.decorID or "?") end,
})

-- Crate key = "crate:<versionID>:<roomID>" (version-scoped; what-if reuses parent roomIDs).
-- CRATE_UPSERT is idempotent; crate authoring works on any version (Live or what-if).
local function _crateIDFor(vid, roomID) return "crate:" .. vid .. ":" .. roomID end
local function _addCrateToSelectedRoom()
    local roomID = HDG.Store:GetState().session.ui.projects.selectedRoomID  -- exception(false-positive): top-level controller read
    if not roomID then return end
    local vid = _activeVersion()
    if not vid then return end
    HDG.Store:Dispatch({
        type    = A.CRATE_UPSERT,
        payload = { crateID = _crateIDFor(vid, roomID),
                    fields = { parent = roomID, versionID = vid, name = "Crate", createdAt = (time and time()) or 0 } },  -- exception(boundary): time()
    })
end

-- Detach the selected room's crate -> orphan bay (reattachable). Recoverable, so no confirm.
local function _detachCrate()
    local cd = HDG.Selectors:Call("projects.crateDetail", HDG.Store:GetState(), {})  -- exception(false-positive): top-level controller helper, not a row factory
    if cd.hasCrate and cd.crateID then
        HDG.Store:Dispatch({ type = A.CRATE_DETACH,
            payload = { crateID = cd.crateID, ts = (time and time()) or 0 } })  -- exception(boundary): time()
    end
end

-- ===== Decor picker row: icon + name + stepper =====
-- Row-body click selects for 3D preview; stepper adjusts the crate. - appears when crateCount > 0.
local function _layoutPickerRow(row)
    local icon = row:CreateTexture(nil, "ARTWORK", nil, 2)
    icon:SetPoint("LEFT", row, "LEFT", 6, 0)
    icon:SetSize(20, 20)
    row._iconTex = icon
    -- Picker uses rightInset=-6 (wider margin than the crate row's -4).
    HDG.UI.WireStepperCluster(row, { rightInset = -6 })
    local name = HDG.UI.RowText(row, "body", "Text", "LEFT")
    name:SetPoint("LEFT", icon, "RIGHT", 6, 0)
    name:SetPoint("RIGHT", row._minusBtn, "LEFT", -6, 0)
    row._nameFs = name
end

local function _pickerAdjust(row, actionType)
    local crateID = HDG.Store:GetState().session.ui.projects.pickerCrateID  -- exception(false-positive): top-level controller read
    if crateID and row._itemID then
        HDG.Store:Dispatch({ type = actionType, payload = { crateID = crateID, decorID = row._itemID } })
    end
end

local function _paintPickerRow(row, ed)
    row._nameFs:SetText(ed.name or ("item " .. tostring(ed.itemID)))
    if ed.iconAtlas then row._iconTex:SetAtlas(ed.iconAtlas); row._iconTex:Show()
    elseif ed.iconTexture then row._iconTex:SetTexture(ed.iconTexture); row._iconTex:Show()
    else row._iconTex:Hide() end
    row._itemID = ed.itemID
    local cc = ed.crateCount
    row._plusBtn:Show()
    row._plusBtn:SetScript("OnClick", function() _pickerAdjust(row, A.CRATE_ADD_DECOR) end)
    if cc > 0 then
        row._qtyFs:SetText(tostring(cc))
        row._minusBtn:Show()
        row._minusBtn:SetScript("OnClick", function() _pickerAdjust(row, A.CRATE_DECREMENT_DECOR) end)
    else
        row._qtyFs:SetText("")
        row._minusBtn:Hide()
        row._minusBtn:SetScript("OnClick", nil)
    end
end

local function _wirePickerRow(row, ed)
    row:SetScript("OnClick", function(self) _dispatchTransient("pickerSelectedItemID", self._itemID) end)
end

HDG.Rows:Register("projectsPickerRow", {
    font = "body", height = 24,
    factory = HDG.UI.MakeRowFactory({
        layout     = _layoutPickerRow,
        paint      = _paintPickerRow,
        laidOutTag = "_pickerLaidOut",
        clicks     = "LeftButtonUp",
        wire       = _wirePickerRow,
        resetText  = { "_nameFs", "_qtyFs" },
        reset      = function(row)
            row._iconTex:Hide()
            row._plusBtn:SetScript("OnClick", nil)
            row._minusBtn:SetScript("OnClick", nil)
            row._itemID = nil
        end,
    }),
    key = function(ed) return "pick:" .. tostring(ed and ed.itemID or "?") end,
})

-- ===== Orphan crate row: re-attach to selected room or delete ================
local function _layoutOrphanRow(row)
    local del = CreateFrame("Button", nil, row)
    del:SetSize(16, 16); del:SetPoint("RIGHT", row, "RIGHT", -6, 0); del:RegisterForClicks("LeftButtonUp")
    local dx = del:CreateFontString(nil, "OVERLAY"); HDG.UI.applyFontRole(dx, "body")
    dx:SetPoint("CENTER"); dx:SetText("x"); HDG.Theme:Register(dx, "TextDim")
    row._delBtn = del
    local attach = HDG.UI.RowButton(row, "Re-attach", 72, 18)
    attach:SetPoint("RIGHT", del, "LEFT", -6, 0); attach:RegisterForClicks("LeftButtonUp")
    row._attachBtn = attach
    local name = HDG.UI.RowText(row, "body", "Text", "LEFT")
    name:SetPoint("LEFT", row, "LEFT", 6, 0); name:SetPoint("RIGHT", attach, "LEFT", -6, 0)
    row._nameFs = name
end

local function _paintOrphanRow(row, ed)
    local label = ed.name or "Crate"
    if ed.lastKnownShape then label = label .. "  (was " .. HDG.Projects.ShapeAtlas.GetLabel(ed.lastKnownShape) .. ")" end
    row._nameFs:SetText(label)
    row._orphanID = ed.id
    row._attachBtn:SetScript("OnClick", function()
        local vid    = _activeVersion()
        local roomID = HDG.Store:GetState().session.ui.projects.selectedRoomID  -- exception(false-positive): top-level controller read
        if vid and roomID and row._orphanID then
            HDG.Store:Dispatch({ type = A.CRATE_REATTACH,
                payload = { crateID = row._orphanID, versionID = vid, roomID = roomID } })
        end
    end)
    row._delBtn:SetScript("OnClick", function()
        if row._orphanID then HDG.Store:Dispatch({ type = A.CRATE_DELETE, payload = { crateID = row._orphanID } }) end
    end)
end

HDG.Rows:Register("projectsOrphanRow", {
    font = "body", height = 22,
    factory = HDG.UI.MakeRowFactory({
        layout     = _layoutOrphanRow,
        paint      = _paintOrphanRow,
        laidOutTag = "_orphanLaidOut",
        resetText  = { "_nameFs" },
        reset      = function(row)
            row._attachBtn:SetScript("OnClick", nil)
            row._delBtn:SetScript("OnClick", nil)
            row._orphanID = nil
        end,
    }),
    key = function(ed) return "orphan:" .. tostring(ed and ed.id or "?") end,
})

-- ===== Room picker list row: blueprint icon + name + cost; click places =====

-- Tooltip: footprint/height/doors/weight + live budget preview "Rooms: N -> N / max".
-- HookScript on row so one Attach covers all pooled binds (reads live row._shape).
local function _roomRowTooltipDef(row)
    local SA, shape = HDG.Projects.ShapeAtlas, row._shape
    if not shape then return nil end   -- pooled row not bound to a shape -> no tooltip
    local dims, cells, doors = SA.GetDims(shape), SA.GetCells(shape), SA.GetDoors(shape)
    local weight, lines = SA.GetBudget(shape), {}
    if dims and cells then
        lines[#lines + 1] = { text = string.format("%d x %d yd  (%d x %d cells)", dims[1], dims[2], cells[1], cells[2]), r = 0.82, g = 0.82, b = 0.82 }
        lines[#lines + 1] = { text = string.format("%d yd tall", dims[3]), r = 0.68, g = 0.68, b = 0.68 }
    end
    if doors and #doors > 0 then
        lines[#lines + 1] = { text = "Doors: " .. table.concat(doors, " "), r = 0.68, g = 0.68, b = 0.68 }
    end
    lines[#lines + 1] = { text = "Placement weight: " .. weight, r = 0.82, g = 0.82, b = 0.82 }
    local bud = HDG.Selectors:Call("projects.roomBudget", HDG.Store:GetState(), {})  -- exception(false-positive): top-level controller helper, not a row factory
    if bud.max > 0 then
        local newCost, over = bud.cost + weight, (bud.cost + weight) > bud.max
        lines[#lines + 1] = { text = string.format("Rooms: %d -> %d / %d", bud.cost, newCost, bud.max),
                              r = over and 0.95 or 0.55, g = over and 0.6 or 0.9, b = 0.45 }
    end
    lines[#lines + 1] = { text = "Click to place", r = 0.55, g = 0.78, b = 1 }
    return { title = SA.GetLabel(shape), extraLines = lines }
end
local function _layoutRoomRow(row)
    local icon = row:CreateTexture(nil, "ARTWORK", nil, 2)   -- shape blueprint glyph
    icon:SetPoint("LEFT", row, "LEFT", 6, 0)
    icon:SetSize(30, 30)
    row._iconTex = icon
    local name = HDG.UI.RowText(row, "body", "Text", "LEFT")
    name:SetPoint("TOPLEFT", icon, "TOPRIGHT", 8, -2)
    name:SetPoint("RIGHT", row, "RIGHT", -6, 0)
    row._nameFs = name
    local cost = HDG.UI.RowText(row, "caption", "TextDim", "LEFT")
    cost:SetPoint("TOPLEFT", name, "BOTTOMLEFT", 0, -2)
    cost:SetPoint("RIGHT", row, "RIGHT", -6, 0)
    row._costFs = cost
    HDG.TooltipEngine:Attach(row, _roomRowTooltipDef)   -- once; reads live row._shape
end
local function _paintRoomRow(row, ed)
    row._nameFs:SetText(ed.label)
    row._costFs:SetText("cost " .. tostring(ed.budget))
    if ed.atlas then row._iconTex:SetAtlas(ed.atlas, false); row._iconTex:Show() else row._iconTex:Hide() end
    row._shape = ed.shape
end
local function _wireRoomRow(row)
    row:SetScript("OnClick", function(self) _placePlannedRoom(self._shape) end)
end
HDG.Rows:Register("projectsRoomListRow", {
    font = "body", height = 40,
    factory = HDG.UI.MakeRowFactory({
        layout     = _layoutRoomRow,
        paint      = _paintRoomRow,
        laidOutTag = "_roomRowLaidOut",
        clicks     = "LeftButtonUp",
        wire       = _wireRoomRow,
        resetText  = { "_nameFs", "_costFs" },
        reset      = function(row)
            row._iconTex:Hide()
            row._shape = nil
        end,
    }),
    key = function(ed) return "room:" .. tostring(ed and ed.shape or "?") end,
})

-- ===== Room shopping-list row: "+N shape wt" (build) / "-N shape wt" (remove) ===
local function _layoutShoppingRow(row)
    local wt = HDG.UI.RowText(row, "caption", "TextDim", "RIGHT")
    wt:SetPoint("RIGHT", row, "RIGHT", -6, 0)
    row._wtFs = wt
    local name = HDG.UI.RowText(row, "caption", "Text", "LEFT")
    name:SetPoint("LEFT", row, "LEFT", 6, 0)
    name:SetPoint("RIGHT", wt, "LEFT", -4, 0)
    row._nameFs = name
end
local function _paintShoppingRow(row, ed)
    HDG.Theme:Register(row._nameFs, "Text")
    local prefix = (ed.kind == "build") and "+" or "-"
    local cc = HDG.Theme:ColorCode(ed.kind == "build" and "semantic.success" or "semantic.warning")
    row._nameFs:SetText(cc .. prefix .. ed.count .. "  " .. ed.label .. "|r")
    row._wtFs:SetText(ed.weight .. " wt")
end
HDG.Rows:Register("projectsShoppingRow", {
    font = "caption", height = 20,
    factory = HDG.UI.MakeRowFactory({
        layout     = _layoutShoppingRow,
        paint      = _paintShoppingRow,
        laidOutTag = "_shopLaidOut",
        resetText  = { "_nameFs", "_wtFs" },
    }),
    key = function(ed) return "shop:" .. tostring(ed and (ed.kind .. ":" .. ed.shape) or "?") end,
})

-- ===== Style-import menu: per style -> Add all / Add missing =================
-- Replaces the old style scrollbox (was stacked above the decor list). Reuses
-- projects.pickerStyleRows + _importStyle.
local function _openStyleImportMenu(owner)
    local rows = HDG.Selectors:Call("projects.pickerStyleRows", HDG.Store:GetState(), {})  -- exception(false-positive): top-level controller helper, not a row factory
    if #rows == 0 then return end
    local items = { { isTitle = true, text = "Import from a Style" } }
    for _, s in ipairs(rows) do
        local id = s.id
        items[#items + 1] = { isTitle = true, text = s.name .. "  (" .. s.count .. ")" }
        items[#items + 1] = { text = "Add all",          callback = function() _importStyle(id, false) end }
        items[#items + 1] = { text = "Add missing only", callback = function() _importStyle(id, true)  end }
    end
    HDG.UI.ShowMenu(owner, items)
end

-- Open the picker for the selected room's crate; Back closes it.
local function _openDecorPicker()
    local cd = HDG.Selectors:Call("projects.crateDetail", HDG.Store:GetState(), {})  -- exception(false-positive): top-level controller helper, not a row factory
    if not cd.hasCrate then return end
    _dispatchTransient("pickerCrateID", cd.crateID)
    _dispatchTransient("pickerSearch", "")
    _dispatchTransient("pickerSelectedItemID", nil)
    _setView("projectsPicker")
end
local function _closeDecorPicker()
    _dispatchTransient("pickerCrateID", nil)
    _setView("projectsArchitect")
end

-- ===== Crate import / export ===============================================
local function _exportCrate()
    local cd = HDG.Selectors:Call("projects.crateDetail", HDG.Store:GetState(), {})  -- exception(false-positive): top-level controller helper, not a row factory
    if not cd.hasCrate then return end
    local crate = HDG.Store:GetState().account.collections[cd.crateID]  -- exception(false-positive): top-level controller read
    local code  = HDG.Projects.CrateCodec.Encode(crate)
    if not code then return end
    local dialog = HDG.UI:CopyDialog()   -- exception(boundary): UI helper may be unbuilt pre-first-open
    if dialog and dialog.Open then dialog:Open("Export crate: " .. (crate.name or "Crate"), code) end
end

-- Decode pasted code -> upsert crate + merge decor (CRATE_ADD_DECOR dedups by id).
local function _importCrateString(value)
    local decoded = HDG.Projects.CrateCodec.Decode(value)
    if not decoded then
        if _G.UIErrorsFrame then   -- exception(boundary): Blizzard toast
            _G.UIErrorsFrame:AddMessage("Projects: unrecognised crate code (expected HDGRCRATE:1:...)", 1, 0.3, 0.3)
        end
        return
    end
    local roomID = HDG.Store:GetState().session.ui.projects.selectedRoomID  -- exception(false-positive): top-level controller read
    if not roomID then return end
    local vid = _activeVersion()
    if not vid then return end
    local crateID = _crateIDFor(vid, roomID)
    HDG.Store:Dispatch({ type = A.CRATE_UPSERT, payload = { crateID = crateID,
        fields = { parent = roomID, versionID = vid, name = decoded.name or "Crate", createdAt = (time and time()) or 0 } } })  -- exception(boundary): time()
    for _, d in ipairs(decoded.decor or {}) do
        HDG.Store:Dispatch({ type = A.CRATE_ADD_DECOR, payload = { crateID = crateID, decorID = d.id, count = d.count } })
    end
end

-- ===== Wire ================================================================
function PC:Wire(rootFrame)
    HDG.UI.OnClick(rootFrame, "projectsLandingPanel.newDesign",      _startNewDesign)
    HDG.UI.OnClick(rootFrame, "projectsLandingPanel.newWhatIf",      _newWhatIfFromPicker)
    HDG.UI.OnClick(rootFrame, "projectsLandingPanel.openArchitect",  function() _setView("projectsArchitect") end)
    HDG.UI.OnClick(rootFrame, "projectsNavPanel.captureAll",         _captureHouse)
    HDG.UI.OnClick(rootFrame, "projectsNavPanel.addFloor",           function() _setWhatIfFloors(1) end)
    HDG.UI.OnClick(rootFrame, "projectsNavPanel.removeFloor",        function() _setWhatIfFloors(-1) end)
    HDG.UI.OnClick(rootFrame, "projectsNavPanel.versionMenu",        function(self) _openVersionMenu(self) end)
    HDG.UI.OnClick(rootFrame, "projectsPickerPanel.newWhatIf",       _newWhatIfFromPicker)
    HDG.UI.OnClick(rootFrame, "projectsDetailPanel.addCrate",        _addCrateToSelectedRoom)
    HDG.UI.OnClick(rootFrame, "projectsDetailPanel.detachCrate",     _detachCrate)
    HDG.UI.OnClick(rootFrame, "projectsDetailPanel.addDecor",        _openDecorPicker)
    HDG.UI.OnClick(rootFrame, "projectsDetailPanel.exportCrate",     _exportCrate)
    HDG.UI.OnClick(rootFrame, "projectsDetailPanel.importCrate", function()
        HDG.UI:PromptInput("Import Crate", {
            hint = "Paste a crate code, then Import.", acceptText = "Import",
            onAccept = function(value) _importCrateString(value) end,
        })
    end)
    HDG.UI.OnClick(rootFrame, "projectsPickerListPanel.back",        _closeDecorPicker)
    HDG.UI.OnClick(rootFrame, "projectsPickerListPanel.styleImport", function(self) _openStyleImportMenu(self) end)
    HDG.UI.OnClick(rootFrame, "projectsPickerListPanel.addAll",      _bulkAddPicker)
    HDG.UI.WireSearchBox(rootFrame, "projectsPickerListPanel.search", "projects", "pickerSearch")
end

function PC:Refresh(_rootFrame, _ctx)
    -- All rendering flows through bindings + the row/chip factories + the canvas
    -- controller; nothing imperative needed here (same shape as LumberController).
end

HDG.Controllers:Register("projects", PC)
