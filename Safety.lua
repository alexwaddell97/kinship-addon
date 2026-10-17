-- Kinship RP: safety. An ignore list that hides someone everywhere (profile,
-- tooltip, nameplate, letters and Kinship messages), and a mature-content
-- filter that covers profiles using words from your list until you choose to
-- see them.
--
--   K:IsIgnored(name), K:Ignore(name, reason), K:Unignore(name)
--   K:IsFlagged(name), K:Flag(name), K:Unflag(name)
--   K.Safety:ConfirmIgnore(name)       the "Ignore someone?" pop-over
--   K.Safety:Cover(parent)             a "may contain mature content" cover;
--                                      call cover:Check(name) when showing someone
-- Fires "IGNORE" (key) when the ignore list changes and "SAFETY" when the
-- filter, its words or a profile's flag change.

local ADDON, ns = ...
local K = ns.K
local UI = K.UI
local Safe = K.Safe
local S = {}
K.Safety = S

local CROP = ":0:0:64:64:5:59:5:59"
local SHIELD = "Interface\\Icons\\spell_holy_sealofprotection"
local DANGER = { 0.88, 0.36, 0.32 }
local WARN = { 0.92, 0.62, 0.30 }
local OnCard = UI.OnCard or function(c) return c end

-- A modest starting list. Words match whole (so "bloodlust" never matches "lust").
local DEFAULT_WORDS = {
  "nsfw", "erp", "explicit", "nude", "nudity", "naked", "sex", "sexual", "sexy", "porn", "porno",
  "fetish", "fetishes", "kink", "kinks", "kinky", "bdsm", "bondage", "lewd", "horny", "slut",
  "whore", "cock", "dick", "pussy", "boobs", "tits", "genitals", "orgasm", "aroused", "erotic",
  "smut", "hentai", "cum", "nipples", "milf",
}
-- Profile keys that never hold player-written text.
local SKIP = { addon = true, status = true, stance = true, crest = true, consent = true, icon = true, music = true }
local LEVELS = {
  { key = 1, label = "Strict" },    -- one listed word is enough
  { key = 2, label = "Balanced" },  -- two different listed words
  { key = 3, label = "Relaxed" },   -- three different listed words
}

local function DB() return K.db and K.db.safety end

local function Key(name)
  if not Safe(name) or type(name) ~= "string" or name == "" then return nil end
  local key = K.NameKey and K.NameKey(name)
  return key or name:lower()
end

local function Short(name) return Ambiguate and Ambiguate(name, "none") or name end

local function RefreshJournal()
  local J = K.Journal
  if J and J.frame and J.frame:IsShown() then J:RefreshCurrent() end
end

---------------------------------------------------------------------------
-- Ignore list: K.db.ignored[nameKey] = { name, t, reason }
---------------------------------------------------------------------------
function K:IsIgnored(name)
  local list = self.db and self.db.ignored
  if not list or next(list) == nil then return false end
  local key = Key(name)
  return key ~= nil and list[key] ~= nil
end

local function IgnoreChanged(key)
  K:Fire("IGNORE", key)
  K:Fire("SAFETY")
  K:Fire("REGISTRY", key)
  K:Fire("TARGET_BUTTONS")
  S:RefreshSettings()
  RefreshJournal()
end

function K:Ignore(name, reason)
  if not self.db then return false end
  local key = Key(name)
  if not key or key == Key(self:MyName()) then return false end
  reason = reason and strtrim((tostring(reason):gsub("|", ""))) or ""
  self.db.ignored[key] = { name = name, t = time(), reason = reason ~= "" and reason or nil }
  -- Forget what we hold of them; Comm won't store anything new.
  if self.db.registry then self.db.registry[key] = nil end
  K.Try("ignore", function()
    local V = K.Viewer
    if V and V.frame and V.frame:IsShown() and V.data and V.data.key == key then V.frame:Hide() end
  end)
  IgnoreChanged(key)
  return true
end

function K:Unignore(name)
  local list = self.db and self.db.ignored
  if not list or type(name) ~= "string" then return false end
  local key = list[name] and name or Key(name)
  if not key or not list[key] then return false end
  local full = list[key].name or name
  list[key] = nil
  IgnoreChanged(key)
  -- Ask for their profile again if they're around.
  K.Try("ignore", function() if K.Comm then K.Comm:Request(full) end end)
  return true
