-- Kinship RP: the target bar. When you target a roleplayer, a slim bar shows
-- their portrait or profile icon, roleplay name, status, stance and
-- relationship, their glances and effects, and a row of actions. The actions are the
-- buttons features register with K:RegisterTargetButton (view the profile,
-- write a letter, roll dice, give an item, set a relationship, ignore...).
-- Drag it to move it (unless locked); it steps aside in combat if you like.

local ADDON, ns = ...
local K = ns.K
local UI = K.UI
local Safe = K.Safe
local B = {}
K.TargetBar = B

local WHITE = "Interface\\Buttons\\WHITE8X8"
local H = 58
local PORTRAIT = 44
local GLANCE, BTN = 28, 28
local NAME_MIN, NAME_MAX = 120, 210

local function S() return K.db and K.db.settings or {} end

local function TargetName()
  local n = GetUnitName("target", true)
  if Safe(n) and type(n) == "string" and n ~= "" then return n end
end

local function IsMe()
  local me = UnitIsUnit("target", "player")
  return Safe(me) and me and true or false
end

---------------------------------------------------------------------------
-- Building
---------------------------------------------------------------------------
-- A round icon in a thin ring that brightens and grows a little on hover.
local function RoundButton(parent, size)
  local b = CreateFrame("Button", nil, parent)
  b:SetSize(size + 4, size + 4)
  b.ring = UI.Circle(b, size + 4, "ARTWORK", 0)
  b.ring:SetPoint("CENTER")
  b.icon = b:CreateTexture(nil, "ARTWORK", nil, 1)
  b.icon:SetSize(size, size)
  b.icon:SetPoint("CENTER")
  b.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
  UI.Round(b.icon)
  local function paint(p)
    local u = K:Theme().ui
    b.ring:SetVertexColor(u[1], u[2], u[3], 0.35 + 0.65 * p)
    b.icon:SetSize(size + 2 * p, size + 2 * p)
  end
  b.paint = paint
  b:HookScript("OnEnter", function(self) UI.Tween(self, 1, 0.1, paint) end)
  b:HookScript("OnLeave", function(self) UI.Tween(self, 0, 0.12, paint) end)
  UI:OnTheme(function() paint(UI.Progress(b)) end)
  return b
end

local function SavePosition(f)
  local point, _, rel, x, y = f:GetPoint(1)
  K.db.settings.targetBarPos = { point = point, rel = rel, x = math.floor(x + 0.5), y = math.floor(y + 0.5) }
end

local function Place(f)
  local p = K.db and K.db.settings.targetBarPos
  f:ClearAllPoints()
  if type(p) == "table" and p.point then
    f:SetPoint(p.point, UIParent, p.rel or p.point, p.x or 0, p.y or 0)
  else
    f:SetPoint("TOP", UIParent, "TOP", 0, -132)
  end
end

