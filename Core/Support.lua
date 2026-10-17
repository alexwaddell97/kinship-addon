-- Kinship RP: supporting development on Ko-fi. The game can't open web
-- pages, so the link is shown in a box, already selected, ready to copy.
-- It's offered quietly: a small cup at the top of the journal, a line on
-- the Options > AddOns page, a button in Settings > General, and /kin kofi.

local ADDON, ns = ...
local K = ns.K
local UI = K.UI
local S = {}
K.Support = S

S.URL = "https://ko-fi.com/vaxorus"
S.ICON = K.MEDIA .. "Kofi"

local function Build()
  local m = UI.Modal(UIParent, 390, 196, function() S.box:Hide() end)
  S.box = m
  m:SetFrameStrata("DIALOG")
  local card = m.card
  local icon = card:CreateTexture(nil, "ARTWORK")
  icon:SetTexture(S.ICON)
  icon:SetSize(26, 26)
  icon:SetPoint("TOPLEFT", 20, -18)
  local title = UI.Text(card, "Support Kinship", "Header", "text", 300)
  title:SetPoint("LEFT", icon, "RIGHT", 10, 0)
  local note = UI.Text(card, "I make Kinship in my spare time. If it's added something to your roleplay, "
    .. "a coffee on Ko-fi helps keep it going. Thank you either way.", "Small", "subtle", 350)
  note:SetPoint("TOPLEFT", 20, -58)
  note:SetSpacing(2)
  local how = UI.Text(card, "Press Ctrl+C to copy the link, then paste it into your browser.", "Small", "subtle", 350)
  how:SetPoint("TOPLEFT", note, "BOTTOMLEFT", 0, -8)
  m.edit = UI.Edit(card, 350, 26, nil, 80)
  m.edit:SetPoint("BOTTOMLEFT", 20, 50)
  -- The link stays as it is, and stays selected, whatever is typed.
  m.edit:SetScript("OnTextChanged", function(self)
    if self:GetText() ~= S.URL then self:SetText(S.URL) end
    self:HighlightText()
  end)
  m.edit:SetScript("OnEditFocusGained", function(self) self:HighlightText() end)
  m.edit:SetScript("OnEnterPressed", function() m:Hide() end)
  m.edit:SetScript("OnEscapePressed", function() m:Hide() end)
  local close = UI.Button(card, "Close", 90, 24)
  close:SetPoint("BOTTOMRIGHT", -16, 14)
  close:SetScript("OnClick", function() m:Hide() end)
  return m
end

function S:Show()
  local m = self.box or Build()
  m:Show()
  m.edit:SetText(S.URL)
  m.edit:SetFocus()
  m.edit:HighlightText()
end

-- A small, quiet text link with the cup. desk: on the window itself rather than a card.
function S.Link(parent, desk)
  local b = CreateFrame("Button", nil, parent)
  b.icon = b:CreateTexture(nil, "ARTWORK")
  b.icon:SetTexture(S.ICON)
  b.icon:SetSize(14, 14)
  b.icon:SetPoint("LEFT", 0, 0)
  b.icon:SetAlpha(0.8)
  b.text = UI.Text(b, "Support Kinship on Ko-fi", "Small", desk and "deskSubtle" or "subtle")
  b.text:SetPoint("LEFT", b.icon, "RIGHT", 5, 0)
  b:SetSize(b.text:GetStringWidth() + 22, 16)
  b:SetScript("OnEnter", function(self)
    local u = K:Theme().ui
    self.text:SetTextColor(u[1], u[2], u[3])
    self.icon:SetAlpha(1)
  end)
  b:SetScript("OnLeave", function(self)
    local t = K:Theme()
    self.text:SetTextColor(unpack(desk and t.deskSubtle or t.subtle))
    self.icon:SetAlpha(0.8)
  end)
  b:SetScript("OnClick", function() S:Show() end)
  return b
end

-- The cup at the top of the journal, beside the guide's "?".
local function AddJournalButton()
  local J = K.Journal
  local f = J and J.frame
  if not f or S.journalButton then return end
  local b = CreateFrame("Button", nil, f)
  b:SetSize(22, 22)
  b:SetPoint("TOPRIGHT", -64, -7)
  b:SetFrameLevel(f:GetFrameLevel() + 10)
  b.ring = UI.Circle(b, 22, "ARTWORK", 0)
  b.ring:SetPoint("CENTER")
  b.hole = UI.Circle(b, 19, "ARTWORK", 1)
  b.hole:SetPoint("CENTER")
  b.icon = b:CreateTexture(nil, "ARTWORK", nil, 2)
  b.icon:SetTexture(S.ICON)
  b.icon:SetSize(13, 13)
  b.icon:SetPoint("CENTER")
  local function paint(p)
    local t = K:Theme()
    b.ring:SetVertexColor(t.ui[1], t.ui[2], t.ui[3], 0.45 + 0.55 * p)
    b.hole:SetVertexColor(t.chrome[1], t.chrome[2], t.chrome[3], 1)
    b.icon:SetAlpha(0.75 + 0.25 * p)
  end
  b:SetScript("OnEnter", function(self)
    UI.Tween(self, 1, 0.1, paint)
    GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
    GameTooltip:SetText("Support Kinship", 1, 0.82, 0)
    GameTooltip:AddLine("A link to Kinship's Ko-fi page, to copy into your browser.", 1, 1, 1, true)
    GameTooltip:Show()
  end)
  b:SetScript("OnLeave", function(self) UI.Tween(self, 0, 0.12, paint); GameTooltip:Hide() end)
  b:SetScript("OnClick", function() S:Show() end)
  UI:OnTheme(function() paint(UI.Progress(b)) end)
  S.journalButton = b
end
hooksecurefunc(K.Journal, "Build", function() AddJournalButton() end)
