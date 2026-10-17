-- Kinship RP: objectives that complete themselves. The quest's writer gives
-- an objective a rule, and Kinship watches for it on the player's own client:
--   place   reach the objective's map pin (its area, or 15 yards)
--   zone    reach a place by its name (a zone or subzone)
--   watch   keep watch at the pin for some minutes (the time adds up)
--   talk    target someone by name (optionally up close)
--   emote   do an emote (optionally at someone)
--   item    carry a Kinship item (optionally handed over when the quest is done)
--   gather  carry a number of a game item
--   wear    have a game item equipped
--   stash   find a stash by name when searching the area
--   dice    pass a dice check (a Roll button; optionally limited tries)
--   riddle  answer a riddle (the answer travels as a hash, never as text)
--   pass    give a password told in roleplay (likewise)
--   duel    win a duel (against anyone, or someone by name)
--   kill    defeat a number of enemies by name, or part of it ("Defias");
--           from the game's "X dies, you gain N experience" line, or seeing
--           your target die in a fight (no experience); or only ones you loot
--   bounty  defeat players in honourable combat (anyone, or someone by name),
--           from the game's "X dies (Honorable Kill)" line
--   effect  take on, or shake off, an effect
--   read    read a document
--   time    be there between two hours (server time; at the pin, if it has one)
--
-- Any rule can add "and also" conditions (auto.w): at the pin, between hours,
-- in character, in a group, with someone close by, carrying a Kinship item,
-- wearing a game item, under an effect. A rule that holds can need holding
-- for a while (auto.hold, seconds); one that happens can need doing several
-- times (auto.times).
--
-- An objective can be optional (o.opt: not needed to finish the quest),
-- hidden (o.hid: players see it once it's done) and can fail (o.fl: if they
-- die, leave the pin's area, or run out of time; dice and riddles also fail
-- when their tries run out). What a failure does (fl.th):
--   nil     holds up the quest (fl.retry lets them try again)
--   carry   the story carries on: it counts as dealt with, marked failed
--   open    a backup objective (fl.alt, a later one) opens in its place;
--           until then it's on standby, unseen and not needed
--   quest   the whole quest fails
-- and it can leave the player with an effect (fl.fx), within their boundaries.
-- On a storyteller's quest, a failure that moves the story on is shared like
-- progress: the storyteller's client takes it and sends it to everyone.
-- A quest can be "in order": an objective opens once every required one before it is done.
--
-- On a storyteller's quest, a follower's objective ticks for them at once and
-- the storyteller is told (K.Net "qauto"), and the storyteller's client ticks
-- it for everyone. If the storyteller ticks objectives themselves (quest.au
-- off), the follower's client only tells them. On any other quest the player
-- ticks it themselves and the writer gets a notice.

local ADDON, ns = ...
local K = ns.K
local UI = K.UI
local Safe = K.Safe
local A = {}
K.QuestAuto = A

K.Net:Gate({ "qauto" }, "campaigns")

local HERE = 15   -- yards that count as "at" a pin with no area
local RED = { 0.90, 0.36, 0.30 }

A.ORDER = { "place", "zone", "watch", "talk", "emote", "item", "gather", "wear", "stash",
  "dice", "riddle", "pass", "duel", "kill", "bounty", "effect", "read", "time" }
A.KINDS = {
  place  = { label = "Reach a place",          icon = "Interface\\Icons\\INV_Misc_Map_01" },
  zone   = { label = "Find a named place",     icon = "Interface\\Icons\\INV_Misc_Map02" },
  watch  = { label = "Keep watch",             icon = "Interface\\Icons\\Ability_Hunter_EagleEye" },
  talk   = { label = "Speak to someone",       icon = "Interface\\Icons\\INV_Misc_Note_01" },
  emote  = { label = "Do an emote",            icon = "Interface\\Icons\\Spell_Holy_PrayerOfSpirit" },
  item   = { label = "Carry a Kinship item",   icon = "Interface\\Icons\\INV_Misc_Bag_08" },
  gather = { label = "Gather game items",      icon = "Interface\\Icons\\INV_Misc_Bag_10" },
  wear   = { label = "Wear something",         icon = "Interface\\Icons\\INV_Chest_Cloth_17" },
  stash  = { label = "Find a stash",           icon = "Interface\\Icons\\INV_Box_01" },
  dice   = { label = "Pass a dice check",      icon = "Interface\\Icons\\INV_Misc_Dice_01" },
  riddle = { label = "Answer a riddle",        icon = "Interface\\Icons\\INV_Misc_QuestionMark" },
  pass   = { label = "Give the password",      icon = "Interface\\Icons\\INV_Misc_Key_03" },
  duel   = { label = "Win a duel",             icon = "Interface\\Icons\\INV_Sword_04" },
  kill   = { label = "Defeat enemies",         icon = "Interface\\Icons\\Ability_Rogue_Eviscerate" },
  bounty = { label = "Claim a bounty",         icon = "Interface\\Icons\\INV_Misc_Bone_HumanSkull_01" },
  effect = { label = "Take on an effect",      icon = "Interface\\Icons\\Spell_Holy_MagicalSentry" },
  read   = { label = "Read a document",        icon = "Interface\\Icons\\INV_Misc_Book_09" },
  time   = { label = "Be there at the hour",   icon = "Interface\\Icons\\INV_Misc_PocketWatch_01" },
}
-- Rules that hold (and can be held for a while) and rules that happen (and can be done several times).
A.HOLDS = { place = true, zone = true, talk = true, item = true, gather = true, wear = true, effect = true, time = true }
A.COUNTS = { emote = true, stash = true, dice = true, duel = true, kill = true, bounty = true }
-- Rules whose "how many" is part of the rule itself.
local OWN_COUNT = { kill = true, bounty = true }
A.EMOTES = { "BOW", "SALUTE", "WAVE", "GREET", "KNEEL", "PRAY", "CHEER", "THANK", "HUG", "DANCE", "CURTSEY", "NOD",
  "POINT", "BEG", "PLEAD", "SURRENDER", "ROAR", "TAUNT", "APOLOGIZE", "CRY", "LAUGH", "CLAP", "FLEX", "KISS", "SIT" }
A.FAILS = { tries = "Out of tries", die = "Failed: you died", out = "Failed: you left the area", time = "Failed: out of time" }
-- What a failure does, for the editor.
A.OUTCOMES = {
  { id = "carry", label = "Carry on (it counts, marked failed)" },
  { id = "open",  label = "Open a backup objective" },
  { id = "quest", label = "Fail the whole quest" },
}
local HOLD_LABEL = "Hold up the quest"

local function Q() return K.Quests end
local function Short(n) return Ambiguate and Ambiguate(n, "none") or n end
local function KindIcon(k) return A.KINDS[k] and A.KINDS[k].icon or "Interface\\Icons\\Spell_Nature_Lightning" end

---------------------------------------------------------------------------
-- Shape
---------------------------------------------------------------------------
local function Str(x, max)
  if type(x) ~= "string" then return "" end
  return strtrim((x:gsub("[%c|]", ""))):sub(1, max)
end
local function Int(x, lo, hi)
  x = tonumber(x)
  if not x or x ~= x then return nil end
  x = math.floor(x)
  if x < lo or x > hi then return nil end
  return x
end
local function Id(x) return type(x) == "string" and x ~= "" and #x <= 100 and x or nil end
local function Named(x) return type(x) == "string" and x ~= "" and x or nil end

-- Answers are compared by a hash of their plain form, so the quest never carries them as text.
function A.Normal(s)
  s = (type(s) == "string" and s or ""):lower():gsub("[%p%c]", " "):gsub("%s+", " ")
  s = strtrim(s):gsub("^the ", ""):gsub("^an? ", "")
  return s
end
function A.Hash(s)
  s = "kinship:" .. A.Normal(s)
  local h1, h2 = 5381, 21661
  for j = 1, #s do
    local c = s:byte(j)
    h1 = (h1 * 33 + c) % 2147483647
    h2 = (h2 * 131 + c * 7 + 1) % 2147483629
  end
  return ("%08x%08x"):format(h1, h2)
end
-- "Ash / the ash tree" -> up to five hashes.
function A.HashList(text)
  local out = {}
  for part in tostring(text or ""):gmatch("[^/;]+") do
    if A.Normal(part) ~= "" and #out < 5 then out[#out + 1] = A.Hash(part) end
  end
  return #out > 0 and out or nil
end
local function Hashes(h)
  if type(h) ~= "table" then return nil end
  local out = {}
  for j = 1, 5 do
    local x = h[j]
    if type(x) ~= "string" or not x:find("^%x+$") or #x ~= 16 then break end
    out[j] = x
  end
  return #out > 0 and out or nil
end

-- The "and also" conditions.
local function SanitizeAlso(w)
  if type(w) ~= "table" then return nil end
  local o = {}
  o.pin = w.pin and true or nil
  local h1, h2 = Int(w.h1, 0, 23), Int(w.h2, 0, 23)
  if h1 and h2 then o.h1, o.h2 = h1, h2 end
  o.ic = w.ic and true or nil
  o.grp = w.grp and true or nil
  local pn = Str(w.pn, 60); if pn ~= "" then o.pn = pn end
  o.cd = Id(w.cd); if o.cd then o.cnm = Str(w.cnm, 60) end
  o.wi = Int(w.wi, 1, 99999999); if o.wi then o.wnm = Str(w.wnm, 60) end
  local fa = Str(w.fa, 60); if fa ~= "" then o.fa, o.fnm = fa, Str(w.fnm, 40) end
  return next(o) and o or nil
end

