-- Kinship RP: player-written quests and campaigns.
-- Quests you write live in an account-wide library; quests you take on live
-- in your character's log. Offer a quest to your group or your target and run
-- it as its storyteller: tick objectives and everyone who accepted sees them.
-- Messages (K.Net):
--   qoffer  a quest offered to you
--   qack    "I accepted / declined / finished / gave up" (to the author)
--   qprog   the storyteller's progress (trusted only from the quest's author)

local ADDON, ns = ...
local K = ns.K
local UI = K.UI
local Safe = K.Safe
local Q = {}
K.Quests = Q
K.Net:Gate({ "qoffer", "qack", "qprog" }, "campaigns")

local WHITE = "Interface\\Buttons\\WHITE8X8"
Q.MAX = { title = 70, giver = 50, campaign = 50, desc = 1600, objective = 120, objectives = 8, reward = 160 }
local M = Q.MAX
local LOG_MAX, LIB_MAX, PLAYERS_MAX, PENDING_MAX = 200, 200, 40, 5
Q.DEFAULT_ICON = "Interface\\Icons\\INV_Scroll_03"
Q.DONE = { 0.40, 0.80, 0.48 }
Q.STATES = {
  active    = { label = "Active",    color = { 0.95, 0.76, 0.36 } },
  complete  = { label = "Complete",  color = { 0.40, 0.80, 0.48 } },
  abandoned = { label = "Set aside", color = { 0.62, 0.62, 0.66 } },
  failed    = { label = "Failed",    color = { 0.90, 0.36, 0.30 } },
}
Q.pending = {}

-- Icons offered when there's no shared icon picker.
Q.ICONS = {
  "INV_Scroll_03", "INV_Misc_Note_01", "INV_Letter_15", "INV_Misc_Map_01", "INV_Misc_Book_09", "INV_Misc_Bag_10",
  "INV_Misc_Coin_01", "INV_Sword_04", "INV_Shield_05", "INV_Crown_01", "INV_Misc_Key_03", "INV_Jewelry_Amulet_03",
  "INV_Misc_Head_Dragon_01", "Ability_Tracking", "INV_Misc_Spyglass_03", "INV_Misc_Rune_01",
}

---------------------------------------------------------------------------
-- Helpers
---------------------------------------------------------------------------
local Short = K.Short
Q.Short = Short

-- A string from anywhere (an edit box or the network), trimmed and capped.
-- multiline keeps line breaks; everything else loses control characters.
local function Str(v, max, multiline)
  if type(v) ~= "string" then return "" end
  if multiline then
    v = v:gsub("\r\n", "\n"):gsub("[%z\1-\9\11-\31]", "")
  else
    v = v:gsub("%c", " ")
  end
  v = strtrim(v)
  if #v > max then v = v:sub(1, max) end
  return v
end
Q.Str = Str

-- An icon: a file ID, "Interface\Icons\Name" or a bare icon name.
function Q.ValidIcon(v)
  if type(v) == "number" then
    if v > 0 and v < 2147483647 and v == math.floor(v) then return v end
    return nil
  end
  if type(v) ~= "string" or v == "" or #v > 120 then return nil end
  if v:find("^%d+$") then return Q.ValidIcon(tonumber(v)) end
  if v:lower():find("^interface\\icons\\[%w_%-]+$") then return v end
  if v:find("^[%w_%-]+$") then return "Interface\\Icons\\" .. v end
  return nil
end

local function NewID()
  return ("%s-%d-%d"):format(K.NameKey(K:MyName()) or "me", time(), math.random(1000, 9999))
end

local function Sound(name)
  if SOUNDKIT and SOUNDKIT[name] then PlaySound(SOUNDKIT[name]) end
end

local function InGroup(name)
  if type(name) ~= "string" then return false end
  local short = Short(name)
  local ok, inParty = pcall(UnitInParty, short)
  if ok and Safe(inParty) and inParty then return true end
  local ok2, inRaid = pcall(UnitInRaid, short)
  return ok2 and Safe(inRaid) and inRaid ~= nil and inRaid ~= false
end

---------------------------------------------------------------------------
-- Saved data
---------------------------------------------------------------------------
K:On("LOGIN", function()
  K.db.questLibrary = K.db.questLibrary or {}
  K.db.questLibrary.quests = K.db.questLibrary.quests or {}
  K.db.questLog = K.db.questLog or {}
  local s = K.db.settings
  if s.questTracker == nil then s.questTracker = true end
  if s.questOffers == nil then s.questOffers = true end
  -- Finished quests don't stay pinned to the tracker across sessions.
  for _, e in pairs(Q:Log()) do if e.state ~= "active" then e.tracked = false end end
end)

function Q:Library() return K.db.questLibrary.quests end

function Q:Log()
  local key = K:CharKey()
  K.db.questLog[key] = K.db.questLog[key] or {}
  return K.db.questLog[key]
end

function Q:IsMine(e)
  return e ~= nil and type(e.author) == "string" and K.NameKey(e.author) == K.NameKey(K:MyName())
end

-- Objectives ticked, objectives in all, as players see them: optional ones
-- don't count, and hidden ones count once they're done (its writer sees all).
-- A failure that lets the story move on counts as dealt with, and a backup
-- objective waiting for its objective to fail doesn't count at all (QuestAuto.lua).
function Q.Progress(e)
  local done, total = 0, 0
  local mine = Q:IsMine(e)
  local QA = K.QuestAuto
  for i, o in ipairs(e.objectives or {}) do
    local counts = not o.opt and (o.done or not o.hid or mine)
    if counts and QA and QA.Standby(e, i) then counts = false end
    if counts then
      total = total + 1
      if o.done or (QA and QA.Resolved(o)) then done = done + 1 end
    end
  end
  return done, total
end

-- Required objectives dealt with, required objectives in all (what finishing the quest needs).
function Q.Required(e)
  local done, total = 0, 0
  local QA = K.QuestAuto
  for i, o in ipairs(e.objectives or {}) do
    if not o.opt and not (QA and QA.Standby(e, i)) then
      total = total + 1
      if o.done or (QA and QA.Resolved(o)) then done = done + 1 end
    end
  end
  return done, total
end

local function Count(t)
  local n = 0
  for _ in pairs(t) do n = n + 1 end
  return n
