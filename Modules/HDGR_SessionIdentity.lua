-- HDG.SessionIdentity
-- ============================================================================
-- Populates session.identity = { name, realm, class, classFile, charKey }
-- once per session (identity is stable until /reload). All consumers read
-- state.session.identity; none call UnitName/GetRealmName/UnitClass directly.
--
-- Why onEnable not PLAYER_LOGIN: PLAYER_LOGIN is owned by Init.lua's bootstrap;
-- onEnable runs after it drains, guaranteeing UnitName + UnitClass resolve.

HDG = HDG or {}
HDG.SessionIdentity = HDG.SessionIdentity or {}

-- Returns nil when identity hasn't dispatched yet (sentinel "" charKey -> nil).
function HDG.SessionIdentity.GetCharKey(state)
    local key = state.session.identity.charKey
    if key == "" then return nil end
    return key
end

HDG.Modules:Declare({
    name = "SessionIdentity",
    dependencies = {},
    onEnable = function(self)
        local name, realm = _G.UnitName("player")
        if not name then
            -- onEnable is guaranteed to fire after PLAYER_LOGIN drains, so
            -- UnitName MUST resolve. If it doesn't, that's a load-order
            -- regression worth surfacing -- not silently leaving identity
            -- at "" for the whole session (which causes consumers to
            -- silently early-exit).
            HDG.Log:Warn("modules",
                "SessionIdentity: UnitName returned nil at onEnable -- session.identity stays empty")
            return
        end
        if not realm or realm == "" then
            realm = _G.GetRealmName() or ""
        end
        local class, classFile = _G.UnitClass("player")
        -- factionGroup: normalize UnitFactionGroup -> "A"/"H"/"N" to match
        -- HDGR_VendorDB row[6] convention. Stamped once; selectors read
        -- state.session.identity.factionGroup (never call UnitFactionGroup).
        -- Pandaren faction swap mid-session requires /reload to re-stamp.
        local fg = _G.UnitFactionGroup("player")
        local factionTag = (fg == "Horde" and "H") or (fg == "Alliance" and "A") or "N"
        HDG.Store:Dispatch({
            type    = HDG.Constants.ACTIONS.SESSION_IDENTITY_SET,
            payload = {
                name         = name,
                realm        = realm,
                class        = class     or "",
                classFile    = classFile or "",
                factionGroup = factionTag,
            },
        })
    end,
})
