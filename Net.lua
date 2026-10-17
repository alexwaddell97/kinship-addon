-- Kinship RP: a small message bus for Kinship-to-Kinship features.
--
-- One addon prefix carries every feature's messages, each tagged with a
-- "kind" (e.g. "dice", "scan", "trade"). Messages are tables, serialised and
-- split by Chomp, so they can be any size.
--
--   K.Net:On(kind, function(msg, sender, channel) ... end [, module])
--   K.Net:Send(kind, msg, channel, target)
-- A kind registered with an Extended module ("inventory", "auras", ...) is
-- neither sent nor handled while K:ExtOn(module) is false.
--
-- channel: "WHISPER" (target = name), "PARTY", "RAID" (falls back to PARTY),
--          "GUILD", or "YELL" (everyone nearby in the zone; the closest thing
--          this client has to a broadcast, and how map scans and drops work).
-- Received messages are dropped for ignored players and rate-limited per
-- sender. Whispers reach Battle.net friends on the other faction too.

local ADDON, ns = ...
local K = ns.K
local Safe = K.Safe
local N = { handlers = {}, recv = {}, gates = {} }
K.Net = N

local PREFIX = "KinshipNet"
local RECV_LIMIT, RECV_WINDOW = 60, 30   -- messages per sender per window (seconds)

function N:On(kind, fn, module)
  self.handlers[kind] = fn
  if module then self.gates[kind] = module end
end

-- Tie existing kinds to an Extended module: N:Gate({ "kindA", "kindB" }, "inventory").
function N:Gate(kinds, module) for _, k in ipairs(kinds) do self.gates[k] = module end end

function N:Allowed(kind) local m = self.gates[kind]; return m == nil or K:ExtOn(m) end

function N:Ready()
  if not AddOn_Chomp or not self.ready then return false end
  if C_ChatInfo and C_ChatInfo.InChatMessagingLockdown and C_ChatInfo.InChatMessagingLockdown() then return false end
  return true
end

-- Returns true if the message was handed to the game.
function N:Send(kind, msg, channel, target, priority)
  if not self:Ready() or type(msg) ~= "table" then return false end
  if not self:Allowed(kind) then return false end
  channel = channel or "WHISPER"
  if channel == "RAID" and not IsInRaid() then channel = "PARTY" end
  if channel == "PARTY" and not IsInGroup() then return false end
  if channel == "GUILD" and not IsInGuild() then return false end
  if channel == "WHISPER" and (type(target) ~= "string" or target == "") then return false end
  if channel ~= "WHISPER" then target = nil end
  msg.k = kind
  local ok = pcall(AddOn_Chomp.SmartAddonMessage, PREFIX, msg, channel, target,
    { serialize = true, priority = priority or "MEDIUM" })   -- Chomp takes HIGH, MEDIUM or LOW
  return ok
end

local function Receive(msg, channel, sender)
  if type(msg) ~= "table" or type(msg.k) ~= "string" then return end
  if not Safe(sender) or type(sender) ~= "string" then return end
  local key = K.NameKey(sender)
  if not key or key == K.NameKey(K:MyName()) then return end
  if K:IsIgnored(sender) then return end

  local now = GetTime()
  local r = N.recv[key]
  if not r or now - r.start > RECV_WINDOW then r = { start = now, n = 0 }; N.recv[key] = r end
  r.n = r.n + 1
  if r.n > RECV_LIMIT then return end

  local fn = N.handlers[msg.k]
  if fn and N:Allowed(msg.k) then
    local ok, err = pcall(fn, msg, sender, channel)
    if not ok then K:CaughtError("net " .. tostring(msg.k), err) end
  end
end

K:On("LOGIN", function()
  if not AddOn_Chomp then return end
  local ok = pcall(AddOn_Chomp.RegisterAddonPrefix, PREFIX, function(_, data, channel, sender)
    Receive(data, type(channel) == "string" and channel:match("^(%u+)") or channel, sender)
  end, { fullMsgOnly = true, validTypes = { table = true } })
  N.ready = ok
end)