end

---------------------------------------------------------------------------
-- Shape: every quest, from the editor or the network, passes through here.
---------------------------------------------------------------------------
function Q:NewDraft()
  return { title = "", giver = "", campaign = "", description = "", reward = "", icon = Q.DEFAULT_ICON, st = true, objectives = {} }
end

-- A clean copy with every field checked. nil if it has no title.
function Q.Sanitize(src)
  if type(src) ~= "table" then return nil end
  local q = {
    id = (type(src.id) == "string" and #src.id <= 96) and src.id or nil,
    title = Str(src.title, M.title),
    giver = Str(src.giver, M.giver),
    campaign = Str(src.campaign, M.campaign),
    description = Str(src.description, M.desc, true),
    reward = Str(src.reward, M.reward),
    icon = Q.ValidIcon(src.icon) or Q.DEFAULT_ICON,
    author = (type(src.author) == "string" and #src.author <= 80) and src.author or nil,
    st = src.st ~= false,
    objectives = {},
  }
  -- Level (or range) and where it happens (QuestMarkers.lua)
  local QM = K.QuestMarkers
  if QM then
    q.level = QM.Level(src.level)
    q.levelMax = q.level and QM.Level(src.levelMax) or nil
    if q.levelMax and q.levelMax <= q.level then q.levelMax = nil end
    q.marker = QM.Sanitize(src.marker)
  end
  -- Kinship items as rewards (QuestRewards.lua)
  local QR = K.QuestRewards
  q.items = QR and QR.Sanitize(src.items) or nil
  q.pick = q.items and #q.items > 1 and src.pick and true or nil
  -- Objectives done in order, and whether a storyteller lets them complete themselves
  q.seq = src.seq and true or nil
  q.au = src.au ~= false
  local QA = K.QuestAuto
  if type(src.objectives) == "table" then
    for i = 1, M.objectives do
      local o = src.objectives[i]
      if o == nil then break end
      local text = Str(type(o) == "table" and o.text or o, M.objective)
      if text ~= "" then
        local ob = {
          text = text, done = false,
          marker = QM and type(o) == "table" and QM.Sanitize(o.marker) or nil,
          auto = QA and type(o) == "table" and QA.Sanitize(o.auto) or nil,
        }
        if QA then ob.opt, ob.hid, ob.fl = QA.Options(o) end
        q.objectives[#q.objectives + 1] = ob
      end
    end
  end
  if q.title == "" then return nil end
  return q
end

-- Compact form for the wire.
function Q.Pack(q)
  local ob, om, oa, oo = {}, nil, nil, nil
  for i, o in ipairs(q.objectives) do
    ob[i] = o.text
    if o.marker then om = om or {}; om[i] = o.marker end
    if o.auto then oa = oa or {}; oa[i] = o.auto end
    if o.opt or o.hid or o.fl then oo = oo or {}; oo[i] = { opt = o.opt, hid = o.hid, fl = o.fl } end
  end
  return { id = q.id, ti = q.title, gv = q.giver, ca = q.campaign, de = q.description, rw = q.reward,
           ic = q.icon, st = q.st and 1 or 0, ob = ob,
           lv = q.level, lx = q.levelMax, mk = q.marker, om = om, oa = oa, oo = oo,
           sq = q.seq and 1 or nil, au = q.au == false and 0 or nil,
           ri = K.QuestRewards and K.QuestRewards.Pack(q) or nil, rp = q.pick and 1 or nil }
end

function Q.Unpack(m)
  if type(m) ~= "table" then return nil end
  local ob = type(m.ob) == "table" and m.ob or nil
  -- Objectives arrive as text, with their markers alongside (newer senders).
  if ob and (type(m.om) == "table" or type(m.oa) == "table" or type(m.oo) == "table") then
    local om = type(m.om) == "table" and m.om or {}
    local oa = type(m.oa) == "table" and m.oa or {}
    local oo = type(m.oo) == "table" and m.oo or {}
    local list = {}
    for i = 1, M.objectives do
      if ob[i] == nil then break end
      local opts = type(oo[i]) == "table" and oo[i] or {}
      list[i] = { text = ob[i], marker = om[i], auto = oa[i], opt = opts.opt, hid = opts.hid, fl = opts.fl }
    end
    ob = list
  end
  return Q.Sanitize({ id = m.id, title = m.ti, giver = m.gv, campaign = m.ca, description = m.de, reward = m.rw,
                      icon = m.ic, st = m.st ~= 0, objectives = ob, level = m.lv, levelMax = m.lx, marker = m.mk,
                      seq = m.sq == 1, au = m.au ~= 0, items = m.ri, pick = m.rp == 1 })
end

---------------------------------------------------------------------------
-- Your library
---------------------------------------------------------------------------
function Q:Save(draft)
  local q = Q.Sanitize(draft)
  if not q then return nil, "Give your quest a title first." end
  local lib = self:Library()
  if not (draft.id and lib[draft.id]) and Count(lib) >= LIB_MAX then
    return nil, "Your library is full. Delete an old quest first."
  end
  q.id = draft.id or NewID()
  q.author = K:MyName()
  q.created = (lib[q.id] and lib[q.id].created) or time()
  q.edited = time()
  lib[q.id] = q
  -- Your own running copy takes the edit too (keeping what's already done),
  -- so new markers, levels and wording reach your journal, tracker and map.
  local e = self:Log()[q.id]
  if e and e.state == "active" and self:IsMine(e) then
    for _, k in ipairs({ "title", "giver", "campaign", "description", "reward", "icon", "level", "levelMax", "marker", "st", "seq", "au",
                         "items", "pick" }) do
      e[k] = q[k]
    end
    local old, objs = e.objectives or {}, {}
    for i, o in ipairs(q.objectives) do
      local was = old[i]
      objs[i] = { text = o.text, marker = o.marker, auto = o.auto, opt = o.opt, hid = o.hid, fl = o.fl,
                  done = (was and was.text == o.text and was.done) or false }
    end
    e.objectives = objs
  end
  K:Fire("QUESTS")
  return q
end

function Q:Delete(id)
  self:Library()[id] = nil
  K:Fire("QUESTS")
end

---------------------------------------------------------------------------
-- Your log
---------------------------------------------------------------------------
local function TrimLog(log)
  if Count(log) <= LOG_MAX then return end
  local old = {}
  for id, e in pairs(log) do
    if e.state ~= "active" then old[#old + 1] = { id = id, t = e.completed or e.accepted or 0 } end
  end
  table.sort(old, function(a, b) return a.t < b.t end)
  for i = 1, math.min(#old, Count(log) - LOG_MAX) do log[old[i].id] = nil end
end

local function NewEntry(q, author)
  local e = CopyTable(q)
  e.author = author
  e.state, e.accepted, e.completed = "active", time(), nil
  e.tracked = true
  for _, o in ipairs(e.objectives) do o.done = false end
  return e
end

-- Begin one of your own quests (as its storyteller).
function Q:Start(id)
  local q = self:Library()[id]
  if not q then return nil end
  local log = self:Log()
  local e = log[id]
  if e and e.state == "active" then return e end
  local players = e and e.players
  e = NewEntry(q, K:MyName())
  e.players = players or {}
  log[id] = e
  TrimLog(log)
  K:AddEntry("milestone", ("Set a quest in motion: %s"):format(UI.Clean(e.title)), e.giver ~= "" and ("Given by " .. UI.Clean(e.giver)) or nil)
  K:Fire("QUESTS")
  K:Fire("QUEST_ACCEPTED", id)
  return e
end

local lastShare = {}
-- how: "group" or "target". Returns ok, message.
function Q:Share(id, how)
  local q = self:Library()[id]
  if not q then return false, "Save the quest first." end
  local channel, target
  if how == "target" then
    if not UnitExists("target") or not UnitIsPlayer("target") or UnitIsUnit("target", "player") then
      return false, "Target another player first."
    end
    local n = GetUnitName("target", true)
    if not Safe(n) or not n then return false, "Couldn't read your target's name." end
    channel, target = "WHISPER", n
  else
    if not IsInGroup() then return false, "You're not in a group." end
    channel = IsInRaid() and "RAID" or "PARTY"
  end
  local key = id .. (target or channel)
  if lastShare[key] and GetTime() - lastShare[key] < 5 then return false, "Give them a moment to answer." end
  if not K.Net:Send("qoffer", Q.Pack(q), channel, target) then
    return false, "Couldn't send it right now. Try again in a moment."
  end
  lastShare[key] = GetTime()
  self:Start(id)   -- you run it as its storyteller
  return true, target and ("Offered to " .. Short(target) .. ".") or "Offered to your group."
end

function Q:Accept(offer)
  local e = NewEntry(offer.q, offer.from)
  local log = self:Log()
  log[e.id] = e
  TrimLog(log)
  K:AddEntry("milestone", ("Accepted the quest %s"):format(UI.Clean(e.title)),
    ("Given by %s"):format(e.giver ~= "" and UI.Clean(e.giver) or Short(offer.from)))
  K.Net:Send("qack", { id = e.id, s = "active" }, "WHISPER", offer.from)
  Sound("IG_QUEST_LIST_OPEN")
  K:Fire("QUESTS")
  K:Fire("QUEST_ACCEPTED", e.id)
  return e
end

function Q:Decline(offer)
  K.Net:Send("qack", { id = offer.q.id, s = "declined" }, "WHISPER", offer.from)
end

function Q:CanTick(e)
  return e ~= nil and e.state == "active" and (self:IsMine(e) or not e.st)
end

local function Bits(e)
  local b = {}
  for i, o in ipairs(e.objectives) do b[i] = o.done and "1" or (o.failed and "2" or "0") end
  return table.concat(b)
end

-- Storyteller: send the current state to everyone following (debounced).
local pushing = {}
function Q:Push(e)
  if not e.players or not next(e.players) or pushing[e.id] then return end
  pushing[e.id] = true
  C_Timer.After(0.6, function()
    pushing[e.id] = nil
    local msg = { id = e.id, o = Bits(e), s = e.state }
    local viaGroup = IsInGroup() and K.Net:Send("qprog", msg, IsInRaid() and "RAID" or "PARTY")
    for _, p in pairs(e.players) do
      if (p.s == "active" or p.s == "complete") and not (viaGroup and InGroup(p.name)) then
        K.Net:Send("qprog", { id = msg.id, o = msg.o, s = msg.s }, "WHISPER", p.name)
      end
    end
  end)
end

function Q:CheckComplete(e)
  if e.state ~= "active" then return end
  local done, total = Q.Required(e)
  if total > 0 and done == total then self:Complete(e.id) end
end

function Q:SetObjective(id, i, done)
  local e = self:Log()[id]
  if not self:CanTick(e) then return end
  local o = e.objectives[i]
  done = done and true or false
  if not o or o.done == done then return end
  o.done = done
  Sound(done and "IG_MAINMENU_OPTION_CHECKBOX_ON" or "IG_MAINMENU_OPTION_CHECKBOX_OFF")
  K:Fire("QUEST_OBJECTIVE", id, i, done)
  if self:IsMine(e) then self:Push(e) end
  self:CheckComplete(e)
  K:Fire("QUESTS")
end

function Q:Complete(id)
  local e = self:Log()[id]
  if not e or e.state ~= "active" then return end
  e.state, e.completed = "complete", time()
  K:AddEntry("milestone", ("Completed the quest %s"):format(UI.Clean(e.title)),
    e.reward ~= "" and ("Reward: " .. UI.Clean(e.reward)) or nil)
  UI.Toast({
    icon = e.icon, round = true, title = "Quest complete", text = UI.Clean(e.title),
    color = Q.DONE, sound = "IG_QUEST_LIST_COMPLETE", duration = 7,
    onClick = function() Q:Open(id) end,
  })
  if self:IsMine(e) then self:Push(e)
  elseif e.author then K.Net:Send("qack", { id = id, s = "complete" }, "WHISPER", e.author) end
  K:Fire("QUEST_COMPLETE", id)
  K:Fire("QUESTS")
  -- Let the tracker show it finished for a few seconds, then let it go.
  C_Timer.After(8, function()
    if e.state == "complete" and e.tracked then e.tracked = false; K:Fire("QUESTS") end
  end)
end

-- The quest ends in failure (an objective set to fail it did).
function Q:Fail(id)
  local e = self:Log()[id]
  if not e or e.state ~= "active" then return end
  e.state, e.completed = "failed", time()
  K:AddEntry("milestone", ("Failed the quest %s"):format(UI.Clean(e.title)), e.giver ~= "" and ("Given by " .. UI.Clean(e.giver)) or nil)
  UI.Toast({
    icon = e.icon, round = true, title = "Quest failed", text = UI.Clean(e.title),
    color = Q.STATES.failed.color, sound = "IG_QUEST_FAILED", duration = 7,
    onClick = function() Q:Open(id) end,
  })
  if self:IsMine(e) then self:Push(e)
  elseif e.author then K.Net:Send("qack", { id = id, s = "failed" }, "WHISPER", e.author) end
  K:Fire("QUEST_FAILED", id)
  K:Fire("QUESTS")
  C_Timer.After(8, function()
    if e.state == "failed" and e.tracked then e.tracked = false; K:Fire("QUESTS") end
  end)
end

function Q:Abandon(id)
  local e = self:Log()[id]
  if not e or e.state ~= "active" then return end
  e.state, e.completed, e.tracked = "abandoned", time(), false
  if not self:IsMine(e) and e.author then K.Net:Send("qack", { id = id, s = "abandoned" }, "WHISPER", e.author) end
  K:Fire("QUESTS")
end

-- Take a finished or set-aside quest up again.
function Q:Resume(id)
  local e = self:Log()[id]
  if not e or e.state == "active" then return end
  e.state, e.completed, e.tracked = "active", nil, true
  if not self:IsMine(e) and e.author then K.Net:Send("qack", { id = id, s = "active" }, "WHISPER", e.author) end
  K:Fire("QUESTS")
end

function Q:Forget(id)
  self:Log()[id] = nil
  K:Fire("QUESTS")
end

function Q:Track(id, on)
  local e = self:Log()[id]
  if not e then return end
  e.tracked = on and true or false
  K:Fire("QUESTS")
end

-- Open the Quests page. tab: 1 Journal, 2 Write, 3 Campaigns.
function Q:Open(id, tab)
  self.focus = { id = id, tab = tab or 1 }
  K.Journal:Open("quests")
end

---------------------------------------------------------------------------
-- Receiving
---------------------------------------------------------------------------
function Q:OnOffer(msg, sender)
  if not K.db.settings.questOffers then return end
  local q = Q.Unpack(msg)
  if not q or not q.id then return end
  q.author = sender
  if K.QuestRewards then K.QuestRewards.Learn(msg.ri, sender) end
  local e = self:Log()[q.id]
  if e then
    if K.NameKey(e.author) ~= K.NameKey(sender) then return end
    if e.state == "active" then
      -- The storyteller reworded it: take the new words, keep what's done.
      local old = e.objectives
      for _, k in ipairs({ "title", "giver", "campaign", "description", "reward", "icon", "st", "seq", "au",
                           "level", "levelMax", "marker", "items", "pick" }) do e[k] = q[k] end
      e.objectives = q.objectives
      for i, o in ipairs(e.objectives) do
        local was = old[i]
        o.done = was and was.done or false
        if was and was.text == o.text then
          for _, k in ipairs({ "failed", "failWhy", "rolls", "guesses", "cnt", "watch", "beenThere", "openAt", "seen",
                               "hadEffect", "noticed", "autoAt" }) do o[k] = was[k] end
        end
      end
      K:Fire("QUESTS")
      UI.Toast({ icon = e.icon, round = true, title = "Quest updated", text = UI.Clean(e.title), duration = 5,
                 onClick = function() Q:Open(e.id) end })
      return
    end
  end
  for _, o in ipairs(self.pending) do if o.q.id == q.id then return end end
  if #self.pending >= PENDING_MAX then return end
  self.pending[#self.pending + 1] = { q = q, from = sender }
  self:ShowOffer()
end

local function OnAck(msg, sender)
  if type(msg.id) ~= "string" or #msg.id > 96 then return end
  local s = msg.s
  if s ~= "active" and s ~= "declined" and s ~= "complete" and s ~= "abandoned" and s ~= "failed" then return end
  local e = Q:Log()[msg.id]
  if not e or not Q:IsMine(e) then return end
  local key = K.NameKey(sender)
  if not key then return end
  e.players = e.players or {}
  if not e.players[key] and Count(e.players) >= PLAYERS_MAX then return end
  e.players[key] = { name = sender, s = s, t = time() }
  local verb = ({ active = "accepted", declined = "declined", complete = "completed", abandoned = "set aside", failed = "failed" })[s]
  if s == "active" or s == "complete" then
    UI.Toast({ icon = e.icon, round = true, title = ("%s %s your quest"):format(Short(sender), verb), text = UI.Clean(e.title),
               duration = 5, color = s == "complete" and Q.DONE or nil, onClick = function() Q:Open(e.id) end })
  else
    K:Print(("%s %s %s."):format(Short(sender), verb, UI.Clean(e.title)))
  end
  K:Fire("QUESTS")
end

local function OnProgress(msg, sender)
  if type(msg.id) ~= "string" or #msg.id > 96 then return end
  local e = Q:Log()[msg.id]
  -- Only the quest's author can move it along.
  if not e or not e.author or K.NameKey(e.author) ~= K.NameKey(sender) or Q:IsMine(e) then return end
  if e.state ~= "active" then return end
  if type(msg.o) == "string" and #msg.o <= M.objectives then
    for i, o in ipairs(e.objectives) do
      local bit = msg.o:sub(i, i)
      if bit == "2" then
        if K.QuestAuto and not o.done and not o.failed then K.QuestAuto:Mark(e, i) end
      elseif bit == "1" or bit == "0" then
        local done = bit == "1"
        local justAuto = not done and o.autoAt and time() - o.autoAt < 120
        if o.done ~= done and not justAuto then
          o.done = done
          K:Fire("QUEST_OBJECTIVE", e.id, i, done)
          if done and not e.tracked then
            UI.Toast({ icon = e.icon, round = true, title = UI.Clean(o.text), text = "Objective complete  ·  " .. UI.Clean(e.title),
                       duration = 4, color = Q.DONE, onClick = function() Q:Open(e.id) end })
          end
        end
      end
    end
  end
  if e.state ~= "active" then K:Fire("QUESTS") return end
  if msg.s == "complete" then Q:Complete(e.id)
  elseif msg.s == "failed" then Q:Fail(e.id)
  else Q:CheckComplete(e) end
  K:Fire("QUESTS")
end

K:On("LOGIN", function()
  K.Net:On("qoffer", function(msg, sender) Q:OnOffer(msg, sender) end)
  K.Net:On("qack", OnAck)
  K.Net:On("qprog", OnProgress)
end)

---------------------------------------------------------------------------
-- Icon choice: the shared picker when there is one, else a small popover
-- with suggestions and a name field. Other Kinship features use it too.
---------------------------------------------------------------------------
local pop
local function BuildPopover()
  pop = CreateFrame("Frame", "KinshipRPIconPopover", UIParent)
  pop:SetSize(296, 150)
  pop:SetFrameStrata("FULLSCREEN_DIALOG")
  pop:SetClampedToScreen(true)
  pop:EnableMouse(true)
  pop.bg = pop:CreateTexture(nil, "BACKGROUND")
  pop.bg:SetAllPoints()
  pop.edge = UI.Border(pop)
  UI:OnTheme(function(t)
    pop.bg:SetColorTexture(unpack(t.chrome))
    pop.edge:SetColor(t.ui[1], t.ui[2], t.ui[3], 0.45)
  end)
  local title = UI.Text(pop, "Choose an icon", "Header", "deskHeading")
  title:SetPoint("TOPLEFT", 12, -10)
  pop.close = UI.CloseButton(pop, false, 20)
  pop.close:SetPoint("TOPRIGHT", -4, -4)
  pop.slots = {}
  for i = 1, 16 do
    local b = CreateFrame("Button", nil, pop)
    b:SetSize(28, 28)
    b:SetPoint("TOPLEFT", 12 + ((i - 1) % 8) * 34, -34 - math.floor((i - 1) / 8) * 34)
    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetAllPoints()
    b.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    b.edge = UI.Border(b)
    local function paint(p)
      local u = K:Theme().ui
      b.edge:SetColor(u[1], u[2], u[3], 0.2 + 0.8 * p)
    end
    paint(0)
    b:SetScript("OnEnter", function(self) UI.Tween(self, 1, 0.1, paint) end)
    b:SetScript("OnLeave", function(self) UI.Tween(self, 0, 0.12, paint) end)
    b:SetScript("OnClick", function(self)
      if pop.onPick and self.value then K.Try("icon picker", pop.onPick, self.value) end
      pop:Hide()
    end)
    pop.slots[i] = b
  end
  pop.edit = UI.Edit(pop, 200, 24, "desk", 100)
  pop.edit:SetPoint("BOTTOMLEFT", 12, 12)
  pop.hint = UI.Text(pop.edit, "or type an icon name", "Small", "deskSubtle")
  pop.hint:SetPoint("LEFT", 8, 0)
  pop.use = UI.Button(pop, "Use", 64, 24)
  pop.use:SetPoint("BOTTOMRIGHT", -12, 12)
  local function Use()
    local v = Q.ValidIcon(strtrim(pop.edit:GetText() or ""))
    if not v then
      pop.edit.edge:SetColor(0.90, 0.36, 0.30, 1)
      return
    end
    if pop.onPick then K.Try("icon picker", pop.onPick, v) end
    pop:Hide()
  end
  pop.use:SetScript("OnClick", Use)
  pop.edit:SetScript("OnEnterPressed", Use)
  pop.edit:SetScript("OnTextChanged", function(self) pop.hint:SetShown((self:GetText() or "") == "") end)
  tinsert(UISpecialFrames, "KinshipRPIconPopover")
  pop:Hide()
end

-- onPick(icon) receives a checked icon (file ID or texture path).
function Q.PickIcon(anchor, current, onPick, suggestions)
  local picker = K.IconPicker
  if type(picker) == "table" and type(picker.Open) == "function" then
    local ok = K.Try("icon picker", picker.Open, picker, anchor, current, function(icon)
      local v = Q.ValidIcon(icon)
      if v then onPick(v) end
    end)
    if ok then return end
  end
  if not pop then BuildPopover() end
  pop.onPick = onPick
  local list = suggestions or Q.ICONS
  for i, b in ipairs(pop.slots) do
    local name = list[i]
    b.value = name and ("Interface\\Icons\\" .. name) or nil
    b.icon:SetTexture(b.value)
    b:SetShown(name ~= nil)
  end
  pop.edit:SetText("")
  pop.edit:ClearFocus()
  pop:ClearAllPoints()
  pop:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -6)
  pop:Show()
  UI.FadeIn(pop, 0.12)
end

---------------------------------------------------------------------------
-- The quest sheet: a reading view on a warm card. Used by the
-- offer popup, the Journal and the editor's live preview.
--   sheet:SetQuest(q, { interactive, onToggle(i), animate = index })
---------------------------------------------------------------------------
local PAD = 18
local CHECK = "Interface\\RAIDFRAME\\ReadyCheck-Ready"

local function ObjectiveRow(s)
  local r = CreateFrame("Button", nil, s.body)
  r.hl = r:CreateTexture(nil, "BACKGROUND")
  r.hl:SetAllPoints()
  r.hl:SetTexture(WHITE)
  r.hl:SetAlpha(0)
  r.flash = r:CreateTexture(nil, "BACKGROUND", nil, 1)
  r.flash:SetPoint("TOPLEFT")
  r.flash:SetPoint("BOTTOMLEFT")
  r.flash:SetTexture(WHITE)
  r.flash:SetWidth(1)
  r.flash:SetAlpha(0)
  r.ring = UI.Circle(r, 16, "ARTWORK", 0)
  r.ring:SetPoint("TOPLEFT", 4, -4)
  r.hole = UI.Circle(r, 12, "ARTWORK", 1)
  r.hole:SetPoint("CENTER", r.ring)
  r.check = r:CreateTexture(nil, "OVERLAY")
  r.check:SetSize(16, 16)
  r.check:SetPoint("CENTER", r.ring, "CENTER", 1, 0)
  r.check:SetTexture(CHECK)
  r.text = UI.Text(r, "", "Body", "plain", s.bw - 34)
  r.text:SetPoint("TOPLEFT", 28, -5)
  r.text:SetSpacing(2)
  r:SetScript("OnEnter", function(self) if self.interactive then self.hl:SetAlpha(1) end end)
  r:SetScript("OnLeave", function(self) self.hl:SetAlpha(0) end)
  r:SetScript("OnClick", function(self) if self.interactive and s.onToggle then s.onToggle(self.index) end end)
  UI:OnTheme(function(t) r.hl:SetVertexColor(unpack(t.hover)) end)
  return r
end

local function PaintRow(r, done)
  local t = K:Theme()
  local c = done and UI.OnCard(Q.DONE) or t.subtle
  r.ring:SetVertexColor(c[1], c[2], c[3], done and 1 or 0.55)
  r.hole:SetVertexColor(unpack(t.panel))
  r.check:SetShown(done)
  r.text:SetTextColor(unpack(done and t.subtle or t.text))
end

function Q.Sheet(parent, w, h, opts)
  opts = opts or {}
  local s = UI.Panel(parent)
  s:SetSize(w, h)
  s.wash = s:CreateTexture(nil, "BACKGROUND", nil, 1)
  s.wash:SetPoint("TOPLEFT")
  s.wash:SetPoint("TOPRIGHT")
  s.wash:SetHeight(120)
  s.wash:SetTexture(WHITE)
  s.bar = s:CreateTexture(nil, "ARTWORK")
  s.bar:SetTexture(WHITE)
  s.bar:SetHeight(3)
  s.bar:SetPoint("TOPLEFT")
  s.bar:SetPoint("TOPRIGHT")

  s.ring = UI.Circle(s, 56, "ARTWORK", 0)
  s.ring:SetPoint("TOPLEFT", PAD, -20)
  s.icon = s:CreateTexture(nil, "ARTWORK", nil, 2)
  s.icon:SetSize(50, 50)
  s.icon:SetPoint("CENTER", s.ring)
  s.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
  UI.Round(s.icon)
  local tw = w - PAD * 2 - 56 - 12
  s.kicker = UI.Text(s, "QUEST", "Label", "accent", tw - 96)
  s.kicker:SetPoint("TOPLEFT", s.ring, "TOPRIGHT", 12, -3)
  s.kicker:SetWordWrap(false)
  s.title = UI.Text(s, "", "Huge", "heading", tw)
  s.title:SetPoint("TOPLEFT", s.kicker, "BOTTOMLEFT", 0, -5)
  s.title:SetWordWrap(false)
  s.giver = UI.Text(s, "", "Small", "subtle", tw)
  s.giver:SetPoint("TOPLEFT", s.title, "BOTTOMLEFT", 0, -5)
  s.giver:SetWordWrap(false)
  s.chip = UI.Chip(s)
  s.chip:SetPoint("TOPRIGHT", -PAD + 2, -18)
  s.chip:Set(nil)
  s.div = UI.Divider(s, w - PAD * 2)
  s.div:SetPoint("TOPLEFT", PAD, -92)

  local sf = CreateFrame("ScrollFrame", nil, s)
  sf:SetPoint("TOPLEFT", PAD, -102)
  sf:SetPoint("BOTTOMRIGHT", -PAD - 8, opts.bottom or 14)
  s.bw = w - PAD * 2 - 8
  local body = CreateFrame("Frame", nil, sf)
  body:SetSize(s.bw, 1)
  sf:SetScrollChild(body)
  s.sf, s.body = sf, body
  s.scroll = UI.ScrollBar(sf, false, 40)

  s.desc = UI.Text(body, "", "Read", "text", s.bw - 4)
  s.desc:SetJustifyV("TOP")
  s.desc:SetSpacing(4)
  s.objHead = UI.Section(body, "Objectives")
  s.rewardHead = UI.Section(body, "Reward")
  s.rewardIcon = body:CreateTexture(nil, "ARTWORK")
  s.rewardIcon:SetSize(24, 24)
  s.rewardIcon:SetTexture("Interface\\Icons\\INV_Misc_Bag_10")
  s.rewardIcon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
  UI.Round(s.rewardIcon)
  s.reward = UI.Text(body, "", "Body", "text", s.bw - 40)
  s.reward:SetSpacing(2)
  s.rows = {}

  UI:OnTheme(function(t)
    local a = t.accent
    s.bar:SetVertexColor(a[1], a[2], a[3], 1)
    s.ring:SetVertexColor(t.ui[1] * 0.8, t.ui[2] * 0.7, t.ui[3] * 0.5, 1)
    -- A warm wash of gold across the top of the card
    if s.wash.SetGradient and CreateColor then
      s.wash:SetGradient("VERTICAL", CreateColor(0.80, 0.60, 0.28, 0), CreateColor(0.80, 0.60, 0.28, 0.22))
    else
      s.wash:SetVertexColor(0.80, 0.60, 0.28, 0.10)
    end
    if s.quest then s:SetQuest(s.quest, s.opts) end
  end)

  function s:SetQuest(q, o)
    o = o or {}
    self.quest, self.opts, self.onToggle = q, o, o.onToggle
    if not q then return end
    self.icon:SetTexture(q.icon or Q.DEFAULT_ICON)
    local camp = UI.Clean(q.campaign)
    self.kicker:SetText(camp ~= "" and ("QUEST  ·  " .. camp) or "QUEST")
    local title = UI.Clean(q.title)
    self.title:SetText(title ~= "" and title or "An untitled quest")
    local giver = UI.Clean(q.giver)
    local QM = K.QuestMarkers
    local lvl = QM and QM.LevelText(q)
    local lvlText = lvl and ("  ·  |cff%sLevel %s|r"):format(QM.LevelHex(q, true) or "ffffff", lvl) or ""
    if giver ~= "" then self.giver:SetText("Given by " .. giver .. lvlText)
    elseif q.author and not Q:IsMine(q) then self.giver:SetText("From " .. Short(q.author) .. lvlText)
    else self.giver:SetText("A quest of your own making" .. lvlText) end

    local t = K:Theme()
    local desc = UI.Clean(q.description)
    self.desc:SetText(desc ~= "" and desc or "No story has been written for this quest yet.")
    self.desc:SetTextColor(unpack(desc ~= "" and t.text or t.subtle))
    self.desc:ClearAllPoints()
    self.desc:SetPoint("TOPLEFT", 2, -2)
    local y = -(math.ceil(self.desc:GetStringHeight()) + 2)
    -- Where it happens
    if not self.where then
      self.where = UI.Text(self.body, "", "Small", "subtle", self.bw - 4)
      self.where:SetWordWrap(false)
    end
    local whereText = QM and q.marker and QM.Label(q.marker)
    self.where:SetShown(whereText ~= nil)
    if whereText then
      local d = QM.Distance(q.marker)
      self.where:SetText(("|T%s:14:14|t  %s%s"):format(QM.PIN_ICON, whereText, d and ("  ·  " .. QM.DistText(d)) or ""))
      self.where:ClearAllPoints()
      self.where:SetPoint("TOPLEFT", 2, y - 8)
      y = y - 8 - 16
    end

    local objs = q.objectives or {}
    local anyShown = false
    for i in ipairs(objs) do
      if not K.QuestAuto or K.QuestAuto.Visible(q, i) or not q.author then anyShown = true break end
    end
    self.objHead:SetShown(anyShown)
    self.objHead.bg:SetShown(anyShown)
    if anyShown then
      y = y - 22
      self.objHead:ClearAllPoints()
      self.objHead:SetPoint("TOPLEFT", 7, y)
      y = y - 14
    end
    local QA = K.QuestAuto
    local n = 0
    for i, ob in ipairs(objs) do
      if not QA or QA.Visible(q, i) or not q.author then
        n = n + 1
        local r = self.rows[n] or ObjectiveRow(self)
        self.rows[n] = r
        r.index, r.interactive = i, o.interactive and true or false
        r:EnableMouse(r.interactive)
        r:SetWidth(self.bw)
        local where = QM and ob.marker and QM.Label(ob.marker)
        local extra = ""
        local sub = UI.Hex(t.subtle)
        local state = QA and q.state == "active" and QA.State(q, i) or nil
        if QA and ob.auto then
          local kind = QA.KINDS[ob.auto.k]
          extra = extra .. ("\n|cff%s|T%s:12:12:0:0:64:64:5:59:5:59|t %s|r"):format(sub, kind and kind.icon or QM.PIN_ICON,
            QA.Describe(ob.auto, ob) or "")
        elseif where then
          extra = ("\n|cff%s|T%s:12:12|t %s|r"):format(sub, QM.PIN_ICON, where)
        end
        local opts = QA and QA.DescribeOptions(ob, q, i)
        if opts then extra = extra .. ("\n|cff%s%s|r"):format(sub, opts) end
        local progress = QA and not ob.done and q.id and QA.ProgressText(q, i)
        if progress then extra = extra .. ("\n|cff%s%s|r"):format(UI.CardHex(K:Theme().accent), progress) end
        if state == "locked" then extra = extra .. ("\n|cff%sLocked until the one before is done|r"):format(sub)
        elseif state == "failed" then extra = extra .. ("\n|cff%s%s|r"):format(UI.CardHex({ 0.90, 0.36, 0.30 }), QA.FailText(ob)) end
        local counter = QA and q.id and QA.CounterPrefix(q, i) or ""
        r.text:SetText(counter .. UI.Clean(ob.text) .. extra)
        r:SetAlpha(state == "locked" and 0.55 or 1)
        -- Something to do for it now: roll, answer, try again
        local actLabel, actFn
        if QA and q.id and not o.preview then actLabel, actFn = QA.Action(q, i) end
        if actLabel and not r.act then
          r.act = UI.Button(r, "", 78, 20)
          r.act:SetPoint("TOPRIGHT", -4, -4)
        end
        if r.act then
          r.act:SetShown(actLabel ~= nil)
          if actLabel then
            r.act:SetText(actLabel)
            r.act:SetScript("OnClick", actFn)
          end
        end
        r.text:SetWidth(self.bw - 34 - (actLabel and 84 or 0))
        local rh = math.max(24, math.ceil(r.text:GetStringHeight()) + 10)
        r:SetHeight(rh)
        r:ClearAllPoints()
        r:SetPoint("TOPLEFT", 0, y)
        PaintRow(r, ob.done)
        r:Show()
        y = y - rh
        if o.animate == i and ob.done then
          UI.SetProgress(r, 0)
          local u = K:Theme().accent
          r.flash:SetVertexColor(u[1], u[2], u[3], 1)
          UI.Tween(r, 1, 0.7, function(p)
            r.flash:SetWidth(math.max(1, self.bw * math.min(1, p * 1.5)))
            r.flash:SetAlpha(0.22 * (1 - p))
            local sz = 16 + 14 * (1 - p)
            r.check:SetSize(sz, sz)
            r.check:SetAlpha(p)
          end, UI.Ease.outQuart)
        else
          r.flash:SetAlpha(0)
          r.check:SetSize(16, 16)
          r.check:SetAlpha(1)
        end
      end
    end
    for i = n + 1, #self.rows do self.rows[i]:Hide() end

    local reward = UI.Clean(q.reward)
    local QR = K.QuestRewards
    local hasText = reward ~= ""
    local hasItems = QR ~= nil and q.items ~= nil
    local hasReward = hasText or hasItems
    self.rewardHead:SetShown(hasReward)
    self.rewardHead.bg:SetShown(hasReward)
    self.rewardIcon:SetShown(hasText)
    self.reward:SetShown(hasText)
    if hasReward then
      y = y - 20
      self.rewardHead:ClearAllPoints()
      self.rewardHead:SetPoint("TOPLEFT", 7, y)
      y = y - 18
    end
    if hasText then
      self.rewardIcon:ClearAllPoints()
      self.rewardIcon:SetPoint("TOPLEFT", 2, y)
      self.reward:SetText(reward)
      self.reward:ClearAllPoints()
      self.reward:SetPoint("TOPLEFT", self.rewardIcon, "TOPRIGHT", 10, -5)
      y = y - math.max(26, math.ceil(self.reward:GetStringHeight()) + 10)
    end
    if QR then y = y - QR:PaintSheet(self, hasItems and q or nil, y) end
    self.body:SetHeight(math.max(1, -y + 8))
    if self.shownId ~= q.id or not q.id then
      self.shownId = q.id
      if o.keepScroll ~= true then self.sf:SetVerticalScroll(0) end
    end
    self.scroll.Update()
  end
  return s
end

---------------------------------------------------------------------------
-- The offer popup
---------------------------------------------------------------------------
local OW, OH = 420, 520

function Q:BuildOffer()
  local f = CreateFrame("Frame", "KinshipRPQuestOffer", UIParent)
  f:SetSize(OW, OH)
  f:SetPoint("CENTER", 0, 40)
  f:SetFrameStrata("DIALOG")
  f:SetToplevel(true)
  f:SetClampedToScreen(true)
  f:EnableMouse(true)
  f:SetMovable(true)
  f:RegisterForDrag("LeftButton")
  f:SetScript("OnDragStart", f.StartMoving)
  f:SetScript("OnDragStop", f.StopMovingOrSizing)
  f.shadow = f:CreateTexture(nil, "BACKGROUND", nil, -8)
  f.shadow:SetPoint("TOPLEFT", 5, -5)
  f.shadow:SetPoint("BOTTOMRIGHT", 5, -5)
  f.shadow:SetColorTexture(0, 0, 0, 0.35)
  f.bg = f:CreateTexture(nil, "BACKGROUND", nil, -7)
  f.bg:SetAllPoints()
  f.edge = UI.Border(f)
  UI:OnTheme(function(t)
    f.bg:SetColorTexture(unpack(t.chrome))
    f.edge:SetColor(t.ui[1], t.ui[2], t.ui[3], 0.45)
  end)

  f.seal = f:CreateTexture(nil, "ARTWORK")
  f.seal:SetSize(18, 18)
  f.seal:SetPoint("TOPLEFT", 14, -10)
  f.seal:SetTexture(K.ICON)
  f.from = UI.Text(f, "", "Small", "deskText", OW - 80)
  f.from:SetPoint("LEFT", f.seal, "RIGHT", 8, 0)
  f.from:SetWordWrap(false)
  f.close = UI.CloseButton(f, false, 22)
  f.close:SetPoint("TOPRIGHT", -6, -6)
  f.close:SetScript("OnClick", function() Q:Answer(false) end)

  f.sheet = Q.Sheet(f, OW - 24, OH - 36 - 56)
  f.sheet:SetPoint("TOPLEFT", 12, -36)

  f.accept = UI.Button(f, "Accept", 150, 28)
  f.accept:SetPoint("BOTTOMRIGHT", -12, 14)
  f.accept:SetScript("OnClick", function() Q:Answer(true) end)
  f.decline = UI.Button(f, "Decline", 110, 28)
  f.decline:SetPoint("RIGHT", f.accept, "LEFT", -8, 0)
  f.decline:SetScript("OnClick", function() Q:Answer(false) end)
  f.more = UI.Text(f, "", "Small", "deskSubtle", 140)
  f.more:SetPoint("BOTTOMLEFT", 16, 22)

  -- Esc: the same as Decline (the offer isn't left hanging)
  tinsert(UISpecialFrames, "KinshipRPQuestOffer")
  f:SetScript("OnHide", function() if Q.showing then Q:Answer(false, true) end end)
  f:Hide()
  self.offerFrame = f
end

function Q:ShowOffer()
  local offer = self.pending[1]
  if not offer then return end
  if InCombatLockdown() then
    if not self.waitCombat then
      self.waitCombat = true
      local w = CreateFrame("Frame")
      w:RegisterEvent("PLAYER_REGEN_ENABLED")
      w:SetScript("OnEvent", function(frame)
        frame:UnregisterAllEvents()
        Q.waitCombat = nil
        Q:ShowOffer()
      end)
    end
    return
  end
  if not self.offerFrame then self:BuildOffer() end
  local f = self.offerFrame
  self.showing = offer
  f.from:SetText(("|cffffffff%s|r offers you a quest"):format(Short(offer.from)))
  f.sheet:SetQuest(offer.q)
  f.more:SetText(#self.pending > 1 and ("%d more waiting"):format(#self.pending - 1) or "")
  local wasShown = f:IsShown()
  f:Show()
  Sound("IG_QUEST_LIST_OPEN")
  -- Rise into place
  UI.SetProgress(f, 0)
  UI.Tween(f, 1, wasShown and 0.25 or 0.35, function(p)
    f:SetAlpha(p)
    f:ClearAllPoints()
    f:SetPoint("CENTER", 0, 40 - 18 * (1 - p))
  end, UI.Ease.outQuart)
end

-- quiet = closed with Esc / hidden: decline without sounds.
function Q:Answer(accept, quiet)
  local offer = self.showing
  if not offer then return end
  self.showing = nil
  table.remove(self.pending, 1)
  if accept then self:Accept(offer) else self:Decline(offer) end
  if not quiet and not accept then Sound("IG_QUEST_LOG_CLOSE") end
  if self.pending[1] then
    -- (from OnHide, wait a beat before showing the frame again)
    if quiet then C_Timer.After(0.1, function() Q:ShowOffer() end) else self:ShowOffer() end
  elseif self.offerFrame and self.offerFrame:IsShown() then
    self.offerFrame:Hide()
  end
end

---------------------------------------------------------------------------
-- Settings
---------------------------------------------------------------------------
K:RegisterSettings({ id = "quests", title = "Quests", order = 35,
  shown = function() return K:ExtOn("campaigns") end, build = function(card)
  card:Toggle("In the objective tracker", "Tracked roleplay quests appear in your objective tracker under Roleplay Quests, with their icons.", {
    get = function() return K.db.settings.questTracker ~= false end,
    set = function(v) K.db.settings.questTracker = v; K:Fire("QUESTS") end,
  })
  card:Toggle("Distances in the tracker", "How far each map pin is, beside the quest and its objectives. "
    .. "Off keeps the tracker as tidy as the game's own; hover a quest there to see them.", {
    get = function() return K.db.settings.questTrackerDistance == true end,
    set = function(v) K.db.settings.questTrackerDistance = v or nil; K:Fire("QUESTS") end,
  })
  card:Toggle("Roleplay tab in the quest log", "A tab beside the quest log's own, listing your roleplay quests.", {
    get = function() return K.db.settings.questLogTab ~= false end,
    set = function(v) K.db.settings.questLogTab = v; if K.QuestTracker then K.QuestTracker:ApplyLogSetting() end end,
  })
  card:Toggle("Quest offers", "Let other Kinship players offer you quests. You still choose whether to accept.", "questOffers")
end })
