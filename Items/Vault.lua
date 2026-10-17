-- Kinship RP: a vault for Kinship items, kept at the bank.
-- Talk to a banker and a Kinship vault opens beside the bank, thirty slots
-- like your Kinship bags. As with the bank itself: right-click an item in
-- your Kinship bags to put it in the vault, click one in the vault to take
-- it back out. Each character has their own vault, reachable only at a bank.

local ADDON, ns = ...
local K = ns.K
local UI = K.UI
local I = K.Items
local V = {}
K.Vault = V

local SLOTS, COLS, CELL, GAP = 30, 6, 36, 6

local function On() return K.db and K:ExtOn("inventory") end

function V:Slots()
  K.db.vault = K.db.vault or {}
  local key = K:CharKey()
  local box = K.db.vault[key]
  if type(box) ~= "table" then box = {}; K.db.vault[key] = box end
  if type(box.slots) ~= "table" then box.slots = {} end
  return box.slots
end

function V:IsOpen() return self.card and self.card:IsShown() or false end

-- Right-click in your Kinship bags at the bank: the whole stack goes in.
-- Returns true when the click was used.
function V:TryDeposit(bagSlot)
  if not self:IsOpen() then return false end
  local s = I:Slot(bagSlot)
  local def = s and I:Get(s.def)
  if not def then return true end
  local n = math.min(s.count, I:Available(def.id))
  if n < 1 then I.Error("That item is promised in a trade.") return true end
  local copy = {}
  for i, e in pairs(self:Slots()) do copy[i] = { def = e.def, count = e.count } end
  local left = I.Fill(copy, def.id, n, def.stack, SLOTS)
  local moved = n - left
  if moved < 1 then I.Error("Your Kinship vault is full.") return true end
  if not I:Remove(def.id, moved, bagSlot) then return true end
  I.Fill(self:Slots(), def.id, moved, def.stack, SLOTS)
  if SOUNDKIT and SOUNDKIT.IG_BACKPACK_COIN_SELECT then PlaySound(SOUNDKIT.IG_BACKPACK_COIN_SELECT) end
  K:Fire("VAULT")
  return true
end

-- Click in the vault: as much of the stack as fits goes to your bags.
function V:Withdraw(i)
  local slots = self:Slots()
  local s = slots[i]
  local def = s and I:Get(s.def)
  if not s then return end
  if not def then I.Error("That item's design never reached you.") return end
  local left = I:Add(def.id, s.count)
  local moved = s.count - left
  if moved < 1 then I.Error("There's no room in your Kinship bags.") return end
  s.count = left
  if s.count <= 0 then slots[i] = nil end
  if SOUNDKIT and SOUNDKIT.IG_BACKPACK_COIN_SELECT then PlaySound(SOUNDKIT.IG_BACKPACK_COIN_SELECT) end
  K:Fire("VAULT")
end

function V:Count()
  local n = 0
  for _ in pairs(self:Slots()) do n = n + 1 end
  return n
end

---------------------------------------------------------------------------
-- The vault card, beside the bank
---------------------------------------------------------------------------
local function BankParent()
  local eui = rawget(_G, "EUI_BankFrame")
  if eui and eui:IsShown() then return eui end
  return rawget(_G, "BankFrame") or eui
end

function V:Build()
  if self.card then return self.card end
  local f = UI.Panel(UIParent)
  f:SetSize(14 * 2 + COLS * CELL + (COLS - 1) * GAP, 0)
  f:SetFrameStrata("HIGH")
  f:Hide()
  self.card = f
  local mono = f:CreateTexture(nil, "ARTWORK")
  mono:SetTexture(K.ICON)
  mono:SetSize(22, 22)
  mono:SetPoint("TOPLEFT", 14, -12)
  local head = UI.Text(f, "Kinship vault", "Header", "heading")
  head:SetPoint("LEFT", mono, "RIGHT", 6, 0)
  f.count = UI.Text(f, "", "Small", "subtle")
  f.count:SetPoint("TOPRIGHT", -14, -18)

  f.cells = {}
  for i = 1, SLOTS do
    local s = I.NewSlot(f, CELL)
    s:SetPoint("TOPLEFT", 14 + ((i - 1) % COLS) * (CELL + GAP), -44 - math.floor((i - 1) / COLS) * (CELL + GAP))
    s.tooltipAnchor = "ANCHOR_RIGHT"
    s:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    s:SetScript("OnClick", function()
      local e = V:Slots()[i]
      if e and K.ItemLinks and K.ItemLinks:TryLink(e.def) then return end
      V:Withdraw(i)
    end)
    f.cells[i] = s
  end
  local rows = math.ceil(SLOTS / COLS)
  local y = 44 + rows * (CELL + GAP) + 4
  f.note = UI.Text(f, "Right-click an item in your Kinship bags to keep it here. Click one here to take it back.",
    "Small", "subtle", f:GetWidth() - 28)
  f.note:SetPoint("TOPLEFT", 14, -y)
  f.note:SetSpacing(2)
  f.bags = UI.Button(f, "Kinship bags", 120, 22)
  f.bags:SetPoint("TOPLEFT", f.note, "BOTTOMLEFT", 0, -10)
  f.bags:SetScript("OnClick", function() if K.Satchel then K.Satchel:Open(false) end end)
  f:SetHeight(y + f.note:GetStringHeight() + 10 + 22 + 14)

  K:On("VAULT", function() if f:IsShown() then V:Paint() end end)
  K:On("INVENTORY", function() if f:IsShown() then V:Paint() end end)
  return f
end

function V:Paint()
  local f = self.card
  if not f then return end
  local slots = self:Slots()
  for i, s in ipairs(f.cells) do
    local e = slots[i]
    local def = e and I:Get(e.def)
    s:SetItem(def, e and e.count, e ~= nil)
  end
  f.count:SetText(("%d / %d"):format(self:Count(), SLOTS))
end

function V:Show()
  if not On() or K.db.settings.vault == false then return end
  local f = self:Build()
  local parent = BankParent()
  f:ClearAllPoints()
  if parent then
    f:SetPoint("TOPLEFT", parent, "TOPRIGHT", 4, 0)
    f:SetFrameLevel((parent:GetFrameLevel() or 1) + 5)
  else
    f:SetPoint("LEFT", UIParent, "CENTER", 40, 0)
  end
  self:Paint()
  f:Show()
end

function V:Hide()
  if self.card then self.card:Hide() end
end

local ev = CreateFrame("Frame")
ev:SetScript("OnEvent", function(_, event)
  if event == "BANKFRAME_OPENED" then
    -- EllesmereUI's bank appears a moment later; sit beside whichever shows
    C_Timer.After(0.1, function() K.Try("vault", V.Show, V) end)
  else
    V:Hide()
  end
end)

K:On("LOGIN", function()
  if not On() then return end
  V:Slots()
  for _, e in ipairs({ "BANKFRAME_OPENED", "BANKFRAME_CLOSED" }) do
    if not pcall(ev.RegisterEvent, ev, e) then K:CaughtError("vault", "this client has no " .. e .. " event") end
  end
end)
