-- Kinship RP: Kinship items in the game's trade window.
-- When you trade with another Kinship player a small card sits beside the
-- trade window with three slots each, like the window's own. Right-click an
-- item in your Kinship bags to put it in (as with real items), click it in
-- the card to take it back. Each side sees what the other has put in.
-- Nothing moves until the real trade goes through: then each side's items
-- are given (Items/Trade.lua) and taken without a question, because the other
-- side saw them and pressed Trade. A cancelled trade moves nothing.
--   tradeStage  either side -> the other   { items = { { d = def, n }, ... } }
-- The receiving side only takes what it was shown, no more.

local ADDON, ns = ...
local K = ns.K
local UI = K.UI
local Safe = K.Safe
local I = K.Items
local TW = { mine = {}, theirs = {} }
K.TradeWindow = TW
K.Net:Gate({ "tradeStage" }, "inventory")

local SLOTS = 3
local CELL = 36
local DONE_WINDOW = 120     -- seconds after a trade in which its items are taken
local REQ = "trade"

local function On() return K.db and K:ExtOn("inventory") end
local function Short(n) return I.Short(n) end

local function PartnerName()
  local n = GetUnitName and GetUnitName("NPC", true)
  if Safe(n) and type(n) == "string" and n ~= "" then return n end
end

---------------------------------------------------------------------------
-- What's in the card
---------------------------------------------------------------------------
local function Count(list, id)
  for _, e in ipairs(list) do if e.id == id then return e end end
end

