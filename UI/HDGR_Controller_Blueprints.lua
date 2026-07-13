-- HDGR_Controller_Blueprints.lua
-- ============================================================================
-- Thin glue for the Blueprints tab (12.1): Wire() attaches behavior to the
-- LayoutConfig-declared frames; row factories render the collection + content
-- scrollboxes. No chrome creation here. 12.1-only: dormant on live.
if not HDG.Constants.IS_121 then return end  -- exception(boundary): 12.1-only view

HDG = HDG or {}
HDG.Controller_Blueprints = HDG.Controller_Blueprints or {}
local C = HDG.Controller_Blueprints
local A = HDG.Constants.ACTIONS

-- ===== Shared helpers ========================================================

local function _selectedCode()
    return HDG.Store:GetState().session.blueprints.selectedCode  -- exception(false-positive): top-level controller read, not a row factory
end

local function _targetHouse()
    return HDG.Store:GetState().session.blueprints.targetHouseGUID  -- exception(false-positive): top-level controller read, not a row factory
end

-- Select a code and fetch its manifest unless one is already cached OR already
-- in flight (design's in-flight dedupe: re-firing a pending request resets
-- requestedAt, silently postponing the escalation copy and the timeout sweep).
-- Failed manifests DO re-request -- re-selecting the row is the retry path.
local function _selectAndFetch(shareCode)
    HDG.Store:Dispatch({ type = A.BLUEPRINT_SELECT, payload = { shareCode = shareCode } })
    local m = HDG.Store:GetState().session.blueprints.manifests[shareCode]  -- exception(false-positive): top-level controller read
    if not m or (m.status ~= "received" and m.status ~= "pending") then
        HDG.BlueprintObserver:RequestContents(shareCode, _targetHouse())
    end
end

-- ===== Row factory: blueprintCollectionRow ==================================
-- Two shapes (ed.kind): "header" group label / "row" blueprint entry with
-- selected chrome, AUTO/type tag, and a Forget button on pasted rows ONLY.
-- SAFETY: Forget dispatches BLUEPRINT_FORGET (HDG-state-only) -- it never
-- touches Blizzard's blueprint catalog, and collection rows get no button.

