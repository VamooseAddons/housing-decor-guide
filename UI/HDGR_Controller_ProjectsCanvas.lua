-- HDG.ProjectsCanvasController + the "projectsCanvas" WidgetType
-- ============================================================================
-- Architect blueprint canvas. Keyed-pool Render(host, model) driven by the
-- pure `projects.canvasModel` selector. Auto-fit tiling: tile = min(vpW/cols,
-- vpH/rows) clamped; re-derived from bbox each render, no zoom/pan.
-- Handlers wired ONCE at pool-init; mutations are dispatched (per ADR-039).

HDG = HDG or {}
HDG.ProjectsCanvasController = HDG.ProjectsCanvasController or {}
local C = HDG.ProjectsCanvasController

-- Per-CELL tile px. Cells are HALF-module (ShapeAtlas rebased x2), so clamps
-- are half what they'd be per-module -- a square_s (4x4 cells) lands ~the same size.
local MIN_TILE, MAX_TILE, GAP, ORB_PX = 15, 52, 6, 14

-- The active version's rooms map + its versionID (editor dispatches carry versionID).
-- nil version -> empty rooms + nil vid (the canvas is empty; nothing to act on).
local function _activeRooms(state)
    local vid     = HDG.Selectors:Call("projects.activeVersionID", state, {})
    local version = vid and state.account.projects.versions[vid]
    return (version and version.rooms) or {}, vid
end

-- ===== keyed mark/sweep pools ==============================================
local function _beginPass(host, pool)
    local p = host[pool]
    if p then for _, f in pairs(p) do f._used = false end end
end
local function _endPass(host, pool)
    local p = host[pool]
    if p then for _, f in pairs(p) do if not f._used then f:Hide() end end end
end
local function _acquire(host, pool, key, factory)
    host[pool] = host[pool] or {}
    local f = host[pool][key]
    if not f then f = factory(host); host[pool][key] = f end
    f._used = true
    return f
end

-- ===== frame factories (built once, reused) ================================
local function _tileFactory(host)
    local tile = CreateFrame("Button", nil, host, "BackdropTemplate")
    tile:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    local icon = tile:CreateTexture(nil, "ARTWORK")   -- shape art; CENTERED + sized per-render to the
    icon:SetPoint("CENTER", tile, "CENTER")            -- CANONICAL footprint so SetRotation maps a non-square
    icon:SetAlpha(0.9)                                 -- shape (hallway) into the rotated frame without stretch
    tile._icon = icon
    local label = tile:CreateFontString(nil, "OVERLAY")
    HDG.UI.applyFontRole(label, "caption")
    label:SetPoint("CENTER")
    label:SetJustifyH("CENTER")
    label:SetWordWrap(true)   -- wraps within the tile width (set per-render) -> never overflows onto neighbours
    tile._label = label
    tile:SetScript("OnClick", function(self, button)
        if button == "RightButton" then
            C:_OnRoomMenu(self)   -- E6: move/rotate/remove (every room in the active version is editable)
            return
        end
        HDG.Store:Dispatch({
            type = HDG.Constants.ACTIONS.UI_SET_TRANSIENT,
            payload = { view = "projects", key = "selectedRoomID", value = self._roomID },
        })
    end)
    -- E4-drag: reposition via StartMoving -> snap to cell on stop.
    -- Every room is repositionable. Overlaps allowed on drop (E5 flags them).
    tile:SetMovable(true)
    tile:RegisterForDrag("LeftButton")
    tile:SetScript("OnDragStart", function(self)
        self:StartMoving()
        C:_HideOrbs(self:GetParent())   -- orbs are host-anchored -> hide them so they don't sit at the pre-drag edges
    end)
    tile:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        C:_DropRoom(self)   -- the drop re-renders -> orbs reappear at the new positions
    end)
    -- Tooltip via the TooltipEngine (dynamic def reads live fields at hover);
    -- Attach HookScripts OnEnter/OnLeave + guards against pool re-attach.
    HDG.TooltipEngine:Attach(tile, function(self)
        if not self._tipName then return nil end
        return { title = self._tipName, extraLines = self._tipSub and { self._tipSub } or nil }
    end)
    return tile
end