function A.Sanitize(v)
  if type(v) ~= "table" or not A.KINDS[v.k] then return nil end
  local k, out = v.k, { k = v.k }
  if k == "talk" then
    out.n = Str(v.n, 60); if out.n == "" then return nil end
    out.near = v.near and true or nil
  elseif k == "emote" then
    out.e = Str(v.e, 20):upper(); if not out.e:find("^[%u_]+$") then return nil end
    local n = Str(v.n, 60); out.n = n ~= "" and n or nil
  elseif k == "item" then
    out.d = Id(v.d); if not out.d then return nil end
    out.c = Int(v.c, 1, 99) or 1
    out.take = v.take and true or nil
    out.nm = Str(v.nm, 60)
  elseif k == "gather" then
    out.i = Int(v.i, 1, 99999999); if not out.i then return nil end
    out.c = Int(v.c, 1, 999) or 1
    out.nm = Str(v.nm, 60)
  elseif k == "wear" then
    out.i = Int(v.i, 1, 99999999); if not out.i then return nil end
    out.nm = Str(v.nm, 60)
  elseif k == "zone" then
    out.n = Str(v.n, 60); if out.n == "" then return nil end
  elseif k == "watch" then
    out.m = Int(v.m, 1, 120); if not out.m then return nil end
    out.strict = v.strict and true or nil
  elseif k == "stash" then
    out.n = Str(v.n, 40); if out.n == "" then return nil end
  elseif k == "dice" then
    out.x = Str(v.x, 24); if out.x == "" then return nil end
    if K.Dice and K.Dice.Parse and not K.Dice.Parse(out.x) then return nil end
    out.at = Int(v.at, -999, 9999) or 1
    out.tries = Int(v.tries, 0, 99) or 0
  elseif k == "riddle" or k == "pass" then
    if k == "riddle" then out.q = Str(v.q, 200); if out.q == "" then return nil end end
    out.h = Hashes(v.h); if not out.h then return nil end
    out.tries = Int(v.tries, 0, 99) or 0
  elseif k == "duel" or k == "bounty" then
    local n = Str(v.n, 60); out.n = n ~= "" and n or nil
  elseif k == "kill" then
    out.n = Str(v.n, 60); if out.n == "" then return nil end
    out.loot = v.loot and true or nil
  elseif k == "effect" then
    out.a = Str(v.a, 60); if out.a == "" then return nil end
    out.nm = Str(v.nm, 40)
    out.lose = v.lose and true or nil
  elseif k == "read" then
    out.d = Id(v.d); if not out.d then return nil end
    out.nm = Str(v.nm, 60)
  elseif k == "time" then
    out.h1, out.h2 = Int(v.h1, 0, 23), Int(v.h2, 0, 23)
    if not out.h1 or not out.h2 then return nil end
  end
  if A.HOLDS[k] then out.hold = Int(v.hold, 5, 3600) end
  if A.COUNTS[k] then
    local t = Int(v.times, 1, 99)
    out.times = t and t > 1 and t or nil
  end
  out.w = SanitizeAlso(v.w)
  return out
end

-- An objective's options: optional, hidden, and how it can fail. Returns opt, hid, fl.
function A.Options(o)
  if type(o) ~= "table" then return nil, nil, nil end
  local fl
  if type(o.fl) == "table" then
    local f = o.fl
    fl = { die = f.die and true or nil, out = f.out and true or nil, mins = Int(f.mins, 1, 1440), retry = f.retry and true or nil }
    if f.th == "carry" or f.th == "open" or f.th == "quest" then fl.th = f.th end
    if fl.th == "open" then
      fl.alt = Int(f.alt, 1, 8)
      if not fl.alt then fl.th = "carry" end
    end
    if fl.th then fl.retry = nil end   -- trying again is for failures that hold things up
    local fx = Str(f.fx, 60)
    if fx ~= "" then fl.fx, fl.fxn = fx, Str(f.fxn, 40) end
    if not (fl.die or fl.out or fl.mins or fl.retry or fl.th or fl.fx) then fl = nil end
  end
  return o.opt and true or nil, o.hid and true or nil, fl
end

---------------------------------------------------------------------------
-- Words for a rule
---------------------------------------------------------------------------
local function GameItemName(id)
  local get = (C_Item and C_Item.GetItemNameByID) or GetItemInfo
  local ok, name = pcall(get, id)
  return ok and type(name) == "string" and name or nil
end
local function ItemId(s)
  if type(s) == "number" then return s end
  if type(s) ~= "string" then return nil end
  return tonumber(s:match("item:(%d+)") or s:match("(%d+)"))
end
local function Tries(n) return n > 0 and (", " .. n .. (n == 1 and " try" or " tries")) or "" end
local function Secs(s)
  s = math.floor(s)
  if s >= 60 and s % 60 == 0 then return (s / 60) .. " min" end
  if s >= 60 then return ("%d min %d s"):format(math.floor(s / 60), s % 60) end
  return s .. " s"
end
local function KinItemName(id, fallback)
  local def = K.Items and K.Items:Get(id)
  return def and def.name or Named(fallback) or "a Kinship item"
end

-- "Reach the pin (Elwynn Forest)", "Speak to Guard Thomas", "/bow at Marshal Dughan"...
local function Main(auto, o)
  local k = auto.k
  if k == "place" then
    local QM = K.QuestMarkers
    return o and o.marker and ("Reach the pin  (" .. ((QM and QM.Label(o.marker)) or "?") .. ")") or "Reach the pin  (no pin set yet)"
  elseif k == "zone" then return ("Find %s"):format(UI.Escape(auto.n))
  elseif k == "watch" then
    local QM = K.QuestMarkers
    local where = o and o.marker and QM and QM.Label(o.marker)
    return ("Keep watch for %d %s%s"):format(auto.m, auto.m == 1 and "minute" or "minutes",
      where and ("  (" .. where .. ")") or "  (no pin set yet)")
  elseif k == "talk" then return ("Speak to %s%s"):format(UI.Escape(auto.n), auto.near and ", up close" or "")
  elseif k == "emote" then return ("/%s%s"):format(auto.e:lower(), auto.n and (" at " .. UI.Escape(auto.n)) or "")
  elseif k == "item" then
    return ("Carry %s%s%s"):format(auto.c > 1 and (auto.c .. " x ") or "", UI.Escape(KinItemName(auto.d, auto.nm)),
      auto.take and ", handed over at the end" or "")
  elseif k == "gather" then
    local name = GameItemName(auto.i) or Named(auto.nm) or ("item " .. auto.i)
    return ("Gather %d %s"):format(auto.c, UI.Escape(name))
  elseif k == "wear" then
    return ("Wear %s"):format(UI.Escape(GameItemName(auto.i) or Named(auto.nm) or ("item " .. auto.i)))
  elseif k == "stash" then return ("Find the stash \"%s\""):format(UI.Escape(auto.n))
  elseif k == "dice" then
    return ("Roll %s: %d or more%s"):format(auto.x, auto.at, Tries(auto.tries))
  elseif k == "riddle" then return ("Answer the riddle: \"%s\"%s"):format(UI.Escape(auto.q), Tries(auto.tries))
  elseif k == "pass" then return "Give the password" .. Tries(auto.tries)
  elseif k == "duel" then return auto.n and ("Win a duel against " .. UI.Escape(auto.n)) or "Win a duel"
  elseif k == "kill" then
    return ("%s %d %s"):format(auto.loot and "Defeat and loot" or "Defeat", auto.times or 1, UI.Escape(auto.n))
  elseif k == "bounty" then
    local n = auto.times or 1
    if auto.n then
      return ("Defeat %s in honourable combat%s"):format(UI.Escape(auto.n), n > 1 and (", " .. n .. " times") or "")
    end
    return ("Defeat %d %s in honourable combat"):format(n, n == 1 and "enemy" or "enemies")
  elseif k == "effect" then return ("%s %s"):format(auto.lose and "Shake off" or "Take on", UI.Escape(Named(auto.nm) or auto.a))
  elseif k == "read" then return ("Read \"%s\""):format(UI.Escape(Named(auto.nm) or "a document"))
  elseif k == "time" then
    return ("Between %02d:00 and %02d:00, server time%s"):format(auto.h1, auto.h2, o and o.marker and ", at the pin" or "")
  end
end

