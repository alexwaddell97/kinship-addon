-- Kinship RP: effects (roleplay auras). Timed boons, afflictions, wounds,
-- captures and states that sit on your character: "Wounded" for a day,
-- "Drunk" for an hour, "Bound" until someone cuts the rope. They show on an
-- effects bar on your screen, in tooltips, on the target bar and in your
-- profile, and travel to other Kinship users over MSP ("KU").
--
-- Others can lay an effect on you (K.Net "auraOffer"), within your
-- boundaries: wounds follow your Injury consent (RI) and captures your
-- Capture consent (RO). "No" turns them away, "Ask" always asks, and
-- everything else follows your "From other players" setting.
--
-- Times are server time (GetServerTime), so every client agrees on when an
-- effect ends. Some wounds heal in stages: when one ends, the next begins.
--
--   K.db.auras[charGUID] = { list = { entry, ... } }   -- what's on you
--   K.db.auraLib[id]     = def                          -- your own designs
--   entry = { key, id, name, icon, kind, desc, note, from, t, expires, next }
--   def   = { id, name, icon, kind, desc, dur, next, custom }
-- Fires "AURAS" whenever your effects or designs change.

local ADDON, ns = ...
local K = ns.K
local UI = K.UI
local Safe = K.Safe
local A = {}
K.Auras = A
K.Net:Gate({ "auraOffer", "auraReply" }, "auras")

local WHITE = "Interface\\Buttons\\WHITE8X8"
local ICONS = "Interface\\Icons\\"
local MAX_ACTIVE, MAX_SHARED = 12, 8
local LIMIT = { id = 60, name = 40, desc = 300, note = 120, sharedDesc = 160 }
local MAX_DUR = 30 * 86400
local MIN, HOUR, DAY = 60, 3600, 86400

---------------------------------------------------------------------------
-- Kinds and presets
---------------------------------------------------------------------------
A.KIND_ORDER = { "boon", "bane", "wound", "capture", "state" }
A.KINDS = {
  boon    = { label = "Boon",       plural = "Boons",   color = { 0.40, 0.80, 0.48 } },
  bane    = { label = "Affliction", plural = "Banes",   color = { 0.72, 0.46, 0.95 } },
  wound   = { label = "Wound",      plural = "Wounds",  color = { 0.90, 0.36, 0.30 }, consent = "RI" },
  capture = { label = "Capture",    plural = "Capture", color = { 0.95, 0.76, 0.36 }, consent = "RO" },
  state   = { label = "State",      plural = "States",  color = { 0.55, 0.74, 0.86 } },
}

A.DURATIONS = {
  { key = 10 * MIN, label = "10 min" }, { key = HOUR, label = "1 hour" }, { key = DAY, label = "1 day" },
  { key = 3 * DAY, label = "3 days" }, { key = 7 * DAY, label = "1 week" }, { key = 0, label = "Ongoing" },
}

local function P(id, kind, name, icon, dur, desc, nxt)
  return { id = id, kind = kind, name = name, icon = ICONS .. icon, dur = dur, desc = desc, next = nxt }