local function _orbFactory(host)
    -- Non-interactive: connection is by PLACEMENT now (no click-to-connect). Just a dot
    -- with a hover tooltip. EnableMouse for the tooltip, but no OnClick.
    local orb = CreateFrame("Frame", nil, host)
    orb:EnableMouse(true)
    HDG.TooltipEngine:Attach(orb, function(self) return C:_OrbTooltipDef(self) end)
    return orb
end

local function _backdropFactory(host)
    local bd = CreateFrame("Frame", nil, host, "BackdropTemplate")
    HDG.Theme:Register(bd, "Raised")
    bd:SetAlpha(0.22)   -- dimmed: the floor below, seen through the current floor
    return bd
end

-- Cell-grid line: a 1px black texture at BACKGROUND, so the grid sits behind the
-- backdrop + room tiles (a host's child FRAMES always draw above its child textures).
local GRID_ALPHA = 0.28
local function _gridLineFactory(host)
    local ln = host:CreateTexture(nil, "BACKGROUND")
    ln:SetColorTexture(0, 0, 0, GRID_ALPHA)
    return ln
end

-- ===== status -> a short sub-label for the room tooltip ====================
local STATUS_SUB = {
    ["in-progress"] = "Crate attached",
    unconfigured    = "No crate yet",
}

-- ===== render ==============================================================
-- Map a cell (x,y) to the host's TOPLEFT-relative pixel origin of that cell.
-- Returns px (>=0, rightward) and py (<=0, downward) per WoW's TOPLEFT anchor.
local function _cellToPx(bbox, tile, ox, oy, x, y)
    return ox + (x - bbox.minX) * tile, -(oy + (y - bbox.minY) * tile)
end

-- Paint a room tile's shape art: the shape's atlas icon (the blueprint shapes from
-- the layout catalog), rotated to the room's orientation. Rotation is cosmetic --
-- SetRotation spins the atlas quad in place. nil atlas hides the icon.
-- Lazy circle mask (CircleMaskScalable): clips the garden's SQUARE photo atlas
-- to a clean disc, trimming the grey corners.
local function _ensureCircleMask(tile)
    local m = tile._circleMask
    if not m then
        m = tile:CreateMaskTexture()
        m:SetAtlas("CircleMaskScalable")
        tile._circleMask = m
    end
    return m
end

local function _paintTileIcon(tile, atlas, rotation, iconW, iconH, isCircle)
    local icon = tile._icon
    if atlas then
        icon:SetSize(iconW, iconH)   -- canonical (unrotated) footprint px; SetRotation maps it into the frame
        icon:SetAtlas(atlas, false)
        icon:SetRotation((rotation or 0) * (math.pi / 2))
        if isCircle then
            local m = _ensureCircleMask(tile)
            m:ClearAllPoints(); m:SetAllPoints(icon)        -- match the just-sized icon
            if not tile._circleMasked then icon:AddMaskTexture(m); tile._circleMasked = true end
        elseif tile._circleMasked then                       -- pooled tile reused for a non-circle room
            icon:RemoveMaskTexture(tile._circleMask)
            tile._circleMasked = false
        end
        icon:Show()
    else
        icon:Hide()
    end
end

-- ============================================================================
-- Line-drawn room OUTLINES -- crisp at any zoom (atlases re-sample soft),
-- theme-colored, outline-only. Geometry derives from ShapeAtlas: rectilinear
-- shapes (entry/square/closet/hall/L/T/cross) trace their occupied-cell mask;
-- octagons use explicit cut-corner vertices; gardens (circle) keep their photo
-- atlas (no geometric outline, masked to a disc).
-- ============================================================================
local ROOM_LINE_PX = 2   -- outline thickness, PHYSICAL pixels (crisp at sub-1.0 scale)
local ROOM_INSET   = 2   -- logical px kept clear of the tile border

-- Room outline color now lives in the Theme `RoomOutline` skinner: selected ->
-- semantic.accent, the rest -> border.default. Crate status is NOT colored here
-- -- it reads in the detail panel, so the canvas stays calm and selection pops.

-- A near-regular octagon inscribed in the w x d cell box (corner cut = 1-1/sqrt2).
-- Octagons are square + symmetric, so rotation leaves the outline unchanged.
local function _octagonOutline(w, d)
    local cx, cy = w * 0.293, d * 0.293
    return { {cx,0}, {w-cx,0}, {w,cy}, {w,d-cy}, {w-cx,d}, {cx,d}, {0,d-cy}, {0,cy} }
end

-- Trace the outline of a set of occupied unit cells into an ordered, simplified
-- vertex loop in CORNER coords (0..w / 0..d). Single connected region, no holes
-- (true for every room mask). Each cell emits its 4 boundary edges as directed CW
-- segments (interior always on the right) so they chain head->tail into one loop.
local function _traceMaskOutline(mask)
    local occ = {}
    for _, c in ipairs(mask) do occ[c[1] .. ":" .. c[2]] = true end
    local function isOcc(x, y) return occ[x .. ":" .. y] == true end
    local nextC = {}
    for _, c in ipairs(mask) do
        local x, y = c[1], c[2]
        if not isOcc(x, y - 1) then nextC[x .. ":" .. y]             = { x + 1, y } end       -- top    -> right
        if not isOcc(x + 1, y) then nextC[(x + 1) .. ":" .. y]       = { x + 1, y + 1 } end   -- right  -> down
        if not isOcc(x, y + 1) then nextC[(x + 1) .. ":" .. (y + 1)] = { x, y + 1 } end       -- bottom -> left
        if not isOcc(x - 1, y) then nextC[x .. ":" .. (y + 1)]       = { x, y } end           -- left   -> up
    end
    local startK = next(nextC)
    if not startK then return nil end
    local sx, sy = startK:match("^(%-?%d+):(%-?%d+)$")
    sx, sy = tonumber(sx), tonumber(sy)
    local loop, cx, cy, guard = { { sx, sy } }, sx, sy, 0
    while true do
        local nx = nextC[cx .. ":" .. cy]
        if not nx then break end
        cx, cy = nx[1], nx[2]
        if cx == sx and cy == sy then break end
        loop[#loop + 1] = { cx, cy }
        guard = guard + 1
        if guard > 4000 then break end   -- exception(boundary): malformed-mask guard
    end
    -- Drop colinear midpoints (keep only direction changes).
    local out, n = {}, #loop
    for i = 1, n do
        local a, b, cc = loop[(i - 2) % n + 1], loop[i], loop[i % n + 1]
        local cross = (b[1] - a[1]) * (cc[2] - b[2]) - (b[2] - a[2]) * (cc[1] - b[1])
        if cross ~= 0 then out[#out + 1] = b end
    end
    return out
end

-- shapeID + rotated footprint -> outline vertex loop (corner coords 0..w/0..d),
-- or nil to fall back to the atlas (gardens / unknown).
local function _shapeOutline(shapeID, rw, rd, rotation)
    local A = HDG.Projects.ShapeAtlas
    if A.IsCircle(shapeID) then return nil end
    if shapeID and shapeID:find("^octagon") then return _octagonOutline(rw, rd) end
    local cells = A.GetCells(shapeID)
    local mask  = A.RotateMask(A.GetMask(shapeID), rotation or 0, cells[1], cells[2])
    return _traceMaskOutline(mask)
end

-- Center (cell coords) + width of the shape's WIDEST horizontal band -- the bar/foot
-- -- so the label sits in the meat of the room, not the empty notch the bbox center
-- lands in on T/L. Rect shapes reduce to the bbox center (full-width band).
local function _labelAnchor(shapeID, rw, rd, rotation)
    local A = HDG.Projects.ShapeAtlas
    local cells = A.GetCells(shapeID)
    local mask  = A.RotateMask(A.GetMask(shapeID), rotation or 0, cells[1], cells[2])
    local rowMin, rowMax = {}, {}
    for _, c in ipairs(mask) do
        local x, y = c[1], c[2]
        rowMin[y] = (rowMin[y] == nil) and x or math.min(rowMin[y], x)
        rowMax[y] = (rowMax[y] == nil) and x or math.max(rowMax[y], x)
    end
    local bestW, ys = 0, {}
    for y = 0, rd - 1 do
        if rowMin[y] ~= nil then
            local w = rowMax[y] - rowMin[y] + 1
            if w > bestW then bestW, ys = w, { y }
            elseif w == bestW then ys[#ys + 1] = y end
        end
    end
    local y0 = ys[1]
    return (rowMin[y0] + rowMax[y0] + 1) / 2, (ys[1] + ys[#ys] + 1) / 2, bestW
end

local function _hideOutlines(tile)
    if tile._outlines then for _, ln in ipairs(tile._outlines) do ln:Hide() end end
end

-- Draw the outline loop as pooled, pixel-snapped lines spanning the tile (minus
-- ROOM_INSET so they sit just inside the border). Hides the atlas icon.
local function _paintTileOutline(tile, verts, rw, rd, selected)
    tile._icon:Hide()
    tile._outlines = tile._outlines or {}
    local pool = tile._outlines
    local tw, th = tile:GetWidth(), tile:GetHeight()
    local scale  = tile:GetEffectiveScale()
    if not scale or scale <= 0 then scale = 1 end
    local innerW, innerH = math.max(1, tw - 2 * ROOM_INSET), math.max(1, th - 2 * ROOM_INSET)
    local function sx(x) return math.floor((ROOM_INSET + x / rw * innerW) * scale + 0.5) / scale end
    local function sy(y) return math.floor((ROOM_INSET + y / rd * innerH) * scale + 0.5) / scale end
    local thick, n = ROOM_LINE_PX / scale, #verts
    for i = 1, n do
        local a, b = verts[i], verts[i % n + 1]
        local ln = pool[i]
        if not ln then ln = tile:CreateLine(nil, "ARTWORK"); pool[i] = ln end
        ln:SetThickness(thick)
        HDG.Theme:Register(ln, "RoomOutline", { selected = selected })
        ln:ClearAllPoints()
        ln:SetStartPoint("TOPLEFT", tile, sx(a[1]), -sy(a[2]))
        ln:SetEndPoint("TOPLEFT",   tile, sx(b[1]), -sy(b[2]))
        ln:Show()
    end
    for i = n + 1, #pool do pool[i]:Hide() end
end

function C:Render(host, model)
    host._lastModel = model   -- OnSizeChanged re-renders from this
    C._activeHost   = host     -- /hdgr doors reads this._lastModel for the door audit
    if not model or model.empty then
        if host._emptyLabel then host._emptyLabel:Show() end
        _beginPass(host, "_gridPool");     _endPass(host, "_gridPool")
        _beginPass(host, "_backdropPool"); _endPass(host, "_backdropPool")
        _beginPass(host, "_tilePool");     _endPass(host, "_tilePool")
        _beginPass(host, "_orbPool");      _endPass(host, "_orbPool")
        return
    end
    if host._emptyLabel then host._emptyLabel:Hide() end

    local vw, vh = host:GetWidth(), host:GetHeight()
    if not vw or not vh or vw <= 1 or vh <= 1 then return end  -- exception(boundary): geometry not settled; OnSizeChanged re-fires

    local bbox = model.bbox
    local tile = math.min(vw / bbox.cols, vh / bbox.rows)
    if tile < MIN_TILE then tile = MIN_TILE end
    if tile > MAX_TILE then tile = MAX_TILE end
    local ox = (vw - bbox.cols * tile) / 2
    local oy = (vh - bbox.rows * tile) / 2
    host._renderCtx = { bbox = bbox, tile = tile, ox = ox, oy = oy }   -- E4-drag: cell<->px reverse on drop

    -- Cell grid: 1px lines at every cell division. BACKGROUND layer.
    -- PHYSICAL-pixel snap: sub-1.0 scale means logical px < 1 physical px ->
    -- lines vanish or alpha-split. Snap offset to floor(v*scale+0.5)/scale;
    -- thickness = 1/scale (exactly 1 physical px).
    _beginPass(host, "_gridPool")
    do
        local scale = host:GetEffectiveScale()
        if not scale or scale <= 0 then scale = 1 end   -- exception(boundary): geometry not settled
        local function _snap(v) return math.floor(v * scale + 0.5) / scale end
        local pxW = 1 / scale                            -- exactly one physical pixel
        local gx, gi = ox % tile, 0
        while gx <= vw do
            local ln = _acquire(host, "_gridPool", "v" .. gi, _gridLineFactory)
            ln:ClearAllPoints(); ln:SetPoint("TOPLEFT", host, "TOPLEFT", _snap(gx), 0); ln:SetSize(pxW, vh); ln:Show()
            gx, gi = gx + tile, gi + 1
        end
        local gy, gj = oy % tile, 0
        while gy <= vh do
            local ln = _acquire(host, "_gridPool", "h" .. gj, _gridLineFactory)
            ln:ClearAllPoints(); ln:SetPoint("TOPLEFT", host, "TOPLEFT", 0, -_snap(gy)); ln:SetSize(vw, pxW); ln:Show()
            gy, gj = gy + tile, gj + 1
        end
    end
    _endPass(host, "_gridPool")

    -- backdrop (lower floor), dimmed, behind the rooms
    _beginPass(host, "_backdropPool")
    for i, b in ipairs(model.backdrop) do
        local bd = _acquire(host, "_backdropPool", i, _backdropFactory)
        local px, py = _cellToPx(bbox, tile, ox, oy, b.x, b.y)
        bd:ClearAllPoints()
        bd:SetPoint("TOPLEFT", host, "TOPLEFT", px + GAP / 2, py - GAP / 2)
        bd:SetSize((b.w or 1) * tile - GAP, (b.d or 1) * tile - GAP)
        bd:Show()
    end
    _endPass(host, "_backdropPool")

    -- Rooms at TRUE footprint (w x d cells), textured + rotated per shape.
    _beginPass(host, "_tilePool")
    for _, r in ipairs(model.rooms) do
        local t = _acquire(host, "_tilePool", r.roomID, _tileFactory)
        local px, py = _cellToPx(bbox, tile, ox, oy, r.x, r.y)
        local tw, th = r.w * tile - GAP, r.d * tile - GAP   -- footprint size (half-module grid -> closet/entry are 2x1)
        t:ClearAllPoints()
        t:SetPoint("TOPLEFT", host, "TOPLEFT", px + GAP / 2, py - GAP / 2)
        t:SetSize(tw, th)
        t:SetAlpha(r.projected and 0.4 or 1)     -- projected garden ghosts: dimmed...
        t:EnableMouse(not r.projected)           -- ...and non-interactive (no drag/menu)
        t._label:SetWidth(math.max(8, tw + 4))   -- allow ~4px overflow so short names + chest stay one line
        t._roomID = r.roomID
        local label = r.name or HDG.Projects.ShapeAtlas.GetLabel(r.shape)
        t._tipName, t._tipSub = label, STATUS_SUB[r.status]
        -- crate-attached indicator: an INLINE chest after the name -- it centers + wraps
        -- WITH the text, so it never gets pushed outside small rooms. Hidden when no crate.
        if r.status ~= "unconfigured" then label = label .. " |A:house-chest-icon:12:12|a" end
        t._label:SetText(label)
        -- Geometric shapes use a line outline; circles fall back to masked photo atlas.
        -- Icon sized to canonical (unrotated) footprint so rotation doesn't stretch.
        local verts = _shapeOutline(r.shape, r.w, r.d, r.rotation)
        if verts then
            _paintTileOutline(t, verts, r.w, r.d, r.isSelected)
            -- label centers in the WIDEST horizontal band (bar/foot), not the bbox notch.
            local lcx, lcy, lbw = _labelAnchor(r.shape, r.w, r.d, r.rotation)
            t._label:ClearAllPoints()
            t._label:SetPoint("CENTER", t, "TOPLEFT", lcx / r.w * tw, -(lcy / r.d * th))
            t._label:SetWidth(math.max(8, lbw / r.w * tw + 4))
        else
            _hideOutlines(t)
            _paintTileIcon(t, r.atlas, r.rotation, (r.canonW or r.w) * tile - 4, (r.canonD or r.d) * tile - 4,
                HDG.Projects.ShapeAtlas.IsCircle(r.shape))
            t._label:ClearAllPoints()
            t._label:SetPoint("CENTER", t, "CENTER")
        end
        -- No footprint pad: outline IS the room. Selection via outline color;
        -- crate status via the inline chest glyph in the label.
        t:SetBackdrop(nil)
        t:Show()
    end
    _endPass(host, "_tilePool")

    -- door orbs at the exact edge midpoint (centered on the side). Glowing when CONNECTED
    -- by placement (another room's door meets it here), plain when it's an open doorway.
    _beginPass(host, "_orbPool")
    for _, o in ipairs(model.orbs) do
        local orb = _acquire(host, "_orbPool", o.roomID .. ":" .. o.cardinal, _orbFactory)
        local px, py = _cellToPx(bbox, tile, ox, oy, o.midX, o.midY)
        orb:ClearAllPoints()
        orb:SetPoint("CENTER", host, "TOPLEFT", px, py)
        orb:SetSize(ORB_PX, ORB_PX)
        orb._cardinal, orb._connected = o.cardinal, o.connected
        HDG.Theme:Register(orb, "ProjectsOrb", { connected = o.connected })
        orb:Show()
    end
    _endPass(host, "_orbPool")
end

-- ===== Door orb tooltip (hover only; orbs are non-interactive) ==============
-- Connection is by PLACEMENT (the canvasModel selector pairs opposite doors at the same
-- edge midpoint) -- no click-to-connect. The tooltip just reads the door's state.
function C:_OrbTooltipDef(orb)
    return {
        title = "Doorway -- " .. orb._cardinal,
        extraLines = { orb._connected
            and "Connected -- a room's door meets it here"
            or  "Open -- align another room's door to connect" },
    }
end

-- ===== E6: room edit menu (move / rotate / remove) =========================
-- Overlaps allowed (E5 flags them). Every room in the active version is editable.
function C:_OnRoomMenu(tile)
    local roomID = tile._roomID
    if not roomID then return end
    local rooms, vid = _activeRooms(HDG.Store:GetState())  -- exception(false-positive): top-level controller method, not a row factory
    local room = rooms[roomID]
    if not (room and vid) then return end   -- exception(boundary): tile points at a since-removed room
    local A = HDG.Constants.ACTIONS
    -- Deltas: reducer applies dx/dy/drotation in place (PROJECTS_MOVE_ROOM).
    local function move(dx, dy, drot)
        -- Block a directional move that would overlap (rotate stays in place -> allowed).
        if (dx ~= 0 or dy ~= 0)
           and not HDG.Projects.FloorMap.CanMoveTo(rooms, roomID, room.cell.x + dx, room.cell.y + dy) then
            return
        end
        HDG.Store:Dispatch({ type = A.PROJECTS_MOVE_ROOM,
            payload = { versionID = vid, roomID = roomID, dx = dx, dy = dy, drotation = drot } })
    end
    local items = {
        { text = "Move up",    callback = function() move(0, -1, 0) end },
        { text = "Move down",  callback = function() move(0,  1, 0) end },
        { text = "Move left",  callback = function() move(-1, 0, 0) end },
        { text = "Move right", callback = function() move(1,  0, 0) end },
        { text = "Rotate",     callback = function() move(0,  0, 1) end },
    }
    -- Stairwells grow up a floor (in-game "Expand Stairwell up"), capped at floor 3.
    -- Single record -> the top floor is base + span - 1 (span = floors override or shape default).
    if room.shape == "staircase" or room.shape == "staircase_mirror" then
        local p    = HDG.Projects.IDs.parsePath(roomID)
        local span = room.floors or HDG.Projects.ShapeAtlas.GetFloors(room.shape)
        local top  = (p and p.floor or 1) + span - 1
        if top < 3 then
            items[#items + 1] = { text = "Expand Stairwell up",
                callback = function() HDG.ProjectsController:ExpandStackUp(roomID) end }
        end
    end
    -- The Entry is the anchor room: there must always be exactly one, so it is undeletable.
    if room.shape ~= "entry" then
        items[#items + 1] = { text = "Remove", callback = function()
            HDG.Store:Dispatch({ type = A.PROJECTS_DELETE_ROOM, payload = { versionID = vid, roomID = roomID } })
        end }
    end
    HDG.UI.ShowMenu(tile, items)
end

-- Hide all door orbs (host-anchored, so they don't follow a dragging tile). Re-shown by
-- the next render -- the drop dispatch repositions them at the new cell.
function C:_HideOrbs(host)
    if host and host._orbPool then
        for _, orb in pairs(host._orbPool) do orb:Hide() end
    end
end

-- E4-drag: snap dropped tile to nearest cell + persist. locked=true marks
-- it user-positioned. Overlaps allowed (E5 flags them).
function C:_DropRoom(tile)
    local host   = tile:GetParent()
    local ctx    = host and host._renderCtx
    local roomID = tile._roomID
    if not (roomID and ctx and tile:GetLeft() and host:GetLeft()) then
        if host and host._lastModel then C:Render(host, host._lastModel) end   -- no snap -> re-render to restore orbs
        return
    end
    local rooms, vid = _activeRooms(HDG.Store:GetState())  -- exception(false-positive): top-level controller method, not a row factory
    if not vid then return end
    local relLeft = tile:GetLeft() - host:GetLeft()
    local relTop  = host:GetTop()  - tile:GetTop()
    local cellX = math.floor((relLeft - GAP / 2 - ctx.ox) / ctx.tile + 0.5) + ctx.bbox.minX
    local cellY = math.floor((relTop  - GAP / 2 - ctx.oy) / ctx.tile + 0.5) + ctx.bbox.minY
    -- Collision: snap back (re-render from state) if the drop would overlap another
    -- room on any floor it occupies -- including the cells above a garden.
    if not HDG.Projects.FloorMap.CanMoveTo(rooms, roomID, cellX, cellY) then
        if host._lastModel then C:Render(host, host._lastModel) end
        return
    end
    -- Absolute snap; reducer preserves rotation. locked=true marks user-positioned.
    HDG.Store:Dispatch({ type = HDG.Constants.ACTIONS.PROJECTS_MOVE_ROOM,
        payload = { versionID = vid, roomID = roomID, x = cellX, y = cellY, locked = true } })
end

-- ===== widget-kind: thin host frame =========================================
local function buildProjectsCanvas(parent, _spec)
    local host = CreateFrame("Frame", nil, parent)
    local empty = host:CreateFontString(nil, "OVERLAY", "GameFontDisableLarge")
    empty:SetPoint("CENTER")
    empty:SetText("No rooms on this floor yet")
    host._emptyLabel = empty
    host:SetScript("OnSizeChanged", function(self)
        if self._lastModel then C:Render(self, self._lastModel) end   -- re-tile on resize / late geometry
    end)
    -- Click empty canvas -> deselect room (room Buttons consume their own clicks;
    -- this fires only on the background).
    host:EnableMouse(true)
    host:SetScript("OnMouseDown", function()
        if HDG.Store:GetState().session.ui.projects.selectedRoomID then  -- exception(false-positive): top-level controller read
            HDG.Store:Dispatch({
                type    = HDG.Constants.ACTIONS.UI_SET_TRANSIENT,
                payload = { view = "projects", key = "selectedRoomID", value = nil },
            })
        end
    end)
    return host
end

HDG.WidgetTypes:Register("projectsCanvas", {
    build        = buildProjectsCanvas,
    dispatch     = { fields = { "model" }, push = function(widget, values) C:Render(widget, values and values.model) end },
    requiresFont = function() return false end,
    specFields   = {},   -- model flows via binding; no kind-specific spec fields
})

-- /hdgr doors: door audit for the open Architect canvas. Reads the ACTUAL rendered
-- orbs (m.orbs) -- gardens + stairwells FLOAT their single door to the nearest
-- neighbour, so re-deriving from GetDoors+rotation (the old audit) misreports them.
-- Prints, per room, each orb's cardinal@midpoint and whether it's connected. Dev tool.
function C:DoorAudit()
    local m = C._activeHost and C._activeHost._lastModel  -- exception(nullable): C._activeHost is nil when architect canvas is not open
    if not (m and m.rooms) then print("HDG doors: open the Architect first."); return end
    local byRoom = {}
    for _, o in ipairs(m.orbs) do
        byRoom[o.roomID] = byRoom[o.roomID] or {}
        local b = byRoom[o.roomID]
        b[#b + 1] = string.format("%s@%d,%d%s", o.cardinal, o.midX, o.midY, o.connected and "*" or "")
    end
    print("|cff66ccffHDGR door audit|r  cell(x,y,w,d) | orbs cardinal@midX,midY (* = connected; N=top S=bot E=right W=left):")
    for _, r in ipairs(m.rooms) do
        local b = byRoom[r.roomID] or {}
        print(string.format("  %s rot=%d  cell(%d,%d,%d,%d)  [%s]",
            r.name or r.shape, r.rotation or 0, r.x, r.y, r.w, r.d, table.concat(b, "  ")))
    end
end
