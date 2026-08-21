-- HDG.SessionIdentity
-- ============================================================================
-- Populates session.identity = { name, realm, class, classFile, charKey }
-- once per session (identity is stable until /reload). All consumers read
-- state.session.identity; none call UnitName/GetRealmName/UnitClass directly.
--
-- Why onEnable not PLAYER_LOGIN: PLAYER_LOGIN is owned by Init.lua's bootstrap;
-- onEnable runs after it drains, guaranteeing UnitName + UnitClass resolve.

HDG.Log:RegisterTags({ identity = { user = false, level = "warn" } })

HDG = HDG or {}
HDG.SessionIdentity = HDG.SessionIdentity or {}

-- Returns nil when identity hasn't dispatched yet (sentinel "" charKey -> nil).
function HDG.SessionIdentity.GetCharKey(state)
    local key = state.session.identity.charKey
    if key == "" then return nil end
    return key
end

-- The whole record, same boot-window contract. Added because three observers
-- had each grown a private copy of exactly this -- EssenceObserver and
-- ProfessionScanner byte-for-byte, ReagentStockObserver reading the Store
-- itself. They existed because the SSoT published the key and nothing else,
-- which is how a single source of truth quietly stops being one.
function HDG.SessionIdentity.GetIdentity(state)
    local id = state.session.identity
    if id.charKey == "" then return nil end
    return id
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
            HDG.Log:Warn("identity",
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
