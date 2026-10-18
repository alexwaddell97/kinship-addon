-- Kinship RP: Warfront page. Three tabs:
--   Rivals            - everyone you've clashed with, and where it stands
--   Stance & consent  - how you like PvP stories to go (shared with others)
--   Parley            - the emotes that cross the faction line

local ADDON, ns = ...
local K = ns.K
local UI = K.UI
local W = K.War

local CW, CH, TOP = 696, 466, 40
local BODY_H = CH - TOP
local LEFT_W = 300
local FACTION_COLOR = { Horde = { 0.88, 0.30, 0.26 }, Alliance = { 0.30, 0.55, 0.92 } }

local Short = K.Short

local function ClassName(class)
  return class and (LOCALIZED_CLASS_NAMES_MALE and LOCALIZED_CLASS_NAMES_MALE[class] or class:lower()) or nil
end

local function Describe(r)
  local parts = {}
  if r.race then parts[#parts + 1] = r.race end
  if r.class then parts[#parts + 1] = ClassName(r.class) end
  local s = table.concat(parts, " ")
  if r.level then s = s .. (s ~= "" and ", " or "") .. "level " .. r.level end
  return s ~= "" and s or "Details unknown"
end

-- Class colours, darkened when printed on a cream card.
local function NameColor(class)
  local r, g, b = UI.ClassColor(class)
  if K:Theme().light then return r * 0.55, g * 0.55, b * 0.55 end
  return r, g, b
end

-- A small number tile: big figure over a label.
local function Tile(parent, label, w)
  local t = CreateFrame("Frame", nil, parent)
  t:SetSize(w, 52)
  t.bg = t:CreateTexture(nil, "BACKGROUND")
  t.bg:SetAllPoints()
  t.num = UI.Text(t, "0", "Huge", "heading")
  t.num:SetPoint("TOP", 0, -7)
  t.label = UI.Text(t, label, "Label", "subtle")
  t.label:SetPoint("BOTTOM", 0, 7)
  UI:OnTheme(function(th) t.bg:SetColorTexture(unpack(th.sectionBg)) end)
  return t
end

---------------------------------------------------------------------------
-- Rivals
---------------------------------------------------------------------------
local function BuildRivals(tab)
  tab.filter = "rivals"
  tab.seg = UI.Segments(tab, { { key = "rivals", label = "Rivals" }, { key = "sighted", label = "Sighted" },
    { key = "all", label = "Everyone" } }, 100, function(k) tab.filter = k; K.Journal:RefreshCurrent() end)
  tab.seg:SetPoint("TOPLEFT", 0, 0)

  tab.list = UI.List(tab, LEFT_W, BODY_H - 34, 50,
    "No rivals yet. Duels, honourable kills and the enemies you face in the field will gather here.",
    function(row)
      row.icon = row:CreateTexture(nil, "ARTWORK")
      row.icon:SetSize(32, 32)
      row.icon:SetPoint("LEFT", 10, 0)
      UI.Round(row.icon)
      row.name = UI.Text(row, "", "Header", "plain", 150)
      row.name:SetPoint("TOPLEFT", row.icon, "TOPRIGHT", 10, 0)
      row.name:SetWordWrap(false)
      row.sub = UI.Text(row, "", "Small", "subtle", 148)
      row.sub:SetPoint("TOPLEFT", row.name, "BOTTOMLEFT", 0, -3)
      row.sub:SetWordWrap(false)
      row.tally = UI.Text(row, "", "Header", "heading")
      row.tally:SetPoint("TOPRIGHT", -12, -9)
      row.chip = UI.Chip(row)
      row.chip:SetPoint("BOTTOMRIGHT", -10, 8)
      row:SetScript("OnClick", function(self) tab.selected = self.item; K.Journal:RefreshCurrent() end)
    end, { emptyIcon = K.Art("IconDungeon") })
  tab.list:SetPoint("TOPLEFT", 0, -34)

  -- Detail card --------------------------------------------------------------
  local card = UI.Panel(tab)
  card:SetPoint("TOPLEFT", LEFT_W + 10, 0)
  card:SetPoint("BOTTOMRIGHT")
  local DW = CW - LEFT_W - 10 - 32
  local d = CreateFrame("Frame", nil, card)
  d:SetPoint("TOPLEFT", 18, -16)
  d:SetPoint("BOTTOMRIGHT", -14, 14)
  tab.detail = d

  d.ring = UI.Circle(d, 56, "ARTWORK", 0)
  d.ring:SetPoint("TOPLEFT")
  d.icon = d:CreateTexture(nil, "ARTWORK", nil, 1)
  d.icon:SetSize(50, 50)
  d.icon:SetPoint("CENTER", d.ring)
  UI.Round(d.icon)
  d.name = UI.Text(d, "", "Huge", "plain", DW - 70)
  d.name:SetPoint("TOPLEFT", d.ring, "TOPRIGHT", 12, -1)
  d.name:SetWordWrap(false)
  d.sub = UI.Text(d, "", "Small", "subtle", DW - 70)
  d.sub:SetPoint("TOPLEFT", d.name, "BOTTOMLEFT", 0, -3)
  d.faction = UI.Chip(d)
  d.faction:SetPoint("TOPLEFT", d.sub, "BOTTOMLEFT", 0, -5)
  d.guild = UI.Text(d, "", "Small", "text", DW - 150)
  d.guild:SetPoint("LEFT", d.faction, "RIGHT", 8, 0)
  d.guild:SetWordWrap(false)

  local gl = UI.Text(d, "Standing", "Label", "subtle")
  gl:SetPoint("TOPLEFT", 1, -66)
  local gitems = {}
  for _, g in ipairs(W.GRUDGES) do gitems[#gitems + 1] = { key = g.key, label = g.label, color = g.color } end
  d.grudge = UI.Segments(d, gitems, math.floor(DW / 4), function(key)
    if tab.selected then tab.selected.grudge = key; K:Fire("RIVALS") end
  end)
  d.grudge:SetPoint("TOPLEFT", 0, -80)

  local tw = math.floor((DW - 3 * 8) / 4)
  d.tiles = {}
  for i, label in ipairs({ "Victories", "Defeats", "Draws", "Parleys" }) do
    local t = Tile(d, label, tw)
    t:SetPoint("TOPLEFT", (i - 1) * (tw + 8), -114)
    d.tiles[i] = t
  end

  d.met = UI.Text(d, "", "Small", "subtle", DW)
  d.met:SetPoint("TOPLEFT", 1, -174)
  d.met:SetSpacing(3)

  local ll = UI.Text(d, "Log a clash", "Label", "subtle")
  ll:SetPoint("TOPLEFT", 1, -208)
  local x = 0
  for _, o in ipairs({ "win", "loss", "draw" }) do
    local b = UI.Button(d, ("|cff%s%s|r"):format(UI.Hex(W.OUTCOMES[o].color), W.OUTCOMES[o].label), 82, 24)
    b:SetPoint("TOPLEFT", x, -222)
    b:SetScript("OnClick", function()
      if tab.selected then W:Record(tab.selected.name, o, "Logged by hand") end
    end)
    x = x + 88
  end
  d.forget = UI.Button(d, "Forget", 76, 24)
  d.forget:SetPoint("TOPRIGHT", 0, -222)
  d.forget:SetScript("OnClick", function()
    if tab.selected then W:Remove(K.NameKey(tab.selected.name)); tab.selected = nil end
  end)
  UI.Tooltip(d.forget, "Forget", "Remove this person and their record from your Warfront.")

  local nl = UI.Text(d, "Notes", "Label", "subtle")
  nl:SetPoint("TOPLEFT", 1, -258)
  d.note = UI.TextArea(d, DW, 52, 500, function(text) if tab.selected then tab.selected.note = text end end)
  d.note:SetPoint("TOPLEFT", 0, -272)

  local hl = UI.Text(d, "History", "Label", "subtle")
  hl:SetPoint("TOPLEFT", 1, -334)
  d.history = UI.ReadArea(d, DW, BODY_H - 30 - 348, "Small", "text")
  d.history:SetPoint("TOPLEFT", 0, -348)

  tab.empty = CreateFrame("Frame", nil, card)
  tab.empty:SetAllPoints()
  local ei = tab.empty:CreateTexture(nil, "ARTWORK")
  ei:SetTexture(K.Art("IconDungeon"))
  ei:SetSize(64, 64)
  ei:SetPoint("CENTER", 0, 24)
  ei:SetAlpha(0.75)
  local et = UI.Text(tab.empty, "Choose someone to see your history with them.", "QuestFont", "subtle", 260)
  et:SetPoint("TOP", ei, "BOTTOM", 0, -12)
  et:SetJustifyH("CENTER")
end

local function RefreshRivals(tab)
  tab.seg:Select(tab.filter)
  local items = {}
  for _, r in pairs(K:Rivals()) do
    local isRival = W:IsRival(r)
    if tab.filter == "all" or (tab.filter == "rivals" and isRival) or (tab.filter == "sighted" and not isRival) then
      items[#items + 1] = r
    end
  end
  local function when(r) return math.max(r.last and r.last.t or 0, r.seen or 0, r.first and r.first.t or 0) end
  table.sort(items, function(a, b) return when(a) > when(b) end)

  tab.list:SetItems(items, function(row, r)
    UI.ClassIcon(row.icon, r.class)
    row.name:SetText(Short(r.name))
    row.name:SetTextColor(NameColor(r.class))
    row.sub:SetText(Describe(r))
    local fought = (r.wins or 0) + (r.losses or 0) + (r.draws or 0) > 0
    row.tally:SetText(fought and W:Tally(r) or "")
    local g = W.Grudge(r.grudge)
    if g then row.chip:Set(g.label, g.color)
    elseif (r.sightings or 0) > 0 then row.chip:Set(("Seen %d×"):format(r.sightings), K:Theme().subtle)
    else row.chip:Set(nil) end
    row.sel:SetShown(r == tab.selected)
  end)

  local r, d = tab.selected, tab.detail
  if r and not K:Rivals()[K.NameKey(r.name) or ""] then r, tab.selected = nil, nil end
  d:SetShown(r ~= nil)
  tab.empty:SetShown(r == nil)
  if not r then return end
  if tab.shown ~= r then
    tab.shown = r
    d.note.edit:ClearFocus()   -- so a half-typed note can't follow you to someone else
    d.note.edit:SetText(r.note or "")
    UI.FadeIn(d, 0.2)
  end

  local g = W.Grudge(r.grudge)
  local gc = g and g.color or K:Theme().ui
  d.ring:SetVertexColor(gc[1], gc[2], gc[3], 1)
  UI.ClassIcon(d.icon, r.class)
  d.name:SetText(Short(r.name))
  d.name:SetTextColor(NameColor(r.class))
  d.sub:SetText(Describe(r))
  d.faction:Set(r.faction or (r.enemy and "Enemy") or nil, FACTION_COLOR[r.faction or ""] or (r.enemy and W.OUTCOMES.loss.color))
  d.guild:ClearAllPoints()
  if d.faction:IsShown() then d.guild:SetPoint("LEFT", d.faction, "RIGHT", 8, 0) else d.guild:SetPoint("TOPLEFT", d.sub, "BOTTOMLEFT", 0, -7) end
  d.guild:SetText(r.guild and ("<" .. r.guild .. ">") or "")
  d.grudge:Select(r.grudge)
  for i, n in ipairs({ r.wins or 0, r.losses or 0, r.draws or 0, r.parleys or 0 }) do d.tiles[i].num:SetText(n) end

  local lines = {}
  if r.first then lines[#lines + 1] = ("First crossed paths in %s, %s."):format(r.first.place or "?", K.FormatDate(r.first.t)) end
  if r.last then lines[#lines + 1] = ("Last clash in %s, %s."):format(r.last.place or "?", UI.Ago(r.last.t))
  elseif r.seen then lines[#lines + 1] = ("Last seen %s%s."):format(UI.Ago(r.seen), r.seenPlace and (" in " .. r.seenPlace) or "") end
  d.met:SetText(table.concat(lines, "\n"))

  if not d.note.edit:HasFocus() then d.note.edit:SetText(r.note or "") end
  local hist = {}
  for _, e in ipairs(r.log or {}) do
    local o = W.OUTCOMES[e.o]
    if o then
      hist[#hist + 1] = ("|cff%s%s|r   %s  ·  %s  ·  %s"):format(UI.CardHex(o.color), o.label, e.how or "", e.place or "?", UI.Ago(e.t))
    end
  end
  d.history:SetText(#hist > 0 and table.concat(hist, "\n") or "Nothing recorded yet.")
end

---------------------------------------------------------------------------
-- Stance & consent
---------------------------------------------------------------------------
local function BuildStance(tab)
  local left = UI.Panel(tab)
  left:SetPoint("TOPLEFT")
  left:SetSize(340, BODY_H)
  local lh = UI.Section(left, "Your war stance")
  lh:SetPoint("TOPLEFT", 21, -15)
  local intro = UI.Text(left, "How you like PvP stories to go. Others see it on your tooltip and profile.", "Small", "subtle", 300)
  intro:SetPoint("TOPLEFT", 16, -38)

  tab.stances = {}
  for i, key in ipairs(K.STANCE_ORDER) do
    local s = K.STANCES[key]
    local b = CreateFrame("Button", nil, left)
    b:SetSize(308, 104)
    b:SetPoint("TOPLEFT", 16, -64 - (i - 1) * 112)
    b.bg = b:CreateTexture(nil, "BACKGROUND")
    b.bg:SetAllPoints()
    b.edge = UI.Border(b)
    b.bar = b:CreateTexture(nil, "ARTWORK")
    b.bar:SetColorTexture(s.color[1], s.color[2], s.color[3], 1)
    b.bar:SetWidth(3)
    b.bar:SetPoint("TOPLEFT"); b.bar:SetPoint("BOTTOMLEFT")
    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetSize(38, 38)
    b.icon:SetPoint("TOPLEFT", 16, -14)
    b.icon:SetTexture(s.icon)
    b.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    UI.Round(b.icon)
    b.title = UI.Text(b, s.label, "Header", "heading")
    b.title:SetPoint("TOPLEFT", b.icon, "TOPRIGHT", 12, -2)
    b.check = UI.Chip(b)
    b.check:SetPoint("TOPRIGHT", -10, -12)
    b.desc = UI.Text(b, s.desc, "Small", "text", 236)
    b.desc:SetPoint("TOPLEFT", b.title, "BOTTOMLEFT", 0, -6)
    b.desc:SetSpacing(2)
    b.key = key
    function b:Paint()
      local t = K:Theme()
      local sel = (K:Profile().stance or "duel") == self.key
      local c = s.color
      if sel then self.bg:SetColorTexture(c[1], c[2], c[3], 0.13)
      elseif self.hover then self.bg:SetColorTexture(unpack(t.hover))
      else self.bg:SetColorTexture(0, 0, 0, 0) end
      if sel then self.edge:SetColor(c[1], c[2], c[3], 0.9) else self.edge:SetColor(unpack(t.panelEdge)) end
      self.bar:SetAlpha(sel and 1 or 0.35)
      self.icon:SetDesaturated(not sel and not self.hover)
      self.check:Set(sel and "Your stance" or nil, c)
    end
    b:SetScript("OnEnter", function(self) self.hover = true; self:Paint() end)
    b:SetScript("OnLeave", function(self) self.hover = false; self:Paint() end)
    b:SetScript("OnClick", function(self)
      if SOUNDKIT then PlaySound(SOUNDKIT.IG_CHARACTER_INFO_TAB) end
      K:SetStance(self.key)
    end)
    UI:OnTheme(function() b:Paint() end)
    tab.stances[i] = b
  end

  local right = UI.Panel(tab)
  right:SetPoint("TOPLEFT", left, "TOPRIGHT", 10, 0)
  right:SetPoint("BOTTOMRIGHT")
  local rw = CW - 350 - 32
  local rh = UI.Section(right, "Consent")
  rh:SetPoint("TOPLEFT", 21, -15)
  local rintro = UI.Text(right, "What your character can go through in a story with you. \"Ask\" means check with you out of character first.",
    "Small", "subtle", rw)
  rintro:SetPoint("TOPLEFT", 16, -38)
  rintro:SetSpacing(2)

  tab.consent = {}
  local vitems = {}
  for _, v in ipairs(K.CONSENT_VALUES) do vitems[#vitems + 1] = { key = v.key, label = v.label, color = v.color } end
  for i, f in ipairs(K.CONSENT) do
    local y = -82 - (i - 1) * 52
    local l = UI.Text(right, f.label, "Body", "heading")
    l:SetPoint("TOPLEFT", 16, y)
    local dsc = UI.Text(right, f.desc, "Small", "subtle", rw - 150)
    dsc:SetPoint("TOPLEFT", l, "BOTTOMLEFT", 0, -3)
    local seg = UI.Segments(right, vitems, 46, function(v) K:SetConsent(f.key, v) end)
    seg:SetPoint("TOPRIGHT", -16, y + 2)
    if K:Compat() then for _, b in ipairs(seg.buttons) do b:Disable() end end   -- Total RP 3's, shown here
    seg.field = f.key
    tab.consent[i] = seg
  end
  local foot = UI.Text(right, K:Compat()
    and "Total RP 3 shares these as your RP style while it runs, so set them there. Kinship shows what it shares."
    or ("Shared through the standard roleplay fields, so Total RP 3, MyRolePlay and XRP users see it too. "
    .. "Players of the other faction only receive it if they're your Battle.net friend."), "Small", "subtle", rw)
  foot:SetPoint("BOTTOMLEFT", 16, 14)
  foot:SetSpacing(2)
end

local function RefreshStance(tab)
  for _, b in ipairs(tab.stances) do b:Paint() end
  local consent = K:Profile().consent or {}
  for _, seg in ipairs(tab.consent) do seg:Select(consent[seg.field]) end
end

---------------------------------------------------------------------------
-- Parley
---------------------------------------------------------------------------
local function BuildParley(tab)
  local top = UI.Panel(tab)
  top:SetPoint("TOPLEFT")
  top:SetPoint("TOPRIGHT")
  top:SetHeight(104)
  local icon = top:CreateTexture(nil, "ARTWORK")
  icon:SetSize(52, 52)
  icon:SetPoint("LEFT", 18, 0)
  icon:SetTexture("Interface\\Icons\\Ability_DualWield")
  icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
  UI.Round(icon)
  local title = UI.Text(top, "Speak across the battle line", "Title", "heading")
  title:SetPoint("TOPLEFT", icon, "TOPRIGHT", 16, 4)
  local text = UI.Text(top, "The other faction can't read your words, and your own emotes reach them only as \"strange gestures\". "
    .. "The game's built-in emotes do get through, so the Parley wheel keeps the ones that matter in a fight one flick away.",
    "Small", "text", 420)
  text:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -6)
  text:SetSpacing(2)
  local open = UI.Button(top, "Open the wheel", 140, 26)
  open:SetPoint("TOPRIGHT", -16, -22)
  open:SetScript("OnClick", function() K.Parley:Open() end)
  tab.key = UI.Text(top, "", "Small", "subtle", 150)
  tab.key:SetPoint("TOP", open, "BOTTOM", 0, -8)
  tab.key:SetJustifyH("CENTER")

  local cols, gap = 4, 10
  local cw = math.floor((CW - gap * (cols - 1)) / cols)
  for i, s in ipairs(K.Parley.SLOTS) do
    local col, row = (i - 1) % cols, math.floor((i - 1) / cols)
    local b = CreateFrame("Button", nil, tab)
    b:SetSize(cw, 104)
    b:SetPoint("TOPLEFT", col * (cw + gap), -116 - row * (104 + gap))
    b.bg = b:CreateTexture(nil, "BACKGROUND")
    b.bg:SetAllPoints()
    b.tint = b:CreateTexture(nil, "BACKGROUND", nil, 1)
    b.tint:SetAllPoints()
    b.edge = UI.Border(b)
    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetSize(34, 34)
    b.icon:SetPoint("TOPLEFT", 14, -14)
    b.icon:SetTexture("Interface\\Icons\\" .. s.icon)
    b.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    UI.Round(b.icon)
    b.label = UI.Text(b, s.label, "Header", "heading")
    b.label:SetPoint("LEFT", b.icon, "RIGHT", 10, 0)
    b.sees = UI.Text(b, s.sees, "Small", "subtle", cw - 28)
    b.sees:SetPoint("TOPLEFT", 14, -58)
    b.sees:SetSpacing(2)
    local function paint(p)
      local t = K:Theme()
      b.bg:SetColorTexture(unpack(t.panel))
      local h = t.hover
      b.tint:SetColorTexture(h[1], h[2], h[3], (h[4] or 1) * 1.5 * p)
      b.edge:SetColor(UI.Mix(t.panelEdge, { t.accent[1], t.accent[2], t.accent[3], 0.9 }, p))
    end
    b:SetScript("OnEnter", function(self)
      UI.Tween(self, 1, 0.12, paint)
      GameTooltip:SetOwner(self, "ANCHOR_TOP")
      GameTooltip:SetText(s.label, 1, 0.82, 0)
      GameTooltip:AddLine("Click to use it now, on your target (or everyone nearby).", 1, 1, 1, true)
      GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function(self) UI.Tween(self, 0, 0.15, paint); GameTooltip:Hide() end)
    b:SetScript("OnClick", function() K.Parley:Choose(i) end)
    tab.slots = tab.slots or {}
    tab.slots[i] = b
    UI:OnTheme(function() paint(UI.Progress(b)) end)
  end

  local narr = UI.Toggle(tab, "Narrate for your own side",
    "Also send a short custom emote (\"levels a weapon at Grommash. A challenge.\"). Your faction reads it; the other side sees strange gestures.",
    function() return K.db.settings.parleyNarrate end, function(v) K.db.settings.parleyNarrate = v end, CW)
  narr:SetPoint("BOTTOMLEFT", 0, 4)
end

local function RefreshParley(tab)
  local key = GetBindingKey and GetBindingKey("KINSHIPRP_PARLEY")
  tab.key:SetText(key and ("Hold |cffffffff" .. key .. "|r, aim, release") or "Tip: bind a key in Key Bindings, under AddOns > Kinship RP")
end

---------------------------------------------------------------------------
-- The page
---------------------------------------------------------------------------
K:RegisterPage({
  id = "warfront", title = "Warfront", heading = "Warfront",
  subtitle = "Rivals, stance and parley for RP-PvP.",

  build = function(c)
    c.tab = 1
    c.tabs = UI.TabBar(c, { "Rivals", "Stance & consent", "Parley" }, function(i) c.tab = i; K.Journal:RefreshCurrent() end, true)
    c.tabs:SetPoint("TOPLEFT", -10, 2)
    c.stanceChip = UI.Chip(c, "Small", true)
    c.stanceChip:SetPoint("TOPRIGHT", 0, -4)
    c.stanceChip:SetHeight(22)
    c.frames = {}
    for i = 1, 3 do
      local f = CreateFrame("Frame", nil, c)
      f:SetPoint("TOPLEFT", 0, -TOP)
      f:SetSize(CW, BODY_H)
      f:Hide()
      c.frames[i] = f
    end
    BuildRivals(c.frames[1])
    BuildStance(c.frames[2])
    BuildParley(c.frames[3])
  end,

  refresh = function(c)
    if W.focus then c.tab = 1; c.frames[1].selected = W.focus; W.focus = nil end
    c.tabs:Select(c.tab)
    for i, f in ipairs(c.frames) do f:SetShown(i == c.tab) end
    if c.shownTab ~= c.tab then
      if c.shownTab then UI.FadeIn(c.frames[c.tab], 0.2) end
      c.shownTab = c.tab
    end
    local s = K.STANCES[K:Profile().stance or "duel"] or K.STANCES.duel
    c.stanceChip:Set(s.label, s.color)
    if c.tab == 1 then RefreshRivals(c.frames[1])
    elseif c.tab == 2 then RefreshStance(c.frames[2])
    else RefreshParley(c.frames[3]) end
  end,
})

K:On("RIVALS", function()
  local J = K.Journal
  if J.frame and J.frame:IsShown() and J.current and J.pages[J.current].id == "warfront" then J:RefreshCurrent() end
end)
