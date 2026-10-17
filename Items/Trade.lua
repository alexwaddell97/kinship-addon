-- Kinship RP: giving items to other Kinship players.
-- The giver offers items (their full designs, and any document they carry)
-- by addon whisper. The recipient accepts or declines; on accept their
-- client adds the items and answers "received", and only then does the
-- giver's client take the items out of their bags (or stash). While an offer
-- is open the items are held back, so they can't be used, dropped or offered
-- twice. A "received" that arrives late still settles the trade, and offers
-- survive a /reload, so items are neither duplicated nor lost when a message
-- goes astray.
--   itemOffer  giver -> recipient   { id, items = { { d = def, n, doc }, ... }, req }
--   itemReply  recipient -> giver   { id, ok, why }
--   itemDone   giver -> recipient   { id }   (stops the recipient repeating its answer)

local ADDON, ns = ...
local K = ns.K
local UI = K.UI
local Safe = K.Safe
local I = K.Items
local Num = I.Num
local T = { inc = {}, sent = {}, recv = {} }
K.Trade = T
K.Net:Gate({ "itemOffer", "itemReply", "itemDone" }, "inventory")

local OFFER_WINDOW = 60     -- seconds the recipient has to answer
local SENDER_TIMEOUT = 80   -- after this the giver's items are free again
local LATE_GRACE = 900      -- a late "received" still settles the trade
local MAX_ENTRIES = 8
local SEND_LIMIT, SEND_WINDOW = 6, 60
local RECV_LIMIT, RECV_WINDOW = 4, 120

local REASONS = {
  declined = "turned it down",
  busy = "is still answering another offer from you",
  full = "has no room in their bags",
  closed = "isn't accepting items",
  expired = "didn't answer in time",
}

local function Short(n) return I.Short(n) end
local function Now() return time() end

-- Outgoing offers are saved, so a reload mid-trade can't duplicate items.
local function Outbox()
  local key = K:CharKey()
  K.db.tradeOut[key] = K.db.tradeOut[key] or {}
  return K.db.tradeOut[key]
end

---------------------------------------------------------------------------
-- Where the items come from: your bags, or one of your stashes
---------------------------------------------------------------------------
local function StashId(src) return type(src) == "string" and src:match("^stash:(.+)$") end

local function SrcCount(src, id)
  if src == "bag" then return I:CountOf(id) end
  if src == "mint" then return I:IsMine(id) and 9999 or 0 end   -- made from your design (quest rewards)
  local sid = StashId(src)
  return sid and K.Stashes and K.Stashes:CountIn(sid, id) or 0
end

local function SrcRemove(src, id, n, slot)
  local have = SrcCount(src, id)
  n = math.min(n, have)
  if n <= 0 then return 0 end
  if src == "mint" then return n end
  if src == "bag" then
    I:Remove(id, n, slot)
  else
    local sid = StashId(src)
    if not (sid and K.Stashes and K.Stashes:TakeOut(sid, id, n)) then return 0 end
  end
  return n
end

-- How many of an item are promised in open offers from a source.
function T:Reserved(src, id)
  local n = 0
  if not K.db or not K.db.tradeOut then return 0 end
  for _, o in pairs(Outbox()) do
    if o.state == "pending" and o.src == src then
      for _, e in ipairs(o.items) do if e.id == id then n = n + e.n end end
    end
  end
  return n
end

function T:PendingTo(name)
  local key = K.NameKey(name)
  for _, o in pairs(Outbox()) do
    if o.state == "pending" and o.key == key then return o end
  end
end