-- "at the pin, in character, carrying the Signet, for 2 min"
function A.DescribeAlso(auto)
  local p, w = {}, auto.w or {}
  if w.pin then p[#p + 1] = "at the pin" end
  if w.h1 then p[#p + 1] = ("between %02d:00 and %02d:00"):format(w.h1, w.h2) end
  if w.ic then p[#p + 1] = "in character" end
  if w.grp then p[#p + 1] = "in a group" end
  if w.pn then p[#p + 1] = "with " .. UI.Escape(w.pn) .. " close by" end
  if w.cd then p[#p + 1] = "carrying " .. UI.Escape(KinItemName(w.cd, w.cnm)) end
  if w.wi then p[#p + 1] = "wearing " .. UI.Escape(GameItemName(w.wi) or Named(w.wnm) or ("item " .. w.wi)) end
  if w.fa then p[#p + 1] = "under " .. UI.Escape(Named(w.fnm) or w.fa) end
  if auto.hold then p[#p + 1] = "for " .. Secs(auto.hold) end
  if auto.times and not OWN_COUNT[auto.k] then p[#p + 1] = auto.times .. " times" end
  return #p > 0 and table.concat(p, ", ") or nil
end

function A.Describe(auto, o)
  if not auto then return nil end
  local main = Main(auto, o)
  local also = A.DescribeAlso(auto)
  return also and (main .. "; " .. also) or main
end

-- "Optional  ·  Fails if you die or 10 min pass  ·  If it fails, the story carries on"
-- e (optional): the quest, to name a backup objective, and to tell its writer which ones are backups.
function A.DescribeOptions(o, e, i)
  if type(o) ~= "table" then return nil end
  local p = {}
  if o.opt then p[#p + 1] = "Optional" end
  if o.hid then p[#p + 1] = "Hidden until done" end
  local from = e and i and A.BackupOf(e, i)
  if from then p[#p + 1] = ("Backup: opens if objective %d fails"):format(from) end
  local f = o.fl
  if f then
    local why = {}
    if f.die then why[#why + 1] = "you die" end
    if f.out then why[#why + 1] = "you leave the area" end
    if f.mins then why[#why + 1] = ("%d min pass"):format(f.mins) end
    if #why > 0 then p[#p + 1] = "Fails if " .. table.concat(why, " or ") .. (f.retry and " (you can try again)" or "")
    elseif f.retry then p[#p + 1] = "You can try again" end
    local mine = e and Q():IsMine(e)
    if f.th == "carry" then p[#p + 1] = "If it fails, the story carries on"
    elseif f.th == "quest" then p[#p + 1] = "If it fails, so does the quest"
    elseif f.th == "open" then
      -- Players learn there's another way only when they need it.
      local alt = e and e.objectives and e.objectives[f.alt]
      if mine or not e then p[#p + 1] = ("If it fails, objective %d opens"):format(f.alt) .. (alt and (": " .. UI.Clean(alt.text)) or "")
      else p[#p + 1] = "If it fails, the story carries on" end
    end
    if f.fx then p[#p + 1] = "Failing leaves you " .. UI.Escape(Named(f.fxn) or f.fx) end
  end
  return #p > 0 and table.concat(p, "  ·  ") or nil
end

---------------------------------------------------------------------------
-- Which objectives are open, shown and watched
---------------------------------------------------------------------------
local held, lastWatch = {}, {}   -- this session only: when a hold began, the last keep-watch tick
local live = false               -- something is counting up or down (the tracker redraws now and then)
local function Key(e, i) return tostring(e.id) .. ":" .. i end

-- Which objective, if any, this one is the backup for.
function A.BackupOf(e, j)
  for i, o in ipairs(e.objectives or {}) do
    if i < j and o.fl and o.fl.th == "open" and o.fl.alt == j then return i end
  end
end

-- A backup waiting for its objective to fail: unseen, unwatched and not needed.
function A.Standby(e, j)
  for i, o in ipairs(e.objectives or {}) do
    if i < j and o.fl and o.fl.th == "open" and o.fl.alt == j and not o.failed then return true end
  end
  return false
end

-- Done, or failed in a way that lets the story move on.
function A.Resolved(o)
  if o.done then return true end
  return o.failed == true and o.fl ~= nil and (o.fl.th == "carry" or o.fl.th == "open")
end

-- Counts towards finishing the quest: required, and not a backup on standby.
function A.Required(e, i)
  local o = e.objectives and e.objectives[i]
  return o ~= nil and not o.opt and not A.Standby(e, i)
end

-- In order, an objective opens once every required one before it is dealt with.
function A.Open(e, i)
  if not e.seq then return true end
  for j = 1, i - 1 do
    local p = e.objectives[j]
    if p and not A.Resolved(p) and A.Required(e, j) then return false end
  end
  return true
end

-- The first required objective still to deal with.
function A.Current(e)
  for i, o in ipairs(e.objectives or {}) do
    if not A.Resolved(o) and A.Required(e, i) then return i end
  end
end

-- Players see a hidden objective once it's done, and a backup once it opens; its writer always sees both.
function A.Visible(e, i)
  local o = e.objectives and e.objectives[i]
  if not o then return false end
  if Q():IsMine(e) then return true end
  return not (o.hid and not o.done) and not A.Standby(e, i)
end

-- "locked" (in order, not its turn), "failed", or nil.
function A.State(e, i)
  local o = e.objectives and e.objectives[i]
  if not o or o.done then return nil end
  if o.failed then return "failed" end
  if not A.Open(e, i) then return "locked" end
end

function A.FailText(o)
  return o and A.FAILS[o.failWhy] or "Failed"
end

-- A storyteller running their quest for others: their own copy isn't played,
-- so it neither completes itself nor fails (on a quest of your own, it does).
local function ForOthers(e)
  if not (e.st and e.players and Q():IsMine(e)) then return false end
  for _, p in pairs(e.players) do
    if p.s == "active" or p.s == "complete" then return true end
  end
  return false
end

A.ForOthers = ForOthers

-- May this objective tick itself on this client?
function A.Watching(e, i)
  local o = e.objectives and e.objectives[i]
  if not (o and o.auto and not o.done and not o.failed and not o.noticed and e.state == "active") then return false end
  if not A.Open(e, i) or A.Standby(e, i) or ForOthers(e) then return false end
  return Q():CanTick(e) or e.st == true
end

-- May this objective fail on this client?
function A.Failable(e, i)
  local o = e.objectives and e.objectives[i]
  if not (o and o.fl and not o.done and not o.failed and e.state == "active" and A.Open(e, i)) then return false end
  return not A.Standby(e, i) and not ForOthers(e)
end

function A.TimeLeft(e, i)
  local o = e.objectives and e.objectives[i]
  if not (o and o.fl and o.fl.mins and o.openAt and not o.done and not o.failed) then return nil end
  return math.max(0, math.floor(o.fl.mins * 60 - (time() - o.openAt)))
end

-- How far a counted objective has got: have, need (or nil when it isn't
-- counted). Kills and bounties always; "do it N times"; and gathering or
-- carrying more than one, from the bags as they are now.
function A.Counter(e, i)
  local o = e.objectives and e.objectives[i]
  local a = o and o.auto
  if not a then return nil end
  local have, need
  if OWN_COUNT[a.k] then
    have, need = o.cnt or 0, a.times or 1
  elseif a.times then
    have, need = o.cnt or 0, a.times
  elseif a.k == "gather" and a.c > 1 then
    local count = (C_Item and C_Item.GetItemCount) or GetItemCount
    local ok, n = pcall(count, a.i)
    have, need = ok and type(n) == "number" and n or 0, a.c
  elseif a.k == "item" and a.c > 1 then
    have, need = K.Items and K.Items:Has(a.d) or 0, a.c
  else
    return nil
  end
  if o.done then have = need end
  return math.min(have, need), need
end

-- "3/8 " before an objective's text, as the game writes its own quests.
function A.CounterPrefix(e, i)
  local have, need = A.Counter(e, i)
  return have and ("%d/%d "):format(have, need) or ""
end

-- "4 min 10 s of 10 min", "held 20 s of 1 min", "3:12 left"...
function A.ProgressText(e, i)
  local o = e.objectives and e.objectives[i]
  if not o or o.done or o.failed or e.state ~= "active" then return nil end
  local a, p = o.auto, {}
  if a then
    if a.k == "watch" and (o.watch or 0) > 0 then p[#p + 1] = ("%s/%d min"):format(Secs(o.watch), a.m) end
    local since = held[Key(e, i)]
    if a.hold and since then p[#p + 1] = ("held %s/%s"):format(Secs(GetTime() - since), Secs(a.hold)) end
    if a.k == "dice" and (o.rolls or 0) > 0 then p[#p + 1] = o.rolls .. " rolled" end
    if (a.k == "riddle" or a.k == "pass") and a.tries > 0 and (o.guesses or 0) > 0 then
      p[#p + 1] = ("%d/%d tries used"):format(o.guesses, a.tries)
    end
  end
  if o.noticed then p[#p + 1] = "the storyteller has been told" end
  local left = A.TimeLeft(e, i)
  if left then p[#p + 1] = ("%d:%02d left"):format(math.floor(left / 60), left % 60) end
  return #p > 0 and table.concat(p, ", ") or nil
end

---------------------------------------------------------------------------
-- Completing, counting, failing
---------------------------------------------------------------------------
local function Open(e) return function() K.Quests:Open(e.id) end end

local function Toast(e, o)
  UI.Toast({ icon = KindIcon(o.auto and o.auto.k), round = true, color = K.Quests.DONE, duration = 5,
    title = UI.Clean(o.text), text = "Objective complete  ·  " .. UI.Clean(e.title), sound = "IG_QUEST_LIST_SELECT",
    onClick = Open(e) })
end

local function Tell(e, msg)
  if not Q():IsMine(e) and e.author then K.Net:Send("qauto", msg, "WHISPER", e.author) end
end

function A:Complete(e, i, extra)
  local QQ = Q()
  local o = e.objectives[i]
  if not o or o.done then return end
  held[Key(e, i)], lastWatch[Key(e, i)] = nil, nil
  if QQ:CanTick(e) then
    QQ:SetObjective(e.id, i, true)
  elseif e.au == false then
    -- The storyteller ticks this one themselves: just tell them.
    o.noticed = true
    UI.Toast({ icon = KindIcon(o.auto and o.auto.k), round = true, duration = 5, title = UI.Clean(o.text),
      text = "Done: the storyteller has been told  ·  " .. UI.Clean(e.title), onClick = Open(e) })
    Tell(e, { id = e.id, i = i, w = extra })
    K:Fire("QUESTS")
    return
  else
    -- A storyteller's quest: done for you now; the storyteller's client confirms it for everyone.
    o.done, o.autoAt = true, time()
    K:Fire("QUEST_OBJECTIVE", e.id, i, true)
    QQ:CheckComplete(e)
    K:Fire("QUESTS")
  end
  Toast(e, o)
  Tell(e, { id = e.id, i = i, w = extra })
end

-- One more time towards "do it N times". Returns true once it's complete.
function A:Count(e, i, extra)
  local o = e.objectives[i]
  local need = o.auto.times or 1
  o.cnt = (o.cnt or 0) + 1
  if o.cnt >= need then self:Complete(e, i, extra) return true end
  UI.Toast({ icon = KindIcon(o.auto.k), round = true, duration = 3, title = UI.Clean(o.text),
    text = ("%d/%d  ·  %s"):format(o.cnt, need, UI.Clean(e.title)), onClick = Open(e) })
  K:Fire("QUESTS")
end

-- A lasting effect from failing, within the player's own boundaries.
local function Consequence(e, f)
  local Au = K.Auras
  local def = Au and f.fx and Au:Def(f.fx)
  if not def then return end
  local from = not Q():IsMine(e) and e.author or nil
  local note = UI.Clean(e.title)
  local c = Au:ConsentOf(nil, def.kind, true)
  if c == "2" then return end
  if c == "3" then
    UI.Toast({ icon = def.icon, round = true, duration = 10, title = "Take on " .. UI.Escape(def.name) .. "?",
      text = "Failing left you with this. Click to take it on; your boundaries say to ask.",
      onClick = function() Au:Apply(def, nil, from, note) end })
    return
  end
  Au:Apply(def, nil, from, note)
end

-- What a failure does next. Runs wherever the failure lands: the player's
-- client, the storyteller's, and everyone the storyteller shares it with.
function A:Outcome(e, i, quiet)
  local o = e.objectives[i]
  local f = o and o.fl
  local QQ = Q()
  if f and f.th == "open" then
    local alt = e.objectives[f.alt]
    if alt and not alt.done and not quiet then
      UI.Toast({ icon = KindIcon(alt.auto and alt.auto.k), round = true, duration = 6, color = K:Theme().accent,
        title = "Another way", text = UI.Clean(alt.text) .. "  ·  " .. UI.Clean(e.title), onClick = Open(e) })
    end
  end
  if f and f.th == "quest" then
    if QQ:CanTick(e) or not e.st or e.au ~= false then QQ:Fail(e.id) end
    return
  end
  if f and (f.th == "carry" or f.th == "open") then QQ:CheckComplete(e) end
end

function A:Fail(e, i, why, extra)
  local o = e.objectives[i]
  if not o or o.done or o.failed then return end
  o.failed, o.failWhy = true, why
  held[Key(e, i)], lastWatch[Key(e, i)] = nil, nil
  local f = o.fl or {}
  local after = (f.th == "carry" or f.th == "open") and "  ·  The story carries on"
    or (f.retry and "  ·  You can try again") or ""
  UI.Toast({ icon = KindIcon(o.auto and o.auto.k), round = true, duration = 5, color = RED,
    title = A.FAILS[why] or "Objective failed",
    text = UI.Clean(o.text) .. "  ·  " .. UI.Clean(e.title) .. after,
    onClick = Open(e) })
  Tell(e, { id = e.id, i = i, f = true, y = why, w = extra })
  Consequence(e, f)
  if Q():IsMine(e) then Q():Push(e) end
  self:Outcome(e, i)
  K:Fire("QUESTS")
end

-- A failure that arrived from elsewhere (the storyteller's shared progress, or a follower's notice).
function A:Mark(e, i, why)
  local o = e.objectives[i]
  if not o or o.done or o.failed then return end
  o.failed, o.failWhy = true, A.FAILS[why] and why or nil
  held[Key(e, i)], lastWatch[Key(e, i)] = nil, nil
  self:Outcome(e, i)
  K:Fire("QUESTS")
end

-- Everything that counts as trying, cleared for another go.
local RUNTIME = { "failed", "failWhy", "rolls", "guesses", "cnt", "watch", "beenThere", "openAt", "seen", "hadEffect", "noticed" }
function A:Retry(id, i)
  local QQ = Q()
  local e = QQ and QQ:Log()[id]
  local o = e and e.objectives[i]
  if not (o and o.failed and o.fl and o.fl.retry and not o.fl.th and e.state == "active") then return end
  for _, k in ipairs(RUNTIME) do o[k] = nil end
  held[Key(e, i)], lastWatch[Key(e, i)] = nil, nil
  Tell(e, { id = e.id, i = i, r = true })
  K:Fire("QUESTS")
end

---------------------------------------------------------------------------
-- The checks
---------------------------------------------------------------------------
local function NameLike(n, want)
  if not want or want == "" then return true end
  if not Safe(n) or type(n) ~= "string" or n == "" then return false end
  n, want = Short(n):lower(), want:lower()
  return n == want or n:find(want, 1, true) ~= nil or want:find(n, 1, true) ~= nil
end

local function TargetMatches(want)
  if not want or want == "" then return true end
  if not UnitExists("target") then return false end
  return NameLike(UnitName("target"), want)
end

local function Near(unit, which)
  if not CheckInteractDistance then return true end
  local ok, v = pcall(CheckInteractDistance, unit or "target", which or 3)
  return ok and Safe(v) and v and true or false
end

local function AtPin(o)
  local QM = K.QuestMarkers
  if not (QM and o.marker) then return false end
  local d = QM.Distance(o.marker)
  return d ~= nil and d <= (o.marker.r or HERE)
end

local function HasEffect(a)
  local Au = K.Auras
  if not Au then return false end
  for _, e in ipairs(Au:Of(nil, true)) do
    if e.id == a or (e.name and e.name:lower() == a:lower()) then return true end
  end
  return false
end

local function InHours(h1, h2)
  local h = GetGameTime and GetGameTime()
  if not h then return false end
  if h1 <= h2 then return h >= h1 and h < h2 + (h1 == h2 and 1 or 0) end
  return h >= h1 or h < h2
end

local function InCharacter()
  local p = K.Profile and K:Profile()
  return p ~= nil and p.status == "ic"
end

local function Wearing(id)
  local fn = (C_Item and C_Item.IsEquippedItem) or IsEquippedItem
  if fn then
    local ok, v = pcall(fn, id)
    if ok and Safe(v) then return v and true or false end
  end
  for slot = 1, 19 do
    local ok, have = pcall(GetInventoryItemID, "player", slot)
    if ok and Safe(have) and have == id then return true end
  end
  return false
end

-- Someone in your group, by name, close enough to talk to.
local function WithPlayer(want)
  local n = GetNumGroupMembers and GetNumGroupMembers() or 0
  if n == 0 then return false end
  local raid = IsInRaid and IsInRaid()
  for j = 1, raid and n or (n - 1) do
    local u = (raid and "raid" or "party") .. j
    if UnitExists(u) and not UnitIsUnit(u, "player") and NameLike(UnitName(u), want) then
      if Near(u, 4) then return true end
      if UnitInRange then
        local ok, inRange = pcall(UnitInRange, u)
        if ok and Safe(inRange) and inRange then return true end
      end
    end
  end
  return false
end

local function ZoneMatches(want)
  want = want:lower()
  for _, fn in ipairs({ GetSubZoneText, GetMinimapZoneText, GetZoneText, GetRealZoneText }) do
    local ok, z = pcall(fn)
    if ok and Safe(z) and type(z) == "string" and z ~= "" then
      z = z:lower()
      if z == want or (#want >= 4 and z:find(want, 1, true)) then return true end
    end
  end
  return false
end

-- The "and also" conditions. Returns true, or false and what's missing.
local function Also(o, a)
  local w = a.w
  if not w then return true end
  if w.pin and not AtPin(o) then return false, "at the pin" end
  if w.h1 and not InHours(w.h1, w.h2) then return false, ("between %02d:00 and %02d:00"):format(w.h1, w.h2) end
  if w.ic and not InCharacter() then return false, "in character" end
  if w.grp and not (IsInGroup and IsInGroup()) then return false, "in a group" end
  if w.pn and not WithPlayer(w.pn) then return false, "with " .. w.pn .. " close by" end
  if w.cd and not (K.Items and K.Items:Has(w.cd) >= 1) then return false, "carrying " .. KinItemName(w.cd, w.cnm) end
  if w.wi and not Wearing(w.wi) then return false, "wearing " .. (GameItemName(w.wi) or Named(w.wnm) or "the item") end
  if w.fa and not HasEffect(w.fa) then return false, "under " .. (Named(w.fnm) or w.fa) end
  return true
end
A.Also = Also

local function Nope(why)
  UI.Toast({ icon = "Interface\\Icons\\INV_Misc_QuestionMark", round = true, duration = 4,
    title = "Not yet", text = "This needs you " .. why .. "." })
end

-- Polled checks: true when the rule is met now.
local CHECK = {
  place = function(o) return AtPin(o) end,
  zone = function(o, a) return ZoneMatches(a.n) end,
  talk = function(o, a) return TargetMatches(a.n) and (not a.near or Near()) end,
  item = function(o, a) return K.Items ~= nil and K.Items:Has(a.d) >= a.c end,
  gather = function(o, a)
    local count = (C_Item and C_Item.GetItemCount) or GetItemCount
    local ok, n = pcall(count, a.i)
    return ok and type(n) == "number" and n >= a.c
  end,
  wear = function(o, a) return Wearing(a.i) end,
  effect = function(o, a)
    local has = HasEffect(a.a)
    if a.lose then
      if has then o.hadEffect = true end
      return not has and o.hadEffect == true
    end
    return has
  end,
  time = function(o, a) return InHours(a.h1, a.h2) and (not o.marker or AtPin(o)) end,
}

-- Every objective being watched: { e, i, o }.
local function Watched()
  local out, QQ = {}, Q()
  if not (QQ and K:ExtOn("campaigns")) then return out end
  for _, e in pairs(QQ:Log()) do
    if type(e) == "table" and e.state == "active" then
      for i, o in ipairs(e.objectives or {}) do
        if A.Watching(e, i) then out[#out + 1] = { e = e, i = i, o = o } end
      end
    end
  end
  return out
end

local function EachFailable(fn)
  local QQ = Q()
  if not (QQ and K:ExtOn("campaigns")) then return end
  for _, e in pairs(QQ:Log()) do
    if type(e) == "table" and e.state == "active" then
      for i, o in ipairs(e.objectives or {}) do
        if A.Failable(e, i) then fn(e, i, o) end
      end
    end
  end
end

function A:CheckOne(e, i, o, a, now)
  local key, k = Key(e, i), a.k
  if k == "watch" then
    -- Time at the pin adds up (or starts again on leaving, if strict).
    local last = lastWatch[key]
    lastWatch[key] = now
    if AtPin(o) and Also(o, a) then
      if last then o.watch = (o.watch or 0) + math.min(2, now - last) end
      live = true
    elseif a.strict and (o.watch or 0) > 0 then
      o.watch = 0
    end
    if (o.watch or 0) >= a.m * 60 then self:Complete(e, i) end
    return
  elseif k == "stash" then
    -- Each different stash found counts once.
    local St = K.Stashes
    local want = a.n:lower()
    for _, r in ipairs(St and St.results or {}) do
      if r.name and r.name:lower():find(want, 1, true) and GetTime() - (r.born or 0) < 120 then
        local id = tostring(r.owner or "") .. ":" .. tostring(r.id or r.name)
        o.seen = o.seen or {}
        if not o.seen[id] and Also(o, a) then
          o.seen[id] = true
          if self:Count(e, i) then return end
        end
      end
    end
    return
  end
  local fn = CHECK[k]
  if not fn then return end
  local met = fn(o, a) and Also(o, a)
  if a.hold then
    if met then
      held[key] = held[key] or now
      live = true
      if now - held[key] >= a.hold then self:Complete(e, i) end
    else
      held[key] = nil
    end
  elseif met then
    self:Complete(e, i)
  end
end

function A:CheckFails()
  local now = time()
  EachFailable(function(e, i, o)
    local f = o.fl
    if f.mins then
      o.openAt = o.openAt or now
      live = true
      if now - o.openAt >= f.mins * 60 then self:Fail(e, i, "time") return end
    end
    if f.out and o.marker then
      if AtPin(o) then
        o.beenThere = true
      elseif o.beenThere then
        local QM = K.QuestMarkers
        local d = QM and QM.Distance(o.marker)
        if not d or d > (o.marker.r or HERE) + 20 then self:Fail(e, i, "out") end
      end
    end
  end)
end

function A:Check()
  live = false
  local now = GetTime()
  for _, w in ipairs(Watched()) do
    K.Try("quest auto", self.CheckOne, self, w.e, w.i, w.o, w.o.auto, now)
  end
  K.Try("quest auto", self.CheckFails, self)
end

-- An enemy's name against the rule's: the same, or containing it ("Defias" counts "Defias Thug").
local function KillName(n, want)
  if not want or want == "" then return true end
  if not Safe(n) or type(n) ~= "string" or n == "" then return false end
  n, want = Short(n):lower(), want:lower()
  return n == want or n:find(want, 1, true) ~= nil
end

-- Things that happen rather than hold: an emote, opening a document, winning
-- a duel, a kill, looting a corpse (guid: which one), an honourable kill.
function A:Signal(kind, value, guid)
  for _, w in ipairs(Watched()) do
    local o, a = w.o, w.o.auto
    local hit = (kind == "emote" and a.k == "emote" and value == a.e and TargetMatches(a.n))
      or (kind == "read" and a.k == "read" and value == a.d)
      or (kind == "duel" and a.k == "duel" and NameLike(value, a.n))
      or (kind == "kill" and a.k == "kill" and not a.loot and KillName(value, a.n))
      or (kind == "loot" and a.k == "kill" and a.loot and KillName(value, a.n) and not (guid and o.seen and o.seen[guid]))
      or (kind == "bounty" and a.k == "bounty" and KillName(value, a.n))
    if hit and Also(o, a) then
      if kind == "loot" and guid then o.seen = o.seen or {}; o.seen[guid] = true end
      if A.COUNTS[a.k] then self:Count(w.e, w.i) else self:Complete(w.e, w.i) end
    end
  end
end

function A:OnDeath()
  EachFailable(function(e, i, o) if o.fl.die then self:Fail(e, i, "die") end end)
end

local function Find(id, i)
  local QQ = Q()
  local e = QQ and QQ:Log()[id]
  return e, e and e.objectives[i]
end

-- The Roll button on a dice check.
function A:Roll(id, i)
  local e, o = Find(id, i)
  if not (o and o.auto and o.auto.k == "dice") or not A.Watching(e, i) then return end
  if not K.Dice then K:Print("The dice aren't available.") return end
  local ok, why = Also(o, o.auto)
  if not ok then Nope(why) return end
  local res = K.Dice:Roll(o.auto.x)
  if not res then return end
  o.rolls = (o.rolls or 0) + 1
  if res.total >= o.auto.at and self:Count(e, i, res.total) then return end
  if o.auto.tries > 0 and o.rolls >= o.auto.tries then
    self:Fail(e, i, "tries", res.total)
  else
    K:Fire("QUESTS")
  end
end

-- A riddle's answer or a password. Returns done, message, out-of-tries.
function A:Answer(id, i, text)
  local e, o = Find(id, i)
  if not (o and o.auto and (o.auto.k == "riddle" or o.auto.k == "pass")) or not A.Watching(e, i) then return false end
  if A.Normal(text) == "" then return false end
  local ok, why = Also(o, o.auto)
  if not ok then return false, "This needs you " .. why .. "." end
  local h = A.Hash(text)
  for _, x in ipairs(o.auto.h) do
    if x == h then self:Complete(e, i) return true end
  end
  o.guesses = (o.guesses or 0) + 1
  local tries = o.auto.tries
  if tries > 0 and o.guesses >= tries then
    self:Fail(e, i, "tries")
    return false, "Out of tries.", true
  end
  K:Fire("QUESTS")
  local left = tries > 0 and (tries - o.guesses) or nil
  return false, left and ("Not that. %d %s left."):format(left, left == 1 and "try" or "tries") or "Not that."
end

-- The button an objective offers right now: label, onClick, menu text, icon (or nil).
local ACT_ICON = {
  retry = "Interface\\Icons\\Spell_Holy_Renew", dice = "Interface\\Icons\\INV_Misc_Dice_01",
  answer = "Interface\\Icons\\INV_Misc_QuestionMark", search = "Interface\\Icons\\INV_Misc_Spyglass_02",
}
function A.Action(e, i)
  local o = e.objectives and e.objectives[i]
  if not o or o.done or e.state ~= "active" or not e.id then return nil end
  local id = e.id
  if o.failed then
    if o.fl and o.fl.retry and not o.fl.th and not ForOthers(e) then
      return "Try again", function() A:Retry(id, i) end, "Try again: " .. o.text, ACT_ICON.retry
    end
    return nil
  end
  if not A.Watching(e, i) then return nil end
  local k = o.auto.k
  if k == "dice" then
    return "Roll", function() A:Roll(id, i) end, ("Roll %s for: %s"):format(o.auto.x, o.text), ACT_ICON.dice
  end
  if k == "riddle" or k == "pass" then
    return "Answer", function() A:Ask(id, i) end, (k == "pass" and "Give the password: " or "Answer: ") .. o.text, ACT_ICON.answer
  end
  if k == "stash" and K.Stashes then
    return "Search", function() K.Stashes:Search() end, "Search the area: " .. o.text, ACT_ICON.search
  end
end

-- The storyteller's side: a follower's objective completed, failed, or is being tried again.
K.Net:On("qauto", function(msg, sender)
  local QQ = Q()
  if not QQ or type(msg) ~= "table" or type(msg.id) ~= "string" or #msg.id > 96 then return end
  local e = QQ:Log()[msg.id]
  if not e or not QQ:IsMine(e) or e.state ~= "active" then return end
  local key = K.NameKey(sender)
  if not (key and e.players and e.players[key]) then return end
  local i = tonumber(msg.i)
  local o = i and e.objectives[i]
  if not o then return end
  if msg.r then
    K:Print(("%s is trying again: %s"):format(Short(sender), UI.Clean(o.text)))
    return
  end
  local roll = tonumber(msg.w)
  local how = roll and (" (rolled " .. math.floor(roll) .. ")") or ""
  if msg.f then
    local why = ({ tries = "is out of tries", die = "died", out = "left the area", time = "ran out of time" })[msg.y] or "failed"
    local th = o.fl and o.fl.th
    local after = ({ carry = "  ·  The story carries on", open = "  ·  The backup objective opens", quest = "  ·  The quest fails" })[th] or ""
    UI.Toast({ icon = KindIcon(o.auto and o.auto.k), round = true, color = RED, duration = 6,
      title = Short(sender) .. " " .. why .. how, text = UI.Clean(o.text) .. (e.au ~= false and after or ""), onClick = Open(e) })
    -- A failure that moves the story on is shared, like progress (unless you tick objectives yourself).
    if th and e.st and e.au ~= false and not o.done and not o.failed then
      A:Mark(e, i, msg.y)
      if e.state == "active" then QQ:Push(e) end
    end
    return
  end
  if not o.auto then return end
  UI.Toast({ icon = KindIcon(o.auto.k), round = true, color = QQ.DONE, duration = 6,
    title = Short(sender) .. " completed an objective" .. how, text = UI.Clean(o.text) .. "  ·  " .. UI.Clean(e.title),
    onClick = Open(e) })
  if e.st and e.au ~= false and not o.done then QQ:SetObjective(e.id, i, true) end
end)

-- Kinship items to hand over, once the quest is done.
K:On("QUEST_COMPLETE", function(id)
  local QQ = Q()
  local e = QQ and QQ:Log()[id]
  if not e or not K.Items then return end
  for _, o in ipairs(e.objectives or {}) do
    local a = o.auto
    if a and a.k == "item" and a.take and o.done then K.Items:Remove(a.d, a.c) end
  end
end)

---------------------------------------------------------------------------
-- Duels, from the game's own "X has defeated Y in a duel" lines
---------------------------------------------------------------------------
-- A game format string ("%s dies, you gain %d experience.") as a Lua pattern,
-- with which argument each capture is. whole: the line must end there too
-- (otherwise extras like "(+12 group bonus)" may follow).
local function Pattern(fmt, whole)
  local order = {}
  local pat = fmt:gsub("%%(%d)%$([sd])", function(d, t) order[#order + 1] = tonumber(d) return t == "d" and "\002" or "\001" end)
  pat = pat:gsub("%%([sd])", function(t) order[#order + 1] = #order + 1 return t == "d" and "\002" or "\001" end)
  pat = pat:gsub("[%^%$%(%)%%%.%[%]%*%+%-%?]", "%%%0")
  -- Functions, not strings: a replacement string reads its own % signs as
  -- capture references, which would turn "%d" into a plain "d".
  pat = pat:gsub("\001", function() return "(.-)" end):gsub("\002", function() return "([%d,%.]+)" end)
  return { pat = "^" .. pat .. (whole and "$" or ""), order = order }
end

local patterns = {}
local function Patterns(key, globals, whole)
  if patterns[key] then return patterns[key] end
  local list = {}
  for _, g in ipairs(globals) do
    if type(_G[g]) == "string" then list[#list + 1] = Pattern(_G[g], whole) end
  end
  patterns[key] = list
  return list
end

-- The arguments of the first pattern a line matches, by position.
local function Parse(msg, list)
  if not Safe(msg) or type(msg) ~= "string" then return nil end
  for _, p in ipairs(list) do
    local caps = { msg:match(p.pat) }
    if #caps >= 1 then
      local args = {}
      for j, idx in ipairs(p.order) do args[idx] = caps[j] end
      return args
    end
  end
end

local function OnSystem(msg)
  -- Both duel lines are written with (winner, loser), in whatever order the language puts them.
  local args = Parse(msg, Patterns("duel", { "DUEL_WINNER_KNOCKOUT", "DUEL_WINNER_RETREAT" }, true))
  if args and args[1] and args[2] and Short(args[1]) == UnitName("player") then A:Signal("duel", Short(args[2])) end
end

---------------------------------------------------------------------------
-- Kills: the experience line, a target seen dying in a fight, a looted corpse
---------------------------------------------------------------------------
local names, nameCount = {}, 0   -- unit id -> name, for corpses looted later
local engaged, counted = {}, {}  -- targets you fought (when), and deaths already counted
local recentXP, recentDeath = {}, {}

local function Remember(unit)
  local ok, g = pcall(UnitGUID, unit)
  local n = UnitName(unit)
  if not (ok and Safe(g) and type(g) == "string" and Safe(n) and type(n) == "string") then return nil end
  if not names[g] then
    nameCount = nameCount + 1
    if nameCount > 400 then names, nameCount = {}, 1 end
  end
  names[g] = n
  return g, n
end

-- The experience line has a name but no guid: settle it against the enemy of
-- that name you fought most recently, so that corpse can't count again later
-- (clicking it to loot targets it, and it reads as a fought enemy, now dead).
local function Settle(n)
  local best, at
  for g, t in pairs(engaged) do
    if names[g] == n and (not at or t > at) then best, at = g, t end
  end
  if best then counted[best], engaged[best] = true, nil end
end

local function OnXP(msg)
  local args = Parse(msg, Patterns("xp", { "COMBATLOG_XPGAIN_FIRSTPERSON" }))
  local n = args and args[1]
  if not n or n == "" then return end
  if recentDeath[n] and GetTime() - recentDeath[n] < 4 then return end   -- seen dying already
  recentXP[n] = GetTime()
  Settle(n)
  A:Signal("kill", n)
end

local function OnHonor(msg)
  local args = Parse(msg, Patterns("honor", { "COMBATLOG_HONORGAIN", "COMBATLOG_HONORGAIN_NO_RANK" }))
  local n = args and args[1]
  if n and n ~= "" then A:Signal("bounty", Short(n)) end
end

-- Your target, in a fight with you, dying: counts when no experience line
-- follows (grey enemies, or once you no longer gain experience). Only a death
-- seen as it happens: a corpse targeted later (to loot it) never counts.
local FRESH = 10   -- seconds since you last saw it alive and fighting
local lookAgain = {}
local function WatchTarget()
  if not UnitExists("target") then return end
  local isPlayer = UnitIsPlayer("target")
  if not Safe(isPlayer) or isPlayer then return end
  local g, n = Remember("target")
  if not g then return end
  local dead = UnitIsDead("target")
  if not Safe(dead) then return end
  if not dead then
    local fighting = UnitAffectingCombat("target")
    local denied = UnitIsTapDenied and UnitIsTapDenied("target")
    if Safe(fighting) and fighting and not (Safe(denied) and denied) then engaged[g] = GetTime() end
    -- At no health the game can say "dead" a moment later: look again then.
    local hp = UnitHealth("target")
    if Safe(hp) and hp == 0 and engaged[g] and not lookAgain[g] then
      lookAgain[g] = true
      C_Timer.After(0.5, function() lookAgain[g] = nil; K.Try("quest auto", WatchTarget) end)
    end
  elseif engaged[g] and not counted[g] and GetTime() - engaged[g] < FRESH then
    counted[g], engaged[g] = true, nil
    C_Timer.After(1.5, function()
      if recentXP[n] and GetTime() - recentXP[n] < 4 then return end
      recentDeath[n] = GetTime()
      A:Signal("kill", n, g)
    end)
  end
end

local function OnLoot()
  if not (GetLootSourceInfo and GetNumLootItems) then return end
  local seen = {}
  for slot = 1, GetNumLootItems() do
    local src = { pcall(GetLootSourceInfo, slot) }
    if src[1] then
      for j = 2, #src, 2 do
        local g = src[j]
        if Safe(g) and type(g) == "string" and not seen[g] then
          seen[g] = true
          local n = names[g]
          if not n and UnitGUID("target") == g then n = UnitName("target") end
          if n and Safe(n) then A:Signal("loot", n, g) end
        end
      end
    end
  end
end

-- The chat-line readers, for the developers' test addon (KinshipRP_Tests) to
-- feed the game's own lines through. Nothing in Kinship uses this table.
A.Hooks = { OnXP = OnXP, OnHonor = OnHonor, OnSystem = OnSystem, OnLoot = OnLoot, WatchTarget = WatchTarget }

---------------------------------------------------------------------------
-- Watching
---------------------------------------------------------------------------
local tick = CreateFrame("Frame")
tick.t, tick.n = 0, 0
tick:SetScript("OnUpdate", function(self, elapsed)
  self.t = self.t + elapsed
  if self.t < 1 then return end
  self.t = 0
  if InCombatLockdown() then return end
  K.Try("quest auto", A.Check, A)
  -- Holds, watches and time limits count: redraw the tracker every few seconds.
  self.n = self.n + 1
  if live and self.n % 5 == 0 then K:Fire("QUEST_TICK") end
end)

local ev = CreateFrame("Frame")
for _, name in ipairs({ "PLAYER_TARGET_CHANGED", "BAG_UPDATE_DELAYED", "PLAYER_EQUIPMENT_CHANGED", "GROUP_ROSTER_UPDATE",
  "ZONE_CHANGED", "ZONE_CHANGED_INDOORS", "ZONE_CHANGED_NEW_AREA", "PLAYER_DEAD", "CHAT_MSG_SYSTEM",
  "CHAT_MSG_COMBAT_XP_GAIN", "CHAT_MSG_COMBAT_HONOR_GAIN", "LOOT_OPENED", "UPDATE_MOUSEOVER_UNIT", "NAME_PLATE_UNIT_ADDED" }) do
  pcall(ev.RegisterEvent, ev, name)
end
if not pcall(ev.RegisterUnitEvent, ev, "UNIT_HEALTH", "target") then pcall(ev.RegisterEvent, ev, "UNIT_HEALTH") end
ev:SetScript("OnEvent", function(_, event, ...)
  if event == "PLAYER_DEAD" then K.Try("quest auto", A.OnDeath, A)
  elseif event == "CHAT_MSG_SYSTEM" then K.Try("quest auto", OnSystem, ...)
  elseif event == "CHAT_MSG_COMBAT_XP_GAIN" then K.Try("quest auto", OnXP, ...)
  elseif event == "CHAT_MSG_COMBAT_HONOR_GAIN" then K.Try("quest auto", OnHonor, ...)
  elseif event == "LOOT_OPENED" then K.Try("quest auto", OnLoot)
  elseif event == "UNIT_HEALTH" then
    if ... == "target" then K.Try("quest auto", WatchTarget) end
  elseif event == "UPDATE_MOUSEOVER_UNIT" then K.Try("quest auto", Remember, "mouseover")
  elseif event == "NAME_PLATE_UNIT_ADDED" then K.Try("quest auto", Remember, ...)
  else
    if event == "PLAYER_TARGET_CHANGED" then K.Try("quest auto", WatchTarget) end
    K.Try("quest auto", A.Check, A)
    if event == "BAG_UPDATE_DELAYED" then K:Fire("QUEST_TICK") end   -- gathering counts move
  end
end)
for _, e in ipairs({ "INVENTORY", "AURAS", "STASHES", "PROFILE" }) do K:On(e, function() K.Try("quest auto", A.Check, A) end) end
K:On("INVENTORY", function() K:Fire("QUEST_TICK") end)

K:On("LOGIN", function()
  local function OnEmote(token) if type(token) == "string" then K.Try("quest auto", A.Signal, A, "emote", token:upper()) end end
  if DoEmote then pcall(hooksecurefunc, "DoEmote", OnEmote) end
  if C_ChatInfo and C_ChatInfo.PerformEmote then pcall(hooksecurefunc, C_ChatInfo, "PerformEmote", OnEmote) end
  if K.Documents and K.Documents.Open then
    hooksecurefunc(K.Documents, "Open", function(_, id) K.Try("quest auto", A.Signal, A, "read", id) end)
  end
end)

---------------------------------------------------------------------------
-- Answering a riddle or giving a password
---------------------------------------------------------------------------
local function BuildAsker()
  local m = UI.Modal(UIParent, 380, 224, function() A.asker:Hide() end)
  A.asker = m
  m:SetFrameStrata("DIALOG")
  local card = m.card
  m.head = UI.Section(card, "Your answer")
  m.head:SetPoint("TOPLEFT", 21, -15)
  m.q = UI.Text(card, "", "Body", "text", 340)
  m.q:SetPoint("TOPLEFT", 20, -42)
  m.q:SetSpacing(2)
  m.edit = UI.Edit(card, 340, 26, nil, 80)
  m.edit:SetPoint("BOTTOMLEFT", 20, 56)
  m.msg = UI.Text(card, "", "Small", "subtle", 230)
  m.msg:SetPoint("BOTTOMLEFT", 20, 22)
  m.ok = UI.Button(card, "Answer", 96, 26)
  m.ok:SetPoint("BOTTOMRIGHT", -16, 14)
  local function Go()
    local done, msg, out = A:Answer(m.id, m.i, m.edit:GetText())
    if done then m:Hide() return end
    if msg then m.msg:SetText("|cff" .. UI.CardHex(RED) .. msg .. "|r") end
    m.edit:SetText("")
    if out then C_Timer.After(1.2, function() m:Hide() end) else m.edit:SetFocus() end
  end
  m.ok:SetScript("OnClick", Go)
  m.edit:SetScript("OnEnterPressed", Go)
  m.edit:SetScript("OnEscapePressed", function() m:Hide() end)
  return m
end

function A:Ask(id, i)
  local e, o = Find(id, i)
  if not (o and o.auto) or not A.Watching(e, i) then return end
  local m = self.asker or BuildAsker()
  m.id, m.i = id, i
  local pass = o.auto.k == "pass"
  m.head:SetText(pass and "The password" or "Your answer")
  m.ok:SetText(pass and "Speak it" or "Answer")
  m.q:SetText(pass and UI.Clean(o.text) or ("\"" .. UI.Escape(o.auto.q) .. "\""))
  m.msg:SetText(UI.Clean(e.title))
  m.edit:SetText("")
  m:Show()
  m.edit:SetFocus()
end

---------------------------------------------------------------------------
-- The rule editor (a pop-over on the quest editor): the rule, its
-- "and also" conditions, and the objective's options, on three tabs.
---------------------------------------------------------------------------
local EW, EH = 480, 432
local EIW = EW - 40
local HW = (EIW - 12) / 2

local function BuildEditor(parent)
  -- Over the whole journal: it's taller than the Write tab.
  local m = UI.Modal((K.Journal and K.Journal.frame) or parent, EW, EH, function() A.editor:Hide() end)
  A.editor = m
  m.draft, m.opts = {}, {}   -- the widgets read these as they're built
  local card = m.card
  m.head = UI.Section(card, "Completes when...")
  m.head:SetPoint("TOPLEFT", 21, -15)
  m.obj = UI.Text(card, "", "Small", "subtle", EIW - 30)
  m.obj:SetPoint("TOPLEFT", 20, -40)
  m.obj:SetWordWrap(false)

  m.tabs = UI.Segments(card, {
    { key = "rule", label = "The rule" }, { key = "also", label = "And also" }, { key = "opts", label = "Options" },
  }, 110, function(key) m.tab = key; m:Paint() end)
  m.tabs:SetPoint("TOPLEFT", 20, -60)

  -- Where a value lives: "x" on the rule, "w.x" its conditions, "o.x" the objective, "f.x" how it fails.
  local function Slot(key, make)
    local space, k = key:match("^(%a)%.(%w+)$")
    if not space then return m.draft, key end
    if space == "o" then return m.opts, k end
    if space == "w" then
      if make then m.draft.w = m.draft.w or {} end
      return m.draft.w, k
    end
    if make then m.opts.fl = m.opts.fl or {} end
    return m.opts.fl, k
  end
  local function Get(key) local t, k = Slot(key); return t and t[k] end
  local function Put(key, v) local t, k = Slot(key, true); t[k] = v end

  local function Field(p, label, x, y, w, max, key, numeric)
    local f = UI.Field(p, label, w, max, function(v)
      if numeric then Put(key, tonumber(v)) else Put(key, v ~= "" and v or nil) end
    end)
    f:SetPoint("TOPLEFT", x, y)
    if numeric then f.edit:SetNumeric(true) end
    f.key = key
    p.fields = p.fields or {}
    p.fields[#p.fields + 1] = f
    return f
  end
  local function Note(p, text, y)
    local n = UI.Text(p, text, "Small", "subtle", EIW)
    n:SetPoint("TOPLEFT", 1, y)
    n:SetSpacing(2)
    return n
  end
  local function Toggle(p, label, key, x, y, w)
    local t = UI.Toggle(p, label, nil, function() return Get(key) and true or false end,
      function(v) Put(key, v or nil); m:Paint() end, w or EIW, true)
    t:SetPoint("TOPLEFT", x or 0, y)
    p.toggles = p.toggles or {}
    p.toggles[#p.toggles + 1] = t
    return t
  end
  -- A button that opens a list. none: a label for "no choice" (for optional conditions);
  -- labelFor(id): the button's text for a choice, when keyName doesn't hold it.
  local function Picker(p, label, x, y, w, list, keyId, keyName, none, labelFor)
    local l = UI.Text(p, label, "Label", "subtle")
    l:SetPoint("TOPLEFT", x + 1, y)
    local b = UI.Button(p, "", w, 24)
    b:SetPoint("TOPLEFT", x, y - 14)
    b:SetScript("OnClick", function(self)
      UI.Menu(self, function(root)
        root:CreateTitle(label)
        if none then root:CreateButton(none, function() Put(keyId, nil); if keyName then Put(keyName, nil) end; m:Paint() end) end
        local items = list()
        if #items == 0 then root:CreateTitle("Nothing to choose yet") end
        for _, it in ipairs(items) do
          root:CreateButton(it.label, function() Put(keyId, it.id); if keyName then Put(keyName, it.label) end; m:Paint() end)
        end
      end)
    end)
    b.keyId, b.keyName, b.none, b.labelFor = keyId, keyName, none, labelFor
    b.caption = l
    p.pickers = p.pickers or {}
    p.pickers[#p.pickers + 1] = b
    return b
  end
  local function KinItems()
    local out = {}
    for _, d in ipairs(K.Items and K.Items:Designs() or {}) do out[#out + 1] = { id = d.id, label = d.name } end
    return out
  end
  local function Effects()
    local out = {}
    for _, d in ipairs(K.Auras and K.Auras:Library("all") or {}) do out[#out + 1] = { id = d.id, label = d.name } end
    return out
  end

  -- The rule tab ---------------------------------------------------------
  m.kind = UI.Button(card, "", 240, 26)
  m.kind:SetPoint("TOPLEFT", 20, -96)
  m.kind:SetScript("OnClick", function(self)
    UI.Menu(self, function(root)
      root:CreateTitle("How it completes")
      root:CreateRadio("Ticked by hand", function() return m.draft.k == nil end, function() m:SetKind(nil) end)
      for _, k in ipairs(A.ORDER) do
        root:CreateRadio(A.KINDS[k].label, function() return m.draft.k == k end, function() m:SetKind(k) end)
      end
    end)
  end)
  -- A new kind keeps the conditions (and holding or counting, where the new kind has them).
  function m:SetKind(k)
    local d = self.draft
    self.draft = { k = k, w = d.w, hold = A.HOLDS[k] and d.hold or nil, times = A.COUNTS[k] and d.times or nil }
    self:Paint()
  end

  local area = CreateFrame("Frame", nil, card)
  area:SetPoint("TOPLEFT", 20, -134)
  area:SetSize(EIW, EH - 134 - 50)
  m.area = area
  m.panels = {}
  local function Panel(k)
    local p = CreateFrame("Frame", nil, area)
    p:SetAllPoints()
    p:Hide()
    m.panels[k] = p
    return p
  end

  local p = Panel("place")
  m.placeNote = Note(p, "", 0)
  p = Panel("zone")
  Field(p, "The place's name (a zone or subzone)", 0, 0, EIW - 132, 60, "n")
  local here = UI.Button(p, "Where I am", 120, 24)
  here:SetPoint("TOPLEFT", EIW - 120, -14)
  here:SetScript("OnClick", function()
    local z = GetSubZoneText and GetSubZoneText() or ""
    if not Safe(z) or z == "" then z = GetZoneText and GetZoneText() or "" end
    if Safe(z) and z ~= "" then m.draft.n = z; m:Paint() end
  end)
  Note(p, "Completes when the name on their minimap (or the zone's) matches. Exact names work best: \"Lion's Pride Inn\".", -50)
  p = Panel("watch")
  Field(p, "Minutes at the pin", 0, 0, 140, 3, "m", true)
  Toggle(p, "Leaving starts the clock again", "strict", 0, -50)
  m.watchNote = Note(p, "", -84)
  p = Panel("talk")
  Field(p, "Their name (an NPC or a player)", 0, 0, EIW, 60, "n")
  Toggle(p, "Only when they're close by", "near", 0, -50)
  Note(p, "Completes when they target someone with that name.", -84)
  p = Panel("emote")
  Picker(p, "The emote", 0, 0, EIW, function()
    local out = {}
    for _, e in ipairs(A.EMOTES) do out[#out + 1] = { id = e, label = "/" .. e:lower() } end
    return out
  end, "e")
  Field(p, "At (optional: a name to target)", 0, -48, EIW, 60, "n")
  p = Panel("item")
  Picker(p, "Which Kinship item", 0, 0, EIW, KinItems, "d", "nm")
  Field(p, "How many", 0, -48, 80, 2, "c", true)
  Toggle(p, "Handed over when the quest is done", "take", 0, -96)
  Note(p, "Design items in Inventory > Workshop, and give them out before the quest.", -128)
  p = Panel("gather")
  Field(p, "Game item: its ID number (from a database site, or an item link)", 0, 0, EIW, 140, "i")
  Field(p, "How many", 0, -48, 80, 3, "c", true)
  m.gatherName = Note(p, "", -96)
  p = Panel("wear")
  Field(p, "Game item: its ID number (or an item link)", 0, 0, EIW, 140, "i")
  m.wearName = Note(p, "", -50)
  p = Panel("stash")
  Field(p, "The stash's name (or part of it)", 0, 0, EIW, 40, "n")
  Note(p, "Completes when they search the area and turn up a stash with that name. To need several, set how many on And also.", -50)
  p = Panel("dice")
  Field(p, "Dice", 0, 0, 140, 24, "x")
  Field(p, "At least", 156, 0, 90, 4, "at", true)
  Field(p, "Tries (0 for any)", 262, 0, 120, 2, "tries", true)
  Note(p, "They get a Roll button on the objective. Rolls are shared as usual.", -50)
  p = Panel("riddle")
  Field(p, "The riddle, as they'll see it", 0, 0, EIW, 200, "q")
  Field(p, "The answer (more than one? separate them with /)", 0, -48, EIW - 136, 120, "ans")
  Field(p, "Tries (0 for any)", EIW - 120, -48, 120, 2, "tries", true)
  m.riddleNote = Note(p, "", -98)
  p = Panel("pass")
  Field(p, "The password (more than one? separate them with /)", 0, 0, EIW - 136, 120, "ans")
  Field(p, "Tries (0 for any)", EIW - 120, 0, 120, 2, "tries", true)
  m.passNote = Note(p, "", -50)
  p = Panel("duel")
  Field(p, "Against (a name; leave it blank for anyone)", 0, 0, EIW, 60, "n")
  Note(p, "Completes when they win a duel, by knockout or when the other side flees. To need several wins, set how many on And also.", -50)
  p = Panel("kill")
  Field(p, "Their name, or part of it (\"Defias\" counts every Defias)", 0, 0, EIW - 106, 60, "n")
  Field(p, "How many", EIW - 90, 0, 90, 2, "times", true)
  Toggle(p, "Only ones they loot", "loot", 0, -50)
  Note(p, "Counts from the game's \"dies, you gain experience\" line, kills in a group included. Enemies that give no experience "
    .. "count when they're the target and die in a fight with them. \"Only ones they loot\" counts each corpse once, at any level.", -84)
  p = Panel("bounty")
  Field(p, "Who (a player's name; leave it blank for anyone)", 0, 0, EIW - 106, 60, "n")
  Field(p, "How many", EIW - 90, 0, 90, 2, "times", true)
  Note(p, "Counts honourable kills, from the game's \"dies (Honorable Kill)\" line. Kills that give no honour (an enemy far below "
    .. "their level, or killed too often) don't count. Add \"At the pin\" on And also for a battle in one place.", -50)
  p = Panel("effect")
  Picker(p, "Which effect", 0, 0, EIW, Effects, "a", "nm")
  Toggle(p, "When they shake it off (not when they take it on)", "lose", 0, -48)
  p = Panel("read")
  Picker(p, "Which document", 0, 0, EIW, function()
    local out = {}
    local D = K.Documents
    for _, doc in ipairs(D and D:List() or {}) do
      if D:IsMine(doc.id) then out[#out + 1] = { id = doc.id, label = D.Title(doc) } end
    end
    return out
  end, "d", "nm")
  Note(p, "Attach the document to a Kinship item so they can open it.", -48)
  p = Panel("time")
  Field(p, "From hour (0-23)", 0, 0, 130, 2, "h1", true)
  Field(p, "Until hour (0-23)", 146, 0, 130, 2, "h2", true)
  Note(p, "Server time, as the clock on your minimap shows it. Give the objective a map pin and they must be there too.", -50)

  m.none = Note(area, "Ticked by hand: by the storyteller, or by the player on quests without storyteller mode. "
    .. "The Options tab still works: optional, hidden, and how it can fail.", 0)

  -- The "and also" tab ---------------------------------------------------
  local also = CreateFrame("Frame", nil, card)
  also:SetPoint("TOPLEFT", 20, -98)
  also:SetSize(EIW, EH - 98 - 50)
  m.alsoPanel = also
  local body = CreateFrame("Frame", nil, also)
  body:SetAllPoints()
  m.alsoBody = body
  Toggle(body, "At the pin", "w.pin", 0, 0, 136)
  Toggle(body, "In character", "w.ic", 150, 0, 136)
  Toggle(body, "In a group", "w.grp", 300, 0, EIW - 300)
  Field(body, "From hour", 0, -34, 100, 2, "w.h1", true)
  Field(body, "Until hour", 112, -34, 100, 2, "w.h2", true)
  Field(body, "With someone close by (their name)", HW + 12, -34, HW, 60, "w.pn")
  Picker(body, "Carrying a Kinship item", 0, -84, HW, KinItems, "w.cd", "w.cnm", "Nothing in particular")
  Picker(body, "Under an effect", HW + 12, -84, HW, Effects, "w.fa", "w.fnm", "No effect needed")
  Field(body, "Wearing a game item (its ID or a link)", 0, -134, HW, 140, "w.wi")
  m.holdField = Field(body, "Keep it up for (seconds)", HW + 12, -134, HW, 4, "hold", true)
  m.timesField = Field(body, "How many times", HW + 12, -134, HW, 2, "times", true)
  m.alsoNote = Note(body, "", -184)
  m.alsoNone = Note(also, "Choose a rule first (on The rule tab). These add to it: \"/kneel, at the shrine, after dark\".", 0)

  -- The options tab ------------------------------------------------------
  local opts = CreateFrame("Frame", nil, card)
  opts:SetPoint("TOPLEFT", 20, -98)
  opts:SetSize(EIW, EH - 98 - 50)
  m.optsPanel = opts
  Toggle(opts, "Optional: a bonus, not needed to finish the quest", "o.opt", 0, 0)
  Toggle(opts, "Hidden: players see it only once it's done", "o.hid", 0, -28)
  local fails = UI.Text(opts, "Fails if...", "Label", "subtle")
  fails:SetPoint("TOPLEFT", 1, -62)
  Toggle(opts, "They die", "f.die", 0, -80, HW)
  Toggle(opts, "They leave the pin's area", "f.out", HW + 12, -80, HW)
  Field(opts, "Time limit (minutes; blank for none)", 0, -108, HW, 4, "f.mins", true)
  local function OutcomeLabel(id)
    for _, it in ipairs(A.OUTCOMES) do if it.id == id then return it.label end end
    return HOLD_LABEL
  end
  Picker(opts, "When it fails", 0, -158, HW, function() return A.OUTCOMES end, "f.th", nil, HOLD_LABEL, OutcomeLabel)
  m.retryToggle = Toggle(opts, "They can try again", "f.retry", HW + 12, -172, HW)
  m.altPicker = Picker(opts, "Which objective opens", HW + 12, -158, HW, function()
    local out = {}
    for _, it in ipairs(m.objective and m.objective.others and m.objective.others() or {}) do
      if it.index > (m.objective.index or 0) then out[#out + 1] = { id = it.index, label = ("%d: %s"):format(it.index, it.text) } end
    end
    return out
  end, "f.alt", nil, nil, function(id)
    for _, it in ipairs(m.objective and m.objective.others and m.objective.others() or {}) do
      if it.index == id then return ("%d: %s"):format(it.index, it.text) end
    end
    return "Objective " .. tostring(id)
  end)
  Picker(opts, "And it leaves them with", 0, -204, HW, Effects, "f.fx", "f.fxn", "Nothing lasting")
  m.optsNote = Note(opts, "", -252)

  m.save = UI.Button(card, "Save", 96, 26)
  m.save:SetPoint("BOTTOMRIGHT", -16, 14)
  m.cancel = UI.Button(card, "Cancel", 80, 26)
  m.cancel:SetPoint("RIGHT", m.save, "LEFT", -8, 0)
  m.cancel:SetScript("OnClick", function() m:Hide() end)
  m.err = UI.Text(card, "", "Small", "subtle", 270)
  m.err:SetPoint("BOTTOMLEFT", 20, 22)
  local function Err(text) m.err:SetText("|cffc0473a" .. text .. "|r") end
  local function HasPin() return m.objective and m.objective.marker ~= nil end

  m.save:SetScript("OnClick", function()
    local opt, hid, fl = A.Options(m.opts)
    local options = { opt = opt, hid = hid, fl = fl }
    if fl and fl.out and not HasPin() then Err("\"They leave the pin's area\" needs a map pin on this objective.") return end
    if m.opts.fl and m.opts.fl.th == "open" and not (fl and fl.alt) then Err("Choose which objective opens (a later one).") return end
    local d = m.draft
    if not d.k then m.set(nil, options); m:Hide() return end
    if d.k == "gather" or d.k == "wear" then d.i = ItemId(d.i) end
    if d.k == "wear" and d.i then d.nm = GameItemName(d.i) or d.nm end
    if d.w then
      d.w.wi = ItemId(d.w.wi)
      if d.w.wi then d.w.wnm = GameItemName(d.w.wi) or d.w.wnm end
      if (d.w.h1 ~= nil) ~= (d.w.h2 ~= nil) then Err("Give both hours, or neither.") return end
      if d.w.pin and not HasPin() then Err("\"At the pin\" needs a map pin on this objective.") return end
    end
    if (d.k == "watch" or d.k == "place") and not HasPin() then Err("This rule needs a map pin on this objective.") return end
    if (d.k == "riddle" or d.k == "pass") and d.ans and A.Normal(d.ans) ~= "" then d.h = A.HashList(d.ans) end
    if (d.k == "riddle" or d.k == "pass") and not d.h then Err("Give the answer.") return end
    local clean = A.Sanitize(d)
    if not clean then Err("Something's missing or not quite right.") return end
    m.set(clean, options)
    m:Hide()
  end)

  local function Fill(panel)
    for _, f in ipairs(panel.fields or {}) do
      local v = Get(f.key)
      if not f.edit:HasFocus() then f.edit:SetText(v ~= nil and tostring(v) or "") end
    end
    for _, t in ipairs(panel.toggles or {}) do t:Refresh() end
    for _, b in ipairs(panel.pickers or {}) do
      local id = Get(b.keyId)
      b:SetText(id and ((b.keyName and Get(b.keyName)) or (b.labelFor and b.labelFor(id))
        or (b.keyId == "e" and ("/" .. id:lower())) or tostring(id)) or b.none or "Choose...")
    end
  end

  function m:Paint()
    local tab = self.tab or "rule"
    local k = self.draft.k
    self.tabs:Select(tab)
    self.err:SetText("")
    self.kind:SetShown(tab == "rule")
    self.area:SetShown(tab == "rule")
    self.alsoPanel:SetShown(tab == "also")
    self.optsPanel:SetShown(tab == "opts")
    self.kind:SetText(k and A.KINDS[k].label or "Ticked by hand")
    self.none:SetShown(k == nil)
    for kk, panel in pairs(self.panels) do
      panel:SetShown(kk == k)
      if kk == k then Fill(panel) end
    end
    if k == "place" or k == "watch" then
      local note = k == "place" and self.placeNote or self.watchNote
      note:SetText(HasPin()
        and ((k == "place" and "Completes when they reach this objective's pin: " or "Time spent at this objective's pin adds up: ")
          .. (K.QuestMarkers.Label(self.objective.marker) or "") .. ". The pin's area counts; an exact spot allows " .. HERE .. " yards.")
        or "|cffc0473aGive this objective a map pin first|r (the pin button beside it).")
    elseif k == "gather" or k == "wear" then
      local id = ItemId(self.draft.i)
      local name = id and GameItemName(id)
      local note = k == "gather" and self.gatherName or self.wearName
      note:SetText(id and (name and ("That's: " .. name) or "That ID isn't known to your game yet.") or "")
    elseif k == "riddle" or k == "pass" then
      local saved = self.draft.h ~= nil
      local note = k == "riddle" and self.riddleNote or self.passNote
      note:SetText(
        (saved and "An answer is saved. Leave it blank to keep it, or type a new one. " or "")
        .. "It's stored scrambled, so it isn't in the quest's text. Capitals, punctuation and a leading \"the\" don't matter."
        .. (k == "pass" and " Tell them the password in roleplay; they type it into the objective." or ""))
    end

    if tab == "also" then
      self.alsoBody:SetShown(k ~= nil)
      self.alsoNone:SetShown(k == nil)
      if k then
        Fill(self.alsoBody)
        self.holdField:SetShown(A.HOLDS[k] and true or false)
        self.timesField:SetShown(A.COUNTS[k] and not OWN_COUNT[k] and true or false)
        local w = self.draft.w or {}
        self.alsoNote:SetText((w.pin and not HasPin()) and "|cffc0473a\"At the pin\" needs a map pin on this objective.|r"
          or ("Everything set here must also be true when the rule is met."
            .. (A.HOLDS[k] and " Keep it up: it must stay true that long." or "")
            .. (A.COUNTS[k] and not OWN_COUNT[k] and " How many times: each one counts." or "")
            .. (k == "watch" and " Keeping watch already takes time; the conditions must hold while the clock runs." or "")))
      end
    elseif tab == "opts" then
      Fill(self.optsPanel)
      local th = self.opts.fl and self.opts.fl.th
      self.retryToggle:SetShown(th == nil)
      self.altPicker:SetShown(th == "open")
      self.altPicker.caption:SetShown(th == "open")
      local what = ({
        carry = "The objective is marked failed but counts as dealt with, and the quest goes on.",
        open = "The objective you choose waits unseen, and opens only if this one fails. Players never learn of it otherwise.",
        quest = "The whole quest ends as failed, in their journal and chronicle.",
      })[th] or "It holds up the quest until they try again, or you tick it yourself."
      self.optsNote:SetText("Dice and riddles with limited tries fail when the tries run out. " .. what
        .. " Time runs from when the objective opens, and keeps running while they're away.")
    end
  end
  return m
end

-- Edit an objective's rule and options. objective: the draft objective (for
-- its pin); get() returns its rule and its options { opt, hid, fl };
-- set(rule or nil, options) stores them.
function A:Edit(parent, objective, title, get, set)
  local m = self.editor or BuildEditor(parent)
  m.objective, m.set = objective, set
  local cur, opts = get()
  m.draft = cur and CopyTable(cur) or {}
  m.opts = opts and CopyTable(opts) or {}
  m.tab = "rule"
  m.obj:SetText(title or "")
  m:Paint()
  m:Show()
end
