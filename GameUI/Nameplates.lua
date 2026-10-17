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

-- Rival marks on enemy players' plates: in combat too, when it matters most.
function P:ActiveFoes()
  local s = S()
  if not s or not s.plates or not s.platesIcons or self.mode == "standdown" or not self.mode then return false end
  return not IsInInstance()
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

-- A small round icon in a coloured ring: Kin, or a rival.
local BADGE = 14
local function Badge(o, icon)
  local b = CreateFrame("Frame", nil, o)
  b:SetSize(BADGE, BADGE)
  b.ring = UI.Circle(b, BADGE, "OVERLAY", 1)
  b.ring:SetPoint("CENTER")
  b.icon = b:CreateTexture(nil, "OVERLAY", nil, 2)
  b.icon:SetSize(BADGE - 3, BADGE - 3)
  b.icon:SetPoint("CENTER")
  b.icon:SetTexture(icon)
  b.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
  UI.Round(b.icon)
  b:Hide()
  return b
end

-- What they are to you: Kin (in your relationship's colour) and a rival (in
-- your standing's colour). Each is a colour, or nil.
local KIN_COLOR = { 0.37, 0.77, 0.72 }
local function Marks(name)
  local kin, rival
  local short = Ambiguate and Ambiguate(name, "none") or name
  if K:KinFor(name) or K:KinFor(short) then
    local def = K.RelationOf and K:RelationOf(name)
    kin = def and def.color or KIN_COLOR
  end
  local W = K.War
  local r = W and W:Get(name)
  if r and W:IsRival(r) then
    local g = W.Grudge(r.grudge)
    rival = g and g.color or { 0.85, 0.85, 0.85 }
  end
  return kin, rival
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
  o.real = o:CreateFontString(nil, "OVERLAY")
  o.real:SetFontObject(GameFontNormalSmall)
  o.real:SetWordWrap(false)
  o.kin = Badge(o, K.Art("IconKin"))
  o.rival = Badge(o, K.Art("IconDungeon"))
  o.ring = UI.Circle(o, 9, "OVERLAY", 1)
  o.ring:SetVertexColor(0, 0, 0, 0.65)
  o.dot = UI.Circle(o, 6, "OVERLAY", 2)
  o.dot:SetPoint("CENTER", o.ring)
  o:Hide()
  P.overlays[plate] = o
  return o
end

-- The plate's own name, faded while "(Name)" stands in for it. A plate that
-- sets its name's alpha again (EllesmereUI's, say) is faded straight back.
local function Fade(fs)
  if not fs.kinHooked then
    fs.kinHooked = true
    hooksecurefunc(fs, "SetAlpha", function(self, a) if self.kinHide and a > 0 then self:SetAlpha(0) end end)
  end
  fs.kinHide = true
  pcall(fs.SetAlpha, fs, 0)
end

local function Unfade(rec)
  local fs = rec and rec.hidden
  if not fs then return end
  fs.kinHide = nil
  pcall(fs.SetAlpha, fs, 1)
  rec.hidden = nil
end

local function Restore(rec)
  if not rec then return end
  local o = rec.plate and P.overlays[rec.plate]
  if o then o:Hide() end
  Unfade(rec)
  local own = rec.plate and P.selfAnchors and P.selfAnchors[rec.plate]
  if own then own:GetParent():Hide() end
end

-- The ring round the status dot: your relationship's colour, if you like.
local function RingColor(def)
  if def and S().platesRelation and def.color then return def.color[1], def.color[2], def.color[3], 0.95 end
  return 0, 0, 0, 0.65
end