local function Share()
  if not TW.partner then return end
  local items = {}
  for _, e in ipairs(TW.mine) do items[#items + 1] = { d = I:Pack(e.id), n = e.n } end
  K.Net:Send("tradeStage", { items = items }, "WHISPER", TW.partner)
end

-- Right-click on an item in your Kinship bags while trading: put one in
-- (shift for the whole stack). Returns true when the click was used.
function TW:TryAdd(id)
  if not (self.partner and self.card and self.card:IsShown()) then return false end
  local def = I:Get(id)
  if not def then return true end
  local e = Count(self.mine, id)
  local have = I:Available(id)
  if not e then
    if #self.mine >= SLOTS then I.Error("The trade can hold three Kinship items.") return true end
    e = { id = id, n = 0 }
    self.mine[#self.mine + 1] = e
  end
  local want = IsShiftKeyDown() and have or e.n + 1
  if want > have then I.Error("You don't have any more of those.") return true end
  e.n = math.min(want, have)
  if e.n < 1 then table.remove(self.mine, #self.mine) return true end
  if SOUNDKIT and SOUNDKIT.IG_BACKPACK_COIN_SELECT then PlaySound(SOUNDKIT.IG_BACKPACK_COIN_SELECT) end
  Share()
  self:Paint()
  return true
end

function TW:Remove(i)
  if not self.mine[i] then return end
  table.remove(self.mine, i)
  Share()
  self:Paint()
end

K.Net:On("tradeStage", function(msg, sender, channel)
  if channel ~= "WHISPER" or not TW.partner then return end
  if K.NameKey(sender) ~= K.NameKey(TW.partner) then return end
  local list = {}
  if type(msg.items) == "table" then
    for i = 1, SLOTS do
      local e = msg.items[i]
      local def = type(e) == "table" and I.Sanitize(e.d)
      local n = type(e) == "table" and math.floor(tonumber(e.n) or 0) or 0
      if def and n >= 1 and n <= 999 then list[#list + 1] = { def = def, n = n } end
    end
  end
  local changed = #list ~= #TW.theirs
  for i, e in ipairs(list) do
    local old = TW.theirs[i]
    if not old or old.def.id ~= e.def.id or old.n ~= e.n then changed = true end
  end
  local first = not TW.heard
  TW.heard = true
  TW.theirs = list
  -- They opened their side after we did: tell them what's in ours
  if first and #TW.mine == 0 then Share() end
  if changed and TW.card then TW.card.flash = 1.2 end
  TW:Paint()
end)

---------------------------------------------------------------------------
-- When the trade goes through
---------------------------------------------------------------------------
-- The other side's items, expected for a little while after the trade.
TW.expect = {}

local function Complete()
  local t = TW.closed
  if not t then TW.completeSeen = true return end   -- said before the window closed
  if t.done then return end
  t.done = true
  if #t.theirs > 0 then
    TW.expect[K.NameKey(t.partner)] = { at = GetTime(), items = t.theirs }
  end
  if #t.mine > 0 and K.Trade then
    local o, err = K.Trade:Offer(t.partner, t.mine, { req = REQ, quiet = true })
    if not o then K:Print("Your Kinship items didn't go: " .. tostring(err)) end
  end
end

-- An offer that came with a finished trade: true when it holds only what
-- the card showed you, so it can be taken without asking.
function TW:Expects(sender, req, entries)
  if req ~= REQ then return false end
  local key = K.NameKey(sender)
  local x = key and self.expect[key]
  if not x or GetTime() - x.at > DONE_WINDOW then return false end
  for _, e in ipairs(entries) do
    local shown
    for _, s in ipairs(x.items) do
      if s.def.id == e.def.id and e.n <= s.n then shown = true end
    end
    if not shown then return false end
  end
  self.expect[key] = nil
  return true
end

function TW:Received(sender, r)
  local parts = {}
  for _, e in ipairs(r.entries) do parts[#parts + 1] = I:Label(I:Get(e.def.id) or e.def, e.n) end
  K:Print(("%s gave you %s in the trade."):format(Short(sender), table.concat(parts, ", ")))
end

---------------------------------------------------------------------------
-- The card
---------------------------------------------------------------------------
local function Slots(f, y, label)
  local head = UI.Text(f, label, "Small", "subtle")
  head:SetPoint("TOPLEFT", 14, y)
  local list = {}
  for i = 1, SLOTS do
    local s = I.NewSlot(f, CELL)
    s:SetPoint("TOPLEFT", 14 + (i - 1) * (CELL + 8), y - 16)
    s.tooltipAnchor = "ANCHOR_RIGHT"
    list[i] = s
  end
  return list, head
end

function TW:Build()
  if self.card then return self.card end
  local tf = rawget(_G, "TradeFrame")
  if not tf then return nil end
  local f = UI.Panel(tf)
  f:SetWidth(220)
  f:SetPoint("TOPLEFT", tf, "TOPRIGHT", 6, 0)
  f:SetFrameStrata(tf:GetFrameStrata())
  f:SetFrameLevel(tf:GetFrameLevel() + 5)
  self.card = f
  local mono = f:CreateTexture(nil, "ARTWORK")
  mono:SetTexture(K.ICON)
  mono:SetSize(22, 22)
  mono:SetPoint("TOPLEFT", 14, -12)
  local head = UI.Text(f, "Kinship items", "Header", "heading")
  head:SetPoint("LEFT", mono, "RIGHT", 6, 0)

  f.mine = Slots(f, -44, "You offer")
  for i, s in ipairs(f.mine) do
    s:SetScript("OnClick", function()
      if TW.mine[i] then TW:Remove(i) elseif K.Satchel then K.Satchel:Open(true) end
    end)
    s:HookScript("OnEnter", function(self)
      if not TW.mine[i] then
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText("Add a Kinship item")
        GameTooltip:AddLine("Right-click one in your Kinship bags. Shift for the whole stack.", 1, 1, 1, true)
        GameTooltip:Show()
      else
        GameTooltip:AddLine("Click to take it out.", 0.55, 0.55, 0.55)
        GameTooltip:Show()
      end
    end)
  end
  f.theirs, f.theirsHead = Slots(f, -104, "They offer")
  for _, s in ipairs(f.theirs) do s:SetScript("OnClick", nil) end

  f.note = UI.Text(f, "", "Small", "subtle", 192)
  f.note:SetPoint("TOPLEFT", 14, -164)
  f.note:SetSpacing(2)
  f.flash = 0
  f:SetScript("OnUpdate", function(card, elapsed)
    if card.flash > 0 then
      card.flash = math.max(0, card.flash - elapsed)
      local a = 0.55 + 0.45 * math.abs(math.sin(card.flash * 6))
      for _, s in ipairs(card.theirs) do s:SetAlpha(a) end
    end
  end)
  K:On("INVENTORY", function() if f:IsShown() then TW:Paint() end end)
  return f
end

function TW:Paint()
  local f = self.card
  if not f then return end
  for i, s in ipairs(f.mine) do
    local e = self.mine[i]
    s:SetItem(e and I:Get(e.id), e and e.n)
  end
  for i, s in ipairs(f.theirs) do
    local e = self.theirs[i]
    s:SetItem(e and (I:Get(e.def.id) or e.def), e and e.n)
    s:SetAlpha(1)
  end
  local who = self.partner and Short(self.partner) or "They"
  f.theirsHead:SetText(who .. " offers")
  local note
  if not self.heard then
    note = who .. " hasn't opened Kinship's side of the trade. Without Kinship, your items stay with you."
  elseif #self.mine == 0 and #self.theirs == 0 then
    note = "Right-click a Kinship item in your bags to add it. Items move when the trade goes through."
  else
    note = "These move when you both press Trade, along with the rest."
  end
  f.note:SetText(note)
  f:SetHeight(164 + f.note:GetStringHeight() + 16)
end

---------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------
local ev = CreateFrame("Frame")
local function OnEvent(_, event, a, b)
  if event == "TRADE_SHOW" then
    TW.partner, TW.mine, TW.theirs, TW.heard, TW.closed = PartnerName(), {}, {}, false, nil
    TW.completeSeen = false
    if not (On() and TW.partner) then return end
    local f = TW:Build()
    if not f then return end
    Share()
    TW:Paint()
    f:Show()
  elseif event == "TRADE_ACCEPT_UPDATE" then
    TW.bothAccepted = (a == 1 and b == 1)
  elseif event == "TRADE_CLOSED" then
    if TW.partner then
      TW.closed = { partner = TW.partner, mine = TW.mine, theirs = TW.theirs, at = GetTime(), both = TW.bothAccepted }
      -- If the game never says "Trade complete", both having accepted is enough
      local t = TW.closed
      if TW.completeSeen then TW.completeSeen = false; K.Try("trade window", Complete) end
      C_Timer.After(1.5, function() if t.both and not t.done and not t.failed then K.Try("trade window", Complete) end end)
    end
    TW.partner, TW.mine, TW.theirs, TW.heard, TW.bothAccepted = nil, {}, {}, false, false
    if TW.card then TW.card:Hide() end
  elseif event == "UI_INFO_MESSAGE" or event == "UI_ERROR_MESSAGE" then
    local text = b
    if text and ERR_TRADE_COMPLETE and text == ERR_TRADE_COMPLETE then
      C_Timer.After(0, function() K.Try("trade window", Complete) end)
    elseif TW.closed and text and (text == ERR_TRADE_CANCELLED or text == ERR_TRADE_BAG_FULL
      or text == ERR_TRADE_TARGET_BAG_FULL) then
      TW.closed.failed = true
    end
  end
end

K:On("LOGIN", function()
  if not On() then return end
  for _, e in ipairs({ "TRADE_SHOW", "TRADE_CLOSED", "TRADE_ACCEPT_UPDATE", "UI_INFO_MESSAGE", "UI_ERROR_MESSAGE" }) do
    if not pcall(ev.RegisterEvent, ev, e) then K:CaughtError("trade window", "this client has no " .. e .. " event") end
  end
  ev:SetScript("OnEvent", function(...) K.Try("trade window", OnEvent, ...) end)
end)