---------------------------------------------------------------------------
-- Giving
---------------------------------------------------------------------------
local function Allowed()
  local now = GetTime()
  local kept = {}
  for _, t in ipairs(T.sent) do if now - t < SEND_WINDOW then kept[#kept + 1] = t end end
  T.sent = kept
  return #kept < SEND_LIMIT
end

-- entries = { { id, n, slot }, ... }; opts = { src = "bag" | "stash:<id>", req, quiet }
-- Returns the offer, or nil and a reason.
function T:Offer(target, entries, opts)
  opts = opts or {}
  local src = opts.src or "bag"
  if type(target) ~= "string" or strtrim(target) == "" then return nil, "Who should receive it?" end
  target = strtrim(target)
  local key = K.NameKey(target)
  if not key or key == K.NameKey(K:MyName()) then return nil, "You can't give items to yourself." end
  if K:IsIgnored(target) then return nil, "You're ignoring " .. Short(target) .. "." end
  if not K.Net:Ready() then return nil, "Kinship can't send messages right now." end
  if self:PendingTo(target) then return nil, "You're already waiting on " .. Short(target) .. "." end
  if not Allowed() then return nil, "Slow down a little: too many offers in a minute." end
  if type(entries) ~= "table" or #entries == 0 or #entries > MAX_ENTRIES then return nil, "Choose something to give." end

  local items, msgItems = {}, {}
  for _, e in ipairs(entries) do
    local def = I:Get(e.id)
    local n = math.floor(Num(e.n) or 0)
    if not def or n < 1 then return nil, "Choose something to give." end
    if SrcCount(src, e.id) - self:Reserved(src, e.id) < n then return nil, "You don't have that many to give." end
    items[#items + 1] = { id = e.id, n = n, slot = e.slot }
    local doc = def.documentId and K.Documents and K.Documents:Pack(def.documentId) or nil
    msgItems[#msgItems + 1] = { d = I:Pack(e.id), n = n, doc = doc }
  end

  local tid = ("%d%06d"):format(Now(), math.random(0, 999999))
  if not K.Net:Send("itemOffer", { id = tid, items = msgItems, req = opts.req }, "WHISPER", target) then
    return nil, "The offer couldn't be sent."
  end
  self.sent[#self.sent + 1] = GetTime()
  local o = { id = tid, to = target, key = key, items = items, src = src, t = Now(), state = "pending",
              quiet = opts.quiet, req = opts.req }
  Outbox()[tid] = o
  K:Fire("TRADE", o)
  K:Fire("INVENTORY")
  C_Timer.After(SENDER_TIMEOUT, function()
    if o.state == "pending" then
      o.state = "expired"
      if not o.quiet then T:Notify(o, "expired") end
      K:Fire("TRADE", o)
      K:Fire("INVENTORY")
    end
  end)
  return o
end

local function Describe(o)
  local e = o.items[1]
  local def = e and I:Get(e.id)
  local s = I:Label(def, e and e.n)
  if #o.items > 1 then s = s .. (" and %d more"):format(#o.items - 1) end
  return s, def
end

-- A toast for the giver about how an offer ended.
function T:Notify(o, why)
  local what, def = Describe(o)
  local good = why == "done"
  UI.Toast({
    icon = def and I.IconTexture(def.icon) or I.DEFAULT_ICON, iconCoords = { 0.08, 0.92, 0.08, 0.92 },
    title = good and ("Given to " .. Short(o.to)) or (Short(o.to) .. " " .. (REASONS[why] or REASONS.declined)),
    text = good and what or (what .. " stays with you."),
    color = good and I.Quality(def and def.quality).color or { 0.90, 0.36, 0.30 },
    duration = 6,
  })
end

local function Settle(o)
  for _, e in ipairs(o.items) do SrcRemove(o.src, e.id, e.n, e.slot) end
  o.state = "done"
  o.doneAt = Now()
  K.Net:Send("itemDone", { id = o.id }, "WHISPER", o.to)
  if StashId(o.src) and K.Stashes then
    K.Stashes:Taken(StashId(o.src), o)
  elseif not o.quiet then
    T:Notify(o, "done")
  end
  K:Fire("TRADE", o)
  K:Fire("INVENTORY")
end

K.Net:On("itemReply", function(msg, sender)
  if type(msg.id) ~= "string" then return end
  local o = Outbox()[msg.id]
  if not o or o.key ~= K.NameKey(sender) then return end
  if msg.ok == true then
    if o.state == "done" then
      K.Net:Send("itemDone", { id = o.id }, "WHISPER", o.to)
    else
      Settle(o)
    end
  elseif o.state == "pending" or o.state == "expired" then
    o.state = "declined"
    local why = type(msg.why) == "string" and REASONS[msg.why] and msg.why or "declined"
    if not o.quiet then T:Notify(o, why) end
    if StashId(o.src) and K.Stashes then K.Stashes:TakeFailed(o, why) end
    K:Fire("TRADE", o)
    K:Fire("INVENTORY")
  end
end)

---------------------------------------------------------------------------
-- Receiving
---------------------------------------------------------------------------
local function Reply(r, ok, why)
  K.Net:Send("itemReply", { id = r.id, ok = ok, why = why }, "WHISPER", r.from)
end

-- Parse an offer's items; nil when nothing in it is valid.
local function ParseItems(raw)
  if type(raw) ~= "table" then return nil end
  local out = {}
  for i = 1, MAX_ENTRIES do
    local e = raw[i]
    if type(e) ~= "table" then break end
    local def = I.Sanitize(e.d)
    local n = math.floor(Num(e.n) or 0)
    if def and n >= 1 and n <= 999 then
      local doc
      if def.documentId and K.Documents then
        doc = K.Documents.Sanitize(e.doc)
        if doc and doc.id ~= def.documentId then doc = nil end
      end
      out[#out + 1] = { def = def, n = n, doc = doc }
    end
  end
  return #out > 0 and out or nil
end

local function Fits(r)
  local list = {}
  for _, e in ipairs(r.entries) do
    local known = I:Get(e.def.id)
    list[#list + 1] = { id = e.def.id, n = e.n, stack = known and known.stack or e.def.stack }
  end
  return I:Fits(list)
end

function T:Accept(key)
  local r = self.inc[key]
  if not r or r.state ~= "pending" then return end
  if GetTime() - r.at > OFFER_WINDOW then
    r.state = "declined"
    I.Error("That offer has expired.")
    return
  end
  if not Fits(r) then
    r.state = "declined"
    Reply(r, false, "full")
    I.Error("There's no room in your bags.")
    return
  end
  for _, e in ipairs(r.entries) do
    if e.doc then K.Documents:Learn(e.doc) end
    local def = I:Learn(e.def)
    if def then I:Add(def.id, e.n) end
  end
  r.state = "accepted"
  if SOUNDKIT and SOUNDKIT.IG_BACKPACK_OPEN then PlaySound(SOUNDKIT.IG_BACKPACK_OPEN) end
  Reply(r, true)
  -- Say it again until the giver confirms, in case the first answer is lost.
  for _, delay in ipairs({ 6, 20, 60 }) do
    C_Timer.After(delay, function() if not r.done then Reply(r, true) end end)
  end
  local first = r.entries[1]
  local def = I:Get(first.def.id)
  if not r.req then
    K:Print(("You received %s from %s."):format(I:Label(def, first.n), Short(r.from)))
  end
  if self.offerFrame and self.offerFrame.key == key then self.offerFrame:Hide() end
  K:Fire("TRADE")
end

function T:Decline(key, why)
  local r = self.inc[key]
  if not r or r.state ~= "pending" then return end
  r.state = "declined"
  Reply(r, false, why or "declined")
  if self.offerFrame and self.offerFrame.key == key then self.offerFrame:Hide() end
end

K.Net:On("itemDone", function(msg, sender)
  if type(msg.id) ~= "string" then return end
  local r = T.inc[(K.NameKey(sender) or "") .. "|" .. msg.id]
  if r then r.done = true end
end)

K.Net:On("itemOffer", function(msg, sender, channel)
  if channel ~= "WHISPER" or type(msg.id) ~= "string" or #msg.id > 40 then return end
  if not Safe(sender) or K:IsIgnored(sender) then return end
  local from = K.NameKey(sender)
  if not from then return end
  local key = from .. "|" .. msg.id
  local seen = T.inc[key]
  if seen then
    -- The same offer again: repeat our answer, never add the items twice.
    if seen.state == "accepted" then Reply(seen, true)
    elseif seen.state == "declined" then Reply(seen, false, "declined") end
    return
  end

  local now = GetTime()
  local rl = T.recv[from]
  if not rl or now - rl.start > RECV_WINDOW then rl = { start = now, n = 0 }; T.recv[from] = rl end
  rl.n = rl.n + 1
  if rl.n > RECV_LIMIT then return end

  local entries = ParseItems(msg.items)
  if not entries then return end
  local req = type(msg.req) == "string" and #msg.req <= 40 and msg.req or nil
  local r = { id = msg.id, from = sender, fromKey = from, entries = entries, at = now, state = "pending", req = req }
  T.inc[key] = r

  -- Something you asked a stash for: take it without asking.
  if req and K.Stashes and K.Stashes:ExpectsTake(sender, req) then
    T:Accept(key)
    K.Stashes:Received(sender, req, r)
    return
  end
  -- Kinship items from a trade that just went through, as the trade window showed them
  local TW = K.TradeWindow
  if req and TW and TW:Expects(sender, req, entries) then
    T:Accept(key)
    TW:Received(sender, r)
    return
  end
  -- A quest reward you claimed: take it without asking (or, if it already came, just say so).
  local QR = K.QuestRewards
  local quest = req and QR and QR:Expects(sender, req)
  if quest then
    T:Accept(key)
    QR:Received(quest, r)
    return
  end
  if req and QR and QR:Already(sender, req) then
    r.state = "accepted"
    Reply(r, true)
    return
  end
  if not K.db.settings.itemOffers then r.state = "declined"; Reply(r, false, "closed") return end
  for k, other in pairs(T.inc) do
    if k ~= key and other.fromKey == from and other.state == "pending" and now - other.at < OFFER_WINDOW then
      r.state = "declined"
      Reply(r, false, "busy")
      return
    end
  end

  C_Timer.After(OFFER_WINDOW, function() if r.state == "pending" then T:Decline(key, "expired") end end)
  local first = entries[1]
  local d = first.def
  local qc = I.Quality(d.quality).color
  local text = I:Label(d, first.n)
  if #entries > 1 then text = text .. (" and %d more"):format(#entries - 1) end
  if d.description ~= "" then
    local line = d.description:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("\n.*", "")
    text = text .. "\n|cffb8b0a0" .. UI.Escape(I.Cut(line, 90)) .. "|r"
  end
  UI.Toast({
    icon = I.IconTexture(d.icon), iconCoords = { 0.08, 0.92, 0.08, 0.92 },
    title = Short(sender) .. " offers you " .. (#entries == 1 and first.n == 1 and "an item" or "items"),
    text = text, color = qc, duration = OFFER_WINDOW - 4, sound = "TELL_MESSAGE",
    onClick = function() T:ShowOffer(key) end,
    actions = { { label = "Decline", fn = function() T:Decline(key) end }, { label = "Accept", fn = function() T:Accept(key) end } },
  })
end)

---------------------------------------------------------------------------
-- The offer card: a closer look before accepting (click the toast)
---------------------------------------------------------------------------
function T:ShowOffer(key)
  local r = self.inc[key]
  if not r or r.state ~= "pending" then return end
  local f = self.offerFrame
  if not f then
    f = UI.Window("KinshipRPItemOffer", "An offer", 360, 330)
    f:SetFrameStrata("DIALOG")
    f.slot = I.NewSlot(f, 52)
    f.slot:SetPoint("TOPLEFT", 18, -52)
    f.name = UI.Text(f, "", "Title", "fixed", 260)
    f.name:SetPoint("TOPLEFT", f.slot, "TOPRIGHT", 12, -4)
    f.name:SetWordWrap(false)
    f.from = UI.Text(f, "", "Small", "deskSubtle", 260)
    f.from:SetPoint("TOPLEFT", f.name, "BOTTOMLEFT", 0, -5)
    f.desc = UI.Text(f, "", "Body", "deskText", 324)
    f.desc:SetPoint("TOPLEFT", 18, -120)
    f.desc:SetSpacing(3)
    f.desc:SetMaxLines(6)
    f.extra = UI.Text(f, "", "Small", "deskAccent", 324)
    f.extra:SetPoint("BOTTOMLEFT", 18, 54)
    f.timer = UI.Text(f, "", "Small", "deskSubtle")
    f.timer:SetPoint("BOTTOMLEFT", 18, 22)
    f.accept = UI.Button(f, "Accept", 96, 26)
    f.accept:SetPoint("BOTTOMRIGHT", -16, 16)
    f.accept:SetScript("OnClick", function() T:Accept(f.key) end)
    f.decline = UI.Button(f, "Decline", 96, 26)
    f.decline:SetPoint("RIGHT", f.accept, "LEFT", -8, 0)
    f.decline:SetScript("OnClick", function() T:Decline(f.key) end)
    f:HookScript("OnUpdate", function(self)
      local rr = T.inc[self.key or ""]
      if not rr or rr.state ~= "pending" then self:Hide() return end
      self.timer:SetText(("Expires in %ds"):format(math.max(0, math.ceil(OFFER_WINDOW - (GetTime() - rr.at)))))
    end)
    self.offerFrame = f
  end
  f.key = key
  local e = r.entries[1]
  local d = e.def
  local qc = I.Quality(d.quality).color
  f.slot:SetItem(d, e.n)
  f.slot.def = d
  f.name:SetText(UI.Escape(d.name) .. (e.n > 1 and (" x" .. e.n) or ""))
  f.name:SetTextColor(qc[1], qc[2], qc[3])
  f.from:SetText(("From %s  ·  %s"):format(Short(r.from), I.Quality(d.quality).label))
  local body = d.description ~= "" and UI.Clean(d.description) or "No description."
  if d.flavor ~= "" then body = body .. "\n|cffe6c97a\"" .. UI.Clean(d.flavor) .. "\"|r" end
  f.desc:SetText(body)
  local extra = {}
  if d.useText ~= "" then extra[#extra + 1] = "Use: " .. UI.Escape(d.useText) end
  if e.doc then extra[#extra + 1] = "Carries writing: " .. UI.Escape(K.Documents.Title(e.doc)) end
  if #r.entries > 1 then extra[#extra + 1] = ("And %d more item%s."):format(#r.entries - 1, #r.entries > 2 and "s" or "") end
  f.extra:SetText(table.concat(extra, "\n"))
  f:Show()
  f:Raise()
end

---------------------------------------------------------------------------
-- The give window: pick an item from your bags and offer it
---------------------------------------------------------------------------
local GW, GH = 380, 460
local COLS, CELL, GAP = 7, 44, 6

local function TargetName(unit)
  if not unit or not UnitExists(unit) then return nil end
  local n = GetUnitName(unit, true)
  if Safe(n) and type(n) == "string" and n ~= "" then return n end
end

function T:BuildGive()
  if self.give then return self.give end
  local f = UI.Window("KinshipRPGive", "Give an item", GW, GH)
  f:SetFrameStrata("DIALOG")
  self.give = f
  f.to = UI.Field(f, "To", 220, 60, nil, "desk")
  f.to:SetPoint("TOPLEFT", 18, -46)
  K.Suggest(f.to.edit)   -- names you know, as you type
  f.toTarget = UI.Button(f, "My target", 96, 23)
  f.toTarget:SetPoint("TOPLEFT", 248, -60)
  f.toTarget:SetScript("OnClick", function()
    local n = TargetName("target")
    if n and UnitIsPlayer("target") then f.to.edit:SetText(n) else I.Error("Target a player first.") end
  end)

  local sec = UI.Section(f, "From your bags", true)
  sec:SetPoint("TOPLEFT", 25, -104)
  f.cells = {}
  for i = 1, I.SLOTS do
    local s = I.NewSlot(f, CELL)
    s:SetPoint("TOPLEFT", 18 + ((i - 1) % COLS) * (CELL + GAP), -124 - math.floor((i - 1) / COLS) * (CELL + GAP))
    s.tooltipAnchor = "ANCHOR_RIGHT"
    s:SetScript("OnClick", function(self)
      if not self.slot then return end
      f.slot = self.slot
      f.n = 1
      T:RefreshGive()
    end)
    f.cells[i] = s
  end
  f.empty = UI.Text(f, "Your bags are empty. Make something in the Workshop first.", "Body", "deskSubtle", GW - 60)
  f.empty:SetPoint("TOP", 0, -190)
  f.empty:SetJustifyH("CENTER")

  local y = -124 - 5 * (CELL + GAP) - 4
  f.pick = UI.Text(f, "", "Header", "fixed", 200)
  f.pick:SetPoint("TOPLEFT", 18, y - 4)
  f.pick:SetWordWrap(false)
  f.plus = UI.Button(f, "+", 26, 24)
  f.plus:SetPoint("TOPRIGHT", -18, y)
  f.count = UI.Text(f, "1", "Header", "deskHeading")
  f.count:SetPoint("RIGHT", f.plus, "LEFT", -12, 0)
  f.minus = UI.Button(f, "-", 26, 24)
  f.minus:SetPoint("RIGHT", f.plus, "LEFT", -44, 0)
  local function step(d)
    local s = f.slot and I:Slot(f.slot)
    if not s then return end
    local max = math.max(1, I:Available(s.def))
    f.n = IsShiftKeyDown() and (d > 0 and max or 1) or math.max(1, math.min(max, (f.n or 1) + d))
    T:RefreshGive()
  end
  f.plus:SetScript("OnClick", function() step(1) end)
  f.minus:SetScript("OnClick", function() step(-1) end)
  UI.Tooltip(f.plus, "More", "Shift-click for all of them.")

  f.status = UI.Text(f, "", "Small", "deskSubtle", 220)
  f.status:SetPoint("BOTTOMLEFT", 18, 22)
  f.offer = UI.Button(f, "Offer", 110, 26)
  f.offer:SetPoint("BOTTOMRIGHT", -16, 16)
  f.offer:SetScript("OnClick", function()
    local s = f.slot and I:Slot(f.slot)
    if not s then I.Error("Choose an item to give.") return end
    local o, err = T:Offer(f.to.edit:GetText(), { { id = s.def, n = f.n or 1, slot = f.slot } })
    if not o then I.Error(err) return end
    f.waiting = o
    if SOUNDKIT and SOUNDKIT.IG_BACKPACK_CLOSE then PlaySound(SOUNDKIT.IG_BACKPACK_CLOSE) end
    T:RefreshGive()
  end)
  f.dots = 0
  f:HookScript("OnUpdate", function(self, elapsed)
    if not self.waiting or self.waiting.state ~= "pending" then return end
    self.dots = (self.dots or 0) + elapsed
    local n = math.floor(self.dots * 2) % 4
    self.status:SetText("Waiting for " .. Short(self.waiting.to) .. string.rep(".", n))
  end)
  K:On("TRADE", function() if f:IsShown() then T:RefreshGive() end end)
  K:On("INVENTORY", function() if f:IsShown() then T:RefreshGive() end end)
  return f
end

function T:RefreshGive()
  local f = self.give
  if not f then return end
  local bag = I:Bag()
  local idx = 0
  for i = 1, I.SLOTS do
    local s = bag[i]
    if s then
      idx = idx + 1
      local cell = f.cells[idx]
      cell.slot = i
      local def = I:Get(s.def)
      cell:SetItem(def, s.count, true)
      cell:SetSelected(f.slot == i)
      cell:SetLocked(I:Available(s.def) < 1)
      cell:Show()
    end
  end
  for i = idx + 1, I.SLOTS do f.cells[i].slot = nil; f.cells[i]:Hide() end
  f.empty:SetShown(idx == 0)

  local s = f.slot and bag[f.slot]
  local def = s and I:Get(s.def)
  if not def then f.slot = nil end
  if def then
    local avail = math.max(0, I:Available(s.def))
    f.n = math.max(1, math.min(f.n or 1, math.max(1, avail)))
    local qc = I.Quality(def.quality).color
    f.pick:SetText(UI.Escape(def.name))
    f.pick:SetTextColor(qc[1], qc[2], qc[3])
    f.count:SetText(f.n)
    f.minus:SetEnabled(f.n > 1)
    f.plus:SetEnabled(f.n < avail)
  else
    f.pick:SetText(idx > 0 and "Choose an item" or "")
    f.pick:SetTextColor(unpack(K:Theme().deskSubtle))
    f.count:SetText("")
    f.minus:SetEnabled(false)
    f.plus:SetEnabled(false)
  end
  f.minus:SetShown(def ~= nil)
  f.plus:SetShown(def ~= nil)
  local waiting = f.waiting and f.waiting.state == "pending"
  f.offer:SetEnabled(def ~= nil and not waiting and I:Available(s.def) >= 1)
  if not waiting then
    local w = f.waiting
    if w and w.state == "done" then f.status:SetText("Given to " .. Short(w.to) .. ".")
    elseif w and (w.state == "declined" or w.state == "expired") then f.status:SetText("Not given. It stays with you.")
    else f.status:SetText("They'll be asked to accept it.") end
  end
end

-- Open the give window, for someone (a name) and optionally a bag slot.
function T:OpenGive(name, slot)
  local f = self:BuildGive()
  if f.waiting and f.waiting.state ~= "pending" then f.waiting = nil end
  if name and not f.waiting then f.to.edit:SetText(name) end
  if slot then f.slot, f.n = slot, 1 end
  f:Show()
  f:Raise()
  self:RefreshGive()
  if f.to.edit:GetText() == "" then f.to.edit:SetFocus() end
end

---------------------------------------------------------------------------
-- Target bar button
---------------------------------------------------------------------------
local function CanGiveTo(unit)
  if not unit or not UnitExists(unit) or not UnitIsPlayer(unit) or UnitIsUnit(unit, "player") then return false end
  local ok, enemy = pcall(UnitIsEnemy, "player", unit)
  if ok and Safe(enemy) and enemy then return false end
  local n = TargetName(unit)
  return n ~= nil and not K:IsIgnored(n)
end

K:RegisterTargetButton({
  id = "giveItem", icon = "Interface\\Icons\\INV_Misc_Gift_01", label = "Give an item", order = 50,
  shown = function(unit) return K:ExtOn("inventory") and CanGiveTo(unit) end,
  onClick = function(unit, name)
    local n = TargetName(unit) or (Safe(name) and type(name) == "string" and name) or nil
    T:OpenGive(n)
  end,
})

---------------------------------------------------------------------------
-- Saved data
---------------------------------------------------------------------------
K:On("LOGIN", function()
  K.db.tradeOut = K.db.tradeOut or {}
  local now = Now()
  for tid, o in pairs(Outbox()) do
    if type(o) ~= "table" or type(o.items) ~= "table" or now - (o.t or 0) > LATE_GRACE then
      Outbox()[tid] = nil
    elseif o.state == "pending" then
      local left = SENDER_TIMEOUT - (now - (o.t or 0))
      if left <= 0 then
        o.state = "expired"
      else
        C_Timer.After(left, function()
          if o.state == "pending" then o.state = "expired"; K:Fire("TRADE", o); K:Fire("INVENTORY") end
        end)
      end
    end
  end
end)