-- Draw a friendly plate's overlay over the plate's own name (anchor).
-- d = { text, epithet, status, ring = {r,g,b,a}, kin = colour|nil,
-- rival = colour|nil }. rec remembers which name we faded. Also used by the
-- preview (/kin plates), so what you see there is what plates draw.
local function Draw(o, anchor, d, rec)
  local s = S()
  MatchFont(o.name, anchor, 0)
  MatchFont(o.title, anchor, -2)
  SetClamped(o.name, d.text)
  local c = K.RP_NAME_COLOR
  o.name:SetTextColor(c[1], c[2], c[3], 1)
  o.ring:SetVertexColor(unpack(d.ring))
  local st = K.STATUS[d.status] or K.STATUS.ooc
  o.dot:SetVertexColor(st.color[1], st.color[2], st.color[3], 1)

  local epithet = s.platesTitles and d.epithet or ""
  local hasTitle = epithet ~= ""
  if hasTitle then
    SetClamped(o.title, epithet)
    o.title:SetTextColor(TITLE_COLOR[1], TITLE_COLOR[2], TITLE_COLOR[3], 0.95)
  end
  o.title:SetShown(hasTitle)

  -- Kin and rival marks after the name
  local marks = 0
  for _, m in ipairs({ { o.kin, s.platesIcons and d.kin }, { o.rival, s.platesIcons and d.rival } }) do
    local b, col = m[1], m[2] or nil
    b:ClearAllPoints()
    if col then
      b.ring:SetVertexColor(col[1], col[2], col[3], 0.95)
      b:SetPoint("LEFT", o.name, "RIGHT", 4 + marks * (BADGE + 2), 0)
      marks = marks + 1
    end
    b:SetShown(col ~= nil)
  end
  local shift = DOT_SHIFT - (marks > 0 and (marks * (BADGE + 2) + 2) / 2 or 0)

  o:ClearAllPoints()
  o.name:ClearAllPoints()
  o.title:ClearAllPoints()
  o.ring:ClearAllPoints()
  o.name:Show()
  o.ring:Show()
  o.dot:Show()
  -- Above the plate's own name (the character name), the title between them.
  o:SetPoint("BOTTOM", anchor, "TOP", 0, 2)
  if hasTitle then
    o.title:SetPoint("BOTTOM", o, "BOTTOM", 0, 0)
    o.name:SetPoint("BOTTOM", o.title, "TOP", shift, 1)
  else
    o.name:SetPoint("BOTTOM", o, "BOTTOM", shift, 0)
  end
  o.ring:SetPoint("RIGHT", o.name, "LEFT", -3, 0)
  -- The character's name stays where the plate shows it: as "(Name)" in a
  -- softer grey, or just as the plate draws it.
  local own = s.platesBrackets ~= false and anchor:GetText()
  own = Safe(own) and type(own) == "string" and Plain(own) or ""
  if own ~= "" then
    if rec.hidden ~= anchor then Unfade(rec) end
    MatchFont(o.real, anchor, -1)
    o.real:ClearAllPoints()
    o.real:SetPoint("CENTER", anchor, "CENTER", 0, 0)
    SetClamped(o.real, "(" .. own .. ")")
    o.real:SetTextColor(0.78, 0.78, 0.78, 0.95)
    o.real:Show()
    Fade(anchor)
    rec.hidden = anchor
  else
    o.real:Hide()
    Unfade(rec)
  end
  if not o:IsShown() then
    o:Show()
    UI.FadeIn(o, 0.15)
  end
end

-- An enemy plate: only the rival mark, just before their name.
local function DrawFoe(o, anchor, rival, rec)
  Unfade(rec)
  o.name:Hide(); o.title:Hide(); o.real:Hide(); o.ring:Hide(); o.dot:Hide(); o.kin:Hide()
  local w = anchor:GetStringWidth() or 0
  o.rival:ClearAllPoints()
  o.rival:SetPoint("RIGHT", anchor, "CENTER", -(w / 2) - 3, 0)
  o.rival.ring:SetVertexColor(rival[1], rival[2], rival[3], 0.95)
  o.rival:Show()
  if not o:IsShown() then
    o:Show()
    UI.FadeIn(o, 0.15)
  end
end

