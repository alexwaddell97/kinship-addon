-- Kinship RP: core data and helpers.
-- This build covers your own character: profiles, Chronicle, Kin, House and
-- local Gatherings. Profile exchange with other players (MSP) comes next.

local ADDON, ns = ...
local K = {}
ns.K = K
_G.KinshipRP = K

K.MEDIA = "Interface\\AddOns\\KinshipRP\\Media\\"
-- Kinship's mark: a K in the game's own typeface on a plain pale disc.
K.ICON = K.MEDIA .. "Icon"
K.MONOGRAM = K.ICON

-- Icons for Kinship's kinds of thing, all the game's own.
local GAME = "Interface\\Icons\\"
K.ART = {
  IconNote = GAME .. "INV_Misc_Note_01",                   -- notes, letters, documents
  IconKin = GAME .. "Spell_Holy_PrayerOfFortitude",        -- people and kin
  IconFire = GAME .. "Spell_Fire_Fire",                    -- gatherings, effects
  IconPlace = GAME .. "INV_Misc_Map_01",                   -- places and the map
  IconMilestone = GAME .. "INV_Misc_Ribbon_01",            -- milestones and quests
  IconDungeon = GAME .. "INV_Sword_04",                    -- dungeons and battles
  IconPalette = GAME .. "INV_Misc_Gem_Variety_01",         -- the profile stage
}
-- A Kinship icon name ("IconNote") as a texture path.
function K.Art(name) return K.ART[name] or name end

