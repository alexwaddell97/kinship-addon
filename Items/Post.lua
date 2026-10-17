-- Kinship RP: letters by post. A sealed letter waits in your Outbox
-- (Letters.lua) until you open a mailbox, then goes as real game mail, so it
-- reaches people who are offline, and your own characters too. Kinship on the
-- other end recognises it in the inbox, marks it with a seal, and shows it as
-- a letter; anyone without Kinship reads an ordinary mail.
--
-- Each mail is one part of a letter:
--   subject  "Sealed letter: <title>"  ("Sealed letter (2/3): <title>" for longer ones)
--   body     the words, the signature on the last part, and a postmark that
--            reads naturally to anyone without Kinship:
--            ~ Sealed in teal wax · house crest · fine hand · rain-soaked · Kinship letter 6ad3e835064c ~
--            (a plain hand, pristine paper and no cipher are left out; a cipher adds "in cipher 4f2a")
-- The crest itself isn't sent: "house crest" is looked up from the sender's
-- profile, "Kinship seal" is the monogram. Game mail holds less than a
-- Kinship letter, so longer letters go in parts, joined back when they arrive.

local ADDON, ns = ...
local K = ns.K
local UI = K.UI
local L = K.Letters
local P = {}
K.Post = P

local SUBJECT = "Sealed letter"
local DOT = " \194\183 "   -- " · "
local POSTMARK = "~ Sealed in (%a+) wax(.-)" .. DOT .. "Kinship letter (%x+) ~%s*$"
local MAX_PARTS = 9

local function Short(n) return Ambiguate and Ambiguate(n or "?", "none") or (n or "?") end

-- How much the game lets a mail hold
local function Limits()
  local body, subject = 500, 64
  local b, s = rawget(_G, "SendMailBodyEditBox"), rawget(_G, "SendMailSubjectEditBox")
  if b and b.GetMaxLetters then
    local n = b:GetMaxLetters()
    if n and n > 0 then body = n end
  end
  if s and s.GetMaxLetters then
    local n = s:GetMaxLetters()
    if n and n > 0 then subject = n end
  end
  return body, subject
end