end

function K:IgnoredList()
  local out = {}
  for key, e in pairs(self.db and self.db.ignored or {}) do
    out[#out + 1] = { key = key, name = e.name or key, t = e.t, reason = e.reason }
  end
  table.sort(out, function(a, b) return (a.t or 0) > (b.t or 0) end)
  return out
end

---------------------------------------------------------------------------
-- Mature filter
---------------------------------------------------------------------------
-- Text as the filter reads it: every UI code removed whole (a link keeps its
-- label), so "|cffff0000nsfw|r" or "|rnsfw" can't hide a word.
local function Plain(v)
  v = v:gsub("||", " ")
  v = v:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|cn[^:|]*:", ""):gsub("|r", "")
  v = v:gsub("|H.-|h(.-)|h", "%1"):gsub("|[TtAaKk].-|[tTaAkK]", " "):gsub("|n", " ")
  return v:lower()
end

-- Raise when matching changes, so stored profiles are checked again once.
local SCAN_RULES = 2

-- Look-alike characters used to slip past word lists ("s3x", "p0rn", "$lut").
local LEET = { ["0"] = "o", ["1"] = "i", ["3"] = "e", ["4"] = "a", ["5"] = "s", ["7"] = "t", ["@"] = "a", ["$"] = "s" }

-- The listed word w stands for, also as a plural ("sluts", "fetishes").
local function Lookup(w, words)
  if words[w] then
    -- A plural of a listed word counts as that word, not as a second one.
    if #w > 4 and w:sub(-2) == "es" and words[w:sub(1, -3)] then return w:sub(1, -3) end
    if #w > 3 and w:sub(-1) == "s" and words[w:sub(1, -2)] then return w:sub(1, -2) end
    return w
  end
  if #w > 3 and w:sub(-1) == "s" then
    if words[w:sub(1, -2)] then return w:sub(1, -2) end
    if w:sub(-2) == "es" and words[w:sub(1, -3)] then return w:sub(1, -3) end
  end
end

-- Runs of one letter cut to at most `keep` (Lua patterns can't repeat a capture).
local function Squeeze(w, keep)
  local out, last, n = {}, nil, 0
  for c in w:gmatch(".") do
    if c == last then n = n + 1 else last, n = c, 1 end
    if n <= keep then out[#out + 1] = c end
  end
  return table.concat(out)
end

-- One word of text, as written and with stretched letters undone
-- ("sexxx", "nuuude", "boooobs").
local function Check(w, words, found)
  local hit = Lookup(w, words)
  if not hit and w:find("(.)%1") then
    local two, one = Squeeze(w, 2), Squeeze(w, 1)
    hit = (two ~= w and Lookup(two, words)) or (one ~= w and Lookup(one, words)) or nil
  end
  if hit then found[hit] = true end
end

local function Scan(v, words, found, depth)
  if type(v) == "string" then
    if v == "" then return end
    local text = Plain(v)
    -- Words spelt out letter by letter ("n s f w", "s.e.x") are read joined.
    local run = {}
    for w in text:gmatch("[^%s%p]+") do
      Check(w, words, found)
      if #w == 1 then
        run[#run + 1] = w
      else
        if #run > 1 then Check(table.concat(run), words, found) end
        run = {}
      end
    end
    if #run > 1 then Check(table.concat(run), words, found) end
    for w in text:gmatch("[%w@%$]+") do
      if w:find("[%d@%$]") and w:find("%a") then Check((w:gsub("[013457@%$]", LEET)), words, found) end
    end
  elseif type(v) == "table" and depth < 6 then
    for k, sub in pairs(v) do
      if not SKIP[k] then Scan(sub, words, found, depth + 1) end
    end
  end
end

-- Check one registry entry. Returns true if its flag changed.
local function Evaluate(key, entry)
  local db = DB()
  if not db or type(entry) ~= "table" then return false end
  local was = entry.flagged
  if db.trusted[key] then
    entry.flagged = nil
  elseif entry.flaggedByHand then
    entry.flagged = true
  else
    local found, n = {}, 0
    Scan(entry.profile, db.words, found, 0)
    for _ in pairs(found) do n = n + 1 end
    entry.flagged = (n >= (db.level or 2)) or nil
  end
  return entry.flagged ~= was
end

function K:IsFlagged(name)
  if not (self.db and self.db.settings.matureFilter) then return false end
  local key, db = Key(name), DB()
  if not key or not db or db.trusted[key] then return false end
  local e = self.db.registry and self.db.registry[key]
  return e ~= nil and e.flagged == true
end

local function FlagChanged(key)
  K:Fire("SAFETY")
  if key then K:Fire("REGISTRY", key, K.db.registry and K.db.registry[key]) end
  RefreshJournal()
end

-- "Show anyway": trust this player's profile from now on.
function K:Unflag(name)
  local key, db = Key(name), DB()
  if not key or not db then return end
  db.trusted[key] = true
  local e = self.db.registry and self.db.registry[key]
  if e then e.flagged, e.flaggedByHand = nil, nil end
  FlagChanged(key)
end

-- Cover someone's profile by hand.
function K:Flag(name)
  local key, db = Key(name), DB()
  if not key or not db then return end
  db.trusted[key] = nil
  local e = self.db.registry and self.db.registry[key]
  if e then e.flagged, e.flaggedByHand = true, true end
  FlagChanged(key)
end

-- Look over every stored profile again (after the words or the level change),
-- a few dozen per frame so a big registry never stutters.
function S:RescanAll()
  local reg = K.db and K.db.registry
  if not reg or not DB() then return end
  if self.scanTicker then self.scanTicker:Cancel() end
  local keys = {}
  for key in pairs(reg) do keys[#keys + 1] = key end
  local i, ticker = 0, nil
  self.scanning = true
  self:RefreshSettings()
  ticker = C_Timer.NewTicker(0.03, function()
    for _ = 1, 40 do
      i = i + 1
      local key = keys[i]
      if not key then
        ticker:Cancel()
        S.scanTicker, S.scanning = nil, false
        K:Fire("SAFETY")
        S:RefreshSettings()
        RefreshJournal()
        return
      end
      local e = reg[key]
      if e then Evaluate(key, e) end
    end
  end)
  self.scanTicker = ticker
end

function S:FlaggedCount()
  local n = 0
  for _, e in pairs(K.db and K.db.registry or {}) do if e.flagged then n = n + 1 end end
  return n
end

function S:AddWords(text)
  local db = DB()
  if not db or type(text) ~= "string" then return 0 end
  local n = 0
  for w in text:lower():gmatch("[^%s%p]+") do
    if not db.words[w] then db.words[w] = true; n = n + 1 end
  end
  if n > 0 then self:RescanAll() end
  return n
end

function S:RemoveWord(word)
  local db = DB()
  if not db or not db.words[word] then return end
  db.words[word] = nil
  self:RescanAll()
end

function S:ResetWords()
  local db = DB()
  if not db then return end
  db.words = {}
  for _, w in ipairs(DEFAULT_WORDS) do db.words[w] = true end
  self:RescanAll()
end

-- Flag new profiles before the pages that show them redraw.
local function OnFirst(event, fn)
  K.listeners[event] = K.listeners[event] or {}
  table.insert(K.listeners[event], 1, fn)
end
OnFirst("REGISTRY", function(key, entry)
  if type(key) ~= "string" or not DB() then return end
  entry = entry or (K.db.registry and K.db.registry[key])
  if entry and Evaluate(key, entry) then K:Fire("SAFETY") end
end)

---------------------------------------------------------------------------
-- Shared bits for pop-overs
---------------------------------------------------------------------------
-- A full-screen host so the confirm card works wherever it's opened from
-- (the target bar has no window of its own). Esc closes it.
local function Host()
  if S.host then return S.host end
  local host = CreateFrame("Frame", "KinshipRPSafetyHost", UIParent)
  host:SetAllPoints(UIParent)
  host:SetFrameStrata("DIALOG")
  host:Hide()
  tinsert(UISpecialFrames, "KinshipRPSafetyHost")
  S.host = host
  return host
end

local function HintEdit(parent, w, hint, max)
  local eb = UI.Edit(parent, w, 24, nil, max)
  eb.hint = UI.Text(eb, hint, "Small", "subtle")
  eb.hint:SetPoint("LEFT", 9, 0)
  eb:HookScript("OnTextChanged", function(self) self.hint:SetShown((self:GetText() or "") == "") end)
  return eb
end

---------------------------------------------------------------------------
-- "Ignore someone?" confirmation
---------------------------------------------------------------------------
local Confirm = {}

function Confirm:Build()
  if self.ov then return end
  local host = Host()
  local ov = UI.Modal(host, 400, 262, function() Confirm:Close() end)
  self.ov = ov
  local card = ov.card
  host:SetScript("OnHide", function() if ov:IsShown() then ov:Hide() end end)
  UI:OnTheme(function() card.accent:SetVertexColor(DANGER[1], DANGER[2], DANGER[3], 1) end)

  card.ring = UI.Circle(card, 46, "ARTWORK", 0)
  card.ring:SetPoint("TOPLEFT", 18, -22)
  card.ring:SetVertexColor(DANGER[1], DANGER[2], DANGER[3], 1)
  card.icon = card:CreateTexture(nil, "ARTWORK", nil, 1)
  card.icon:SetSize(40, 40)
  card.icon:SetPoint("CENTER", card.ring)
  card.icon:SetTexture(SHIELD)
  card.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
  UI.Round(card.icon)
  self.title = UI.Text(card, "", "Title", "heading", 280)
  self.title:SetPoint("TOPLEFT", card.ring, "TOPRIGHT", 12, -4)
  self.title:SetWordWrap(false)
  self.sub = UI.Text(card, "", "Small", "subtle", 280)
  self.sub:SetPoint("TOPLEFT", self.title, "BOTTOMLEFT", 0, -4)
  self.sub:SetWordWrap(false)

  local body = UI.Text(card, "Their profile, tooltip details, nameplate name, letters and Kinship messages "
    .. "will be hidden from you. They aren't told, and you can undo it any time in Settings.", "Small", "text", 364)
  body:SetPoint("TOPLEFT", 18, -84)
  body:SetSpacing(2)

  self.reason = UI.Field(card, "Reason (only you can see it)", 364, 80)
  self.reason:SetPoint("TOPLEFT", 18, -140)
  self.reason.edit:SetScript("OnEnterPressed", function() Confirm:Accept() end)

  self.ok = UI.Button(card, ("|cff%sIgnore|r"):format(UI.Hex(DANGER)), 110, 26)   -- on a dark teal button
  self.ok:SetPoint("BOTTOMRIGHT", -16, 16)
  self.ok:SetScript("OnClick", function() Confirm:Accept() end)
  local cancel = UI.Button(card, "Cancel", 90, 26)
  cancel:SetPoint("RIGHT", self.ok, "LEFT", -8, 0)
  cancel:SetScript("OnClick", function() Confirm:Close() end)
end

function Confirm:Open(name)
  self:Build()
  self.name = name
  local short = Short(name)
  local reg = K:ProfileOf(name)
  local rp = reg and reg.profile and strtrim(UI.Clean(reg.profile.rpName or "")) or ""
  self.title:SetText("Ignore " .. short .. "?")
  self.sub:SetText(rp ~= "" and ("Known to you as " .. UI.Escape((rp:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")))) or name)
  self.reason.edit:SetText("")
  S.host:Show()
  self.ov:Show()
  self.reason.edit:SetFocus()
end

function Confirm:Accept()
  local name = self.name
  if not name then return end
  local reason = self.reason.edit:GetText()
  self:Close()
  if K:Ignore(name, reason) then
    if SOUNDKIT then PlaySound(SOUNDKIT.IG_CHARACTER_INFO_TAB) end
    UI.Toast({
      icon = SHIELD, round = true, color = DANGER,
      title = "Ignoring " .. Short(name),
      text = "Their profile and messages are hidden from you.",
      actions = { { label = "Undo", fn = function() K:Unignore(name) end } },
      duration = 8,
    })
  end
end

function Confirm:Close()
  if not self.ov then return end
  self.reason.edit:ClearFocus()
  self.ov:Hide()
  if S.host then S.host:Hide() end
  self.name = nil
end

function S:ConfirmIgnore(name)
  if not Key(name) then return end
  Confirm:Open(name)
end

---------------------------------------------------------------------------
-- Mature content cover, for the Directory preview and the profile viewer.
-- local cover = K.Safety:Cover(panel); cover:Check(name) (nil hides it).
---------------------------------------------------------------------------
S.covers = {}

function S:Cover(parent)
  local c = CreateFrame("Frame", nil, parent)
  c:SetAllPoints()
  c:SetFrameLevel(parent:GetFrameLevel() + 20)
  c:EnableMouse(true)
  c.base = c:CreateTexture(nil, "BACKGROUND", nil, -8)
  c.base:SetAllPoints()
  c.wash = c:CreateTexture(nil, "BACKGROUND", nil, -7)
  c.wash:SetAllPoints()
  c.edge = UI.Border(c)
  UI:OnTheme(function(t)
    local p = t.panel
    c.base:SetColorTexture(p[1], p[2], p[3], 1)
    c.wash:SetColorTexture(unpack(t.sectionBg))
    c.edge:SetColor(unpack(t.panelEdge))
  end)

  local mid = CreateFrame("Frame", nil, c)
  mid:SetSize(1, 1)
  mid:SetPoint("CENTER", 0, 10)
  c.halo = UI.Circle(c, 84, "ARTWORK", 0)
  c.halo:SetPoint("BOTTOM", mid, "CENTER", 0, 26)
  c.halo:SetVertexColor(WARN[1], WARN[2], WARN[3], 0.16)
  c.ring = UI.Circle(c, 62, "ARTWORK", 1)
  c.ring:SetPoint("CENTER", c.halo)
  c.ring:SetVertexColor(WARN[1], WARN[2], WARN[3], 1)
  c.icon = c:CreateTexture(nil, "ARTWORK", nil, 2)
  c.icon:SetSize(54, 54)
  c.icon:SetPoint("CENTER", c.ring)
  c.icon:SetTexture(SHIELD)
  c.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
  UI.Round(c.icon)

  c.title = UI.Text(c, "This profile may contain mature content", "Header", "heading", 250)
  c.title:SetPoint("TOP", mid, "CENTER", 0, 14)
  c.title:SetJustifyH("CENTER")
  c.title:SetSpacing(2)
  c.text = UI.Text(c, "Some of its words match your mature filter. You can look anyway, or leave it covered.",
    "Small", "subtle", 240)
  c.text:SetPoint("TOP", c.title, "BOTTOM", 0, -8)
  c.text:SetJustifyH("CENTER")
  c.text:SetSpacing(2)

  c.show = UI.Button(c, "Show anyway", 116, 26)
  c.show:SetPoint("TOPRIGHT", c.text, "BOTTOM", -4, -16)
  c.show:SetScript("OnClick", function()
    local name = c.name
    if not name then return end
    c.revealing = true
    UI.Tween(c, 0, 0.22, function(p)
      c:SetAlpha(p)
      if p <= 0 then c:Hide(); c:SetAlpha(1); c.revealing = false end
    end)
    K:Unflag(name)
  end)
  UI.Tooltip(c.show, "Show anyway", "Uncover this profile, now and from now on.")
  c.settings = UI.Button(c, "Filter settings", 116, 26)
  c.settings:SetPoint("TOPLEFT", c.text, "BOTTOM", 4, -16)
  c.settings:SetScript("OnClick", function() if K.Journal then K.Journal:Open("settings") end end)

  function c:Check(name)
    self.name = name
    local flagged = name ~= nil and K:IsFlagged(name)
    if flagged then
      if not self:IsShown() or self.revealing then
        self.revealing = false
        self:Show()
        UI.FadeIn(self, 0.2)
      end
    elseif not self.revealing then
      self:Hide()
    end
    return flagged
  end

  c:Hide()
  table.insert(S.covers, c)
  return c
end

---------------------------------------------------------------------------
-- Target bar
---------------------------------------------------------------------------
local function IsOther(unit, name)
  if not Key(name) then return false end
  if unit and Safe(unit) then
    local ok, me = pcall(UnitIsUnit, unit, "player")
    if ok and Safe(me) and me then return false end
  end
  return Key(name) ~= Key(K:MyName())
end

K:RegisterTargetButton({
  id = "ignore", order = 90, label = "Ignore profile", icon = SHIELD,
  shown = function(unit, name) return IsOther(unit, name) and not K:IsIgnored(name) end,
  onClick = function(unit, name) S:ConfirmIgnore(name) end,
})
K:RegisterTargetButton({
  id = "unignore", order = 90, label = "Stop ignoring", icon = SHIELD,
  shown = function(unit, name) return IsOther(unit, name) and K:IsIgnored(name) end,
  onClick = function(unit, name)
    if K:Unignore(name) then
      UI.Toast({ icon = SHIELD, round = true, title = "No longer ignoring " .. Short(name),
        text = "Their profile will show again when it next arrives." })
    end
  end,
})

---------------------------------------------------------------------------
-- Settings
---------------------------------------------------------------------------
function S:RefreshSettings()
  local ui = self.ui
  if not ui or not ui.ignoreList:IsVisible() then return end
  local db = DB()
  if not db then return end

  local ignored = K:IgnoredList()
  ui.ignoreCount:SetText(#ignored > 0 and tostring(#ignored) or "")
  ui.ignoreList:SetItems(ignored, function(row, e)
    row.name:SetText(UI.Escape(Short(e.name)))
    local when = e.t and ("Ignored " .. UI.Ago(e.t)) or "Ignored"
    row.sub:SetText(e.reason and (when .. "  ·  " .. UI.Escape(e.reason)) or when)
  end)

  local words = {}
  for w in pairs(db.words) do words[#words + 1] = w end
  table.sort(words)
  local flagged = self:FlaggedCount()
  if self.scanning then
    ui.wordCount:SetText("Checking profiles...")
  else
    ui.wordCount:SetText(("%d words  ·  %d covered"):format(#words, flagged))
  end
  ui.wordList:SetItems(words, function(row, w) row.word:SetText(UI.Escape(w)) end)
end

K:RegisterSettings({ id = "safety", title = "Safety", order = 40, build = function(card)
  local W = card:GetWidth() - 32
  card:Toggle("Mature content filter", "Cover profiles that use words from your list until you choose to see them.", {
    get = function() return K.db.settings.matureFilter and true or false end,
    set = function(v) K.db.settings.matureFilter = v; K:Fire("SAFETY"); RefreshJournal() end,
  })
  card:Segments("Filter sensitivity", LEVELS, function() return DB() and DB().level or 2 end,
    function(v) if DB() then DB().level = v; S:RescanAll() end end, 92)

  local ui = {}
  S.ui = ui
  local colW = math.floor((W - 24) / 2)
  local x2 = 16 + colW + 24
  local LIST_H = 168
  local y = card.y

  -- Ignored players ---------------------------------------------------------
  local lh = UI.Text(card, "Ignored players", "Label", "subtle")
  lh:SetPoint("TOPLEFT", 17, y)
  ui.ignoreCount = UI.Text(card, "", "Label", "subtle")
  ui.ignoreCount:SetPoint("LEFT", lh, "RIGHT", 8, 0)
  ui.ignoreCount:SetAlpha(0.8)
  ui.ignoreList = UI.List(card, colW, LIST_H, 42,
    "No one ignored. If someone makes roleplay unpleasant, ignore them from the target bar and they vanish from Kinship.",
    function(row)
      row.name = UI.Text(row, "", "Body", "heading", colW - 140)
      row.name:SetPoint("TOPLEFT", 10, -7)
      row.name:SetWordWrap(false)
      row.sub = UI.Text(row, "", "Small", "subtle", colW - 140)
      row.sub:SetPoint("TOPLEFT", row.name, "BOTTOMLEFT", 0, -3)
      row.sub:SetWordWrap(false)
      row.stop = UI.Button(row, "Stop ignoring", 100, 22)
      row.stop:SetPoint("RIGHT", -6, 0)
      row.stop:SetScript("OnClick", function() if row.item then K:Unignore(row.item.key) end end)
    end, { emptyIcon = K.Art("IconKin") })
  ui.ignoreList:SetPoint("TOPLEFT", 16, y - 16)

  local ie = HintEdit(card, colW - 92, "Ignore someone by name", 60)
  ie:SetPoint("TOPLEFT", 16, y - 16 - LIST_H - 8)
  local ib = UI.Button(card, "Ignore", 84, 24)
  ib:SetPoint("LEFT", ie, "RIGHT", 8, 0)
  local function addIgnore()
    local name = strtrim(ie:GetText() or "")
    if name ~= "" then S:ConfirmIgnore(name); ie:SetText(""); ie:ClearFocus() end
  end
  ib:SetScript("OnClick", addIgnore)
  ie:SetScript("OnEnterPressed", addIgnore)

  -- Filter words ------------------------------------------------------------
  local wh = UI.Text(card, "Filter words", "Label", "subtle")
  wh:SetPoint("TOPLEFT", x2 + 1, y)
  ui.wordCount = UI.Text(card, "", "Label", "subtle")
  ui.wordCount:SetPoint("LEFT", wh, "RIGHT", 8, 0)
  ui.wordCount:SetAlpha(0.8)
  ui.wordList = UI.List(card, colW, LIST_H, 26,
    "Your list is empty, so nothing will be covered. Add words below, or bring back the starting list.",
    function(row)
      row.word = UI.Text(row, "", "Body", "text", colW - 60)
      row.word:SetPoint("LEFT", 10, 0)
      row.word:SetWordWrap(false)
      row.remove = UI.CloseButton(row, true, 18)
      row.remove:SetPoint("RIGHT", -6, 0)
      row.remove:SetScript("OnClick", function() if row.item then S:RemoveWord(row.item) end end)
      UI.Tooltip(row.remove, "Remove word")
    end, { emptyIcon = K.Art("IconNote") })
  ui.wordList:SetPoint("TOPLEFT", x2, y - 16)

  local we = HintEdit(card, colW - 152, "Add words", 60)
  we:SetPoint("TOPLEFT", x2, y - 16 - LIST_H - 8)
  local wb = UI.Button(card, "Add", 64, 24)
  wb:SetPoint("LEFT", we, "RIGHT", 8, 0)
  local function addWords()
    if S:AddWords(we:GetText() or "") >= 0 then we:SetText(""); we:ClearFocus() end
  end
  wb:SetScript("OnClick", addWords)
  we:SetScript("OnEnterPressed", addWords)
  local reset = UI.Button(card, "Reset", 72, 24)
  reset:SetPoint("LEFT", wb, "RIGHT", 8, 0)
  reset:SetScript("OnClick", function() S:ResetWords() end)
  UI.Tooltip(reset, "Reset words", "Bring back Kinship's starting list, replacing your changes.")

  y = y - 16 - LIST_H - 8 - 24
  card:Space(card.y - y + 12)
  card:Note("Words match whole, in every part of a profile: names, descriptions, history and glances. "
    .. "Plurals, stretched letters (\"sexxx\"), spaced-out letters and look-alikes such as \"s3x\" match too. "
    .. "Ignoring someone also forgets the profile Kinship holds for them.")
  card:OnRefresh(function() S:RefreshSettings() end)
end })

---------------------------------------------------------------------------
-- Start-up and events
---------------------------------------------------------------------------
K:On("LOGIN", function()
  K.db.ignored = K.db.ignored or {}
  K.db.safety = K.db.safety or {}
  local db = K.db.safety
  db.trusted = db.trusted or {}
  if type(db.words) ~= "table" then
    db.words = {}
    for _, w in ipairs(DEFAULT_WORDS) do db.words[w] = true end
  end
  db.level = db.level or 2
  if K.db.settings.matureFilter == nil then K.db.settings.matureFilter = true end
  -- Profiles stored before the filter existed, or before its matching last
  -- changed (SCAN_RULES), are checked once, quietly.
  if db.scanned ~= SCAN_RULES then
    db.scanned = SCAN_RULES
    C_Timer.After(5, function() S:RescanAll() end)
  end
end)

K:On("SAFETY", function()
  for _, c in ipairs(S.covers) do
    if c.name then K.Try("mature cover", c.Check, c, c.name) end
  end
end)
