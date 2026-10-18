-- Kinship RP: Warfront. Rivals and battle records for RP-PvP.
--
-- The full combat log isn't open to addons on this client, so battles are
-- pieced together from what is:
--   * enemy players you target or mouse over (sightings),
--   * honourable-kill and duel messages (victories and defeats),
--   * a prompt after you die, naming the enemy you were last facing,
--   * clashes you log by hand (emote-and-dice fights never touch the log).
-- Everything here is private to you: nothing is sent to anyone.

local ADDON, ns = ...
local K = ns.K
local UI = K.UI
local Safe = K.Safe
local W = {}
K.War = W

W.GRUDGES = {
  { key = "respect", label = "Respect", color = { 0.55, 0.74, 0.86 } },
  { key = "rival",   label = "Rival",   color = { 0.95, 0.76, 0.36 } },
  { key = "grudge",  label = "Grudge",  color = { 0.93, 0.52, 0.26 } },
  { key = "nemesis", label = "Nemesis", color = { 0.90, 0.30, 0.28 } },
}
W.OUTCOMES = {
  win    = { label = "Victory", color = { 0.42, 0.82, 0.50 }, verb = "Victory over %s" },
  loss   = { label = "Defeat",  color = { 0.90, 0.36, 0.30 }, verb = "Fell to %s" },
  draw   = { label = "Draw",    color = { 0.80, 0.80, 0.80 }, verb = "Fought %s to a standstill" },
  parley = { label = "Parley",  color = { 0.55, 0.74, 0.86 }, verb = "Parleyed with %s" },
}

local LOG_MAX, RECENT_WINDOW = 30, 40

function W.Grudge(key)
  for _, g in ipairs(W.GRUDGES) do if g.key == key then return g end end
end

---------------------------------------------------------------------------
-- Data
---------------------------------------------------------------------------
-- rival = { name, class, race, level, guild, faction, enemy,
--           wins, losses, draws, parleys, sightings, grudge, note,
--           first = { t, place }, last = { t, place }, seen = t,
--           log = { { t = time, o = outcome, place, how }, ... } newest first }

function K:Rivals()
  local key = self:CharKey()
  self.db.rivals[key] = self.db.rivals[key] or {}
  return self.db.rivals[key]
end

function W:Get(name, create)
  local key = K.NameKey(name)
  if not key then return nil end
  local list = K:Rivals()
  local r = list[key]
  if not r and create then
    local place = K:CurrentPlace()
    r = { name = name, wins = 0, losses = 0, draws = 0, parleys = 0, sightings = 0,
          first = { t = time(), place = place }, log = {} }
    list[key] = r
  end
  return r, key
end

function W:IsRival(r)
  return r and ((r.wins or 0) + (r.losses or 0) + (r.draws or 0) + (r.parleys or 0) > 0 or r.grudge or (r.note or "") ~= "")
end

local Short = K.Short

-- Learn what we can about a player from a live unit.
local function UnitInfo(unit)
  local info = {}
  local _, class = UnitClass(unit)
  if Safe(class) then info.class = class end
  local race = UnitRace(unit)
  if Safe(race) then info.race = race end
  local level = UnitLevel(unit)
  if Safe(level) and level and level > 0 then info.level = level end
  local guild = GetGuildInfo(unit)
  if Safe(guild) and guild then info.guild = guild end
  local faction = UnitFactionGroup(unit)
  if Safe(faction) then info.faction = faction end
  local enemy = UnitIsEnemy("player", unit)
  if Safe(enemy) then info.enemy = enemy and true or false end
  return info
end

local function Absorb(r, info)
  if not info then return end
  for _, k in ipairs({ "class", "race", "level", "guild", "faction" }) do
    if info[k] ~= nil then r[k] = info[k] end
  end
  if info.enemy ~= nil then r.enemy = info.enemy end
end

function W:Tally(r) return ("%d : %d"):format(r.wins or 0, r.losses or 0) end