---------------------------------------------------------------------------
-- Demo (/kin plates live): for a few minutes, players around you without a
-- profile get a made-up one, and some are marked as Kin or rivals, so you
-- can see plates on real players. Only on your screen; nothing is saved.
---------------------------------------------------------------------------
local DEMO_FOR = 180
local DEMO = {
  { "Brother Aldric", "of the Cathedral", "ic" }, { "Mira Ashveil", "", "lfrp" },
  { "Captain Hale Morrow", "the Lionguard", "ic" }, { "Sister Elowen", "", "ic" },
  { "Old Tom Barrow", "Innkeeper", "lfrp" }, { "Lady Seraphine Vale", "the Gilded Rose", "ic" },
  { "Corwin Blackwood", "", "ooc" }, { "Wren Fallowmere", "the Wandering Blade", "ic" },
}
local function Hash(name)
  local h = 0
  for i = 1, #name do h = (h * 31 + name:byte(i)) % 100003 end
  return h
end

function P:DemoOn() return self.demoUntil and GetTime() < self.demoUntil or false end

-- A made-up profile and marks for someone, the same each time for that name.
local function Demo(name, hostile)
  local h = Hash(name)
  local W = K.War
  local function grudge(key) local g = W and W.Grudge(key); return g and g.color or { 0.95, 0.76, 0.36 } end
  if hostile then
    return { rival = grudge(({ "rival", "grudge", "nemesis" })[h % 3 + 1]) }
  end
  local d = DEMO[h % #DEMO + 1]
  local rels = { "friend", "family" }
  local def = K.RelationDef and K:RelationDef(rels[h % 2 + 1])
  local kin = (h % 3 == 0 or h % 5 == 0) and (def and def.color or { 0.37, 0.77, 0.72 }) or nil
  local rival = (h % 4 == 1) and grudge("rival") or nil
  return { text = d[1], epithet = d[2], status = d[3], kin = kin, rival = rival, def = kin and def or nil }
end

function P:Demo()
  if self:DemoOn() then
    self.demoUntil = nil
    K:Print("Nameplate demo off.")
  else
    self.demoUntil = GetTime() + DEMO_FOR
    K:Print("Nameplate demo on for three minutes: players near you get made-up roleplay names, and some are marked "
      .. "as Kin or rivals. Only you see it. Type /kin plates live again to stop."
      .. ((not S().plates) and " (Roleplay names on nameplates is switched off in Settings > Nameplates.)" or ""))
    C_Timer.After(DEMO_FOR + 0.5, function() if not P:DemoOn() then P:RefreshAll() end end)
  end
  self:RefreshAll()
end

---------------------------------------------------------------------------
-- Your own plate: the game's personal nameplate (the bars under your
-- character), with your roleplay name over it. "Show my own nameplate"
-- turns that plate on (and keeps it showing out of combat); switching it
-- off puts the game's settings back as they were.
---------------------------------------------------------------------------
local SELF_CVARS = { "nameplateShowSelf", "nameplatePersonalShowAlways" }
local function CVar(name)
  local get = (C_CVar and C_CVar.GetCVar) or GetCVar
  local ok, v = pcall(get, name)
  return ok and v or nil
end
local function SetCVarSafe(name, v)
  local set = (C_CVar and C_CVar.SetCVar) or SetCVar
  return (pcall(set, name, v))
end

function P:SelfAvailable() return CVar("nameplateShowSelf") ~= nil end

function P:SetSelfPlate(on)
  local s = S()
  if on then
    if not self:SelfAvailable() then
      K:Print("This client has no personal nameplate to show, so your own plate can't be shown.")
      s.platesSelf = false
      return
    end
    if InCombatLockdown() then K:Print("Try again out of combat.") s.platesSelf = false return end
    if type(s.platesSelfWas) ~= "table" then
      s.platesSelfWas = {}
      for _, n in ipairs(SELF_CVARS) do s.platesSelfWas[n] = CVar(n) end
    end
    for _, n in ipairs(SELF_CVARS) do SetCVarSafe(n, "1") end
    s.platesSelf = true
  else
    if InCombatLockdown() then K:Print("Try again out of combat.") return end
    if type(s.platesSelfWas) == "table" then
      for n, v in pairs(s.platesSelfWas) do if v ~= nil then SetCVarSafe(n, v) end end
    end
    s.platesSelfWas = nil
    s.platesSelf = false
  end
  self:RefreshAll()
