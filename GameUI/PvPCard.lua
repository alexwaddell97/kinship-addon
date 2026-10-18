-- Kinship RP: your Warfront record beside the game's PvP window.
-- When the PvP (honor) window opens, a card sits at its side with your
-- record against other players (victories : defeats) and the rivals you
-- last clashed with. Click a rival to open them in the Warfront, or open the
-- Warfront itself. The window is looked for by name when it shows, since it
-- differs between clients; it is never changed, only sat beside.

local ADDON, ns = ...
local K = ns.K
local UI = K.UI
local PC = { hooked = {} }
K.PvPCard = PC

local ROWS = 5
local W_CARD = 236
local CANDIDATES = { "PVPUIFrame", "PVPFrame", "PVPParentFrame", "HonorFrame" }

local function On() return K.db and K.db.settings.pvpCard ~= false and K.War end
local Short = K.Short
local function When(r) return math.max(r.last and r.last.t or 0, r.first and r.first.t or 0) end

local function Rivals()
  local W, list = K.War, {}
  for _, r in pairs(K:Rivals()) do if W:IsRival(r) then list[#list + 1] = r end end
  table.sort(list, function(a, b) return When(a) > When(b) end)
  return list
end

function PC:Build()
  if self.card then return self.card end
  local f = UI.Panel(UIParent)
  f:SetWidth(W_CARD)
  f:SetFrameStrata("HIGH")
  f:Hide()
  self.card = f
  local mono = f:CreateTexture(nil, "ARTWORK")
  mono:SetTexture(K.ICON)
  mono:SetSize(22, 22)
  mono:SetPoint("TOPLEFT", 14, -12)
  local head = UI.Text(f, "Warfront", "Header", "heading")
  head:SetPoint("LEFT", mono, "RIGHT", 6, 0)
  f.record = UI.Text(f, "", "Small", "subtle")
  f.record:SetPoint("TOPRIGHT", -14, -18)

  f.rows = {}
  for i = 1, ROWS do
    local row = CreateFrame("Button", nil, f)
    row:SetSize(W_CARD - 28, 30)
    row:SetPoint("TOPLEFT", 14, -44 - (i - 1) * 32)
    row.hl = row:CreateTexture(nil, "BACKGROUND")
    row.hl:SetAllPoints()
    row.hl:SetColorTexture(1, 1, 1, 0.06)
    row.hl:Hide()
    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetSize(22, 22)
    row.icon:SetPoint("LEFT", 2, 0)
    row.name = UI.Text(row, "", "Body", "text", 110)
    row.name:SetPoint("TOPLEFT", row.icon, "TOPRIGHT", 8, 1)
    row.name:SetWordWrap(false)
    row.grudge = UI.Text(row, "", "Small", "subtle", 110)
    row.grudge:SetPoint("TOPLEFT", row.name, "BOTTOMLEFT", 0, -1)
    row.tally = UI.Text(row, "", "Body", "text")
    row.tally:SetPoint("RIGHT", -4, 0)
    row:SetScript("OnEnter", function(self) self.hl:Show() end)
    row:SetScript("OnLeave", function(self) self.hl:Hide() end)
    row:SetScript("OnClick", function(self) if self.r then K.War:Open(self.r) end end)
    f.rows[i] = row
  end
  f.empty = UI.Text(f, "No rivals yet. Duels, honourable kills and the enemies you face in the field gather in the Warfront.",
    "Small", "subtle", W_CARD - 28)
  f.empty:SetPoint("TOPLEFT", 14, -46)
  f.empty:SetSpacing(2)
  f.open = UI.Button(f, "Open the Warfront", W_CARD - 28, 24)
  f.open:SetScript("OnClick", function() K.Journal:Open("warfront") end)
  K:On("RIVALS", function() if f:IsShown() then PC:Paint() end end)
  return f
end

function PC:Paint()
  local f = self.card
  if not f then return end
  local W = K.War
  local list = Rivals()
  local wins, losses = 0, 0
  for _, r in pairs(K:Rivals()) do wins, losses = wins + (r.wins or 0), losses + (r.losses or 0) end
  f.record:SetText(("%d : %d"):format(wins, losses))
  local shown = math.min(ROWS, #list)
  for i, row in ipairs(f.rows) do
    local r = list[i]
    row.r = r
    if r then
      UI.ClassIcon(row.icon, r.class)
      row.name:SetText(UI.Escape(Short(r.name)))
      row.name:SetTextColor(UI.ClassColor(r.class))
      local g = W.Grudge(r.grudge)
      row.grudge:SetText(g and g.label or "")
      if g then row.grudge:SetTextColor(g.color[1], g.color[2], g.color[3]) end
      local fought = (r.wins or 0) + (r.losses or 0) + (r.draws or 0) > 0
      row.tally:SetText(fought and W:Tally(r) or "")
      row:Show()
    else
      row:Hide()
    end
  end
  f.empty:SetShown(shown == 0)
  local y = shown > 0 and (44 + shown * 32 + 6) or (46 + f.empty:GetStringHeight() + 12)
  f.open:ClearAllPoints()
  f.open:SetPoint("TOPLEFT", 14, -y)
  f:SetHeight(y + 24 + 14)
end

function PC:ShowBeside(frame)
  if not On() or not frame:IsShown() then return end
  local f = self:Build()
  f:ClearAllPoints()
  f:SetPoint("TOPLEFT", frame, "TOPRIGHT", 4, 0)
  f:SetFrameLevel((frame:GetFrameLevel() or 1) + 5)
  f.owner = frame
  self:Paint()
  f:Show()
end

-- Hook whichever PvP windows this client has, now and as they load.
function PC:Hook()
  for _, name in ipairs(CANDIDATES) do
    local frame = rawget(_G, name)
    if frame and frame.HookScript and not self.hooked[frame] then
      self.hooked[frame] = true
      frame:HookScript("OnShow", function(w) K.Try("pvp card", PC.ShowBeside, PC, w) end)
      frame:HookScript("OnHide", function(w) if PC.card and PC.card.owner == w then PC.card:Hide() end end)
      if frame:IsShown() then K.Try("pvp card", PC.ShowBeside, PC, frame) end
    end
  end
end

local ev = CreateFrame("Frame")
ev:SetScript("OnEvent", function(_, _, name)
  if type(name) == "string" and name:find("PVP", 1, true) then K.Try("pvp card", PC.Hook, PC) end
end)

K:On("LOGIN", function()
  if K.db.settings.pvpCard == nil then K.db.settings.pvpCard = true end
  K.Try("pvp card", PC.Hook, PC)
  ev:RegisterEvent("ADDON_LOADED")
end)