end
A.PRESETS = {
  P("grazed", "wound", "Grazed", "Ability_Gouge", HOUR, "A shallow cut or a bruise. It stings, nothing worse."),
  P("bleeding", "wound", "Bleeding", "Ability_Rogue_Rupture", HOUR, "An open wound that won't stop bleeding without help.", "wounded"),
  P("wounded", "wound", "Wounded", "Ability_Warrior_BloodFrenzy", DAY, "Hurt badly enough to slow them down and show on their face.", "healing"),
  P("grave", "wound", "Gravely wounded", "Spell_Shadow_LifeDrain", 3 * DAY, "Barely on their feet, if at all. Needs a healer and rest.", "wounded"),
  P("broken", "wound", "Broken bone", "INV_Misc_Bone_01", 7 * DAY, "A splinted arm or leg. Every movement is careful.", "healing"),
  P("healing", "wound", "Healing", "Spell_Nature_Regenerate", 2 * DAY, "On the mend: stiff, tender, bandaged."),
  P("scarred", "wound", "Scarred", "Ability_Hunter_SniperShot", 0, "An old wound that left its mark for good."),
  P("bandaged", "boon", "Bandaged", "INV_Misc_Bandage_15", DAY, "Cleaned and dressed by someone who knew what they were doing."),
  P("inspired", "boon", "Inspired", "Spell_Holy_MindVision", HOUR, "Something lit a fire in them. Bolder, brighter, sure of themselves."),
  P("blessed", "boon", "Blessed", "Spell_Holy_GreaterBlessingofKings", DAY, "Touched by a blessing, and it shows."),
  P("emboldened", "boon", "Emboldened", "Ability_Warrior_BattleShout", HOUR, "Steeled for what comes next."),
  P("rested", "boon", "Well rested", "Spell_Holy_Renew", DAY, "A good night's sleep and a clear head."),
  P("poisoned", "bane", "Poisoned", "Ability_Creature_Poison_02", HOUR, "Pale, sweating and unsteady."),
  P("cursed", "bane", "Cursed", "Spell_Shadow_AntiShadow", DAY, "Something dark clings to them."),
  P("sick", "bane", "Sick", "Spell_Nature_NullifyDisease", DAY, "Feverish, coughing, best kept at arm's length."),
  P("exhausted", "bane", "Exhausted", "Spell_Nature_Sleep", HOUR, "Running on nothing. Slow to react."),
  P("frightened", "bane", "Frightened", "Spell_Shadow_PsychicScream", 10 * MIN, "Shaken, jumpy, looking for a way out."),
  P("bound", "capture", "Bound", "Spell_Nature_EarthBind", 0, "Hands tied. Going nowhere without help."),
  P("captured", "capture", "Captured", "Spell_Shadow_Charm", 0, "A prisoner, held against their will."),
  P("blindfolded", "capture", "Blindfolded", "Spell_Shadow_MindSteal", HOUR, "Can't see a thing."),
  P("drunk", "state", "Drunk", "INV_Drink_05", HOUR, "Loud, swaying, and very sure of themselves."),
  P("disguised", "state", "Disguised", "Ability_Rogue_Disguise", 0, "Not quite who they seem to be."),
  P("soaked", "state", "Soaked", "Spell_Frost_SummonWaterElemental", HOUR, "Drenched to the bone and dripping."),
  P("hungry", "state", "Hungry", "INV_Misc_Food_15", HOUR, "Stomach growling."),
}
local PRESET = {}
for _, d in ipairs(A.PRESETS) do PRESET[d.id] = d end

function A.Kind(kind) return A.KINDS[kind] or A.KINDS.state end
function A.Color(kind) return A.Kind(kind).color end

---------------------------------------------------------------------------
-- Small helpers
---------------------------------------------------------------------------
local function Now() return GetServerTime and GetServerTime() or time() end
local function Short(n) return Ambiguate and Ambiguate(n, "none") or n end
local function S() return K.db and K.db.settings or {} end

local function Cut(s, max)
  if K.Items then return K.Items.Cut(s, max) end
  s = type(s) == "string" and s or ""
  return #s > max and s:sub(1, max) or s
end

local function ValidIcon(v)
  if type(v) == "number" then return (v > 0 and v == math.floor(v)) and v or nil end
  if type(v) ~= "string" or #v > 120 or v:find("[|:]") then return nil end
  if v:find("^[%w_%-]+$") then return ICONS .. v end
  if v:lower():find("^interface\\icons\\[%w_%-]+$") then return v end
end

-- "2d 4h", "3h 12m", "12m", "40s"
function A.Left(expires)
  if not expires then return nil end
  local s = math.max(0, expires - Now())
  if s >= DAY then
    local d, h = math.floor(s / DAY), math.floor((s % DAY) / HOUR)
    return h > 0 and ("%dd %dh"):format(d, h) or ("%dd"):format(d)
  elseif s >= HOUR then
    local h, m = math.floor(s / HOUR), math.floor((s % HOUR) / MIN)
    return m > 0 and ("%dh %dm"):format(h, m) or ("%dh"):format(h)
  elseif s >= MIN then
    return ("%dm"):format(math.floor(s / MIN))
  end
  return ("%ds"):format(math.floor(s))
end

-- "1 hour", "3 days", "Ongoing"
function A.DurLabel(dur)
  for _, d in ipairs(A.DURATIONS) do if d.key == dur then return d.label end end
  if not dur or dur <= 0 then return "Ongoing" end
  if dur >= DAY then return ("%d days"):format(math.floor(dur / DAY + 0.5)) end
  if dur >= HOUR then return ("%d hours"):format(math.floor(dur / HOUR + 0.5)) end
  return ("%d min"):format(math.max(1, math.floor(dur / MIN + 0.5)))
