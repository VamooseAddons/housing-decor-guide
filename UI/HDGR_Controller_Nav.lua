-- HDG.NavController
-- ============================================================================
-- Sidebar nav (per ADR-025). treeList bound to nav.tree; click payload dispatches:
--   view -> setView | action -> setView + Dispatch | transient -> setView + SetUITransientView
--   launcher -> Dispatch only

HDG = HDG or {}
HDG.NavController = HDG.NavController or {}

local NavController = HDG.NavController

local function setView(view)
    HDG.Store:Dispatch({
        type    = HDG.Constants.ACTIONS.UI_SET_PERSISTENT,
        payload = { key = "view", value = view },
    })
end

-- Dispatch a node's click payload. Returns nothing; safe to call from OnClick.
local function dispatchClick(click)
    if not click then return end
    local k = click.kind
    if k == "view" then
        setView(click.view)
    elseif k == "action" then
        setView(click.view)
        HDG.Store:Dispatch({ type = HDG.Constants.ACTIONS[click.action], payload = click.payload })
    elseif k == "transient" then
        setView(click.view)
        local t = click.transient
        HDG.ControllerHelpers.Mechanics.SetUITransientView(t.view, t.key, t.value)
    elseif k == "launcher" then
        HDG.Store:Dispatch({ type = HDG.Constants.ACTIONS[click.action] })
    end
end

-- Exposed for the controller-wire smoke test.
NavController._dispatchClick = dispatchClick

-- Paint nav icon from file path or atlas. GetAtlasInfo-guards bad names (hide, no error). nil -> hide.
local function _paintNavAtlas(tex, ic)
    if not tex then return end
    if ic and ic:find("[/\\]") then
        tex:SetTexture(ic); tex:Show()
    -- exception(boundary): C_Texture is a Blizzard global (absent in headless tests); when present,
    -- GetAtlasInfo validates the atlas so a bad name hides the icon instead of erroring.
    elseif ic and (not (C_Texture and C_Texture.GetAtlasInfo) or C_Texture.GetAtlasInfo(ic) ~= nil) then
        tex:SetAtlas(ic); tex:Show()
    else
        tex:Hide()
    end
end

-- Tooltip for the group-icon collapse toggle. Reads per-init stamps on the icon
-- button (stable module-level def + stamps -> safe with idempotent TooltipEngine:Attach).
local function _navIconTipDef(self_)
    if not self_._hubView then return nil end
    return { title = (self_._navTipCollapsed and "Expand " or "Collapse ")
                     .. (self_._navTipLabel or "group") }
end