-- Record a clash. outcome: win | loss | draw | parley; how: a few words.
function W:Record(name, outcome, how, info, quiet)
  if not name or not W.OUTCOMES[outcome] then return end
  local r = self:Get(name, true)
  if not r then return end
  Absorb(r, info or self.known[K.NameKey(name) or ""])
  local place = K:CurrentPlace()
  local now = time()
  if outcome == "win" then r.wins = (r.wins or 0) + 1
  elseif outcome == "loss" then r.losses = (r.losses or 0) + 1
  elseif outcome == "draw" then r.draws = (r.draws or 0) + 1
  else r.parleys = (r.parleys or 0) + 1 end
  r.last = { t = now, place = place }
  r.log = r.log or {}
  table.insert(r.log, 1, { t = now, o = outcome, place = place, how = how })
  while #r.log > LOG_MAX do table.remove(r.log) end
  if not r.grudge and outcome ~= "parley" then r.grudge = "rival" end

  if outcome ~= "parley" and K.db.settings.warChronicle then
    K:AddEntry("battle", W.OUTCOMES[outcome].verb:format(Short(r.name)), how and ("(" .. how .. ")") or nil, place)
  end
  K:Fire("RIVALS", r)
  if not quiet and outcome ~= "parley" and K.db.settings.warToasts then self:Toast(r, outcome, how) end
  return r
end

function W:Remove(key) K:Rivals()[key] = nil; K:Fire("RIVALS") end

