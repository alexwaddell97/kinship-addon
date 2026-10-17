-- Kinship RP: Kinship items as quest rewards. A quest's writer lists up to
-- four of their own item designs (quest.items = { { d = design id, n }, ... }),
-- optionally as a choice of one (quest.pick). The designs travel with the
-- quest offer, so players see what they'd earn.
--
-- When a player finishes the quest, their client claims the reward (after
-- they choose, if it's a choice):
--   qclaim  player -> writer  { id, pk = chosen index }
-- The writer's client makes the items from the designs and sends them through
-- Kinship's trade (source "mint"), which the player's client takes without
-- asking. Until a delivery lands it stays owed, in the writer's log
-- (players[key].rw), and is tried again every few minutes and whenever the
-- player claims again (on login, and now and then), so a reward reaches
-- someone who was offline. On a quest of your own, the items are made for you.

local ADDON, ns = ...
local K = ns.K
local UI = K.UI
local Safe = K.Safe
local R = { MAX = 4 }
K.QuestRewards = R

K.Net:Gate({ "qclaim" }, "campaigns")

local RETRY = 180          -- seconds between tries to deliver an owed reward
local CLAIM_AGAIN = 600    -- seconds between a player's reminders

local function Q() return K.Quests end
local function I() return K.Items end
local function Short(n) return Ambiguate and Ambiguate(n, "none") or n end
local function Gold() return { 0.95, 0.76, 0.36 } end

---------------------------------------------------------------------------
-- Shape
---------------------------------------------------------------------------
function R.Sanitize(list)
  if type(list) ~= "table" then return nil end
  local out, seen = {}, {}
  for j = 1, R.MAX * 2 do
    local it = list[j]
    if type(it) ~= "table" then break end
    local d, n = it.d, tonumber(it.n)
    if type(d) == "string" and d ~= "" and #d <= 100 and not seen[d] and n then
      n = math.floor(n)
      if n >= 1 and n <= 99 then
        seen[d] = true
        out[#out + 1] = { d = d, n = n }
        if #out >= R.MAX then break end
      end
    end
  end
  return #out > 0 and out or nil
end

-- For the wire: each item with its design.
function R.Pack(q)
  if not (q.items and I()) then return nil end
  local out = {}
  for j, it in ipairs(q.items) do out[j] = { d = it.d, n = it.n, def = I():Pack(it.d) } end
  return out
end

-- Designs that came with a quest offer: kept only if the quest's writer made them.
function R.Learn(raw, sender)
  if type(raw) ~= "table" or not I() then return end
  local key = K.NameKey(sender)
  for j = 1, R.MAX do
    local it = raw[j]
    if type(it) ~= "table" then break end
    local def = I().Sanitize(it.def)
    if def and def.id == it.d and K.NameKey(def.creator) == key then I():Learn(def) end
  end
end

function R.Req(e) return "q:" .. tostring(e.id):sub(-36) end

local function Hosting(e)
  local QA = K.QuestAuto
  if QA and QA.ForOthers then return QA.ForOthers(e) end
  return e.st and e.players and next(e.players) ~= nil
end

-- What a player gets: the chosen item, or all of them.
local function Chosen(e, pk)
  if not e.items then return {} end
  if e.pick then
    local it = pk and e.items[pk]
    return it and { it } or {}
  end
  return e.items
end

function R.Label(it)
  local def = I() and I():Get(it.d)
  return I() and I():Label(def, it.n) or "an item"
end

---------------------------------------------------------------------------
-- The player's side
---------------------------------------------------------------------------
-- "choose", "take" (your own quest, not yet in your bags), "coming", "got", or nil.
function R.State(e)
  if not (e and e.items and e.state == "complete") then return nil end
  if e.rewarded then return "got" end
  if e.pick and not (e.claim and e.claim.pk) then return "choose" end
  if Q():IsMine(e) then return not Hosting(e) and "take" or nil end
  return "coming"
end

function R:Claim(e)
  if not (e.author and not Q():IsMine(e)) then return end
  e.claim = e.claim or {}
  e.claim.at = time()
  K.Net:Send("qclaim", { id = e.id, pk = e.claim.pk }, "WHISPER", e.author)
end

-- Your own quest: the items go straight into your bags.
function R:Mint(e)
  local Items = I()
  if not Items or e.rewarded then return end
  local list, check = {}, {}
  for _, it in ipairs(Chosen(e, e.claim and e.claim.pk)) do
    local def = Items:Get(it.d)
    if def then
      list[#list + 1] = it
      check[#check + 1] = { id = it.d, n = it.n, stack = def.stack }
    end
  end
  if #list == 0 then e.rewarded = true; K:Fire("QUESTS") return end
  if not Items:Fits(check) then
    UI.Toast({ icon = "Interface\\Icons\\INV_Misc_Bag_08", round = true, duration = 6, color = { 0.90, 0.36, 0.30 },
      title = "No room for your reward", text = "Make space in your Kinship bags, then take it from the quest." })
    return
  end
  for _, it in ipairs(list) do Items:Add(it.d, it.n) end
  e.rewarded = true
  self:Toast(e, list)
  K:Fire("QUESTS")
end

function R:Toast(e, list)
  local first = list[1]
  local def = first and I() and I():Get(first.d)
  UI.Toast({
    icon = def and I().IconTexture(def.icon) or e.icon, iconCoords = { 0.08, 0.92, 0.08, 0.92 }, duration = 6,
    title = "Reward: " .. (first and R.Label(first) or "") .. (#list > 1 and (" and %d more"):format(#list - 1) or ""),
    text = UI.Clean(e.title), color = def and I().Quality(def.quality).color or Gold(), sound = "IG_BACKPACK_OPEN",
    onClick = function() if K.Journal then K.Journal:Open("inventory") end end,
  })
end

-- After choosing (or straight away when there's nothing to choose).
function R:Settle(e)
  if R.State(e) == "take" then self:Mint(e)
  elseif R.State(e) == "coming" then self:Claim(e) end
  K:Fire("QUESTS")
end

function R:Choose(id, pk)
  local e = Q():Log()[id]
  if not (e and e.items and e.items[pk]) or e.rewarded then return end
  e.claim = { pk = pk }
  self:Settle(e)
end

K:On("QUEST_COMPLETE", function(id)
  local e = Q() and Q():Log()[id]
  if not (e and e.items) or e.rewarded then return end
  if R.State(e) == "choose" then
    C_Timer.After(1.5, function() R:OpenChooser(id) end)
  else
    R:Settle(e)
  end
end)

-- The writer's items, arriving: take them without asking.
function R:Expects(sender, req)
  local key = K.NameKey(sender)
  for _, e in pairs(Q():Log()) do
    if type(e) == "table" and e.items and e.claim and not e.rewarded and R.Req(e) == req and K.NameKey(e.author) == key then
      return e
    end
  end
end

-- A reward that already arrived, sent again (its first answer went astray).
function R:Already(sender, req)
  local key = K.NameKey(sender)
  for _, e in pairs(Q():Log()) do
    if type(e) == "table" and e.items and e.rewarded and R.Req(e) == req and K.NameKey(e.author) == key then return true end
  end
  return false
end

function R:Received(e, r)
  if r.state ~= "accepted" then
    UI.Toast({ icon = e.icon, round = true, duration = 8, color = { 0.90, 0.36, 0.30 },
      title = "Your reward is waiting", text = "Make room in your Kinship bags; " .. Short(e.author) .. " will send it again." })
    return
  end
  e.rewarded = true
  local list = {}
  for _, en in ipairs(r.entries or {}) do list[#list + 1] = { d = en.def.id, n = en.n } end
  self:Toast(e, list)
  K:Fire("QUESTS")
end

---------------------------------------------------------------------------
-- The writer's side
---------------------------------------------------------------------------
function R:Deliver(e, key)
  local T, Items = K.Trade, I()
  local p = e.players and e.players[key]
  local rw = p and p.rw
  if not (T and Items and rw and rw.st == "owed") then return end
  if T:PendingTo(p.name) then return end
  local entries = {}
  for _, it in ipairs(Chosen(e, rw.pk)) do
    if Items:IsMine(it.d) then entries[#entries + 1] = { id = it.d, n = it.n } end
  end
  if #entries == 0 then
    rw.st = "gone"
    K:Print(("The reward for %s is no longer among your designs, so %s can't be sent it."):format(UI.Clean(e.title), Short(p.name)))
    return
  end
  rw.t = time()
  local o = T:Offer(p.name, entries, { src = "mint", quiet = true, req = R.Req(e) })
  if o then rw.tid = o.id end
end

K.Net:On("qclaim", function(msg, sender)
  local QQ = Q()
  if not QQ or type(msg) ~= "table" or type(msg.id) ~= "string" or #msg.id > 96 then return end
  local e = QQ:Log()[msg.id] or nil
  if not (e and QQ:IsMine(e) and e.items) then return end
  local key = K.NameKey(sender)
  local p = key and e.players and e.players[key]
  if not p or p.s == "declined" then return end
  p.s = "complete"
  p.rw = p.rw or { st = "owed" }
  if p.rw.st ~= "owed" then
    -- Delivered already: Kinship's trade repeats its own answer, so nothing comes twice.
    return
  end
  if e.pick then
    local pk = tonumber(msg.pk)
    if not (pk and e.items[pk]) then return end
    p.rw.pk = pk
  end
  if not p.rw.told then
    p.rw.told = true
    UI.Toast({ icon = e.icon, round = true, duration = 5, color = Gold(),
      title = Short(sender) .. " earned a reward", text = UI.Clean(e.title) .. "  ·  Kinship sends it for you",
      onClick = function() QQ:Open(e.id) end })
  end
  R:Deliver(e, key)
  K:Fire("QUESTS")
end)

-- How a delivery went.
K:On("TRADE", function(o)
  if type(o) ~= "table" or type(o.req) ~= "string" or o.req:sub(1, 2) ~= "q:" or o.src ~= "mint" then return end
  local QQ = Q()
  for _, e in pairs(QQ and QQ:Log() or {}) do
    if type(e) == "table" and e.players and QQ:IsMine(e) then
      for _, p in pairs(e.players) do
        local rw = p.rw
        if rw and rw.tid == o.id then
          if o.state == "done" and rw.st == "owed" then
            rw.st, rw.at = "paid", time()
            UI.Toast({ icon = e.icon, round = true, duration = 5, color = QQ.DONE,
              title = "Reward delivered to " .. Short(p.name), text = UI.Clean(e.title) })
            K:Fire("QUESTS")
          end
          return
        end
      end
    end
  end
end)

-- How many rewards you've sent and still owe for a quest.
function R.Owed(e)
  local paid, owed = 0, 0
  for _, p in pairs(e.players or {}) do
    if p.rw then
      if p.rw.st == "paid" then paid = paid + 1 elseif p.rw.st == "owed" then owed = owed + 1 end
    end
  end
  return paid, owed
end

-- Keep trying: owed rewards (the writer), and reminders (the player).
local function Sweep()
  local QQ = Q()
  if not (QQ and K:ExtOn("campaigns") and K.Net:Ready()) then return end
  local now = time()
  for _, e in pairs(QQ:Log()) do
    if type(e) == "table" and e.items then
      if QQ:IsMine(e) then
        for key, p in pairs(e.players or {}) do
          if p.rw and p.rw.st == "owed" and now - (p.rw.t or 0) >= RETRY - 10 then R:Deliver(e, key) end
        end
      elseif R.State(e) == "coming" and e.claim and now - (e.claim.at or 0) >= CLAIM_AGAIN then
        R:Claim(e)
      end
    end
  end
end

K:On("LOGIN", function()
  C_Timer.After(20, function()
    -- Remind writers straight away after logging in.
    for _, e in pairs(Q():Log()) do
      if type(e) == "table" and R.State(e) == "coming" then R:Claim(e) end
    end
    if C_Timer.NewTicker then C_Timer.NewTicker(RETRY, function() K.Try("quest rewards", Sweep) end) end
  end)
end)

---------------------------------------------------------------------------
-- Choosing a reward
---------------------------------------------------------------------------
local function BuildChooser()
  local m = UI.Modal(UIParent, 400, 236, function() R.chooser:Hide() end)
  R.chooser = m
  m:SetFrameStrata("DIALOG")
  local card = m.card
  m.head = UI.Section(card, "Choose your reward")
  m.head:SetPoint("TOPLEFT", 21, -15)
  m.quest = UI.Text(card, "", "Small", "subtle", 340)
  m.quest:SetPoint("TOPLEFT", 20, -40)
  m.quest:SetWordWrap(false)
  m.slots = {}
  for j = 1, R.MAX do
    local s = I().NewSlot(card, 46)
    s:SetPoint("TOPLEFT", 20 + (j - 1) * 92, -66)
    s.name = UI.Text(card, "", "Small", "text", 84)
    s.name:SetPoint("TOP", s, "BOTTOM", 0, -6)
    s.name:SetJustifyH("CENTER")
    s:SetScript("OnEnter", function(self)
      local it = m.e and m.e.items[j]
      if it then I():ShowTooltip(self, I():Get(it.d), it.n) end
    end)
    s:SetScript("OnLeave", function() GameTooltip:Hide() end)
    s:SetScript("OnClick", function() m.pk = j; m:Paint() end)
    m.slots[j] = s
  end
  m.ok = UI.Button(card, "Take it", 110, 26)
  m.ok:SetPoint("BOTTOMRIGHT", -16, 14)
  m.ok:SetScript("OnClick", function()
    if m.e and m.pk then R:Choose(m.e.id, m.pk); m:Hide() end
  end)
  m.later = UI.Button(card, "Later", 80, 26)
  m.later:SetPoint("RIGHT", m.ok, "LEFT", -8, 0)
  m.later:SetScript("OnClick", function() m:Hide() end)
  m.note = UI.Text(card, "You can choose later from the quest.", "Small", "subtle", 190)
  m.note:SetPoint("BOTTOMLEFT", 20, 22)
  function m:Paint()
    local items = self.e and self.e.items or {}
    for j, s in ipairs(self.slots) do
      local it = items[j]
      s:SetShown(it ~= nil)
      s.name:SetShown(it ~= nil)
      if it then
        local def = I():Get(it.d)
        s:SetItem(def, it.n)
        s:SetSelected(self.pk == j)
        s.name:SetText(def and UI.Escape(def.name) or "?")
      end
    end
    self.ok:SetEnabled(self.pk ~= nil)
  end
  return m
end

function R:OpenChooser(id)
  local e = Q():Log()[id]
  if R.State(e) ~= "choose" or not I() then return end
  local m = self.chooser or BuildChooser()
  m.e, m.pk = e, nil
  m.quest:SetText(UI.Clean(e.title))
  m:Paint()
  m:Show()
end

---------------------------------------------------------------------------
-- On the quest sheet: the items, and where the reward stands
---------------------------------------------------------------------------
-- Lays out under y on sheet s's body; returns the height used. q nil hides it all.
function R:PaintSheet(s, q, y)
  local items = q and q.items
  local box = s.rwBox
  if not items or not I() then
    if box then box:Hide() end
    return 0
  end
  if not box then
    box = CreateFrame("Frame", nil, s.body)
    s.rwBox = box
    box.label = UI.Text(box, "", "Small", "subtle", 300)
    box.label:SetPoint("TOPLEFT", 2, 0)
    box.slots = {}
    for j = 1, R.MAX do
      local sl = I().NewSlot(box, 34)
      sl:SetScript("OnEnter", function(self)
        if self.it then I():ShowTooltip(self, I():Get(self.it.d), self.it.n) end
      end)
      sl:SetScript("OnLeave", function() GameTooltip:Hide() end)
      box.slots[j] = sl
    end
    box.status = UI.Text(box, "", "Small", "subtle", 260)
    box.act = UI.Button(box, "", 128, 22)
  end
  box:SetWidth(s.bw)
  box:ClearAllPoints()
  box:SetPoint("TOPLEFT", 0, y)
  box:Show()
  local state = q.id and Q():Log()[q.id] == q and R.State(q) or nil
  local mine = Q():IsMine(q)
  box.label:SetText(q.pick and "Choose one of these Kinship items:" or "Kinship items:")
  local x = 2
  local chosen = q.claim and q.claim.pk
  for j, sl in ipairs(box.slots) do
    local it = items[j]
    sl:SetShown(it ~= nil)
    sl.it = it
    if it then
      sl:ClearAllPoints()
      sl:SetPoint("TOPLEFT", x, -16)
      sl:SetItem(I():Get(it.d), it.n)
      sl:SetSelected(q.pick and chosen == j or false)
      x = x + 40
    end
  end
  -- Where it stands
  local text, act, fn = "", nil, nil
  if state == "choose" then
    text, act, fn = "Choose your reward.", "Choose", function() R:OpenChooser(q.id) end
  elseif state == "take" then
    text, act, fn = "Ready for you.", "Take your reward", function() R:Mint(q) end
  elseif state == "coming" then
    text, act, fn = "On its way: it arrives when you and " .. Short(q.author) .. " are both online.", "Ask again", function() R:Claim(q) end
  elseif state == "got" then
    text = "Received."
  elseif mine and q.players and q.id and Q():Log()[q.id] == q then
    local paid, owed = R.Owed(q)
    if paid + owed > 0 then
      text = ("Sent to %d %s"):format(paid, paid == 1 and "player" or "players")
        .. (owed > 0 and (", %d still to send (Kinship keeps trying)"):format(owed) or "") .. "."
    else
      text = "Kinship sends these for you when players finish."
    end
  elseif not q.id or not Q():Log()[q.id] then
    text = mine and "Made from your designs and sent for you when players finish." or ""
  end
  box.status:SetText(text)
  box.status:ClearAllPoints()
  box.status:SetPoint("TOPLEFT", 2, -56)
  box.act:SetShown(act ~= nil)
  local h = 56 + (text ~= "" and (math.ceil(box.status:GetStringHeight()) + 4) or 0)
  if act then
    box.act:SetText(act)
    box.act:SetScript("OnClick", fn)
    box.act:ClearAllPoints()
    box.act:SetPoint("TOPLEFT", 2, -h - 2)
    h = h + 28
  end
  box:SetHeight(h)
  return h + 6
end
