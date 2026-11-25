-- Kinship RP: playing Total RP 3: Extended campaigns. One campaign plays at a
-- time, as in Extended: its quests start, move from step to step and reveal
-- objectives through the campaign's own workflows (ext/Script.lua), which
-- answer game events and the Look / Listen / Talk / Interact actions.
-- Each quest you're on is copied into your Kinship quest journal (marked
-- e.ext), so the journal, tracker and campaigns tab show it like any other;
-- only the campaign moves it on, and nothing about it is sent to anyone.
--   K.db.extPlay[charGUID] = { current = campaignID,
--     logs = { [campaignID] = { QUEST = { [questID] = { OB, CS, PS, FI } }, vars } } }
-- (the same shape as Extended's quest log, so its workflows read it as they expect).

local _, ns = ...
local Loc = ns.L
local K = ns.K
local UI = K.UI
local E = K.Ext
local S = K.ExtScript
local P = {}
K.ExtCampaign = P

local EMPTY = {}
local ACTIONS = {
  { key = "LOOK", label = "Look", icon = "Interface\\Icons\\Ability_EyeOfTheOwl", none = "There's nothing to look at here." },
  { key = "LISTEN", label = "Listen", icon = "Interface\\Icons\\INV_Misc_Ear_Human_01", none = "You hear nothing worth noting." },
  { key = "TALK", label = "Talk", icon = "Interface\\Icons\\Warrior_DisruptingShout", none = "There's nobody to talk to here." },
  { key = "ACTION", label = "Interact", icon = "Interface\\Icons\\Ability_Warrior_Disarm", none = "There's nothing to do here." },
}
P.ACTIONS = ACTIONS

local function On() return K:ExtOn("campaigns") end

---------------------------------------------------------------------------
-- State
---------------------------------------------------------------------------
function P:State()
  K.db.extPlay = type(K.db.extPlay) == "table" and K.db.extPlay or {}
  local key = K:CharKey()
  local st = K.db.extPlay[key]
  if type(st) ~= "table" then st = {}; K.db.extPlay[key] = st end
  st.logs = type(st.logs) == "table" and st.logs or {}
  return st
end

function P:Current()
  local c = K.db and self:State().current
  if c and not E:Get(c) then return nil end
  return c
end

function P:Log(c) return c and self:State().logs[c] or nil end
function P:ActiveLog() return self:Log(self:Current()) end

local function Class(...) return E:Get(E.FullID(...)) end
local function BA(obj) return type(obj) == "table" and type(obj.BA) == "table" and obj.BA or EMPTY end
local function Name(obj) return K.Plain(S.Text(E.Str(BA(obj).NA) or "")) end

-- Keys of a table in a steady order (Extended's own order is whatever pairs gives).
local function Keys(t)
  local out = {}
  for k in pairs(type(t) == "table" and t or EMPTY) do out[#out + 1] = k end
  table.sort(out, function(a, b) return tostring(a) < tostring(b) end)
  return out
end

local function Say(text) DEFAULT_CHAT_FRAME:AddMessage(text, 1, 0.82, 0) end
local function Alert(text) if UIErrorsFrame then UIErrorsFrame:AddMessage(K.UI.Clean(text), 1, 0.82, 0) end end
local function Green(text) return "|cff66d97a" .. K.UI.Escape(text) .. "|r" end

local function Run(scriptID, obj, fullID, extra)
  if scriptID == nil or type(obj) ~= "table" then return end
  local args = extra or {}
  args.object = args.object or P:Log(E.RootID(fullID))
  S:Run(scriptID, obj.SC, args, fullID)
end

---------------------------------------------------------------------------
-- The campaign's NPCs: names, titles and descriptions given to game NPCs
-- while it plays (Extended's ND).
---------------------------------------------------------------------------
function P:NPC(unit)
  local c = self:Current()
  local nd = c and E.Path(E:Get(c), "ND")
  if type(nd) ~= "table" then return nil end
  local id = S.NPCID(unit)
  local npc = id and (nd[id] or nd[tonumber(id)])
  if type(npc) ~= "table" then return nil end
  local args = { object = self:Log(c) }
  local name = E.Str(npc.NA)
  return {
    name = name and name ~= "" and K.Plain(S.Text(S.Parse(name, args))) or nil,
    title = E.Str(npc.FT) and K.Plain(S.Text(S.Parse(npc.FT, args))) or nil,
    desc = E.Str(npc.DE) and S.Text(S.Parse(npc.DE, args)) or nil,
  }
end

---------------------------------------------------------------------------
-- Your journal: one Kinship quest entry per Extended quest you've begun.
---------------------------------------------------------------------------
function P.EntryID(c, q) return "ext:" .. E.FullID(c, q) end

local function Objectives(qc, ql, args)
  local out = {}
  for _, id in ipairs(Keys(ql.OB)) do
    local o = type(qc.OB) == "table" and qc.OB[id]
    if type(o) == "table" then
      local text = K.Plain(S.Text(S.Parse(E.Str(o.TX) or "", args)))
      out[#out + 1] = { text = text ~= "" and text or id, done = ql.OB[id] == true }
    end
  end
  return out
end

-- What the quest says now: the current step, the quest's own story, then
-- what came before.
local function Description(c, q, qc, ql, args)
  local parts = {}
  local step = ql.CS and Class(c, q, ql.CS)
  local now = step and E.Str(BA(step).TX)
  if now and now ~= "" then parts[#parts + 1] = S.Text(S.Parse(now, args)) end
  local de = E.Str(BA(qc).DE)
  if de and de ~= "" then parts[#parts + 1] = S.Text(S.Parse(de, args)) end
  local before = {}
  for i = #(ql.PS or EMPTY), 1, -1 do
    local ps = Class(c, q, ql.PS[i])
    local dx = ps and E.Str(BA(ps).DX)
    if dx and dx ~= "" then before[#before + 1] = S.Text(S.Parse(dx, args)) end
  end
  if #before > 0 then parts[#parts + 1] = table.concat(before, "\n\n") end
  return table.concat(parts, "\n\n")
end

function P:Mirror(c, q, create)
  local Q = K.Quests
  if not Q then return end
  local cl = self:Log(c)
  local ql = cl and cl.QUEST and cl.QUEST[q]
  local qc, cc = Class(c, q), E:Get(c)
  if type(ql) ~= "table" or not qc or not cc then return end
  local log, id = Q:Log(), P.EntryID(c, q)
  local e = log[id]
  if not e then
    if not create then return end
    e = { id = id, ext = { c = c, q = q }, st = true, giver = "", reward = "", accepted = time(), objectives = {} }
    log[id] = e
  end
  if create then e.state, e.completed, e.tracked, e.accepted = "active", nil, self:Current() == c, time() end
  local args = { object = cl }
  e.ext = { c = c, q = q }
  e.title = K.Plain(S.Text(S.Parse(E.Str(BA(qc).NA) or q, args)))
  e.icon = Q.ValidIcon(E.Str(BA(qc).IC)) or Q.ValidIcon(E.Str(BA(cc).IC)) or Q.DEFAULT_ICON
  e.campaign = Name(cc)
  e.from = E.Str(E.Path(cc, "MD", "CB"))
  e.description = Description(c, q, qc, ql, args)
  e.objectives = Objectives(qc, ql, args)
  if ql.FI and e.state == "active" then Q:Complete(id) end
  return e
end

function P:SyncAll(c)
  local cl = self:Log(c)
  if not cl then return end
  for q in pairs(cl.QUEST or EMPTY) do self:Mirror(c, q) end
  K:Fire("QUESTS")
end

-- Your journal follows the campaign that's playing: its unfinished quests
-- are tracked, a paused campaign's aren't.
local function TrackCampaign(c, on)
  local Q = K.Quests
  if not (Q and c) then return end
  for _, e in pairs(Q:Log()) do
    if type(e.ext) == "table" and e.ext.c == c and e.state == "active" then e.tracked = on and true or false end
  end
  K:Fire("QUESTS")
end

---------------------------------------------------------------------------
-- Playing, pausing, starting over
---------------------------------------------------------------------------
function P:Pause(quiet)
  local st = self:State()
  local c = st.current
  if not c then return end
  st.current = nil
  if not quiet then Say("Pausing the campaign " .. Green(Name(E:Get(c)) ~= "" and Name(E:Get(c)) or c) .. ".") end
  self:Rebuild()
  TrackCampaign(c, false)
  if K.ExtCutscene then K.ExtCutscene:Stop() end
  K:Fire("EXT_CAMPAIGN")
end

-- A campaign someone else made asks once, the first time it plays, before
-- it may speak, emote or play sounds for the people around you. The answer
-- is kept per campaign (K.Ext:Allowed reads it).
local asking
StaticPopupDialogs["KINSHIPRP_EXT_ALLOW"] = {
  text = "%s", button1 = "Allow", button2 = "Don't allow",
  OnAccept = function() if asking then asking(true) end end,
  OnCancel = function() if asking then asking(false) end end,
  timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
}

local function Permitted(c, cc)
  local db = E:DB()
  if not db or db.my[c] then return true end
  local sec = db.security
  if type(sec.specific[c]) == "table" then return true end
  local _, details = E.ComputeSecurity(c, cc)
  local labels = K.ExtDB and K.ExtDB.GROUP_LABEL or EMPTY
  local groups, words = {}, {}
  for group in pairs(details) do
    if labels[group] and group ~= "SEC_REASON_SCRIPT" and group ~= "SEC_REASON_MACRO" then
      groups[#groups + 1] = group
      words[#words + 1] = labels[group]
    end
  end
  if #groups == 0 then return true end
  table.sort(words)
  asking = function(yes)
    asking = nil
    sec.specific[c] = {}
    if yes then for _, g in ipairs(groups) do sec.specific[c][g] = true end end
    C_Timer.After(0, function() P:Play(c) end)
  end
  StaticPopup_Show("KINSHIPRP_EXT_ALLOW", ("%s wants to %s. Allow it?\n\nIf you don't, it shows those to you alone."):format(
    K.UI.Escape(Name(cc) ~= "" and Name(cc) or c), table.concat(words, ", ")))
  return false
end

function P:Play(c)
  if not On() then K:Print("Campaigns are switched off (Settings > Extended features).") return end
  local cc = E:Get(c)
  if not cc or cc.TY ~= "CA" then K:Print("That campaign isn't in your Database any more.") return end
  local st = self:State()
  if st.current == c then return end
  if not Permitted(c, cc) then return end
  if st.current then self:Pause(true) end
  local name = Name(cc) ~= "" and Name(cc) or c
  local fresh = type(st.logs[c]) ~= "table"
  if fresh then st.logs[c] = { QUEST = {}, vars = {} } end
  local cl = st.logs[c]
  cl.QUEST = type(cl.QUEST) == "table" and cl.QUEST or {}
  st.current = c
  Say((fresh and "Starting the campaign " or "Resuming the campaign ") .. Green(name) .. ".")
  self:Rebuild()
  if fresh then
    Run(E.Path(cc, "LI", "OS"), cc, c, { object = cl })
    for _, q in ipairs(Keys(cc.QE)) do
      if self:Current() == c and E.Bool(BA(cc.QE[q]).IN) then self:StartQuest(c, q) end
    end
  end
  TrackCampaign(c, true)
  self:SyncAll(c)
  self:Rebuild()
  K:Fire("EXT_CAMPAIGN")
end

function P:Toggle(c)
  if self:Current() == c then self:Pause() else self:Play(c) end
end

-- Forget your progress in a campaign; if it's playing, it begins again.
function P:Reset(c)
  local st = self:State()
  local playing = st.current == c
  if playing then self:Pause(true) end
  st.logs[c] = nil
  local Q = K.Quests
  if Q then
    local log = Q:Log()
    for id, e in pairs(log) do
      if type(e.ext) == "table" and e.ext.c == c then log[id] = nil end
    end
    K:Fire("QUESTS")
  end
  if playing then self:Play(c) end
  K:Fire("EXT_CAMPAIGN")
end

function P:Started(c) return self:Log(c) ~= nil end

-- Something in a campaign that isn't playing wants to move it on: ask first.
local pending
StaticPopupDialogs["KINSHIPRP_EXT_RESUME"] = {
  text = "%s isn't playing. Play it now?", button1 = YES or Loc["Yes"], button2 = NO or Loc["No"],
  OnAccept = function()
    local p = pending
    pending = nil
    if not p then return end
    P:Play(p.c)
    if P:Current() == p.c then p.fn() end
  end,
  OnCancel = function() pending = nil end,
  timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
}

local function WhenPlaying(c, fn)
  if P:Current() == c and P:Log(c) then fn() return 1 end
  pending = { c = c, fn = fn }
  local cc = E:Get(c)
  StaticPopup_Show("KINSHIPRP_EXT_RESUME", K.UI.Escape(cc and Name(cc) or c))
  return 3
end

---------------------------------------------------------------------------
-- Quests, steps and objectives (the quest_* effects land here)
---------------------------------------------------------------------------
local function Missing(what, ...)
  local first = ...
  S.Note(first, "missing:" .. E.FullID(...), ("it asks for a %s that isn't in it (%s)."):format(what, E.FullID(...)))
  return 2
end

function P:StartQuest(c, q)
  local qc = Class(c, q)
  if not qc then return Missing("quest", c, q) end
  return WhenPlaying(c, function()
    local cl = P:Log(c)
    cl.QUEST[q] = { OB = {} }
    local args = { object = cl }
    Say("Starting the quest " .. Green(K.Plain(S.Text(S.Parse(E.Str(BA(qc).NA) or q, args)))) .. ".")
    P:Mirror(c, q, true)
    Run(E.Path(qc, "LI", "OS"), qc, E.FullID(c, q), { object = cl })
    for _, s in ipairs(Keys(qc.ST)) do
      if E.Bool(BA(qc.ST[s]).IN) then P:GoToStep(c, q, s) break end
    end
    for _, o in ipairs(Keys(qc.OB)) do
      if type(qc.OB[o]) == "table" and E.Bool(qc.OB[o].AA) then P:Reveal(c, q, o) end
    end
    local e = P:Mirror(c, q)
    if e then
      UI.Toast({ icon = e.icon, round = true, title = Loc["New quest"], text = UI.Clean(e.title),
                 sound = "IG_QUEST_LIST_OPEN", duration = 6, onClick = function() K.Quests:Open(e.id) end })
    end
    P:Rebuild()
    K:Fire("QUESTS")
  end)
end

function P:GoToStep(c, q, s)
  local sc = Class(c, q, s)
  if not sc then return Missing("step", c, q, s) end
  local cl = self:Log(c)
  if not (cl and cl.QUEST[q]) then
    S.Note(c, "nostep:" .. q, ("it moves on a quest that hasn't begun (%s)."):format(q))
    return 2
  end
  return WhenPlaying(c, function()
    local ql = P:Log(c).QUEST[q]
    if not ql then return end
    if ql.CS then
      local old = Class(c, q, ql.CS)
      if old then Run(E.Path(old, "LI", "OL"), old, E.FullID(c, q, ql.CS), { object = P:Log(c), classID = s }) end
      ql.PS = type(ql.PS) == "table" and ql.PS or {}
      table.insert(ql.PS, ql.CS)
    end
    ql.CS = s
    P:Rebuild()
    Run(E.Path(sc, "LI", "OS"), sc, E.FullID(c, q, s), { object = P:Log(c), classID = s })
    if E.Bool(BA(sc).FI) then ql.FI = true end
    P:Rebuild()
    P:Mirror(c, q)
    K:Fire("QUESTS")
  end)
end

local function ObjectiveText(c, q, o)
  local qc = Class(c, q)
  local ob = qc and type(qc.OB) == "table" and qc.OB[o]
  return K.Plain(S.Text(S.Parse(ob and E.Str(ob.TX) or o, { object = P:Log(c) })))
end

function P:Reveal(c, q, o)
  local qc = Class(c, q)
  if not qc then return Missing("quest", c, q) end
  if not (type(qc.OB) == "table" and qc.OB[o]) then return Missing("objective", c, q, o) end
  local cl = self:Log(c)
  if not (cl and cl.QUEST[q]) then return 2 end
  return WhenPlaying(c, function()
    local ql = P:Log(c).QUEST[q]
    if not ql then return end
    ql.OB = type(ql.OB) == "table" and ql.OB or {}
    local first = ql.OB[o] == nil
    if first then ql.OB[o] = false end
    Alert((first and "New objective: " or "Objective updated: ") .. ObjectiveText(c, q, o))
    P:Mirror(c, q)
    K:Fire("QUESTS")
  end)
end

function P:MarkDone(c, q, o)
  local qc = Class(c, q)
  if not qc then return Missing("quest", c, q) end
  if not (type(qc.OB) == "table" and qc.OB[o]) then return Missing("objective", c, q, o) end
  local cl = self:Log(c)
  if not (cl and cl.QUEST[q]) then return 2 end
  return WhenPlaying(c, function()
    local ql = P:Log(c).QUEST[q]
    if not ql then return end
    ql.OB = type(ql.OB) == "table" and ql.OB or {}
    Alert("Objective complete: " .. ObjectiveText(c, q, o))
    ql.OB[o] = true
    P:Mirror(c, q)
    K:Fire("QUESTS")
    local fullID = E.FullID(c, q)
    Run(E.Path(qc, "LI", "OOC"), qc, fullID, { object = P:Log(c), classID = fullID })
  end)
end

function P:CurrentStep(c, q)
  local cl = self:Log(c)
  local ql = cl and cl.QUEST and cl.QUEST[q]
  return ql and ql.CS or nil
end

function P:ObjectiveDone(c, q, o)
  local cl = self:Log(c)
  local ql = cl and cl.QUEST and cl.QUEST[q]
  return ql and type(ql.OB) == "table" and ql.OB[o] == true or false
end

-- all: every objective the quest has, else every one revealed so far.
function P:AllDone(c, q, all)
  local cl = self:Log(c)
  local ql = cl and cl.QUEST and cl.QUEST[q]
  if not ql then return false end
  local ob = type(ql.OB) == "table" and ql.OB or EMPTY
  if not all then
    for _, v in pairs(ob) do if not v then return false end end
    return true
  end
  local qc = Class(c, q)
  for id in pairs(qc and type(qc.OB) == "table" and qc.OB or EMPTY) do
    if ob[id] ~= true then return false end
  end
  return true
end

---------------------------------------------------------------------------
-- Handlers: the campaign's, its unfinished quests' and their current steps'
-- answers to game events and Extended's own events.
---------------------------------------------------------------------------
local CUSTOM = { TRP3_KILL = true, TRP3_ROLL = true, TRP3_SIGNAL = true, TRP3_ITEM_USED = true, TRP3_EMOTE = true }
local handlers = {}        -- event -> { { obj, fullID, sc, co }, ... }
local frame = CreateFrame("Frame")
local registered = {}      -- game events this frame listens to
local unknown = {}

local function Add(obj, fullID)
  for _, h in pairs(type(obj) == "table" and type(obj.HA) == "table" and obj.HA or EMPTY) do
    local ev = type(h) == "table" and E.Str(h.EV)
    if ev and ev ~= "" and h.SC ~= nil then
      handlers[ev] = handlers[ev] or {}
      table.insert(handlers[ev], { obj = obj, fullID = fullID, sc = h.SC, co = h.CO })
    end
  end
end

function P:Rebuild()
  wipe(handlers)
  local c = On() and self:Current()
  local cc = c and E:Get(c)
  local cl = c and self:Log(c)
  if cc and cl then
    Add(cc, c)
    for q, ql in pairs(cl.QUEST or EMPTY) do
      local qc = Class(c, q)
      if qc and type(ql) == "table" and not ql.FI then
        Add(qc, E.FullID(c, q))
        local sc = ql.CS and Class(c, q, ql.CS)
        if sc then Add(sc, E.FullID(c, q, ql.CS)) end
      end
    end
  end
  -- Listen for exactly the game events something answers.
  local want = {}
  for ev in pairs(handlers) do
    if ev == "TRP3_KILL" then
      want.PARTY_KILL = true
    elseif not CUSTOM[ev] then
      want[ev] = true
    end
  end
  for ev in pairs(registered) do
    if not want[ev] then pcall(frame.UnregisterEvent, frame, ev); registered[ev] = nil end
  end
  for ev in pairs(want) do
    if not registered[ev] and not unknown[ev] then
      if pcall(frame.RegisterEvent, frame, ev) then
        registered[ev] = true
      elseif ev == "PARTY_KILL" then
        -- Older clients tell of kills only in the combat log.
        if pcall(frame.RegisterEvent, frame, "COMBAT_LOG_EVENT_UNFILTERED") then registered.COMBAT_LOG_EVENT_UNFILTERED = true end
      else
        unknown[ev] = true
        S.Note(c, "event:" .. ev, ("it listens for a game event this client doesn't have (%s)."):format(ev))
      end
    end
  end
  self:ShowBar()
end

local function Dispatch(ev, payload)
  local list = handlers[ev]
  if not list then return end
  local c = P:Current()
  local copy = {}
  for i, h in ipairs(list) do copy[i] = h end
  for _, h in ipairs(copy) do
    if P:Current() ~= c then return end
    local args = { object = P:Log(c), event = payload }
    if S:Check(h.co, args) then S:Run(h.sc, h.obj.SC, args, h.fullID) end
  end
end

function P:Custom(ev, ...)
  if handlers[ev] then Dispatch(ev, { ... }) end
end

local function Kill(sourceGUID, targetGUID)
  if not (K.Safe(sourceGUID) and K.Safe(targetGUID)) then P:Custom("TRP3_KILL") return end
  local _, _, _, _, _, sourceName = GetPlayerInfoByGUID(sourceGUID)
  local kind, _, _, _, _, npcID = strsplit("-", targetGUID)
  if kind == "Player" then
    local className, classID, raceName, raceID, gender, name = GetPlayerInfoByGUID(targetGUID)
    P:Custom("TRP3_KILL", kind, sourceGUID, sourceName, targetGUID, name, classID, className, raceID, raceName, gender)
  else
    P:Custom("TRP3_KILL", kind, sourceGUID, sourceName, targetGUID, rawget(_G, "UNKNOWN") or "Unknown", npcID)
  end
end

frame:SetScript("OnEvent", function(_, ev, ...)
  if ev == "PARTY_KILL" then
    Kill(...)
    return
  end
  if ev == "COMBAT_LOG_EVENT_UNFILTERED" or ev == "COMBAT_LOG_EVENT" then
    local info = { CombatLogGetCurrentEventInfo() }
    if handlers.TRP3_KILL and info[2] == "PARTY_KILL" then Kill(info[4], info[8]) end
    if handlers[ev] then Dispatch(ev, info) end
    return
  end
  Dispatch(ev, { ... })
end)

-- Extended's own events, from what Kinship sees.
local function OnEmote(token) if handlers.TRP3_EMOTE then P:Custom("TRP3_EMOTE", token) end end
if C_ChatInfo and C_ChatInfo.PerformEmote then hooksecurefunc(C_ChatInfo, "PerformEmote", OnEmote) end
if rawget(_G, "DoEmote") then hooksecurefunc("DoEmote", OnEmote) end
K:On("DICE", function(res)
  if type(res) == "table" and res.me and handlers.TRP3_ROLL then P:Custom("TRP3_ROLL", res.expr or "", res.total or 0) end
end)

---------------------------------------------------------------------------
-- Look, Listen, Talk, Interact: the first matching action of the current
-- step, then its quest, then the campaign.
---------------------------------------------------------------------------
function P:Act(kind)
  local c = self:Current()
  local cl = c and self:Log(c)
  local def
  for _, a in ipairs(ACTIONS) do if a.key == kind then def = a end end
  if not cl then Alert("No campaign is playing.") return end
  local args = { object = cl }
  local function Try(obj, fullID)
    for _, a in pairs(type(obj) == "table" and type(obj.AC) == "table" and obj.AC or EMPTY) do
      if type(a) == "table" and a.TY == kind and S:Check(a.CO, args) then
        S:Run(a.SC, obj.SC, { object = cl }, fullID)
        return true
      end
    end
  end
  for _, q in ipairs(Keys(cl.QUEST)) do
    local ql = cl.QUEST[q]
    local qc = Class(c, q)
    if qc and type(ql) == "table" and not ql.FI then
      local sc = ql.CS and Class(c, q, ql.CS)
      if sc and Try(sc, E.FullID(c, q, ql.CS)) then return end
      if Try(qc, E.FullID(c, q)) then return end
    end
  end
  if Try(E:Get(c), c) then return end
  Alert(def and def.none or "Nothing happens.")
end

---------------------------------------------------------------------------
-- The campaign bar: the playing campaign and its four actions.
---------------------------------------------------------------------------
local bar
local function BuildBar()
  if bar then return bar end
  local f = CreateFrame("Frame", "KinshipRPCampaignBar", UIParent)
  f:SetSize(36 + 4 * 34 + 30, 40)
  f:SetFrameStrata("MEDIUM")
  f:SetClampedToScreen(true)
  f:SetMovable(true)
  f:EnableMouse(true)
  f:RegisterForDrag("LeftButton")
  f:SetScript("OnDragStart", f.StartMoving)
  f:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    local point, _, rel, x, y = self:GetPoint()
    K.db.settings.extBarPos = { point, rel, x, y }
  end)
  f.bg = f:CreateTexture(nil, "BACKGROUND")
  f.bg:SetAllPoints()
  f.bg:SetColorTexture(0, 0, 0, 0.55)
  f.edge = UI.Border(f)
  f.icon = f:CreateTexture(nil, "ARTWORK")
  f.icon:SetSize(30, 30)
  f.icon:SetPoint("LEFT", 5, 0)
  f.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
  UI.Round(f.icon)
  local hit = CreateFrame("Button", nil, f)
  hit:SetAllPoints(f.icon)
  hit:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  hit:SetScript("OnClick", function(_, button)
    if button == "RightButton" then
      UI.Menu(hit, function(root)
        local c = P:Current()
        root:CreateTitle(c and Name(E:Get(c)) or Loc["Campaign"])
        root:CreateButton("Open the quest journal", function() K.Journal:Open("quests") end)
        root:CreateButton("Pause the campaign", function() P:Pause() end)
      end)
    else
      K.Journal:Open("quests")
    end
  end)
  hit:SetScript("OnEnter", function(self)
    local c = P:Current()
    GameTooltip:SetOwner(self, "ANCHOR_TOP")
    GameTooltip:SetText(c and Name(E:Get(c)) or Loc["Campaign"], 1, 0.82, 0)
    GameTooltip:AddLine("Playing now. Click for your quest journal; right-click to pause it.", 1, 1, 1, true)
    GameTooltip:Show()
  end)
  hit:SetScript("OnLeave", function() GameTooltip:Hide() end)
  f.buttons = {}
  for i, a in ipairs(ACTIONS) do
    local b = CreateFrame("Button", nil, f)
    b:SetSize(30, 30)
    b:SetPoint("LEFT", 40 + (i - 1) * 34, 0)
    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetAllPoints()
    b.icon:SetTexture(a.icon)
    b.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    b:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
    b:SetScript("OnClick", function() P:Act(a.key) end)
    b:SetScript("OnEnter", function(self)
      GameTooltip:SetOwner(self, "ANCHOR_TOP")
      GameTooltip:SetText(a.label, 1, 0.82, 0)
      GameTooltip:AddLine(("Try this when the campaign asks you to. Also /kin %s."):format(a.label:lower()), 1, 1, 1, true)
      GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    f.buttons[i] = b
  end
  f.close = UI.CloseButton(f, nil, 18)
  f.close:SetPoint("RIGHT", -5, 0)
  f.close:SetScript("OnClick", function() P:Pause() end)
  UI.Tooltip(f.close, "Pause the campaign", "Your progress is kept. Play it again from your Database.")
  local pos = K.db.settings.extBarPos
  if type(pos) == "table" and pos[1] then
    f:SetPoint(pos[1], UIParent, pos[2] or pos[1], tonumber(pos[3]) or 0, tonumber(pos[4]) or 0)
  else
    f:SetPoint("BOTTOM", UIParent, "BOTTOM", 0, 190)
  end
  UI:OnTheme(function(t) f.edge:SetColor(t.ui[1], t.ui[2], t.ui[3], 0.8) end)
  bar = f
  return f
end

function P:ShowBar()
  local c = K.db and On() and self:Current()
  if not c or K.db.settings.extBar == false then
    if bar then bar:Hide() end
    return
  end
  local f = BuildBar()
  f.icon:SetTexture(E.IconTexture(E.Str(BA(E:Get(c)).IC) or "INV_Scroll_03"))
  f:Show()
end

---------------------------------------------------------------------------
-- NPC tooltips while a campaign plays
---------------------------------------------------------------------------
local function OnUnitTooltip(tt)
  if not (On() and P:Current()) or tt ~= GameTooltip then return end
  local _, unit = tt:GetUnit()
  if not unit or not K.Safe(unit) or UnitIsPlayer(unit) then return end
  local npc = P:NPC(unit)
  if not npc then return end
  local first = _G[tt:GetName() .. "TextLeft1"]
  if first and npc.name then first:SetText(npc.name) end
  if npc.title and npc.title ~= "" then tt:AddLine("<" .. npc.title .. ">", 1, 0.82, 0) end
  if npc.desc and npc.desc ~= "" then tt:AddLine(K.UI.Clean(npc.desc), 1, 1, 1, true) end
  tt:Show()
end

if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and Enum and Enum.TooltipDataType then
  TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Unit, function(tt) pcall(OnUnitTooltip, tt) end)
elseif GameTooltip:HasScript("OnTooltipSetUnit") then
  GameTooltip:HookScript("OnTooltipSetUnit", function(tt) pcall(OnUnitTooltip, tt) end)
end

---------------------------------------------------------------------------
-- Starting up
---------------------------------------------------------------------------
K:On("LOGIN", function()
  local st = P:State()
  if st.current and not E:Get(st.current) then st.current = nil end
  if st.current and On() then
    local c = st.current
    C_Timer.After(2, function()
      if P:Current() ~= c then return end
      Say("Resuming the campaign " .. Green(Name(E:Get(c))) .. ".")
      P:Rebuild()
      P:SyncAll(c)
    end)
  end
end)

-- A campaign removed from the Database stops playing.
K:On("EXT_DB", function(rootID)
  if K.db and P:State().current == rootID then
    if not E:Get(rootID) then P:State().current = nil end
    P:Rebuild()
    K:Fire("EXT_CAMPAIGN")
  end
end)
