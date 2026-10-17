-- Kinship RP: roleplay names on friendly player nameplates, with a status dot
-- (IC / LFRP / OOC), an optional title line and your relationship's colour.
--
-- The roleplay name sits just above the plate's own name, in roleplay gold,
-- and the character's name stays where the plate draws it: you can always
-- see who to whisper or invite. That's the same on the game's own plates and
-- on EllesmereUI Nameplates (whose text is never touched). Other
-- plate addons that draw friendly plates themselves (Plater's friendly module,
-- Kui, Platynator, ElvUI...) are left alone. Everything steps aside in
-- dungeons and raids, where plates are protected and profiles can't travel.

local ADDON, ns = ...
local K = ns.K
local UI = K.UI
local Safe = K.Safe
local P = {
  units = {},                                   -- [unit token] = { plate, key, hidden }
  overlays = setmetatable({}, { __mode = "k" }), -- [nameplate] = our overlay frame
  queue = {}, queued = {}, asked = {},
}
K.Plates = P

local MAX_W = 220
local ASK_GAP, ASK_AGAIN, STALE, QUEUE_MAX = 0.6, 300, 600, 40
local TITLE_COLOR = { 0.56, 0.84, 0.80 }
local DOT_SHIFT = 6   -- half the dot and its gap, so dot + name sit centred

local function S() return K.db and K.db.settings end

---------------------------------------------------------------------------
-- Who draws friendly plates?
---------------------------------------------------------------------------
local function Loaded(name)
  local f = C_AddOns and C_AddOns.IsAddOnLoaded or IsAddOnLoaded
  if not f then return false end
  local ok, v = pcall(f, name)
  return ok and v and true or false
end

local REPLACERS = {
  { addon = "Kui_Nameplates", label = "KuiNameplates" },
  { addon = "Platynator", label = "Platynator" },
  { addon = "TidyPlates_ThreatPlates", label = "Threat Plates" },
  { addon = "TidyPlates", label = "TidyPlates" },
  { addon = "NeatPlates", label = "NeatPlates" },
}

-- "blizzard" or "ellesmere" (we add the name above theirs), or
-- "standdown" (another addon owns friendly plates), plus a label.
function P:DetectMode()
  if Loaded("EllesmereUINameplates") then return "ellesmere", "EllesmereUI Nameplates" end
  if Loaded("Plater") then
    local plater = rawget(_G, "Plater")
    local ok, on = pcall(function() return plater.db.profile.plate_config.friendlyplayer.module_enabled end)
    if not ok or on then return "standdown", "Plater" end
  end
  for _, r in ipairs(REPLACERS) do
    if Loaded(r.addon) then return "standdown", r.label end
  end
  local elv = rawget(_G, "ElvUI")
  if type(elv) == "table" then
    local ok, on = pcall(function() local E = elv[1]; return E.NamePlates and E.NamePlates.Initialized end)
    if ok and on then return "standdown", "ElvUI" end
  end
  return "blizzard", nil
end

function P:Active()
  local s = S()
  if not s or not s.plates or self.mode == "standdown" or not self.mode then return false end
  if IsInInstance() then return false end
  if s.platesCombat and (self.inCombat or InCombatLockdown()) then return false end
  return true
end

