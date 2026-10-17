-- Kinship RP: letters by post. A sealed letter waits in your Outbox
-- (Letters.lua) until you open a mailbox, then goes as real game mail, so it
-- reaches people who are offline, and your own characters too. Kinship on the
-- other end recognises it in the inbox, marks it with a seal, and keeps it on
-- the Letters page; anyone without Kinship simply reads an ordinary mail.
--
-- Each mail is one part of a letter:
--   subject  "Sealed letter: <title>"  ("Sealed letter (2/3): <title>" for longer ones)
--   body     the words, the signature on the last part, and a last line
--            {kinship:<wax>:<crest>:<part>/<parts>:<id>}
-- Game mail holds less than a Kinship letter, so longer letters go in parts,
-- joined back into one letter when they arrive.

local ADDON, ns = ...
local K = ns.K
local UI = K.UI
local L = K.Letters
local P = {}
K.Post = P

local SUBJECT = "Sealed letter"
local TAG_PATTERN = "{kinship:(%a+):([%w_%-]+):(%d+)/(%d+):(%x+)}%s*$"
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

local function CrestName(crest)
  if crest == "monogram" then return "monogram" end
  if type(crest) ~= "string" then return "-" end
  return (crest:gsub("^[Ii]nterface\\[Ii]cons\\", ""))
end

local function CrestFrom(name)
  if name == "monogram" then return "monogram" end
  if name == "-" or name == "" then return nil end
  return L.ValidCrest("Interface\\Icons\\" .. name)
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
  local tag = function(i, n)
    return ("{kinship:%s:%s:%d/%d:%s}"):format(letter.seal or "crimson", CrestName(letter.crest), i, n, mid)
  end
  local room = bodyMax - #tag(MAX_PARTS, MAX_PARTS) - 2
  local sign = (letter.sign or "") ~= "" and ("\n\n— " .. letter.sign) or ""
  local pieces = Cut(letter.body or "", room)
  -- The signature goes on the last part, or one of its own if it won't fit
  if #pieces[#pieces] + #sign > room then pieces[#pieces + 1] = "" end
  pieces[#pieces] = pieces[#pieces] .. sign
  while #pieces > MAX_PARTS do table.remove(pieces, MAX_PARTS) end   -- never happens at sensible limits
  local n = #pieces
  local out = {}
  for i, text in ipairs(pieces) do
    local subject = SUBJECT .. (n > 1 and (" (%d/%d)"):format(i, n) or "")
      .. ((letter.title or "") ~= "" and (": " .. letter.title) or "")
    out[i] = { subject = subject:sub(1, subjectMax), body = strtrim(text) .. "\n\n" .. tag(i, n) }
  end
  return out
end

-- One part of a letter, read back from a mail's text
function P.Read(subject, body)
  if type(subject) ~= "string" or subject:sub(1, #SUBJECT) ~= SUBJECT or type(body) ~= "string" then return nil end
  local wax, crest, i, n, mid = body:match(TAG_PATTERN)
  if not wax then return nil end
  local text = strtrim((body:gsub("\n*" .. TAG_PATTERN, "")))
  local title = subject:match("^" .. SUBJECT .. "[^:]*: (.+)$") or ""
  return { wax = wax, crest = crest, i = tonumber(i), n = tonumber(n), mid = mid, text = text, title = title }
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

-- The mail's words without the tag, for the game's own mail window
function P.Clean(body)
  return type(body) == "string" and strtrim((body:gsub("\n*" .. TAG_PATTERN, ""))) or body
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
  local ok, err = pcall(SendMail, Short(job.letter.to), part.subject, part.body)
  if not ok then self:Failed(tostring(err)) end
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

-- Back in the Outbox, to try again
function P:Retry(letter)
  letter.state, letter.why = "outbox", nil
  K:Fire("LETTERS")
  if self.open then self:PostAll() end
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
  e.wax, e.crest = part.wax, part.crest
  for i = 1, e.n do if not e.got[i] then return end end
  -- All of it: one letter again
  store[id] = nil
  local text, sign = P.Join(e.got, e.n)
  L:Deliver({
    id = id, dir = "in", from = sender, to = K:MyName(),
    title = L.Str(e.title or "", L.MAX_TITLE), body = L.Str(text, L.MAX_BODY), sign = L.Str(sign, L.MAX_SIGN),
    seal = L.ValidSeal(e.wax), crest = CrestFrom(e.crest),
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
  UI.Tooltip(f.post, "Post them", "Letters you seal anywhere wait in your Sent letters until you're at a mailbox. "
    .. "This sends them as game mail, so they reach people even when they're offline.")
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

function P:Paint()
  local f = self.card
  if not (f and self.open) then return end
  local waiting = #L:Outbox()
  if self.busy then
    f.status:SetText("Posting your letters...")
  elseif waiting > 0 then
    f.status:SetText(("%d %s waiting to be posted."):format(waiting, waiting == 1 and "letter" or "letters"))
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

-- The game's mail window shows the words without Kinship's tag
local function CleanOpenMail()
  local text = rawget(_G, "OpenMailBodyText")
  local frame = rawget(_G, "InboxFrame")
  if not (text and frame and frame.openMailID and GetInboxText) then return end
  local body = GetInboxText(frame.openMailID)
  if type(body) == "string" and body:find(TAG_PATTERN) then pcall(text.SetText, text, P.Clean(body)) end
end

local ev = CreateFrame("Frame")
for _, e in ipairs({ "MAIL_SHOW", "MAIL_CLOSED", "MAIL_INBOX_UPDATE", "MAIL_SEND_SUCCESS", "MAIL_FAILED" }) do
  pcall(ev.RegisterEvent, ev, e)
end
ev:SetScript("OnEvent", function(_, event, ...)
  if event == "MAIL_SHOW" then
    P.open = true
    if not P.hooked then
      P.hooked = true
      if rawget(_G, "InboxFrame_Update") then hooksecurefunc("InboxFrame_Update", function() K.Try("post inbox", MarkInbox) end) end
      if rawget(_G, "OpenMail_Update") then hooksecurefunc("OpenMail_Update", function() K.Try("post open", CleanOpenMail) end) end
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
  elseif event == "MAIL_SEND_SUCCESS" then
    if P.sending then P:Sent() end
  elseif event == "MAIL_FAILED" then
    if P.sending then P:Failed() end
  end
end)

-- The error the game shows when a mail fails ("Cannot find player", "Not enough money"...)
local errs = CreateFrame("Frame")
pcall(errs.RegisterEvent, errs, "UI_ERROR_MESSAGE")
errs:SetScript("OnEvent", function(_, _, _, message)
  if P.sending and type(message) == "string" then P.lastError = message end
end)
local failed = P.Failed
function P:Failed(why)
  failed(self, why or self.lastError)
  self.lastError = nil
end

K:On("LETTERS", function() P:Paint() end)