function B:Build()
  if self.frame then return self.frame end
  local f = CreateFrame("Frame", "KinshipRPTargetBar", UIParent)
  self.frame = f
  f:SetSize(320, H)
  f:SetFrameStrata("MEDIUM")
  f:SetClampedToScreen(true)
  f:SetMovable(true)
  f:EnableMouse(true)
  f:RegisterForDrag("LeftButton")
  f:SetScript("OnDragStart", function(self) if not S().targetBarLock then self:StartMoving() end end)
  f:SetScript("OnDragStop", function(self) self:StopMovingOrSizing(); SavePosition(self) end)

  f.bg = f:CreateTexture(nil, "BACKGROUND")
  f.bg:SetAllPoints()
  f.edge = UI.Border(f)
  f.line = f:CreateTexture(nil, "ARTWORK")
  f.line:SetTexture(WHITE)
  f.line:SetHeight(1)
  f.line:SetPoint("BOTTOMLEFT", 1, 1)
  f.line:SetPoint("BOTTOMRIGHT", -1, 1)
  UI:OnTheme(function(t)
    f.bg:SetColorTexture(unpack(t.chrome))
    f.edge:SetColor(unpack(t.chromeEdge))
    f.line:SetVertexColor(t.ui[1], t.ui[2], t.ui[3], 0.45)
  end)

  -- Portrait (or profile icon); click to open the profile
  f.portrait = RoundButton(f, PORTRAIT)
  f.portrait:SetPoint("LEFT", 6, 0)
  f.portrait:SetScript("OnClick", function() B:OpenProfile() end)
  f.portrait:HookScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
    GameTooltip:SetText("View profile", 1, 0.82, 0)
    GameTooltip:Show()
  end)
  f.portrait:HookScript("OnLeave", function() GameTooltip:Hide() end)
  -- Status dot: on the ring's edge, above the portrait, with a cut-out in
  -- the bar's colour so it reads as a badge rather than a blot on the ring
  f.dotBack = UI.Circle(f.portrait, 14, "OVERLAY", 0)
  f.dotBack:SetPoint("CENTER", f.portrait, "BOTTOMRIGHT", -7, 7)
  UI:OnTheme(function(t) f.dotBack:SetVertexColor(unpack(t.chrome)); f.dotBack:SetAlpha(1) end)
  f.dot = UI.Gem(f.portrait, 14)
  f.dot:SetDrawLayer("OVERLAY", 1)
  f.dot:SetPoint("CENTER", f.dotBack)

  f.name = UI.Text(f, "", "Header", "plain", NAME_MAX)
  f.name:SetPoint("TOPLEFT", f.portrait, "TOPRIGHT", 8, -6)
  f.name:SetWordWrap(false)
  f.sub = UI.Text(f, "", "Small", "deskSubtle", NAME_MAX)
  f.sub:SetPoint("TOPLEFT", f.name, "BOTTOMLEFT", 0, -4)
  f.sub:SetWordWrap(false)

  f.glances = {}
  for i = 1, 5 do
    local g = RoundButton(f, GLANCE)
    g:SetScript("OnEnter", function(self) UI.Tween(self, 1, 0.1, self.paint); B.GlanceEnter(self) end)
    g:SetScript("OnLeave", function(self) UI.Tween(self, 0, 0.12, self.paint); B.GlanceLeave() end)
    g:Hide()
    f.glances[i] = g
  end

  f.auras = {}

  f.split = f:CreateTexture(nil, "ARTWORK")
  f.split:SetTexture(WHITE)
  f.split:SetSize(1, H - 20)
  UI:OnTheme(function(t) f.split:SetVertexColor(unpack(t.chromeEdge)) end)

  f.buttons = {}
  f:Hide()
  Place(f)
  return f
end

-- Glance tooltips come from Persona; it's optional, so look it up at hover time.
function B.GlanceEnter(self)
  local P = K.Persona
  if P and self.glance then P.GlanceTooltip(self, self.glance, not self.mine) end
end

function B.GlanceLeave()
  local P = K.Persona
  if P then P.HideTooltip() else GameTooltip:Hide() end
end

local function ActionButton(f, i)
  local b = f.buttons[i]
  if b then return b end
  b = RoundButton(f, BTN)
  b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  b:HookScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
    GameTooltip:SetText(self.def and self.def.label or "", 1, 0.82, 0)
    GameTooltip:Show()
  end)
  b:HookScript("OnLeave", function() GameTooltip:Hide() end)
  b:SetScript("OnClick", function(self)
    local def = self.def
    if not def or not def.onClick then return end
    local ok, err = pcall(def.onClick, "target", B.name, self)
    if not ok then K:CaughtError("target bar " .. tostring(def.id), err) end
  end)
  f.buttons[i] = b
  return b
end

---------------------------------------------------------------------------
-- Filling it in
---------------------------------------------------------------------------
function B:OpenProfile()
  if not UnitExists("target") then return end
  if K.Viewer then K.Viewer:ShowUnit("target") end
