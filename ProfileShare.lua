-- Kinship RP: share a profile as text. Export turns the active profile into a
-- copyable code; import reads one back as a new profile.
--
-- Code format:  KINSHIP1:<flag><checksum>:<base64>
--   flag      p = plain, z = deflate-compressed first (when the client offers
--             C_EncodingUtil; every code is round-trip checked before use)
--   checksum  Adler-32 (8 hex digits) of the serialised table, so damaged or
--             cut-off codes are caught before anything is imported
--   payload   { v = 1, name, by, t, profile }, serialised with Chomp's
--             Serialize (plain data only) and read back with its Deserialize,
--             a real parser: nothing in a code is ever run as Lua.
-- Imported text is cleaned (no links or textures) and limited in size.

local ADDON, ns = ...
local K = ns.K
local UI = K.UI
local S = {}
K.ProfileShare = S

local HEADER = "KINSHIP1:"
-- MAX_STRING is bytes: the Profile page allows 20,000 letters, and accented
-- or non-Latin letters take up to 4 bytes each. MAX_RAW caps the data inside
-- a code and MAX_ZIP the compressed form, so a pasted code can't balloon.
local MAX_CODE, MAX_STRING, MAX_NODES = 600000, 80000, 6000
local MAX_RAW, MAX_ZIP = 450000, 160000
local GOOD, BAD = { 0.40, 0.80, 0.48 }, { 0.90, 0.36, 0.30 }

---------------------------------------------------------------------------
-- Base64 and checksum
---------------------------------------------------------------------------
local B64 = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
local ENC, DEC = {}, {}
for i = 1, 64 do
  local c = B64:sub(i, i)
  ENC[i - 1] = c
  DEC[c:byte()] = i - 1
end

