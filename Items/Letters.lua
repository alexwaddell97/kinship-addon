-- Kinship RP: letters. Write a letter and seal it in wax: it waits in your
-- Outbox until you next open a mailbox, then goes as real game mail (Post.lua),
-- so it reaches people who are offline. The recipient's Kinship finds it in
-- their inbox and gives them a sealed letter to open; anyone without Kinship
-- reads an ordinary mail.
-- Letters from earlier versions of Kinship came by courier (an addon
-- whisper) and still arrive that way:
--   L  a letter          A  "it arrived" (sent back by the recipient)

local ADDON, ns = ...
local K = ns.K
local UI = K.UI
local Safe = K.Safe
local L = {}
K.Letters = L

local PREFIX = "KinshipLtr"
L.MAX_TITLE, L.MAX_BODY, L.MAX_SIGN = 60, 2000, 60
local BOX_MAX = 200
local RECV_LIMIT, RECV_WINDOW = 5, 600

local function Short(n) return Ambiguate and Ambiguate(n, "none") or n end
local function Str(v, max) return type(v) == "string" and v:sub(1, max) or "" end

-- Seal crests: an icon from the game's icon folder, or Kinship's monogram.
local function ValidCrest(path)
  if path == "monogram" then return path end
  if type(path) ~= "string" or #path > 120 then return nil end
  return path:lower():find("^interface\\icons\\[%w_]+$") and path or nil
end
function L.CrestTexture(crest) return crest == "monogram" and K.ICON or crest end
local function ValidSeal(key)
  for _, s in ipairs(UI.SEAL_COLORS) do if s.key == key then return key end end
  return "crimson"
end

function K:LetterBox()
  local key = self:CharKey()
  self.db.letters[key] = self.db.letters[key] or { list = {} }
  return self.db.letters[key].list
end

function L:Find(id)
  for i, l in ipairs(K:LetterBox()) do if l.id == id then return l, i end end
end

function L:Unread()
  local n = 0
  for _, l in ipairs(K:LetterBox()) do
    if l.dir == "in" and not l.read and not K:IsIgnored(l.from) then n = n + 1 end
  end
  return n
end

local function Store(letter)
  local box = K:LetterBox()
  table.insert(box, 1, letter)
  while #box > BOX_MAX do table.remove(box) end
  K:Fire("LETTERS", letter)
end

---------------------------------------------------------------------------
-- Sending
---------------------------------------------------------------------------
local function Post(target, msg, priority)
  if not AddOn_Chomp or not L.ready then return false end
  if C_ChatInfo and C_ChatInfo.InChatMessagingLockdown and C_ChatInfo.InChatMessagingLockdown() then return false end
  local ok = pcall(AddOn_Chomp.SmartAddonMessage, PREFIX, msg, "WHISPER", target, { serialize = true, priority = priority or "MEDIUM" })
  return ok
end

-- Returns the letter, or nil and a reason.
function L:Send(to, title, body, sign, seal, crest)
  to = strtrim(to or "")
  body = strtrim(body or "")
  if to == "" then return nil, "Who is the letter for?" end
  if body == "" then return nil, "The letter is empty." end
  if K.NameKey(to) == K.NameKey(K:MyName()) then return nil, "You can't send a letter to yourself." end
  local me, now = K:MyName(), time()
  local letter = {
    id = ("%s-%d-%d"):format(me, now, math.random(1000, 9999)), dir = "out",
    -- A short id for the post: it rides in the mail itself
    mid = ("%x%04x"):format(now, math.random(0, 65535)),
    from = me, to = to, title = Str(strtrim(title or ""), L.MAX_TITLE), body = Str(body, L.MAX_BODY),
    sign = Str(strtrim(sign or ""), L.MAX_SIGN), seal = ValidSeal(seal), crest = ValidCrest(crest),
    place = K:CurrentPlace(), t = now, read = true, state = "outbox",
  }
  Store(letter)
  return letter
end

-- Letters waiting to be posted, oldest first
function L:Outbox()
  local out = {}
  for _, l in ipairs(K:LetterBox()) do
    if l.dir == "out" and l.state == "outbox" then table.insert(out, 1, l) end
  end
  return out
