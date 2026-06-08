-- HDG.MapRenderer
--
-- Renders a uiMap's art tiles into a host frame, scaled to fit. Pure-render module.
-- Canvas width/height = scaled map size; pin overlays go at (canvas_w * x, canvas_h * y).
-- Returns nil when uiMapID has no art (continent/world/cosmic) -> caller shows "no preview".
--
-- Public API:
--   HDG.MapRenderer:Render(host, uiMapID)  -> canvas, artMapID
--   HDG.MapRenderer:Clear(host)

HDG = HDG or {}
HDG.MapRenderer = HDG.MapRenderer or {}

local MR = HDG.MapRenderer

-- Walk parents until finding a uiMap with art. Cap at depth 5 to prevent broken-chain loops.
-- Instance maps (Dungeon/Orphan) don't fall through to continent on art miss
-- (boundary: mistyped mapID would silently render wrong zone; hard nil is correct here).
-- UiMapType: 0=Cosmic, 1=World, 2=Continent, 3=Zone, 4=Dungeon, 5=Orphan.
local INSTANCE_MAP_TYPES = { [4] = true, [5] = true }   -- Dungeon, Orphan
local function findArtableMap(uiMapID)
    local origInfo = C_Map.GetMapInfo(uiMapID)
    local origIsInstance = origInfo and INSTANCE_MAP_TYPES[origInfo.mapType] or false
    local walkID = uiMapID
    for depth = 0, 5 do
        local layers = C_Map.GetMapArtLayers(walkID)
        if layers and layers[1] and layers[1].layerWidth and layers[1].layerWidth > 0 then
            return walkID, layers[1]
        end
        -- Instance input + no art at the source: don't fall through to
        -- whatever continent the parent chain leads to.
        if origIsInstance and depth == 0 then return nil end
        local info = C_Map.GetMapInfo(walkID)
        if not info or not info.parentMapID or info.parentMapID == 0 then return nil end
        walkID = info.parentMapID
    end
    return nil
end

-- Texture pool: WoW textures can't be destroyed; reuse across renders.
-- _textureCount = high-water mark; textures beyond it are hidden until reused.
local function _acquireTexture(canvas, drawLayer, sublayer)
    canvas._textures     = canvas._textures     or {}
    canvas._textureCount = (canvas._textureCount or 0) + 1
    local tex = canvas._textures[canvas._textureCount]
    if tex then
        tex:SetDrawLayer(drawLayer, sublayer or 0)  -- exception(boundary): optional param
        tex:ClearAllPoints()
        tex:SetTexCoord(0, 1, 0, 1)
        tex:Show()
    else
        tex = canvas:CreateTexture(nil, drawLayer, nil, sublayer or 0)  -- exception(optional): sublayer param defaults to 0
        canvas._textures[canvas._textureCount] = tex
    end
    return tex
end

local function _resetTexturePool(canvas)
    if not canvas._textures then return end
    for _, tex in ipairs(canvas._textures) do
        tex:Hide()
        tex:SetTexture(nil)
    end
    canvas._textureCount = 0
end

function MR:Clear(host)
    if not host or not host._mapCanvas then return end
    local canvas = host._mapCanvas
    canvas:Hide()
    _resetTexturePool(canvas)
        -- canvas kept on host._mapCanvas for reuse; hiding it hides all pooled textures.
end

-- ===== Render primitives =====================================================

-- Resize/reuse the persistent canvas to fit the map layer (aspect-preserving).
-- Texture pool reset by caller before tiling.
local function _resolveCanvas(host, layer, hostW, hostH)
    local canvas = host._mapCanvas
    if not canvas then
        canvas = CreateFrame("Frame", nil, host)
        host._mapCanvas = canvas
    end
    local scale = math.min(hostW / layer.layerWidth, hostH / layer.layerHeight)
    _resetTexturePool(canvas)
    canvas:Show()
    canvas:SetSize(layer.layerWidth, layer.layerHeight)
    canvas:SetScale(scale)
    -- Centre the scaled map inside the host. SetPoint coords are in the
    -- canvas's own scale, so divide host dims by scale to get the offset
    -- that lands the canvas centre at the host centre.
    canvas:ClearAllPoints()
    canvas:SetPoint("TOPLEFT", host, "TOPLEFT",
         (hostW / scale - layer.layerWidth)  / 2,
        -(hostH / scale - layer.layerHeight) / 2)
    return canvas
