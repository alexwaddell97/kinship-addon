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

---------------------------------------------------------------------------
-- How a letter looks: the writer's hand, and the state of the paper
---------------------------------------------------------------------------
L.HANDS = {
  { key = "plain", label = "Plain hand", file = "Fonts\\FRIZQT__.TTF", size = 14 },
  { key = "fine", label = "Fine hand", file = "Fonts\\MORPHEUS.TTF", size = 16 },
  { key = "rough", label = "Rough scrawl", file = "Fonts\\SKURRI.TTF", size = 15 },
}
L.CONDITIONS = {
  { key = "pristine", label = "Pristine" },
  { key = "aged", label = "Aged" },
  { key = "singed", label = "Singed" },
}
local HAND, COND = {}, {}
for _, h in ipairs(L.HANDS) do HAND[h.key] = h end
for _, c in ipairs(L.CONDITIONS) do COND[c.key] = c end
function L.ValidHand(k) return HAND[k] and k or "plain" end
function L.ValidCond(k) return COND[k] and k or "pristine" end
function L.HandLabel(k) return (HAND[k] or HAND.plain).label end
function L.CondLabel(k) return (COND[k] or COND.pristine).label end

-- The hand as a font, in ink (the game's own book, plain and scrawled faces)
local fonts = {}
function L.HandFont(key)
  local h = HAND[key] or HAND.plain
  if not fonts[h.key] then
    local f = CreateFont("KinshipRPHand_" .. h.key)
    f:SetFont(h.file, h.size, "")
    if not f:GetFont() then f:SetFont(STANDARD_TEXT_FONT, 14, "") end   -- the face isn't there
    local ink = UI.INK.ink
    f:SetTextColor(ink[1], ink[2], ink[3])
    f:SetShadowOffset(0, 0)
    fonts[h.key] = f
  end
  return fonts[h.key]
end

-- The same letter always looks the same: a little number from its id places the marks.
local function Seed(s)
  local n = 7
  s = tostring(s or "")
  for i = 1, #s do n = (n * 31 + s:byte(i)) % 2147483647 end
  return n
end

-- The paper's condition, drawn into the paper itself: yellowed with age, or scorched.
function L.Stain(paper, cond, seed)
  paper.stains = paper.stains or {}
  paper.burns = paper.burns or {}
  for _, t in ipairs(paper.stains) do t:Hide() end
  for _, t in ipairs(paper.burns) do t:Hide() end
  if paper.tint then paper.tint:Hide() end
  cond = L.ValidCond(cond)
  if cond == "pristine" then return end
  local w, h = paper:GetWidth(), paper:GetHeight()
  if not w or w < 40 then return end
  local state = Seed(seed) + 1
  local function rnd()
    state = (state * 1103515245 + 12345) % 2147483648
    return state / 2147483648
  end

  -- Edges that darken toward the rim: scorched, or browned with age
  local function Edges(size, r, g, b, a)
    local sides = {
      { "TOPLEFT", "TOPRIGHT", nil, size, "VERTICAL", false },
      { "BOTTOMLEFT", "BOTTOMRIGHT", nil, size, "VERTICAL", true },
      { "TOPLEFT", "BOTTOMLEFT", size, nil, "HORIZONTAL", true },
      { "TOPRIGHT", "BOTTOMRIGHT", size, nil, "HORIZONTAL", false },
    }
    for i, sd in ipairs(sides) do
      local t = paper.burns[i]
      if not t then
        t = paper:CreateTexture(nil, "BORDER", nil, 2)
        t:SetTexture("Interface\\Buttons\\WHITE8X8")
        paper.burns[i] = t
      end
      t:ClearAllPoints()
      t:SetPoint(sd[1])
      t:SetPoint(sd[2])
      if sd[3] then t:SetWidth(sd[3]) else t:SetHeight(sd[4]) end
      local dark, clear = CreateColor(r, g, b, a), CreateColor(r, g, b, 0)
      if sd[6] then t:SetGradient(sd[5], dark, clear) else t:SetGradient(sd[5], clear, dark) end
      t:Show()
    end
  end

  -- Soft-edged patches (Kinship's own pool texture), for burnt corners
  local used = 0
  local function Patch(x, y, pw, ph, r, g, b, a)
    used = used + 1
    local t = paper.stains[used]
    if not t then
      t = paper:CreateTexture(nil, "BORDER", nil, 1)
      t:SetTexture(K.MEDIA .. "StageFloor")
      paper.stains[used] = t
    end
    t:ClearAllPoints()
    t:SetSize(pw, ph)
    t:SetPoint("CENTER", paper, "TOPLEFT", x, -y)
    t:SetVertexColor(r, g, b, a)
    t:Show()
  end

  if cond == "singed" then
    Edges(26, 0.22, 0.11, 0.03, 0.55)
    for _, c in ipairs({ { 0, 0 }, { w, 0 }, { 0, h }, { w, h } }) do
      if rnd() < 0.75 then
        local s = 60 + rnd() * 60
        Patch(c[1], c[2], s, s * 0.8, 0.20, 0.10, 0.03, 0.45)
      end
    end
  elseif cond == "aged" then
    -- Yellowed all over, browning gently at the edges
    if not paper.tint then
      paper.tint = paper:CreateTexture(nil, "BORDER", nil, 0)
      paper.tint:SetAllPoints()
    end
    paper.tint:SetColorTexture(0.62, 0.48, 0.20, 0.16)
    paper.tint:Show()
    Edges(34, 0.42, 0.28, 0.10, 0.32)
  end
end

---------------------------------------------------------------------------
-- Ciphers: a key word shifts each letter A-Z along the alphabet (a Vigenere
-- cipher); everything else is left as it is. The key never travels: a short
-- check of the true words does, so the right key can be recognised.
---------------------------------------------------------------------------
function L.CleanKey(key) return (tostring(key or ""):lower():gsub("[^a-z]", "")) end

local function Shift(text, key, dir)
  key = L.CleanKey(key)
  if key == "" then return text end
  local i = 0
  return (text:gsub("%a", function(ch)
    local b = ch:byte()
    local base = b >= 97 and 97 or 65
    i = i % #key + 1
    return string.char((b - base + dir * (key:byte(i) - 97)) % 26 + base)
  end))
end
function L.Encipher(text, key) return Shift(text, key, 1) end
function L.Decipher(text, key) return Shift(text, key, -1) end
-- Spacing is left out: a long letter's parts are rejoined with plain spaces.
function L.CipherCheck(text)
  local n = 0
  text = text:gsub("%s", "")
  for i = 1, #text do n = (n * 33 + text:byte(i)) % 65536 end
  return ("%04x"):format(n)
end

-- Try a key on a letter in cipher. True, and the letter's words revealed, if it's right.
function L:TryKey(letter, key)
  if not (letter and letter.cipher and not letter.solved) then return false end
  local plain = L.Decipher(letter.body, key)
  if L.CipherCheck(plain) ~= letter.cipher then return false end
  letter.body, letter.solved = plain, true
  K:Fire("LETTERS")
  return true
end

-- Returns the letter, or nil and a reason.
-- opts: { hand = "fine", cond = "rain", key = "a key word" for a cipher }
function L:Send(to, title, body, sign, seal, crest, opts)
  opts = opts or {}
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
    hand = L.ValidHand(opts.hand), cond = L.ValidCond(opts.cond),
  }
  local key = L.CleanKey(opts.key)
  if key ~= "" then letter.key, letter.cipher = key, L.CipherCheck(letter.body) end
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