end

-- Check and copy a design (yours, a preset, or one someone sent).
function A.Sanitize(raw)
  if type(raw) ~= "table" then return nil end
  local id = type(raw.id) == "string" and raw.id or ""
  if id == "" or #id > LIMIT.id then return nil end
  local name = strtrim(Cut(raw.name, LIMIT.name))
  if name == "" then return nil end
  local dur = tonumber(raw.dur) or 0
  dur = math.max(0, math.min(MAX_DUR, math.floor(dur)))
  return {
    id = id, name = name, icon = ValidIcon(raw.icon) or (ICONS .. "INV_Misc_QuestionMark"),
    kind = A.KINDS[raw.kind] and raw.kind or "state",
    desc = Cut(raw.desc, LIMIT.desc), dur = dur,
    next = (type(raw.next) == "string" and PRESET[raw.next]) and raw.next or nil,
    custom = raw.custom and true or nil,
  }
end

---------------------------------------------------------------------------
-- The library: presets and your own designs
---------------------------------------------------------------------------
function A:Def(id)
  if type(id) ~= "string" then return nil end
  return PRESET[id] or (K.db and K.db.auraLib[id])
end

function A:Library(kind)
  local out = {}
  for _, k in ipairs(self.KIND_ORDER) do
    if not kind or kind == "all" or kind == k then
      local customs = {}
      for _, d in pairs(K.db.auraLib) do if d.kind == k then customs[#customs + 1] = d end end
      table.sort(customs, function(a, b) return a.name:lower() < b.name:lower() end)
      for _, d in ipairs(customs) do out[#out + 1] = d end
      for _, d in ipairs(self.PRESETS) do if d.kind == k then out[#out + 1] = d end end
    end
  end
  return out
end

function A:SaveCustom(fields, id)
  local old = id and K.db.auraLib[id]
  local raw = {}
  for k, v in pairs(fields) do raw[k] = v end
  raw.id = old and old.id or ("my#%d#%d"):format(time(), math.random(100000, 999999))
  raw.custom = true
  local def = A.Sanitize(raw)
  if not def then return nil, "Give the effect a name first." end
  K.db.auraLib[def.id] = def
  K:Fire("AURAS")
  return def
end

function A:DeleteCustom(id)
  if K.db.auraLib[id] then K.db.auraLib[id] = nil; K:Fire("AURAS") end
end

---------------------------------------------------------------------------
-- What's on you
---------------------------------------------------------------------------
function A:Mine()
  local key = K:CharKey()
  local box = K.db.auras[key]
  if type(box) ~= "table" then box = { list = {} }; K.db.auras[key] = box end
  if type(box.list) ~= "table" then box.list = {} end
  return box.list
end

local function Changed()
  K:Fire("AURAS")
  if K.Comm and K.Comm.SchedulePublish then K.Comm:SchedulePublish() end
end

function A:Find(id)
  for i, e in ipairs(self:Mine()) do if e.id == id then return e, i end end
end

-- Put an effect on yourself. dur: seconds (0 = until you end it); from: who
-- laid it on you (nil = yourself). Returns the entry.
function A:Apply(def, dur, from, note, quiet)
  def = A.Sanitize(def)
  if not def then return nil end
  dur = tonumber(dur)
  if not dur then dur = def.dur end
  dur = math.max(0, math.min(MAX_DUR, math.floor(dur)))
  note = strtrim(Cut((note or ""):gsub("[|\r\n]", " "), LIMIT.note))
  local list = self:Mine()
  local e = self:Find(def.id)
  local renewed = e ~= nil
  if not e then
    if #list >= MAX_ACTIVE then
      if not quiet then UI.Toast({ icon = def.icon, round = true, title = "Too many effects",
        text = "End one before taking on another.", color = A.Color(def.kind) }) end
      return nil
    end
    e = { key = ("%d#%d"):format(Now(), math.random(1000, 9999)) }
    list[#list + 1] = e
  end
  e.id, e.name, e.icon, e.kind, e.desc, e.next = def.id, def.name, def.icon, def.kind, def.desc, def.next
  e.note = note ~= "" and note or nil
  e.from = from
  e.t = Now()
  e.expires = dur > 0 and (Now() + dur) or nil
  if not quiet then
    local how = (from and ("From " .. Short(from) .. ". ") or "") .. (e.expires and (A.DurLabel(dur) .. ".") or "Until you end it.")
    UI.Toast({
      icon = def.icon, round = true, color = A.Color(def.kind), duration = 5,
      title = (renewed and "Renewed: " or "") .. UI.Escape(def.name),
      text = how .. (def.desc ~= "" and (" " .. UI.Escape(def.desc)) or ""),
    })
  end
  Changed()
  return e
end

function A:Remove(key, quiet)
  local list = self:Mine()
  for i, e in ipairs(list) do
    if e.key == key then
      table.remove(list, i)
      if not quiet and SOUNDKIT and SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_OFF then PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_OFF) end
      Changed()
      return e
    end
  end
end

function A:Clear()
  wipe(self:Mine())
  Changed()
end

-- End what has run out; wounds that heal in stages move to the next one.
function A:Expire()
  if not K.db then return end
  local list, now, changed = self:Mine(), Now(), false
  for i = #list, 1, -1 do
    local e = list[i]
    if e.expires and e.expires <= now then
      table.remove(list, i)
      changed = true
      local nxt = e.next and PRESET[e.next]
      if nxt then
        self:Apply(nxt, nxt.dur, e.from, e.note, true)
        UI.Toast({ icon = nxt.icon, round = true, color = A.Color(nxt.kind), duration = 6,
          title = UI.Escape(e.name) .. " gives way", text = "Now: " .. nxt.name .. ". " .. nxt.desc })
      elseif (now - e.expires) < 120 then
        UI.Toast({ icon = e.icon, round = true, color = A.Color(e.kind), duration = 4,
          title = UI.Escape(e.name) .. " has passed", text = "It's no longer on you." })
      end
    end
  end
  if changed then Changed() end
end

---------------------------------------------------------------------------
-- Other players' effects
---------------------------------------------------------------------------
-- Live effects of a player (a name), or yours when isMe.
function A:Of(name, isMe)
  local out, now = {}, Now()
  if not K:ExtOn("auras") then return out end   -- switched off: nobody shows effects, yours aren't shared
  local list
  if isMe then
    list = self:Mine()
  else
    if not name or K:IsIgnored(name) then return out end
    local reg = K:ProfileOf(name)
    local au = reg and reg.profile and reg.profile.auras
    list = au and au.list
  end
  for _, e in ipairs(list or {}) do
    if not e.expires or e.expires > now then out[#out + 1] = e end
  end
  return out
end

-- Their boundary for a kind of effect: "1" yes, "2" no, "3" ask, or nil (unknown).
function A:ConsentOf(name, kind, isMe)
  local field = A.Kind(kind).consent
  if not field then return nil end
  local p
  if isMe then p = K:Profile() else local reg = K:ProfileOf(name); p = reg and reg.profile end
  return p and p.consent and p.consent[field] or nil
end

---------------------------------------------------------------------------
-- Tooltips for one effect
---------------------------------------------------------------------------
function A:ShowTooltip(owner, e, other, anchor)
  if not e then return end
  local function C(s) return other and UI.Clean(s) or UI.Escape(s or "") end
  local c = A.Color(e.kind)
  GameTooltip:SetOwner(owner, anchor or "ANCHOR_RIGHT")
  local icon = e.icon and ("|T%s:20:20:0:0:64:64:5:59:5:59|t  "):format(tostring(e.icon)) or ""
  GameTooltip:SetText(icon .. C(e.name), c[1], c[2], c[3])
  local left = e.expires and A.Left(e.expires)
  GameTooltip:AddLine(A.Kind(e.kind).label .. (left and ("  ·  " .. left .. " left") or (e.dur and e.dur > 0 and not e.key
    and ("  ·  " .. A.DurLabel(e.dur)) or "  ·  ongoing")), 0.62, 0.62, 0.62)
  if e.desc and e.desc ~= "" then GameTooltip:AddLine(C(e.desc), 0.95, 0.93, 0.88, true) end
  if e.note and e.note ~= "" then GameTooltip:AddLine("\"" .. C(e.note) .. "\"", 1, 0.82, 0, true) end
  if e.from then GameTooltip:AddLine("From " .. UI.Escape(Short(e.from)), 0.55, 0.55, 0.55) end
  if e.next and PRESET[e.next] then GameTooltip:AddLine("Then: " .. PRESET[e.next].name, 0.55, 0.55, 0.55) end
  GameTooltip:Show()
end

-- One line of icons and names for a unit tooltip.
function A.Summary(list, other, max)
  local parts = {}
  for i, e in ipairs(list) do
    if i > (max or 4) then parts[#parts + 1] = ("+%d more"):format(#list - (max or 4)) break end
    local c = A.Color(e.kind)
    local name = other and UI.Clean(e.name) or UI.Escape(e.name)
    local left = e.expires and A.Left(e.expires)
    parts[#parts + 1] = ("|T%s:14:14:0:0:64:64:5:59:5:59|t |cff%s%s|r%s"):format(tostring(e.icon), UI.Hex(c), name,
      left and ("|cff9a9a9a %s|r"):format(left) or "")
  end
  return table.concat(parts, "   ")
end

K:AddTooltipLines(function(tooltip, unit, name, profile, isMe)
  if not K.db or S().auraTooltip == false then return end
  local list = A:Of(name, isMe)
  if #list == 0 then return end
  tooltip:AddLine(A.Summary(list, not isMe, 3), 1, 1, 1, true)
end)

---------------------------------------------------------------------------
-- Sharing over MSP: "KU" = "1" then "~record" per effect, where a record is
-- id^kind^name^icon^expires^desc^note^from, %XX-escaped like companions.
-- expires is server time (0 = ongoing), so every client counts down alike.
---------------------------------------------------------------------------
local function Esc(s)
  return (tostring(s or ""):gsub("[%%%^~;`|]", function(ch) return ("%%%02X"):format(ch:byte()) end))
end
local function Unesc(s)
  return (tostring(s or ""):gsub("%%(%x%x)", function(h) return string.char(tonumber(h, 16)) end))
end

function A:Serialize()
  local parts, n = { "1" }, 0
  for _, e in ipairs(self:Of(nil, true)) do
    n = n + 1
    if n > MAX_SHARED then break end
    parts[#parts + 1] = "~" .. table.concat({
      Esc(e.id), Esc(e.kind), Esc(e.name), Esc(tostring(e.icon or "")), tostring(e.expires or 0),
      Esc(Cut(e.desc or "", LIMIT.sharedDesc)), Esc(e.note or ""), Esc(e.from and Short(e.from) or ""),
    }, "^")
  end
  return table.concat(parts)
end

function A.Deserialize(s)
  if type(s) ~= "string" or s:sub(1, 1) ~= "1" then return nil end
  local list = {}
  for rec in s:gmatch("~([^~]*)") do
    if #list >= MAX_SHARED then break end
    local f = {}
    for part in (rec .. "^"):gmatch("([^%^]*)%^") do f[#f + 1] = part end
    local name = strtrim(Cut(Unesc(f[3]), LIMIT.name))
    local icon = Unesc(f[4])
    if name ~= "" then
      local exp = tonumber(f[5]) or 0
      local kind = Unesc(f[2])
      local from = Unesc(f[8])
      local note = Cut(Unesc(f[7]), LIMIT.note)
      list[#list + 1] = {
        id = Cut(Unesc(f[1]), LIMIT.id), kind = A.KINDS[kind] and kind or "state", name = name,
        icon = ValidIcon(tonumber(icon) or icon) or (ICONS .. "INV_Misc_QuestionMark"),
        expires = exp > 0 and exp or nil, desc = Cut(Unesc(f[6]), LIMIT.sharedDesc),
        note = note ~= "" and note or nil, from = from ~= "" and from or nil,
      }
    end
  end
  return list
end

K:AddProfileField({
  publish = function(my) my.KU = A:Serialize() end,
  read = function(fields, out)
    local v = fields.KU
    -- Always a non-empty table, so an emptied list replaces the old one.
    if type(v) == "string" and v ~= "" then out.auras = { v = 1, list = A.Deserialize(v) or {} } end
  end,
  full = { "KU" },
  tooltip = { "KU" },
})

---------------------------------------------------------------------------
-- Laying an effect on someone else
--   auraOffer  WHISPER  { r, d = def, dur, note }
--   auraReply  WHISPER  { r, ok, why }
---------------------------------------------------------------------------
A.sent = {}

-- Can I offer this kind to them? Returns ok, and a reason when not (or a note when they'll be asked).
function A:CanOffer(name, kind)
  if not name or not K.Net then return false, "Choose a player first." end
  if K:IsIgnored(name) then return false, "You've ignored them." end
  local c = self:ConsentOf(name, kind)
  if c == "2" then return false, "Their boundaries say no to " .. A.Kind(kind).plural:lower() .. "." end
  if c == "3" then return true, "They'll be asked first." end
  return true, nil
end

function A:Offer(name, def, dur, note)
  def = A.Sanitize(def)
  if not def then return false, "Choose an effect first." end
  local ok, why = self:CanOffer(name, def.kind)
  if not ok then return false, why end
  local r = ("%d%d"):format(time() % 100000, math.random(100, 999))
  local sent = K.Net:Send("auraOffer", {
    r = r, d = { id = def.id, name = def.name, icon = def.icon, kind = def.kind, desc = def.desc, next = def.next },
    dur = tonumber(dur) or def.dur, note = note,
  }, "WHISPER", name)
  if not sent then return false, "Couldn't reach them. Effects only travel between Kinship users." end
  self.sent[r] = { to = name, def = def, t = GetTime() }
  return true
end

local function Reply(to, r, ok, why) K.Net:Send("auraReply", { r = r, ok = ok and true or nil, why = why }, "WHISPER", to) end

local function InGroupWith(name)
  local short = Short(name)
  return (UnitInParty and UnitInParty(short)) or (UnitInRaid and UnitInRaid(short)) and true or false
end

K.Net:On("auraOffer", function(msg, sender)
  if type(msg) ~= "table" or type(msg.r) ~= "string" or not K.db then return end
  local def = A.Sanitize(type(msg.d) == "table" and msg.d or nil)
  if not def then return end
  def.custom = nil
  local dur = math.max(0, math.min(MAX_DUR, math.floor(tonumber(msg.dur) or def.dur)))
  local note = type(msg.note) == "string" and msg.note or nil
  local consent = A:ConsentOf(nil, def.kind, true)
  if consent == "2" then Reply(sender, msg.r, false, "boundary") return end
  local mode = S().auraAccept or "ask"
  if mode == "never" then Reply(sender, msg.r, false, "closed") return end
  local ask = consent == "3" or mode == "ask" or (mode == "group" and not InGroupWith(sender))
  if not ask then
    if A:Apply(def, dur, sender, note) then Reply(sender, msg.r, true) else Reply(sender, msg.r, false, "full") end
    return
  end
  local c = A.Color(def.kind)
  UI.Toast({
    icon = def.icon, round = true, color = c, duration = 30, sound = "TELL_MESSAGE",
    title = Short(sender) .. " lays an effect on you",
    text = ("|cff%s%s|r for %s.%s"):format(UI.Hex(c), UI.Escape(def.name), A.DurLabel(dur):lower(),
      note and note ~= "" and (" \"" .. UI.Clean(note) .. "\"") or ""),
    actions = {
      { label = "Decline", fn = function() Reply(sender, msg.r, false, "declined") end },
      { label = "Accept", fn = function()
        if A:Apply(def, dur, sender, note) then Reply(sender, msg.r, true) else Reply(sender, msg.r, false, "full") end
      end },
    },
  })
end)

local WHY = {
  boundary = "Their boundaries say no to that.", closed = "They aren't accepting effects from others.",
  declined = "They declined.", full = "They already carry too many effects.",
}
K.Net:On("auraReply", function(msg, sender)
  if type(msg) ~= "table" or type(msg.r) ~= "string" then return end
  local o = A.sent[msg.r]
  if not o or K.NameKey(o.to) ~= K.NameKey(sender) then return end
  A.sent[msg.r] = nil
  local c = A.Color(o.def.kind)
  UI.Toast({
    icon = o.def.icon, round = true, color = c, duration = 5,
    title = Short(sender) .. (msg.ok and " took it on" or " turned it away"),
    text = msg.ok and (UI.Escape(o.def.name) .. " is on them now.") or (WHY[msg.why] or "Not this time."),
  })
end)

---------------------------------------------------------------------------
-- After a fight: did it leave a mark?
---------------------------------------------------------------------------
local function OnDeath()
  if not K:ExtOn("auras") or S().auraDeathPrompt == false then return end
  if A:ConsentOf(nil, "wound", true) == "2" then return end
  local foe = K.War and K.War.LastFoe and K.War:LastFoe()
  if not foe then return end
  C_Timer.After(2, function()
    UI.Toast({
      icon = PRESET.wounded.icon, round = true, color = A.Color("wound"), duration = 25,
      title = "Did the fight leave a mark?",
      text = "Carry a wound from " .. UI.Escape(Short(foe)) .. " into your story. It heals on its own.",
      actions = {
        { label = "Wounded", fn = function() A:Apply(PRESET.wounded, PRESET.wounded.dur, foe) end },
        { label = "Gravely", fn = function() A:Apply(PRESET.grave, PRESET.grave.dur, foe) end },
      },
    })
  end)
end

---------------------------------------------------------------------------
-- The effects bar: your own effects as round icons with time left. Drag to
-- move; click to open them in your journal; right-click to end one.
---------------------------------------------------------------------------
local Bar = {}
A.Bar = Bar
local ICON = 30

local function BarPlace(f)
  local p = S().auraBarPos
  f:ClearAllPoints()
  if type(p) == "table" and p.point then f:SetPoint(p.point, UIParent, p.rel or p.point, p.x or 0, p.y or 0)
  else f:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", -260, -150) end
end

function Bar:Build()
  if self.frame then return self.frame end
  local f = CreateFrame("Frame", "KinshipRPEffectsBar", UIParent)
  self.frame = f
  f:SetSize(ICON + 8, ICON + 22)
  f:SetFrameStrata("MEDIUM")
  f:SetClampedToScreen(true)
  f:SetMovable(true)
  f:EnableMouse(true)
  f:RegisterForDrag("LeftButton")
  f:SetScript("OnDragStart", function(self) if not S().auraBarLock then self:StartMoving() end end)
  f:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    local point, _, rel, x, y = self:GetPoint(1)
    K.db.settings.auraBarPos = { point = point, rel = rel, x = math.floor(x + 0.5), y = math.floor(y + 0.5) }
  end)
  f.icons = {}
  f.t = 0
  f:SetScript("OnUpdate", function(self, elapsed)
    self.t = self.t + elapsed
    if self.t < 1 then return end
    self.t = 0
    for _, b in ipairs(self.icons) do
      if b:IsShown() and b.entry then b.time:SetText(b.entry.expires and A.Left(b.entry.expires) or "") end
    end
  end)
  BarPlace(f)
  f:Hide()
  return f
end

local function BarIcon(f, i)
  local b = f.icons[i]
  if b then return b end
  b = CreateFrame("Button", nil, f)
  b:SetSize(ICON + 4, ICON + 18)
  b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  b:RegisterForDrag("LeftButton")
  b:SetScript("OnDragStart", function() f:GetScript("OnDragStart")(f) end)
  b:SetScript("OnDragStop", function() f:GetScript("OnDragStop")(f) end)
  b.ring = UI.Circle(b, ICON + 4, "ARTWORK", 0)
  b.ring:SetPoint("TOP")
  b.icon = b:CreateTexture(nil, "ARTWORK", nil, 1)
  b.icon:SetSize(ICON, ICON)
  b.icon:SetPoint("CENTER", b.ring)
  b.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
  UI.Round(b.icon)
  b.time = b:CreateFontString(nil, "OVERLAY")
  b.time:SetFontObject(UI.FONTS.Small)
  b.time:SetPoint("TOP", b.ring, "BOTTOM", 0, -2)
  local face, size = UI.FONTS.Small:GetFont()
  if face then b.time:SetFont(face, size, "OUTLINE") end
  b.time:SetTextColor(1, 0.95, 0.85)
  local function paint(p)
    local c = A.Color(b.entry and b.entry.kind)
    b.ring:SetVertexColor(c[1], c[2], c[3], 0.65 + 0.35 * p)
    b.icon:SetSize(ICON + 2 * p, ICON + 2 * p)
  end
  b.paint = paint
  b:SetScript("OnEnter", function(self)
    UI.Tween(self, 1, 0.1, paint)
    A:ShowTooltip(self, self.entry, false, "ANCHOR_BOTTOMLEFT")
    GameTooltip:AddLine("Right-click to end it.", 0.55, 0.80, 1)
    GameTooltip:Show()
  end)
  b:SetScript("OnLeave", function(self) UI.Tween(self, 0, 0.12, paint); GameTooltip:Hide() end)
  b:SetScript("OnClick", function(self, button)
    if button == "RightButton" then
      if self.entry then A:Remove(self.entry.key) end
      GameTooltip:Hide()
    else
      A:OpenJournal()
    end
  end)
  f.icons[i] = b
  return b
end

function Bar:Update()
  if not K.db then return end
  local list = A:Of(nil, true)
  if S().auraBar == false or #list == 0 then
    if self.frame then self.frame:Hide() end
    return
  end
  local f = self:Build()
  for i, e in ipairs(list) do
    local b = BarIcon(f, i)
    b.entry = e
    b.icon:SetTexture(e.icon)
    b.time:SetText(e.expires and A.Left(e.expires) or "")
    b:ClearAllPoints()
    b:SetPoint("TOPRIGHT", f, "TOPRIGHT", -((i - 1) * (ICON + 8)) - 2, -2)
    b.paint(UI.Progress(b))
    b:Show()
  end
  for i = #list + 1, #f.icons do f.icons[i]:Hide(); f.icons[i].entry = nil end
  f:SetWidth(#list * (ICON + 8) + 4)
  if not f:IsShown() then f:Show(); UI.FadeIn(f, 0.2) end
end

---------------------------------------------------------------------------
-- Opening the effects tab (Persona page), optionally aimed at someone
---------------------------------------------------------------------------
function A:OpenJournal(target)
  self.wantTab = true
  self.target = target
  K.Journal:Open("persona")
end

K:RegisterTargetButton({
  id = "aura", order = 30, label = "Lay an effect", icon = ICONS .. "Spell_Holy_MagicalSentry",
  shown = function(unit, name)
    if not K:ExtOn("auras") or not name or K:IsIgnored(name) then return false end
    local me = UnitIsUnit("target", "player")
    return Safe(me) and not me
  end,
  onClick = function(unit, name) A:OpenJournal(name) end,
})

---------------------------------------------------------------------------
-- Start-up, timers and settings
---------------------------------------------------------------------------
K:On("AURAS", function() Bar:Update() end)

-- Switched off or back on: hide the bar and republish, so others stop (or start) seeing your effects.
local auraWasOn
K:On("EXTENDED", function()
  local on = K:ExtOn("auras")
  if on == auraWasOn then return end
  auraWasOn = on
  Bar:Update()
  K:Fire("AURAS")
  K:Fire("PROFILE")
end)

local ev = CreateFrame("Frame")
ev:SetScript("OnEvent", function() K.Try("auras", OnDeath) end)

K:On("LOGIN", function()
  K.db.auras = K.db.auras or {}
  K.db.auraLib = K.db.auraLib or {}
  local s = K.db.settings
  if s.auraBar == nil then s.auraBar = true end
  if s.auraTooltip == nil then s.auraTooltip = true end
  if s.auraDeathPrompt == nil then s.auraDeathPrompt = true end
  if s.auraAccept == nil then s.auraAccept = "ask" end
  if s.auraBarLock == nil then s.auraBarLock = false end
  A:Mine()
  auraWasOn = K:ExtOn("auras")
  if not auraWasOn then return end   -- switched off: no events, no timers, no bar
  ev:RegisterEvent("PLAYER_DEAD")
  A:Expire()
  Bar:Update()
  C_Timer.NewTicker(5, function() if K:ExtOn("auras") then K.Try("auras", A.Expire, A) end end)
end)

K:RegisterSettings({ id = "auras", title = "Effects", order = 16,
  shown = function() return K:ExtOn("auras") end, build = function(card)
  card:Toggle("Effects bar", "Your own effects as icons on your screen, with time left. Drag to move.",
    { get = function() return S().auraBar ~= false end, set = function(v) K.db.settings.auraBar = v; Bar:Update() end })
  card:Toggle("Effects in tooltips", "Show players' effects when you hover over them.", "auraTooltip")
  card:Toggle("Offer a wound after a PvP death", "When an enemy player brings you down, ask whether the fight left a mark.",
    "auraDeathPrompt")
  card:Toggle("Lock the effects bar", "Stop it moving when dragged.", "auraBarLock")
  card:Segments("From other players", {
    { key = "ask", label = "Ask me" }, { key = "group", label = "Trust my group" }, { key = "never", label = "Never" },
  }, function() return S().auraAccept or "ask" end, function(v) K.db.settings.auraAccept = v end, 110)
  card:Note("Wounds always follow your Injury boundary, and captures your Capture boundary (Warfront > Stance & consent): "
    .. "\"No\" turns them away and \"Ask\" always asks, whatever you choose here.")
  card:Button("Reset the effects bar position", function()
    K.db.settings.auraBarPos = nil
    if Bar.frame then BarPlace(Bar.frame) end
  end, 220)
end })
