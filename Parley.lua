-- Kinship RP: the Parley wheel.
-- On an RP-PvP realm the other faction can't read your words: their /say is
-- gibberish and custom /e emotes show as "makes some strange gestures". The
-- game's own emotes do cross that line, so the wheel puts the ones that
-- matter in a fight one flick away. Hold the key, point, let go.

local ADDON, ns = ...
local K = ns.K
local UI = K.UI
local Safe = K.Safe
local P = {}
K.Parley = P

-- Clockwise from the top: hostile on the right, peaceful on the left.
-- narrate: optional custom emote for your own side (%s = target name).
P.SLOTS = {
  { label = "Challenge",  token = "THREATEN",  icon = "Ability_Warrior_Challange",
    sees = "They see you threaten them with the wrath of doom.", narrate = "levels a weapon at %s. A challenge." },
  { label = "Battle cry", token = "ROAR",      icon = "Ability_Warrior_BattleShout",
    sees = "They see you roar at them.", narrate = "lets out a battle cry." },
  { label = "Taunt",      token = "TAUNT",     icon = "Spell_Nature_Reincarnation",
    sees = "They see you taunt them.", narrate = "taunts %s, beckoning them closer." },
  { label = "Retreat",    token = "FLEE",      icon = "Ability_Rogue_Sprint",
    sees = "Everyone hears you call to flee.", narrate = "calls the retreat." },
  { label = "Yield",      token = "SURRENDER", icon = "Ability_Warrior_DefensiveStance",
    sees = "They see you surrender before them.", narrate = "lowers their weapon and yields to %s." },
  { label = "Mercy",      token = "MERCY",     icon = "Spell_Holy_Heal",
    sees = "They see you beg them for mercy.", narrate = "begs %s for mercy." },
  { label = "Salute",     token = "SALUTE",    icon = "INV_Banner_02",
    sees = "They see you salute them with respect.", narrate = "salutes %s. Well fought." },
  { label = "Parley",     token = "WAVE",      icon = "INV_Misc_Note_01",
    sees = "They see you wave: a sign you mean to talk.", narrate = "raises an open hand toward %s, asking for parley." },
}

local RADIUS, SLOT, HUB = 132, 60, 132

local function Emote(token)
  if C_ChatInfo and C_ChatInfo.PerformEmote then
    if pcall(C_ChatInfo.PerformEmote, token) then return end
  end
  if DoEmote then pcall(DoEmote, token) end
end

local function TargetInfo()
  if not UnitExists("target") or not UnitIsPlayer("target") then return nil end
  local name = GetUnitName("target", true)
  if not Safe(name) or not name then return nil end
  local enemy = UnitIsEnemy("player", "target")
  return name, Safe(enemy) and enemy or false
end