local function Encode64(s)
  local out, floor = {}, math.floor
  for i = 1, #s, 3 do
    local a, b, c = s:byte(i, i + 2)
    local v = a * 65536 + (b or 0) * 256 + (c or 0)
    out[#out + 1] = ENC[floor(v / 262144) % 64] .. ENC[floor(v / 4096) % 64]
      .. (b and ENC[floor(v / 64) % 64] or "=") .. (c and ENC[v % 64] or "=")
  end
  return table.concat(out)
end

local function Decode64(s)
  if #s % 4 ~= 0 then return nil end
  local out, floor, char = {}, math.floor, string.char
  for i = 1, #s, 4 do
    local a, b, c, d = s:byte(i, i + 3)
    local va, vb = DEC[a], DEC[b]
    local vc, vd = DEC[c], DEC[d]
    if not va or not vb or (c ~= 61 and not vc) or (d ~= 61 and not vd) or (c == 61 and d ~= 61) then return nil end
    local v = va * 262144 + vb * 4096 + (vc or 0) * 64 + (vd or 0)
    local b1, b2, b3 = floor(v / 65536) % 256, floor(v / 256) % 256, v % 256
    if vc and vd then out[#out + 1] = char(b1, b2, b3)
    elseif vc then out[#out + 1] = char(b1, b2)
    else out[#out + 1] = char(b1) end
  end
  return table.concat(out)
end

local function Adler(s)
  local a, b = 1, 0
  for i = 1, #s, 64 do
    for _, byte in ipairs({ s:byte(i, i + 63) }) do
      a = (a + byte) % 65521
      b = (b + a) % 65521
    end
  end
  return ("%04x%04x"):format(b, a)
end

---------------------------------------------------------------------------
-- Serialising and compressing
---------------------------------------------------------------------------
local function Serialize(t)
  local C = rawget(_G, "AddOn_Chomp")
  if C and C.Serialize then
    local ok, s = pcall(C.Serialize, t)
    if ok and type(s) == "string" then return s end
  end
end

local function Deserialize(s)
  local C = rawget(_G, "AddOn_Chomp")
  if C and C.Deserialize then
    local ok, t = pcall(C.Deserialize, s)
    if ok and type(t) == "table" then return t end
  end
end

local function Method()
  local EU = rawget(_G, "C_EncodingUtil")
  if type(EU) == "table" and EU.CompressString and EU.DecompressString and Enum and Enum.CompressionMethod
      and Enum.CompressionMethod.Deflate then
    return EU, Enum.CompressionMethod.Deflate
  end
end

local function Deflate(s)
  local EU, m = Method()
  if not EU then return nil end
  local ok, z = pcall(EU.CompressString, s, m)
  if not ok or type(z) ~= "string" then return nil end
  local ok2, back = pcall(EU.DecompressString, z, m)
  if ok2 and back == s then return z end
end

local function Inflate(z)
  local EU, m = Method()
  if not EU then return nil end
  local ok, s = pcall(EU.DecompressString, z, m)
  if ok and type(s) == "string" then return s end
end

-- The same building blocks for other codes (Backup.lua uses them).
S.Codec = { Encode64 = Encode64, Decode64 = Decode64, Adler = Adler, Serialize = Serialize,
            Deserialize = Deserialize, Deflate = Deflate, Inflate = Inflate }

-- Plain data only, within sensible limits. clean = text from a code (strip
-- links and textures, as for any text from another player).
local function Clean(v, depth, budget, clean)
  local tv = type(v)
  if tv == "string" then
    if #v > MAX_STRING then
      v = v:sub(1, MAX_STRING):gsub("[\192-\255][\128-\191]*$", "")
      budget.cut = (budget.cut or 0) + 1
    end
    return clean and UI.Clean(v) or v
  elseif tv == "number" then
    if v ~= v or v == math.huge or v == -math.huge then return nil end
    return v
  elseif tv == "boolean" then
    return v
  elseif tv == "table" then
    if depth > 4 then return nil end
    local out = {}
    for k, x in pairs(v) do
      budget.n = budget.n + 1
      if budget.n > MAX_NODES then break end
      local tk = type(k)
      local okKey = (tk == "string" and #k <= 64 and k:find("^[%w_]+$") ~= nil)
        or (tk == "number" and k >= 1 and k <= 1000 and k == math.floor(k))
      if okKey then
        local cx = Clean(x, depth + 1, budget, clean)
        if cx ~= nil then out[k] = cx end
      end
    end
    return out
  end
end

-- Returns the code and the size of the data inside it.
-- (and how many texts were too long and had to be cut).
function S:Encode(profile, name)
  local budget = { n = 0 }
  local data = Clean(profile, 1, budget, false) or {}
  data.source = nil
  local payload = { v = 1, name = tostring(name or "Profile"), by = K.VERSION, t = time(), profile = data }
  local text = Serialize(payload)
  if not text then return nil end
  local sum, flag, body = Adler(text), "p", text
  local z = Deflate(text)
  if z and #z < #text then flag, body = "z", z end
  local b64 = Encode64(body)
  local lines = { HEADER .. flag .. sum .. ":" }
  for i = 1, #b64, 64 do lines[#lines + 1] = b64:sub(i, i + 63) end
  return table.concat(lines, "\n"), #text, budget.cut or 0
end

-- Keep only the fields a profile has, each in the shape the rest of Kinship
-- expects; anything else in a code is dropped.
local function Str(v) return type(v) == "string" and v or nil end
local function Icon(v) return (type(v) == "string" or (type(v) == "number" and v > 0)) and v or nil end
local function Color(c)
  if type(c) ~= "table" then return nil end
  for i = 1, 3 do if type(c[i]) ~= "number" or c[i] < 0 or c[i] > 1 then return nil end end
  return { c[1], c[2], c[3] }
end

local function Shape(src)
  local p = {}
  for k, v in pairs(K.BlankProfile()) do
    if type(v) == "string" then p[k] = Str(src[k]) or v end
  end
  p.status, p.stance = Str(src.status), Str(src.stance)
  p.consent = {}
  if type(src.consent) == "table" then
    for _, f in ipairs(K.CONSENT) do
      local v = src.consent[f.key]
      if v == "1" or v == "2" or v == "3" then p.consent[f.key] = v end
    end
  end
  if type(src.glances) == "table" then
    p.glances = {}
    for _, g in ipairs(src.glances) do
      if #p.glances >= 5 then break end
      if type(g) == "table" then
        p.glances[#p.glances + 1] = { icon = Icon(g.icon), title = Str(g.title) or "", text = Str(g.text) or "",
          active = g.active ~= false }
      end
    end
  end
  if type(src.traits) == "table" then
    p.traits = {}
    for _, t in ipairs(src.traits) do
      if #p.traits >= 10 then break end
      if type(t) == "table" and Str(t.left) and Str(t.right) then
        local v = type(t.value) == "number" and math.max(0, math.min(20, t.value)) or 10
        p.traits[#p.traits + 1] = { left = t.left, right = t.right, value = v,
          leftColor = Color(t.leftColor), rightColor = Color(t.rightColor) }
      end
    end
  end
  p.icon = Icon(src.icon)
  p.nameColor = Color(src.nameColor)
  p.music = type(src.music) == "number" and src.music > 0 and math.floor(src.music) or nil
  return p
end

-- Returns { name, profile, by, t } or nil and a reason.
function S:Decode(code)
  if type(code) ~= "string" or strtrim(code) == "" then return nil, nil end
  if #code > MAX_CODE then return nil, "That's far too long to be a profile code." end
  local flat = code:gsub("%s+", "")
  local flag, sum, body = flat:match("KINSHIP1:([pz])(%x%x%x%x%x%x%x%x):([%w%+/=]+)$")
  if not flag then
    if flat:find("KINSHIP%d") and not flat:find("KINSHIP1:") then
      return nil, "This code comes from a newer version of Kinship. Update to import it."
    end
    if flat:find("KINSHIP1:") then return nil, "The code is incomplete. Copy all of it, from KINSHIP1 to the end." end
    return nil, "That doesn't look like a Kinship profile code."
  end
  local raw = Decode64(body)
  if not raw then return nil, "The code is damaged: some characters are missing or changed." end
  local tooBig = "That's far too much to be one profile."
  if flag == "z" then
    if #raw > MAX_ZIP then return nil, tooBig end
    raw = Inflate(raw)
    if not raw then return nil, "This code is compressed, and this game client can't open it." end
  end
  if #raw > MAX_RAW then return nil, tooBig end
  if Adler(raw) ~= sum:lower() then return nil, "The code is damaged or cut short. Copy all of it and try again." end
  local t = Deserialize(raw)
  if type(t) ~= "table" or type(t.profile) ~= "table" then return nil, "The code doesn't hold a profile." end

  local p = Shape(Clean(t.profile, 1, { n = 0 }, true) or {})
  for k, v in pairs(K.BlankProfile()) do
    if type(p[k]) ~= type(v) then p[k] = type(v) == "table" and {} or v end
  end
  if not K.STATUS[p.status] then p.status = "ooc" end
  if not K.STANCES[p.stance] then p.stance = "duel" end
  local name = type(t.name) == "string" and strtrim((UI.Clean(t.name):gsub("|", ""))) or ""
  if name == "" then name = "Imported" end
  return { name = name:sub(1, 24), profile = p, by = type(t.by) == "string" and t.by or nil,
           t = type(t.t) == "number" and t.t or nil }
end

local function UniqueName(list, name)
  name = strtrim(name or "")
  if name == "" then name = "Imported" end
  if not list[name] then return name end
  local n = 2
  while list[name .. " " .. n] do n = n + 1 end
  return name .. " " .. n
end

-- "Appearance, History, 3 glances" and the like.
local function Summary(p)
  local parts = {}
  for _, s in ipairs({ { "appearance", "Appearance" }, { "personality", "Personality" }, { "history", "History" } }) do
    local v = p[s[1]]
    if type(v) == "string" and strtrim(v) ~= "" then parts[#parts + 1] = s[2] end
  end
  if type(p.glances) == "table" and #p.glances > 0 then
    parts[#parts + 1] = #p.glances .. (#p.glances == 1 and " glance" or " glances")
  end
  if type(p.traits) == "table" and #p.traits > 0 then
    parts[#parts + 1] = #p.traits .. (#p.traits == 1 and " trait" or " traits")
  end
  return #parts > 0 and table.concat(parts, "  ·  ") or "No longer writing yet"
end

local function Size(n)
  if n < 1024 then return n .. " bytes" end
  return ("%.1f KB"):format(n / 1024)
end

---------------------------------------------------------------------------
-- The window
---------------------------------------------------------------------------
local W, H = 560, 484
local PW = W - 32

local function BuildExport(pg)
  local card = UI.Panel(pg)
  card:SetPoint("TOPLEFT", 16, -8)
  card:SetSize(PW, 66)
  card.ring = UI.Circle(card, 44, "ARTWORK", 0)
  card.ring:SetPoint("LEFT", 12, 0)
  UI:OnTheme(function(t) card.ring:SetVertexColor(t.accent[1], t.accent[2], t.accent[3], 1) end)
  card.face = card:CreateTexture(nil, "ARTWORK", nil, 1)
  card.face:SetSize(40, 40)
  card.face:SetPoint("CENTER", card.ring)
  UI.Round(card.face)
  card.name = UI.Text(card, "", "Title", "heading", PW - 190)
  card.name:SetPoint("TOPLEFT", 68, -14)
  card.name:SetWordWrap(false)
  card.sub = UI.Text(card, "", "Small", "subtle", PW - 190)
  card.sub:SetPoint("TOPLEFT", card.name, "BOTTOMLEFT", 0, -4)
  card.sub:SetWordWrap(false)
  card.size = UI.Chip(card)
  card.size:SetPoint("RIGHT", -14, 0)
  pg.card = card

  local hint = UI.Text(pg, "Copy this code to keep a backup, or give it to a friend: anyone with Kinship can import it "
    .. "as a new profile. Press Ctrl+C to copy.", "Small", "deskSubtle", PW)
  hint:SetPoint("TOPLEFT", 17, -86)
  hint:SetSpacing(2)

  pg.area = UI.TextArea(pg, PW, 236, 0, nil, "desk")
  pg.area:SetPoint("TOPLEFT", 16, -120)
  -- Read-only: any typing puts the code back.
  pg.area.edit:HookScript("OnTextChanged", function(self, user)
    if user and S.code and self:GetText() ~= S.code then self:SetText(S.code); self:HighlightText() end
  end)

  pg.done = UI.Button(pg, "Done", 100, 28)
  pg.done:SetPoint("BOTTOMRIGHT", -16, 14)
  pg.done:SetScript("OnClick", function() S.frame:Hide() end)
  pg.select = UI.Button(pg, "Select all", 110, 28)
  pg.select:SetPoint("RIGHT", pg.done, "LEFT", -8, 0)
  pg.select:SetScript("OnClick", function()
    pg.area.edit:SetFocus()
    pg.area.edit:HighlightText()
  end)
end

local function BuildImport(pg)
  local hint = UI.Text(pg, "Paste a profile code below (Ctrl+V). Codes start with KINSHIP1.", "Small", "deskSubtle", PW)
  hint:SetPoint("TOPLEFT", 17, -10)

  pg.area = UI.TextArea(pg, PW, 104, 0, function() S:QueueValidate() end, "desk")
  pg.area:SetPoint("TOPLEFT", 16, -30)

  pg.dot = UI.Circle(pg, 8)
  pg.dot:SetPoint("TOPLEFT", 18, -149)
  pg.status = UI.Text(pg, "", "Small", "deskSubtle", PW - 20)
  pg.status:SetPoint("TOPLEFT", 32, -146)
  pg.status:SetWordWrap(false)

  -- Preview card
  local card = UI.Panel(pg)
  card:SetPoint("TOPLEFT", 16, -168)
  card:SetSize(PW, 116)
  pg.card = card
  local filled = CreateFrame("Frame", nil, card)
  filled:SetAllPoints()
  card.filled = filled
  card.seal = UI.Seal(filled, 52)
  card.seal:SetPoint("TOPLEFT", 16, -16)
  card.name = UI.Text(filled, "", "Title", "heading", PW - 200)
  card.name:SetPoint("TOPLEFT", 84, -16)
  card.name:SetWordWrap(false)
  card.epithet = UI.Text(filled, "", "Body", "accent", PW - 110)
  card.epithet:SetPoint("TOPLEFT", card.name, "BOTTOMLEFT", 0, -3)
  card.epithet:SetWordWrap(false)
  card.facts = UI.Text(filled, "", "Small", "text", PW - 110)
  card.facts:SetPoint("TOPLEFT", card.epithet, "BOTTOMLEFT", 0, -7)
  card.facts:SetWordWrap(false)
  card.written = UI.Text(filled, "", "Small", "subtle", PW - 110)
  card.written:SetPoint("TOPLEFT", card.facts, "BOTTOMLEFT", 0, -4)
  card.written:SetWordWrap(false)
  card.status = UI.Chip(filled)
  card.status:SetPoint("TOPRIGHT", -14, -16)

  local empty = CreateFrame("Frame", nil, card)
  empty:SetAllPoints()
  card.empty = empty
  local art = empty:CreateTexture(nil, "ARTWORK")
  art:SetTexture(K.Art("IconNote"))
  art:SetSize(48, 48)
  art:SetPoint("LEFT", 24, 0)
  art:SetAlpha(0.75)
  local et = UI.Text(empty, "A preview of the profile appears here once you paste a code.", "Body", "subtle", PW - 110)
  et:SetPoint("LEFT", art, "RIGHT", 16, 0)

  pg.saveAs = UI.Field(pg, "Save as", 240, 24, nil, "desk")
  pg.saveAs:SetPoint("TOPLEFT", 16, -296)
  S.switchTo = true
  pg.switch = UI.Toggle(pg, "Switch to it now", "Make it your active profile straight away.",
    function() return S.switchTo end, function(v) S.switchTo = v end, 250)
  pg.switch:SetPoint("TOPLEFT", 280, -308)

  pg.go = UI.Button(pg, "Import as new profile", 170, 28)
  pg.go:SetPoint("BOTTOMRIGHT", -16, 14)
  pg.go:SetScript("OnClick", function() S:DoImport() end)
  pg.clear = UI.Button(pg, "Clear", 90, 28)
  pg.clear:SetPoint("RIGHT", pg.go, "LEFT", -8, 0)
  pg.clear:SetScript("OnClick", function()
    pg.area.edit:SetText("")
    S:Validate()
  end)
end

function S:Build()
  if self.frame then return end
  local f = UI.Window("KinshipRPShare", "Share a profile", W, H)
  f:SetFrameStrata("DIALOG")
  self.frame = f
  local desk = UI.Desk(f)
  desk:SetPoint("TOPLEFT", 1, -35)
  desk:SetPoint("BOTTOMRIGHT", -1, 1)
  f.tabs = UI.TabBar(f, { "Export", "Import" }, function(i) S:ShowTab(i) end, true)
  f.tabs:SetPoint("TOPLEFT", 6, -42)
  f.pages = {}
  for i = 1, 2 do
    local pg = CreateFrame("Frame", nil, f)
    pg:SetPoint("TOPLEFT", 0, -72)
    pg:SetPoint("BOTTOMRIGHT")
    pg:Hide()
    f.pages[i] = pg
  end
  BuildExport(f.pages[1])
  BuildImport(f.pages[2])
end

function S:ShowTab(i)
  local f = self.frame
  f.tabs:Select(i)
  for n, pg in ipairs(f.pages) do pg:SetShown(n == i) end
  if self.tab ~= i then UI.FadeIn(f.pages[i], 0.2) end
  self.tab = i
  if i == 1 then self:RefreshExport() else self:Validate() end
end

-- tab: "export" (default) or "import"
function S:Open(tab)
  self:Build()
  self.frame:Show()
  self:ShowTab(tab == "import" and 2 or 1)
  if tab == "import" then self.frame.pages[2].area.edit:SetFocus() end
end

function S:RefreshExport()
  local pg = self.frame.pages[1]
  local p, active = K:Profile(), K:MyProfiles().active
  local code, size, cut = self:Encode(p, active)
  self.code = code
  pg.card.name:SetText(K:DisplayName(p))
  SetPortraitTexture(pg.card.face, "player")
  if code then
    pg.card.sub:SetText(("Profile \"%s\"  ·  %s"):format(active, Summary(p))
      .. ((cut or 0) > 0 and ("  ·  |cffe8735a%d long %s cut short|r"):format(cut, cut == 1 and "text was" or "texts were") or ""))
    pg.card.size:Set(Size(#code), K:Theme().accent)
    pg.area.edit:SetText(code)
    pg.area.edit:SetCursorPosition(0)
    pg.area.edit:SetFocus()
    pg.area.edit:HighlightText()
  else
    pg.card.sub:SetText("This profile couldn't be packed into a code.")
    pg.card.size:Set(nil)
    pg.area.edit:SetText("")
  end
  pg.select:SetEnabled(code ~= nil)
end

---------------------------------------------------------------------------
-- Import
---------------------------------------------------------------------------
local function SetStatus(pg, text, color)
  pg.status:SetText(text or "")
  if color then
    pg.status:SetTextColor(color[1], color[2], color[3])
    pg.dot:SetVertexColor(color[1], color[2], color[3], 1)
    pg.dot:Show()
  else
    pg.status:SetTextColor(unpack(K:Theme().deskSubtle))
    pg.dot:Hide()
  end
end

function S:QueueValidate()
  self.token = (self.token or 0) + 1
  local token = self.token
  C_Timer.After(0.15, function() if S.token == token then S:Validate() end end)
end

function S:Validate()
  local pg = self.frame and self.frame.pages[2]
  if not pg then return end
  local data, err = self:Decode(pg.area.edit:GetText() or "")
  self.pending = data
  local card = pg.card
  card.filled:SetShown(data ~= nil)
  card.empty:SetShown(data == nil)
  pg.go:SetEnabled(data ~= nil)
  if not data then
    if err then SetStatus(pg, err, BAD) else SetStatus(pg, "Waiting for a code.") end
    return
  end
  local p = data.profile
  local rp = strtrim(p.rpName or "")
  local prefix = strtrim(p.prefix or "")
  if rp == "" then rp = "Unnamed character" end
  card.name:SetText(prefix ~= "" and (prefix .. " " .. rp) or rp)
  card.epithet:SetText(strtrim(p.epithet or "") ~= "" and p.epithet or " ")
  local facts = {}
  for _, k in ipairs({ "race", "class", "age", "home" }) do
    if strtrim(p[k] or "") ~= "" then facts[#facts + 1] = strtrim(p[k]) end
  end
  if strtrim(p.house or "") ~= "" then facts[#facts + 1] = "House " .. strtrim(p.house) end
  card.facts:SetText(#facts > 0 and table.concat(facts, "  ·  ") or "No details filled in")
  card.written:SetText(Summary(p))
  local s = K.STATUS[p.status]
  card.status:Set(s and s.short, s and s.color)
  card.seal:SetSeal("teal", K.Art("IconKin"))
  UI.FadeIn(card.filled, 0.2)
  SetStatus(pg, ("A valid profile%s%s."):format(data.by and (" from Kinship " .. data.by) or "",
    data.t and (", made " .. K.FormatDate(data.t)) or ""), GOOD)
  if not pg.saveAs.edit:HasFocus() then
    pg.saveAs.edit:SetText(UniqueName(K:MyProfiles().list, data.name))
  end
  pg.switch:Refresh()
end

function S:DoImport()
  local data, pg = self.pending, self.frame.pages[2]
  if not data then return end
  local list = K:MyProfiles().list
  local name = UniqueName(list, (pg.saveAs.edit:GetText() or ""):gsub("|", ""):sub(1, 24))
  list[name] = CopyTable(data.profile)
  if self.switchTo then K:SwitchProfile(name) else K:Fire("PROFILE") end
  self.pending = nil
  pg.go:SetEnabled(false)
  SetStatus(pg, ("Imported as \"%s\"%s."):format(name, self.switchTo and ", and it's now your active profile" or ""), GOOD)
  UI.Toast({ icon = K.Art("IconKin"), title = "Profile imported",
    text = ("\"%s\" is ready on your Profile page."):format(name), duration = 5,
    onClick = function() K.Journal:Open("profile") end })
end

---------------------------------------------------------------------------
-- Settings
---------------------------------------------------------------------------
K:RegisterSettings({ id = "profiles", trp3 = "hide", title = "Profiles", order = 5, build = function(card)
  card:Note("Back up a profile as a block of text, move it to another character, or share it with a friend.")
  local ex = card:Button("Export current profile", function() S:Open("export") end, 180)
  local im = UI.Button(card, "Import a profile", 160, 26)
  im:SetPoint("LEFT", ex, "RIGHT", 8, 0)
  im:SetScript("OnClick", function() S:Open("import") end)
end })
