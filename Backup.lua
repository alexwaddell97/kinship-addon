-- Kinship RP: back up everything. One copyable code holding all of Kinship's
-- saved data for this account (KinshipRPDB), and a way to restore it. The
-- Forever beta sometimes loses addon data on load, so now and then a gentle
-- reminder suggests making a fresh backup.
--
-- Code format:  KINSHIPBAK1:<flag><checksum>:<base64>
--   built like a profile code (ProfileShare.lua, whose building blocks it
--   uses): flag p = plain, z = deflate-compressed; checksum = Adler-32 of the
--   serialised table; read back with Chomp's parser, so nothing in a code is
--   ever run as Lua.
--   payload  { kind = "backup", v = 1, by, schema, t, who, data }
--            data is KinshipRPDB without the error log and backup bookkeeping
--            (and, if you choose, without other players' profiles and items).
-- Restoring replaces the saved data and reloads; the schema migrations in
-- Core.lua then bring an older backup up to date.

local ADDON, ns = ...
local K = ns.K
local UI = K.UI
local B = {}
K.Backup = B

local HEADER = "KINSHIPBAK1:"
local MAX_CODE = 6000000          -- longest code we'll read (characters)
local MAX_SHOW = 3000000          -- longest code we'll put in the text box
local MAX_DEPTH = 40
local REMIND_AFTER = 14 * 86400   -- since your last backup
local REMIND_EVERY = 7 * 86400    -- between reminders
local GOOD, BAD, WARN = { 0.40, 0.80, 0.48 }, { 0.90, 0.36, 0.30 }, { 0.95, 0.76, 0.36 }

-- Never part of a backup: they describe this install, not your roleplay.
local SKIP = { errorLog = true, backup = true }
-- Other players' profiles, items and documents you've come across. They come
-- back as you meet people again, so they can be left out to keep codes short.
local OTHERS = { registry = true, itemCache = true, docCache = true }

local function Codec() return K.ProfileShare and K.ProfileShare.Codec end
local function State()
  if type(K.db.backup) ~= "table" then K.db.backup = {} end
  return K.db.backup
end

---------------------------------------------------------------------------
-- Packing and reading codes
---------------------------------------------------------------------------
local issecret = _G.issecretvalue or function() return false end
local HUGE = math.huge

-- A copy holding plain data only: no functions, loops or broken numbers.
local function Plain(v, depth, seen)
  if issecret(v) then return nil end
  local tv = type(v)
  if tv == "string" or tv == "boolean" then return v end
  if tv == "number" then
    if v ~= v or v == HUGE or v == -HUGE then return nil end
    return v
  end
  if tv ~= "table" or depth > MAX_DEPTH or seen[v] then return nil end
  seen[v] = true
  local out = {}
  for k, x in pairs(v) do
    local tk = type(k)
    if not issecret(k) and (tk == "string" or (tk == "number" and k == k and k ~= HUGE and k ~= -HUGE)) then
      local cx = Plain(x, depth + 1, seen)
      if cx ~= nil then out[k] = cx end
    end
  end
  seen[v] = nil
  return out
end

local function Count(t)
  local n = 0
  if type(t) == "table" then for _ in pairs(t) do n = n + 1 end end
  return n
end

-- "2 characters  ·  5 profiles  ·  12 quests" and so on.
local function Summary(db)
  local chars, profiles = 0, 0
  for _, c in pairs(type(db.profiles) == "table" and db.profiles or {}) do
    chars = chars + 1
    if type(c) == "table" then profiles = profiles + Count(c.list) end
  end
  local parts = {}
  local function Add(n, one, many) if n > 0 then parts[#parts + 1] = n .. " " .. (n == 1 and one or many) end end
  Add(chars, "character", "characters")
  Add(profiles, "profile", "profiles")
  Add(Count(db.questLibrary), "quest", "quests")
  Add(Count(db.itemDefs), "item design", "item designs")
  Add(Count(db.documents), "document", "documents")
  Add(Count(db.registry), "player in your directory", "players in your directory")
  return #parts > 0 and table.concat(parts, "  ·  ") or "Nothing saved yet"
end
B.Summary = Summary

local function Size(n)
  if n < 1024 then return n .. " bytes" end
  if n < 1048576 then return ("%.0f KB"):format(n / 1024) end
  return ("%.1f MB"):format(n / 1048576)
end

-- Returns the code, or nil and a reason.
function B:Encode(withOthers)
  local C = Codec()
  if not C then return nil, "The profile code builder isn't loaded." end
  local data = {}
  for k, v in pairs(KinshipRPDB or {}) do
    if type(k) == "string" and not SKIP[k] and (withOthers or not OTHERS[k]) then
      local cv = Plain(v, 1, {})
      if cv ~= nil then data[k] = cv end
    end
  end
  local payload = { kind = "backup", v = 1, by = K.VERSION, schema = tonumber(K.db.schema) or 0, t = time(),
                    who = K:PlayerName(), data = data }
  local text = C.Serialize(payload)
  if not text then return nil, "Your saved data couldn't be packed into a code." end
  local sum, flag, body = C.Adler(text), "p", text
  local z = C.Deflate(text)
  if z and #z < #text then flag, body = "z", z end
  local b64 = C.Encode64(body)
  local lines = { HEADER .. flag .. sum .. ":" }
  for i = 1, #b64, 64 do lines[#lines + 1] = b64:sub(i, i + 63) end
  return table.concat(lines, "\n"), data
end

-- Returns { data, by, schema, t, who } or nil and a reason (nil, nil = empty).
function B:Decode(code)
  local C = Codec()
  if type(code) ~= "string" or strtrim(code) == "" then return nil, nil end
  if not C then return nil, "The profile code reader isn't loaded." end
  if #code > MAX_CODE then return nil, "That's far too long to be a Kinship backup." end
  local flat = code:gsub("%s+", "")
  local flag, sum, body = flat:match("^KINSHIPBAK1:([pz])(%x%x%x%x%x%x%x%x):([%w%+/=]+)$")
  if not flag then
    if flat:find("KINSHIPBAK%d") and not flat:find("KINSHIPBAK1:") then
      return nil, "This backup comes from a newer version of Kinship. Update to restore it."
    end
    if flat:find("KINSHIPBAK1:") then return nil, "The backup is incomplete. Copy all of it, from KINSHIPBAK1 to the end." end
    if flat:find("KINSHIP1:") then return nil, "That's a profile code. Import it under Settings > Profiles instead." end
    return nil, "That doesn't look like a Kinship backup."
  end
  local raw = C.Decode64(body)
  if not raw then return nil, "The backup is damaged: some characters are missing or changed." end
  if flag == "z" then
    raw = C.Inflate(raw)
    if not raw then return nil, "This backup is compressed, and this game client can't open it." end
  end
  if C.Adler(raw) ~= sum:lower() then return nil, "The backup is damaged or cut short. Copy all of it and try again." end
  local t = C.Deserialize(raw)
  if type(t) ~= "table" or t.kind ~= "backup" or type(t.data) ~= "table" then
    return nil, "The code doesn't hold a Kinship backup."
  end
  local schema = tonumber(t.schema) or 0
  if schema > K.SCHEMA then
    return nil, "This backup comes from a newer version of Kinship. Update to restore it."
  end
  local data = Plain(t.data, 1, {}) or {}
  for k in pairs(SKIP) do data[k] = nil end
  if type(data.profiles) ~= "table" then return nil, "The backup has no profiles in it, so it can't be right." end
  return { data = data, schema = schema, by = type(t.by) == "string" and t.by or nil,
           t = type(t.t) == "number" and t.t or nil, who = type(t.who) == "string" and UI.Clean(t.who) or nil }
end

-- Replace all saved data with the backup's and reload, so every module starts
-- again from it. Core.lua upgrades it at load if it's from an older Kinship.
function B:Restore(backup)
  local db = KinshipRPDB
  if type(db) ~= "table" or type(backup) ~= "table" then return end
  local errors = db.errorLog
  wipe(db)
  for k, v in pairs(backup.data) do db[k] = v end
  db.schema = backup.schema
  db.errorLog = errors
  db.backup = { last = time(), restored = time() }   -- what you just restored is backed up
  ReloadUI()
end

---------------------------------------------------------------------------
-- The window
---------------------------------------------------------------------------
local W, H = 560, 500
local PW = W - 32

local function SetStatus(pg, text, color)
  pg.status:SetText(text or "")
  if color then
    pg.status:SetTextColor(color[1], color[2], color[3])
    pg.dot:SetVertexColor(color[1], color[2], color[3], 1)
    pg.dot:Show()
  else
    pg.status:SetTextColor(unpack(K:Theme().deskSubtle))
    pg.dot:Hide()
  end
end

local function BuildBackup(pg)
  local card = UI.Panel(pg)
  card:SetPoint("TOPLEFT", 16, -8)
  card:SetSize(PW, 66)
  card.seal = UI.Seal(card, 44)
  card.seal:SetPoint("LEFT", 12, 0)
  card.seal:SetSeal("teal", K.Art("IconNote"))
  card.name = UI.Text(card, "Everything Kinship has saved", "Title", "heading", PW - 190)
  card.name:SetPoint("TOPLEFT", 68, -14)
  card.name:SetWordWrap(false)
  card.sub = UI.Text(card, "", "Small", "subtle", PW - 190)
  card.sub:SetPoint("TOPLEFT", card.name, "BOTTOMLEFT", 0, -4)
  card.sub:SetWordWrap(false)
  card.size = UI.Chip(card)
  card.size:SetPoint("RIGHT", -14, 0)
  pg.card = card

  local hint = UI.Text(pg, "Copy this text (Ctrl+C) and keep it somewhere safe, such as a text file. If your Kinship "
    .. "data is ever lost, paste it under Restore. It covers every character on this account.", "Small", "deskSubtle", PW)
  hint:SetPoint("TOPLEFT", 17, -86)
  hint:SetSpacing(2)

  pg.others = UI.Toggle(pg, "Include other players' profiles and items",
    "They come back as you meet people again; leave them out for a shorter backup.",
    function() return State().others ~= false end,
    function(v) State().others = v and true or false; B:RefreshBackup() end, PW)
  pg.others:SetPoint("TOPLEFT", 16, -122)

  pg.area = UI.TextArea(pg, PW, 206, 0, nil, "desk")
  pg.area:SetPoint("TOPLEFT", 16, -166)
  -- Read-only: any typing puts the code back.
  pg.area.edit:HookScript("OnTextChanged", function(self, user)
    if user and B.code and self:GetText() ~= B.code then self:SetText(B.code); self:HighlightText() end
  end)

  pg.done = UI.Button(pg, "Done", 100, 28)
  pg.done:SetPoint("BOTTOMRIGHT", -16, 14)
  pg.done:SetScript("OnClick", function() B.frame:Hide() end)
  pg.select = UI.Button(pg, "Select all", 110, 28)
  pg.select:SetPoint("RIGHT", pg.done, "LEFT", -8, 0)
  pg.select:SetScript("OnClick", function()
    pg.area.edit:SetFocus()
    pg.area.edit:HighlightText()
  end)
end

local function BuildRestore(pg)
  local hint = UI.Text(pg, "Paste a backup below (Ctrl+V). Backups start with KINSHIPBAK1.", "Small", "deskSubtle", PW)
  hint:SetPoint("TOPLEFT", 17, -10)

  pg.area = UI.TextArea(pg, PW, 150, 0, function() B:QueueValidate() end, "desk")
  pg.area:SetPoint("TOPLEFT", 16, -30)

  pg.dot = UI.Circle(pg, 8)
  pg.dot:SetPoint("TOPLEFT", 18, -195)
  pg.status = UI.Text(pg, "", "Small", "deskSubtle", PW - 20)
  pg.status:SetPoint("TOPLEFT", 32, -192)
  pg.status:SetWordWrap(false)

  local card = UI.Panel(pg)
  card:SetPoint("TOPLEFT", 16, -216)
  card:SetSize(PW, 116)
  card.title = UI.Text(card, "", "Title", "heading", PW - 32)
  card.title:SetPoint("TOPLEFT", 16, -16)
  card.title:SetWordWrap(false)
  card.facts = UI.Text(card, "", "Small", "text", PW - 32)
  card.facts:SetPoint("TOPLEFT", card.title, "BOTTOMLEFT", 0, -7)
  card.warn = UI.Text(card, "Restoring replaces everything Kinship has saved on this account with the backup, "
    .. "then reloads your interface. Only restore a backup you made yourself.", "Small", "subtle", PW - 32)
  card.warn:SetPoint("BOTTOMLEFT", 16, 14)
  card.warn:SetSpacing(2)
  pg.card = card

  pg.go = UI.Button(pg, "Restore", 120, 28)
  pg.go:SetPoint("BOTTOMRIGHT", -16, 14)
  pg.go:SetScript("OnClick", function() if B.pending then B:Confirm() end end)
  pg.clear = UI.Button(pg, "Clear", 90, 28)
  pg.clear:SetPoint("RIGHT", pg.go, "LEFT", -8, 0)
  pg.clear:SetScript("OnClick", function()
    pg.area.edit:SetText("")
    B:Validate()
  end)
end

-- Asked once more before anything is replaced.
function B:Confirm()
  local f = self.frame
  if not f.confirm then
    local m = UI.Modal(f, 400, 200, function() f.confirm:Hide() end)
    local c = m.card
    c.title = UI.Text(c, "Replace everything?", "Title", "heading", 360)
    c.title:SetPoint("TOPLEFT", 20, -22)
    c.body = UI.Text(c, "", "Body", "text", 360)
    c.body:SetPoint("TOPLEFT", c.title, "BOTTOMLEFT", 0, -10)
    c.body:SetSpacing(2)
    c.yes = UI.Button(c, "Restore and reload", 160, 28)
    c.yes:SetPoint("BOTTOMRIGHT", -16, 14)
    c.yes:SetScript("OnClick", function() if B.pending then B:Restore(B.pending) end end)
    c.no = UI.Button(c, "Cancel", 90, 28)
    c.no:SetPoint("RIGHT", c.yes, "LEFT", -8, 0)
    c.no:SetScript("OnClick", function() m:Hide() end)
    f.confirm = m
  end
  local p = self.pending
  f.confirm.card.body:SetText(("Kinship's saved data on this account will be replaced with the backup%s. "
    .. "Anything you've changed since then will be lost. Your interface reloads straight away.")
    :format(p.t and (" from " .. K.FormatDate(p.t)) or ""))
  f.confirm:Show()
end

function B:Build()
  if self.frame then return end
  local f = UI.Window("KinshipRPBackup", "Back up everything", W, H)
  f:SetFrameStrata("DIALOG")
  self.frame = f
  local desk = UI.Desk(f)
  desk:SetPoint("TOPLEFT", 1, -35)
  desk:SetPoint("BOTTOMRIGHT", -1, 1)
  f.tabs = UI.TabBar(f, { "Back up", "Restore" }, function(i) B:ShowTab(i) end, true)
  f.tabs:SetPoint("TOPLEFT", 6, -42)
  f.pages = {}
  for i = 1, 2 do
    local pg = CreateFrame("Frame", nil, f)
    pg:SetPoint("TOPLEFT", 0, -72)
    pg:SetPoint("BOTTOMRIGHT")
    pg:Hide()
    f.pages[i] = pg
  end
  BuildBackup(f.pages[1])
  BuildRestore(f.pages[2])
  f:HookScript("OnHide", function() if f.confirm then f.confirm:Hide() end end)
end

function B:ShowTab(i)
  local f = self.frame
  f.tabs:Select(i)
  for n, pg in ipairs(f.pages) do pg:SetShown(n == i) end
  if self.tab ~= i then UI.FadeIn(f.pages[i], 0.2) end
  self.tab = i
  if i == 1 then self:RefreshBackup() else self:Validate() end
end

-- tab: "restore", or nil for the backup itself.
function B:Open(tab)
  self:Build()
  self.frame:Show()
  self:ShowTab(tab == "restore" and 2 or 1)
  if tab == "restore" then self.frame.pages[2].area.edit:SetFocus() end
end

function B:RefreshBackup()
  local pg = self.frame.pages[1]
  pg.others:Refresh()
  pg.card.sub:SetText("Packing...")
  pg.card.size:Set(nil)
  pg.area.edit:SetText("")
  pg.select:SetEnabled(false)
  -- Packing a large backup takes a moment: let the window draw first.
  self.packToken = (self.packToken or 0) + 1
  local token = self.packToken
  C_Timer.After(0.05, function()
    if B.packToken ~= token or not pg:IsVisible() then return end
    local code, data = B:Encode(State().others ~= false)
    if code and #code > MAX_SHOW then
      code, data = nil, "This backup is too large to show. Leave out other players' profiles and items to shorten it."
    end
    B.code = code
    if not code then
      pg.card.sub:SetText(data or "Your saved data couldn't be packed into a code.")
      return
    end
    pg.card.sub:SetText(Summary(data))
    pg.card.size:Set(Size(#code), K:Theme().accent)
    pg.area.edit:SetText(code)
    pg.area.edit:SetCursorPosition(0)
    pg.area.edit:SetFocus()
    pg.area.edit:HighlightText()
    pg.select:SetEnabled(true)
    State().last = time()
  end)
end

function B:QueueValidate()
  self.token = (self.token or 0) + 1
  local token = self.token
  C_Timer.After(0.2, function() if B.token == token then B:Validate() end end)
end

function B:Validate()
  local pg = self.frame and self.frame.pages[2]
  if not pg then return end
  local data, err = self:Decode(pg.area.edit:GetText() or "")
  self.pending = data
  pg.go:SetEnabled(data ~= nil)
  if not data then
    pg.card.title:SetText("No backup yet")
    pg.card.facts:SetText("A summary of what's in the backup appears here once you paste it.")
    if err then SetStatus(pg, err, BAD) else SetStatus(pg, "Waiting for a backup.") end
    return
  end
  pg.card.title:SetText(data.t and ("Backup from " .. K.FormatDate(data.t)) or "Kinship backup")
  pg.card.facts:SetText(Summary(data.data))
  local old = data.schema < K.SCHEMA
  SetStatus(pg, ("A valid backup%s%s.%s"):format(data.by and (" from Kinship " .. data.by) or "",
    data.who and (", made on " .. data.who) or "", old and " It will be updated as it loads." or ""),
    old and WARN or GOOD)
  UI.FadeIn(pg.card, 0.2)
end

---------------------------------------------------------------------------
-- The gentle reminder: at most once a week, only once there's something
-- worth keeping, and only if your last backup is two weeks old (or there
-- isn't one). Settings > General switches it off.
---------------------------------------------------------------------------
local function WorthKeeping()
  for _, c in pairs(K.db.profiles or {}) do
    for _, p in pairs(type(c) == "table" and type(c.list) == "table" and c.list or {}) do
      if type(p) == "table" and ((p.rpName or "") ~= "" or (p.history or "") ~= "" or (p.appearance or "") ~= "") then
        return true
      end
    end
  end
  return Count(K.db.questLibrary) > 0 or Count(K.db.itemDefs) > 0 or Count(K.db.documents) > 0
end

local function MaybeRemind()
  if K.db.settings.backupReminder == false then return end
  local s, now = State(), time()
  s.since = s.since or now
  if now - (s.last or s.since) < REMIND_AFTER or now - (s.nag or 0) < REMIND_EVERY then return end
  if not WorthKeeping() or InCombatLockdown() then return end
  s.nag = now
  UI.Toast({ icon = K.Art("IconNote"), title = "Back up your Kinship data?",
    text = s.last and ("Your last backup was " .. K.FormatDate(s.last) .. ". The Forever client sometimes loses addon data; a fresh copy only takes a moment.")
      or "The Forever client sometimes loses addon data. A backup is one block of text you keep somewhere safe.",
    actions = { { label = "Back up now", fn = function() B:Open() end }, { label = "Not now", fn = function() end } } })
end

K:On("LOGIN", function()
  local s = State()
  s.since = s.since or time()
  C_Timer.After(45, function() pcall(MaybeRemind) end)
end)

---------------------------------------------------------------------------
-- Settings > General adds these rows (see PageSettings.lua).
---------------------------------------------------------------------------
function B:AddSettings(card)
  local note = card:Note("", 28)
  local bk = card:Button("Back up everything", function() B:Open() end, 170)
  local rs = UI.Button(card, "Restore a backup", 150, 26)
  rs:SetPoint("LEFT", bk, "RIGHT", 8, 0)
  rs:SetScript("OnClick", function() B:Open("restore") end)
  card:Toggle("Remind me to back up", "Now and then, when it's been a while since your last backup.", {
    get = function() return K.db.settings.backupReminder ~= false end,
    set = function(v) K.db.settings.backupReminder = v and true or false end,
  })
  card:EndRow()
  card:OnRefresh(function()
    local last = State().last
    note:SetText("Keep a copy of all your Kinship data (every character on this account) as one block of text. "
      .. (last and ("Last backup: " .. K.FormatDate(last) .. ".") or "You haven't made a backup yet."))
  end)
end