function W:Toast(r, outcome, how)
  local o = W.OUTCOMES[outcome]
  local classCoords = r.class and CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[r.class]
  local who = Short(r.name)
  local cr, cg, cb = UI.ClassColor(r.class)
  local desc = {}
  if r.race or r.class then desc[#desc + 1] = ((r.race or "") .. " " .. (r.class and (LOCALIZED_CLASS_NAMES_MALE and LOCALIZED_CLASS_NAMES_MALE[r.class] or r.class:lower()) or "")):gsub("^%s+", "") end
  desc[#desc + 1] = how or K:CurrentPlace()
  UI.Toast({
    icon = classCoords and "Interface\\WorldStateFrame\\ICONS-CLASSES" or (K.Art("IconDungeon")),
    iconCoords = classCoords and { classCoords[1] + 0.015, classCoords[2] - 0.015, classCoords[3] + 0.015, classCoords[4] - 0.015 } or nil,
    title = ("|cff%s%s|r  ·  |cff%s%s|r"):format(UI.Hex(o.color), o.label, UI.Hex({ cr, cg, cb }), who),
    text = table.concat(desc, "  ·  "),
    big = W:Tally(r),
    color = o.color,
    sound = outcome == "win" and "UI_BATTLEGROUND_COUNTDOWN_FINISHED" or nil,
    onClick = function() W:Open(r) end,
  })
end

function W:Open(r)
  W.focus = r
  K.Journal:Open("warfront")
end

---------------------------------------------------------------------------
-- Sightings: who you've crossed paths with, and who you were last facing.
---------------------------------------------------------------------------
W.known = {}    -- [nameKey] = info from the last time we saw them (this session)
W.recent = {}   -- [nameKey] = { name, t } hostile players seen in the last moments

function W:Sight(unit)
  if not UnitExists(unit) or not UnitIsPlayer(unit) or UnitIsUnit(unit, "player") then return end
  local name = GetUnitName(unit, true)
  if not Safe(name) or not name then return end
  local key = K.NameKey(name)
  if not key then return end
  local info = UnitInfo(unit)
  self.known[key] = info
  if info.enemy then self.recent[key] = { name = name, t = GetTime() } end

  local r = K:Rivals()[key]
  local changed = false
  if not r and info.enemy and K.db.settings.warSightings then r = self:Get(name, true); changed = true end
  if not r then return end
  Absorb(r, info)
  -- Count a sighting at most once every ten minutes.
  if not r.seen or time() - r.seen > 600 then
    r.sightings = (r.sightings or 0) + 1
    r.seenPlace = K:CurrentPlace()
    changed = true
  end
  r.seen = time()
  -- Let an open Warfront page catch up (at most every couple of seconds).
  if changed and (not self.lastFire or GetTime() - self.lastFire > 2) then
    self.lastFire = GetTime()
    K:Fire("RIVALS", r)
  end
end

-- The enemy you were most recently facing (current target first).
function W:LastFoe()
  if UnitExists("target") and UnitIsPlayer("target") then
    local enemy = UnitIsEnemy("player", "target")
    local name = GetUnitName("target", true)
    if Safe(enemy) and enemy and Safe(name) and name then return name end
  end
  local best, bestT
  for _, e in pairs(self.recent) do
    if GetTime() - e.t <= RECENT_WINDOW and (not bestT or e.t > bestT) then best, bestT = e.name, e.t end
  end
  return best
end

-- After dying, offer to record the defeat against whoever you were facing.
local function OnDeath()
  if not K.db.settings.warToasts then return end
  local foe = W:LastFoe()
  if not foe then return end
  local info = W.known[K.NameKey(foe) or ""] or {}
  local cr, cg, cb = UI.ClassColor(info.class)
  UI.Toast({
    icon = K.Art("IconDungeon"),
    title = "You have fallen",
    text = ("Was it |cff%s%s|r who brought you down?"):format(UI.Hex({ cr, cg, cb }), Short(foe)),
    color = W.OUTCOMES.loss.color,
    duration = 25,
    actions = {
      { label = "Not them", fn = function() end },
      { label = "Record defeat", fn = function() W:Record(foe, "loss", "Fell in battle", info) end },
    },
  })
end

---------------------------------------------------------------------------
-- Messages: honourable kills and duel results
---------------------------------------------------------------------------
-- Turn a game format string ("%s dies, ...", "%1$s has defeated %2$s") into a
-- Lua pattern plus the order its captures come back in.
local function Pattern(fmt)
  if type(fmt) ~= "string" or fmt == "" then return nil end
  local order, i = {}, 0
  local s = fmt:gsub("%%(%d)%$([sd])", function(n, t) i = i + 1; order[i] = tonumber(n); return "\001" .. t end)
  s = s:gsub("%%([sd])", function(t) i = i + 1; order[i] = i; return "\001" .. t end)
  s = s:gsub("([%(%)%.%+%-%*%?%[%]%^%$%%])", "%%%1")
  s = s:gsub("\001s", "(.-)")
  s = s:gsub("\001d", "(%%d+)")
  return "^" .. s .. "$", order
end

local function Match(msg, fmt)
  local pat, order = Pattern(fmt)
  if not pat then return nil end
  local caps = { msg:match(pat) }
  if #caps == 0 then return nil end
  local out = {}
  for k, v in ipairs(caps) do out[order[k] or k] = v end
  return out
end

local function IsMe(name)
  return K:IsMe(name)
end

local function OnHonor(msg)
  for _, fmt in ipairs({ _G.COMBATLOG_HONORGAIN, _G.COMBATLOG_HONORGAIN_NO_RANK }) do
    local m = Match(msg, fmt)
    if m and m[1] then
      W:Record(m[1], "win", "Honourable kill")
      return
    end
  end
end

local function OnSystem(msg)
  local m = Match(msg, _G.DUEL_WINNER_KNOCKOUT)
  local how = "Duel"
  if not m then m = Match(msg, _G.DUEL_WINNER_RETREAT); how = "Duel (they fled)" end
  if not m or not m[1] or not m[2] then return end
  local winner, loser = m[1], m[2]
  if IsMe(winner) then W:Record(loser, "win", how)
  elseif IsMe(loser) then W:Record(winner, "loss", how == "Duel" and "Duel" or "Duel (you fled)") end
end

---------------------------------------------------------------------------
-- Housekeeping and start-up
---------------------------------------------------------------------------
-- Sightings nobody fought, noted or marked fade after a month.
local function Prune()
  local cutoff = time() - 30 * 86400
  for key, r in pairs(K:Rivals()) do
    if not W:IsRival(r) and (r.seen or r.first and r.first.t or 0) < cutoff then K:Rivals()[key] = nil end
  end
end

K:On("LOGIN", function()
  Prune()
  local ev = CreateFrame("Frame")
  for _, e in ipairs({ "PLAYER_TARGET_CHANGED", "UPDATE_MOUSEOVER_UNIT", "PLAYER_DEAD",
                       "CHAT_MSG_COMBAT_HONOR_GAIN", "CHAT_MSG_SYSTEM" }) do
    pcall(ev.RegisterEvent, ev, e)
  end
  ev:SetScript("OnEvent", function(_, event, msg)
    if event == "PLAYER_TARGET_CHANGED" then K.Try("warfront", W.Sight, W, "target")
    elseif event == "UPDATE_MOUSEOVER_UNIT" then K.Try("warfront", W.Sight, W, "mouseover")
    elseif event == "PLAYER_DEAD" then K.Try("warfront", OnDeath)
    elseif not Safe(msg) or type(msg) ~= "string" then return
    elseif event == "CHAT_MSG_COMBAT_HONOR_GAIN" then K.Try("warfront", OnHonor, msg)
    elseif event == "CHAT_MSG_SYSTEM" then K.Try("warfront", OnSystem, msg) end
  end)
end)
