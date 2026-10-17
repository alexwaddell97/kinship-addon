-- Kinship RP: effects that come on their own, from things that really
-- happened in the game. Only light ones, and each toast has "Not now" to
-- take it off again. All of them sit behind Settings > Effects that come on
-- their own, and each has its own switch there too.
--   Drunk      the game says you feel tipsy, drunk or smashed; gone when it
--              says you're sober again (if Kinship put it on you)
--   Soaked     a while swimming, then a fair chance of it as you climb out;
--              dries twice as fast at rest
--   Bandaged   a real bandage on you while you have a wound: your wounds
--              heal in half the time from there
--   Hungry     hours of play without eating, then a chance each hour; real
--              food clears it
--   Exhausted  a long stretch without resting, then a chance each hour;
--              rest clears the count (and eases Exhausted itself)
--   Well rested  half an hour's rest (World/Auras.lua)
-- Only time you're playing counts, never time logged out.

local ADDON, ns = ...
local K = ns.K
local A = K.Auras
local AE = {}
K.AutoEffects = AE

local MIN, HOUR = 60, 3600
AE.SWIM_FOR = 90               -- seconds in the water before you might come out soaked
AE.SOAK_CHANCE = 0.5
AE.SOAK_FOR = 15 * MIN
AE.HUNGRY_AFTER = 3 * HOUR     -- played without eating
AE.HUNGRY_CHANCE = 0.4         -- each hour after that
AE.HUNGRY_FOR = 2 * HOUR
AE.TIRED_AFTER = 4 * HOUR      -- played without resting
AE.TIRED_CHANCE = 0.3          -- each hour after that
AE.BANDAGE_FOR = 2 * HOUR
local BANDAGED_SPELL = 11196   -- "Recently Bandaged", on whoever was bandaged
local FOOD = { ["Food"] = true, ["Food & Drink"] = true, ["Well Fed"] = true }

-- The switches, in the order Settings shows them.
AE.LIST = {
  { id = "drunk",     label = "Drunk",       desc = "When the game says you feel tipsy or drunk. Gone when you sober up." },
  { id = "soaked",    label = "Soaked",      desc = "Sometimes, after a good while in the water." },
  { id = "bandaged",  label = "Bandaged",    desc = "A real bandage on a wounded character: wounds heal in half the time." },
  { id = "hungry",    label = "Hungry",      desc = "Sometimes, after three hours without eating. Food clears it." },
  { id = "exhausted", label = "Exhausted",   desc = "Sometimes, after four hours without resting. Rest clears it." },
  { id = "rested",    label = "Well rested", desc = "After half an hour's rest at an inn or in a city." },
}

local function Now() return GetServerTime and GetServerTime() or time() end
local function S() return K.db and K.db.settings or {} end

-- Counters, per character: seconds swimming, unfed and awake.
local function Box()
  local key = K:CharKey()
  local box = K.db.auras[key]
  if type(box) ~= "table" then box = { list = {} }; K.db.auras[key] = box end
  if type(box.auto) ~= "table" then box.auto = {} end
  return box.auto
end

local function InCombat()
  local ok, v = pcall(UnitAffectingCombat, "player")
  return ok and v == true
end

-- A roll for something with `chance` per hour, over `spent` seconds.
local function Roll(chance, spent)
  return math.random() < 1 - (1 - chance) ^ (spent / HOUR)
end

---------------------------------------------------------------------------
-- Drunk
---------------------------------------------------------------------------
function AE:OnSystem(msg)
  if type(msg) ~= "string" then return end
  if msg == DRUNK_MESSAGE_SELF1 then
    local e = A:Find("drunk")
    if e and e.auto then A:Remove(e.key, true) end
    return
  end
  for i = 2, 4 do
    local m = _G["DRUNK_MESSAGE_SELF" .. i]
    if m and msg == m then
      local e = A:Find("drunk")
      if e then
        if e.auto and e.expires then e.expires = math.max(e.expires, Now() + HOUR) end
      else
        A:AutoGive("drunk", HOUR, i == 4 and "Completely smashed. Loud, swaying, and very sure of yourself."
          or "The drink is going to your head.")
      end
      return
    end
  end
end

