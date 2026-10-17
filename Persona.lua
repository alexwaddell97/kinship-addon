-- Kinship RP: persona data. Glances ("at first glance"), personality traits,
-- the profile icon, name colour and theme music: helpers to read, edit and
-- show them, and the MSP fields that carry them (PE, PS, IC, MU and a
-- coloured NA) in the formats other MSP profile addons read and write, so
-- players on either side see each other's.

local ADDON, ns = ...
local K = ns.K
local UI = K.UI
local Safe = K.Safe
local P = {}
K.Persona = P

P.MAX_GLANCES, P.MAX_TRAITS = 5, 10
P.MAX_TITLE, P.MAX_TEXT = 50, 800
P.MAX_PRESET_NAME = 32

local ICON_PATH = "Interface\\Icons\\"
P.DEFAULT_ICON = ICON_PATH .. "INV_Misc_QuestionMark"
local QUESTION_ID = 134400   -- INV_Misc_QuestionMark (LibRPMedia's own fallback)
local ICON_TYPE_MASK = 0xfc000000   -- LibRPMedia: icon ids with these bits are atlases

-- Total RP 3's default trait colours (left / right).
P.LEFT_COLOR  = { 1, 0.76, 0.42 }
P.RIGHT_COLOR = { 0.42, 0.65, 1 }

-- Total RP 3's eleven trait pairs, in its own id order (PS "id" values), with
-- the icons it shows for each side.
P.TRAIT_PRESETS = {
  { "Chaotic", "Lawful", "Ability_Rogue_WrongfullyAccused", "Ability_Paladin_SanctifiedWrath" },
  { "Chaste", "Lustful", "INV_Belt_27", "Spell_Shadow_SummonSuccubus" },
  { "Forgiving", "Vindictive", "INV_RoseBouquet01", "Ability_Hunter_SniperShot" },
  { "Altruistic", "Selfish", "INV_Misc_Gift_02", "INV_Misc_Coin_02" },
  { "Truthful", "Deceitful", "INV_Misc_Toy_07", "Ability_Rogue_Disguise" },
  { "Gentle", "Brutal", "INV_ValentinesCandySack", "Ability_Warrior_Trauma" },
  { "Superstitious", "Rational", "Spell_Holy_HolyGuidance", "INV_Gizmo_02" },
  { "Renegade", "Paragon", "Ability_Rogue_HonorAmongstThieves", "INV_Misc_GroupNeedMore" },
  { "Cautious", "Impulsive", "Spell_Shadow_Brainwash", "Achievement_BG_CaptureFlag_EOS" },
  { "Ascetic", "Bon vivant", "INV_Misc_Food_PineNut", "INV_Misc_Food_99" },
  { "Valorous", "Spineless", "Ability_Paladin_BeaconOfLight", "Ability_Druid_Cower" },
}

-- Name colour swatches (the player's own choice, so fixed colours are fine).
P.NAME_COLORS = {
  { 0.96, 0.80, 0.42 }, { 0.92, 0.36, 0.30 }, { 0.96, 0.56, 0.26 }, { 0.44, 0.82, 0.48 },
  { 0.30, 0.74, 0.70 }, { 0.38, 0.62, 0.96 }, { 0.64, 0.48, 0.92 }, { 0.92, 0.50, 0.74 },
  { 0.86, 0.86, 0.88 }, { 0.70, 0.54, 0.36 }, { 0.58, 0.90, 0.96 }, { 0.98, 0.96, 0.78 },
}

-- Well-known game music, checked against LibRPMedia's data for this client
-- (Total RP 3's music list). Entries the client doesn't have are dropped at login.
P.MUSIC = {
  { id = 53221, name = "Lament of the Highborne", time = 172 },
  { id = 53202, name = "Stormwind",               time = 55 },
  { id = 53198, name = "Orgrimmar",               time = 69 },
  { id = 53192, name = "Ironforge",               time = 124 },
  { id = 53213, name = "Thunder Bluff",           time = 118 },
  { id = 53216, name = "Undercity",               time = 76 },
  { id = 53183, name = "Darnassus",               time = 40 },
  { id = 53737, name = "Alliance tavern",         time = 48 },
  { id = 53744, name = "Horde tavern",            time = 49 },
  { id = 53748, name = "Human tavern",            time = 93 },
  { id = 53453, name = "Enchanted forest",        time = 50 },
  { id = 53486, name = "Haunted woods",           time = 71 },
  { id = 53240, name = "Mystery",                 time = 61 },
  { id = 53224, name = "Angelic",                 time = 48 },
}

---------------------------------------------------------------------------
-- Small helpers
---------------------------------------------------------------------------
local function Trim(s) return type(s) == "string" and strtrim(s) or "" end
local function Clamp(v, lo, hi) return math.max(lo, math.min(hi, v)) end

local function HexColor(hex)
  if type(hex) ~= "string" then return nil end
  local r, g, b = hex:match("^(%x%x)(%x%x)(%x%x)$")
  if not r then return nil end
  return { tonumber(r, 16) / 255, tonumber(g, 16) / 255, tonumber(b, 16) / 255 }
end
P.HexColor = HexColor

function P.ColorHex(c)
  local function byte(v) return math.floor(Clamp(tonumber(v) or 1, 0, 1) * 255 + 0.5) end
  return ("%02x%02x%02x"):format(byte(c[1]), byte(c[2]), byte(c[3]))
end

local function ValidColor(c)
  return type(c) == "table" and type(c[1]) == "number" and type(c[2]) == "number" and type(c[3]) == "number"
end

function P.FormatTime(s)
  s = tonumber(s) or 0
  return ("%d:%02d"):format(math.floor(s / 60), s % 60)
end

---------------------------------------------------------------------------
-- Icons. An icon is a file ID (number), a texture path, a bare icon name
-- ("INV_Misc_Book_09") or an atlas name. These helpers draw any of them.
---------------------------------------------------------------------------
-- Returns the texture source and whether it is an atlas, or nil.
function P.IconSource(icon)
  if icon == nil or icon == "" then return nil end
  local n = tonumber(icon)
  if n then
    if n <= 0 or n ~= math.floor(n) then return nil end
    if bit and bit.band and bit.band(n, ICON_TYPE_MASK) ~= 0 then return nil end
    return n, false
  end
  if type(icon) ~= "string" or icon:find("[|:]") then return nil end
  if icon:find("[\\/]") then return icon, false end
  if C_Texture and C_Texture.GetAtlasInfo then
    local ok, info = pcall(C_Texture.GetAtlasInfo, icon)
    if ok and info then return icon, true end
  end
  if icon:find("^[%w_%-]+$") then return ICON_PATH .. icon, false end
  return nil
end

-- Draw an icon on a texture, cropped like a button icon. fallback is used
-- when the icon is missing or unusable.
function P.SetIcon(tex, icon, fallback)
  local src, atlas = P.IconSource(icon)
  if not src then src, atlas = P.IconSource(fallback or P.DEFAULT_ICON) end
  if atlas then
    tex:SetAtlas(src)
  else
    tex:SetTexture(src or P.DEFAULT_ICON)
    tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
  end
end

-- Inline markup for text: |T...|t (or |A...|a for an atlas).
function P.IconMarkup(icon, size)
  size = size or 16
  local src, atlas = P.IconSource(icon)
  if not src then src, atlas = P.DEFAULT_ICON, false end
  if atlas then return ("|A:%s:%d:%d|a"):format(src, size, size) end
  return ("|T%s:%d:%d:0:0:64:64:5:59:5:59|t"):format(tostring(src), size, size)
end

-- Icons for one side of a preset trait pair (nil for custom pairs).
function P.PresetIndex(left, right)
  left, right = Trim(left):lower(), Trim(right):lower()
  for i, t in ipairs(P.TRAIT_PRESETS) do
    if t[1]:lower() == left and t[2]:lower() == right then return i end
  end
end

function P.TraitIcons(trait)
  local i = trait and P.PresetIndex(trait.left, trait.right)
  if not i then return nil end
  local t = P.TRAIT_PRESETS[i]
  return ICON_PATH .. t[3], ICON_PATH .. t[4]
end

---------------------------------------------------------------------------
-- Reading a profile (yours or someone else's)
---------------------------------------------------------------------------
function P.HasContent(g)
  return type(g) == "table" and (Trim(g.title) ~= "" or Trim(g.text) ~= "" or P.IconSource(g.icon) ~= nil)
end

-- Glances that are switched on (missing `active` counts as on). all = every glance.
function P.Glances(p, all)
  local out = {}
  if type(p) ~= "table" or type(p.glances) ~= "table" then return out end
  for _, g in ipairs(p.glances) do
    if type(g) == "table" and (all or g.active ~= false) and P.HasContent(g) then out[#out + 1] = g end
    if #out >= P.MAX_GLANCES then break end
  end
  return out
end

function P.Traits(p)
  local out = {}
  if type(p) ~= "table" or type(p.traits) ~= "table" then return out end
  for _, t in ipairs(p.traits) do
    if type(t) == "table" and Trim(t.left) ~= "" and Trim(t.right) ~= "" then out[#out + 1] = t end
  end
  return out
end

function P.TraitValue(t) return Clamp(math.floor((tonumber(t and t.value) or 10) + 0.5), 0, 20) end
function P.LeftColor(t) return ValidColor(t and t.leftColor) and t.leftColor or P.LEFT_COLOR end
function P.RightColor(t) return ValidColor(t and t.rightColor) and t.rightColor or P.RIGHT_COLOR end

-- "75% Chaotic", "Balanced"
function P.TraitHint(t)
  local v = P.TraitValue(t)
  if v == 10 then return "Balanced" end
  if v > 10 then return ("%d%% %s"):format(v * 5, Trim(t.left)) end
  return ("%d%% %s"):format((20 - v) * 5, Trim(t.right))
end

-- r, g, b of a profile's name colour, or nil.
function P.NameColor(p)
  local c = type(p) == "table" and p.nameColor
  if ValidColor(c) then return Clamp(c[1], 0, 1), Clamp(c[2], 0, 1), Clamp(c[3], 0, 1) end
end

function P.Music(p)
  local m = type(p) == "table" and tonumber(p.music)
  if m and m > 0 then return math.floor(m) end
end

function P.MusicLabel(id)
  id = tonumber(id)
  if not id then return nil end
  for _, m in ipairs(P.MUSIC) do if m.id == id then return m.name end end
  return ("Music file %d"):format(id)
end

-- A rich tooltip for one glance: icon and title, then the text.
function P.GlanceTooltip(owner, g, other, anchor)
  if not g then return end
  local function C(s) return other and UI.Clean(s) or (s or "") end
  local title = strtrim(C(g.title))
  if title == "" then title = "At first glance" end
  GameTooltip:SetOwner(owner, anchor or "ANCHOR_NONE")
  if not anchor then
    GameTooltip:ClearAllPoints()
    GameTooltip:SetPoint("TOPLEFT", owner, "BOTTOMLEFT", 0, -6)
  end
  if GameTooltip.SetMinimumWidth then GameTooltip:SetMinimumWidth(220) end
  GameTooltip:SetText(P.IconMarkup(g.icon, 22) .. "  " .. title, 1, 0.82, 0)
  local text = strtrim(C(g.text))
  if text ~= "" then GameTooltip:AddLine(text, 0.95, 0.93, 0.88, true) end
  GameTooltip:Show()
end

function P.HideTooltip()
  if GameTooltip.SetMinimumWidth then GameTooltip:SetMinimumWidth(0) end
  GameTooltip:Hide()
end

---------------------------------------------------------------------------
-- Editing your own persona. Every change fires PROFILE (which republishes).
---------------------------------------------------------------------------
function P:MyGlances()
  local p = K:Profile()
  if type(p.glances) ~= "table" then p.glances = {} end
  return p.glances
end

function P:AddGlance()
  local list = self:MyGlances()
  if #list >= self.MAX_GLANCES then return nil end
  list[#list + 1] = { title = "", text = "", active = true }
  K:Fire("PROFILE")
  return #list
end

function P:RemoveGlance(i)
  local list = self:MyGlances()
  if not list[i] then return end
  table.remove(list, i)
  K:Fire("PROFILE")
end

function P:MoveGlance(i, delta)
  local list, j = self:MyGlances(), i + delta
  if not list[i] or not list[j] then return i end
  list[i], list[j] = list[j], list[i]
  K:Fire("PROFILE")
  return j
end

function P:MyTraits()
  local p = K:Profile()
  if type(p.traits) ~= "table" then p.traits = {} end
  return p.traits
end

function P:HasTrait(left, right)
  left, right = Trim(left):lower(), Trim(right):lower()
  for _, t in ipairs(self:MyTraits()) do
    if Trim(t.left):lower() == left and Trim(t.right):lower() == right then return true end
  end
  return false
end

function P:AddTrait(left, right)
  left, right = Trim(left):gsub("[%]=\"\r\n]", ""), Trim(right):gsub("[%]=\"\r\n]", "")
  left, right = strtrim(left), strtrim(right)
  local list = self:MyTraits()
  if left == "" or right == "" or #list >= self.MAX_TRAITS or self:HasTrait(left, right) then return false end
  list[#list + 1] = { left = left, right = right, value = 10 }
  K:Fire("PROFILE")
  return true
end

function P:RemoveTrait(i)
  local list = self:MyTraits()
  if list[i] then table.remove(list, i); K:Fire("PROFILE") end
end

function P:MoveTrait(i, delta)
  local list, j = self:MyTraits(), i + delta
  if not list[i] or not list[j] then return end
  list[i], list[j] = list[j], list[i]
  K:Fire("PROFILE")
end

---------------------------------------------------------------------------
-- Glance presets (account-wide, in K.db.glancePresets)
---------------------------------------------------------------------------
function P:PresetNames()
  local out = {}
  for name in pairs(K.db.glancePresets or {}) do out[#out + 1] = name end
  table.sort(out, function(a, b) return a:lower() < b:lower() end)
  return out
end

function P:SavePreset(name)
  name = Trim(name):sub(1, self.MAX_PRESET_NAME)
  if name == "" then return false end
  K.db.glancePresets[name] = { glances = CopyTable(self:MyGlances()), t = time() }
  K:Fire("GLANCE_PRESETS")
  return true
end

function P:LoadPreset(name)
  local pr = K.db.glancePresets[name]
  if type(pr) ~= "table" then return false end
  K:Profile().glances = CopyTable(type(pr.glances) == "table" and pr.glances or {})
  K:Fire("PROFILE")
  return true
end

function P:DeletePreset(name)
  if K.db.glancePresets[name] then
    K.db.glancePresets[name] = nil
    K:Fire("GLANCE_PRESETS")
  end
end

---------------------------------------------------------------------------
-- Theme music
---------------------------------------------------------------------------
function P:PlayMusic(id)
  id = tonumber(id)
  if not id or id <= 0 then return false end
  if StopMusic then pcall(StopMusic) end
  local ok = PlayMusic and pcall(PlayMusic, math.floor(id))
  self.playing = ok and math.floor(id) or nil
  K:Fire("PERSONA_MUSIC")
  return ok and true or false
end

function P:StopMusic()
  if StopMusic then pcall(StopMusic) end
  self.playing = nil
  K:Fire("PERSONA_MUSIC")
end

function P:ToggleMusic(id)
  id = tonumber(id)
  if id and self.playing == math.floor(id) then self:StopMusic() else self:PlayMusic(id) end
end

---------------------------------------------------------------------------
-- MSP: writing, in the field formats shared by the MSP profile addons
---------------------------------------------------------------------------
-- PE: glances joined by "\n\n---\n\n", each "|T<icon>:32:32|t\n#<title>\n\n<text>".
local function PeekIcon(icon)
  local src, atlas = P.IconSource(icon)
  if src and atlas then return ("|A:%s:32:32|a"):format(src) end
  if type(src) == "number" then return ("|T%d:32:32|t"):format(src) end
  local name = type(src) == "string" and src:lower():match("^interface\\icons\\([%w_%-]+)$")
  return "|TInterface\\Icons\\" .. (name or "INV_Misc_QuestionMark") .. ":32:32|t"
end

local function WritePeeks(p)
  local out = {}
  for _, g in ipairs(P.Glances(p)) do
    if #out > 0 then out[#out + 1] = "\n\n---\n\n" end
    out[#out + 1] = PeekIcon(g.icon)
    out[#out + 1] = "\n"
    local title = Trim(g.title):gsub("[\r\n]+", " ")
    if title ~= "" then out[#out + 1] = "#" .. title .. "\n\n" end
    local text = Trim(g.text):gsub("\n%-%-%-", "\n- - -")
    out[#out + 1] = text
  end
  local s = table.concat(out)
  return s ~= "" and s or nil
end

-- PS: one [trait ...] per line. Preset pairs go by id (so Total RP 3 shows them
-- in its own language, with its icons); custom pairs, or presets with your own
-- colours, carry names and colours. Value 0-1 is the left trait's share.
local PS_BUILTIN = "[trait value=\"%.2f\" id=\"%d\"]"
local PS_CUSTOM = "[trait value=\"%.2f\" left-name=\"%s\" left-icon=\"%d\" left-color=\"%s\""
  .. " right-name=\"%s\" right-icon=\"%d\" right-color=\"%s\"]"

local function WriteTraits(p)
  local out = {}
  for _, t in ipairs(P.Traits(p)) do
    local value = P.TraitValue(t) / 20
    local id = P.PresetIndex(t.left, t.right)
    if id and not ValidColor(t.leftColor) and not ValidColor(t.rightColor) then
      out[#out + 1] = PS_BUILTIN:format(value, id)
    else
      local left = Trim(t.left):gsub("[%]=\"\r\n]", "")
      local right = Trim(t.right):gsub("[%]=\"\r\n]", "")
      out[#out + 1] = PS_CUSTOM:format(value, left, QUESTION_ID, P.ColorHex(P.LeftColor(t)),
        right, QUESTION_ID, P.ColorHex(P.RightColor(t)))
    end
  end
  return #out > 0 and table.concat(out, "\n") or nil
end

-- IC: a file ID as a number string (as Total RP 3 sends it), or an icon name.
local function WriteIcon(icon)
  local src, atlas = P.IconSource(icon)
  if not src then return nil end
  if atlas then return src end
  if type(src) == "number" then return tostring(src) end
  return src:lower():match("^interface\\icons\\([%w_%-]+)$")
end

---------------------------------------------------------------------------
-- MSP: reading
---------------------------------------------------------------------------
local function ReadIcon(v)
  if type(v) ~= "string" or v == "" then return nil end
  local n = tonumber(v)
  if n then
    if n > 0 and n == math.floor(n) and not (bit and bit.band and bit.band(n, ICON_TYPE_MASK) ~= 0) then return n end
    return nil
  end
  local name = v:match("^[Ii][Nn][Tt][Ee][Rr][Ff][Aa][Cc][Ee]\\[Ii][Cc][Oo][Nn][Ss]\\([%w_%-]+)$") or v:match("^([%w_%-]+)$")
  return name and (ICON_PATH .. name) or nil
end
P.ReadIcon = ReadIcon

local function ReadPeek(chunk)
  local icon
  local fid = chunk:match("|T(%d+)[:|]")
  if fid then icon = ReadIcon(fid) end
  if not icon then
    local name = chunk:match("|T[Ii][Nn][Tt][Ee][Rr][Ff][Aa][Cc][Ee][\\/][Ii][Cc][Oo][Nn][Ss][\\/]([%w_%-]+)")
    if name then icon = ICON_PATH .. name end
  end
  if not icon then
    local atlas = chunk:match("|A:([%w_%-%.]+):")
    if atlas then icon = atlas end
  end
  local body = chunk:gsub("^%s*|T.-|t", "", 1)
  body = body:gsub("^%s*|A.-|a", "", 1)
  body = body:gsub("^%s+", "")
  local title = ""
  local t, rest = body:match("^#+ *([^\n]*)\n?(.*)$")
  if t then title, body = strtrim(t), rest end
  body = body:gsub("{[^}\n]*}", "")   -- Total RP 3 markup tags
  local text = strtrim(body)
  if title == "" and text == "" and not icon then return nil end
  return { icon = icon, title = title:sub(1, 120), text = text:sub(1, 2000), active = true }
end

local function ReadPeeks(value)
  if type(value) ~= "string" or value == "" then return nil end
  local out, index = {}, 1
  for _ = 1, P.MAX_GLANCES do
    local s, e = value:find("\n\n---\n\n", index, true)
    local g = ReadPeek(s and value:sub(index, s - 1) or value:sub(index))
    if g then out[#out + 1] = g end
    if not s then break end
    index = e + 1
  end
  return #out > 0 and out or nil
end

local function ReadTraits(value)
  if type(value) ~= "string" or value == "" then return nil end
  local out = {}
  for block in value:gmatch("%[trait [^%]]-%]") do
    local a = {}
    for key, v in block:gmatch("([%w_%-]+)=\"([^\"]*)\"") do a[key] = v end
    local share = tonumber(a.value)
    local id = tonumber(a.id)
    local preset = id and P.TRAIT_PRESETS[id]
    local left, right
    if preset then left, right = preset[1], preset[2]
    else left, right = Trim(a["left-name"]), Trim(a["right-name"]) end
    if share and left ~= "" and right ~= "" then
      local t = { left = left:sub(1, 40), right = right:sub(1, 40), value = Clamp(math.floor(share * 20 + 0.5), 0, 20) }
      if not preset then t.leftColor, t.rightColor = HexColor(a["left-color"]), HexColor(a["right-color"]) end
      out[#out + 1] = t
      if #out >= 20 then break end
    end
  end
  return #out > 0 and out or nil
end

-- NA wrapped in one colour ("|cffRRGGBBName|r") gives the name colour.
local function SplitName(na)
  if type(na) ~= "string" then return nil end
  local hex, inner = na:match("^|c%x%x(%x%x%x%x%x%x)(.-)|r$")
  if hex and not inner:find("|c", 1, true) then return HexColor(hex), inner end
end

K:AddProfileField({
  publish = function(my, p)
    my.PE = WritePeeks(p)
    my.PS = WriteTraits(p)
    my.IC = WriteIcon(p.icon)
    local mu = P.Music(p)
    my.MU = mu and tostring(mu) or nil
    local r, g, b = P.NameColor(p)
    if r and type(my.NA) == "string" and my.NA ~= "" then
      my.NA = ("|cff%s%s|r"):format(P.ColorHex({ r, g, b }), my.NA)
    end
  end,
  read = function(fields, out)
    out.glances = ReadPeeks(fields.PE)
    out.traits = ReadTraits(fields.PS)
    out.icon = ReadIcon(fields.IC)
    local mu = tonumber(fields.MU)
    out.music = (mu and mu > 0) and math.floor(mu) or nil
    local color, inner = SplitName(fields.NA)
    if color then out.nameColor, out.rpName = color, inner end
  end,
  full = { "PE", "PS", "MU", "IC" },
  tooltip = { "IC" },
})

---------------------------------------------------------------------------
-- Keeping stored profiles honest. The registry merge only takes non-empty
-- strings and tables, so a field someone cleared would linger and numbers
-- (icon, music) would never update: LibMSP tells us about both.
---------------------------------------------------------------------------
local CLEARS = { PE = "glances", PS = "traits", IC = "icon", MU = "music" }

local function Entry(name)
  if type(name) ~= "string" or not Safe(name) then return nil end
  local key = K.NameKey(name)
  local e = key and K.db and K.db.registry and K.db.registry[key]
  return (e and type(e.profile) == "table") and e or nil
end

local function OnFieldUpdated(name, field, contents)
  if not CLEARS[field] and field ~= "NA" then return end
  local e = Entry(name)
  if not e then return end
  if field == "NA" then
    if not SplitName(contents) then e.profile.nameColor = nil end
  elseif contents == nil or contents == "" then
    e.profile[CLEARS[field]] = nil
  end
end

K:On("REGISTRY", function(key, entry)
  if type(entry) ~= "table" or type(entry.profile) ~= "table" or not msp or not msp.char then return end
  local char = type(entry.name) == "string" and rawget(msp.char, entry.name)
  local fields = char and rawget(char, "field")
  if not fields then return end
  local icon = ReadIcon(fields.IC)
  if icon then entry.profile.icon = icon end
  local mu = tonumber(fields.MU)
  if mu and mu > 0 then entry.profile.music = math.floor(mu) end
end)

---------------------------------------------------------------------------
-- Asking for glances. Comm fetches the tooltip fields; glances and music
-- are full-profile fields, so we ask for them when someone is targeted or
-- moused over. LibMSP only re-sends what changed.
---------------------------------------------------------------------------
local PERSONA_FIELDS = { "PE", "PS", "MU", "IC" }

local function Blocked()
  if IsInInstance() then return true end
  return C_ChatInfo and C_ChatInfo.InChatMessagingLockdown and C_ChatInfo.InChatMessagingLockdown()
end

function P:Request(name, fields)
  if not msp or type(msp.Request) ~= "function" or Blocked() then return end
  if type(name) ~= "string" or not Safe(name) or name == "" then return end
  if K:IsIgnored(name) or K.NameKey(name) == K.NameKey(K:MyName()) then return end
  pcall(msp.Request, msp, name, fields or PERSONA_FIELDS)
end

-- A moment after Comm's tooltip request, so first contact isn't skipped.
function P:RequestUnit(unit, fields)
  local exists = UnitExists(unit)
  if not Safe(exists) or not exists then return end
  local isPlayer, isMe = UnitIsPlayer(unit), UnitIsUnit(unit, "player")
  if not Safe(isPlayer) or not isPlayer or not Safe(isMe) or isMe then return end
  local name = GetUnitName(unit, true)
  if not Safe(name) or type(name) ~= "string" then return end
  C_Timer.After(1.2, function() P:Request(name, fields) end)
end

---------------------------------------------------------------------------
-- Start-up
---------------------------------------------------------------------------
K:On("LOGIN", function()
  K.db.glancePresets = K.db.glancePresets or {}

  -- Drop curated music this client doesn't have.
  local known = C_UIFileAsset and C_UIFileAsset.IsKnownFile
  if type(known) == "function" then
    local keep = {}
    for _, m in ipairs(P.MUSIC) do
      local ok, has = pcall(known, m.id)
      if not ok or has then keep[#keep + 1] = m end
    end
    P.MUSIC = keep
  end

  if msp and msp.callback then
    msp.callback.updated = msp.callback.updated or {}
    table.insert(msp.callback.updated, function(name, field, contents) K.Try("persona", OnFieldUpdated, name, field, contents) end)
  end

  local ev = CreateFrame("Frame")
  ev:RegisterEvent("UPDATE_MOUSEOVER_UNIT")
  ev:RegisterEvent("PLAYER_TARGET_CHANGED")
  ev:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_TARGET_CHANGED" then P:RequestUnit("target")
    elseif not K.db.targetBar or K.db.targetBar.tooltip ~= false then P:RequestUnit("mouseover", { "PE", "IC" }) end
  end)
end)