-- The postmark's words for how a letter looks, and back
local function Marks(letter)
  local out = {}
  if letter.crest == "monogram" then out[#out + 1] = "Kinship seal"
  elseif letter.crest then out[#out + 1] = "house crest" end
  if (letter.hand or "plain") ~= "plain" then out[#out + 1] = L.HandLabel(letter.hand):lower() end
  if (letter.cond or "pristine") ~= "pristine" then out[#out + 1] = L.CondLabel(letter.cond):lower() end
  if letter.cipher then out[#out + 1] = "in cipher " .. letter.cipher end
  return out
end

local function ReadMarks(text)
  local m = {}
  for word in (text .. DOT):gmatch("(.-)" .. DOT) do
    word = strtrim(word)
    if word == "Kinship seal" then m.crest = "monogram"
    elseif word == "house crest" then m.crest = "house"
    elseif word:match("^in cipher %x+$") then m.cipher = word:match("(%x+)$")
    elseif word ~= "" then
      for _, h in ipairs(L.HANDS) do if h.label:lower() == word then m.hand = h.key end end
      for _, c in ipairs(L.CONDITIONS) do if c.label:lower() == word then m.cond = c.key end end
    end
  end
  return m
end

function P.Postmark(letter, mid)
  local marks = Marks(letter)
  return ("~ Sealed in %s wax%s%sKinship letter %s ~"):format(letter.seal or "crimson",
    #marks > 0 and (DOT .. table.concat(marks, DOT)) or "", DOT, mid)
end

-- Cut text into pieces of at most `room` letters, at a space or line break where it can.
local function Cut(text, room)
  local out = {}
  while #text > room do
    local piece = text:sub(1, room)
    local at = piece:match(".*()[%s]") or room + 1
    if at < room * 0.6 then at = room + 1 end   -- no handy space: cut where it falls
    out[#out + 1] = strtrim(text:sub(1, at - 1))
    text = strtrim(text:sub(at))
  end
  if text ~= "" or #out == 0 then out[#out + 1] = text end
  return out
end

-- A letter as the mails that carry it: { { subject, body }, ... }
function P.Parts(letter, bodyMax, subjectMax)
  local mid = letter.mid or ("%x%04x"):format(letter.t or time(), 0)
  local mark = P.Postmark(letter, mid)
  local room = bodyMax - #mark - 2
  local sign = (letter.sign or "") ~= "" and ("\n\n— " .. letter.sign) or ""
  -- A letter in cipher goes enciphered; only its writer keeps the key
  local words = letter.key and L.Encipher(letter.body or "", letter.key) or (letter.body or "")
  local pieces = Cut(words, room)
  -- The signature goes on the last part, or one of its own if it won't fit
  if #pieces[#pieces] + #sign > room then pieces[#pieces + 1] = "" end
  pieces[#pieces] = pieces[#pieces] .. sign
  while #pieces > MAX_PARTS do table.remove(pieces, MAX_PARTS) end   -- never happens at sensible limits
  local n = #pieces
  local out = {}
  for i, text in ipairs(pieces) do
    local subject = SUBJECT .. (n > 1 and (" (%d/%d)"):format(i, n) or "")
      .. ((letter.title or "") ~= "" and (": " .. letter.title) or "")
    out[i] = { subject = subject:sub(1, subjectMax), body = strtrim(text) .. "\n\n" .. mark }
  end
  return out
end

-- One part of a letter, read back from a mail's subject and text
function P.Read(subject, body)
  if type(subject) ~= "string" or subject:sub(1, #SUBJECT) ~= SUBJECT or type(body) ~= "string" then return nil end
  local wax, marks, mid = body:match(POSTMARK)
  if not wax then return nil end
  local m = ReadMarks(marks)
  local i, n = subject:match("^" .. SUBJECT .. " %((%d+)/(%d+)%)")
  local text = strtrim((body:gsub("\n*" .. POSTMARK, "")))
  local title = subject:match("^" .. SUBJECT .. "[^:]*: (.+)$") or ""
  return { wax = wax, crest = m.crest, hand = m.hand, cond = m.cond, cipher = m.cipher,
           i = tonumber(i) or 1, n = tonumber(n) or 1, mid = mid, text = text, title = title }
end

-- A letter's parts (their words, in order) back into its text and signature.
-- The signature is the last part's last line; the parts were cut at spaces.
function P.Join(got, n)
  local parts = {}
  for i = 1, n do parts[i] = got[i] or "" end
  local sign = ""
  local before, s = parts[n]:match("^(.-)\n\n— ([^\n]*)$")
  if not before then
    s = parts[n]:match("^— ([^\n]*)$")
    if s then before = "" end
  end
  if before then parts[n], sign = before, s end
  return strtrim(table.concat(parts, " ")), sign
end

-- The mail's words without the postmark, for the game's own mail window
function P.Clean(body)
  return type(body) == "string" and strtrim((body:gsub("\n*" .. POSTMARK, ""))) or body
end

-- The sender's crest, for a letter sealed with their house crest
local function HouseCrestOf(sender)
  local e = K.Registry and K.Registry[K.NameKey(sender) or ""]
  local crest = e and e.profile and e.profile.crest
  return crest and L.ValidCrest(crest) or "monogram"
end

---------------------------------------------------------------------------
-- Posting, one mail at a time, at a mailbox
---------------------------------------------------------------------------
P.jobs = {}

-- Something already set out on the Send Mail tab (an item, money, COD) would
-- go with our mail, so we wait for it to be cleared.
local function SendTabBusy()
  if (GetSendMailMoney and GetSendMailMoney() or 0) > 0 then return true end
  if (GetSendMailCOD and GetSendMailCOD() or 0) > 0 then return true end
  for i = 1, (rawget(_G, "ATTACHMENTS_MAX_SEND") or 12) do
    if GetSendMailItem and GetSendMailItem(i) then return true end
  end
  return false
end

function P:PostAll()
  if not self.open then K:Print("Letters are posted at a mailbox.") return end
  if self.busy then return end
  local waiting = L:Outbox()
  if #waiting == 0 then return end
  if SendTabBusy() then
    K:Print("Clear the Send Mail tab first (items, money or COD would go with your letters).")
    return
  end
  local bodyMax, subjectMax = Limits()
  wipe(self.jobs)
  for _, l in ipairs(waiting) do
    self.jobs[#self.jobs + 1] = { letter = l, parts = P.Parts(l, bodyMax, subjectMax), i = 1 }
  end
  self.busy = true
  self:Next()
end

function P:Next()
  local job = self.jobs[1]
  if not job then
    self.busy = false
    self:Paint()
    return
  end
  local part = job.parts[job.i]
  self.sending = job
  self.lastError = nil
  local ok, err = pcall(SendMail, Short(job.letter.to), part.subject, part.body)
  if not ok then self:Failed(tostring(err)) return end
  -- Some clients never say a mail went, only when one didn't. So: no mail
  -- error within a few seconds means it's on its way (a "sent" signal, where
  -- there is one, moves things along sooner).
  local mine = job.i
  C_Timer.After(3, function()
    if self.sending ~= job or job.i ~= mine then return end
    if self.lastError then self:Failed(self.lastError) else self:Sent() end
  end)
end

function P:Sent()
  local job = self.sending
  if not job then return end
  self.sending = nil
  job.i = job.i + 1
  if job.i > #job.parts then
    job.letter.state = "posted"
    job.letter.posted = time()
    job.letter.parts = #job.parts
    table.remove(self.jobs, 1)
    K:Print(("Posted your letter to %s%s."):format(Short(job.letter.to),
      #job.parts > 1 and (" in %d parts"):format(#job.parts) or ""))
    K:Fire("LETTERS")
  end
  C_Timer.After(0.4, function() self:Next() end)
end

function P:Failed(why)
  local job = self.sending
  self.sending = nil
  if job then
    job.letter.state = "failed"
    job.letter.why = why
    K:Print(("Couldn't post your letter to %s%s"):format(Short(job.letter.to), why and why ~= "" and (": " .. why) or "."))
    K:Fire("LETTERS")
  end
  -- The rest stay in the Outbox for another try
  wipe(self.jobs)
  self.busy = false
  self:Paint()
end

-- Back in the Outbox, to try again (posted, like the rest, only with Post them)
function P:Retry(letter)
  letter.state, letter.why = "outbox", nil
  K:Fire("LETTERS")
  K:Print("Back with your letters to post. Press Post them at a mailbox to send it.")
end

---------------------------------------------------------------------------
-- Letters arriving in the inbox
---------------------------------------------------------------------------
local function Parts()
  local key = K:CharKey()
  K.db.letterParts = K.db.letterParts or {}
  K.db.letterParts[key] = K.db.letterParts[key] or {}
  return K.db.letterParts[key]
end

-- A part read from the inbox: kept until the whole letter is here.
function P:Take(sender, part)
  if not (sender and part) or K:IsIgnored(sender) or not L.Allowed(sender) then return end
  local id = ("post:%s:%s"):format(K.NameKey(sender) or sender, part.mid)
  if L:Find(id) then return end
  local store = Parts()
  local e = store[id] or { from = sender, n = part.n, got = {}, t = time() }
  store[id] = e
  e.got[part.i] = part.text
  e.title = e.title or (part.title ~= "" and part.title or nil)
  e.wax, e.crest, e.hand, e.cond, e.cipher = part.wax, part.crest, part.hand, part.cond, part.cipher
  for i = 1, e.n do if not e.got[i] then return end end
  -- All of it: one letter again
  store[id] = nil
  local text, sign = P.Join(e.got, e.n)
  L:Deliver({
    id = id, dir = "in", from = sender, to = K:MyName(),
    title = L.Str(e.title or "", L.MAX_TITLE), body = L.Str(text, L.MAX_BODY), sign = L.Str(sign, L.MAX_SIGN),
    seal = L.ValidSeal(e.wax), crest = e.crest == "house" and HouseCrestOf(sender) or e.crest,
    hand = L.ValidHand(e.hand), cond = L.ValidCond(e.cond), cipher = e.cipher,
    t = time(), read = false, state = "received", post = true,
  })
end

-- Read every Kinship letter in the inbox that's been opened, and the other
-- parts of any letter you've just opened.
function P:Scan()
  if not (GetInboxNumItems and GetInboxHeaderInfo and GetInboxText) then return end
  local opened = {}
  local n = GetInboxNumItems() or 0
  for i = 1, n do
    local _, _, sender, subject, _, _, _, _, wasRead = GetInboxHeaderInfo(i)
    if sender and type(subject) == "string" and subject:sub(1, #SUBJECT) == SUBJECT and wasRead then
      local part = P.Read(subject, GetInboxText(i))
      if part then
        self:Take(sender, part)
        opened[sender .. "\0" .. part.mid] = part.n
      end
    end
  end
  -- Its other parts, so the letter comes together in one go
  for i = 1, n do
    local _, _, sender, subject, _, _, _, _, wasRead = GetInboxHeaderInfo(i)
    if sender and not wasRead and type(subject) == "string" and subject:match("^" .. SUBJECT .. " %(%d+/%d+%)") then
      for key in pairs(opened) do
        if key:sub(1, #sender + 1) == sender .. "\0" then
          local part = P.Read(subject, GetInboxText(i))
          if part then self:Take(sender, part) end
          break
        end
      end
    end
  end
end

-- The letter behind the mail open in the game's mail window, if it's one of ours
function P:OpenLetter()
  local frame = rawget(_G, "InboxFrame")
  local index = frame and frame.openMailID
  if not (index and GetInboxHeaderInfo) then return nil end
  local _, _, sender, subject = GetInboxHeaderInfo(index)
  local part = sender and P.Read(subject, GetInboxText(index))
  return part and L:Find(("post:%s:%s"):format(K.NameKey(sender) or sender, part.mid)) or nil
end

---------------------------------------------------------------------------
-- At the mailbox: a small card beside the mail window
---------------------------------------------------------------------------
function P:Build()
  if self.card then return self.card end
  local mf = rawget(_G, "MailFrame")
  if not mf then return nil end
  local f = UI.Panel(mf)
  f:SetSize(220, 172)
  f:SetPoint("TOPLEFT", mf, "TOPRIGHT", 6, 0)
  f:SetFrameStrata(mf:GetFrameStrata())
  f:SetFrameLevel(mf:GetFrameLevel() + 5)
  self.card = f
  local mono = f:CreateTexture(nil, "ARTWORK")
  mono:SetTexture(K.ICON)
  mono:SetSize(22, 22)
  mono:SetPoint("TOPLEFT", 14, -12)
  local head = UI.Text(f, "Kinship letters", "Header", "heading")
  head:SetPoint("LEFT", mono, "RIGHT", 6, 0)
  f.status = UI.Text(f, "", "Small", "text", 192)
  f.status:SetPoint("TOPLEFT", 14, -44)
  f.status:SetSpacing(2)
  f.post = UI.Button(f, "Post them", 192, 24)
  f.post:SetPoint("TOPLEFT", f.status, "BOTTOMLEFT", 0, -10)   -- follows the text, however many lines
  f.post:SetScript("OnClick", function() P:PostAll() end)
  UI.Tooltip(f.post, "Post them", "Sends your sealed letters as game mail, so they reach people even when they're "
    .. "offline. Each mail costs the usual postage, shown above. Nothing is posted until you press this.")
  f.write = UI.Button(f, "Write a letter", 192, 24)
  f.write:SetPoint("TOPLEFT", f.post, "BOTTOMLEFT", 0, -6)
  f.write:SetScript("OnClick", function() L:Compose("") end)
  f.read = UI.Button(f, "Read it as a letter", 192, 24)
  f.read:SetPoint("TOPLEFT", f.write, "BOTTOMLEFT", 0, -6)
  f.read:SetScript("OnClick", function()
    local l = P:OpenLetter()
    if l then L:Open(l) end
  end)
  UI.Tooltip(f.read, "Read it as a letter", "Open this letter in Kinship, sealed, as it was sent.")
  return f
end

-- How many mails the Outbox makes, and what posting them costs
function P:Postage()
  local bodyMax, subjectMax = Limits()
  local mails = 0
  for _, l in ipairs(L:Outbox()) do mails = mails + #P.Parts(l, bodyMax, subjectMax) end
  local each = (GetSendMailPrice and GetSendMailPrice()) or 30
  if not each or each <= 0 then each = 30 end
  return mails, mails * each
end

local function Money(copper)
  if GetCoinTextureString then return GetCoinTextureString(copper) end
  return ("%dc"):format(copper)
end

function P:Paint()
  local f = self.card
  if not (f and self.open) then return end
  local waiting = #L:Outbox()
  if self.busy then
    f.status:SetText("Posting your letters...")
  elseif waiting > 0 then
    local mails, cost = self:Postage()
    f.status:SetText(("%d %s waiting to be posted.\nPostage: %s%s"):format(waiting, waiting == 1 and "letter" or "letters",
      Money(cost), mails > waiting and (" (%d mails)"):format(mails) or ""))
  else
    f.status:SetText("Nothing waiting to be posted.")
  end
  f.post:SetEnabled(waiting > 0 and not self.busy)
  f.read:SetShown(self:OpenLetter() ~= nil)
  -- Tall enough for the text and the buttons beneath it
  local h = 44 + math.ceil(f.status:GetStringHeight()) + 10 + 24 + 6 + 24 + 14
  if f.read:IsShown() then h = h + 30 end
  f:SetHeight(h)
end

-- Kinship letters in the inbox list wear the Kinship seal
local function MarkInbox()
  local frame = rawget(_G, "InboxFrame")
  local per = rawget(_G, "INBOXITEMS_TO_DISPLAY") or 7
  if not (frame and GetInboxHeaderInfo) then return end
  local first = ((frame.pageNum or 1) - 1) * per
  for i = 1, per do
    local icon = _G["MailItem" .. i .. "ButtonIcon"]
    local _, _, sender, subject = GetInboxHeaderInfo(first + i)
    if icon and sender and type(subject) == "string" and subject:sub(1, #SUBJECT) == SUBJECT then
      icon:SetTexture(K.ICON)
    end
  end
end

-- A Kinship letter opened in the mailbox: a sheet of Kinship paper over the
-- mail's own text, sealed until you break the seal, then the letter itself.
local PAPER, PAPER_EDGE, PAPER_RULE = { 0.955, 0.925, 0.850 }, { 0.30, 0.20, 0.08, 0.40 }, { 0.45, 0.32, 0.15, 0.16 }

function P:Sheet()
  if self.sheet then return self.sheet end
  local om = rawget(_G, "OpenMailFrame")
  if not om then return nil end
  local area = rawget(_G, "OpenMailScrollFrame") or om
  local w, h = area:GetWidth(), area:GetHeight()
  if not w or w < 120 then w, h = 300, 260 end
  w, h = math.floor(w + 22), math.floor(h + 8)
  local s = CreateFrame("Frame", nil, om)
  s:SetSize(w, h)
  s:SetPoint("TOPLEFT", area, "TOPLEFT", -4, 4)   -- over its scroll bar too
  s:SetFrameLevel((area.GetFrameLevel and area:GetFrameLevel() or om:GetFrameLevel()) + 10)
  s:EnableMouse(true)
  s.bg = s:CreateTexture(nil, "BACKGROUND")
  s.bg:SetAllPoints()
  s.bg:SetColorTexture(PAPER[1], PAPER[2], PAPER[3], 1)
  UI.Border(s, PAPER_EDGE)
  local rule = CreateFrame("Frame", nil, s)
  rule:SetPoint("TOPLEFT", 7, -7)
  rule:SetPoint("BOTTOMRIGHT", -7, 7)
  UI.Border(rule, PAPER_RULE)
  local IW = w - 36

  -- Sealed
  local sealed = CreateFrame("Frame", nil, s)
  sealed:SetAllPoints()
  s.sealed = sealed
  sealed.from = UI.Text(sealed, "A letter from", "Small", "inkSubtle")
  sealed.from:SetPoint("TOP", 0, -22)
  sealed.name = UI.Text(sealed, "", "Title", "inkHeading", IW)
  sealed.name:SetPoint("TOP", sealed.from, "BOTTOM", 0, -4)
  sealed.name:SetJustifyH("CENTER")
  sealed.title = UI.Text(sealed, "", "QuestFont", "inkSubtle", IW)
  sealed.title:SetPoint("TOP", sealed.name, "BOTTOM", 0, -6)
  sealed.title:SetJustifyH("CENTER")
  sealed.seal = UI.Seal(sealed, math.min(76, math.floor(h * 0.3)))
  sealed.seal:SetPoint("CENTER", 0, -12)
  sealed.open = UI.Button(sealed, "Break the seal", 140, 26)
  sealed.open:SetPoint("BOTTOM", 0, 18)
  sealed.open:SetScript("OnClick", function() P:BreakSeal() end)

  -- Open
  local open = CreateFrame("Frame", nil, s)
  open:SetAllPoints()
  s.open = open
  open.title = UI.Text(open, "", "Header", "inkHeading", IW)
  open.title:SetPoint("TOPLEFT", 18, -16)
  open.title:SetWordWrap(false)
  open.body = UI.ReadArea(open, IW + 6, h - 40 - 62, "QuestFont", "ink")
  open.body:SetPoint("TOPLEFT", 18, -38)
  open.sign = UI.Text(open, "", "QuestFont", "inkAccent", IW - 50)
  open.sign:SetPoint("BOTTOMRIGHT", -18, 18)
  open.sign:SetJustifyH("RIGHT")
  open.seal = UI.Seal(open, 34)
  open.seal:SetPoint("BOTTOMLEFT", 14, 12)
  open.decipher = UI.Button(open, "Decipher...", 100, 22)
  open.decipher:SetPoint("BOTTOM", 0, 14)
  open.decipher:SetScript("OnClick", function() if P.sheetLetter then L:Open(P.sheetLetter) end end)
  UI.Tooltip(open.decipher, "In cipher", "It reads as nonsense without its key word. Open it on your Letters page to decipher it.")
  self.sheet = s
  return s
end

function P:BreakSeal()
  local s, l = self.sheet, self.sheetLetter
  if not (s and l) then return end
  if SOUNDKIT then PlaySound(SOUNDKIT.IG_QUEST_LIST_OPEN) end
  local seal = s.sealed.seal
  UI.Tween(seal, 1, 0.35, function(p)
    seal:SetScale(1 + 0.45 * p)
    seal:SetAlpha(1 - p)
    if p >= 1 then
      seal:SetScale(1); seal:SetAlpha(1)
      l.read = true
      K:Fire("LETTERS")
      P:ShowSheet()
      UI.FadeIn(s.open, 0.35)
    end
  end, UI.Ease.outQuart)
end

-- Show the sheet over the open mail if it's a Kinship letter; out of the way if not.
function P:ShowSheet()
  local l = self:OpenLetter()
  self.sheetLetter = l
  if not l then
    if self.sheet then self.sheet:Hide() end
    return
  end
  local s = self:Sheet()
  if not s then return end
  local crest = L.CrestTexture(l.crest)
  L.Stain(s, l.cond, l.id)
  s.sealed:SetShown(not l.read)
  s.open:SetShown(l.read and true or false)
  if not l.read then
    s.sealed.name:SetText(Short(l.from))
    s.sealed.title:SetText(l.title ~= "" and ("\"" .. UI.Escape(l.title) .. "\"") or "")
    s.sealed.seal:SetSeal(l.seal, crest)
  else
    s.open.title:SetText(l.title ~= "" and UI.Escape(l.title) or ("From " .. Short(l.from)))
    s.open.body.text:SetFontObject(L.HandFont(l.hand))
    s.open.body:SetText(UI.Escape(l.body))
    s.open.sign:SetFontObject(L.HandFont(l.hand))
    s.open.sign:SetTextColor(unpack(UI.INK.inkAccent))
    s.open.sign:SetText(l.sign ~= "" and ("— " .. UI.Escape(l.sign)) or "")
    s.open.decipher:SetShown((l.cipher and not l.solved) and true or false)
    s.open.seal:SetSeal(l.seal, crest)
  end
  s:Show()
end

-- The game's mail window shows the words without Kinship's tag
local function CleanOpenMail()
  local text = rawget(_G, "OpenMailBodyText")
  local frame = rawget(_G, "InboxFrame")
  if not (text and frame and frame.openMailID and GetInboxText) then return end
  local body = GetInboxText(frame.openMailID)
  if type(body) == "string" and body:find(POSTMARK) then pcall(text.SetText, text, P.Clean(body)) end
end

local ev = CreateFrame("Frame")
for _, e in ipairs({ "MAIL_SHOW", "MAIL_CLOSED", "MAIL_INBOX_UPDATE", "MAIL_SEND_SUCCESS", "MAIL_FAILED" }) do
  -- A client without one of these can't tell us how posting went: note it for /kin bug
  if not pcall(ev.RegisterEvent, ev, e) then K:CaughtError("post", "this client has no " .. e .. " event") end
end
ev:SetScript("OnEvent", function(_, event, ...)
  if event == "MAIL_SHOW" then
    P.open = true
    if not P.hooked then
      P.hooked = true
      if rawget(_G, "InboxFrame_Update") then hooksecurefunc("InboxFrame_Update", function() K.Try("post inbox", MarkInbox) end) end
      if rawget(_G, "OpenMail_Update") then hooksecurefunc("OpenMail_Update", function() K.Try("post open", CleanOpenMail) end) end
      local om = rawget(_G, "OpenMailFrame")
      if om then
        om:HookScript("OnShow", function()
          C_Timer.After(0, function() K.Try("post open", CleanOpenMail); K.Try("post sheet", P.ShowSheet, P) end)
        end)
        om:HookScript("OnHide", function() if P.sheet then P.sheet:Hide() end end)
      end
    end
    local f = K.Try("post card", P.Build, P) and P.card
    if f then f:Show() end
    P:Paint()
    local waiting = #L:Outbox()
    if waiting > 0 then
      K:Print(("%d %s waiting to be posted. Click Post them beside the mail window."):format(waiting,
        waiting == 1 and "letter" or "letters"))
    end
  elseif event == "MAIL_CLOSED" then
    P.open = false
    if P.busy then P:Failed("the mailbox closed") end
    if P.card then P.card:Hide() end
  elseif event == "MAIL_INBOX_UPDATE" then
    K.Try("post scan", P.Scan, P)
    P:Paint()
    -- After the game has drawn the mail it opened
    C_Timer.After(0, function()
      local om = rawget(_G, "OpenMailFrame")
      if om and om:IsShown() then K.Try("post open", CleanOpenMail); K.Try("post sheet", P.ShowSheet, P) end
    end)
  elseif event == "MAIL_SEND_SUCCESS" then
    if P.sending then P:Sent() end
  elseif event == "MAIL_FAILED" then
    if P.sending then P:Failed() end
  end
end)

-- The error the game shows when a mail fails ("Cannot find player", "Not enough money"...)
local errs = CreateFrame("Frame")
pcall(errs.RegisterEvent, errs, "UI_ERROR_MESSAGE")
local MAIL_ERRORS = {}
for _, key in ipairs({ "ERR_MAIL_TARGET_NOT_FOUND", "ERR_MAIL_TO_SELF", "ERR_MAIL_DATABASE_ERROR", "ERR_MAIL_REACHED_CAP",
                       "ERR_NOT_ENOUGH_MONEY", "ERR_PLAYER_WRONG_FACTION", "ERR_MAIL_WRONG_FACTION", "ERR_MAIL_BOUNCED",
                       "ERR_MAIL_TOO_MANY_ATTACHMENTS", "ERR_MAIL_INVALID_ATTACHMENT", "ERR_MAIL_ATTACHMENT_INVALID",
                       "ERR_MAIL_DISABLED_PERIOD", "ERR_MAIL_INTERNAL_ERROR" }) do
  local text = rawget(_G, key)
  if type(text) == "string" then MAIL_ERRORS[text] = true end
end
errs:SetScript("OnEvent", function(_, _, _, message)
  if P.sending and type(message) == "string" and (MAIL_ERRORS[message] or message:lower():find("mail")) then
    P.lastError = message
  end
end)
local failed = P.Failed
function P:Failed(why)
  failed(self, why or self.lastError)
  self.lastError = nil
end

K:On("LETTERS", function() P:Paint() end)