end

-- A name line of our own to hang yours from: the personal plate has none.
P.selfAnchors = setmetatable({}, { __mode = "k" })
local function SelfAnchor(plate)
  local a = P.selfAnchors[plate]
  if not a then
    local holder = CreateFrame("Frame", nil, plate)
    holder:SetSize(1, 1)
    local uf = plate.UnitFrame
    local bar = uf and (uf.healthBar or uf.HealthBar) or uf or plate
    holder:SetPoint("BOTTOM", bar, "TOP", 0, 4)
    a = holder:CreateFontString(nil, "OVERLAY")
    a:SetFont(STANDARD_TEXT_FONT, 11, "OUTLINE")
    a:SetPoint("BOTTOM", holder, "BOTTOM", 0, 0)
    P.selfAnchors[plate] = a
  end
  return a
end

local function PaintSelf(rec)
  local s = S()
  local plate = rec.plate
  if not s.platesSelf or not P:Active() then return Restore(rec) end
  local me = K:Profile()
  local text = DisplayName(me)
  if text == "" then return Restore(rec) end
  local a = SelfAnchor(plate)
  a:SetText(K:MyName() or "")
  a:GetParent():Show()
  Draw(Overlay(plate), a, { text = text, epithet = Plain(me.epithet), status = me.status, ring = { RingColor(nil) } }, rec)
end

local function Paint(unit, rec)
  local s = S()
  if not s then return Restore(rec) end
  local plate = rec.plate
  if not plate or (plate.IsForbidden and plate:IsForbidden()) then return Restore(rec) end
  local ok, me = pcall(UnitIsUnit, unit, "player")
  if ok and Safe(me) and me then return PaintSelf(rec) end
  -- A plate that showed yours before, now someone else's
  local own = P.selfAnchors[plate]
  if own then own:GetParent():Hide() end
  if not FriendlyPlayer(unit) then return P.PaintFoe(unit, rec) end
  if not P:Active() then return Restore(rec) end
  local name = GetUnitName(unit, true)
  if not Safe(name) or type(name) ~= "string" or name == "" then return Restore(rec) end
  rec.key = K.NameKey(name)
  if not rec.key or K:IsIgnored(name) then return Restore(rec) end

  local reg = K:ProfileOf(name)
  local p = reg and reg.profile
  if not p or (reg.t and time() - reg.t > STALE) then P:Ask(name) end
  if not p and P:DemoOn() then
    local anchor = FindAnchor(unit, plate)
    if not anchor then return Restore(rec) end
    local d = Demo(name)
    d.ring = { RingColor(d.def) }
    return Draw(Overlay(plate), anchor, d, rec)
  end
  if not p then return Restore(rec) end
  if p.status == "ooc" and not s.platesOOC then return Restore(rec) end
  local text = DisplayName(p)
  if text == "" then return Restore(rec) end

  local anchor = FindAnchor(unit, plate)
  if not anchor then return Restore(rec) end
  local kin, rival = Marks(name)
  Draw(Overlay(plate), anchor, {
    text = text, epithet = Plain(p.epithet), status = p.status,
    ring = { RingColor(K.RelationOf and K:RelationOf(name)) }, kin = kin, rival = rival,
  }, rec)
end

-- Enemy players: only the rival mark, just before their name. Their plate
-- is otherwise left exactly as it is.
function P.PaintFoe(unit, rec)
  if not P:ActiveFoes() then return Restore(rec) end
  local ok, isPlayer = pcall(UnitIsPlayer, unit)
  if not ok or not Safe(isPlayer) or not isPlayer then return Restore(rec) end
  local name = GetUnitName(unit, true)
  if not Safe(name) or type(name) ~= "string" or name == "" then return Restore(rec) end
  local _, rival = Marks(name)
  if not rival and P:DemoOn() then rival = Demo(name, true).rival end
  if not rival then return Restore(rec) end
  local anchor = FindAnchor(unit, rec.plate)
  if not anchor then return Restore(rec) end
  DrawFoe(Overlay(rec.plate), anchor, rival, rec)