---------------------------------------------------------------------------
-- Building the wheel
---------------------------------------------------------------------------
function P:Build()
  if self.frame then return end
  local f = CreateFrame("Frame", "KinshipRPParley", UIParent)
  f:SetAllPoints()
  f:SetFrameStrata("FULLSCREEN_DIALOG")
  f:EnableMouse(true)
  f:Hide()
  self.frame = f
  -- Esc closes it through the game's own special-frame handling, which keeps
  -- working in combat (keyboard capture would not).
  tinsert(UISpecialFrames, "KinshipRPParley")

  f.dim = f:CreateTexture(nil, "BACKGROUND")
  f.dim:SetAllPoints()
  f.dim:SetColorTexture(0, 0, 0, 0.30)

  local wheel = CreateFrame("Frame", nil, f)
  wheel:SetSize(2 * (RADIUS + SLOT), 2 * (RADIUS + SLOT))
  f.wheel = wheel

  -- A dark disc the slots sit on, with a hairline rim in the accent colour
  local disc = 2 * RADIUS + SLOT + 28
  local rim = UI.Circle(wheel, disc, "BACKGROUND", 1)
  rim:SetPoint("CENTER")
  local plate = UI.Circle(wheel, disc - 3, "BACKGROUND", 2)
  plate:SetPoint("CENTER")

  -- Hub
  local hub = CreateFrame("Frame", nil, wheel)
  hub:SetSize(HUB, HUB)
  hub:SetPoint("CENTER")
  hub.ring = UI.Circle(hub, HUB, "ARTWORK", 0)
  hub.ring:SetPoint("CENTER")
  hub.fill = UI.Circle(hub, HUB - 4, "ARTWORK", 1)
  hub.fill:SetPoint("CENTER")
  hub.label = UI.Text(hub, "Parley", "Title", "deskHeading", HUB - 20)
  hub.label:SetPoint("CENTER", 0, 10)
  hub.label:SetJustifyH("CENTER")
  hub.sees = UI.Text(hub, "", "Label", "deskSubtle", HUB - 26)
  hub.sees:SetPoint("TOP", hub.label, "BOTTOM", 0, -5)
  hub.sees:SetJustifyH("CENTER")
  hub.sees:SetSpacing(2)
  f.hub = hub

  -- Pointer: a small dot on the hub's rim that follows your aim
  f.pointer = UI.Circle(wheel, 10, "OVERLAY", 2)

  f.target = UI.Text(wheel, "", "Header", "deskHeading")
  f.target:SetPoint("BOTTOM", wheel, "TOP", 0, -6)
  f.hint = UI.Text(wheel, "Point and release, or click.  Right-click or Esc to close.", "Small", "deskSubtle")
  f.hint:SetPoint("TOP", wheel, "BOTTOM", 0, 6)

  f.slots = {}
  for i, s in ipairs(self.SLOTS) do
    local b = CreateFrame("Button", nil, wheel)
    b:SetSize(SLOT, SLOT)
    b.angle = math.rad(90 - (i - 1) * (360 / #self.SLOTS))
    b.ring = UI.Circle(b, SLOT, "BACKGROUND", 0)
    b.ring:SetPoint("CENTER")
    b.bg = UI.Circle(b, SLOT - 4, "BACKGROUND", 1)
    b.bg:SetPoint("CENTER")
    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetSize(SLOT - 14, SLOT - 14)
    b.icon:SetPoint("CENTER")
    b.icon:SetTexture("Interface\\Icons\\" .. s.icon)
    b.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    UI.Round(b.icon)
    b.label = UI.Text(b, s.label, "Small", "deskText")
    b.label:SetPoint("TOP", b, "BOTTOM", 0, -3)
    b.slot = s
    b:SetScript("OnEnter", function() P.mouseSlot = i end)
    b:SetScript("OnLeave", function() if P.mouseSlot == i then P.mouseSlot = nil end end)
    b:SetScript("OnClick", function() P:Choose(i) end)
    f.slots[i] = b
  end

  f:SetScript("OnMouseDown", function(_, button)
    if button == "RightButton" then P:Close() elseif P.selected then P:Choose(P.selected) end
  end)
  f:SetScript("OnUpdate", function(self, elapsed) P:Update(elapsed) end)

  UI:OnTheme(function(t)
    rim:SetVertexColor(t.ui[1], t.ui[2], t.ui[3], 0.35)
    plate:SetVertexColor(t.chrome[1], t.chrome[2], t.chrome[3], 0.88)
    hub.ring:SetVertexColor(t.ui[1], t.ui[2], t.ui[3], 0.9)
    hub.fill:SetVertexColor(unpack(t.chrome))
    f.pointer:SetVertexColor(t.ui[1], t.ui[2], t.ui[3], 1)
    for _, b in ipairs(f.slots) do b.bg:SetVertexColor(unpack(t.chrome)) end
  end)
end

---------------------------------------------------------------------------
-- Open, aim, choose
---------------------------------------------------------------------------
function P:Open()
  self:Build()
  local f = self.frame
  local scale = UIParent:GetEffectiveScale()
  local x, y = GetCursorPosition()
  x, y = x / scale, y / scale
  local half = RADIUS + SLOT
  x = math.max(half, math.min(UIParent:GetWidth() - half, x))
  y = math.max(half + 30, math.min(UIParent:GetHeight() - half - 30, y))
  f.wheel:ClearAllPoints()
  f.wheel:SetPoint("CENTER", UIParent, "BOTTOMLEFT", x, y)
  self.cx, self.cy = x, y
  self.selected, self.mouseSlot, self.t = nil, nil, 0

  local name, enemy = TargetInfo()
  if name then
    local short = Ambiguate and Ambiguate(name, "none") or name
    f.target:SetText((enemy and "|cffe65c4cEnemy|r  " or "") .. short)
  else
    f.target:SetText("No target: emotes go to everyone nearby")
  end
  f:Show()
  if SOUNDKIT then PlaySound(SOUNDKIT.IG_MAINMENU_OPEN) end
end

function P:Close()
  if self.frame then self.frame:Hide() end
  self.selected = nil
end

function P:Toggle()
  if self.frame and self.frame:IsShown() then self:Close() else self:Open() end
end

function P:Update(elapsed)
  local f = self.frame
  self.t = (self.t or 0) + elapsed
  -- Slots fly out from the hub as the wheel opens
  local open = UI.Ease.outQuart(math.min(1, self.t / 0.22))
  f:SetAlpha(math.min(1, self.t / 0.12))

  -- Aim: whichever slot the cursor points toward, once it's off the hub
  local scale = UIParent:GetEffectiveScale()
  local x, y = GetCursorPosition()
  local dx, dy = x / scale - self.cx, y / scale - self.cy
  local dist = math.sqrt(dx * dx + dy * dy)
  local sel = self.mouseSlot
  if not sel and dist > HUB / 2 then
    local a = math.deg(math.atan2(dy, dx))
    local n = #self.SLOTS
    local step = 360 / n
    sel = math.floor(((90 - a) % 360 + step / 2) / step) % n + 1
  end
  self.selected = sel

  local t = K:Theme()
  for i, b in ipairs(f.slots) do
    local on = i == sel
    local r = RADIUS * open + (on and 6 or 0)
    local sc = on and 1.12 or 1   -- offsets are in the slot's own scale, so divide it back out
    b:SetScale(sc)
    b:ClearAllPoints()
    b:SetPoint("CENTER", f.wheel, "CENTER", math.cos(b.angle) * r / sc, math.sin(b.angle) * r / sc)
    b.ring:SetVertexColor(t.ui[1], t.ui[2], t.ui[3], on and 1 or 0.35)
    b.icon:SetAlpha(on and 1 or 0.8)
    b.label:SetAlpha(on and 1 or 0.7)
  end

  local s = sel and self.SLOTS[sel]
  f.hub.label:SetText(s and s.label or "Parley")
  f.hub.sees:SetText(s and s.sees or "Emotes the other faction can read.")
  if sel then
    local a = f.slots[sel].angle
    f.pointer:Show()
    f.pointer:ClearAllPoints()
    f.pointer:SetPoint("CENTER", f.wheel, "CENTER", math.cos(a) * (HUB / 2 + 2), math.sin(a) * (HUB / 2 + 2))
  else
    f.pointer:Hide()
  end
end

function P:Choose(i)
  local s = self.SLOTS[i]
  self:Close()
  if not s then return end
  Emote(s.token)
  local name, enemy = TargetInfo()
  local short = name and (Ambiguate and Ambiguate(name, "none") or name)
  -- Optional words for your own side (the other faction sees strange gestures)
  if K.db.settings.parleyNarrate and s.narrate then
    local line = s.narrate:format(short or "everyone")
    local send = C_ChatInfo and C_ChatInfo.SendChatMessage or SendChatMessage
    if send then pcall(send, line, "EMOTE") end
  end
  if name and enemy then K.War:Record(name, "parley", s.label, nil, true) end
end

-- Key binding: hold to open, release to choose.
function KinshipRP_ParleyKey(keystate)
  if keystate == "down" then
    P:Open()
  elseif P.frame and P.frame:IsShown() then
    if P.selected then P:Choose(P.selected) elseif (P.t or 0) > 0.3 then P:Close() end
  end
end

BINDING_HEADER_KINSHIPRP = "Kinship RP"
_G["BINDING_NAME_KINSHIPRP_PARLEY"] = "Parley wheel (hold, aim, release)"
_G["BINDING_NAME_KINSHIPRP_JOURNAL"] = "Open the Kinship journal"