---------------------------------------------------------------------------
-- Bandaged
---------------------------------------------------------------------------
function AE:Bandaged()
  local wounds = {}
  for _, e in ipairs(A:Mine()) do
    if e.kind == "wound" and e.expires then wounds[#wounds + 1] = e end
  end
  if #wounds == 0 then return false end
  if not A:AutoGive("bandaged", AE.BANDAGE_FOR, "Your wounds are cleaned and dressed. They'll heal in half the time.") then
    return false
  end
  local now = Now()
  for _, e in ipairs(wounds) do
    if e.expires > now then e.expires = now + math.floor((e.expires - now) / 2) end
  end
  K:Fire("AURAS")
  return true
end

local function HasBandage()
  if C_UnitAuras and C_UnitAuras.GetPlayerAuraBySpellID then
    local ok, a = pcall(C_UnitAuras.GetPlayerAuraBySpellID, BANDAGED_SPELL)
    return ok and a ~= nil
  end
  return false
end

local function Eating()
  if not (C_UnitAuras and C_UnitAuras.GetAuraDataByIndex) then return false end
  for i = 1, 40 do
    local ok, a = pcall(C_UnitAuras.GetAuraDataByIndex, "player", i, "HELPFUL")
    if not ok or not a then break end
    if K.Safe(a.name) and FOOD[a.name] then return true end
  end
  return false
end

-- Food clears hunger, and restarts the count.
function AE:Ate()
  Box().unfed = 0
  local e = A:Find("hungry")
  if e then A:Remove(e.key, true) end
end

-- Well rested (World/Auras.lua) clears the count towards exhaustion.
function AE:Rested() Box().awake = 0 end

local wasBandaged, wasEating
function AE:OnAura()
  local band, eat = HasBandage(), Eating()
  if band and not wasBandaged and A.AutoOn("bandaged") then K.Try("auto effects", AE.Bandaged, AE) end
  if eat and not wasEating then self:Ate() end
  wasBandaged, wasEating = band, eat
end

---------------------------------------------------------------------------
-- Time: swimming, going without food, going without rest
---------------------------------------------------------------------------
-- One tick: `spent` seconds, and whether you're swimming and resting.
function AE:Tick(spent, swimming, resting)
  local b = Box()
  -- Soaked, as you leave the water
  if swimming then
    b.swim = (b.swim or 0) + spent
  elseif (b.swim or 0) > 0 then
    local long = b.swim >= AE.SWIM_FOR
    b.swim = 0
    if long and math.random() < AE.SOAK_CHANCE then
      A:AutoGive("soaked", AE.SOAK_FOR, "Drenched to the bone and dripping. Rest at an inn or in town to dry off sooner.")
    end
  end
  -- Hungry
  b.unfed = (b.unfed or 0) + spent
  if b.unfed >= AE.HUNGRY_AFTER and not A:Find("hungry") and not InCombat() and Roll(AE.HUNGRY_CHANCE, spent) then
    A:AutoGive("hungry", AE.HUNGRY_FOR, "Your stomach's growling. Something to eat would fix it.")
  end
  -- Exhausted: rest takes the count down three times as fast as it builds
  if resting then
    b.awake = math.max(0, (b.awake or 0) - 3 * spent)
  else
    b.awake = (b.awake or 0) + spent
    if b.awake >= AE.TIRED_AFTER and not A:Find("exhausted") and not A:Find("rested") and not InCombat()
      and Roll(AE.TIRED_CHANCE, spent) then
      A:AutoGive("exhausted", HOUR, "You've been on your feet too long. Rest at an inn or in a city.")
    end
  end
end

local lastTick
local function OnTick()
  if not (K.db and K:ExtOn("auras")) then return end
  local now = Now()
  local was = lastTick
  lastTick = now
  if not was then return end
  local spent = math.min(now - was, 30)
  if spent <= 0 then return end
  local swimming = IsSwimming and IsSwimming() and true or false
  AE:Tick(spent, swimming, A.Resting())
end

---------------------------------------------------------------------------
-- Start-up and settings
---------------------------------------------------------------------------
local ev = CreateFrame("Frame")
ev:SetScript("OnEvent", function(_, event, a)
  if event == "CHAT_MSG_SYSTEM" then K.Try("auto effects", AE.OnSystem, AE, a)
  elseif event == "UNIT_AURA" then K.Try("auto effects", AE.OnAura, AE) end
end)

K:On("LOGIN", function()
  if not K:ExtOn("auras") then return end
  Box()
  wasBandaged, wasEating = HasBandage(), Eating()
  ev:RegisterEvent("CHAT_MSG_SYSTEM")
  if not pcall(ev.RegisterUnitEvent, ev, "UNIT_AURA", "player") then ev:RegisterEvent("UNIT_AURA") end
  C_Timer.NewTicker(5, function() K.Try("auto effects", OnTick) end)
end)

K:RegisterSettings({ id = "autoEffects", title = "Effects that come on their own", order = 17,
  shown = function() return K:ExtOn("auras") end, build = function(card)
  card:Toggle("Let effects come on their own", "Light effects from what happens in the game. Every one can be taken off "
    .. "with Not now.", { get = function() return S().auraAuto ~= false end,
    set = function(v) K.db.settings.auraAuto = v end })
  for _, fx in ipairs(AE.LIST) do
    card:Toggle(fx.label, fx.desc, {
      get = function() return not (type(S().autoFx) == "table" and S().autoFx[fx.id] == false) end,
      set = function(v)
        K.db.settings.autoFx = type(K.db.settings.autoFx) == "table" and K.db.settings.autoFx or {}
        if v then K.db.settings.autoFx[fx.id] = nil else K.db.settings.autoFx[fx.id] = false end
      end,
    })
  end
  card:Note("Only time you're playing counts, and nothing that would get in the way of your roleplay comes on its own.")
end })
