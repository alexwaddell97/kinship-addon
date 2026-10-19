-- Kinship RP: profile sharing over the Mary Sue Protocol (via LibMSP).
-- Standard fields let Total RP 3, MyRolePlay, XRP and friends read Kinship
-- profiles (and us theirs). Extra "K?" fields carry Kinship-only details;
-- other addons simply ignore them.

local ADDON, ns = ...
local K = ns.K
local Safe = K.Safe
local C = {}
K.Comm = C

K.VERSION = "1.2.2"

-- Fields to fetch when viewing someone's full profile.
local FULL_FIELDS = { "TT", "DE", "HI", "AG", "AH", "HH", "MO", "PN", "KP", "KG", "KC", "KM", "KH", "KW", "RI", "RD", "RO", "RM", "RR",
                      "PX", "NI", "RA", "RC", "AE", "HB", "CO" }
-- Stance and the PvP-relevant consent fields travel with the tooltip data.
local TOOLTIP_EXTRA = { "KW", "RI", "RD", "RO", "RM", "PX", "RC", "CO" }
local CONSENT_FIELDS = { "RI", "RD", "RO", "RM", "RR" }
local TT_REQUEST = { "TT", "KW", "RI", "RD", "RO", "RM", "PX", "RC", "CO" }
-- Field lists, including any added through K:AddProfileField.
local function Merge(base, key)
  local out, seen = {}, {}
  for _, f in ipairs(base) do if not seen[f] then seen[f] = true; out[#out + 1] = f end end
  for _, def in ipairs(K.profileFields) do
    for _, f in ipairs(def[key] or {}) do if not seen[f] then seen[f] = true; out[#out + 1] = f end end
  end
  return out
end
function C.FullFields() return Merge(FULL_FIELDS, "full") end
function C.TooltipFields(request) return Merge(request and TT_REQUEST or TOOLTIP_EXTRA, "tooltip") end

-- These always reflect the latest message, even when it leaves them out.
local ALWAYS_FRESH = { status = true, stance = true, addon = true }

-- The MSP field each stored text comes from. LibMSP keeps every field it has
-- heard for a player this session, and an emptied field as "": when one is
-- present but empty, the player cleared it, so we clear our copy too.
local FIELD_OF = {
  rpName = "NA", prefix = "PX", nickname = "NI", race = "RA", class = "RC", eyes = "AE", birthplace = "HB",
  ooc = "CO", epithet = "NT", house = "NH", pronouns = "PN", age = "AG", height = "AH", home = "HH",
  motto = "MO", currently = "CU", appearance = "DE", history = "HI", personality = "KP", glance = "KG",
  crest = "KC", houseMotto = "KM", houseHistory = "KH",
}

-- Personality has no standard MSP field, so for other addons it rides at the
-- end of History behind this marker. Kinship readers use KP and trim it off.
local PERSONALITY_MARK = "\n\n~ Personality ~\n"

local FC_OUT = { ic = "2", ooc = "1", lfrp = "3" }
local FC_IN  = { ["1"] = "ooc", ["2"] = "ic", ["3"] = "lfrp", ["4"] = "ic" }

-- Other RP addons that publish their own MSP profile. Kinship is meant to
-- replace them: if one is still running, Kinship offers to bring your
-- profile across and switch it off (see Import.lua). Until then both write
-- to the same shared profile, so the switch matters.
local OTHER_RP = { "totalRP3", "MyRolePlay", "xrp" }

local REGISTRY_DAYS = 30
local REGISTRY_MAX = 3000        -- profiles kept; past this the longest-unseen go...
local REGISTRY_KEEP = 2400       -- ...down to this many, so trimming is rare

---------------------------------------------------------------------------
-- Names
---------------------------------------------------------------------------
function K.MergedName(name)
  if not name or not Safe(name) then return nil end
  if AddOn_Chomp and AddOn_Chomp.NameMergedRealm then
    local ok, merged = pcall(AddOn_Chomp.NameMergedRealm, name)
    if ok and merged then return merged end
  end
  return name
end

function K.NameKey(name)
  local merged = K.MergedName(name)
  return merged and merged:lower() or nil
end

function K:MyName()
  local n, r = UnitFullName("player")
  if AddOn_Chomp and AddOn_Chomp.NameMergedRealm then
    local ok, merged = pcall(AddOn_Chomp.NameMergedRealm, n, r)
    if ok and merged then return merged end
  end
  return n or self:PlayerName()
end

-- Is this name you, in any form (short, Name-Realm, or a merged realm)?
function K:IsMe(name)
  if type(name) ~= "string" or not Safe(name) or name == "" then return false end
  if name == self:PlayerName() then return true end
  local key = K.NameKey(name)
  return key ~= nil and key == K.NameKey(self:MyName())
end

-- Look up another player's shared profile by any form of their name.
function K:ProfileOf(name)
  if not name then return nil end
  local reg = self.Registry[K.NameKey(name) or ""] or self.Registry[name:lower()]
  return reg
end

---------------------------------------------------------------------------
-- Availability
---------------------------------------------------------------------------
function C:Available() return msp ~= nil and type(msp.Request) == "function" end

function C:OtherRPAddon()
  local loaded = C_AddOns and C_AddOns.IsAddOnLoaded or IsAddOnLoaded
  if not loaded then return nil end
  for _, name in ipairs(OTHER_RP) do
    local ok, isLoaded = pcall(loaded, name)
    if ok and isLoaded then return name end
  end
end

local function Blocked()
  if IsInInstance() then return true end
  return C_ChatInfo and C_ChatInfo.InChatMessagingLockdown and C_ChatInfo.InChatMessagingLockdown()
end

---------------------------------------------------------------------------
-- Publishing your profile
---------------------------------------------------------------------------
local function Clean(v)
  v = v and strtrim(v) or ""
  return v ~= "" and v or nil
end

local function ValidCrest(path)
  if type(path) ~= "string" or #path > 120 then return nil end
  if not path:lower():find("^interface\\icons\\[%w_]+$") then return nil end
  return path
end

-- Alongside Total RP 3 Kinship writes only the fields that are its own; it
-- writes the rest (name, description, glances, RP style and so on).
local OWN_FIELDS = { "KC", "KM", "KH", "KW", "KU", "KS", "KQ" }

function C:Publish()
  if not self:Available() then return end
  local compat = K:Compat()
  local p, my = K:Profile(), compat and {} or msp.my
  my.VA = "KinshipRP/" .. K.VERSION
  my.NA = Clean(p.rpName) or K:CharacterName()
  my.PX = Clean(p.prefix)
  my.NI = Clean(p.nickname)
  my.RA = Clean(p.race)
  my.RC = Clean(p.class)
  my.AE = Clean(p.eyes)
  my.HB = Clean(p.birthplace)
  my.CO = Clean(p.ooc)
  my.NT = Clean(p.epithet)
  my.NH = Clean(p.house)
  my.PN = Clean(p.pronouns)
  my.AG = Clean(p.age)
  my.AH = Clean(p.height)
  my.HH = Clean(p.home)
  my.MO = Clean(p.motto)
  my.CU = Clean(p.currently)
  my.DE = Clean(p.appearance)
  my.FC = FC_OUT[p.status] or "1"
  local history, personality = Clean(p.history), Clean(p.personality)
  my.HI = personality and ((history or "") .. PERSONALITY_MARK .. personality) or history
  my.KP = personality
  my.KG = Clean(p.glance)
  local house = K:House()
  my.KC = house and ValidCrest(house.crest) or nil
  my.KM = house and Clean(house.motto) or nil
  my.KH = house and Clean(house.desc) or nil   -- the house's history
  my.KW = K.STANCES[p.stance or ""] and p.stance or "duel"
  local consent = p.consent or {}
  for _, field in ipairs(CONSENT_FIELDS) do
    local v = consent[field]
    my[field] = (v == "1" or v == "2" or v == "3") and v or nil
  end
  for _, def in ipairs(K.profileFields) do
    if def.publish then K.Try("profile field", def.publish, my, p) end
  end
  if compat then
    for _, f in ipairs(OWN_FIELDS) do msp.my[f] = my[f] end
    if not msp.my.VA or msp.my.VA == "" then return end   -- Total RP 3 hasn't set out its profile yet
  end
  local ok, err = pcall(msp.Update, msp)
  if not ok then K:CaughtError("profile update", err) end
end

-- Typing fires lots of changes; publish once things settle.
function C:SchedulePublish()
  if self.pending then return end
  self.pending = true
  C_Timer.After(2, function() C.pending = false; C:Publish() end)
end

---------------------------------------------------------------------------
-- Receiving other players' profiles
---------------------------------------------------------------------------
local BuildProfile
function C.BuildProfile(fields) return BuildProfile(fields) end   -- Compat.lua reads Total RP 3's with it
function BuildProfile(fields)
  local function f(key)
    local v = fields[key]
    return (type(v) == "string" and v ~= "") and v or ""
  end
  local history, personality = f("HI"), f("KP")
  if personality ~= "" then
    local cut = history:find(PERSONALITY_MARK, 1, true)
    if cut then history = history:sub(1, cut - 1) end
  end
  local consent = {}
  for _, field in ipairs(CONSENT_FIELDS) do
    local v = f(field)
    if v == "1" or v == "2" or v == "3" then consent[field] = v end
  end
  local out = {
    stance = K.STANCES[f("KW")] and f("KW") or nil, consent = consent,
    rpName = f("NA"), prefix = f("PX"), nickname = f("NI"), race = f("RA"), class = f("RC"),
    eyes = f("AE"), birthplace = f("HB"), ooc = f("CO"),
    epithet = f("NT"), house = f("NH"), pronouns = f("PN"),
    age = f("AG"), height = f("AH"), home = f("HH"), motto = f("MO"), currently = f("CU"),
    appearance = f("DE"), history = history, personality = personality, glance = f("KG"),
    status = FC_IN[f("FC")] or "ooc",
    crest = ValidCrest(f("KC")), houseMotto = f("KM"), houseHistory = f("KH"),
    addon = f("VA"),
  }
  -- Fields added by other Kinship features (glances, traits, badges...)
  for _, def in ipairs(K.profileFields) do
    if def.read then K.Try("profile field", def.read, fields, out) end
  end
  return out
end

function C:OnReceived(name)
  if not name or not msp.char or K:IsIgnored(name) then return end
  local char = rawget(msp.char, name) or msp.char[name]
  if not char or not char.field then return end
  local fields = char.field
  local va, na = fields.VA, fields.NA
  if (not va or va == "") and (not na or na == "") then return end
  local key = K.NameKey(name)
  if not key or key == K.NameKey(K:MyName()) then return end
  local fresh = BuildProfile(fields)
  local entry = K.db.registry[key]
  if not entry then
    entry = { name = name, profile = fresh }
    C.count = (C.count or 0) + 1
    if C.count > REGISTRY_MAX then C:Shrink() end
  else
    -- A tooltip-sized update mustn't wipe the longer texts we already hold:
    -- only take what this message actually carried.
    local p = entry.profile or {}
    for k, v in pairs(fresh) do
      local has = (type(v) == "string" and v ~= "") or (type(v) == "table" and next(v) ~= nil)
      if k ~= "consent" and (has or ALWAYS_FRESH[k]) then p[k] = v end
    end
    -- Fields they've emptied: empty here too, so nothing stale lingers.
    for k, src in pairs(FIELD_OF) do
      if fields[src] == "" then p[k] = (k == "crest") and nil or "" end
    end
    -- Consent, answer by answer: a cleared answer must not keep an old "yes".
    p.consent = type(p.consent) == "table" and p.consent or {}
    for _, f in ipairs(CONSENT_FIELDS) do
      if fields[f] ~= nil then p.consent[f] = fresh.consent[f] end
    end
    entry.profile, entry.name = p, name
  end
  entry.t = time()
  K.db.registry[key] = entry
  K:Fire("REGISTRY", key, entry)
end

-- Keep the registry to a sensible size by dropping the longest-unseen, down
-- to REGISTRY_KEEP however far over it has grown. C.count is only a running
-- guess (other pages forget profiles too), so count properly first: nothing
-- is dropped unless the registry really is over REGISTRY_MAX. Profiles you
-- covered by hand go last, so the cover sticks.
function C:Shrink()
  local reg = K.db and K.db.registry
  if not reg then return end
  local list = {}
  for key, e in pairs(reg) do
    local t = type(e) == "table" and tonumber(e.t) or 0
    if type(e) == "table" and e.flaggedByHand then t = math.huge end
    list[#list + 1] = { key = key, t = t }
  end
  C.count = #list
  if #list <= REGISTRY_MAX then return end
  table.sort(list, function(a, b) return a.t < b.t end)
  for i = 1, #list - REGISTRY_KEEP do reg[list[i].key] = nil end
  C.count = REGISTRY_KEEP
end

---------------------------------------------------------------------------
-- Asking for profiles
---------------------------------------------------------------------------
function C:Request(name, full)
  if not self:Available() or Blocked() or not name or not Safe(name) then return end
  if K.NameKey(name) == K.NameKey(K:MyName()) then return end
  pcall(msp.Request, msp, name, full and C.FullFields() or C.TooltipFields(true))
end

function C:RequestUnit(unit, full)
  if not UnitExists(unit) or not UnitIsPlayer(unit) or UnitIsUnit(unit, "player") then return end
  local name = GetUnitName(unit, true)
  if Safe(name) and name then self:Request(name, full) end
end

local function Prune()
  local cutoff = time() - REGISTRY_DAYS * 86400
  for key, e in pairs(K.db.registry) do
    if (e.t or 0) < cutoff then K.db.registry[key] = nil end
  end
end

---------------------------------------------------------------------------
-- Start-up
---------------------------------------------------------------------------
K:On("LOGIN", function()
  K.db.registry = K.db.registry or {}
  Prune()
  C:Shrink()   -- counts, and trims a registry saved over the cap
  K.Registry = K.db.registry

  if not C:Available() then
    K:Print("Profile sharing is unavailable (LibMSP didn't load).")
    return
  end

  C.otherAddon = C:OtherRPAddon()
  -- Alongside Total RP 3 the shared profile is its own: claiming it would stop it sharing.
  if not K:Compat() and not rawget(_G, "msp_RPAddOn") then _G.msp_RPAddOn = "KinshipRP" end

  table.insert(msp.callback.received, function(name) K.Try("profile received", C.OnReceived, C, name) end)
  if type(msp.AddFieldsToTooltip) == "function" then pcall(msp.AddFieldsToTooltip, msp, C.TooltipFields(false)) end
  C:Publish()

  local ev = CreateFrame("Frame")
  ev:RegisterEvent("UPDATE_MOUSEOVER_UNIT")
  ev:RegisterEvent("PLAYER_TARGET_CHANGED")
  ev:RegisterEvent("GROUP_ROSTER_UPDATE")
  ev:SetScript("OnEvent", function(_, event)
    if event == "UPDATE_MOUSEOVER_UNIT" then C:RequestUnit("mouseover")
    elseif event == "PLAYER_TARGET_CHANGED" then C:RequestUnit("target")
    elseif event == "GROUP_ROSTER_UPDATE" then
      local raid = IsInRaid()
      local prefix, n = raid and "raid" or "party", raid and GetNumGroupMembers() or GetNumSubgroupMembers()
      for i = 1, n do C:RequestUnit(prefix .. i) end
    end
  end)
end)

K:On("PROFILE", function() C:SchedulePublish() end)
K:On("HOUSE", function() C:SchedulePublish() end)

-- Refresh an open tooltip when that player's profile arrives.
K:On("REGISTRY", function(key)
  if GameTooltip:IsShown() and UnitExists("mouseover") and UnitIsPlayer("mouseover") then
    local name = GetUnitName("mouseover", true)
    if Safe(name) and K.NameKey(name) == key then GameTooltip:SetUnit("mouseover") end
  end
end)