end

---------------------------------------------------------------------------
-- Preview (/kin plates): sample plates drawn the way real ones are, with
-- your current settings, so you can see them without anyone around.
---------------------------------------------------------------------------
local function SamplePlate(parent, charName, hostile)
  local pl = CreateFrame("Frame", nil, parent)
  pl:SetSize(130, 40)
  pl.bar = pl:CreateTexture(nil, "ARTWORK")
  pl.bar:SetTexture("Interface\\Buttons\\WHITE8X8")
  pl.bar:SetSize(110, 8)
  pl.bar:SetPoint("BOTTOM", 0, 6)
  if hostile then pl.bar:SetVertexColor(0.78, 0.18, 0.15) else pl.bar:SetVertexColor(0.18, 0.62, 0.25) end
  pl.edge = pl:CreateTexture(nil, "BACKGROUND")
  pl.edge:SetColorTexture(0, 0, 0, 1)
  pl.edge:SetPoint("TOPLEFT", pl.bar, -1, 1)
  pl.edge:SetPoint("BOTTOMRIGHT", pl.bar, 1, -1)
  pl.name = pl:CreateFontString(nil, "OVERLAY")
  pl.name:SetFont(STANDARD_TEXT_FONT, 11, "OUTLINE")
  pl.name:SetPoint("BOTTOM", pl.bar, "TOP", 0, 3)
  pl.name:SetText(charName)
  if hostile then pl.name:SetTextColor(1, 0.25, 0.2) else pl.name:SetTextColor(1, 1, 1) end
  pl.rec = { plate = pl }
  return pl
end

-- The font a real plate is using right now, if one is showing.
local function LivePlateFont()
  for unit, rec in pairs(P.units) do
    local a = rec.plate and FindAnchor(unit, rec.plate)
    if a then return a end
  end
end

function P:PaintPreview()
  local f = self.preview
  if not f or not f:IsShown() then return end
  local W = K.War
  local function rel(key, fallback)
    local d = K.RelationDef and K:RelationDef(key)
    return d and d.color or fallback
  end
  local function grudge(key)
    local g = W and W.Grudge(key)
    return g and g.color or { 0.95, 0.76, 0.36 }
  end
  local me = K:Profile()
  local myName = DisplayName(me)
  local live = LivePlateFont()
  local samples = {
    { char = K:MyName() or "Vax Orus", text = myName ~= "" and myName or "Lord John Dynamo",
      epithet = myName ~= "" and Plain(me.epithet) or "the Deviant", status = me.status or "ic",
      kin = rel("friend", { 0.42, 0.82, 0.46 }), relKey = "friend" },
    { char = "Mirabel Thorn", text = "Mira Ashveil", epithet = "", status = "lfrp",
      kin = rel("family", { 0.96, 0.70, 0.26 }), rival = grudge("rival"), relKey = "family" },
    { char = "Aldric Vane", text = "Brother Aldric", epithet = "of the Cathedral", status = "ic" },
    { char = "Grukka", hostile = true, rival = grudge("nemesis") },
  }
  for i, d in ipairs(samples) do
    local pl = f.plates[i]
    pl.name:SetText(d.char)
    if live then MatchFont(pl.name, live, 0) end
    local o = Overlay(pl)
    if d.hostile then
      if S().platesIcons then DrawFoe(o, pl.name, d.rival, pl.rec) else Restore(pl.rec) end
    else
      local def = d.relKey and K.RelationDef and K:RelationDef(d.relKey)
      Draw(o, pl.name, { text = d.text, epithet = d.epithet, status = d.status,
        ring = { RingColor(def) }, kin = d.kin, rival = d.rival }, pl.rec)
    end
  end
end

