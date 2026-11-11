-- Kinship RP: the typing indicator. While you write in say, emote or yell,
-- Kinship users near you see three small dots over your nameplate (and on
-- their target bar when you're their target), so nobody talks over a long
-- emote. It stops when you send, clear or close the chat box.
--
-- Only "writing" and "stopped" are sent, never a word of what you write, and
-- only to Kinship users close enough to hear a yell (K.Net, "YELL").
-- Settings > Typing indicator turns sharing and showing on or off.

local ADDON, ns = ...
local K = ns.K
local UI = K.UI
local Safe = K.Safe
local T = { typing = {}, bubbles = {} }
K.Typing = T

local KIND = "typ"
local LOCAL = { SAY = true, EMOTE = true, YELL = true }
local REFRESH = 8      -- while still writing, say so again this often (seconds)
local LASTS = 15       -- someone who said nothing more for this long has stopped
local DOT, GAP = 4, 3
local W, H = 3 * DOT + 2 * GAP + 12, DOT + 10

local function S() return K.db and K.db.settings or {} end
local function Sharing() return S().typingShare ~= false end
local function Showing() return S().typingShow ~= false end

---------------------------------------------------------------------------
-- Your own typing
---------------------------------------------------------------------------
local mine = { on = false, sent = 0 }

local function Say(on)
  if not (K.Net and K.Net.Send) then return end
  K.Net:Send(KIND, { s = on and 1 or 0 }, "YELL", nil, "LOW")
end

local function Stop()
  if mine.on then
    mine.on = false
    Say(false)
  end
end

local function Check(eb)
  if not Sharing() then return Stop() end
  local text = eb:GetText() or ""
  local kind = eb.GetAttribute and eb:GetAttribute("chatType")
  local writing = eb:IsShown() and eb:HasFocus() and LOCAL[kind] and text ~= "" and not text:find("^/")
  if not writing then return Stop() end
  local now = GetTime()
  if not mine.on or now - mine.sent > REFRESH then
    mine.on, mine.sent = true, now
    Say(true)
  end
end

local hooked = {}
local function Hook(eb)
  if not eb or hooked[eb] then return end
  hooked[eb] = true
  eb:HookScript("OnTextChanged", function(self) K.Try("typing", Check, self) end)
  eb:HookScript("OnEditFocusLost", function() K.Try("typing", Stop) end)
  eb:HookScript("OnHide", function() K.Try("typing", Stop) end)
end

local function HookAll()
  for i = 1, (NUM_CHAT_WINDOWS or 10) do Hook(_G["ChatFrame" .. i .. "EditBox"]) end
  if ChatEdit_GetActiveWindow then Hook(ChatEdit_GetActiveWindow()) end
end

---------------------------------------------------------------------------
-- The dots
---------------------------------------------------------------------------
local function NewBubble(parent)
  local b = CreateFrame("Frame", nil, parent)
  b:SetSize(W, H)
  b.bg = b:CreateTexture(nil, "BACKGROUND")
  b.bg:SetAllPoints()
  b.bg:SetColorTexture(0.05, 0.05, 0.07, 0.72)
  b.edge = UI.Border(b)
  b.edge:SetColor(1, 1, 1, 0.18)
  b.dots = {}
  for i = 1, 3 do
    local d = UI.Circle(b, DOT, "ARTWORK", 1)
    d:SetPoint("LEFT", 6 + (i - 1) * (DOT + GAP), 0)
    d:SetVertexColor(1, 0.86, 0.55, 1)
    b.dots[i] = d
  end
  -- Each dot rises and fades in turn, like someone thinking aloud.
  b:SetScript("OnUpdate", function(self)
    local t = GetTime() * 3.2
    for i, d in ipairs(self.dots) do
      local p = (math.sin(t - i * 0.9) + 1) / 2
      d:SetAlpha(0.3 + 0.7 * p)
    end
  end)
  b:Hide()
  return b
end

-- The bubble for a nameplate (one each, made as needed, on the plate itself
-- so it scales, fades and hides with it).
local function PlateBubble(plate)
  local b = T.bubbles[plate]
  if not b then
    b = NewBubble(plate)
    pcall(b.SetFrameLevel, b, plate:GetFrameLevel() + 20)
    T.bubbles[plate] = b
  end
  return b
end

local function UnitOfPlate(plate)
  local unit = plate.namePlateUnitToken or (plate.UnitFrame and plate.UnitFrame.unit)
  return type(unit) == "string" and unit or nil
end

-- Where the dots go on a plate: above Kinship's roleplay name when it's
-- there, otherwise above the plate itself.
local function PlaceOn(b, plate)
  b:ClearAllPoints()
  local o = K.Plates and K.Plates.overlays and K.Plates.overlays[plate]
  if o and o:IsShown() and o.name and o.name:IsShown() then
    b:SetPoint("BOTTOM", o.name, "TOP", 0, 3)
  else
    b:SetPoint("BOTTOM", plate, "TOP", 0, 0)
  end
end

function T:Refresh()
  local show = Showing()
  local now = GetTime()
  for key, e in pairs(self.typing) do
    if now > e.till then self.typing[key] = nil end
  end
  local used = {}
  if show and C_NamePlate and C_NamePlate.GetNamePlates and next(self.typing) then
    local ok, plates = pcall(C_NamePlate.GetNamePlates)
    for _, plate in ipairs(ok and plates or {}) do
      local forbidden = plate.IsForbidden and plate:IsForbidden()
      local unit = not forbidden and UnitOfPlate(plate)
      local name = unit and GetUnitName(unit, true)
      local key = Safe(name) and name and K.NameKey(name)
      if key and self.typing[key] and plate:IsVisible() then
        local b = PlateBubble(plate)
        PlaceOn(b, plate)
        b:Show()
        used[b] = true
      end
    end
  end
  for _, b in pairs(self.bubbles) do if not used[b] then b:Hide() end end
  self:RefreshTarget(show)
end

-- On Kinship's target bar, after their name.
function T:RefreshTarget(show)
  local bar = K.TargetBar and K.TargetBar.frame
  if not bar or not bar.name then return end
  if not self.targetBubble then self.targetBubble = NewBubble(bar) end
  local b = self.targetBubble
  local name = bar:IsShown() and K.TargetBar.name
  local key = show and name and K.NameKey(name)
  if key and self.typing[key] then
    b:ClearAllPoints()
    b:SetPoint("LEFT", bar.name, "LEFT", math.min(bar.name:GetStringWidth(), bar.name:GetWidth()) + 6, 0)
    b:SetFrameStrata(bar:GetFrameStrata())
    b:SetFrameLevel(bar:GetFrameLevel() + 5)
    b:Show()
  else
    b:Hide()
  end
end

-- Someone near you started or stopped writing.
local function Heard(msg, sender)
  local key = K.NameKey(sender)
  if not key then return end
  if msg.s == 1 then
    T.typing[key] = { name = sender, till = GetTime() + LASTS }
  else
    T.typing[key] = nil
  end
  T:Refresh()
end

-- What they wrote arrived: they've stopped.
local function Spoke(sender)
  if not Safe(sender) or type(sender) ~= "string" then return end
  local key = K.NameKey(sender)
  if key and T.typing[key] then
    T.typing[key] = nil
    T:Refresh()
  end
end

---------------------------------------------------------------------------
-- Start-up and settings
---------------------------------------------------------------------------
K:On("LOGIN", function()
  if K.Net then K.Net:On(KIND, function(msg, sender) Heard(msg, sender) end) end
  HookAll()
  if hooksecurefunc and ChatEdit_ActivateChat then
    hooksecurefunc("ChatEdit_ActivateChat", function(eb) Hook(eb) end)
  end
  local ev = CreateFrame("Frame")
  for _, e in ipairs({ "CHAT_MSG_SAY", "CHAT_MSG_EMOTE", "CHAT_MSG_YELL", "CHAT_MSG_TEXT_EMOTE",
                       "NAME_PLATE_UNIT_ADDED", "NAME_PLATE_UNIT_REMOVED", "PLAYER_TARGET_CHANGED" }) do
    pcall(ev.RegisterEvent, ev, e)
  end
  ev:SetScript("OnEvent", function(_, event, _, sender)
    if event:find("^CHAT_MSG_") then K.Try("typing", Spoke, sender)
    elseif next(T.typing) or event == "PLAYER_TARGET_CHANGED" then
      -- after the plate or bar has drawn itself
      C_Timer.After(0, function() K.Try("typing", T.Refresh, T) end)
    end
  end)
  C_Timer.NewTicker(1, function() if next(T.typing) then K.Try("typing", T.Refresh, T) end end)
end)

K:RegisterSettings({ id = "typing", title = "Typing indicator", order = 11,
  keywords = "typing writing dots emote say yell nameplate", build = function(card)
  card:Toggle("Show when others are typing", "Shows dots over a nearby Kinship user's nameplate while they type in say, emote or yell. Also shows on your target bar.",
    { get = Showing, set = function(v) S().typingShow = v; T:Refresh() end })
  card:Toggle("Let others see when I'm typing", "Nearby Kinship users can see when you're typing. What you type is never sent.", { get = Sharing, set = function(v) S().typingShare = v; if not v then Stop() end end })
  card:Note("You need friendly nameplates turned on to see the dots.")
end })
