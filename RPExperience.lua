-- Kinship RP: roleplay experience. How much someone has roleplayed, so new
-- roleplayers are met with patience and can find people glad to show them
-- around. Asked once (the first time the journal opens), changed any time
-- on the Profile page, and shown in tooltips, the profile viewer and the
-- target bar. Travels as the standard MSP "FR" field (so Total RP 3,
-- MyRolePlay and XRP users see it too) and Kinship's own "KX" for the exact
-- answer (FR has no word for "happy to help").
--   profile.rpExp = "new" | "casual" | "experienced" | "mentor" | nil

local ADDON, ns = ...
local K = ns.K
local UI = K.UI
local X = {}
K.Experience = X

X.ORDER = { "new", "casual", "experienced", "mentor" }
X.LEVELS = {
  new = { label = "New to roleplay", short = "New to RP", icon = "Interface\\Icons\\INV_Misc_Flower_02",
          color = { 0.55, 0.85, 0.45 }, fr = "4", tip = "New to roleplay: be welcoming",
          desc = "Still finding your feet. Others will know to be patient and kind." },
  casual = { label = "Casual roleplayer", short = "Casual", icon = "Interface\\Icons\\INV_Drink_05",
          color = { 0.80, 0.76, 0.62 }, fr = "2",
          desc = "You roleplay now and then, when the mood takes you." },
  experienced = { label = "Experienced roleplayer", short = "Experienced", icon = "Interface\\Icons\\INV_Misc_Book_09",
          color = { 0.62, 0.76, 0.96 }, fr = "1",
          desc = "At home in long scenes, plots and making it up as you go." },
  mentor = { label = "Happy to help newcomers", short = "Helper", icon = "Interface\\Icons\\Spell_Holy_SealOfWisdom",
          color = { 0.95, 0.80, 0.40 }, fr = "1", tip = "Happy to help new roleplayers",
          desc = "Experienced, and glad to show new roleplayers the ropes. They can find you." },
}
-- MSP's roleplaying style, for other addons' players: 1 normal, 2 casual, 3 full-time, 4 beginner.
local FR_IN = { ["1"] = "experienced", ["2"] = "casual", ["3"] = "experienced", ["4"] = "new" }

function X.Of(p) return p and X.LEVELS[p.rpExp] or nil end

-- Tooltips and the target bar show the two that matter to a stranger: new, and happy to help.
function X.Notable(p) return p and (p.rpExp == "new" or p.rpExp == "mentor") and X.LEVELS[p.rpExp] or nil end

function X:Set(key)
  local p = K:Profile()
  p.rpExp = X.LEVELS[key] and key or nil
  K.db.settings.rpExpAsked = true
  K:Fire("PROFILE")
  if K.Journal and K.Journal.RefreshCurrent then K.Journal:RefreshCurrent() end
end

K:AddProfileField({
  full = { "KX", "FR" }, tooltip = { "KX" },
  publish = function(my, p)
    local lv = X.LEVELS[p.rpExp or ""]
    my.FR = lv and lv.fr or nil
    my.KX = lv and p.rpExp or nil
  end,
  read = function(fields, out)
    local kx, fr = fields.KX, fields.FR
    if type(kx) == "string" and X.LEVELS[kx] then out.rpExp = kx
    elseif type(fr) == "string" and FR_IN[fr] then out.rpExp = FR_IN[fr] end
  end,
})

---------------------------------------------------------------------------
-- Asking (once, the first time the journal opens)
---------------------------------------------------------------------------
function X:NeedsAsking()
  local p = K.db and K:Profile()
  return p ~= nil and not K.db.settings.rpExpAsked and not p.rpExp
end

local function Welcome(key)
  if key == "new" then
    UI.Toast({ icon = X.LEVELS.new.icon, round = true, duration = 10, color = X.LEVELS.new.color,
      title = "Welcome to roleplay!",
      text = "Players marked \"Happy to help newcomers\" (a gold seal in their tooltip) are glad to show you around. "
        .. "Find them in the Directory under RP help.",
      onClick = function() K.Journal:Open("directory") end })
  elseif key == "mentor" then
    UI.Toast({ icon = X.LEVELS.mentor.icon, round = true, duration = 8, color = X.LEVELS.mentor.color,
      title = "Thank you!",
      text = "New roleplayers show a green sprout in their tooltip, and can find you in the Directory under RP help." })
  end
end

local CARD_W, CARD_H = 242, 86