---------------------------------------------------------------------------
-- Profile requests: one at a time, never the same person twice in a while
---------------------------------------------------------------------------
function P:Ask(name)
  local key = K.NameKey(name)
  if not key or self.queued[key] or #self.queue >= QUEUE_MAX then return end
  local last = self.asked[key]
  if last and GetTime() - last < ASK_AGAIN then return end
  self.queued[key] = true
  self.queue[#self.queue + 1] = name
  if self.ticker then return end
  local ticker
  ticker = C_Timer.NewTicker(ASK_GAP, function()
    local n = table.remove(P.queue, 1)
    if not n then ticker:Cancel(); P.ticker = nil; return end
    local k = K.NameKey(n)
    if k then P.queued[k] = nil; P.asked[k] = GetTime() end
    if not IsInInstance() and K.Comm then K.Try("nameplates", K.Comm.Request, K.Comm, n) end
  end)
  self.ticker = ticker
end

---------------------------------------------------------------------------
-- Text helpers
---------------------------------------------------------------------------
-- Plate text is plain: no colours, links or codes from other players.
local function Plain(s)
  if type(s) ~= "string" or s == "" then return "" end
  local t = UI.Clean(s)
  t = t:gsub("|c%x%x%x%x%x%x%x%x", "")
  t = t:gsub("|r", "")
  t = t:gsub("[\r\n]+", " ")
  t = t:gsub("|", "||")
  return strtrim(t)
end

local function DisplayName(p)
  local rp = Plain(p.rpName)
  if rp == "" then return "" end
  local prefix = Plain(p.prefix)
  return prefix ~= "" and (prefix .. " " .. rp) or rp
end

local function MatchFont(fs, from, delta)
  local face, size, flags
  if from then
    local ok, a, b, c = pcall(from.GetFont, from)
    if ok and Safe(a) and type(a) == "string" and Safe(b) and type(b) == "number" then face, size, flags = a, b, c end
  end
  if not face then face, size, flags = STANDARD_TEXT_FONT, 10, "OUTLINE" end
  if type(flags) ~= "string" then flags = "" end
  size = math.max(7, math.floor(size + (delta or 0) + 0.5))
  local sig = face .. size .. flags
  if fs.kSig ~= sig then
    fs.kSig = sig
    fs:SetFont(face, size, flags)
    if flags == "" then fs:SetShadowColor(0, 0, 0, 1); fs:SetShadowOffset(1, -1) else fs:SetShadowOffset(0, 0) end
  end
end

local function SetClamped(fs, text)
  fs:SetWidth(0)
  fs:SetText(text)
  local w = fs.GetUnboundedStringWidth and fs:GetUnboundedStringWidth() or fs:GetStringWidth()
  if w > MAX_W then fs:SetWidth(MAX_W) end
end

---------------------------------------------------------------------------
-- Units and plates
---------------------------------------------------------------------------
local function FriendlyPlayer(unit)
  local ok, res = pcall(function()
    if not UnitExists(unit) then return false end
    local isPlayer = UnitIsPlayer(unit)
    if not Safe(isPlayer) or not isPlayer then return false end
    local me = UnitIsUnit(unit, "player")
    if not Safe(me) or me then return false end
    local hostile = UnitCanAttack("player", unit)
    if not Safe(hostile) or hostile then return false end
    return true
  end)
  return ok and res == true
end

-- Where to put the name: above the plate's own name text (the game's, or
-- whichever of EllesmereUI's is showing).
local function FindAnchor(unit, plate)
  local uf = plate.UnitFrame
  local own = uf and uf.name
  local ownOK = own and not (uf.IsForbidden and uf:IsForbidden()) and uf:GetParent() == plate and own:IsShown()
  if P.mode == "blizzard" then
    if ownOK then return own end
    return nil
  end
  -- EllesmereUI: name-only mode writes into the game's own name text...
  if ownOK and uf:IsShown() and uf:GetAlpha() > 0.05 then return own end
  -- ...full-plate mode hangs its own frame (with a .name) off the nameplate.
  for _, child in ipairs({ plate:GetChildren() }) do
    if child ~= P.overlays[plate] and rawget(child, "unit") == unit and child:IsShown() then
      local fs = rawget(child, "name")
      if type(fs) == "table" and fs.GetObjectType and fs:GetObjectType() == "FontString" then return fs end
    end
  end
end

local function Overlay(plate)
  local o = P.overlays[plate]
  if o then return o end
  o = CreateFrame("Frame", nil, plate)
  o:SetSize(1, 1)
  o:EnableMouse(false)
  pcall(o.SetFrameLevel, o, plate:GetFrameLevel() + 10)
  o.name = o:CreateFontString(nil, "OVERLAY")
  o.name:SetFontObject(GameFontNormal)
  o.name:SetWordWrap(false)
  o.title = o:CreateFontString(nil, "OVERLAY")
  o.title:SetFontObject(GameFontNormalSmall)
  o.title:SetWordWrap(false)
  o.ring = UI.Circle(o, 9, "OVERLAY", 1)
  o.ring:SetVertexColor(0, 0, 0, 0.65)
  o.dot = UI.Circle(o, 6, "OVERLAY", 2)
  o.dot:SetPoint("CENTER", o.ring)
  o:Hide()
  P.overlays[plate] = o
  return o
end

local function Restore(rec)
  if not rec then return end
  local o = rec.plate and P.overlays[rec.plate]
  if o then o:Hide() end
  if rec.hidden then
    pcall(rec.hidden.SetAlpha, rec.hidden, 1)
    rec.hidden = nil
  end
end

-- The ring round the status dot: your relationship's colour, if you like.
local function RingColor(def)
  if def and S().platesRelation and def.color then return def.color[1], def.color[2], def.color[3], 0.95 end
  return 0, 0, 0, 0.65
end

local function Paint(unit, rec)
  local s = S()
  if not s or not P:Active() then return Restore(rec) end
  local plate = rec.plate
  if not plate or (plate.IsForbidden and plate:IsForbidden()) then return Restore(rec) end
  if not FriendlyPlayer(unit) then return Restore(rec) end
  local name = GetUnitName(unit, true)
  if not Safe(name) or type(name) ~= "string" or name == "" then return Restore(rec) end
  rec.key = K.NameKey(name)
  if not rec.key or K:IsIgnored(name) then return Restore(rec) end

  local reg = K:ProfileOf(name)
  local p = reg and reg.profile
  if not p or (reg.t and time() - reg.t > STALE) then P:Ask(name) end
  if not p then return Restore(rec) end
  if p.status == "ooc" and not s.platesOOC then return Restore(rec) end
  local text = DisplayName(p)
  if text == "" then return Restore(rec) end

  local anchor = FindAnchor(unit, plate)
  if not anchor then return Restore(rec) end
  local o = Overlay(plate)
  local def = K.RelationOf and K:RelationOf(name)

  MatchFont(o.name, anchor, 0)
  MatchFont(o.title, anchor, -2)
  SetClamped(o.name, text)
  local c = K.RP_NAME_COLOR
  o.name:SetTextColor(c[1], c[2], c[3], 1)
  o.ring:SetVertexColor(RingColor(def))
  local st = K.STATUS[p.status] or K.STATUS.ooc
  o.dot:SetVertexColor(st.color[1], st.color[2], st.color[3], 1)

  local epithet = s.platesTitles and Plain(p.epithet) or ""
  local hasTitle = epithet ~= ""
  if hasTitle then
    SetClamped(o.title, epithet)
    o.title:SetTextColor(TITLE_COLOR[1], TITLE_COLOR[2], TITLE_COLOR[3], 0.95)
  end
  o.title:SetShown(hasTitle)

  o:ClearAllPoints()
  o.name:ClearAllPoints()
  o.title:ClearAllPoints()
  o.ring:ClearAllPoints()
  -- Above the plate's own name (the character name), the title between them.
  o:SetPoint("BOTTOM", anchor, "TOP", 0, 2)
  if hasTitle then
    o.title:SetPoint("BOTTOM", o, "BOTTOM", 0, 0)
    o.name:SetPoint("BOTTOM", o.title, "TOP", DOT_SHIFT, 1)
  else
    o.name:SetPoint("BOTTOM", o, "BOTTOM", DOT_SHIFT, 0)
  end
  o.ring:SetPoint("RIGHT", o.name, "LEFT", -3, 0)
  -- Plates from before this version faded the game's name out: bring it back.
  if rec.hidden then
    pcall(rec.hidden.SetAlpha, rec.hidden, 1)
    rec.hidden = nil
  end
  if not o:IsShown() then
    o:Show()
    UI.FadeIn(o, 0.15)
  end
end

function P:Update(unit)
  if K:Compat() then return end
  local rec = self.units[unit]
  if not rec then return end
  local ok, err = pcall(Paint, unit, rec)
  if not ok then
    pcall(Restore, rec)
    K:CaughtError("nameplates", err)
  end
end

function P:RefreshAll()
  if K:Compat() then return end
  for unit in pairs(self.units) do self:Update(unit) end
end

local function Added(unit)
  if not Safe(unit) or type(unit) ~= "string" then return end
  local ok, plate = pcall(C_NamePlate.GetNamePlateForUnit, unit)
  if not ok or not plate then return end
  local old = P.units[unit]
  if old then Restore(old) end
  local rec = { plate = plate }
  P.units[unit] = rec
  -- Next frame: the game and other plate addons finish setting the plate up first.
  C_Timer.After(0, function() if P.units[unit] == rec then P:Update(unit) end end)
end

local function Removed(unit)
  if not Safe(unit) or type(unit) ~= "string" then return end
  local rec = P.units[unit]
  if rec then
    K.Try("nameplates", Restore, rec)
    P.units[unit] = nil
  end
end

function P:Seed()
  for i = 1, 60 do
    local u = "nameplate" .. i
    local ok, exists = pcall(UnitExists, u)
    if ok and Safe(exists) and exists then Added(u) end
  end
end

---------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------
local ev = CreateFrame("Frame")
ev:SetScript("OnEvent", function(_, event, unit)
  if not K.db then return end
  if event == "NAME_PLATE_UNIT_ADDED" then Added(unit)
  elseif event == "NAME_PLATE_UNIT_REMOVED" then Removed(unit)
  elseif event == "PLAYER_REGEN_DISABLED" then
    P.inCombat = true
    if S().platesCombat then P:RefreshAll() end
  elseif event == "PLAYER_REGEN_ENABLED" then
    P.inCombat = false
    if S().platesCombat then P:RefreshAll() end
  elseif event == "PLAYER_ENTERING_WORLD" then
    C_Timer.After(1, function() P:RefreshAll() end)
  end
end)

K:On("LOGIN", function()
  local s = K.db.settings
  for key, v in pairs({ plates = true, platesTitles = true, platesOOC = true, platesCombat = true, platesRelation = true }) do
    if s[key] == nil then s[key] = v end
  end
  if K:Compat() then return end   -- Total RP 3 names the plates while it runs
  P.mode, P.modeLabel = P:DetectMode()
  for _, e in ipairs({ "NAME_PLATE_UNIT_ADDED", "NAME_PLATE_UNIT_REMOVED", "PLAYER_REGEN_DISABLED",
                       "PLAYER_REGEN_ENABLED", "PLAYER_ENTERING_WORLD" }) do
    ev:RegisterEvent(e)
  end
  -- Some plate addons load their settings late; look again once things settle.
  C_Timer.After(2, function()
    P.mode, P.modeLabel = P:DetectMode()
    P:Seed()
  end)
end)

K:On("REGISTRY", function(key)
  if type(key) ~= "string" then return end
  for unit, rec in pairs(P.units) do
    if rec.key == key then P:Update(unit) end
  end
end)
for _, e in ipairs({ "RELATIONS", "IGNORE", "SAFETY" }) do
  K:On(e, function() P:RefreshAll() end)
end

---------------------------------------------------------------------------
-- Settings
---------------------------------------------------------------------------
function P:Describe()
  local s = S()
  local ok = UI.Hex(K:Theme().accent)
  local warn = UI.CardHex and UI.CardHex({ 0.92, 0.56, 0.30 }) or "b0602a"
  if not s or not s.plates then
    return "Off. Switch it on to see roleplay names above friendly players."
  end
  local mode, label = self:DetectMode()
  self.mode, self.modeLabel = mode, label
  local text
  if mode == "standdown" then
    text = ("|cff%s%s is drawing friendly nameplates,|r so Kinship stays out of its way. "
      .. "Switch off its friendly player plates to see roleplay names here."):format(warn, label)
  elseif mode == "ellesmere" then
    text = ("|cff%sWorking alongside %s.|r Kinship adds the roleplay name above each friendly player's own name "
      .. "instead of replacing it, so EllesmereUI's layout stays exactly as you set it."):format(ok, label)
  else
    text = ("|cff%sOn.|r Roleplay names show above the character names on the game's own nameplates."):format(ok)
    local okC, shown = pcall(function() return C_CVar.GetCVarBool("nameplateShowFriends") end)
    if okC and shown == false then
      text = text .. (" |cff%sFriendly player nameplates are switched off in the game's options.|r"):format(warn)
    end
  end
  return text .. " Names step aside in dungeons and raids, where profiles can't travel."
end

K:RegisterSettings({ id = "nameplates", trp3 = "hide", title = "Nameplates", order = 15, build = function(card)
  local function opt(key)
    return {
      get = function() return S()[key] and true or false end,
      set = function(v) S()[key] = v; P:RefreshAll() end,
    }
  end
  card:Toggle("Roleplay names on nameplates", "Friendly players' profile names in roleplay gold above their character names, with a dot for IC, LFRP or OOC.", opt("plates"))
  card:Toggle("Show titles", "Their title in small letters with the name, like \"the Wandering Blade\".", opt("platesTitles"))
  card:Toggle("Show out-of-character players", "When off, players marked OOC keep their ordinary name.", opt("platesOOC"))
  card:Toggle("Hide in combat", "Plates go back to plain names while you're fighting.", opt("platesCombat"))
  card:Toggle("Colour by relationship", "The ring round their status dot in your relationship's colour: friends, family, rivals and the rest.", opt("platesRelation"))
  local note = card:Note("", 52)
  card:OnRefresh(function()
    note:SetText(P:Describe())
    P:RefreshAll()
  end)
end })