end

-- Tile a textures array into a cols x rows grid. Used by both base + explored layers.
-- Right/bottom edge tiles clipped to residual size (texcoord crops proportionally).
local function _tileGrid(canvas, drawLayer, sublayer, params)
    local tileW, tileH = params.tileW, params.tileH
    local regW,  regH  = params.regionW, params.regionH
    local ofsX,  ofsY  = params.ofsX or 0, params.ofsY or 0
    local textures     = params.textures
    local cols = math.ceil(regW / tileW)
    local rows = math.ceil(regH / tileH)
    local idx = 1
    for r = 0, rows - 1 do
        for c = 0, cols - 1 do
            if idx > #textures then return end
            local tex = _acquireTexture(canvas, drawLayer, sublayer)
            tex:SetPoint("TOPLEFT", ofsX + c * tileW, -(ofsY + r * tileH))
            local w = math.min(tileW, regW - c * tileW)
            local h = math.min(tileH, regH - r * tileH)
            tex:SetSize(w, h)
            tex:SetTexture(textures[idx])
            if w < tileW or h < tileH then
                tex:SetTexCoord(0, w / tileW, 0, h / tileH)
            end
            idx = idx + 1
        end
    end
end

-- Tile explored overlays for a uiMap. Each info = one revealed region (multiple disjoint per zone).
-- Sparse fields coerced to 0; regW > 0 check skips empty regions.
local function _renderExploredOverlay(canvas, artMapID, tileW, tileH)
    if not (C_MapExplorationInfo and C_MapExplorationInfo.GetExploredMapTextures) then return end
    local explored = C_MapExplorationInfo.GetExploredMapTextures(artMapID)
    if not explored then return end
    for _, info in ipairs(explored) do
        local fileIDs = info.fileDataIDs
        local regW, regH = info.textureWidth or 0, info.textureHeight or 0  -- exception(boundary): Blizzard struct field sparse
        if fileIDs and regW > 0 and regH > 0 then
            _tileGrid(canvas, "ARTWORK", 1, {
                tileW    = tileW, tileH = tileH,
                regionW  = regW,  regionH = regH,
                ofsX     = info.offsetX or 0,  -- exception(boundary): Blizzard struct field sparse
                ofsY     = info.offsetY or 0,  -- exception(boundary): Blizzard struct field sparse
                textures = fileIDs,
            })
        end
    end
end

function MR:Render(host, uiMapID)
    if not host or not uiMapID then return nil end

    local artMapID, layer = findArtableMap(uiMapID)
    if not artMapID or not layer then return nil end

    local textures = C_Map.GetMapArtLayerTextures(artMapID, 1)
    if not textures or #textures == 0 then return nil end

    local hostW, hostH = host:GetWidth(), host:GetHeight()
    if hostW <= 0 or hostH <= 0 then return nil end

    local canvas = _resolveCanvas(host, layer, hostW, hostH)

    -- Tile size from the layer struct (typically 256x256). Used by both
    -- the base tile walk and each explored-region overlay.
    local tileW = layer.tileWidth  or 256  -- exception(boundary): Blizz struct
    local tileH = layer.tileHeight or 256  -- exception(boundary): map-layer tile size (Blizz struct)

    -- BASE tiles (full map, dim/fogged).
    _tileGrid(canvas, "ARTWORK", 0, {
        tileW    = tileW, tileH = tileH,
        regionW  = layer.layerWidth,
        regionH  = layer.layerHeight,
        textures = textures,
    })

    -- EXPLORED overlay (sublayer 1: bright for player-revealed regions).
    _renderExploredOverlay(canvas, artMapID, tileW, tileH)

    return canvas, artMapID
end