end

-- A letter has come in (by post or by courier): keep it, note it in the
-- Chronicle, and say so.
function L:Deliver(letter)
  Store(letter)
  K:AddEntry("letter", "A letter from " .. Short(letter.from), letter.title ~= "" and letter.title or nil)
  UI.Toast({
    icon = L.CrestTexture(letter.crest) or K.ICON, round = letter.crest ~= nil and letter.crest ~= "monogram",
    title = "A letter has arrived",
    text = ("From |cffffffff%s|r%s"):format(Short(letter.from), letter.title ~= "" and (": " .. UI.Escape(letter.title)) or ""),
    color = UI.SealColor(letter.seal),
    sound = "TELL_MESSAGE",
    duration = 10,
    onClick = function() L:Open(letter) end,
  })
end

-- Who's let through (Settings > Letters: only from my Kin)
function L.Allowed(sender)
  if K.db.settings.lettersFrom ~= "kin" then return true end
  return K:KinFor(sender) ~= nil or K:KinFor(Short(sender)) ~= nil
end
L.Str, L.ValidSeal, L.ValidCrest = Str, ValidSeal, ValidCrest

---------------------------------------------------------------------------
-- Receiving
---------------------------------------------------------------------------
L.recv = {}


function L:Receive(msg, sender)
  if type(msg) ~= "table" or not Safe(sender) or type(sender) ~= "string" then return end
  local from = K.NameKey(sender)
  if not from or from == K.NameKey(K:MyName()) or K:IsIgnored(sender) then return end

  if msg.k == "A" and type(msg.id) == "string" then
    local l = self:Find(msg.id)
    if l and l.dir == "out" and K.NameKey(l.to) == from then
      l.state = "delivered"
      K:Fire("LETTERS")
    end
    return
  end
  if msg.k ~= "L" or type(msg.id) ~= "string" or #msg.id > 100 then return end
  if self:Find(msg.id) then Post(sender, { k = "A", id = msg.id }, "LOW") return end
  if not L.Allowed(sender) then return end

  local now = GetTime()
  local r = self.recv[from]
  if not r or now - r.start > RECV_WINDOW then r = { start = now, n = 0 }; self.recv[from] = r end
  r.n = r.n + 1
  if r.n > RECV_LIMIT then return end

  local body = Str(msg.body, L.MAX_BODY)
  if strtrim(body) == "" then return end
  local letter = {
    id = msg.id, dir = "in", from = sender, to = K:MyName(),
    title = Str(msg.title, L.MAX_TITLE), body = body, sign = Str(msg.sign, L.MAX_SIGN),
    seal = ValidSeal(msg.seal), crest = ValidCrest(msg.crest), place = Str(msg.place, 60),
    t = time(), sent = type(msg.t) == "number" and msg.t or nil, read = false, state = "received",
  }
  Post(sender, { k = "A", id = msg.id }, "LOW")
  self:Deliver(letter)
end

---------------------------------------------------------------------------
-- Opening the Letters page
---------------------------------------------------------------------------
function L:Open(letter)
  self.focus = letter
  K.Journal:Open("letters")
end

function L:Compose(to)
  self.composeTo = to and (Ambiguate and Ambiguate(to, "none") or to) or ""
  K.Journal:Open("letters")
end

function L:Delete(letter)
  local _, i = self:Find(letter.id)
  if i then table.remove(K:LetterBox(), i); K:Fire("LETTERS") end
end

K:On("LOGIN", function()
  if not AddOn_Chomp then return end
  local ok = pcall(AddOn_Chomp.RegisterAddonPrefix, PREFIX, function(_, data, channel, sender)
    if type(channel) == "string" and channel:find("^WHISPER") then K.Try("letters", L.Receive, L, data, sender) end
  end, { fullMsgOnly = true, validTypes = { table = true } })
  L.ready = ok
  -- Anything still "sending" from last session never got an answer.
  for _, l in ipairs(K:LetterBox()) do if l.state == "sending" then l.state = "unconfirmed" end end
end)