function P:Preview()
  local f = self.preview
  if f and f:IsShown() then f:Hide() return end
  if not f then
    f = UI.Panel(UIParent)
    f:SetSize(600, 184)
    f:SetPoint("CENTER", 0, 120)
    f:SetFrameStrata("DIALOG")
    f:EnableMouse(true)
    f:SetMovable(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    self.preview = f
    local head = UI.Text(f, "Nameplate preview", "Header", "heading")
    head:SetPoint("TOPLEFT", 14, -12)
    local note = UI.Text(f, "Samples drawn the way real plates are, with your settings. Change them in Settings > Nameplates.",
      "Small", "subtle", 520)
    note:SetPoint("BOTTOMLEFT", 14, 10)
    local close = UI.CloseButton(f, true)
    close:SetPoint("TOPRIGHT", -6, -6)
    close:SetScript("OnClick", function() f:Hide() end)
    f.plates = {}
    for i = 1, 4 do
      local pl = SamplePlate(f, "", i == 4)
      pl:SetPoint("BOTTOM", f, "BOTTOMLEFT", 80 + (i - 1) * 146, 64)
      f.plates[i] = pl
    end
    -- The key: what the dots and marks mean
    local x = 14
    local function item(widget, label, w)
      widget:SetPoint("LEFT", f, "BOTTOMLEFT", x, 40)
      local t = UI.Text(f, label, "Small", "text")
      t:SetPoint("LEFT", widget, "RIGHT", 5, 0)
      x = x + (w or 14) + 5 + t:GetStringWidth() + 16
    end
    for _, key in ipairs({ "ic", "lfrp", "ooc" }) do
      local st = K.STATUS[key]
      local dot = UI.Circle(f, 8, "OVERLAY", 2)
      dot:SetVertexColor(st.color[1], st.color[2], st.color[3], 1)
      item(dot, st.short, 8)
    end
    local kin = Badge(f, K.Art("IconKin"))
    kin.ring:SetVertexColor(KIN_COLOR[1], KIN_COLOR[2], KIN_COLOR[3], 0.95)
    kin:Show()
    item(kin, "Kin (ring: your bond)")
    local rival = Badge(f, K.Art("IconDungeon"))
    local g = K.War and K.War.Grudge("rival")
    local gc = g and g.color or { 0.95, 0.76, 0.36 }
    rival.ring:SetVertexColor(gc[1], gc[2], gc[3], 0.95)
    rival:Show()
    item(rival, "Rival (ring: your standing)")
  end
  f:Show()
  self:PaintPreview()
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
  K.Try("plate preview", self.PaintPreview, self)
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
  for key, v in pairs({ plates = true, platesTitles = true, platesOOC = true, platesCombat = true, platesRelation = true,
                         platesBrackets = true, platesIcons = true }) do
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

-- Kin, relationships and rivals change the marks
for _, e in ipairs({ "KIN", "RIVALS", "RELATIONS" }) do
  K:On(e, function() if K.db and not K:Compat() then P:RefreshAll() end end)
end

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
  card:Toggle("Character name in brackets", "Under the roleplay name, their character's name as \"(Name)\" in a softer grey, where the plate shows it.", opt("platesBrackets"))
  card:Toggle("Kin and rival marks", "A small icon after their name for your Kin and your rivals, in your relationship's or standing's colour. Rivals are marked on enemy players' plates too.", opt("platesIcons"))
  card:Toggle("Show titles", "Their title in small letters with the name, like \"the Wandering Blade\".", opt("platesTitles"))
  card:Toggle("Show out-of-character players", "When off, players marked OOC keep their ordinary name.", opt("platesOOC"))
  card:Toggle("Hide in combat", "Plates go back to plain names while you're fighting.", opt("platesCombat"))
  card:Toggle("Show my own nameplate", "Your roleplay name over the game's personal nameplate, the bars under your character. Turns that plate on, and keeps it showing out of combat; off puts it back as it was.", {
    get = function() return S().platesSelf and true or false end,
    set = function(v) P:SetSelfPlate(v) end,
  })
  card:Toggle("Colour by relationship", "The ring round their status dot in your relationship's colour: friends, family, rivals and the rest.", opt("platesRelation"))
  local note = card:Note("", 52)
  card:OnRefresh(function()
    note:SetText(P:Describe())
    P:RefreshAll()
  end)
end })