-- ===== Cell kind: navNode =====================================================
-- One cell kind for the whole nav. Single FontString (shared via SetText) avoids
-- cross-kind pool recycling that caused the double-text overlay.
HDG.TreeList:RegisterCellKind("navNode", {
        template = "Button",
        initializer = function(frame, node)
            local data = node:GetData()
            if not frame._navLaidOut and frame.CreateFontString then
                HDG.UI:EnsureRowChrome(frame)
                local icon = frame:CreateTexture(nil, "ARTWORK", nil, 2)
                icon:SetSize(15, 15)
                icon:SetPoint("LEFT", frame, "LEFT", 7, 0)
                icon:Hide()
                frame._navIcon = icon
                -- Clickable collapse toggle over the group icon (shown on hub rows
                -- only). 17px hit-area at the icon; the row's own OnClick (label /
                -- body) still navigates -- the child button captures only its region.
                local iconBtn = CreateFrame("Button", nil, frame)
                iconBtn:SetSize(17, 17)
                iconBtn:SetPoint("LEFT", frame, "LEFT", 6, 0)
                iconBtn:RegisterForClicks("LeftButtonUp")
                iconBtn:SetScript("OnClick", function(self_)
                    if not self_._hubView then return end
                    HDG.Store:Dispatch({
                        type    = HDG.Constants.ACTIONS.NAV_TOGGLE_GROUP,
                        payload = { view = self_._hubView },
                    })
                end)
                iconBtn:Hide()
                HDG.TooltipEngine:Attach(iconBtn, _navIconTipDef)
                frame._navIconBtn = iconBtn
                -- Indent guide: 1px line; flush rows stack into a continuous connector.
                local guide = frame:CreateTexture(nil, "ARTWORK", nil, 1)
                guide:SetTexture("Interface\\Buttons\\WHITE8x8")
                guide:SetWidth(1)
                guide:SetPoint("TOPLEFT",    frame, "TOPLEFT",    22, 0)
                guide:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 22, 0)
                guide:Hide()
                frame._navGuide = guide
                local label = frame:CreateFontString(nil, "OVERLAY")
                label:SetJustifyH("LEFT")
                label:SetWordWrap(false)   -- fixed-height rows never reflow (scroll-gutter reclaim caused 2-line wrap)
                frame._navLabelFs = label
                frame._navLaidOut = true
            end

            -- Tier-based font/role: heading (home/hub/parent/config/launcher), body (leaf), caption (header).
            -- Re-applied each init; a pooled frame may flip tier across recycles.
            local tier = data.tier or (data.isHeader and "header")
                or (data.isHome and "home") or "leaf"
            local isHeader = (tier == "header")
            local fontRole, textRole
            if isHeader then
                fontRole, textRole = "caption", "TextDim"
            elseif tier == "leaf" then
                fontRole = "body"
                textRole = data.active and "Text" or "TextMuted"
            else  -- home / hub / parent / config / launcher
                fontRole = "heading"
                textRole = (data.active or data.spine) and "TextHeading" or "Text"
            end
            HDG.UI.applyFontRole(frame._navLabelFs, fontRole)
            HDG.Theme:Register(frame._navLabelFs, textRole)
            frame._navLabelFs:SetText(isHeader and string.upper(data.label or "")
                or (data.label or ""))

            -- Label X: headers=8, top-level=26 (icon col), leaves=40 (manual indent, tree indent=0).
            local labelX = isHeader and 8 or (tier == "leaf" and 40 or 26)
            frame._navLabelFs:ClearAllPoints()
            frame._navLabelFs:SetPoint("LEFT",  frame, "LEFT",  labelX, 0)
            frame._navLabelFs:SetPoint("RIGHT", frame, "RIGHT", -4, 0)

            -- Category icon: top-level rows. iconActive/iconPressed stashed for pressed handlers.
            if frame._navIcon then
                local isTop = (tier ~= "leaf" and tier ~= "header")
                frame._navIconDefault = isTop and data.icon or nil
                frame._navIconActive  = isTop and data.iconActive or nil
                frame._navIconPressed = isTop and data.iconPressed or nil
                frame._navActive      = data.active and true or false
                _paintNavAtlas(frame._navIcon,
                    (frame._navActive and frame._navIconActive) or frame._navIconDefault)
            end
            -- Collapse toggle: enable + stamp the icon button on hub rows (parent
            -- groups with children); hidden elsewhere so clicks pass to the row.
            if frame._navIconBtn then
                if data.tier == "hub" then
                    frame._navIconBtn._hubView         = data.groupKey   -- collapse key (= view, or "tools")
                    frame._navIconBtn._navTipLabel     = data.label
                    frame._navIconBtn._navTipCollapsed = data.isCollapsed and true or false
                    frame._navIconBtn:Show()
                else
                    frame._navIconBtn._hubView = nil
                    frame._navIconBtn:Hide()
                end
            end
            -- Indent guide: leaves only.
            if frame._navGuide then
                if tier == "leaf" then frame._navGuide:Show() else frame._navGuide:Hide() end
            end

            -- NavRow paint: tier fill + accent spine (flat, never zebra).
            HDG.Theme:Register(frame, "NavRow", {
                tier   = tier,
                active = data.active and true or false,
                spine  = data.spine  and true or false,
            })
            if frame.EnableMouse then frame:EnableMouse(not isHeader) end  -- exception(false-positive): navNode template = "Button"; EnableMouse + RegisterForClicks are guaranteed; mock-fidelity guard
            if frame.RegisterForClicks then frame:RegisterForClicks("LeftButtonUp") end  -- exception(false-positive): navNode template = "Button"; see above
            if isHeader then
                frame:SetScript("OnClick", nil)
            else
                local click = data.click
                frame:SetScript("OnClick", function() dispatchClick(click) end)
            end
            -- Pressed-state icon swap. Cleared otherwise so pooled frames can't inherit stale handlers.
            if frame._navIconPressed and not isHeader then
                frame:SetScript("OnMouseDown", function(self) _paintNavAtlas(self._navIcon, self._navIconPressed) end)
                frame:SetScript("OnMouseUp", function(self)
                    _paintNavAtlas(self._navIcon, (self._navActive and self._navIconActive) or self._navIconDefault)
                end)
            else
                frame:SetScript("OnMouseDown", nil)
                frame:SetScript("OnMouseUp", nil)
            end
        end,
    })

-- Clicks live in cell initializers; active highlight flows via nav.tree's `active` flags.
function NavController:Wire(_rootFrame) end
function NavController:Refresh(_rootFrame, _ctx) end

HDG.Controllers:Register("nav", NavController)
