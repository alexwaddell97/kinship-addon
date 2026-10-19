-- Kinship RP: Settings page. A scrolling stack of cards, one per section,
-- with a search box that finds settings by what they do: whole words, the
-- start of a word, small typos, plurals, and everyday names for things
-- ("pvp" finds the Warfront, "mature" finds Safety). Matching cards come
-- first and the matching lines are lit, their matching letters coloured;
-- "on" or "off" in a search narrows it to switches in that state. While you
-- type, a list under the box offers the best-matching settings themselves:
-- arrows and Enter (or a click) jump straight to one.
-- Features add their own section with K:RegisterSettings({ id, title, order, shown, keywords, build = fn(card) }).
-- shown = fn() -> false hides the whole card (a switched-off feature).
-- keywords = "words people might search for" (optional; titles and labels are searched anyway).
-- Inside build, a card offers:
--   card:Toggle(label, desc, key | { get = fn, set = fn })   two per row
--   card:Note(text [, reserve])                              full width
--   card:Button(label, onClick [, width])                    full width row
--   card:Segments(label, items, get, set [, width])          a labelled segmented choice
--   card:Space(px)
-- The card is refreshed whenever the page is shown.

local ADDON, ns = ...
local K = ns.K
local UI = K.UI

local CW, CH = 696, 466
local CARD_W = CW - 14
local INNER = CARD_W - 32
local HALF = (INNER - 24) / 2

local S = K.Settings

---------------------------------------------------------------------------
-- Search: words, synonyms, typos
---------------------------------------------------------------------------
-- Everyday words for things, and what they're called here.
local SYNONYMS = {
  pvp = "warfront stance consent rival honour duel enemy faction parley wound",
  war = "warfront stance rival", fight = "warfront duel rival stance", enemy = "warfront rival sighted",
  consent = "consent boundaries injury capture", boundary = "consent injury capture",
  name = "roleplay names titles nameplates unit frames", title = "titles window names",
  nameplate = "nameplates", plate = "nameplates", frame = "unit frames target bar character sheet",
  portrait = "unit frames", tooltip = "tooltips tooltip",
  map = "map scan markers pins minimap stash", minimap = "minimap markers", pin = "markers pins map",
  waypoint = "markers quest map", location = "share my location map scan markers",
  mature = "safety mature filter", nsfw = "safety mature filter", adult = "safety mature filter",
  block = "ignore safety", mute = "ignore safety", hide = "ignore hidden off",
  chat = "roleplay chat emote speech languages links", emote = "emotes chat parley",
  ooc = "out of character oocs dim", say = "chat speech", language = "chat languages",
  sound = "music theme", music = "theme music",
  bar = "effects bar target bar status button", hud = "effects bar target bar",
  tour = "guides", help = "guides", tutorial = "guides", guide = "guides",
  trade = "items offers give", give = "items offers", bag = "items stashes", stash = "stashes items",
  dice = "dice rolls", roll = "dice rolls",
  trp = "extended import total rp move", trp3 = "extended import total rp move", totalrp = "extended import move",
  extended = "extended features", import = "move import profiles", export = "profiles share code",
  aura = "effects", buff = "effects boons", debuff = "effects afflictions", wound = "effects injury wounds",
  injury = "effects wounds injury", effect = "effects",
  rp = "roleplay", roleplay = "roleplay",
  event = "gatherings", guild = "gatherings guild", house = "gatherings house", public = "gatherings public",
  quest = "quests tracker markers", tracker = "objective tracker quests", objective = "objective tracker",
  letter = "letters", mail = "letters", status = "status button ic lfrp ooc",
  automatic = "automation", auto = "automation", rule = "automation",
  friend = "relationships", relationship = "relationships", kin = "kin relationships letters",
  link = "profile links chat", share = "share profile links code",
  backup = "back up everything restore", restore = "restore back up", lost = "back up restore",
  save = "back up everything", data = "back up everything restore",
}