end

local function Hex(c) return UI.Hex(c) end

local function Wanted()
  local s = S()
  if s.targetBar == false then return false end
  if not UnitExists("target") then return false end
  local isPlayer = UnitIsPlayer("target")
  if not Safe(isPlayer) or not isPlayer then return false end
  if s.targetBarCombat ~= false and InCombatLockdown() then return false end
  return true
end

function B:Update()
  if K:Compat() then   -- Total RP 3's target bar, which carries a Kinship button (Compat.lua)
    if self.frame then self.frame:Hide() end
    return
  end
  if not K.db then return end
  if not Wanted() then
    if self.frame then self.frame:Hide() end
    self.name = nil
    return
  end
  local f = self:Build()
  local me = IsMe()
  local name = me and K:MyName() or TargetName()
  if not name then f:Hide() return end
  self.name = name

  local ignored = not me and K:IsIgnored(name)
  local P = K.Persona
  local p
  if me then p = K:Profile()
  elseif not ignored then
    local reg = K:ProfileOf(name)
    p = reg and reg.profile
  end
  if not p and not me and not ignored and not S().targetBarAll then f:Hide() return end

  local function C(s) return me and (s or "") or UI.Clean(s) end

  -- Portrait: their profile icon, or the game's portrait
  local icon = p and p.icon
  if P and icon and icon ~= "" and P.IconSource(icon) then
    P.SetIcon(f.portrait.icon, icon)
  else
    SetPortraitTexture(f.portrait.icon, "target")
    f.portrait.icon:SetTexCoord(0, 1, 0, 1)
  end
  f.dot:SetShown(p ~= nil and p.status ~= nil)
  f.dotBack:SetShown(f.dot:IsShown())
  if p and p.status and K.STATUS[p.status] then f.dot:SetStatus(p.status) end

  -- Name, in their colour or their class's
  -- (with the character's own name after a roleplay name, in grey)
  local text
  local char = K:CharacterName(not me and name or nil)
  local hasRP = p and strtrim(C(p.rpName)) ~= ""
  if me then
    text = K:DisplayName(p)
  else
    local rp = p and strtrim(C(p.rpName)) or ""
    if rp ~= "" then
      local prefix = strtrim(C(p.prefix))
      text = prefix ~= "" and (prefix .. " " .. rp) or rp
    else
      text = char
    end
  end
  if hasRP and char ~= "" and char:lower() ~= text:lower() then
    text = text .. " |cff" .. K.CHAR_NAME_HEX .. "(" .. char .. ")|r"
  end
  f.name:SetText(text)
  local r, g, b
  if P and p then r, g, b = P.NameColor(p) end
  if not r then
    local _, class = UnitClass("target")
    if Safe(class) and class then r, g, b = UI.ClassColor(class) else r, g, b = 0.95, 0.90, 0.80 end
  end
  if ignored then r, g, b = 0.55, 0.55, 0.55 end
  f.name:SetTextColor(r, g, b)

  -- Status, stance and relationship on the line below
  local bits = {}
  if ignored then
    bits[1] = "Ignored"
  elseif p then
    local epithet = strtrim(C(p.epithet))
    if epithet ~= "" then bits[#bits + 1] = epithet end
    local st = p.status and K.STATUS[p.status]
    if st then bits[#bits + 1] = ("|cff%s%s|r"):format(Hex(st.color), st.short or st.label) end
    local stance = p.stance and K.STANCES[p.stance]
    if stance then bits[#bits + 1] = ("|cff%s%s|r"):format(Hex(stance.color), stance.short or stance.label) end
    local lv = K.Experience and K.Experience.Notable(p)
    if lv then bits[#bits + 1] = ("|cff%s%s|r"):format(Hex(lv.color), lv.short) end
  else
    bits[1] = "No roleplay profile"
  end
  if not me and K.RelationOf then
    local d = K:RelationOf(name)
    if d then bits[#bits + 1] = ("|cff%s%s|r"):format(Hex(d.color), d.label) end
  end
  f.sub:SetText(table.concat(bits, "  ·  "))
  local nameW = math.max(NAME_MIN, math.min(NAME_MAX, math.ceil(math.max(f.name:GetUnboundedStringWidth(),
    f.sub:GetUnboundedStringWidth()))))
  f.name:SetWidth(nameW)
  f.sub:SetWidth(nameW)

  -- Glances
  local x = 6 + PORTRAIT + 4 + 8 + nameW + 10
  local list = (P and p and not ignored) and P.Glances(p) or {}
  for i, gb in ipairs(f.glances) do
    local gl = list[i]
    gb.glance, gb.mine = gl, me
    if gl then
      P.SetIcon(gb.icon, gl.icon)
      gb:ClearAllPoints()
      gb:SetPoint("LEFT", x, 0)
      gb:Show()
      x = x + GLANCE + 6
    else
      gb:Hide()
    end
  end
  if #list > 0 then x = x + 4 end

  -- Effects (wounds, boons...), smaller, each ringed in its kind's colour
  local A = K.Auras
  local effects = (A and not ignored) and A:Of(name, me) or {}
  for i = 1, math.max(#effects, #f.auras) do
    local e = effects[i]
    local ab = f.auras[i]
    if e and i <= 6 then
      if not ab then
        ab = RoundButton(f, 20)
        local btn = ab
        ab.paint = function(p)
          local c = K.Auras.Color(btn.entry and btn.entry.kind)
          btn.ring:SetVertexColor(c[1], c[2], c[3], 0.6 + 0.4 * p)
          btn.icon:SetSize(20 + 2 * p, 20 + 2 * p)
        end
        ab:SetScript("OnEnter", function(self)
          UI.Tween(self, 1, 0.1, self.paint)
          if K.Auras then K.Auras:ShowTooltip(self, self.entry, not self.mine, "ANCHOR_BOTTOM") end
        end)
        ab:SetScript("OnLeave", function(self) UI.Tween(self, 0, 0.12, self.paint); GameTooltip:Hide() end)
        f.auras[i] = ab
      end
      ab.entry, ab.mine = e, me
      ab.icon:SetTexture(e.icon)
      ab.paint(UI.Progress(ab))
      ab:ClearAllPoints()
      ab:SetPoint("LEFT", x, 0)
      ab:Show()
      x = x + 24 + 2
    elseif ab then
      ab:Hide()
      ab.entry = nil
    end
  end
  if #effects > 0 then x = x + 6 end

  -- Actions
  local shown = {}
  for _, def in ipairs(K.targetButtons) do
    local ok, want = true, true
    if def.shown then ok, want = K.Try("target bar " .. tostring(def.id), def.shown, "target", name) end
    if ok and want then shown[#shown + 1] = def end
  end
  f.split:SetShown(#shown > 0)
  if #shown > 0 then
    f.split:ClearAllPoints()
    f.split:SetPoint("LEFT", x, 0)
    x = x + 9
  end
  for i, def in ipairs(shown) do
    local btn = ActionButton(f, i)
    btn.def = def
    btn.icon:SetTexture(def.icon or K.ICON)
    btn:ClearAllPoints()
    btn:SetPoint("LEFT", x, 0)
    btn:Show()
    x = x + BTN + 6
  end
  for i = #shown + 1, #f.buttons do f.buttons[i]:Hide(); f.buttons[i].def = nil end

  f:SetWidth(x + 4)
  if not f:IsShown() then
    f:Show()
    UI.FadeIn(f, 0.15)
    if K.Guide then C_Timer.After(0.5, function() if f:IsShown() then K.Guide:Maybe("targetbar", f, f) end end) end
  end
end

---------------------------------------------------------------------------
-- Built-in actions
---------------------------------------------------------------------------
local function Other(unit, name)
  return name ~= nil and not IsMe() and not K:IsIgnored(name)
end

K:RegisterTargetButton({
  id = "profile", order = 10, label = "View profile", icon = "Interface\\Icons\\INV_Misc_Book_09",
  onClick = function() B:OpenProfile() end,
})

K:RegisterTargetButton({
  id = "letter", order = 20, label = "Write a letter", icon = "Interface\\Icons\\INV_Letter_15",
  shown = function(unit, name) return Other(unit, name) and K.Letters ~= nil end,
  onClick = function(unit, name) K.Letters:Compose(name) end,
})

K:RegisterTargetButton({
  id = "music", order = 40, label = "Play their theme", icon = "Interface\\Icons\\INV_Misc_Drum_01",
  shown = function(unit, name)
    local P = K.Persona
    if not P or not name or K:IsIgnored(name) then return false end
    local p
    if IsMe() then p = K:Profile() else local reg = K:ProfileOf(name); p = reg and reg.profile end
    return P.Music(p) ~= nil
  end,
  onClick = function(unit, name)
    local P = K.Persona
    local p
    if IsMe() then p = K:Profile() else local reg = K:ProfileOf(name); p = reg and reg.profile end
    local id = P and P.Music(p)
    if id then P:ToggleMusic(id) end
  end,
})

---------------------------------------------------------------------------
-- Events and settings
---------------------------------------------------------------------------
local pending
local function Queue()
  if pending then return end
  pending = true
  C_Timer.After(0, function() pending = nil; K.Try("target bar", B.Update, B) end)
end

local ev = CreateFrame("Frame")
ev:RegisterEvent("PLAYER_TARGET_CHANGED")
ev:RegisterEvent("PLAYER_REGEN_DISABLED")
ev:RegisterEvent("PLAYER_REGEN_ENABLED")
ev:RegisterEvent("UNIT_PORTRAIT_UPDATE")
ev:SetScript("OnEvent", function(_, event, unit)
  if event == "UNIT_PORTRAIT_UPDATE" and unit ~= "target" then return end
  Queue()
end)

K:On("REGISTRY", function(key)
  if B.name and (key == nil or key == K.NameKey(B.name)) then Queue() end
end)
for _, e in ipairs({ "PROFILE", "TARGET_BUTTONS", "IGNORE", "RELATIONS", "PERSONA_MUSIC", "AURAS" }) do K:On(e, Queue) end

K:On("LOGIN", function()
  local s = K.db.settings
  if s.targetBar == nil then s.targetBar = true end
  if s.targetBarCombat == nil then s.targetBarCombat = true end
  if s.targetBarAll == nil then s.targetBarAll = false end
  if s.targetBarLock == nil then s.targetBarLock = false end
  if B.frame then Place(B.frame) end
  Queue()
end)

K:RegisterSettings({ id = "targetbar", trp3 = "hide", title = "Target bar", order = 14, build = function(card)
  card:Toggle("Show the target bar", "A bar with someone's roleplay name, glances and actions when you target them.",
    { get = function() return S().targetBar ~= false end, set = function(v) K.db.settings.targetBar = v; Queue() end })
  card:Toggle("Hide it in combat", "Steps aside while you fight and comes back afterwards.",
    { get = function() return S().targetBarCombat ~= false end, set = function(v) K.db.settings.targetBarCombat = v; Queue() end })
  card:Toggle("Players without a profile", "Also show it for players who don't use a roleplay addon.",
    { get = function() return S().targetBarAll end, set = function(v) K.db.settings.targetBarAll = v; Queue() end })
  card:Toggle("Lock its position", "Stop it moving when dragged.",
    { get = function() return S().targetBarLock end, set = function(v) K.db.settings.targetBarLock = v end })
  card:Button("Reset its position", function()
    K.db.settings.targetBarPos = nil
    if B.frame then Place(B.frame) end
  end, 160)
end })