local function Build(host)
  local m = UI.Modal(host, 540, 340, function() X.asker:Done(nil) end)
  X.asker = m
  local card = m.card
  local head = UI.Section(card, "One quick question")
  head:SetPoint("TOPLEFT", 21, -15)
  local title = UI.Text(card, "How much have you roleplayed?", "Title", "text", 500)
  title:SetPoint("TOPLEFT", 20, -42)
  local sub = UI.Text(card, "It shows on your profile, so others know what to expect. There's no wrong answer, "
    .. "and you can change it any time on your Profile page.", "Small", "subtle", 500)
  sub:SetPoint("TOPLEFT", 20, -68)
  sub:SetSpacing(2)

  m.cards = {}
  for i, key in ipairs(X.ORDER) do
    local lv = X.LEVELS[key]
    local b = CreateFrame("Button", nil, card)
    b:SetSize(CARD_W, CARD_H)
    b:SetPoint("TOPLEFT", 20 + ((i - 1) % 2) * (CARD_W + 16), -104 - math.floor((i - 1) / 2) * (CARD_H + 10))
    b.bg = b:CreateTexture(nil, "BACKGROUND")
    b.bg:SetAllPoints()
    b.bg:SetTexture("Interface\\Buttons\\WHITE8X8")
    b.edge = UI.Border(b)
    b.ring = UI.Circle(b, 40, "ARTWORK", 0)
    b.ring:SetPoint("TOPLEFT", 12, -14)
    b.icon = b:CreateTexture(nil, "ARTWORK", nil, 1)
    b.icon:SetSize(34, 34)
    b.icon:SetPoint("CENTER", b.ring)
    b.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    b.icon:SetTexture(lv.icon)
    UI.Round(b.icon)
    b.label = UI.Text(b, lv.label, "Header", "text", CARD_W - 74)
    b.label:SetPoint("TOPLEFT", 62, -14)
    b.label:SetWordWrap(false)
    b.desc = UI.Text(b, lv.desc, "Small", "subtle", CARD_W - 74)
    b.desc:SetPoint("TOPLEFT", b.label, "BOTTOMLEFT", 0, -5)
    b.desc:SetSpacing(2)
    function b:Paint()
      local t = K:Theme()
      local u = lv.color
      self.bg:SetVertexColor(u[1], u[2], u[3], self.hover and 0.16 or 0.06)
      self.edge:SetColor(u[1], u[2], u[3], self.hover and 0.9 or 0.35)
      self.ring:SetVertexColor(u[1], u[2], u[3], self.hover and 1 or 0.7)
      self.label:SetTextColor(unpack(t.text))
    end
    b:SetScript("OnEnter", function(self) self.hover = true; self:Paint() end)
    b:SetScript("OnLeave", function(self) self.hover = false; self:Paint() end)
    b:SetScript("OnClick", function()
      if SOUNDKIT then PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON) end
      m:Done(key)
    end)
    UI:OnTheme(function() b:Paint() end)
    m.cards[i] = b
  end

  local skip = UI.Button(card, "Skip for now", 120, 26)
  skip:SetPoint("BOTTOMRIGHT", -16, 14)
  skip:SetScript("OnClick", function() m:Done(nil) end)
  local note = UI.Text(card, "New here? Pick the first one: people will know to take it gently.", "Small", "subtle", 360)
  note:SetPoint("BOTTOMLEFT", 20, 22)

  function m:Done(key)
    K.db.settings.rpExpAsked = true
    self:Hide()
    if key then X:Set(key); Welcome(key) end
    local after = self.after
    self.after = nil
    if after then C_Timer.After(0.2, after) end
  end
  return m
end

-- host: the frame to cover (the journal); after(): what to do once answered or skipped.
function X:Ask(host, after)
  local m = self.asker or Build(host)
  m.after = after
  m:Show()
end

---------------------------------------------------------------------------
-- Choosing again (the Profile page's button)
---------------------------------------------------------------------------
function X:Menu(owner)
  UI.Menu(owner, function(root)
    root:CreateTitle("Roleplay experience")
    for _, key in ipairs(X.ORDER) do
      root:CreateRadio(X.LEVELS[key].label, function() return K:Profile().rpExp == key end, function() X:Set(key) end)
    end
    root:CreateRadio("Rather not say", function() return K:Profile().rpExp == nil end, function() X:Set(nil) end)
  end)
end

-- "|T..|t New to RP" for a button, or a prompt when there's no answer yet.
function X.ButtonText(p)
  local lv = X.Of(p)
  if not lv then return "RP experience..." end
  return ("|T%s:16:16:0:0:64:64:5:59:5:59|t %s"):format(lv.icon, lv.short)
end