local function _layoutCollectionRow(row)
    HDG.UI:EnsureRowChrome(row)
    local headerFs = HDG.UI.RowText(row, "caption", "TextStatus", "LEFT")
    headerFs:SetPoint("LEFT", row, "LEFT", 8, 0)
    headerFs:SetPoint("RIGHT", row, "RIGHT", -8, 0)
    headerFs:SetWordWrap(false)   -- long names truncate, never wrap into the next row
    row._headerFs = headerFs

    -- Zone divider ("Your catalog") -- centered white label with a hairline
    -- underneath, marking where the saved catalog begins.
    local dividerFs = HDG.UI.RowText(row, "caption", "Text", "CENTER")
    dividerFs:SetPoint("LEFT", row, "LEFT", 8, 0)
    dividerFs:SetPoint("RIGHT", row, "RIGHT", -8, 0)
    dividerFs:SetWordWrap(false)
    row._dividerFs = dividerFs

    local dividerLine = row:CreateTexture(nil, "ARTWORK", nil, 2)
    dividerLine:SetHeight(1)
    dividerLine:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 8, 3)
    dividerLine:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", -8, 3)
    HDG.Theme:Register(dividerLine, "Divider")  -- repaints on scheme switch
    dividerLine:Hide()
    row._dividerLine = dividerLine

    local forgetBtn = CreateFrame("Button", nil, row)
    forgetBtn:SetSize(16, 16)
    forgetBtn:SetPoint("RIGHT", row, "RIGHT", -6, 0)
    local x = HDG.UI.RowText(forgetBtn, "body", "TextDim", "CENTER")
    x:SetAllPoints()
    x:SetText("x")
    forgetBtn._x = x
    forgetBtn:SetAlpha(0.4)  -- quiet until hovered; always present on pasted rows (visible affordance)
    forgetBtn:SetScript("OnEnter", function(self) self:SetAlpha(1) end)
    forgetBtn:SetScript("OnLeave", function(self) self:SetAlpha(0.4) end)
    -- Hover tooltip names WHICH remove this is BEFORE the click: catalog rows
    -- delete permanently, pasted rows just forget the code (UX review #4).
    -- Attach hooks (doesn't clobber the alpha scripts above).
    HDG.TooltipEngine:Attach(forgetBtn, function(self)
        if self._deleteBID then
            return { title = HDG.Locale:Get("TIP_BP_DELETE_TITLE"), body = HDG.Locale:Get("TIP_BP_DELETE_BODY") }
        end
        return { title = HDG.Locale:Get("TIP_BP_FORGET_TITLE"), body = HDG.Locale:Get("TIP_BP_FORGET_BODY") }
    end)
    forgetBtn:SetScript("OnClick", function(self)
        if self._deleteBID then
            HDG.Controller_Blueprints:_ConfirmDelete(self._deleteBID, self._deleteName)
        elseif self._shareCode then
            HDG.Store:Dispatch({ type = A.BLUEPRINT_FORGET, payload = { shareCode = self._shareCode } })
        end
    end)
    row._forgetBtn = forgetBtn

    local tagFs = HDG.UI.RowText(row, "caption", "TextDim", "RIGHT")
    tagFs:SetPoint("RIGHT", forgetBtn, "LEFT", -4, 0)
    tagFs:SetWordWrap(false)
    row._tagFs = tagFs

    local nameFs = HDG.UI.RowText(row, "body", "Text", "LEFT")
    nameFs:SetPoint("LEFT", row, "LEFT", 8, 0)
    nameFs:SetPoint("RIGHT", tagFs, "LEFT", -4, 0)
    nameFs:SetWordWrap(false)
    row._nameFs = nameFs

    row._laidOut = true
end

local function _paintCollectionRow(row, ed)
    if ed.kind == "divider" then
        row._dividerFs:Show()
        row._dividerLine:Show()
        row._headerFs:Hide()
        row._nameFs:Hide()
        row._tagFs:Hide()
        row._forgetBtn:Hide()
        row._dividerFs:SetText(ed.label)
        HDG.Theme:Register(row, "RowChrome", { header = true })
    elseif ed.kind == "header" then
        row._dividerFs:Hide()
        row._dividerLine:Hide()
        row._headerFs:Show()
        row._nameFs:Hide()
        row._tagFs:Hide()
        row._forgetBtn:Hide()
        row._headerFs:SetText(ed.label)
        HDG.Theme:Register(row, "RowChrome", { header = true })
    else
        row._dividerFs:Hide()
        row._dividerLine:Hide()
        row._headerFs:Hide()
        row._nameFs:Show()
        row._tagFs:Show()
        row._nameFs:SetText(ed.name)
        -- Faction tint (House/Exterior blueprints, once inspected): Alliance-blue
        -- / Horde-red name; everything else keeps the default text color.
        HDG.Theme:Register(row._nameFs,
            (ed.faction == "Alliance" and "TextAlliance")
            or (ed.faction == "Horde" and "TextHorde") or "Text")
        row._tagFs:SetText(ed.isAuto and "AUTO" or (ed.typeLabel or (ed.isPasted and "shared" or "")))
        -- Row remove `x`: pasted rows FORGET (HDG-list-only, no confirm);
        -- own MANUAL blueprints DELETE from the catalog (confirm dialog).
        -- Auto-backups are read-only, so they get no `x`.
        local canForget = ed.isPasted == true
        local canDelete = (not ed.isPasted) and ed.blueprintID ~= nil and ed.isAuto ~= true
        row._forgetBtn:SetShown(canForget or canDelete)
        row._forgetBtn._shareCode  = canForget and ed.shareCode or nil
        row._forgetBtn._deleteBID  = canDelete and ed.blueprintID or nil
        row._forgetBtn._deleteName = canDelete and ed.name or nil
        HDG.Theme:Register(row, "RowChrome", { selected = ed.isSelected })
    end
    row._edKind    = ed.kind
    row._shareCode = ed.shareCode
end

local function _wireCollectionRow(row)
    row:SetScript("OnClick", function(self)
        if self._edKind ~= "row" or not self._shareCode then return end
        _selectAndFetch(self._shareCode)
    end)
end

local function _resetCollectionRow(row)
    HDG.UI.ClearRowText(row, "_headerFs", "_dividerFs", "_nameFs", "_tagFs")
    row._dividerLine:Hide()
    row._forgetBtn:Hide()
    row._forgetBtn._shareCode, row._forgetBtn._deleteBID, row._forgetBtn._deleteName = nil, nil, nil
    row._edKind, row._shareCode = nil, nil
end

local function _collectionRowFactory(_def)
    return {
        Configure = function(rowFrame, ed)
            if not rowFrame._laidOut then _layoutCollectionRow(rowFrame) end
            _paintCollectionRow(rowFrame, ed)
            _wireCollectionRow(rowFrame)
        end,
        Reset = function(rowFrame) _resetCollectionRow(rowFrame) end,
    }
end

HDG.Rows:Register("blueprintCollectionRow", {
    font = "body", height = 24,
    factory = _collectionRowFactory,
    key = function(ed)
        -- Keys use the INTERNAL identity, not the shareCode: the same code can
        -- legitimately appear as a pasted row AND an own-collection row (both
        -- are real entries; PTR key-collision 2026-07-12). Collection rows key
        -- on blueprintID (unique numeric); pasted rows on the code.
        if not ed then return "bpColl:?" end
        if ed.kind == "divider" then return "bpCollDiv" end  -- no shareCode/blueprintID; must not fall through to "bpColl:nil"
        if ed.kind == "header" then return "bpCollHdr:" .. tostring(ed.label) end
        if ed.isPasted then return "bpPasted:" .. tostring(ed.shareCode) end
        return "bpColl:" .. tostring(ed.blueprintID or ed.shareCode)  -- exception(nullable): blueprintID nil on pre-68569 rows
    end,
})

-- ===== Row factory: blueprintContentRow =====================================
-- Two shapes (ed.kind): "header" collapsible group bar / "item" manifest entry
-- (name | owned/total | need-badge | source chip). Chip colors come from the
-- existing SOURCE_KINDS system via Format.SourceChip -- no new roles.

local function _toggleGroupCollapse(ct)
    -- Immutable copy-update: never mutate the table a selector handed out.
    local cur = HDG.Store:GetState().session.ui.blueprints.collapsedGroups  -- exception(false-positive): top-level controller read
    local next_ = {}
    for k, v in pairs(cur) do next_[k] = v end
    next_[ct] = not next_[ct] or nil
    HDG.Store:Dispatch({ type = A.UI_SET_TRANSIENT,
        payload = { view = "blueprints", key = "collapsedGroups", value = next_ } })
end

local function _layoutContentRow(row)
    HDG.UI:EnsureRowChrome(row)
    local headerFs = HDG.UI.RowText(row, "body", "TextStatus", "LEFT")
    headerFs:SetPoint("LEFT", row, "LEFT", 8, 0)
    headerFs:SetPoint("RIGHT", row, "RIGHT", -8, 0)
    headerFs:SetWordWrap(false)   -- long names truncate, never wrap into the next row
    row._headerFs = headerFs

    local chipFs = HDG.UI.RowText(row, "caption", "TextDim", "RIGHT")
    chipFs:SetPoint("RIGHT", row, "RIGHT", -8, 0)
    chipFs:SetWidth(190)
    chipFs:SetWordWrap(false)
    row._chipFs = chipFs

    local needFs = HDG.UI.RowText(row, "caption", "TextDim", "RIGHT")
    needFs:SetPoint("RIGHT", chipFs, "LEFT", -6, 0)
    needFs:SetWidth(52)
    needFs:SetWordWrap(false)
    row._needFs = needFs

    local ownFs = HDG.UI.RowText(row, "caption", "TextDim", "RIGHT")
    ownFs:SetPoint("RIGHT", needFs, "LEFT", -6, 0)
    ownFs:SetWidth(36)
    ownFs:SetWordWrap(false)
    row._ownFs = ownFs

    local nameFs = HDG.UI.RowText(row, "body", "Text", "LEFT")
    nameFs:SetPoint("LEFT", row, "LEFT", 16, 0)
    nameFs:SetPoint("RIGHT", ownFs, "LEFT", -4, 0)
    nameFs:SetWordWrap(false)
    row._nameFs = nameFs

    row._laidOut = true
end

local function _paintContentRow(row, ed)
    if ed.kind == "header" then
        row._headerFs:Show()
        row._nameFs:Hide(); row._ownFs:Hide(); row._needFs:Hide(); row._chipFs:Hide()
        local suffix = (ed.missing > 0) and ("  --  " .. ed.missing .. " missing") or ""
        row._headerFs:SetText(HDG.UI.CollapsePrefix(ed.collapsed) .. ed.label .. "  (" .. ed.count .. ")" .. suffix)
        -- Headers carrying missing items escalate so a scroll down the group
        -- bars alone shows where the gaps are (UX review #12).
        HDG.Theme:Register(row._headerFs, (ed.missing > 0) and "TextWarning" or "TextStatus")
        HDG.Theme:Register(row, "RowChrome", { header = true })
    else
        row._headerFs:Hide()
        row._nameFs:Show(); row._ownFs:Show(); row._needFs:Show(); row._chipFs:Show()
        row._nameFs:SetText(ed.name)
        HDG.Theme:Register(row._nameFs, ed.invalid and "TextError" or (ed.numMissing > 0 and "Text" or "TextDim"))
        row._ownFs:SetText((ed.total - ed.numMissing) .. "/" .. ed.total)
        if ed.numMissing > 0 then
            row._needFs:SetText("need " .. ed.numMissing)
            HDG.Theme:Register(row._needFs, "TextWarning")
        else
            -- Owned: the same green check the Decor/Acquire collected marks use.
            row._needFs:SetText("|A:common-icon-checkmark:12:12|a")
            HDG.Theme:Register(row._needFs, "TextDim")
        end
        if ed.srcKind then
            row._chipFs:SetText(HDG.Format.SourceChip(ed.srcKind, ed.numMissing == 0) .. " " .. (ed.srcName or ""))
        elseif ed.numMissing > 0 and ed.itemID then
            row._chipFs:SetText("resolves at vendor")
        else
            row._chipFs:SetText("")
        end
        HDG.Theme:Register(row, "RowChrome", {})
    end
    row._edKind = ed.kind
    row._ct     = ed.ct
    row._tip    = ed.tooltip
end

local function _wireContentRow(row)
    row:SetScript("OnClick", function(self)
        if self._edKind == "header" and self._ct then _toggleGroupCollapse(self._ct) end
    end)
    row:SetScript("OnEnter", function(self)
        if self._tip then
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(self._tip, nil, nil, nil, nil, true)
            GameTooltip:Show()
        end
    end)
    row:SetScript("OnLeave", function() GameTooltip:Hide() end)
end

local function _resetContentRow(row)
    HDG.UI.ClearRowText(row, "_headerFs", "_nameFs", "_ownFs", "_needFs", "_chipFs")
    row._edKind, row._ct, row._tip = nil, nil, nil
end

local function _contentRowFactory(_def)
    return {
        Configure = function(rowFrame, ed)
            if not rowFrame._laidOut then _layoutContentRow(rowFrame) end
            _paintContentRow(rowFrame, ed)
            _wireContentRow(rowFrame)
        end,
        Reset = function(rowFrame) _resetContentRow(rowFrame) end,
    }
end

HDG.Rows:Register("blueprintContentRow", {
    font = "body", height = 22,
    factory = _contentRowFactory,
    key = function(ed)
        if not ed then return "bpRow:?" end
        if ed.kind == "header" then return "bpHdr:" .. tostring(ed.ct) end
        return "bpItem:" .. tostring(ed.ct) .. ":" .. tostring(ed.name)
    end,
})

-- ===== Paste flow ============================================================
-- Structure check via the observer's sync wrapper (controllers never touch
-- C_HousingBlueprint); a structurally-valid code then goes through the normal
-- select+fetch path. pasteError drives the inline field state.

function C:_SubmitPaste(text)
    local code = HDG.Format.Trim(text)
    if code == "" then return end
    if not HDG.BlueprintObserver:IsShareCodeValid(code) then
        HDG.Store:Dispatch({ type = A.UI_SET_TRANSIENT,
            payload = { view = "blueprints", key = "pasteError", value = true } })
        return
    end
    HDG.Store:Dispatch({ type = A.UI_SET_TRANSIENT,
        payload = { view = "blueprints", key = "pasteError", value = false } })
    HDG.Store:Dispatch({ type = A.BLUEPRINT_PASTE_ADD, payload = {
        shareCode = code,
        blueprintType = HDG.BlueprintObserver:GetBlueprintTypeForCode(code),
    } })
    _selectAndFetch(code)
end

-- Target-house change (picker dispatch) -> re-fetch the selected code against
-- the new target. Named method so the seam is directly testable.
function C:_OnTargetChanged()
    local code = _selectedCode()
    if code then
        HDG.BlueprintObserver:RequestContents(code, _targetHouse())
    end
end

-- ===== Controller contract ===================================================

function C:Wire(root)
    -- WireAll runs once per WINDOW (main + lumber tracker + ...); only the
    -- window hosting the Blueprints view has our widgets.
    local pasteProbe = HDG.UI.W(root, "blueprintsListPanel.pasteBox")
    if not pasteProbe then return end  -- exception(nullable): this window doesn't host the Blueprints view
    self.root = root

    -- One collection request per session, not per re-mount.
    if not self._collectionRequested then
        self._collectionRequested = true
        HDG.BlueprintObserver:RequestCollection()
    end

    -- Paste: Enter in the box or the Inspect button.
    local pasteBox = HDG.UI.W(root, "blueprintsListPanel.pasteBox")
    pasteBox:SetScript("OnEnterPressed", function(box)
        C:_SubmitPaste(box:GetText())
        box:ClearFocus()
    end)
    HDG.UI.OnClick(root, "blueprintsListPanel.inspectBtn", function()
        C:_SubmitPaste(pasteBox:GetText())
    end)

    -- House-picker changes re-fetch the selection against the new target.
    if not self._targetSub then
        self._targetSub = true
        HDG.Store:Subscribe(function(_, invalidation)
            if HDG.Paths.MatchesAny({ "session.blueprints.targetHouseGUID" }, invalidation) then
                C:_OnTargetChanged()
            end
        end)
    end

    -- Missing-only segmented pair: explicit value set (not a flip), so both
    -- buttons stay truthful to state via their `active` bindings.
    HDG.UI.OnClick(root, "blueprintsDetailPanel.filterAll", function()
        HDG.Store:Dispatch({ type = A.UI_SET_TRANSIENT,
            payload = { view = "blueprints", key = "missingOnly", value = false } })
    end)
    HDG.UI.OnClick(root, "blueprintsDetailPanel.filterMissing", function()
        HDG.Store:Dispatch({ type = A.UI_SET_TRANSIENT,
            payload = { view = "blueprints", key = "missingOnly", value = true } })
    end)

    -- Name commit: Enter (or focus-out) labels the selected code. Shared codes
    -- arrive nameless; the label is the only persisted blueprint state.
    -- Focus-lost is the ONLY commit path (Enter just clears focus -- committing
    -- in OnEnterPressed double-fired via ClearFocus -> OnEditFocusLost), and it
    -- commits only USER-typed edits (_dirty), so Escape can genuinely cancel.
    -- HookScript, NOT SetScript: the editbox factory already hooked
    -- OnTextChanged/OnEditFocus* for the placeholder overlay + focus ring, and
    -- SetScript wiped that chain (PTR 2026-07-13: "Name this blueprint..."
    -- ghosting under real text). Enter already ClearFocus()es via the factory.
    local nameBox = HDG.UI.W(root, "blueprintsDetailPanel.nameBox")
    nameBox:HookScript("OnTextChanged", function(box, userInput)
        if userInput then box._dirty = true end
    end)
    nameBox:HookScript("OnEditFocusLost", function(box) C:_CommitName(box) end)
    nameBox:SetScript("OnEscapePressed", function(box)
        box._dirty = nil  -- discard the typed edit...
        local entry = HDG.Selectors:Call("blueprints.selectedEntry", HDG.Store:GetState(), {})  -- exception(false-positive): top-level controller read
        box:SetText((entry and (entry.isOwn and entry.name or entry.label)) or "")  -- ...and restore the shown name
        box:ClearFocus()
    end)

    -- Share-code box: read-only, click-to-select (the standard share-code
    -- pattern -- no clipboard API). Programmatic SetText happens in Refresh;
    -- user edits revert instantly.
    local codeBox = HDG.UI.W(root, "blueprintsDetailPanel.codeBox")
    codeBox:HookScript("OnEditFocusGained", function(box) box:HighlightText() end)  -- hook: keep the factory's focus ring
    codeBox:HookScript("OnTextChanged", function(box, userInput)
        if userInput then
            box:SetText(_selectedCode() or "")
            box:HighlightText()
        end
    end)

    -- Link in chat: insert the blueprint's chat hyperlink (players link builds
    -- like items). Blizzard's own LinkItem pattern -- insert if a chat editbox
    -- is active, else open one prefilled.
    HDG.UI.OnClick(root, "blueprintsDetailPanel.linkBtn", function() C:_LinkInChat() end)

    -- Import (pasted rows): open Blizzard's Import dialog prefilled with the
    -- code (its preview + confirm own the destructive apply).
    HDG.UI.OnClick(root, "blueprintsDetailPanel.importBtn", function()
        local code = _selectedCode()
        if code then HDG.BlueprintObserver:OpenImport(code) end
    end)

    -- Action row: the four seams.
    HDG.UI.OnClick(root, "blueprintsDetailPanel.routeBtn", function() C:_RouteMissingToShopping() end)
    HDG.UI.OnClick(root, "blueprintsDetailPanel.setBtn", function() C:_ImportAsSet() end)
    HDG.UI.OnClick(root, "blueprintsDetailPanel.architectBtn", function(btn) C:_OpenInArchitect(btn) end)
    HDG.UI.OnClick(root, "blueprintsListPanel.saveBtn", function(btn) C:_SaveBlueprint(btn) end)

    if not self._popupsRegistered then
        self._popupsRegistered = true
        HDG.UI:RegisterInputDialog("HDGR_BLUEPRINT_SAVE", {
            text       = "Name this blueprint:",
            accept     = "Save",
            maxLetters = 64,
            onAccept   = function(value, data)
                if not (value and value ~= "" and data and data.blueprintType) then return end
                HDG.BlueprintObserver:Export(data.blueprintType, value)
            end,
        })
    end
end

-- ===== Seams =================================================================

-- Missing decor+dye entries -> { {itemID, npcID=0, qty}, ... } + a skipped
-- count for catalog misses (no itemID = can't route; surfaces via Log).
function C:_BuildMissingItems()
    local insp = HDG.Selectors:Call("blueprints.inspector", HDG.Store:GetState(), {})  -- exception(false-positive): top-level controller read
    if not insp or insp.status ~= "received" then return nil end
    local items, skipped = {}, 0
    for _, g in ipairs(insp.groups) do
        if g.ct == 3 or g.ct == 4 then
            for _, it in ipairs(g.items) do
                if it.numMissing > 0 and it.itemID then
                    items[#items + 1] = { itemID = it.itemID, npcID = 0, qty = it.numMissing }
                elseif it.numMissing > 0 then
                    skipped = skipped + 1  -- no itemID: can't route
                end
            end
        end
    end
    return items, skipped
end

-- Route missing -> a NAMED shopping list via the SHOPPING_LIST_IMPORT upsert:
-- identity = "blueprint:<shareCode>" (meta.url), so re-routing the same
-- blueprint refreshes its list in place; name collisions auto-number.
function C:_RouteMissingToShopping()
    local items, skipped = self:_BuildMissingItems()
    if not items then return end
    local code = _selectedCode()
    local name = HDG.Selectors:Call("blueprints.displayName", HDG.Store:GetState(), {})  -- exception(false-positive): top-level controller read
    local encoded = HDG.ShoppingCodec.Encode({
        name = name, items = items,
        meta = { source = "blueprint", url = "blueprint:" .. code, desc = name },
    })
    HDG.Store:Dispatch({ type = A.SHOPPING_LIST_IMPORT, payload = { encoded = encoded } })
    if skipped > 0 then
        HDG.Log:Info("blueprints", skipped .. " item(s) not in the catalog yet were skipped")
    end
    HDG.Log:Info("blueprints", ("Shopping list %q updated: %d missing item(s)"):format(name, #items))
    -- Show the result: open the shopping widget on the routed list (design doc
    -- seams: "Widget switches to the list"; UX review #9). Toggle-only when closed.
    if HDG.Store:GetState().account.ui.shoppingWidgetShown ~= true then
        HDG.Store:Dispatch({ type = A.SHOPPING_WIDGET_TOGGLE })
    end
end

-- Import ALL decor (full quantities) as a furnishing set: encode an HDGRCRATE
-- code and land the player on the unified Import-a-Build view, parsed and
-- titled -- one Commit click away (the flow owns naming/dedupe).
function C:_ImportAsSet()
    local insp = HDG.Selectors:Call("blueprints.inspector", HDG.Store:GetState(), {})  -- exception(false-positive): top-level controller read
    if not insp or insp.status ~= "received" then return end
    local decor, skipped = {}, 0
    for _, g in ipairs(insp.groups) do
        if g.ct == 3 then
            for _, it in ipairs(g.items) do
                if it.itemID then
                    decor[#decor + 1] = { id = it.itemID, count = it.total }
                else
                    skipped = skipped + 1
                end
            end
        end
    end
    if #decor == 0 then
        HDG.Log:Warn("blueprints", "No catalog-resolvable decor in this blueprint yet")
        return
    end
    local name = HDG.Selectors:Call("blueprints.displayName", HDG.Store:GetState(), {})  -- exception(false-positive): top-level controller read
    local code = HDG.Projects.CrateCodec.Encode({ name = name, decor = decor })
    HDG.Store:Dispatch({ type = A.STYLES_IMPORT_RESET })
    HDG.Store:Dispatch({ type = A.STYLES_IMPORT_SET_DESTINATION, payload = { destination = "set" } })
    HDG.Store:Dispatch({ type = A.STYLES_IMPORT_SET_URL, payload = { text = code } })
    HDG.Store:Dispatch({ type = A.STYLES_IMPORT_PARSE })
    HDG.Store:Dispatch({ type = A.STYLES_IMPORT_SET_TITLE, payload = { text = name } })
    HDG.Store:Dispatch({ type = A.STYLES_SET_VIEW, payload = { view = "import" } })
    HDG.Store:Dispatch({ type = A.UI_SET_PERSISTENT, payload = { key = "view", value = "styles" } })
    if skipped > 0 then
        HDG.Log:Info("blueprints", skipped .. " uncatalogued item(s) left out of the set")
    end
end

-- Rooms from a received blueprint manifest -> a slot-src map for AutoLayout.
-- Shapes resolve from the RAW manifest (recordID lives on raw entries, not the
-- projected inspector rows). Returns the room map, room count, and the count of
-- unrecognized (unknown-shape) rooms.
local function _extractBlueprintRooms(m)
    local rooms, n, unknown = {}, 0, 0
    for _, g in ipairs(m.raw.contentGroups) do
        if g.contentType == 2 then
            for _, e in ipairs(g.entries) do
                local shape = HDG.Projects.ShapeAtlas.ShapeForRecordID(e.recordID)  -- exception(nullable): unknown room record
                if shape then
                    for _ = 1, e.total do
                        n = n + 1
                        rooms["slotsrc:" .. n] = { shape = shape, captureIndex = n }
                    end
                else
                    unknown = unknown + e.total
                end
            end
        end
    end
    return rooms, n, unknown
end

-- Slot-keyed placements from the auto-packed layout (floor 1; blueprints carry
-- no floor/position data -- AutoLayout arranges them).
local function _buildArchitectPlacements(rooms, packed)
    local placements, slotSeq = {}, 0
    for id, room in pairs(rooms) do
        local p = packed.layout[id]
        if p then
            slotSeq = slotSeq + 1
            placements["slot:" .. slotSeq] = {
                floor = 1, x = p.cell.x, y = p.cell.y,
                rotation = p.rotation or 0, shape = room.shape,
            }
        end
    end
    return placements, slotSeq
end

-- Rooms -> a new Architect layout: shapes via ShapeAtlas, positions via the
-- AutoLayout grid-pack ("arranged for you" -- share codes carry no positions).
function C:_OpenInArchitect(ownerBtn)
    local sb = HDG.Store:GetState().session.blueprints  -- exception(false-positive): top-level controller read
    local m = sb.selectedCode and sb.manifests[sb.selectedCode]
    if not (m and m.status == "received") then return end
    local rooms, n, unknown = _extractBlueprintRooms(m)
    if n == 0 then
        HDG.Log:Warn("blueprints", "No recognizable rooms in this blueprint")
        return
    end
    local packed = HDG.Projects.AutoLayout.compute({ rooms = rooms })
    local name = HDG.Selectors:Call("blueprints.displayName", HDG.Store:GetState(), {})  -- exception(false-positive): top-level controller read

    local function commitTo(houseID, houseName)
        local placements, slotSeq = _buildArchitectPlacements(rooms, packed)
        HDG.Store:Dispatch({ type = A.PROJECTS_IMPORT_LAYOUT, payload = {
            houseID = houseID, houseName = houseName,
            version = {
                houseID = houseID, name = name .. " (blueprint)",
                createdAt = HDG.ControllerHelpers.Mechanics.Now(),  -- exception(boundary): time()
                basedOn = nil, placements = placements, slotSeq = slotSeq, numFloors = 1,
            },
        } })
        HDG.Store:Dispatch({ type = A.UI_SET_PERSISTENT, payload = { key = "view", value = "projectsArchitect" } })
        if unknown > 0 then
            HDG.Log:Info("blueprints", unknown .. " room(s) with unknown shapes were left out")
        end
    end

    -- House targeting mirrors the Layouts importer: the only house, or a menu.
    if not HDG.ControllerHelpers.Mechanics.PromptHouseTarget(
            ownerBtn, "Open in Architect for which house?", commitTo) then
        HDG.Log:Warn("blueprints", "No Projects house yet -- visit a house first")
    end
end

-- Save the current location as a blueprint into Blizzard's catalog. This is
-- "Save Blueprint" (the House menu's own verb), NOT an export of what's
-- inspected. A type menu (House/Room/Interior/Exterior) -> a name prompt ->
-- ExportBlueprint(type, name); the fresh code is auto-selected on success and
-- a failure toasts Blizzard's reason (OnExportFailure). Availability is
-- location-based and single-valued, so all four are offered; the server
-- rejects the ones that don't fit where you stand.
function C:_SaveBlueprint(ownerBtn)
    local avail = HDG.BlueprintObserver:GetExportAvailability()
    if avail ~= Enum.HousingResult.Success then  -- exception(boundary): Blizzard enum
        local map = _G.HousingResultToErrorText  -- exception(boundary): Blizzard global map
        HDG.Log:Warn("blueprints", (map and map[avail]) or "Saving unavailable here -- be at your house first")  -- exception(boundary): not every value mapped
        return
    end
    local BT = Enum.HousingBlueprintType  -- exception(boundary): Blizzard enum
    local items = {
        { isTitle = true, text = "Save as..." },
        { text = "Full House", callback = function() _G.StaticPopup_Show("HDGR_BLUEPRINT_SAVE", nil, nil, { blueprintType = BT.House }) end },
        { text = "This Room",  callback = function() _G.StaticPopup_Show("HDGR_BLUEPRINT_SAVE", nil, nil, { blueprintType = BT.Room }) end },
        { text = "Interior",   callback = function() _G.StaticPopup_Show("HDGR_BLUEPRINT_SAVE", nil, nil, { blueprintType = BT.Interior }) end },
        { text = "Exterior",   callback = function() _G.StaticPopup_Show("HDGR_BLUEPRINT_SAVE", nil, nil, { blueprintType = BT.Exterior }) end },
    }
    HDG.UI.ShowMenu(ownerBtn, items)
end

-- Meter fill variants (state-driven paint; ProgressBarFill takes { variant, dim }).
local METER_VARIANT = {
    na   = { variant = "success", dim = true },
    fit  = { variant = "success" },
    full = { variant = "warning" },
    over = { variant = "error" },
}
local METER_BAR_IDS = {
    room     = "blueprintsDetailPanel.meterRoomBar",
    interior = "blueprintsDetailPanel.meterIntBar",
    exterior = "blueprintsDetailPanel.meterExtBar",
}

function C:Refresh(rootFrame, _ctx)
    -- RefreshAll runs once per WINDOW; skip windows that don't host the view.
    local codeBox = HDG.UI.W(rootFrame, "blueprintsDetailPanel.codeBox")
    if not codeBox then return end  -- exception(nullable): this window doesn't host the Blueprints view
    local nameBox = HDG.UI.W(rootFrame, "blueprintsDetailPanel.nameBox")

    -- Bindings render everything textual; the two imperative reconciles are the
    -- meter fill colors (state-driven skinner re-registration) and the
    -- programmatic share-code text (editboxes have no binding channel).
    local b = HDG.Selectors:Call("blueprints.budgetFit", HDG.Store:GetState(), {})  -- exception(false-positive): top-level controller read
    for _, m in ipairs(b.meters) do
        local bar = HDG.UI.W(rootFrame, METER_BAR_IDS[m.key])
        HDG.Theme:Register(bar._hdgrBarFill, "ProgressBarFill", METER_VARIANT[m.state])
    end
    -- Verdict badge text: green when it fits, red when blocked (the band's
    -- card chrome stays accent; only the text role tones -- UX review #14).
    local verdictFs = HDG.UI.W(rootFrame, "blueprintsDetailPanel.verdict")
    if verdictFs then  -- exception(nullable): windows without the Blueprints view
        HDG.Theme:Register(verdictFs, b.fits and "TextSuccess" or "TextError")
    end
    if not codeBox:HasFocus() then
        codeBox:SetText(_selectedCode() or "")
    end
    -- Name box shows the SELECTED entry's name (own -> Blizzard catalog name;
    -- pasted -> HDG label), per-row not last-typed. Never clobber mid-edit.
    if not nameBox:HasFocus() then
        local entry = HDG.Selectors:Call("blueprints.selectedEntry", HDG.Store:GetState(), {})  -- exception(false-positive): top-level controller read
        nameBox:SetText((entry and (entry.isOwn and entry.name or entry.label)) or "")
        -- Programmatic SetText: poke the placeholder overlay (OnTextChanged-
        -- via-SetText isn't guaranteed; same belt the binding dispatch wears).
        if nameBox._hdgrPlaceholderRefresh then nameBox._hdgrPlaceholderRefresh() end
    end
end

-- Delete an OWN manual blueprint from Blizzard's catalog, with a confirm. This
-- is a real catalog delete (never wired into Forget, which is HDG-list-only);
-- the row `x` only exposes it on own manual blueprints, never auto-backups.
function C:_ConfirmDelete(blueprintID, name)
    if not blueprintID then return end
    HDG.UI.Confirm({
        id       = "HDGR_BLUEPRINT_DELETE",
        text     = "Delete blueprint \"%s\" from your catalog? This can't be undone.",
        accept   = "Delete", cancel = "Cancel",
        textArg1 = name or "Blueprint", data = blueprintID,
        onAccept = function(_, bid)
            if bid then HDG.BlueprintObserver:Delete(bid) end
        end,
    })
end

-- Commit a USER-typed name for the selected code: own saved blueprint -> rename
-- in Blizzard's catalog; pasted code -> HDG display-label overlay. Runs on
-- focus-lost only, which fires BEFORE a new row's OnClick -- so clicking
-- another row still lands the commit on the code selected while typing. The
-- _dirty flag (stamped by OnTextChanged(userInput)) makes the commit both
-- once-only (review finding: Enter double-fired) and Escape-cancellable.
function C:_CommitName(box)
    if not box._dirty then return end
    box._dirty = nil
    local code = _selectedCode()
    if not code then return end
    local text = HDG.Format.Trim(box:GetText())
    if text == "" then return end
    local entry = HDG.Selectors:Call("blueprints.selectedEntry", HDG.Store:GetState(), {})  -- exception(false-positive): top-level controller read
    if entry and entry.isOwn then
        if entry.isAuto then
            -- Auto-backups are read-only: say so and revert instead of the old
            -- silent no-op-then-revert (UX review #3).
            if text ~= entry.name then
                HDG.Log:Warn("blueprints", "Auto-backups can't be renamed")
                box:SetText(entry.name or "")
            end
        elseif entry.blueprintID and text ~= entry.name then
            -- Own saved blueprint: rename in Blizzard's catalog.
            HDG.BlueprintObserver:Rename(entry.blueprintID, text)
        end
    elseif text ~= (entry and entry.label) then
        -- Pasted/shared code: HDG display label overlay.
        HDG.Store:Dispatch({ type = A.BLUEPRINT_SET_LABEL, payload = { shareCode = code, label = text } })
    end
end

-- Link in chat (mirrors ChatFrameUtil.LinkItem's active-editbox / open-chat split).
function C:_LinkInChat()
    local code = _selectedCode()
    if not code then return end
    local link = HDG.BlueprintObserver:GetHyperlink(code)
    if not link then return end  -- exception(nullable): hyperlink may be unavailable
    local CFU = _G.ChatFrameUtil
    if CFU and CFU.GetActiveWindow and CFU.GetActiveWindow() then  -- exception(boundary): Blizzard chat API
        CFU.InsertLink(link)
    elseif CFU and CFU.OpenChat then
        CFU.OpenChat(link)
    end
end

HDG.Controllers:Register("blueprints", C)
