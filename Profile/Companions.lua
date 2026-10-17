-- Kinship RP: companion profiles for pets and mounts. Each character keeps a
-- few companions (name, title, icon, glance, description) bound to the names
-- of their pets or mounts. A compact copy travels with your profile over MSP
-- ("KA"), and the companion's story shows on that pet's tooltip (or on its
-- rider's tooltip, for mounts).

local ADDON, ns = ...
local K = ns.K
local UI = K.UI
local Safe = K.Safe
local C = { asked = {} }
K.Companions = C

C.KINDS = {
  pet   = { label = "Pet",   icon = "Interface\\Icons\\Ability_Hunter_Pet_Wolf" },
  mount = { label = "Mount", icon = "Interface\\Icons\\Ability_Mount_RidingHorse" },
}
C.KIND_ORDER = { "pet", "mount" }

C.LIMITS = { name = 60, title = 80, glance = 160, desc = 1500, bindings = 8, count = 16 }
local SHARED_DESC = 1200     -- characters of description sent to others
local ASK_GAP = 120          -- seconds between asking the same owner for their companions

---------------------------------------------------------------------------
-- Your companions
---------------------------------------------------------------------------
K:On("LOGIN", function() K.db.companions = K.db.companions or {} end)

-- K.db.companions[charKey] = { [id] = companion }
function C:All()
  if not K.db then return {} end
  K.db.companions = K.db.companions or {}
  local key = K:CharKey()
  if not key then return {} end
  K.db.companions[key] = K.db.companions[key] or {}
  return K.db.companions[key]
end

function C:Get(id) return id and self:All()[id] or nil end

-- Your companions as a list, oldest first (the order you made them in).
function C:Sorted()
  local out = {}
  for id, c in pairs(self:All()) do
    c.id = id
    c.bindings = c.bindings or {}
    out[#out + 1] = c
  end
  table.sort(out, function(a, b)
    if (a.t or 0) ~= (b.t or 0) then return (a.t or 0) < (b.t or 0) end
    return a.id < b.id
  end)
  return out
end

function C:Count()
  local n = 0
  for _ in pairs(self:All()) do n = n + 1 end
  return n
end

-- Something changed: tell the page, and republish once typing settles.
function C:Changed()
  K:Fire("COMPANIONS")
  if K.Comm and K.Comm.SchedulePublish then K.Comm:SchedulePublish() end
end

function C:New(kind, name)
  if self:Count() >= self.LIMITS.count then return nil end
  kind = self.KINDS[kind or ""] and kind or "pet"
  local all = self:All()
  local id
  repeat id = ("c%d%03d"):format(time(), math.random(0, 999)) until not all[id]
  local c = { id = id, kind = kind, name = name or "", title = "", glance = "", desc = "",
              icon = self.KINDS[kind].icon, bindings = {}, t = time() }
  all[id] = c
  self:Changed()
  return c
end

function C:Delete(id)
  self:All()[id] = nil
  self:Changed()
end

function C:IsBound(c, name)
  local low = name:lower()
  for _, b in ipairs(c.bindings or {}) do if b:lower() == low then return true end end
  return false
end

-- Bind a pet or mount name. Returns true, or false and a reason.
function C:Bind(c, name)
  name = strtrim(name or "")
  if name == "" then return false, "Type a name first." end
  if #name > 60 then return false, "That name is too long." end
  c.bindings = c.bindings or {}
  if self:IsBound(c, name) then return false, name .. " is already bound." end
  if #c.bindings >= self.LIMITS.bindings then return false, "That's as many names as one companion can hold." end
  -- A name belongs to one companion at a time
  for _, other in pairs(self:All()) do
    if other ~= c and self:IsBound(other, name) then self:Unbind(other, name, true) end
  end
  c.bindings[#c.bindings + 1] = name
  self:Changed()
  return true
end

function C:Unbind(c, name, quiet)
  local low = name:lower()
  for i = #(c.bindings or {}), 1, -1 do
    if c.bindings[i]:lower() == low then table.remove(c.bindings, i) end
  end
  if not quiet then self:Changed() end
end

-- Your current pet's name (hunter and warlock pets), or nil.
function C:CurrentPetName()
  if not UnitExists("pet") then return nil end
  local n = UnitName("pet")
  if Safe(n) and type(n) == "string" and n ~= "" and n ~= UNKNOWNOBJECT then return n end
end

-- Helpful auras on a unit: { { name, icon, duration, spellId }, ... }
local function Auras(unit)
  local out = {}
  for i = 1, 40 do
    local name, icon, duration, spellId
    if C_UnitAuras and C_UnitAuras.GetAuraDataByIndex then
      local ok, a = pcall(C_UnitAuras.GetAuraDataByIndex, unit, i, "HELPFUL")
      if not ok or type(a) ~= "table" then break end
      name, icon, duration, spellId = a.name, a.icon, a.duration, a.spellId
    elseif UnitBuff then
      local ok, n, ic, _, _, dur, _, _, _, _, sid = pcall(UnitBuff, unit, i)
      if not ok or not n then break end
      name, icon, duration, spellId = n, ic, dur, sid
    else
      break
    end
    if Safe(name) and type(name) == "string" and name ~= "" then
      out[#out + 1] = { name = name, icon = Safe(icon) and icon or nil,
                        duration = Safe(duration) and duration or nil, spellId = Safe(spellId) and spellId or nil }
    end
  end
  return out
end

-- The aura that is probably your mount: { name, icon }s to choose from, or nil when not mounted.
function C:MountCandidates()
  if not IsMounted or not IsMounted() then return nil end
  local list, sure = {}, {}
  for _, a in ipairs(Auras("player")) do
    local isMount = false
    if a.spellId and C_MountJournal and C_MountJournal.GetMountFromSpell then
      local ok, mountID = pcall(C_MountJournal.GetMountFromSpell, a.spellId)
      isMount = ok and mountID ~= nil
    end
    if isMount then sure[#sure + 1] = a
    elseif not a.duration or a.duration == 0 then list[#list + 1] = a end
  end
  return #sure > 0 and sure or list
end

---------------------------------------------------------------------------
-- Icons
---------------------------------------------------------------------------
-- A texture to show for a companion (file ID or path), never nil.
function C.IconOf(c)
  local icon = c and c.icon
  if type(icon) == "number" or (type(icon) == "string" and icon ~= "") then return icon end
  local kind = c and C.KINDS[c.kind or ""] or C.KINDS.pet
  return kind.icon
end

-- Icons from other players: file IDs or game icons only.
local function ValidIcon(v)
  if type(v) ~= "string" or v == "" or #v > 120 then return nil end
  local n = tonumber(v)
  if n then return n > 0 and math.floor(n) or nil end
  if v:find("^[%w_%-]+$") then return "Interface\\Icons\\" .. v end
  if v:lower():find("^interface\\icons\\[%w_%-]+$") then return v end
  return nil
end
C.ValidIcon = ValidIcon

---------------------------------------------------------------------------
-- Sharing over MSP: "KA" = "1" followed by "~record" per companion, where a
-- record is kind^bindings^name^title^icon^glance^desc (bindings joined by ";")
-- and the special characters inside fields are %XX-escaped.
---------------------------------------------------------------------------
local function Esc(s)
  return (tostring(s or ""):gsub("[%%%^~;`|]", function(ch) return ("%%%02X"):format(ch:byte()) end))
end
local function Unesc(s)
  return (tostring(s or ""):gsub("%%(%x%x)", function(h) return string.char(tonumber(h, 16)) end))
end

function C:Serialize()
  local parts = { "1" }
  for _, c in ipairs(self:Sorted()) do
    local binds = {}
    for _, b in ipairs(c.bindings) do binds[#binds + 1] = Esc(b) end
    local name = strtrim(c.name or "")
    if name ~= "" then
      parts[#parts + 1] = "~" .. table.concat({
        c.kind == "mount" and "mount" or "pet",
        table.concat(binds, ";"),
        Esc(name:sub(1, self.LIMITS.name)),
        Esc(strtrim(c.title or ""):sub(1, self.LIMITS.title)),
        Esc(c.icon and tostring(c.icon) or ""),
        Esc(strtrim(c.glance or ""):sub(1, self.LIMITS.glance)),
        Esc(strtrim(c.desc or ""):sub(1, SHARED_DESC)),
      }, "^")
    end
  end
  return table.concat(parts)
end

function C.Deserialize(s)
  if type(s) ~= "string" or s:sub(1, 1) ~= "1" then return nil end
  local list = {}
  for rec in s:gmatch("~([^~]*)") do
    if #list >= C.LIMITS.count then break end
    local f = {}
    for part in (rec .. "^"):gmatch("([^%^]*)%^") do f[#f + 1] = part end
    local binds = {}
    for b in (f[2] or ""):gmatch("[^;]+") do
      if #binds < C.LIMITS.bindings then
        local name = strtrim(Unesc(b))
        if name ~= "" then binds[#binds + 1] = name end
      end
    end
    local c = {
      kind = f[1] == "mount" and "mount" or "pet", bindings = binds,
      name = Unesc(f[3]):sub(1, C.LIMITS.name), title = Unesc(f[4]):sub(1, C.LIMITS.title),
      icon = ValidIcon(Unesc(f[5])), glance = Unesc(f[6]):sub(1, C.LIMITS.glance),
      desc = Unesc(f[7]):sub(1, SHARED_DESC),
    }
    if strtrim(c.name) ~= "" then list[#list + 1] = c end
  end
  return list
end

K:AddProfileField({
  publish = function(my) my.KA = C:Serialize() end,
  read = function(fields, out)
    local v = fields.KA
    -- Always a non-empty table, so an emptied list replaces the old one.
    if type(v) == "string" and v ~= "" then out.companions = { v = 1, list = C.Deserialize(v) or {} } end
  end,
  full = { "KA" },
})

---------------------------------------------------------------------------
-- Looking companions up
---------------------------------------------------------------------------
local function CompanionsOf(owner, isMe)
  if isMe then return C:Sorted() end
  local reg = K:ProfileOf(owner)
  local comp = reg and reg.profile and reg.profile.companions
  return comp and comp.list, reg
end

-- The owner's companion bound to this pet or mount name (kind optional).
function C:Find(owner, unitName, isMe, kind)
  local list, reg = CompanionsOf(owner, isMe)
  if not list or not unitName then return nil, reg end
  for _, c in ipairs(list) do
    if (not kind or c.kind == kind) and strtrim(c.name or "") ~= "" and self:IsBound(c, unitName) then return c, reg end
  end
  return nil, reg
end

-- Ask an owner for their companions (throttled), so the pet's tooltip can fill in.
function C:Ask(owner)
  local key = K.NameKey(owner)
  if not key or not msp or type(msp.Request) ~= "function" then return end
  if IsInInstance() then return end
  if C_ChatInfo and C_ChatInfo.InChatMessagingLockdown and C_ChatInfo.InChatMessagingLockdown() then return end
  local now = GetTime()
  if self.asked[key] and now - self.asked[key] < ASK_GAP then return end
  self.asked[key] = now
  self.waiting = key
  pcall(msp.Request, msp, owner, { "TT", "KA" })
end

---------------------------------------------------------------------------
-- Tooltips
---------------------------------------------------------------------------
local OWNER_PATTERNS
local function OwnerPatterns()
  if OWNER_PATTERNS then return OWNER_PATTERNS end
  OWNER_PATTERNS = {}
  for _, g in ipairs({ "UNITNAME_TITLE_PET", "UNITNAME_TITLE_MINION", "UNITNAME_TITLE_GUARDIAN",
                       "UNITNAME_TITLE_COMPANION", "UNITNAME_TITLE_CHARM", "UNITNAME_TITLE_CREATION" }) do
    local fmt = rawget(_G, g)
    if type(fmt) == "string" and fmt:find("%s", 1, true) then
      local p = fmt:gsub("([%(%)%.%+%-%*%?%[%]%^%$%%])", "%%%1")
      p = p:gsub("%%%%s", "(.+)")
      OWNER_PATTERNS[#OWNER_PATTERNS + 1] = "^" .. p .. "$"
    end
  end
  return OWNER_PATTERNS
end

-- Who owns this pet: from its owner's GUID when the client tells us, else
-- from the "Name's Pet" line on the tooltip.
local function OwnerOf(unit, tooltip)
  local ownerGUID = rawget(_G, "UnitOwnerGUID")
  if ownerGUID and GetPlayerInfoByGUID then
    local ok, guid = pcall(ownerGUID, unit)
    if ok and Safe(guid) and type(guid) == "string" and guid ~= "" then
      local ok2, _, _, _, _, _, name, realm = pcall(GetPlayerInfoByGUID, guid)
      if ok2 and Safe(name) and type(name) == "string" and name ~= "" then
        if Safe(realm) and type(realm) == "string" and realm ~= "" then return name .. "-" .. realm end
        return name
      end
    end
  end
  local tname = tooltip.GetName and tooltip:GetName()
  if not tname then return nil end
  for i = 2, math.min(4, tooltip:NumLines() or 0) do
    local fs = _G[tname .. "TextLeft" .. i]
    local text = fs and fs:GetText()
    if Safe(text) and type(text) == "string" then
      for _, pat in ipairs(OwnerPatterns()) do
        local owner = text:match(pat)
        if owner and owner ~= "" then return owner end
      end
    end
  end
end

local function OwnerName(owner, reg, isMe)
  if isMe then return K:DisplayName() end
  local p = reg and reg.profile
  local rp = p and strtrim(UI.Clean(p.rpName or "")) or ""
  if rp ~= "" then return rp end
  return Ambiguate and Ambiguate(owner, "none") or owner
end

local function Trim(text, n)
  text = strtrim((UI.Clean(text or ""):gsub("%s+", " ")))
  if #text > n then
    local cut = text:sub(1, n):match("^(.*)%s") or text:sub(1, n)
    text = cut .. "..."
  end
  return text
end

local GOLD, TEAL, SOFT = { 1, 0.86, 0.55 }, { 0.30, 0.72, 0.68 }, { 0.80, 0.71, 0.51 }

-- The companion section: a big icon beside the name, title, owner, glance and a taste of the story.
local function AddSection(tooltip, c, ownerName, riding)
  local name = strtrim(UI.Clean(c.name or ""))
  if name == "" then return end
  local icon = C.IconOf(c)
  if not riding then
    local first = tooltip.GetName and _G[(tooltip:GetName() or "") .. "TextLeft1"]
    if first then first:SetText(name) end
  end
  tooltip:AddLine(" ")
  tooltip:AddLine(("|T%s:32:32:0:0:64:64:5:59:5:59|t  %s%s"):format(tostring(icon), riding and "Riding " or "", name),
    GOLD[1], GOLD[2], GOLD[3])
  local title = strtrim(UI.Clean(c.title or ""))
  if title ~= "" then tooltip:AddLine(title, TEAL[1], TEAL[2], TEAL[3], true) end
  if not riding then
    tooltip:AddLine(("|T%s:12:12|t %s of %s"):format(K.ICON, c.kind == "mount" and "Mount" or "Companion", ownerName),
      SOFT[1], SOFT[2], SOFT[3])
  end
  local glance = strtrim(UI.Clean(c.glance or ""))
  if glance ~= "" then tooltip:AddLine("\"" .. Trim(glance, 160) .. "\"", 0.92, 0.90, 0.84, true) end
  local desc = Trim(c.desc, 220)
  if desc ~= "" then tooltip:AddLine(desc, 0.70, 0.70, 0.70, true) end
end

-- Pets: your own, or another player's.
local function OnUnitTooltip(tooltip)
  if tooltip ~= GameTooltip then return end
  local ok, _, unit = pcall(tooltip.GetUnit, tooltip)
  if not ok or not unit or not Safe(unit) or not UnitExists(unit) then return end
  local isPlayer = UnitIsPlayer(unit)
  if not Safe(isPlayer) or isPlayer then return end
  local isMe = UnitIsUnit(unit, "pet")
  if not (Safe(isMe) and isMe) then
    isMe = false
    local other = UnitIsOtherPlayersPet and UnitIsOtherPlayersPet(unit)
    if not (Safe(other) and other) then
      local pc = UnitPlayerControlled(unit)
      if not (Safe(pc) and pc) then return end
    end
  end
  local petName = UnitName(unit)
  if not Safe(petName) or type(petName) ~= "string" or petName == "" then return end
  local owner = isMe and K:MyName() or OwnerOf(unit, tooltip)
  if not owner then return end
  if not isMe then
    if K.NameKey(owner) == K.NameKey(K:MyName()) then isMe = true
    elseif K:IsIgnored(owner) then return end
  end
  local c, reg = C:Find(owner, petName, isMe)
  if c then
    AddSection(tooltip, c, OwnerName(owner, reg, isMe), false)
    tooltip:Show()
  elseif not isMe and not (reg and reg.profile and reg.profile.companions) then
    C.waitingPet = petName
    C:Ask(owner)
  end
end

-- Mounts: a line on the rider's tooltip when they ride a bound mount.
K:AddTooltipLines(function(tooltip, unit, name, profile, isMe)
  local list = isMe and C:Sorted() or (profile and profile.companions and profile.companions.list)
  if not list or #list == 0 then return end
  local mounts = {}
  for _, c in ipairs(list) do if c.kind == "mount" and #(c.bindings or {}) > 0 then mounts[#mounts + 1] = c end end
  if #mounts == 0 then return end
  for _, a in ipairs(Auras(unit)) do
    for _, c in ipairs(mounts) do
      if C:IsBound(c, a.name) then
        AddSection(tooltip, c, nil, true)
        return
      end
    end
  end
end)

K:On("LOGIN", function()
  if TooltipDataProcessor and Enum and Enum.TooltipDataType then
    TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Unit, function(tt) K.Try("companions tooltip", OnUnitTooltip, tt) end)
  end
end)

-- When an owner's companions arrive while you're looking at their pet, redraw the tooltip.
K:On("REGISTRY", function(key)
  if key ~= C.waiting then return end
  C.waiting = nil
  if not GameTooltip:IsShown() or not UnitExists("mouseover") or UnitIsPlayer("mouseover") then return end
  local n = UnitName("mouseover")
  if Safe(n) and n == C.waitingPet then GameTooltip:SetUnit("mouseover") end
end)
