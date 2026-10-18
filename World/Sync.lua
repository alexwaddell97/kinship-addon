-- Kinship RP: sharing Gatherings. Three boards:
--   guild   your guild (the GUILD addon channel)
--   house   everyone carrying your house name, passed by whisper between
--           members as you see each other (there's no house channel)
--   public  Kinship users near you (YELL: same zone, same faction), passed
--           along as people meet, so it reaches further the longer it's up
--
-- There's no server, so everyone keeps a copy and they keep each other up to
-- date with the same five messages on every board:
--   G  a gathering (new, or a newer version from its host)
--   R  someone's RSVP ("I'm going" / "not going")
--   D  the host removed a gathering
--   H  a short summary of what I have
--   Q  "please send me these", in reply to a summary
-- The game tells us who sent each message, so only the host can change or
-- remove a gathering, and only you can RSVP for yourself. Copies passed on by
-- others carry RSVPs only from the host's own copy; a gathering first heard
-- of from someone other than its host is marked as shared by them ("via")
-- until the host's own copy confirms it, and isn't passed on further. The
-- host's summary is the word on their own gatherings: one it no longer lists
-- has been removed, wherever else copies linger.
--
-- Guild messages use their own prefix (as before); house and public ones
-- travel on K.Net as kind "gath" = { t = "G"|"R"|"D"|"H"|"Q", b = board, ... }.

local ADDON, ns = ...
local K = ns.K
local Safe = K.Safe
local S = {}
K.Sync = S

local PREFIX = "KinshipRP"
local EXPIRE_DAYS = 14           -- an undated gathering lasts this long after its last change
local DAY_GRACE = 2 * 86400      -- a dated one, until this long after its day
local MAX_AHEAD = 120 * 86400    -- how far ahead a gathering may be dated
local HELLO_EVERY = 900          -- seconds between guild and house summaries
local PUBLIC_EVERY = 600         -- seconds between public summaries (when nobody nearby just sent one)
local RECV_LIMIT, RECV_WINDOW = 40, 60
local SKEW = 86400               -- how far ahead of our clock a time may be
local MAX_RSVP = 200             -- answers kept per gathering
local MAX_VIA = 10               -- unconfirmed gatherings kept per member who shared them
local MAX_IDS = 100              -- ids read from one summary or request
local MAX_PUBLIC_PER_HOST = 3    -- a stranger's public posts we'll keep
local HOUSE_RECENT = 20 * 60     -- a house member seen this recently is worth a whisper
local HOUSE_FANOUT = 12          -- house members whispered per summary

local function Key(name) return K.NameKey(name) end
local function MyKey() return Key(K:MyName()) end
local Short = K.Short
local function S_() return K.db and K.db.settings or {} end

function S.GuildName()
  if not IsInGuild() then return nil end
  local g = GetGuildInfo("player")
  return (Safe(g) and g) or nil
end

local function HouseKey(name)
  name = strtrim(tostring(name or "")):lower()
  return name ~= "" and name or nil
end
function S.MyHouse() return HouseKey(K:HouseName()) end

---------------------------------------------------------------------------
-- Data model
---------------------------------------------------------------------------
-- g = { id, title, when, where, desc, host, scope, guild, house, t (posted),
--       ver (last change), day (scheduled day, optional: noon on that day, host's time),
--       rsvp = { [nameKey] = { n = name, on = bool, t = time } },
--       via, viaKey }       scope nil = guild (gatherings from before boards)

local function Upgrade(g)
  if not g.rsvp then
    g.rsvp = {}
    for n in pairs(g.going or {}) do g.rsvp[Key(n) or n:lower()] = { n = n, on = true, t = g.t or time() } end
    g.going = nil
  end
  g.ver = g.ver or g.t or time()
  g.id = g.id or (tostring(g.t or time()) .. math.random(1000, 9999))
  return g
end

function S:Find(id)
  for i, g in ipairs(K.db.gatherings) do if g.id == id then return g, i end end
end

function K:GoingNames(g)
  local out = {}
  for _, r in pairs(g.rsvp or {}) do if r.on and not K:IsIgnored(r.n) then out[#out + 1] = r.n end end
  table.sort(out)
  return out
end

function K:IsGoing(g)
  local r = (g.rsvp or {})[MyKey() or ""]
  return r and r.on or false
end

function K:IsHost(g) return Key(g.host) == MyKey() end

-- Copy only the fields we share.
local function Pack(g)
  local rsvp = {}
  for k, r in pairs(g.rsvp or {}) do rsvp[k] = { n = r.n, on = r.on, t = r.t } end
  return { id = g.id, title = g.title, when = g.when, where = g.where, desc = g.desc,
           host = g.host, guild = g.guild, house = g.house, scope = g.scope or "guild",
           t = g.t, ver = g.ver, day = g.day, rsvp = rsvp }
end

local function Str(v, max) return type(v) == "string" and v:sub(1, max) or "" end

-- A time that is a real number and not far in the future (received numbers
-- can be anything, even infinity).
local function SaneTime(v)
  return type(v) == "number" and v == v and v > 0 and v <= time() + SKEW
end

-- The scheduled day (noon, host's time), if it's a real one within reach.
local function SaneDay(v)
  if type(v) == "number" and v == v and v > 0 and v <= time() + MAX_AHEAD then return math.floor(v) end
  return nil
end

-- A dated gathering lasts until its day is over (with a day's grace for other
-- time zones), however long ago it was posted; one without a date lasts
-- EXPIRE_DAYS from its last change.
local function Expired(g, now)
  now = now or time()
  if type(g.day) == "number" then return g.day + DAY_GRACE < now end
  return (g.ver or 0) < now - EXPIRE_DAYS * 86400
end
S.Expired = Expired

-- Remember a removed gathering until its copies can't come back: EXPIRE_DAYS
-- from now, or from its day if that's later.
local function Tomb(g)
  K.db.gatherTomb[g.id] = math.max(time(), SaneDay(g.day) or 0)
end

-- Check an incoming gathering is well-formed before trusting any of it.
local function Valid(g)
  return type(g) == "table" and type(g.id) == "string" and g.id ~= "" and #g.id <= 80
    and type(g.title) == "string" and g.title ~= "" and type(g.host) == "string" and g.host ~= ""
    and SaneTime(g.ver) and SaneTime(g.t)
end

local function Count(t) local n = 0; for _ in pairs(t) do n = n + 1 end; return n end

-- Merge RSVPs into a gathering's list. Only the entry keyed by `only`
-- (the sender's own) is taken, unless `only` is nil (a copy from the host).
local function MergeRSVP(into, from, only)
  if type(from) ~= "table" then return false end
  local changed, n = false, Count(into)
  for k, r in pairs(from) do
    if type(k) == "string" and #k <= 80 and (only == nil or k == only) and type(r) == "table"
        and type(r.n) == "string" and Key(r.n) == k and SaneTime(r.t) then
      local cur = into[k]
      if (cur and r.t > cur.t) or (not cur and n < MAX_RSVP) then
        if not cur then n = n + 1 end
        into[k] = { n = Str(r.n, 60), on = r.on and true or false, t = r.t }
        changed = true
      end
    end
  end
  return changed
end

---------------------------------------------------------------------------
-- Whispers to someone who has just gone offline make the game say "No
-- player named ... is currently playing". Hide that line for names we've
-- just whispered a gathering to.
---------------------------------------------------------------------------
S.whispered = {}
local notFound
local function NoteWhisper(name) S.whispered[(Short(name) or ""):lower()] = GetTime() end

local function SystemFilter(_, _, msg, ...)
  if not notFound or type(msg) ~= "string" or not Safe(msg) then return false, msg, ... end
  local who = msg:match(notFound)
  if who then
    local t = S.whispered[(Short(who) or ""):lower()]
    if t and GetTime() - t < 15 then return true end
  end
  return false, msg, ...
end

---------------------------------------------------------------------------
-- The three boards
---------------------------------------------------------------------------
local Guild, House, Public = {}, {}, {}
S.boards = { guild = Guild, house = House, public = Public }

local function Wrap(board, msg)
  local m = {}
  for k, v in pairs(msg) do m[k] = v end
  m.t, m.k, m.b = msg.k, nil, board.scope
  if board == House then m.h = S.MyHouse() end
  return m
end

-- Guild ----------------------------------------------------------------------
Guild.scope, Guild.max = "guild", 60
function Guild.on() return true end
function Guild.match(g) return (g.scope == nil or g.scope == "guild") and g.guild == S.GuildName() end
function Guild.accept(inc) return (inc.scope == nil or inc.scope == "guild") and inc.guild ~= nil and inc.guild == S.GuildName() end
function Guild.stamp(g) g.scope, g.guild, g.house = "guild", S.GuildName(), nil end
function Guild.send(msg) return S:Send(msg) end
function Guild.reply(msg) return S:Send(msg) end

-- House ----------------------------------------------------------------------
House.scope, House.max = "house", 40
function House.on() return S_().gatherHouse ~= false and S.MyHouse() ~= nil end
function House.match(g) return g.scope == "house" and g.house ~= nil and g.house == S.MyHouse() end
function House.accept(inc) return inc.scope == "house" and type(inc.house) == "string" and inc.house == S.MyHouse() end
function House.stamp(g) g.scope, g.house, g.guild = "house", S.MyHouse(), nil end

-- House members seen recently, most recent first (their profile says so).
function S:HouseMembers(limit)
  local mine, out = S.MyHouse(), {}
  if not mine then return out end
  local now, me = time(), MyKey()
  for key, e in pairs(K.Registry or {}) do
    local p = e.profile
    if p and key ~= me and HouseKey(p.house) == mine and (e.t or 0) > now - HOUSE_RECENT and not K:IsIgnored(e.name) then
      out[#out + 1] = e
    end
  end
  table.sort(out, function(a, b) return (a.t or 0) > (b.t or 0) end)
  local names = {}
  for i = 1, math.min(#out, limit or HOUSE_FANOUT) do names[i] = out[i].name end
  return names
end

function House.send(msg, extra)
  if not House.on() then return false end
  local sent, done = false, {}
  local list = S:HouseMembers()
  if extra then table.insert(list, 1, extra) end
  for _, name in ipairs(list) do
    local key = Key(name)
    if key and not done[key] and key ~= MyKey() then
      done[key] = true
      NoteWhisper(name)
      if K.Net:Send("gath", Wrap(House, msg), "WHISPER", name, "LOW") then sent = true end
    end
  end
  return sent
end
function House.reply(msg, to)
  if not to then return House.send(msg) end
  NoteWhisper(to)
  return K.Net:Send("gath", Wrap(House, msg), "WHISPER", to, "LOW")
end

-- Public ---------------------------------------------------------------------
Public.scope, Public.max = "public", 40
function Public.on() return S_().gatherPublic ~= false end
function Public.match(g) return g.scope == "public" end
function Public.accept(inc) return inc.scope == "public" end
function Public.stamp(g) g.scope, g.guild, g.house = "public", nil, nil end
function Public.send(msg, host)
  if not Public.on() or IsInInstance() then return false end
  local ok = K.Net:Send("gath", Wrap(Public, msg), "YELL", nil, "LOW")
  -- An answer also goes straight to the host, who may be far away.
  if host and Key(host) ~= MyKey() then
    NoteWhisper(host)
    K.Net:Send("gath", Wrap(Public, msg), "WHISPER", host, "LOW")
  end
  return ok
end
function Public.reply(msg) return Public.send(msg) end

local function BoardOf(g)
  if g.scope == "house" then return House end
  if g.scope == "public" then return Public end
  return Guild
end
S.BoardOf = BoardOf

-- Gatherings on one board (default: guild), newest first. Not in a guild,
-- the guild board holds the ones you made outside a guild.
function K:VisibleGatherings(scope)
  local board = S.boards[scope or "guild"] or Guild
  local out = {}
  for i = #self.db.gatherings, 1, -1 do
    local g = self.db.gatherings[i]
    if board.match(g) and not self:IsIgnored(g.host) then out[#out + 1] = g end
  end
  return out
end

---------------------------------------------------------------------------
-- Sending
---------------------------------------------------------------------------
function S:CanSend()
  if not AddOn_Chomp or not self.ready or not IsInGuild() or IsInInstance() then return false end
  if C_ChatInfo and C_ChatInfo.InChatMessagingLockdown and C_ChatInfo.InChatMessagingLockdown() then return false end
  return true
end

-- The guild channel.
function S:Send(msg)
  if not self:CanSend() then return false end
  local ok = pcall(AddOn_Chomp.SmartAddonMessage, PREFIX, msg, "GUILD", nil, { serialize = true, priority = "LOW" })
  return ok
end

-- Replies are delayed a little at random, and skipped if someone else
-- already sent the same thing, so a whole board doesn't answer at once.
S.lastSeen = {}
function S:SendSoon(id, ver, board, to)
  C_Timer.After(1 + math.random() * 4, function()
    local seen = S.lastSeen[id]
    if seen and seen.ver >= ver and GetTime() - seen.at < 15 then return end
    local g = S:Find(id)
    if g and g.ver == ver and board.match(g) then
      S.lastSeen[id] = { ver = ver, at = GetTime() }
      board.reply({ k = "G", g = Pack(g) }, to)
    end
  end)
end

-- A summary of a board: what we hold, by id and version.
local function Summary(board)
  local d, n = {}, 0
  for _, g in ipairs(K.db.gatherings) do
    if board.match(g) and not g.via then d[g.id] = g.ver; n = n + 1 end
  end
  return d, n
end

function S:Hello()
  if not S.GuildName() then return end
  self:Send({ k = "H", d = (Summary(Guild)) })
end

-- House: a summary to each member seen recently (or just to one).
S.greeted = {}
function S:HelloHouse(to)
  if not House.on() then return end
  local d = Summary(House)
  if to then House.reply({ k = "H", d = d }, to) else House.send({ k = "H", d = d }) end
end

-- Public: a summary to everyone nearby, unless someone nearby has just sent
-- one (their summary already starts the swap, and we answer it).
S.publicHeard = 0
function S:HelloPublic()
  if not Public.on() or IsInInstance() or InCombatLockdown() then return end
  if GetTime() - self.publicHeard < PUBLIC_EVERY / 2 then return end
  local d, n = Summary(Public)
  if n == 0 then return end
  Public.send({ k = "H", d = d })
end

---------------------------------------------------------------------------
-- Local actions (then shared)
---------------------------------------------------------------------------
-- scope: "guild" (default), "house" or "public".
function K:AddGathering(g, scope)
  local board = S.boards[scope or g.scope or "guild"] or Guild
  local me, now = self:MyName(), time()
  g.id = ("%s-%d-%d"):format(me, now, math.random(1000, 9999))
  g.host, g.t, g.ver = me, now, now
  g.day = SaneDay(g.day)
  board.stamp(g)
  g.rsvp = { [MyKey()] = { n = me, on = true, t = now } }
  table.insert(self.db.gatherings, g)
  S:Trim(board)
  self:Fire("GATHERINGS")
  board.send({ k = "G", g = Pack(g) })
  return g
end

function K:RemoveGathering(g)
  if not self:IsHost(g) then return end
  local _, i = S:Find(g.id)
  if i then table.remove(self.db.gatherings, i) end
  Tomb(g)
  self:Fire("GATHERINGS")
  BoardOf(g).send({ k = "D", id = g.id })
end

function K:SetRSVP(g, on)
  local me, now = self:MyName(), time()
  g.rsvp = g.rsvp or {}
  g.rsvp[MyKey()] = { n = me, on = on and true or false, t = now }
  self:Fire("GATHERINGS")
  local board = BoardOf(g)
  local msg = { k = "R", id = g.id, r = { n = me, on = on and true or false, t = now } }
  if board == Guild then board.send(msg) else board.send(msg, g.host) end
end

---------------------------------------------------------------------------
-- Receiving (every board follows the same rules)
---------------------------------------------------------------------------
function S:Trim(board)
  local list = {}
  for _, g in ipairs(K.db.gatherings) do if board.match(g) then list[#list + 1] = g end end
  if #list <= board.max then return end
  -- Unconfirmed copies go first, then the oldest; your own are never dropped.
  local me = MyKey()
  table.sort(list, function(a, b)
    local am, bm = Key(a.host) == me, Key(b.host) == me
    if am ~= bm then return bm end
    if (a.via ~= nil) ~= (b.via ~= nil) then return a.via ~= nil end
    return a.ver < b.ver
  end)
  for i = 1, #list - board.max do
    if Key(list[i].host) ~= me then
      local _, idx = self:Find(list[i].id)
      if idx then table.remove(K.db.gatherings, idx) end
    end
  end
end

S.recv = {}
function S:Handle(msg, sender, board)
  if type(msg) ~= "table" or not Safe(sender) or not sender then return end
  local from = Key(sender)
  if not from or from == MyKey() or K:IsIgnored(sender) then return end
  if not board.on() then return end

  -- Per-sender rate limit
  local now = GetTime()
  local r = self.recv[from]
  if not r or now - r.start > RECV_WINDOW then r = { start = now, n = 0 }; self.recv[from] = r end
  r.n = r.n + 1
  if r.n > RECV_LIMIT then return end

  local changed = false
  if msg.k == "G" and Valid(msg.g) then
    local inc = msg.g
    if K.db.gatherTomb[inc.id] then return end
    inc.day = SaneDay(inc.day)
    if Expired(inc) then return end
    if not board.accept(inc) then return end
    local cur = self:Find(inc.id)
    if cur and BoardOf(cur) ~= board then return end   -- one id, one board
    local fromHost = Key(cur and cur.host or inc.host) == from
    -- Only a copy we can vouch for stops others relaying it for a while.
    if fromHost or (cur and inc.ver == cur.ver) then self.lastSeen[inc.id] = { ver = inc.ver, at = now } end
    if cur then
      -- Only the host may change the details or vouch for others' answers;
      -- anyone else's copy only brings their own answer.
      if fromHost and inc.ver > cur.ver then
        cur.title, cur.when, cur.where, cur.desc = Str(inc.title, 60), Str(inc.when, 60), Str(inc.where, 60), Str(inc.desc, 1000)
        cur.ver, cur.day = inc.ver, inc.day
        changed = true
      end
      if fromHost and cur.via then cur.via, cur.viaKey = nil, nil; changed = true end
      if MergeRSVP(cur.rsvp, inc.rsvp, (not fromHost) and from or nil) then changed = true end
    else
      local shared, byHost = 0, 0
      local hostKey = Key(inc.host)
      for _, g in ipairs(K.db.gatherings) do
        if not fromHost and g.viaKey == from then shared = shared + 1 end
        if board == Public and g.scope == "public" and Key(g.host) == hostKey then byHost = byHost + 1 end
      end
      if shared < MAX_VIA and (board ~= Public or byHost < MAX_PUBLIC_PER_HOST) then
        local g = { id = inc.id, title = Str(inc.title, 60), when = Str(inc.when, 60), where = Str(inc.where, 60),
                    desc = Str(inc.desc, 1000), host = Str(inc.host, 60), t = inc.t, ver = inc.ver, day = inc.day, rsvp = {} }
        board.stamp(g)
        if not fromHost then g.via, g.viaKey = Str(sender, 60), from end
        MergeRSVP(g.rsvp, inc.rsvp, (not fromHost) and from or nil)
        table.insert(K.db.gatherings, g)
        self:Trim(board)
        changed = true
      end
    end

  elseif msg.k == "R" and type(msg.id) == "string" and type(msg.r) == "table" then
    local g = self:Find(msg.id)
    -- You can only answer for yourself.
    if g and BoardOf(g) == board and type(msg.r.n) == "string" and Key(msg.r.n) == from then
      if MergeRSVP(g.rsvp, { [from] = msg.r }) then changed = true end
    end

  elseif msg.k == "D" and type(msg.id) == "string" then
    local g, i = self:Find(msg.id)
    if g and BoardOf(g) == board and Key(g.host) == from then
      table.remove(K.db.gatherings, i)
      Tomb(g)
      changed = true
    end

  elseif msg.k == "H" and type(msg.d) == "table" then
    if board == Public then self.publicHeard = now end
    -- Their summary is the word on their own gatherings: any we hold that
    -- they host but no longer list has been removed.
    for i = #K.db.gatherings, 1, -1 do
      local g = K.db.gatherings[i]
      if board.match(g) and Key(g.host) == from and msg.d[g.id] == nil then
        table.remove(K.db.gatherings, i)
        Tomb(g)
        changed = true
      end
    end
    -- Send what they're missing or have an older copy of (only copies we can
    -- vouch for); ask for what we lack.
    for _, g in ipairs(K.db.gatherings) do
      if board.match(g) and not g.via and Key(g.host) ~= from then
        local theirs = msg.d[g.id]
        if type(theirs) ~= "number" or theirs < g.ver then self:SendSoon(g.id, g.ver, board, sender) end
      end
    end
    local want, seen = {}, 0
    for id, ver in pairs(msg.d) do
      seen = seen + 1
      if seen > MAX_IDS or #want >= 30 then break end
      if type(id) == "string" and #id <= 80 and SaneTime(ver) and not K.db.gatherTomb[id] then
        local g = self:Find(id)
        if not g or g.ver < ver then want[#want + 1] = id end
      end
    end
    if #want > 0 then
      C_Timer.After(1 + math.random() * 3, function() board.reply({ k = "Q", ids = want }, sender) end)
    end
    -- A house member we hadn't swapped with yet: send ours back.
    if board == House and not self.greeted[from] then
      self.greeted[from] = true
      C_Timer.After(2 + math.random() * 3, function() S:HelloHouse(sender) end)
    end

  elseif msg.k == "Q" and type(msg.ids) == "table" then
    for i, id in ipairs(msg.ids) do
      if i > 30 then break end
      local g = type(id) == "string" and self:Find(id)
      if g and board.match(g) and not g.via then self:SendSoon(g.id, g.ver, board, sender) end
    end
  end

  if changed then K:Fire("GATHERINGS") end
end

-- The guild channel (kept for clients from before boards).
function S:Receive(msg, sender) return self:Handle(msg, sender, Guild) end

-- House and public, on K.Net.
K.Net:On("gath", function(msg, sender, channel)
  if type(msg) ~= "table" or type(msg.t) ~= "string" then return end
  local board = msg.b == "house" and House or (msg.b == "public" and Public or nil)
  if not board then return end
  if board == House and (channel ~= "WHISPER" or msg.h ~= S.MyHouse()) then return end
  if board == Public and channel ~= "YELL" and channel ~= "WHISPER" then return end
  local m = { k = msg.t, g = msg.g, r = msg.r, id = msg.id, d = msg.d, ids = msg.ids }
  if board == House then S.greeted[Key(sender) or ""] = true end
  S:Handle(m, sender, board)
end)

-- Meeting a house member (their profile arrived): swap summaries once a session.
K:On("REGISTRY", function(key, entry)
  if not key or S.greeted[key] or not House.on() then return end
  local p = entry and entry.profile
  if not p or HouseKey(p.house) ~= S.MyHouse() or K:IsIgnored(entry.name) then return end
  S.greeted[key] = true
  C_Timer.After(3 + math.random() * 5, function() S:HelloHouse(entry.name) end)
end)

---------------------------------------------------------------------------
-- Housekeeping and start-up
---------------------------------------------------------------------------
local function Expire()
  local now = time()
  local cutoff = now - EXPIRE_DAYS * 86400
  local changed = false
  for i = #K.db.gatherings, 1, -1 do
    local g = Upgrade(K.db.gatherings[i])
    g.day = SaneDay(g.day)
    if Expired(g, now) then table.remove(K.db.gatherings, i); changed = true end
  end
  if changed then K:Fire("GATHERINGS") end
  for id, t in pairs(K.db.gatherTomb) do if t < cutoff then K.db.gatherTomb[id] = nil end end
end

K:On("LOGIN", function()
  K.db.gatherTomb = K.db.gatherTomb or {}
  local s = K.db.settings
  if s.gatherHouse == nil then s.gatherHouse = true end
  if s.gatherPublic == nil then s.gatherPublic = true end
  if s.gatherCalendar == nil then s.gatherCalendar = true end
  Expire()

  local fmt = ERR_CHAT_PLAYER_NOT_FOUND_S
  if type(fmt) == "string" then
    notFound = "^" .. fmt:gsub("([%(%)%.%%%+%-%*%?%[%]%^%$])", "%%%1"):gsub("%%%%s", "(.+)") .. "$"
    local util = type(ChatFrameUtil) == "table" and ChatFrameUtil or nil
    local add = (util and util.AddMessageEventFilter) or ChatFrame_AddMessageEventFilter
    if add then pcall(add, "CHAT_MSG_SYSTEM", SystemFilter) end
  end

  if not AddOn_Chomp then return end
  local ok = pcall(AddOn_Chomp.RegisterAddonPrefix, PREFIX, function(_, data, channel, sender)
    if channel == "GUILD" then K.Try("gatherings", S.Receive, S, data, sender) end
  end, { fullMsgOnly = true, validTypes = { table = true } })
  if not ok then return end
  S.ready = true
  C_Timer.After(20, function() S:Hello() end)
  C_Timer.After(45, function() S:HelloHouse() end)
  C_Timer.After(60 + math.random() * 60, function() S:HelloPublic() end)
  C_Timer.NewTicker(HELLO_EVERY, function() Expire(); S:Hello(); S:HelloHouse() end)
  C_Timer.NewTicker(PUBLIC_EVERY + math.random() * 120, function() S:HelloPublic() end)
end)

K:RegisterSettings({ id = "gatherings", title = "Gatherings", order = 36, build = function(card)
  card:Toggle("House gatherings", "Share and receive gatherings with players who carry your house name, as you see each other.",
    { get = function() return S_().gatherHouse ~= false end, set = function(v) K.db.settings.gatherHouse = v; K:Fire("GATHERINGS") end })
  card:Toggle("Public gatherings", "See and pass on gatherings posted by Kinship users near you.",
    { get = function() return S_().gatherPublic ~= false end, set = function(v) K.db.settings.gatherPublic = v; K:Fire("GATHERINGS") end })
  card:Toggle("Add to my calendar when I'm going", "Saying you're going to a gathering with a date also puts it on your game calendar.",
    { get = function() return S_().gatherCalendar ~= false end, set = function(v) K.db.settings.gatherCalendar = v end })
  card:Note("Public gatherings reach Kinship users of your own faction near you, and travel further as people meet. "
    .. "Each stranger can have three on your board at most, and anyone you ignore disappears from it.")
end })