---------------------------------------------------------------------------
-- Saved data
---------------------------------------------------------------------------
local DEFAULTS = {
  version    = 1,
  profiles   = {},          -- [charGUID] = { name, active, list = { [profileName] = profile } }
  chronicle  = {},          -- [charGUID] = { entries = {}, zones = {}, instances = {} }
  kin        = {},          -- [charGUID] = { [nameKey] = kinEntry }
  houses     = {},          -- [houseKey] = { crest, motto, desc }
  gatherings = {},          -- gatherings (yours and your guild's)
  gatherTomb = {},          -- [id] = time a gathering was removed (stops it coming back)
  registry   = {},          -- [nameKey] = { name, profile, t } other players' shared profiles
  notes      = {},          -- [nameKey] = your private note about another player
  migration  = {},          -- moving over from other RP addons: { dismissed, imported }
  rivals     = {},          -- [charGUID] = { [nameKey] = rival }   (Warfront)
  letters    = {},          -- [charGUID] = { list = { letter, ... } }
  statusButton = { shown = true, pos = nil },
  settings   = {
    chatNames = true, chatEmotes = true, chatOOC = true, chatNPC = true,
    warToasts = true, warChronicle = true, warSightings = true, warTooltip = true,
    parleyNarrate = false,
    lettersFrom = "anyone",   -- anyone | known (Kin, guild, house)
    -- Extended features: the master switch ("on") and one switch per module
    ext = { on = true, inventory = true, documents = true, auras = true, campaigns = true,
            dialogues = true, scripting = true, interop = true },
  },
}

local function CopyDefaults(src, dst)
  for k, v in pairs(src) do
    if dst[k] == nil then
      dst[k] = type(v) == "table" and CopyDefaults(v, {}) or v
    elseif type(v) == "table" and type(dst[k]) == "table" then
      CopyDefaults(v, dst[k])
    end
  end
  return dst
end

---------------------------------------------------------------------------
-- Saved-data schema. K.db.schema says which layout the saved data is in.
-- When an update changes that layout, raise K.SCHEMA and add a step to
-- MIGRATIONS: MIGRATIONS[n] = function(db) upgrades schema n - 1 to n.
-- Steps run in order at load, on the raw saved data, before the defaults are
-- filled in. Write each step so running it twice does no harm, and never
-- delete a step: someone may update from a much older version.
--   Schema 0: no schema field (0.3.x and earlier)
--   Schema 1: 1.0.0, the first public release
---------------------------------------------------------------------------
K.SCHEMA = 1
local MIGRATIONS = {
  [1] = function(db) end,   -- 1.0.0 keeps 0.3.x's layout; it only adds the schema field
}

-- Returns true when the data is at K.SCHEMA. A failed step stops the run and
-- leaves db.schema at the last step that worked, so it's tried again next
-- load. Data from a newer Kinship is left exactly as it is.
local function Migrate(db, fresh)
  if fresh then db.schema = K.SCHEMA; return true end
  local from = tonumber(db.schema) or 0
  if from > K.SCHEMA then
    K.newerSchema = from
    return false
  end
  for n = from + 1, K.SCHEMA do
    local step = MIGRATIONS[n]
    if step then
      local ok, err = pcall(step, db)
      if not ok then
        K.migrationFailed = n
        K:CaughtError("migration " .. n, err)
        return false
      end
    end
    db.schema = n
  end
  return true
end
K.Migrate = Migrate   -- also used to bring a restored backup up to date

---------------------------------------------------------------------------
-- Helpers
---------------------------------------------------------------------------
local issecret = _G.issecretvalue or function() return false end
-- Check for a secret value before anything else touches it (even ~= nil).
function K.Safe(v) return not issecret(v) and v ~= nil end

function K:Print(msg)
  print("|T" .. self.ICON .. ":14:14|t |cff2e8580Kinship|r: " .. tostring(msg))
end

-- Tiny event bus so panels refresh when data changes.
K.listeners = {}
function K:On(event, fn)
  self.listeners[event] = self.listeners[event] or {}
  table.insert(self.listeners[event], fn)
end
function K:Fire(event, ...)
  for _, fn in ipairs(self.listeners[event] or {}) do
    local ok, err = pcall(fn, ...)
    if not ok then self:CaughtError(event, err) end
  end
end

-- Errors Kinship caught instead of letting them break something: kept for
-- /kin bug (the last 25, repeats counted rather than listed, saved across a
-- /reload) and printed straight away while /kin debug is on.
-- where: a short label such as "nameplates" or an event name.
K.errors = {}
local MAX_ERRORS = 25
function K:CaughtError(where, err)
  if issecret(err) or issecret(where) then return end
  where, err = tostring(where or "?"), tostring(err)
  if self.debug then self:Print("|cffff6060" .. where .. ":|r " .. err) end
  for _, e in ipairs(self.errors) do
    if e.where == where and e.msg == err then
      e.n, e.t = (e.n or 1) + 1, time()
      return
    end
  end
  table.insert(self.errors, { where = where, msg = err:sub(1, 600), t = time(), n = 1, v = self.VERSION })
  while #self.errors > MAX_ERRORS do table.remove(self.errors, 1) end
end

-- When the game blocks something Kinship asked for ("Interface action failed
-- because of an AddOn"), note which call it was, for /kin bug.
do
  local blocked = CreateFrame("Frame")
  for _, e in ipairs({ "ADDON_ACTION_BLOCKED", "ADDON_ACTION_FORBIDDEN" }) do pcall(blocked.RegisterEvent, blocked, e) end
  blocked:SetScript("OnEvent", function(_, event, addon, fn)
    if addon == ADDON then K:CaughtError(event == "ADDON_ACTION_FORBIDDEN" and "forbidden" or "blocked", tostring(fn)) end
  end)
end

-- pcall that notes a failure with K:CaughtError instead of hiding it:
-- K.Try(where, fn, ...) returns what pcall(fn, ...) would. Code that runs
-- every frame can fail over and over, so the same error is noted at most
-- once every 10 seconds.
local lastNoted, notedCount = {}, 0
local function Noted(where, ok, ...)
  if not ok then
    local err = ...
    local id = tostring(where) .. "\001" .. (issecret(err) and "" or tostring(err))
    local now = GetTime()
    if not lastNoted[id] or now - lastNoted[id] > 10 then
      if not lastNoted[id] then notedCount = notedCount + 1 end
      if notedCount > 200 then wipe(lastNoted); notedCount = 1 end
      lastNoted[id] = now
      K:CaughtError(where, err)
    end
  end
  return ok, ...
end
function K.Try(where, fn, ...) return Noted(where, pcall(fn, ...)) end

-- Lua errors raised from Kinship's own files are noted too, then passed on
-- to whatever error handler was there before (the game's, or BugSack's).
local function WatchErrors()
  if not geterrorhandler or not seterrorhandler then return end
  local prev = geterrorhandler()
  seterrorhandler(function(msg, ...)
    if type(msg) == "string" and not issecret(msg)
        and msg:find("AddOns[/\\]KinshipRP[/\\]") then
      pcall(K.CaughtError, K, "lua", msg)
    end
    if prev then return prev(msg, ...) end
  end)
end

function K:CharKey() return UnitGUID("player") end

---------------------------------------------------------------------------
-- Extension points. Features plug in here instead of editing shared files.
---------------------------------------------------------------------------
-- Extra tooltip lines for players: fn(tooltip, unit, name, profile, isMe).
-- profile is their shared profile (or yours), possibly nil.
K.tooltipProviders = {}
function K:AddTooltipLines(fn) table.insert(self.tooltipProviders, fn) end

-- Buttons on the target bar (shown when you target a player):
-- { id, icon, label, order, onClick = fn(unit, name), shown = fn(unit, name) -> bool }
K.targetButtons = {}
function K:RegisterTargetButton(def)
  table.insert(self.targetButtons, def)
  table.sort(self.targetButtons, function(a, b) return (a.order or 50) < (b.order or 50) end)
  self:Fire("TARGET_BUTTONS")
end

-- Sections on the Settings page: { id, title, order, build = fn(card) }.
-- card:Toggle(label, desc, key | { get, set }), card:Note(text), card:Button(label, onClick), card:Space(px).
K.settingsSections = {}
function K:RegisterSettings(def)
  table.insert(self.settingsSections, def)
  table.sort(self.settingsSections, function(a, b) return (a.order or 50) < (b.order or 50) end)
end

-- Extra profile fields over MSP:
-- { publish = fn(my, profile) -- set msp.my fields from your profile
--   read = fn(fields, out)    -- copy received fields into the stored profile table
--   full = { "XX", ... }      -- fields to fetch when someone's full profile is opened
--   tooltip = { "XX", ... } } -- fields that should travel with the tooltip data
K.profileFields = {}
function K:AddProfileField(def) table.insert(self.profileFields, def) end

-- Extended features: a master switch and one switch per module, under
-- Settings > Extended features. K:ExtOn(module) is false when either is off;
-- K:ExtOn() asks about the master switch alone. Switching off takes effect at
-- once. Switching on something that was off at login waits for a /reload, so
-- a module never runs half set up (its events and timers start at login).
K.EXT_MODULES = { "inventory", "documents", "auras", "campaigns", "dialogues", "scripting", "interop" }
local extBoot = {}
local function ExtSettings() return K.db and type(K.db.settings.ext) == "table" and K.db.settings.ext or nil end

function K:ExtOn(module)
  local s = ExtSettings()
  if not s or s.on == false or not extBoot.on then return false end
  if module == nil then return true end
  return s[module] ~= false and extBoot[module] == true
end

-- The saved switch, whatever the session is running with.
function K:ExtWanted(module)
  local s = ExtSettings()
  if not s then return false end
  if module == nil then return s.on ~= false end
  return s[module] ~= false
end

function K:SetExt(module, on)
  local s = ExtSettings()
  if not s then return end
  s[module or "on"] = on and true or false
  self:Fire("EXTENDED")
end

-- True when a switch was turned on after login and needs a /reload.
function K:ExtNeedsReload()
  local s = ExtSettings()
  if not s then return false end
  if s.on ~= false and not extBoot.on then return true end
  for _, m in ipairs(self.EXT_MODULES) do
    if s[m] ~= false and not extBoot[m] and (s.on ~= false) then return true end
  end
  return false
end

local function SnapshotExt()
  if type(K.db.settings.ext) ~= "table" then K.db.settings.ext = {} end   -- missing switches count as on
  local s = ExtSettings()
  extBoot.on = s.on ~= false
  for _, m in ipairs(K.EXT_MODULES) do extBoot[m] = s[m] ~= false end
end

-- Players whose profiles, letters and messages you've chosen not to see.
-- Replaced by the Safety module; everything checks it.
function K:IsIgnored(name) return false end

-- Forever characters have a first and last name. How the client reports them
-- to addons still needs checking in the beta, so we split on the first space
-- and let players correct their house name by hand.
function K.SplitName(full)
  if not full then return nil, nil end
  local first, last = full:match("^(%S+)%s+(.+)$")
  return first or full, last
end

function K:PlayerName() return UnitName("player") or "?" end

-- Total RP 3 running too? Then Kinship works alongside it (Compat.lua):
-- Total RP 3 keeps profiles, tooltips, nameplates and chat names. Settled at
-- login for the whole session, since what's hooked then stays hooked.
function K:TRP3Loaded()
  local loaded = (C_AddOns and C_AddOns.IsAddOnLoaded) or rawget(_G, "IsAddOnLoaded")
  if not loaded then return false end
  local ok, v = pcall(loaded, "totalRP3")
  return ok and v and true or false
end

function K:Compat()
  if self.compat ~= nil then return self.compat end
  local v = self:TRP3Loaded()
  if IsLoggedIn and IsLoggedIn() then self.compat = v end
  return v
end

-- Start a whisper to someone in the chat box, on whichever chat API the client has.
function K:Whisper(name)
  if type(name) ~= "string" or name == "" then return end
  local util = type(ChatFrameUtil) == "table" and ChatFrameUtil or nil
  local tell = (util and util.SendTell) or rawget(_G, "ChatFrame_SendTell")
  if type(tell) == "function" and pcall(tell, name) then return end
  local open = (util and util.OpenChat) or rawget(_G, "ChatFrame_OpenChat")
  if type(open) == "function" then pcall(open, "/w " .. name .. " ") end
end

function K:CurrentPlace()
  local id = C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")
  local info = id and C_Map.GetMapInfo(id)
  local name = info and info.name
  if not name or name == "" then name = GetZoneText() end
  return name ~= "" and name or "somewhere unknown", id
end

function K.FormatDate(t) return date("%d %b %Y", t or time()) end

---------------------------------------------------------------------------
-- Profiles
---------------------------------------------------------------------------
K.STATUS = {
  ic   = { label = "In Character",     short = "IC",   color = { 0.35, 0.85, 0.45 } },
  ooc  = { label = "Out of Character", short = "OOC",  color = { 0.60, 0.65, 0.72 } },
  lfrp = { label = "Looking for RP",   short = "LFRP", color = { 0.95, 0.78, 0.30 } },
}
K.STATUS_ORDER = { "ic", "lfrp", "ooc" }

-- Warfront: how you approach fights, and what your character can go through.
K.STANCES = {
  open = { label = "Open war", short = "Open war", icon = "Interface\\Icons\\Ability_DualWield",
           color = { 0.90, 0.36, 0.30 },
           desc = "Any fight, any time. If our banners differ, attacking on sight is fair game." },
  duel = { label = "Honour first", short = "Honour", icon = "Interface\\Icons\\Ability_Warrior_BattleShout",
           color = { 0.95, 0.76, 0.36 },
           desc = "Fights are welcome, but challenge or emote first. No ambushes, no corpse camping." },
  none = { label = "Non-combatant", short = "Non-combatant", icon = "Interface\\Icons\\Spell_Holy_SealOfProtection",
           color = { 0.55, 0.74, 0.86 },
           desc = "Prefers to stay out of PvP stories. Will yield or flee rather than fight." },
}
K.STANCE_ORDER = { "open", "duel", "none" }

-- Consent uses the standard MSP fields, so other RP addons understand it.
-- Values (as every MSP addon sends them): "1" yes, "2" no, "3" ask first.
K.CONSENT = {
  { key = "RI", label = "Injury",          desc = "Wounds, scars and lasting harm" },
  { key = "RD", label = "Death",           desc = "Your character dying in a story" },
  { key = "RO", label = "Capture",         desc = "Being captured, bound or controlled" },
  { key = "RM", label = "Crime & theft",   desc = "Robbery, threats and other crimes" },
  { key = "RR", label = "Romance",         desc = "Romantic storylines" },
}
K.CONSENT_VALUES = {
  { key = "1", label = "Yes", color = { 0.40, 0.80, 0.48 } },
  { key = "3", label = "Ask", color = { 0.95, 0.76, 0.36 } },
  { key = "2", label = "No",  color = { 0.90, 0.36, 0.30 } },
}

local function NewProfile()
  local _, surname = K.SplitName(K:PlayerName())
  return {
    rpName = "", prefix = "", nickname = "",   -- full roleplay name, short title ("Lord"), nickname
    epithet = "", glance = "", pronouns = "", age = "", height = "", home = "",
    race = "", class = "", eyes = "", birthplace = "",   -- race/class: only if different from the game's
    house = surname or "", motto = "", currently = "", ooc = "",
    appearance = "", personality = "", history = "",
    status = "ooc", stance = "duel", consent = {},
  }
end
K.BlankProfile = NewProfile

-- The name to show for your character: roleplay name if set, else the game's.
function K:DisplayName(p)
  p = p or self:Profile()
  local n = strtrim(p.rpName or "")
  if n == "" then n = self:PlayerName() end
  local prefix = strtrim(p.prefix or "")
  return prefix ~= "" and (prefix .. " " .. n) or n
end

-- Out in the world (tooltips, nameplates, unit frames, chat) a roleplay name
-- is always in the same roleplay gold, so it reads as a roleplay name at a
-- glance, and always has the character's own name beside it in grey: the
-- name whispers, invites, /who and the friends list go by.
K.RP_NAME_COLOR = { 1.00, 0.86, 0.56 }
K.RP_NAME_HEX = "ffdb8f"
K.CHAR_NAME_COLOR = { 0.62, 0.62, 0.62 }
K.CHAR_NAME_HEX = "9d9d9d"

-- A character's name as the game shows it (no realm; with the surname Forever
-- characters have). Yours when name is nil.
function K:CharacterName(name)
  name = name or self:MyName()
  if type(name) ~= "string" or name == "" then return self:PlayerName() end
  return Ambiguate and Ambiguate(name, "none") or name
end

-- "Aldric Vane (Leeroy Jenkins)": the roleplay name in roleplay gold and the
-- character's name after it in grey. Just the character name when there's no
-- roleplay name, and no repeat when they're the same.
function K.BothNames(rp, char)
  rp, char = rp or "", char or ""
  if rp == "" then return char end
  local out = "|cff" .. K.RP_NAME_HEX .. rp .. "|r"
  if char ~= "" and char:lower() ~= rp:lower() then out = out .. " |cff" .. K.CHAR_NAME_HEX .. "(" .. char .. ")|r" end
  return out
end

function K:SetStance(stance)
  if not self.STANCES[stance] then return end
  self:Profile().stance = stance
  self:Fire("PROFILE")
end

function K:SetConsent(field, value)
  local p = self:Profile()
  p.consent = p.consent or {}
  p.consent[field] = value
  self:Fire("PROFILE")
end

function K:MyProfiles()
  local key = self:CharKey()
  local p = self.db.profiles[key]
  if not p then
    p = { active = "Main", list = { Main = NewProfile() } }
    self.db.profiles[key] = p
  end
  p.name = self:PlayerName()
  -- The whole name: on Forever the plain one is the first name only ("Vax" of Vax Orus)
  p.full = self:MyName()
  return p
end

function K:Profile()
  local p = self:MyProfiles()
  if not p.list[p.active] then p.active = next(p.list) or "Main"; p.list[p.active] = p.list[p.active] or NewProfile() end
  return p.list[p.active]
end

function K:SetField(field, value)
  self:Profile()[field] = value
  self:Fire("PROFILE")
end

function K:SetStatus(status)
  if not self.STATUS[status] then return end
  self:Profile().status = status
  self:Fire("PROFILE")
end

function K:CycleStatus()
  local cur = self:Profile().status
  for i, s in ipairs(self.STATUS_ORDER) do
    if s == cur then return self:SetStatus(self.STATUS_ORDER[i % #self.STATUS_ORDER + 1]) end
  end
  self:SetStatus("ic")
end

function K:ProfileNames()
  local out = {}
  for name in pairs(self:MyProfiles().list) do out[#out + 1] = name end
  table.sort(out)
  return out
end

function K:SwitchProfile(name)
  local p = self:MyProfiles()
  if p.list[name] then p.active = name; self:Fire("PROFILE") end
end

function K:NewProfile(name, copyCurrent)
  local p = self:MyProfiles()
  name = strtrim(name or "")
  if name == "" or p.list[name] then return false end
  if copyCurrent then
    -- Deep copy: consent, glances and traits are tables of their own.
    p.list[name] = CopyTable(self:Profile())
    -- A copy is your own: a later import must never mistake it for the original.
    p.list[name].source, p.list[name].sourceSig = nil, nil
  else
    p.list[name] = NewProfile()
  end
  p.active = name
  self:Fire("PROFILE")
  return true
end

function K:DeleteProfile(name)
  local p = self:MyProfiles()
  local count = 0
  for _ in pairs(p.list) do count = count + 1 end
  if count <= 1 or not p.list[name] then return false end
  p.list[name] = nil
  if p.active == name then p.active = next(p.list) end
  self:Fire("PROFILE")
  return true
end

-- The house a character belongs to (their surname unless they changed it).
function K:HouseName() return strtrim(self:Profile().house or "") end
function K:HouseKey(name) name = name or self:HouseName(); return name ~= "" and name:lower() or nil end

function K:House()
  local key = self:HouseKey()
  if not key then return nil end
  self.db.houses[key] = self.db.houses[key] or { crest = "Interface\\Icons\\INV_Shield_05", motto = "", desc = "" }
  return self.db.houses[key]
end

---------------------------------------------------------------------------
-- Chronicle
---------------------------------------------------------------------------
K.ENTRY = {
  place     = { label = "Places",     icon = K.Art("IconPlace") },
  milestone = { label = "Milestones", icon = K.Art("IconMilestone") },
  dungeon   = { label = "Dungeons",   icon = K.Art("IconDungeon") },
  kin       = { label = "Kin",        icon = K.Art("IconKin") },
  note      = { label = "Notes",      icon = K.Art("IconNote") },
  battle    = { label = "Battles",    icon = K.Art("IconDungeon") },
  letter    = { label = "Letters",    icon = K.Art("IconNote") },
}

function K:Chronicle()
  local key = self:CharKey()
  local c = self.db.chronicle[key]
  if not c then
    c = { entries = {}, zones = {}, instances = {} }
    self.db.chronicle[key] = c
  end
  return c
end

function K:AddEntry(kind, title, text, place)
  local c = self:Chronicle()
  local entry = {
    kind = kind, title = title, text = text or "",
    place = place or (self:CurrentPlace()), level = UnitLevel("player"), t = time(),
  }
  table.insert(c.entries, entry)
  self:Fire("CHRONICLE", entry)
  return entry
end

function K:RemoveEntry(entry)
  local c = self:Chronicle()
  for i, e in ipairs(c.entries) do
    if e == entry then table.remove(c.entries, i); self:Fire("CHRONICLE"); return true end
  end
end

---------------------------------------------------------------------------
-- Kin (companions)
---------------------------------------------------------------------------
K.RELATIONS = {
  { key = "",          label = "Companion" },
  { key = "friend",    label = "Friend" },
  { key = "family",    label = "Family" },
  { key = "mentor",    label = "Mentor" },
  { key = "rival",     label = "Rival" },
}
function K.RelationLabel(key)
  for _, r in ipairs(K.RELATIONS) do if r.key == (key or "") then return r.label end end
  return "Companion"
end

function K:KinList()
  local key = self:CharKey()
  self.db.kin[key] = self.db.kin[key] or {}
  return self.db.kin[key]
end

function K:KinFor(name)
  if not self.Safe(name) or not name then return nil end
  return self:KinList()[name:lower()]
end

-- Remember someone you've adventured with. how: "group" | "manual"
function K:MeetUnit(unit, how)
  if not UnitExists(unit) or not UnitIsPlayer(unit) or UnitIsUnit(unit, "player") then return end
  local name = GetUnitName(unit, true)
  if not self.Safe(name) or not name then return end
  local list, key = self:KinList(), name:lower()
  local e = list[key]
  if not e then
    local place = self:CurrentPlace()
    e = { name = name, rel = "", how = how or "group",
          met = { place = place, level = UnitLevel("player"), t = time() } }
    list[key] = e
    self:AddEntry("kin", "Travelled with " .. name, nil, place)
    self:Fire("KIN")
  end
  e.seen = time()
  local _, class = UnitClass(unit)
  if self.Safe(class) then e.class = class end
  return e
end

function K:AddKinByName(name)
  name = strtrim(name or "")
  if name == "" then return end
  local list, key = self:KinList(), name:lower()
  if list[key] then return list[key] end
  local place = self:CurrentPlace()
  list[key] = { name = name, rel = "", how = "manual", met = { place = place, level = UnitLevel("player"), t = time() } }
  self:Fire("KIN")
  return list[key]
end

function K:RemoveKin(key) self:KinList()[key] = nil; self:Fire("KIN") end

---------------------------------------------------------------------------
-- Automatic Chronicle entries
---------------------------------------------------------------------------
local function OnZone()
  local c = K:Chronicle()
  local place, id = K:CurrentPlace()
  local zoneKey = id or place
  if zoneKey and not c.zones[zoneKey] then
    c.zones[zoneKey] = time()
    K:AddEntry("place", "Set foot in " .. place, nil, place)
  end
  local inInstance, kind = IsInInstance()
  if inInstance and (kind == "party" or kind == "raid") then
    local name = GetInstanceInfo()
    if K.Safe(name) and name and not c.instances[name] then
      c.instances[name] = time()
      K:AddEntry("dungeon", "Entered " .. name, nil, name)
    end
  end
end

local function OnLevel(level)
  if level and (level % 5 == 0 or level == 60) then
    K:AddEntry("milestone", ("Reached level %d"):format(level))
  end
end

-- Who counts as travelling with you: your party, or in a raid only your own
-- group of five. Battlegrounds and arenas fill up with strangers, so they
-- never add anyone.
local function OnGroup()
  local inInstance, kind = IsInInstance()
  if inInstance and (kind == "pvp" or kind == "arena") then return end
  if IsInRaid() then
    local n, mine = GetNumGroupMembers(), nil
    for i = 1, n do
      local me = UnitIsUnit("raid" .. i, "player")
      if K.Safe(me) and me then mine = select(3, GetRaidRosterInfo(i)) break end
    end
    if not mine then return end
    for i = 1, n do
      local sub = select(3, GetRaidRosterInfo(i))
      if sub == mine then K.Try("group", K.MeetUnit, K, "raid" .. i, "group") end
    end
  else
    for i = 1, GetNumSubgroupMembers() do K.Try("group", K.MeetUnit, K, "party" .. i, "group") end
  end
end

-- The roster changes in bursts; look once it settles.
local groupPending
local function ScheduleGroup()
  if groupPending then return end
  groupPending = true
  C_Timer.After(2, function() groupPending = nil; K.Try("group", OnGroup) end)
end

---------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------
local ev = CreateFrame("Frame")
ev:RegisterEvent("ADDON_LOADED")
ev:RegisterEvent("PLAYER_LOGIN")
ev:SetScript("OnEvent", function(_, event, ...)
  if event == "ADDON_LOADED" then
    if ... ~= ADDON then return end
    -- Nothing saved yet: a new install (or the data didn't load).
    local fresh = type(KinshipRPDB) ~= "table" or next(KinshipRPDB) == nil
    if type(KinshipRPDB) ~= "table" then KinshipRPDB = {} end
    local current = Migrate(KinshipRPDB, fresh)
    K.db = CopyDefaults(DEFAULTS, KinshipRPDB)
    -- Keep caught errors across a /reload (anything caught before now first).
    if type(K.db.errorLog) ~= "table" then K.db.errorLog = {} end
    for _, e in ipairs(K.errors) do table.insert(K.db.errorLog, e) end
    while #K.db.errorLog > MAX_ERRORS do table.remove(K.db.errorLog, 1) end
    K.errors = K.db.errorLog
    WatchErrors()
    SnapshotExt()
    if not current then
      C_Timer.After(8, function()
        if K.newerSchema then
          K:Print("|cffe6a04cYour saved data comes from a newer version of Kinship.|r Update Kinship before you change "
            .. "anything, or some of it may not show.")
        else
          K:Print("|cffe6a04cKinship couldn't finish updating your saved data.|r It will try again "
            .. "next time you log in. Type /kin bug to report it.")
        end
      end)
    end
  elseif event == "PLAYER_LOGIN" then
    K:MyProfiles()
    for _, e in ipairs({ "ZONE_CHANGED_NEW_AREA", "PLAYER_ENTERING_WORLD", "PLAYER_LEVEL_UP", "GROUP_ROSTER_UPDATE" }) do
      ev:RegisterEvent(e)
    end
    K:Fire("LOGIN")
  elseif event == "ZONE_CHANGED_NEW_AREA" or event == "PLAYER_ENTERING_WORLD" then
    C_Timer.After(1, function() K.Try("zone", OnZone) end)
  elseif event == "PLAYER_LEVEL_UP" then
    OnLevel(...)
  elseif event == "GROUP_ROSTER_UPDATE" then
    ScheduleGroup()
  end
end)

---------------------------------------------------------------------------
-- Slash commands and addon compartment
---------------------------------------------------------------------------
function KinshipRP_OnCompartmentClick() K.Journal:Toggle() end

SLASH_KINSHIPRP1, SLASH_KINSHIPRP2 = "/kinship", "/kin"
SlashCmdList.KINSHIPRP = function(input)
  local cmd, rest = (input or ""):match("^%s*(%S*)%s*(.-)%s*$")
  cmd = (cmd or ""):lower()
  if cmd == "" then
    K.Journal:Toggle()
  elseif cmd == "profile" or cmd == "chronicle" or cmd == "kin" or cmd == "house" or cmd == "gatherings"
      or cmd == "directory" or cmd == "warfront" or cmd == "letters" or cmd == "settings"
      or cmd == "persona" or cmd == "companions" or cmd == "quests" or cmd == "inventory" then
    K.Journal:Open(cmd)
  elseif (cmd == "effects" or cmd == "auras") and K.Auras then
    if K:ExtOn("auras") then K.Auras:OpenJournal() else K:Print("Effects are switched off (Settings > Extended features).") end
  elseif cmd == "markers" and K.QuestMarkers then
    K.QuestMarkers:Report()
  elseif cmd == "satchel" and K.Satchel then
    K.Satchel:Toggle()
  elseif (cmd == "outfit" or cmd == "wear") and K.Worn then
    if not K:ExtOn("inventory") then
      K:Print("Items are switched off (Settings > Extended features).")
    elseif rest == "" then
      K.Journal:Open("inventory")
      local c = K.Journal.content[K.Journal:Index("inventory")]
      if c and c.frames then
        c.tab = 5
        K.Journal:RefreshCurrent()
        local tab = c.frames[5]
        if tab and tab.ShowView then tab:ShowView("outfits") end
      end
    else
      local o = K.Worn:FindOutfit(rest)
      if o then K.Worn:ChangeInto(o) else K:Print(("You have no outfit called \"%s\"."):format(K.UI.Escape(rest))) end
    end
  elseif cmd == "bags" or cmd == "items" then
    K.Journal:Open("inventory")
  elseif (cmd == "roll" or cmd == "dice") and K.Dice then
    if rest ~= "" then K.Dice:Roll(rest) else K.Dice:Toggle() end
  elseif (cmd == "scan" or cmd == "map") and K.MapScan then
    -- The scan lives on the world map, so open it first.
    if WorldMapFrame and not WorldMapFrame:IsShown() and ToggleWorldMap then ToggleWorldMap() end
    C_Timer.After(0.3, function() K.MapScan:Scan() end)
  elseif (cmd == "share" or cmd == "export" or cmd == "import") and K.ProfileShare then
    K.ProfileShare:Open(cmd == "import" and "import" or nil)
  elseif cmd == "ignore" and K.Safety then
    local who = rest ~= "" and rest or nil
    if not who and UnitExists("target") and UnitIsPlayer("target") then
      local n = GetUnitName("target", true)
      if K.Safe(n) then who = n end
    end
    if who then K.Safety:ConfirmIgnore(who) else K:Print("Ignore whom? Target them, or type /kin ignore Name.") end
  elseif cmd == "bar" then
    K.db.settings.targetBar = K.db.settings.targetBar == false
    if K.TargetBar then K.TargetBar:Update() end
    K:Print("Target bar " .. (K.db.settings.targetBar and "on" or "off"))
  elseif cmd == "parley" then
    K.Parley:Toggle()
  elseif cmd == "letter" or cmd == "write" then
    local to = rest ~= "" and rest or nil
    if not to and UnitExists("target") and UnitIsPlayer("target") then
      local n = GetUnitName("target", true)
      if K.Safe(n) then to = n end
    end
    K.Letters:Compose(to)
  elseif cmd == "bug" and K.BugReport then
    K.BugReport:Open()
  elseif cmd == "backup" and K.Backup then
    K.Backup:Open(rest:lower() == "restore" and "restore" or nil)
  elseif (cmd == "kofi" or cmd == "support") and K.Support then
    K.Support:Show()
  elseif cmd == "debug" then
    K.debug = not K.debug
    K:Print("Debug messages " .. (K.debug and "on" or "off"))
  elseif cmd == "view" then
    K:ViewUnitProfile("target")
  elseif cmd == "status" and K:Compat() then
    K:Print("Your status is set in Total RP 3 while it runs.")
  elseif cmd == "status" then
    local s = rest:lower()
    if s == "lf" then s = "lfrp" end
    if K.STATUS[s] then K:SetStatus(s) else K:CycleStatus() end
    K:Print("Status: " .. K.STATUS[K:Profile().status].label)
  elseif cmd == "button" then
    K.db.statusButton.shown = not K.db.statusButton.shown
    K.StatusButton:Update()
  else
    for _, line in ipairs({
      "/kin - open your Kinship journal",
      "/kin kofi - a link to support Kinship on Ko-fi",
      "/kin satchel - open your roleplay satchel (it also opens with your bags)",
      "/kin outfit [name] - change into a saved outfit (or open your outfits)",
      "/kin profile | persona | companions | directory | kin | house | letters - open a page",
      "/kin chronicle | quests | gatherings | warfront | inventory | settings - open a page",
      "/kin effects - wounds, boons and states on your character",
      "/kin roll [2d6+3] - roll dice (or open the dice tray)",
      "/kin scan - find roleplayers nearby on the map",
      "/kin share | import - share a profile as text, or bring one in",
      "/kin ignore [name] - hide someone everywhere in Kinship",
      "/kin bar - show or hide the target bar",
      "/kin parley - open the Parley wheel (bind a key for hold-and-release)",
      "/kin letter [name] - write a letter to someone (or your target)",
      "/kin view - view your target's profile (or your own)",
      "/kin status [ic|lf|ooc] - set or cycle your status",
      "/kin button - show or hide the status button",
      "/kin backup [restore] - back up all of Kinship's saved data as text, or restore it",
      "/kin bug - details to copy into a bug report",
    }) do K:Print(line) end
  end
end

---------------------------------------------------------------------------
-- Development builds could set out a Westfall test campaign (/kin seed) and
-- demo content for screenshots (/kin showcase). Neither ships, so take away
-- what they left: only the quests, item designs, document and stash the
-- campaign recorded making (K.db.kinSeed). Runs once, after the modules have
-- set up their saved data.
---------------------------------------------------------------------------
K:On("LOGIN", function()
  C_Timer.After(0, function()
    K.db.showcaseLog = nil
    local made = K.db.kinSeed
    if type(made) ~= "table" then return end
    local Q, I, D, S = K.Quests, K.Items, K.Documents, K.Stashes
    for _, id in ipairs(made.quests or {}) do
      if Q then Q:Library()[id] = nil; Q:Log()[id] = nil end
    end
    for _, id in ipairs(made.designs or {}) do
      if I then
        local n = I:CountOf(id)
        if n > 0 then I:Remove(id, n) end
        K.db.itemDefs[id] = nil
      end
    end
    for _, id in ipairs(made.docs or {}) do if D then D:Delete(id) end end
    if made.stash and S then
      local _, i = S:Find(made.stash)
      if i then table.remove(S:Mine(), i) end
    end
    K.db.kinSeed = nil
    K:Fire("QUESTS"); K:Fire("INVENTORY"); K:Fire("STASHES")
  end)
end)