-- Lowercase words, plurals folded ("nameplates" -> "nameplate").
local function Words(text)
  local out = {}
  text = tostring(text or ""):lower():gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
  for w in text:gmatch("[%w']+") do
    w = w:gsub("'s$", ""):gsub("'", "")
    if #w > 3 and w:sub(-1) == "s" and w:sub(-2) ~= "ss" then w = w:sub(1, -2) end
    if w ~= "" then out[#out + 1] = w end
  end
  return out
end

-- Edit distance, giving up past `max`.
local function Near(a, b, max)
  local la, lb = #a, #b
  if math.abs(la - lb) > max then return false end
  local prev = {}
  for j = 0, lb do prev[j] = j end
  for i = 1, la do
    local cur, best = { [0] = i }, i
    local ca = a:byte(i)
    for j = 1, lb do
      local cost = (ca == b:byte(j)) and 0 or 1
      cur[j] = math.min(prev[j] + 1, cur[j - 1] + 1, prev[j - 1] + cost)
      if cur[j] < best then best = cur[j] end
    end
    if best > max then return false end
    prev = cur
  end
  return prev[lb] <= max
end

-- How well one query word matches a list of words: 3 whole word, 2 start of
-- a word, 1 inside a word, 0.8 a near miss (a typo), 0 no match.
local function WordScore(q, words)
  local best = 0
  local fuzz = (#q >= 7 and 2) or (#q >= 4 and 1) or 0
  for _, w in ipairs(words) do
    if w == q then return 3 end
    if #q >= 2 and w:sub(1, #q) == q then best = math.max(best, 2)
    elseif #q >= 3 and w:find(q, 1, true) then best = math.max(best, 1)
    elseif fuzz > 0 and best < 0.8 and Near(q, w, fuzz) then best = 0.8 end
  end
  return best
end

-- A query word, or one of its everyday stand-ins, against some text.
local function TermScore(q, words)
  local best = WordScore(q, words)
  local syn = SYNONYMS[q]
  if syn and best < 3 then
    for _, alt in ipairs(Words(syn)) do
      local sc = WordScore(alt, words) * 0.8
      if sc > best then best = sc end
    end
  end
  return best
end

-- Text with the parts that match the search coloured: each search word at the
-- start of a word (or anywhere inside one, for three letters or more).
local function Mark(text, terms, hex)
  text = tostring(text or "")
  local lower = text:lower()
  local marks = {}
  for _, q in ipairs(terms) do
    local from = 1
    while #q > 0 do
      local a, b = lower:find(q, from, true)
      if not a then break end
      if #q >= 3 or a == 1 or not lower:sub(a - 1, a - 1):find("%w") then marks[#marks + 1] = { a, b } end
      from = b + 1
    end
  end
  if #marks == 0 then return UI.Escape(text) end
  table.sort(marks, function(x, y) return x[1] < y[1] end)
  local out, at = {}, 1
  for _, m in ipairs(marks) do
    if m[2] >= at then
      local a = math.max(m[1], at)
      out[#out + 1] = UI.Escape(text:sub(at, a - 1))
      out[#out + 1] = "|cff" .. hex .. UI.Escape(text:sub(a, m[2])) .. "|r"
      at = m[2] + 1
    end
  end
  out[#out + 1] = UI.Escape(text:sub(at))
  return table.concat(out)
end

local function NewCard(parent, def)
  local card = UI.Panel(parent)
  card:SetWidth(CARD_W)
  local title = UI.Section(card, def.title)
  title:SetPoint("TOPLEFT", 21, -15)
  card.y, card.col, card.rowH = -42, 0, 0
  card.refreshers = {}
  card.items = {}      -- what search looks through: { widget, text = fn() or string, get = toggle state }
  card.titleText = def.title

  local function EndRow()
    if card.col > 0 then
      card.y = card.y - card.rowH - 12
      card.col, card.rowH = 0, 0
    end
  end
  card.EndRow = EndRow

  function card:Toggle(label, desc, key)
    local get = type(key) == "table" and key.get or function() return S()[key] and true or false end
    local set = type(key) == "table" and key.set or function(v) S()[key] = v end
    local t = UI.Toggle(self, label, desc, get, set, HALF, true)
    t:SetPoint("TOPLEFT", 16 + self.col * (HALF + 24), self.y)
    self.items[#self.items + 1] = { widget = t, text = (label or "") .. " " .. (desc or ""), label = label, get = get, fs = t.label }
    t:Refresh()
    self.rowH = math.max(self.rowH, t:GetHeight())
    self.refreshers[#self.refreshers + 1] = function() t:Refresh() end
    self.col = self.col + 1
    if self.col == 2 then EndRow() end
    return t
  end

  function card:Note(text, reserve)
    EndRow()
    local n = UI.Text(self, text, "Small", "subtle", INNER)
    n:SetPoint("TOPLEFT", 16, self.y)
    self.items[#self.items + 1] = { widget = n, text = function() return n:GetText() end }
    n:SetSpacing(2)
    self.y = self.y - math.max(n:GetStringHeight(), reserve or 0) - 12
    return n
  end

  function card:Button(label, onClick, width)
    EndRow()
    local b = UI.Button(self, label, width or 160, 26)
    b:SetPoint("TOPLEFT", 16, self.y)
    self.items[#self.items + 1] = { widget = b, text = function() return b:GetText() end, button = true }
    b:SetScript("OnClick", onClick)
    self.y = self.y - 26 - 12
    return b
  end

  function card:Segments(label, items, get, set, width)
    EndRow()
    local l = UI.Text(self, label, "Body", "text")
    l:SetPoint("TOPLEFT", 16, self.y - 5)
    local seg = UI.Segments(self, items, width or 100, function(key) set(key) end)
    seg:SetPoint("TOPRIGHT", -16, self.y)
    local words = { label }
    for _, it in ipairs(items) do words[#words + 1] = it.label end
    self.items[#self.items + 1] = { widget = l, wide = seg, text = table.concat(words, " "), label = label, fs = l }
    self.refreshers[#self.refreshers + 1] = function() seg:Select(get()) end
    seg:Select(get())
    self.y = self.y - 24 - 14
    return seg
  end

  function card:Space(px) EndRow(); self.y = self.y - (px or 8) end

  function card:OnRefresh(fn) self.refreshers[#self.refreshers + 1] = fn end

  local ok, err = pcall(def.build, card)
  if not ok then K:CaughtError("settings " .. tostring(def.id), err) end
  EndRow()
  card:SetHeight(-card.y + 6)

  -- A soft light behind each line, lit when a search matches it.
  for _, it in ipairs(card.items) do
    local hl = card:CreateTexture(nil, "BACKGROUND", nil, 2)
    hl:SetPoint("TOPLEFT", it.widget, "TOPLEFT", -8, 5)
    hl:SetPoint("BOTTOMRIGHT", it.wide or it.widget, "BOTTOMRIGHT", 8, -5)
    hl:SetTexture("Interface\\Buttons\\WHITE8X8")
    hl:Hide()
    it.hl = hl
  end
  card.keywords = def.keywords

  -- Score this card for a search: every query word must match somewhere
  -- (title, keywords or a line). Returns score, or 0; lights matching lines.
  -- state: "on" / "off" narrows matches to switches in that state.
  function card:Score(terms, state)
    local title = Words(self.titleText .. " " .. (self.keywords or "") .. " " .. (def.id or ""))
    local total, lit = 0, {}
    for _, it in ipairs(self.items) do
      local t = it.text
      if type(t) == "function" then local ok2, v = K.Try("settings", t); t = ok2 and v or "" end
      it.words = Words(t)
      it.hit = 0
    end
    for _, q in ipairs(terms) do
      local best = TermScore(q, title) * 1.6
      for _, it in ipairs(self.items) do
        local sc = TermScore(q, it.words) * (it.label and 1.2 or 1)
        if sc > 0 then it.hit = it.hit + sc end
        if sc > best then best = sc end
      end
      if best == 0 then
        for _, it in ipairs(self.items) do it.hit = 0 end
        return 0
      end
      total = total + best
    end
    local any = false
    for _, it in ipairs(self.items) do
      local on = it.hit > 0 or (#terms == 0 and it.get ~= nil)
      if state and it.get then
        local okg, v = K.Try("settings", it.get)
        local isOn = okg and v and true or false
        on = (#terms == 0 or it.hit > 0) and (isOn == (state == "on"))
      elseif state then
        on = false
      end
      it.lit = on
      if on then any = true end
    end
    if state and not any then return 0 end
    return total + (any and 0.5 or 0)
  end

  function card:Light(on, terms)
    local a = K:Theme().accent
    local hex = UI.CardHex(a)
    for _, it in ipairs(self.items) do
      it.hl:SetVertexColor(a[1], a[2], a[3], 0.12)
      local lit = on and it.lit and true or false
      it.hl:SetShown(lit)
      if it.fs and it.label then
        it.fs:SetText(lit and terms and #terms > 0 and Mark(it.label, terms, hex) or it.label)
      end
    end
  end
  return card
end

K:RegisterPage({
  id = "settings", title = "Settings", heading = "Settings", hidden = true,
  subtitle = "Choose what Kinship does for you.",

  build = function(c)
    c.query = ""
    c.search = UI.Search(c, 300, "Search settings: nameplates, pvp, map pins...", function(text)
      c.query = text
      c.token = (c.token or 0) + 1
      local token = c.token
      C_Timer.After(0.12, function() if c.token == token then K.Journal:RefreshCurrent(); c.sf:SetVerticalScroll(0) end end)
    end)
    c.search:SetPoint("TOPLEFT", 0, 0)
    c.search:HookScript("OnEnterPressed", function(self)
      local pick = c.suggest:IsShown() and c.suggestions and c.suggestions[c.sel or 1]
      self:ClearFocus()
      if pick then c:Jump(pick) elseif c.firstMatch then c.sf:SetVerticalScroll(0) end
    end)
    c.search:HookScript("OnArrowPressed", function(_, key)
      local list = c.suggestions
      if not (list and #list > 0 and c.suggest:IsShown()) then return end
      if key == "DOWN" then c.sel = (c.sel or 1) % #list + 1
      elseif key == "UP" then c.sel = ((c.sel or 1) - 2) % #list + 1 end
      c:PaintSuggestions()
    end)
    c.search:HookScript("OnEditFocusGained", function() c:ShowSuggestions() end)
    c.search:HookScript("OnEditFocusLost", function()
      C_Timer.After(0.15, function() if not c.search:HasFocus() then c.suggest:Hide() end end)
    end)

    -- Up to eight best-matching settings, under the box
    local SW, SH = 460, 26
    local sug = UI.Panel(c)
    c.suggest = sug
    sug:SetWidth(SW)
    sug:SetPoint("TOPLEFT", c.search, "BOTTOMLEFT", 0, -4)
    sug:SetFrameLevel(c:GetFrameLevel() + 60)
    sug:EnableMouse(true)
    sug:Hide()
    sug.rows = {}
    for i = 1, 8 do
      local r = CreateFrame("Button", nil, sug)
      r:SetSize(SW - 8, SH)
      r:SetPoint("TOPLEFT", 4, -4 - (i - 1) * SH)
      r.hl = r:CreateTexture(nil, "BACKGROUND")
      r.hl:SetAllPoints()
      r.hl:SetTexture("Interface\\Buttons\\WHITE8X8")
      r.bar = r:CreateTexture(nil, "BORDER")
      r.bar:SetTexture("Interface\\Buttons\\WHITE8X8")
      r.bar:SetWidth(2)
      r.bar:SetPoint("TOPLEFT"); r.bar:SetPoint("BOTTOMLEFT")
      r.text = UI.Text(r, "", "Body", "text", SW - 170)
      r.text:SetPoint("LEFT", 10, 0)
      r.text:SetWordWrap(false)
      r.where = UI.Text(r, "", "Small", "subtle", 140)
      r.where:SetPoint("RIGHT", -10, 0)
      r.where:SetJustifyH("RIGHT")
      r.where:SetWordWrap(false)
      r:SetScript("OnEnter", function(self) c.sel = self.index; c:PaintSuggestions() end)
      -- On press, not release: the box loses focus (and the list) as the mouse goes down.
      r:SetScript("OnMouseDown", function(self) local pick = c.suggestions and c.suggestions[self.index]; if pick then c:Jump(pick) end end)
      sug.rows[i] = r
    end

    function c:PaintSuggestions()
      local t = K:Theme()
      for i, r in ipairs(sug.rows) do
        local on = i == self.sel
        r.hl:SetVertexColor(t.accent[1], t.accent[2], t.accent[3], on and 0.16 or 0)
        r.bar:SetVertexColor(t.accent[1], t.accent[2], t.accent[3], on and 1 or 0)
      end
    end

    function c:ShowSuggestions()
      local list = self.suggestions or {}
      if #list == 0 or not self.search:HasFocus() then sug:Hide() return end
      local hex = UI.CardHex(K:Theme().accent)
      for i, r in ipairs(sug.rows) do
        local it = list[i]
        r:SetShown(it ~= nil)
        if it then
          r.index = i
          r.text:SetText(Mark(it.label, self.terms or {}, hex))
          local state = ""
          if it.get then
            local ok, v = K.Try("settings", it.get)
            if ok then state = v and "  ·  On" or "  ·  Off" end
          end
          r.where:SetText(UI.Escape(it.card.titleText) .. state)
        end
      end
      if not self.sel or self.sel > #list then self.sel = 1 end
      sug:SetHeight(8 + math.min(#list, #sug.rows) * SH)
      self:PaintSuggestions()
      sug:Show()
    end

    -- Bring a setting into view and flash it.
    function c:Jump(pick)
      sug:Hide()
      self.search:ClearFocus()
      local card, it = pick.card, pick.item
      local within = (card:GetTop() or 0) - (it.widget:GetTop() or 0)
      local range = math.max(0, self.child:GetHeight() - self.sf:GetHeight())
      self.sf:SetVerticalScroll(math.max(0, math.min(range, (card.layoutY or 0) + within - 40)))
      local a = K:Theme().accent
      it.hl:Show()
      UI.SetProgress(it, 1)
      UI.Tween(it, 0, 1.2, function(p)
        it.hl:SetVertexColor(a[1], a[2], a[3], 0.12 + 0.30 * p)
        if p == 0 and not it.lit then it.hl:Hide() end
      end)
    end
    c.found = UI.Text(c, "", "Small", "deskSubtle", 360)
    c.found:SetPoint("LEFT", c.search, "RIGHT", 12, 0)
    c.found:SetWordWrap(false)
    c.none = UI.Text(c, "", "Read", "deskSubtle", 420)
    c.none:SetPoint("TOP", 0, -110)
    c.none:SetJustifyH("CENTER")
    c.none:SetSpacing(3)

    local sf = CreateFrame("ScrollFrame", nil, c)
    c.sf = sf
    sf:SetPoint("TOPLEFT", 0, -34)
    sf:SetPoint("BOTTOMRIGHT", -12, 0)
    local child = CreateFrame("Frame", nil, sf)
    child:SetSize(CARD_W, 1)
    sf:SetScrollChild(child)
    UI.ScrollBar(sf, "desk", 60)
    c.child = child
    c.cards = {}
    for _, def in ipairs(K.settingsSections) do
      local card = NewCard(child, def)
      card.def = def
      c.cards[#c.cards + 1] = card
    end
  end,

  refresh = function(c)
    -- What's being searched for: words, and "on" / "off" for switch state.
    local terms, state = {}, nil
    for _, w in ipairs(Words(c.query or "")) do
      if w == "on" or w == "enabled" then state = "on"
      elseif w == "off" or w == "disabled" then state = "off"
      elseif w ~= "the" and w ~= "a" and w ~= "my" and w ~= "of" and w ~= "to" and w ~= "and" then terms[#terms + 1] = w end
    end
    local searching = #terms > 0 or state ~= nil

    local order = {}
    for i, card in ipairs(c.cards) do
      local shown = true
      if card.def.shown then
        local ok, v = K.Try("settings", card.def.shown)
        shown = not ok or v ~= false
      end
      if card.def.trp3 == "hide" and K:Compat() then shown = false end   -- Total RP 3 does this while it runs
      if shown then for _, fn in ipairs(card.refreshers) do K.Try("settings", fn) end end
      local score = 1
      if shown and searching then score = card:Score(terms, state) end
      card:Light(searching and score > 0, terms)
      card.searchScore = score
      card.listIndex = i
      if shown and score > 0 then order[#order + 1] = card else card:Hide() end
    end
    if searching then
      table.sort(order, function(a, b)
        if a.searchScore ~= b.searchScore then return a.searchScore > b.searchScore end
        return a.listIndex < b.listIndex
      end)
    end
    local y = 0
    for _, card in ipairs(order) do
      card:Show()
      card:ClearAllPoints()
      card:SetPoint("TOPLEFT", 0, -y)
      card.layoutY = y
      y = y + card:GetHeight() + 10
    end

    -- The settings themselves that match best, for the list under the box
    local picks = {}
    if #terms > 0 then
      for _, card in ipairs(order) do
        for _, it in ipairs(card.items) do
          local label = it.label or (it.button and it.widget:GetText()) or nil
          if it.lit and label and label ~= "" then
            picks[#picks + 1] = { card = card, item = it, label = label, get = it.get,
                                  score = it.hit + card.searchScore * 0.1 }
          end
        end
      end
      table.sort(picks, function(a, b) return a.score > b.score end)
      for i = #picks, 9, -1 do picks[i] = nil end
    end
    c.suggestions, c.terms, c.sel = picks, terms, 1
    c:ShowSuggestions()
    c.child:SetHeight(math.max(1, y))
    c.firstMatch = order[1]

    if searching then
      c.found:SetText(#order == 0 and "" or ((#order == 1 and "1 section" or (#order .. " sections"))
        .. (#picks > 0 and "  ·  arrows and Enter to jump to one" or "")))
      c.none:SetShown(#order == 0)
      c.none:SetText(("Nothing matches \"%s\".\nTry what it does, like nameplates, effects, chat or map pins."):format(UI.Escape(c.query or "")))
    else
      c.found:SetText("")
      c.none:Hide()
    end
  end,
})

---------------------------------------------------------------------------
-- Kinship's own sections
---------------------------------------------------------------------------
K:RegisterSettings({ id = "chat", trp3 = "hide", title = "Roleplay chat", order = 10, build = function(card)
  card:Toggle("Roleplay names", "Profile names in roleplay gold, with the character name after them.", "chatNames")
  card:Toggle("Colour emotes and speech", "\"Quotes\" in emotes and *actions* in speech.", "chatEmotes")
  card:Toggle("Dim (( out of character ))", "Grey out text in double brackets.", "chatOOC")
  card:Toggle("NPC speech", "/e || Guard says: Halt!  speaks as someone else.", "chatNPC")
  local note = card:Note("", 14)
  card:OnRefresh(function()
    local other = K.Comm:OtherRPAddon()
    note:SetText(other and ("|cffe6a04c%s is still running and will style chat too.|r Move over under General to switch it off.")
      :format(K.Import.Label(other)) or "Works in say, yell, emote, party, raid, guild and whispers.")
  end)
end })

K:RegisterSettings({ id = "warfront", title = "Warfront", order = 20, build = function(card)
  card:Toggle("Battle toasts", "A card after a victory or defeat, and a prompt when you fall.", "warToasts")
  card:Toggle("Record battles in your Chronicle", "Victories and defeats become Chronicle entries.", "warChronicle")
  card:Toggle("Remember enemies you meet", "Enemy players you target or mouse over are kept under Sighted.", "warSightings")
  card:Toggle("Rival line in tooltips", "Your standing and tally when you mouse over a rival.", "warTooltip")
  card:Toggle("Beside the PvP window", "Your record and latest rivals in a card next to the game's PvP window.", "pvpCard")
  card:Toggle("Narrate parley for your side", "A short custom emote alongside each Parley emote.", "parleyNarrate")
end })

K:RegisterSettings({ id = "letters", title = "Letters", order = 30, build = function(card)
  card:Toggle("Only accept letters from my Kin", "Letters from anyone else are quietly turned away.", {
    get = function() return S().lettersFrom == "kin" end,
    set = function(v) S().lettersFrom = v and "kin" or "anyone" end,
  })
end })

-- The game's Key Bindings, opened where Kinship's keys are (AddOns > Kinship RP).
local function OpenKeyBindings()
  if InCombatLockdown() then K:Print("Key bindings can't be opened in combat.") return end
  local S = rawget(_G, "Settings")
  if S and S.OpenToCategory and S.KEYBINDINGS_CATEGORY_ID and pcall(S.OpenToCategory, S.KEYBINDINGS_CATEGORY_ID) then return end
  local load = (C_AddOns and C_AddOns.LoadAddOn) or rawget(_G, "LoadAddOn")
  if load then pcall(load, "Blizzard_BindingUI") end
  local kb = rawget(_G, "KeyBindingFrame")
  if kb then pcall(ShowUIPanel, kb) else K:Print("Open Key Bindings from the game menu, under AddOns > Kinship RP.") end
end

K:RegisterSettings({ id = "general", title = "General", order = 90, keywords = "backup restore saved data key bindings keys",
    build = function(card)
  card:Toggle("Status button", "The small IC / LFRP / OOC badge. Shift-drag it to move it.", {
    get = function() return K.db.statusButton.shown and true or false end,
    set = function(v) K.db.statusButton.shown = v; K.StatusButton:Update() end,
  })
  card:Toggle("Minimap button", "Click it for your journal, right-click for Settings.", {
    get = function() return not (K.db.minimap and K.db.minimap.hide) end,
    set = function(v) K:SetMinimapButton(v) end,
  })
  card:Toggle("Game menu button", "A Kinship button just below the game menu (Esc), in the same style as its buttons.", {
    get = function() return K.db.settings.gameMenuButton ~= false end,
    set = function(v) K.db.settings.gameMenuButton = v end,
  })
  card:EndRow()
  local note = card:Note("", 28)
  local move = card:Button("Move to Kinship", function() K.Import:Show(true) end, 160)
  local adds = card:Button("What Kinship adds", function() if K.TRP3 then K.TRP3:Show() end end, 170)
  card:Button("Support Kinship on Ko-fi", function() if K.Support then K.Support:Show() end end, 200)
  local keys = card:Button("Key bindings", OpenKeyBindings, 130)
  UI.Tooltip(keys, "Key bindings", "Keys for the journal, Parley wheel, dice, satchel, your status and your target's profile, "
    .. "under AddOns > Kinship RP.")
  card:OnRefresh(function()
    local other = K.Comm:OtherRPAddon()
    if K:Compat() then
      note:SetText(("Working alongside Total RP 3: it keeps %s. Move to Kinship to bring your profiles across and run Kinship on its own.")
        :format(K.TRP3 and K.TRP3.KEEPS or "your profile"))
    else
      note:SetText(other and ("%s is still running. Bring your profiles into Kinship and switch it off."):format(K.Import.Label(other))
        or "Kinship is your only roleplay addon. Nothing else is writing to your profile.")
    end
    move:SetShown(other ~= nil)
    adds:SetShown(K:Compat())
  end)
  if K.Backup then K.Backup:AddSettings(card) end
end })
