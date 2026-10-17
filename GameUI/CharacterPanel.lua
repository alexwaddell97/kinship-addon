-- Kinship RP: roleplay on the character sheet and the inspect window.
--
-- Character sheet (C): a native side tab joins the window's own column of
-- round tabs (built from the game's LargeSideTabButtonTemplate, the same as
-- its Character / Reputation / Skills tabs). Clicking it turns the right-hand
-- pane into a Roleplay pane in Kinship's own look: your portrait or profile
-- icon and roleplay name, status, "Currently" and OOC notes you can edit in
-- place, your glances and effects, and your war stance and boundaries. Any
-- other tab, or this one again, puts the stats back.
--
-- Window titles: with "Roleplay name in window titles" on, the character
-- window (and the inspect window, for someone whose profile has arrived)
-- shows the roleplay name where the game shows the character name.
--
-- Inspect window: their roleplay profile in a matching panel at its side.
--
-- Blizzard's protected code is never touched: the tab is a sibling of the
-- window's own tabs, the panes are children laid over or beside the window,
-- and titles are only re-labelled after the game sets them.

local ADDON, ns = ...
local K = ns.K
local UI = K.UI
local Safe = K.Safe
local CP = {}
K.CharacterPanel = CP

local WHITE = "Interface\\Buttons\\WHITE8X8"
local PAD = 12
-- The Roleplay tab's icon: a game icon, like the window's own tabs (a masked face, for a persona).
local TAB_ICON = "Interface\\Icons\\Ability_Rogue_Disguise"

local function S() return K.db.settings end
local function Short(n) return Ambiguate and Ambiguate(n, "none") or n end

local function Next(list, current)
  for i, k in ipairs(list) do if k == current then return list[i % #list + 1] end end
  return list[1]
end

-- The colour a name is shown in: their chosen name colour, else their class's.
local function NameRGB(p, unit)
  local P = K.Persona
  local r, g, b
  if P and p then r, g, b = P.NameColor(p) end
  if not r and unit then
    local _, class = UnitClass(unit)
    if Safe(class) and class then r, g, b = UI.ClassColor(class) end
  end
  if not r then local c = K:Theme().deskHeading; r, g, b = c[1], c[2], c[3] end
  return r, g, b
end

---------------------------------------------------------------------------
-- Small pieces, drawn in Kinship's chrome style
---------------------------------------------------------------------------
-- A round icon in a gold ring that brightens on hover.
local function Medallion(parent, size)
  local b = CreateFrame("Button", nil, parent)
  b:SetSize(size + 4, size + 4)
  b.ring = UI.Circle(b, size + 4, "ARTWORK", 0)
  b.ring:SetPoint("CENTER")
  b.icon = b:CreateTexture(nil, "ARTWORK", nil, 1)
  b.icon:SetSize(size, size)
  b.icon:SetPoint("CENTER")
  b.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
  UI.Round(b.icon)
  b.size = size
  function b:Paint(p, color)
    local c = color or self.color or K:Theme().ui
    self.ring:SetVertexColor(c[1], c[2], c[3], 0.55 + 0.45 * (p or 0))
    self.icon:SetSize(self.size + 2 * (p or 0), self.size + 2 * (p or 0))
  end
  b:HookScript("OnEnter", function(self) UI.Tween(self, 1, 0.1, function(p) self:Paint(p) end) end)
  b:HookScript("OnLeave", function(self) UI.Tween(self, 0, 0.12, function(p) self:Paint(p) end) end)
  UI:OnTheme(function() b:Paint(UI.Progress(b)) end)
  return b
end

-- A label-and-value line, optionally clickable (cycles a setting).
local function Line(parent, label, onClick)
  -- A plain frame, not a Button: skins give buttons in the character sheet
  -- their own highlight and brighten their textures.
  local r = CreateFrame("Frame", nil, parent)
  r:SetHeight(20)
  r.label = UI.Text(r, label, "Small", "deskSubtle")
  r.label:SetPoint("LEFT", 2, 0)
  r.value = UI.Text(r, "", "Small", "plain")
  r.value:SetPoint("RIGHT", -2, 0)
  r.value:SetPoint("LEFT", r.label, "RIGHT", 8, 0)
  r.value:SetJustifyH("RIGHT")
  r.value:SetWordWrap(false)
  -- The hover wash: its own faint frame, shown only while hovered.
  r.wash = CreateFrame("Frame", nil, r)
  r.wash:SetAllPoints()
  r.wash:SetFrameLevel(r:GetFrameLevel())
  r.wash:Hide()
  r.hl = r.wash:CreateTexture(nil, "BACKGROUND")
  r.hl:SetAllPoints()
  local function paint(self, p)
    local u = K:Theme().ui
    self.hl:SetColorTexture(u[1], u[2], u[3], 0.08)
    self.wash:SetAlpha(p)
    self.wash:SetShown(p > 0)
  end
  if onClick then
    r:EnableMouse(true)
    r:SetScript("OnMouseUp", function(self, button)
      if button == "LeftButton" and self:IsMouseOver() then onClick(self) end
    end)
    r:SetScript("OnEnter", function(self) UI.Tween(self, 1, 0.1, function(p) paint(self, p) end) end)
    r:SetScript("OnLeave", function(self)
      UI.Tween(self, 0, 0.12, function(p) paint(self, p) end)
      GameTooltip:Hide()
    end)
  else
    r:EnableMouse(false)
  end
  return r
end

-- A row of up to n small round icons (glances or effects), with an empty line.
local function IconRow(parent, n, size, emptyText)
  local row = CreateFrame("Frame", nil, parent)
  row:SetHeight(size + 8)
  row.icons = {}
  for i = 1, n do
    local m = Medallion(row, size)
    m:SetPoint("LEFT", (i - 1) * (size + 8), 0)
    m.time = m:CreateFontString(nil, "OVERLAY")
    m.time:SetFontObject(UI.FONTS.Label)
    local face, fsize = UI.FONTS.Label:GetFont()
    if face then m.time:SetFont(face, fsize, "OUTLINE") end
    m.time:SetPoint("BOTTOM", 0, -2)
    m.time:SetTextColor(1, 0.95, 0.85)
    m:Hide()
    row.icons[i] = m
  end
  row.empty = UI.Text(row, emptyText or "", "Small", "deskSubtle")
  row.empty:SetPoint("LEFT", 2, 0)
  row.empty:SetPoint("RIGHT", -2, 0)
  row.empty:SetWordWrap(false)
  return row
end

---------------------------------------------------------------------------
-- Your Roleplay pane on the character sheet
---------------------------------------------------------------------------
local function BuildPane()
  local cf = _G.CharacterFrame
  local host = cf and cf.RightPaneHost
  if not host then return end
  local pane = CreateFrame("Frame", "KinshipRPCharacterPane", host)
  pane:SetAllPoints(host)
  pane:SetFrameLevel(610)   -- above the stats lists (and another addon's pane at 600)
  pane:EnableMouse(true)
  pane:Hide()
  CP.pane = pane

  -- The backdrop lives on a child frame: character-sheet skins (EllesmereUI's)
  -- fade the textures of every frame in the right pane's host, which would
  -- leave this pane see-through, with the stats list showing behind it.
  pane.back = CreateFrame("Frame", nil, pane)
  pane.back:SetAllPoints(pane)
  pane.back:SetFrameLevel(pane:GetFrameLevel())
  pane.bg = pane.back:CreateTexture(nil, "BACKGROUND")
  pane.bg:SetPoint("TOPLEFT", 4, -4)
  pane.bg:SetPoint("BOTTOMRIGHT", -6, 6)
  pane.bg:SetTexture(WHITE)
  -- Stay on top of whatever else shares the pane's host (the stats lists, which
  -- skins may raise): above the highest of them, each time the pane opens.
  local function Highest(f, depth, skip)
    local top = 0
    for _, child in ipairs({ f:GetChildren() }) do
      if child ~= skip and not (child.IsForbidden and child:IsForbidden()) then
        top = math.max(top, child:GetFrameLevel())
        if depth < 4 then top = math.max(top, Highest(child, depth + 1, skip)) end
      end
    end
    return top
  end
  pane:HookScript("OnShow", function(self)
    self.bg:SetAlpha(1)
    local ok, top = K.Try("character pane", Highest, host, 1, self)
    if ok and top >= self:GetFrameLevel() and top < 9000 then
      -- Lift the pane and everything in it by the same step, so it all keeps its order.
      local delta = top + 5 - self:GetFrameLevel()
      local function Lift(f, depth)
        f:SetFrameLevel(math.min(10000, f:GetFrameLevel() + delta))
        if depth < 12 then
          for _, child in ipairs({ f:GetChildren() }) do Lift(child, depth + 1) end
        end
      end
      K.Try("character pane", Lift, self, 0)
    end
  end)
  pane.edge = CreateFrame("Frame", nil, pane)
  pane.edge:SetPoint("TOPLEFT", pane.bg)
  pane.edge:SetPoint("BOTTOMRIGHT", pane.bg)
  pane.edge.b = UI.Border(pane.edge)
  UI:OnTheme(function(t)
    -- Fully solid: the window colour is a touch see-through, which let the
    -- stats text underneath ghost through this pane.
    pane.bg:SetVertexColor(t.chrome[1], t.chrome[2], t.chrome[3], 1)
    pane.edge.b:SetColor(unpack(t.chromeEdge))
  end)

  -- Who you are (fixed at the top) ----------------------------------------------
  pane.med = Medallion(pane, 40)
  pane.med:SetPoint("TOPLEFT", PAD, -PAD - 2)
  pane.med:SetScript("OnClick", function() K.Journal:Open("persona") end)
  UI.Tooltip(pane.med, "Your look", "Profile icon, name colour and theme music, on the Persona page.")
  pane.name = UI.Text(pane, "", "Header", "plain")
  pane.name:SetPoint("TOPLEFT", pane.med, "TOPRIGHT", 8, -5)
  pane.name:SetPoint("RIGHT", -PAD, 0)
  pane.name:SetWordWrap(false)
  pane.epithet = UI.Text(pane, "", "Small", "deskSubtle")
  pane.epithet:SetPoint("TOPLEFT", pane.name, "BOTTOMLEFT", 0, -4)
  pane.epithet:SetPoint("RIGHT", -PAD, 0)
  pane.epithet:SetWordWrap(false)

  local items = {}
  for _, key in ipairs(K.STATUS_ORDER) do items[#items + 1] = { key = key, label = K.STATUS[key].short, color = K.STATUS[key].color } end
  local alongside = K:Compat()
  if alongside then
    pane.alongside = UI.Text(pane, "Total RP 3 keeps your status, notes and glances.", "Small", "deskSubtle")
    pane.alongside:SetPoint("TOPLEFT", PAD, -62)
    pane.alongside:SetPoint("RIGHT", -PAD, 0)
    pane.alongside:SetSpacing(2)
  else
    pane.status = UI.Segments(pane, items, 60, function(key) K:SetStatus(key) end)
    pane.status:SetPoint("TOPLEFT", PAD, -64)
    for _, b in ipairs(pane.status.buttons) do UI.Tooltip(b, K.STATUS[b.key].label) end
  end

  -- The rest scrolls, between the status buttons and the footer ----------------
  local sf = CreateFrame("ScrollFrame", nil, pane)
  sf:SetPoint("TOPLEFT", PAD, alongside and -100 or -98)
  sf:SetPoint("BOTTOMRIGHT", -PAD - 6, 74)
  local body = CreateFrame("Frame", nil, sf)
  body:SetSize(1, 1)
  sf:SetScrollChild(body)
  pane.sf, pane.body = sf, body
  pane.bar = UI.ScrollBar(sf, "desk", 40)

  local y = 0
  local function Add(widget, h, gap)
    y = y + (gap or 0)
    widget:ClearAllPoints()
    widget:SetPoint("TOPLEFT", body, "TOPLEFT", 0, -y)
    widget:SetPoint("RIGHT", body, "RIGHT", 0, 0)
    if h then widget:SetHeight(h) end
    y = y + (h or widget:GetHeight())
    return widget
  end
  local function Section(text, gap)
    local holder = CreateFrame("Frame", nil, body)
    local s = UI.Section(holder, text, true)
    s:SetPoint("LEFT", 7, 0)
    return Add(holder, 18, gap)
  end

  -- Name in window titles
  pane.titleToggle = UI.Toggle(body, "Name in window titles", nil,
    function() return S().rpTitles == true end,
    function(v) S().rpTitles = v; CP:ApplyTitles() end, 200, false)
  UI.Tooltip(pane.titleToggle, "Roleplay name in window titles",
    "Show your roleplay name where the character window shows your character's name, and others' in the inspect window.")
  Add(pane.titleToggle, 24, 0)
  pane.frameToggle = UI.Toggle(body, "Name on unit frames", nil,
    function() return S().rpUnitNames ~= false end,
    function(v) S().rpUnitNames = v; if K.UnitNames then K.UnitNames:Refresh() end end, 200, false)
  UI.Tooltip(pane.frameToggle, "Roleplay names on unit frames",
    "Show your roleplay name on your player frame, and others' on your target and focus frames. More options in Settings > Unit frames.")
  Add(pane.frameToggle, 24, 4)

  -- Right now
  if not alongside then
    Section("Right now", 10)
    local cl = CreateFrame("Frame", nil, body)
    cl.t = UI.Text(cl, "Currently", "Label", "deskSubtle"); cl.t:SetPoint("LEFT", 1, 0)
    Add(cl, 14, 6)
    pane.currently = UI.Edit(body, 100, 24, "desk", 255)
    Add(pane.currently, 24, 2)
    local ol = CreateFrame("Frame", nil, body)
    ol.t = UI.Text(ol, "Out of character", "Label", "deskSubtle"); ol.t:SetPoint("LEFT", 1, 0)
    Add(ol, 14, 6)
    pane.ooc = UI.Edit(body, 100, 24, "desk", 255)
    Add(pane.ooc, 24, 2)
    for eb, field in pairs({ [pane.currently] = "currently", [pane.ooc] = "ooc" }) do
      eb:SetScript("OnTextChanged", function(self, user) if user then K:SetField(field, self:GetText()) end end)
    end

    -- Glances
    Section("Glances", 12)
    pane.glances = Add(IconRow(body, 5, 26, "None yet. Add them on the Persona page."), nil, 6)
    for _, m in ipairs(pane.glances.icons) do
      m:SetScript("OnEnter", function(self)
        UI.Tween(self, 1, 0.1, function(p) self:Paint(p) end)
        if K.Persona and self.glance then K.Persona.GlanceTooltip(self, self.glance, false, "ANCHOR_RIGHT") end
      end)
      m:SetScript("OnLeave", function(self)
        UI.Tween(self, 0, 0.12, function(p) self:Paint(p) end)
        if K.Persona then K.Persona.HideTooltip() else GameTooltip:Hide() end
      end)
      m:SetScript("OnClick", function() K.Journal:Open("persona") end)
    end
  end   -- Right now and Glances: Total RP 3's alongside it

  -- Effects
  pane.effectsTitle = Section("Effects", 12)
  pane.effects = Add(IconRow(body, 6, 26, "Nothing on you right now."), nil, 6)
  for _, m in ipairs(pane.effects.icons) do
    m:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    m:SetScript("OnEnter", function(self)
      UI.Tween(self, 1, 0.1, function(p) self:Paint(p) end)
      if K.Auras and self.entry then
        K.Auras:ShowTooltip(self, self.entry, false, "ANCHOR_RIGHT")
        GameTooltip:AddLine("Right-click to end it.", 0.55, 0.80, 1)
        GameTooltip:Show()
      end
    end)
    m:SetScript("OnLeave", function(self) UI.Tween(self, 0, 0.12, function(p) self:Paint(p) end); GameTooltip:Hide() end)
    m:SetScript("OnClick", function(self, button)
      if button == "RightButton" and self.entry and K.Auras then K.Auras:Remove(self.entry.key); GameTooltip:Hide()
      elseif K.Auras then K.Auras:OpenJournal() end
    end)
  end
  pane.effects.empty:SetPoint("RIGHT", -30, 0)
  pane.addEffect = UI.Button(pane.effects, "+", 24, 24)
  pane.addEffect:SetScript("OnClick", function() if K.Auras then K.Auras:OpenJournal() end end)
  UI.Tooltip(pane.addEffect, "Take on an effect", "A wound, a blessing, a bottle too many.")

  -- Warfront
  Section("Warfront", 12)
  pane.stance = Add(Line(body, "Stance", function() K:SetStance(Next(K.STANCE_ORDER, K:Profile().stance or "duel")) end), 20, 4)
  pane.stance:HookScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:SetText("War stance", 1, 0.82, 0)
    GameTooltip:AddLine("Click to change: Open war, Honour first, Non-combatant.", 1, 1, 1, true)
    GameTooltip:Show()
  end)
  pane.consent = {}
  for _, f in ipairs(K.CONSENT) do
    if f.key ~= "RR" then
      local row = Add(Line(body, f.label, function()
        if alongside then return end   -- Total RP 3's RP style
        local cur = K:Profile().consent and K:Profile().consent[f.key]
        local nxt
        if cur == nil then nxt = "1" elseif cur == "1" then nxt = "3" elseif cur == "3" then nxt = "2" else nxt = nil end
        K:SetConsent(f.key, nxt)
      end), 20, 0)
      row:HookScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(f.label, 1, 0.82, 0)
        GameTooltip:AddLine(f.desc .. (alongside and ".\nSet in Total RP 3, as your RP style." or ".\nClick to cycle: Yes, Ask first, No, not stated."), 1, 1, 1, true)
        GameTooltip:Show()
      end)
      row.key = f.key
      pane.consent[#pane.consent + 1] = row
    end
  end
  pane.bodyHeight = y + 6

  -- Footer (fixed) ------------------------------------------------------------
  pane.profileBtn = UI.Button(pane, "", 100, 26)
  pane.profileBtn:SetPoint("BOTTOMLEFT", PAD, 42)
  pane.profileBtn:SetPoint("BOTTOMRIGHT", -PAD, 42)
  pane.profileBtn:SetScript("OnClick", function(self)
    UI.Menu(self, function(root)
      root:CreateTitle("Profiles")
      for _, name in ipairs(K:ProfileNames()) do
        root:CreateRadio(name, function() return name == K:MyProfiles().active end, function() K:SwitchProfile(name) end)
      end
    end)
  end)
  pane.journal = UI.Button(pane, "Journal", 100, 26)
  pane.journal:SetPoint("BOTTOMLEFT", PAD, 12)
  pane.journal:SetPoint("RIGHT", pane, "BOTTOM", -3, 0)
  pane.journal:SetScript("OnClick", function() K.Journal:Open(K:Compat() and "persona" or "profile") end)
  pane.preview = UI.Button(pane, "Preview", 100, 26)
  pane.preview:SetPoint("BOTTOMRIGHT", -PAD, 12)
  pane.preview:SetPoint("LEFT", pane, "BOTTOM", 3, 0)
  pane.preview:SetScript("OnClick", function() K:ViewProfile() end)
  UI.Tooltip(pane.preview, "Preview", "See your profile the way other players will.")

  -- Widths follow the pane. The pane is sized by the window before it's ever
  -- shown, so this runs on show as well as on every resize.
  function pane:Layout()
    local w = self:GetWidth()
    if not w or w < 50 then return end
    local inner = math.max(120, w - 2 * PAD)
    if self.status then   -- not alongside Total RP 3, which keeps your status
      local seg = math.floor(inner / #self.status.buttons)
      for i, b in ipairs(self.status.buttons) do
        b:ClearAllPoints()
        b:SetPoint("LEFT", (i - 1) * seg, 0)
        b:SetWidth(seg)
      end
      self.status:SetWidth(seg * #self.status.buttons)
    end
    local bw = math.max(100, inner - 6)
    self.body:SetWidth(bw)
    for _, t in ipairs({ self.titleToggle, self.frameToggle }) do
      t:SetWidth(bw)
      t.label:SetWidth(bw - 48)
    end
  end
  pane:SetScript("OnSizeChanged", function(self) self:Layout() end)

  -- Effect timers count down while the pane is open
  pane.t = 0
  pane:SetScript("OnUpdate", function(self, elapsed)
    self.t = self.t + elapsed
    if self.t < 1 then return end
    self.t = 0
    for _, m in ipairs(self.effects.icons) do
      if m:IsShown() and m.entry then m.time:SetText(m.entry.expires and K.Auras.LeftShort(m.entry.expires) or "") end
    end
  end)

  pane:SetScript("OnShow", function(self)
    self:Layout()
    CP:Refresh()
    if K.Guide then C_Timer.After(0.3, function() if self:IsVisible() then K.Guide:Maybe("charpane", self, self) end end) end
  end)
  for _, e in ipairs({ "PROFILE", "HOUSE", "AURAS", "WORN" }) do
    K:On(e, function() if pane:IsVisible() then CP:Refresh() end end)
  end
end

function CP:Refresh()
  local pane = self.pane
  if not pane then return end
  local p = K:Profile()
  local P = K.Persona

  -- Who you are
  if P and p.icon and P.IconSource(p.icon) then
    P.SetIcon(pane.med.icon, p.icon)
  else
    SetPortraitTexture(pane.med.icon, "player")
    pane.med.icon:SetTexCoord(0, 1, 0, 1)
  end
  pane.name:SetText(K:DisplayName(p))
  pane.name:SetTextColor(NameRGB(p, "player"))
  local sub = strtrim(p.epithet or "")
  if sub == "" and K:HouseName() ~= "" then sub = "of House " .. K:HouseName() end
  pane.epithet:SetText(sub)
  if pane.status then pane.status:Select(p.status) end

  pane.titleToggle:Refresh()
  pane.frameToggle:Refresh()
  if pane.currently then
    for eb, field in pairs({ [pane.currently] = "currently", [pane.ooc] = "ooc" }) do
      if not eb:HasFocus() then eb:SetText(p[field] or ""); eb:SetCursorPosition(0) end
    end
  end

  -- Glances
  if pane.glances then
    local list = P and P.Glances(p) or {}
    for i, m in ipairs(pane.glances.icons) do
      local g = list[i]
      m.glance = g
      if g then P.SetIcon(m.icon, g.icon); m:Show() else m:Hide() end
    end
    pane.glances.empty:SetShown(#list == 0)
  end

  -- Effects (when the module is on)
  local on = K.Auras ~= nil and K:ExtOn("auras")
  pane.effectsTitle:SetShown(on)
  pane.effects:SetShown(on)
  local effects = on and K.Auras:Of(nil, true) or {}
  local shown = 0
  for i, m in ipairs(pane.effects.icons) do
    local e = effects[i]
    m.entry = e
    if e then
      shown = i
      m.icon:SetTexture(e.icon)
      m.color = K.Auras.Color(e.kind)
      m:Paint(UI.Progress(m))
      m.time:SetText(e.expires and K.Auras.LeftShort(e.expires) or "")
      m:Show()
    else
      m:Hide()
    end
  end
  pane.effects.empty:SetShown(on and #effects == 0)
  pane.addEffect:ClearAllPoints()
  if #effects == 0 then pane.addEffect:SetPoint("RIGHT", pane.effects, "RIGHT", 0, 0)
  else pane.addEffect:SetPoint("LEFT", pane.effects.icons[math.max(1, shown)], "RIGHT", 6, 0) end
  pane.addEffect:SetShown(on and #effects < #pane.effects.icons)

  -- Warfront
  local stance = K.STANCES[p.stance or "duel"] or K.STANCES.duel
  pane.stance.value:SetText(stance.label)
  pane.stance.value:SetTextColor(unpack(stance.color))
  for _, row in ipairs(pane.consent) do
    local v = p.consent and p.consent[row.key]
    local label, color = "Not stated", { 0.62, 0.64, 0.62 }
    for _, cv in ipairs(K.CONSENT_VALUES) do
      if cv.key == v then label, color = (cv.key == "3" and "Ask first" or cv.label), cv.color end
    end
    row.value:SetText(label)
    row.value:SetTextColor(unpack(color))
  end

  pane.body:SetHeight(math.max(1, pane.bodyHeight))
  if pane.bar and pane.bar.Update then pane.bar.Update() end
  pane.profileBtn:SetText("Profile: " .. (K:MyProfiles().active or "?"))
end

---------------------------------------------------------------------------
-- Roleplay names in window titles
---------------------------------------------------------------------------
local function TitleOf(frame, global)
  return _G[global] or (frame and frame.TitleContainer and frame.TitleContainer.TitleText) or (frame and frame.TitleText)
end

-- After the game sets a title, put the roleplay name in its place (when the
-- setting is on and there is one). The game's own text is remembered, so
-- switching off puts it straight back.
local function HookTitle(fs, getName)
  if not fs or fs.kinshipTitle then return end
  fs.kinshipTitle = getName
  fs.kinshipOriginal = fs:GetText()
  local function After(self)
    if self.kinshipBusy then return end
    self.kinshipOriginal = self:GetText()
    local want = S().rpTitles and self.kinshipTitle()
    if want then
      self.kinshipBusy = true
      self:SetText(want)
      self.kinshipBusy = false
    end
  end
  hooksecurefunc(fs, "SetText", After)
  if fs.SetFormattedText then hooksecurefunc(fs, "SetFormattedText", After) end
end

local function Apply(fs)
  if not fs or not fs.kinshipTitle then return end
  local want = S().rpTitles and fs.kinshipTitle()
  fs.kinshipBusy = true
  fs:SetText(want or fs.kinshipOriginal or fs:GetText())
  fs.kinshipBusy = false
end

local function Coloured(text, r, g, b)
  return ("|cff%02x%02x%02x%s|r"):format(math.floor(r * 255), math.floor(g * 255), math.floor(b * 255), text)
end

local function MyTitle()
  local p = K:Profile()
  if strtrim(p.rpName or "") == "" then return nil end
  local P = K.Persona
  local r, g, b
  if P then r, g, b = P.NameColor(p) end
  local name = UI.Escape(K:DisplayName(p))
  local char = K:CharacterName()
  local tail = char:lower() ~= name:lower() and (" |cff" .. K.CHAR_NAME_HEX .. "(" .. char .. ")|r") or ""
  return (r and Coloured(name, r, g, b) or name) .. tail
end

local function TheirTitle()
  local unit = _G.InspectFrame and _G.InspectFrame.unit
  if not unit or not UnitExists(unit) then return nil end
  local name = GetUnitName(unit, true)
  if not Safe(name) or not name or K:IsIgnored(name) then return nil end
  local reg = K:ProfileOf(name)
  local p = reg and reg.profile
  local rp = p and strtrim(UI.Clean(p.rpName or "")) or ""
  if rp == "" then return nil end
  local prefix = strtrim(UI.Clean(p.prefix or ""))
  local text = prefix ~= "" and (prefix .. " " .. rp) or rp
  local P = K.Persona
  local r, g, b
  if P then r, g, b = P.NameColor(p) end
  local char = K:CharacterName(name)
  local tail = char:lower() ~= text:lower() and (" |cff" .. K.CHAR_NAME_HEX .. "(" .. char .. ")|r") or ""
  return (r and Coloured(text, r, g, b) or text) .. tail
end

function CP:ApplyTitles()
  Apply(TitleOf(_G.CharacterFrame, "CharacterFrameTitleText"))
  Apply(TitleOf(_G.InspectFrame, "InspectFrameTitleText"))
end

---------------------------------------------------------------------------
-- The side tab
---------------------------------------------------------------------------
local tab, active, expandedByUs

-- The lowest tab in the column that isn't ours: the window's own, or another
-- addon's tab that joined the column before us.
local function PlaceTab()
  local cf = _G.CharacterFrame
  if not tab or not cf or not cf.ModeTabs then return end
  local lowest, lowestY
  for _, child in ipairs({ cf.ModeTabs:GetChildren() }) do
    if child ~= tab and child:IsShown() and child.Icon then
      local b = child:GetBottom()
      if b and (not lowestY or b < lowestY) then lowest, lowestY = child, b end
    end
  end
  for _, other in ipairs(cf.ModeTabs.Tabs or {}) do
    if other ~= tab and other:IsShown() then
      local b = other:GetBottom()
      if b and (not lowestY or b < lowestY) then lowest, lowestY = other, b end
    end
  end
  tab:ClearAllPoints()
  if lowest then
    tab:SetPoint("TOPLEFT", lowest, "BOTTOMLEFT", 0, -2)
  else
    tab:SetPoint("TOPLEFT", cf.ModeTabs, "TOPLEFT")
  end
end

---------------------------------------------------------------------------
-- On the Roleplay tab, the character screen's own gear slots show what your
-- character wears in roleplay: Kinship's slots laid over the matching ones
-- (head over head, off hand over off hand...), and the gear slots with no
-- roleplay match dimmed. Nothing of the game's is changed: they're frames of
-- Kinship's sitting on top, gone again as soon as you leave the tab.
---------------------------------------------------------------------------
local DOLL = {
  head = "CharacterHeadSlot", neck = "CharacterNeckSlot", shoulder = "CharacterShoulderSlot", back = "CharacterBackSlot",
  chest = "CharacterChestSlot", shirt = "CharacterShirtSlot", tabard = "CharacterTabardSlot", wrist = "CharacterWristSlot",
  hands = "CharacterHandsSlot", waist = "CharacterWaistSlot", legs = "CharacterLegsSlot", feet = "CharacterFeetSlot",
  finger = "CharacterFinger0Slot", finger2 = "CharacterFinger1Slot", keepsake = "CharacterTrinket0Slot",
  charm = "CharacterTrinket1Slot", main = "CharacterMainHandSlot", off = "CharacterSecondaryHandSlot",
  carried = "CharacterRangedSlot",
}
local DIM = { "CharacterAmmoSlot" }
local doll

local function BuildDoll()
  if doll then return doll end
  local host = _G.PaperDollItemsFrame or _G.PaperDollFrame   -- hidden with the character page
  if not (K.Worn and host) then return nil end
  doll = CreateFrame("Frame", nil, host)
  doll:SetAllPoints()
  doll:Hide()
  doll.slots = {}
  for _, w in ipairs(K.Items.WEAR) do
    local g = _G[DOLL[w.key]]
    if g then
      local cover = CreateFrame("Frame", nil, doll)
      cover:SetPoint("TOPLEFT", g, "TOPLEFT", -3, 3)
      cover:SetPoint("BOTTOMRIGHT", g, "BOTTOMRIGHT", 3, -3)
      cover:SetFrameLevel(g:GetFrameLevel() + 5)
      cover:EnableMouse(false)
      cover.t = cover:CreateTexture(nil, "BACKGROUND")
      cover.t:SetAllPoints()
      cover.t:SetColorTexture(0.04, 0.04, 0.04, 1)
      local b = K.Worn.SlotButton(doll, math.max(24, math.floor((g:GetWidth() or 37) + 0.5)), w.key, true)
      b:ClearAllPoints()
      b:SetAllPoints(g)
      b:SetFrameLevel(g:GetFrameLevel() + 6)
      doll.slots[#doll.slots + 1] = b
    end
  end
  for _, name in ipairs(DIM) do
    local g = _G[name]
    if g then
      local d = CreateFrame("Frame", nil, doll)
      d:SetPoint("TOPLEFT", g, "TOPLEFT", -3, 3)
      d:SetPoint("BOTTOMRIGHT", g, "BOTTOMRIGHT", 3, -3)
      d:SetFrameLevel(g:GetFrameLevel() + 6)
      d:EnableMouse(true)   -- and the gear underneath can't be picked up from here
      d.shade = d:CreateTexture(nil, "BACKGROUND")
      d.shade:SetAllPoints()
      d.shade:SetColorTexture(0.04, 0.04, 0.04, 1)
      d.edge = UI.Border(d)
      d.edge:SetColor(1, 1, 1, 0.06)
    end
  end
  return doll
end

local faded = {}
local function FadeGearText(on)
  local slot = _G.CharacterHeadSlot
  local host = slot and slot:GetParent()
  if on then
    if not host then return end
    for _, child in ipairs({ host:GetChildren() }) do
      if child ~= doll and not child:IsObjectType("Button") and not (child.IsForbidden and child:IsForbidden()) then
        local text = false
        for _, r in ipairs({ child:GetRegions() }) do
          if r:IsObjectType("FontString") then text = true break end
        end
        if text and faded[child] == nil then
          faded[child] = child:GetAlpha()
          child:SetAlpha(0)
        end
      end
    end
  else
    for f, a in pairs(faded) do f:SetAlpha(a) end
    wipe(faded)
  end
end

function CP:RefreshDoll()
  if not (doll and doll:IsShown() and K.Worn) then return end
  for _, b in ipairs(doll.slots) do b:SetItem((K.Worn:In(b.slot)), nil) end
end

local function ShowDoll(on)
  local want = on and K.Worn ~= nil and K:ExtOn("inventory") and S().rpDoll ~= false
  if want then BuildDoll() end
  if doll then
    doll:SetShown(want and true or false)
    CP:RefreshDoll()
  end
  K.Try("character pane", FadeGearText, want and true or false)
end
CP.ShowDoll = ShowDoll

local function SetActive(on)
  if on == active then return end
  active = on
  local cf = _G.CharacterFrame
  if on then
    if not CP.pane then BuildPane() end
    if not CP.pane then active = false return end
    if cf.IsRightPaneCollapsed and cf:IsRightPaneCollapsed() and cf.SetRightPaneCollapsed then
      expandedByUs = true
      cf:SetRightPaneCollapsed(false)
    end
    CP.pane:Show()
    ShowDoll(true)
    if SOUNDKIT then PlaySound(SOUNDKIT.IG_CHARACTER_INFO_TAB) end
  else
    if CP.pane then CP.pane:Hide() end
    ShowDoll(false)
    -- Put the pane back the way you had it, even if the window is closing.
    if expandedByUs and cf.SetRightPaneCollapsed and not InCombatLockdown() then cf:SetRightPaneCollapsed(true) end
    expandedByUs = false
    if cf.UpdatePortrait then pcall(cf.UpdatePortrait, cf) end
  end
  if tab and tab.SetChecked then tab:SetChecked(on) end
end
CP.SetActive = SetActive


local function BuildTab()
  local cf = _G.CharacterFrame
  if tab or not cf or not cf.ModeTabs then return end
  local ok, t = pcall(CreateFrame, "Frame", "KinshipRPCharacterTab", cf.ModeTabs, "LargeSideTabButtonTemplate")
  if not ok or not t then return end
  tab = t
  tab.tooltipText = "Roleplay"
  if tab.Icon then tab.Icon:SetTexture(TAB_ICON) end
  if tab.SetFillToInterior then tab:SetFillToInterior(true) end
  if tab.SetChecked then tab:SetChecked(false) end
  local function OnUp(_, button, upInside)
    if button ~= "LeftButton" or upInside == false then return end
    if active then SetActive(false) return end
    -- The pane belongs to the character page; from another page, go there first.
    if _G.PaperDollFrame and not _G.PaperDollFrame:IsShown() and ToggleCharacter then
      ToggleCharacter("PaperDollFrame", true)
    end
    SetActive(true)
  end
  if tab.SetCustomOnMouseUpHandler then tab:SetCustomOnMouseUpHandler(OnUp)
  else tab:SetScript("OnMouseUp", function(self, button) OnUp(self, button, self:IsMouseOver()) end) end
  PlaceTab()
end

-- Any other tab in the column (the window's or another addon's) gives the pane back.
local hookedTabs = setmetatable({}, { __mode = "k" })
local function WatchSiblings()
  local cf = _G.CharacterFrame
  if not cf or not cf.ModeTabs then return end
  for _, child in ipairs({ cf.ModeTabs:GetChildren() }) do
    if child ~= tab and not hookedTabs[child] and child.HookScript then
      hookedTabs[child] = true
      child:HookScript("OnMouseUp", function() if active then SetActive(false) end end)
    end
  end
end

local function ApplySetting()
  if not tab then return end
  local wanted = S().charPanel ~= false
  if not wanted then SetActive(false) end
  tab:SetShown(wanted)
  if wanted then C_Timer.After(0, PlaceTab) end
end

local function HookCharacter()
  local cf = _G.CharacterFrame
  if CP.hooked or not cf or not cf.ModeTabs then return end
  CP.hooked = true
  BuildTab()
  ApplySetting()
  HookTitle(TitleOf(cf, "CharacterFrameTitleText"), MyTitle)
  cf:HookScript("OnShow", function()
    ApplySetting()
    Apply(TitleOf(cf, "CharacterFrameTitleText"))
    -- After every other tab has had its say about where it sits
    C_Timer.After(0, function() PlaceTab(); WatchSiblings() end)
  end)
  if cf.UpdateTabLayout then hooksecurefunc(cf, "UpdateTabLayout", function() C_Timer.After(0, PlaceTab) end) end
  if cf.OnModeTabClicked then hooksecurefunc(cf, "OnModeTabClicked", function() SetActive(false) end) end
  -- The window keeps its own portrait (your character) on the Roleplay tab too.
  cf:HookScript("OnHide", function() SetActive(false) end)
  if _G.PaperDollFrame then _G.PaperDollFrame:HookScript("OnHide", function() SetActive(false) end) end
end

---------------------------------------------------------------------------
-- Their panel beside the inspect window
---------------------------------------------------------------------------
function CP:BuildTheirs()
  local host = _G.InspectFrame
  if self.theirs or not host then return end
  local f = CreateFrame("Frame", "KinshipRPInspectPanel", host)
  f:SetWidth(270)
  f:SetPoint("TOPLEFT", host, "TOPRIGHT", 2, 0)
  f:SetPoint("BOTTOMLEFT", host, "BOTTOMRIGHT", 2, 0)
  f:SetFrameLevel(host:GetFrameLevel() + 5)
  f:EnableMouse(true)
  self.theirs = f
  f.bg = f:CreateTexture(nil, "BACKGROUND")
  f.bg:SetAllPoints()
  f.bg:SetTexture(WHITE)
  f.edge = UI.Border(f)
  UI:OnTheme(function(t)
    f.bg:SetVertexColor(unpack(t.chrome))
    f.edge:SetColor(unpack(t.chromeEdge))
  end)
  f.close = UI.CloseButton(f, false, 20)
  f.close:SetPoint("TOPRIGHT", -6, -6)
  f.close:SetScript("OnClick", function() f:Hide(); f.dismissed = true end)

  f.med = Medallion(f, 40)
  f.med:SetPoint("TOPLEFT", PAD, -PAD - 2)
  f.med:SetScript("OnClick", function() if f.who then K:ViewProfile(f.who, f.unit) end end)
  UI.Tooltip(f.med, "Full profile")
  f.name = UI.Text(f, "", "Header", "plain", 270 - 2 * PAD - 52 - 20)
  f.name:SetPoint("TOPLEFT", f.med, "TOPRIGHT", 8, -5)
  f.name:SetWordWrap(false)
  f.epithet = UI.Text(f, "", "Small", "deskSubtle", 270 - 2 * PAD - 52)
  f.epithet:SetPoint("TOPLEFT", f.name, "BOTTOMLEFT", 0, -4)
  f.epithet:SetWordWrap(false)

  f.rows = {}
  local y = -66
  for _, label in ipairs({ "Status", "Stance", "House", "Pronouns" }) do
    local r = Line(f, label)
    r:SetPoint("TOPLEFT", PAD, y)
    r:SetPoint("RIGHT", -PAD, 0)
    f.rows[label] = r
    y = y - 20
  end
  f.glances = IconRow(f, 5, 24, "")
  f.glances:SetPoint("TOPLEFT", PAD, y - 6)
  f.glances:SetPoint("RIGHT", -PAD, 0)
  for _, m in ipairs(f.glances.icons) do
    m:SetScript("OnEnter", function(self)
      UI.Tween(self, 1, 0.1, function(p) self:Paint(p) end)
      if K.Persona and self.glance then K.Persona.GlanceTooltip(self, self.glance, true, "ANCHOR_RIGHT") end
    end)
    m:SetScript("OnLeave", function(self)
      UI.Tween(self, 0, 0.12, function(p) self:Paint(p) end)
      if K.Persona then K.Persona.HideTooltip() else GameTooltip:Hide() end
    end)
  end
  f.effects = IconRow(f, 6, 24, "")
  f.effects:SetPoint("TOPLEFT", f.glances, "BOTTOMLEFT", 0, -2)
  f.effects:SetPoint("RIGHT", -PAD, 0)
  for _, m in ipairs(f.effects.icons) do
    m:SetScript("OnEnter", function(self)
      UI.Tween(self, 1, 0.1, function(p) self:Paint(p) end)
      if K.Auras and self.entry then K.Auras:ShowTooltip(self, self.entry, true, "ANCHOR_RIGHT") end
    end)
    m:SetScript("OnLeave", function(self) UI.Tween(self, 0, 0.12, function(p) self:Paint(p) end); GameTooltip:Hide() end)
  end
  f.body = UI.ReadArea(f, 270 - 2 * PAD, 1, "Read", "deskText")
  f.body:SetPoint("TOPLEFT", f.effects, "BOTTOMLEFT", 2, -8)
  f.body:SetPoint("BOTTOMRIGHT", -PAD, 46)
  f.view = UI.Button(f, "Full profile", 100, 26)
  f.view:SetPoint("BOTTOMLEFT", PAD, 12)
  f.view:SetPoint("RIGHT", f, "BOTTOM", -3, 0)
  f.view:SetScript("OnClick", function() if f.who then K:ViewProfile(f.who, f.unit) end end)
  f.letter = UI.Button(f, "Write a letter", 100, 26)
  f.letter:SetPoint("BOTTOMRIGHT", -PAD, 12)
  f.letter:SetPoint("LEFT", f, "BOTTOM", 3, 0)
  f.letter:SetScript("OnClick", function() if f.who then K.Letters:Compose(f.who) end end)

  K:On("REGISTRY", function(key)
    if f:IsVisible() and f.who and K.NameKey(f.who) == key then CP:RefreshTheirs() end
  end)
end

function CP:RefreshTheirs()
  local f = self.theirs
  if not f then return end
  local unit = _G.InspectFrame and _G.InspectFrame.unit or "target"
  local name = UnitExists(unit) and GetUnitName(unit, true)
  local isPlayer = UnitIsPlayer(unit)
  if not Safe(name) or not name or not Safe(isPlayer) or not isPlayer or K:IsIgnored(name) or S().inspectPanel == false then
    f:Hide()
    return
  end
  if f.who ~= name then f.dismissed = false; K.Comm:Request(name, true) end
  if f.dismissed then f:Hide() return end
  f.who, f.unit = name, unit
  f:Show()
  Apply(TitleOf(_G.InspectFrame, "InspectFrameTitleText"))

  local reg = K:ProfileOf(name)
  local p = reg and reg.profile
  local C = UI.Clean
  local P = K.Persona
  if P and p and p.icon and P.IconSource(p.icon) then
    P.SetIcon(f.med.icon, p.icon)
  else
    SetPortraitTexture(f.med.icon, unit)
    f.med.icon:SetTexCoord(0, 1, 0, 1)
  end
  local rp = p and strtrim(C(p.rpName)) or ""
  f.name:SetText(rp ~= "" and ((C(p.prefix) ~= "" and (C(p.prefix) .. " ") or "") .. rp) or Short(name))
  f.name:SetTextColor(NameRGB(p, unit))
  f.epithet:SetText(p and C(p.epithet) or "")
  local st = p and K.STATUS[p.status]
  f.rows.Status.value:SetText(st and st.label or "|cff808080Unknown|r")
  if st then f.rows.Status.value:SetTextColor(unpack(st.color)) end
  local stance = p and p.stance and K.STANCES[p.stance]
  f.rows.Stance.value:SetText(stance and stance.label or "|cff808080Not stated|r")
  if stance then f.rows.Stance.value:SetTextColor(unpack(stance.color)) end
  local house = p and strtrim(C(p.house)) or ""
  f.rows.House.value:SetText(house ~= "" and house or "|cff808080-|r")
  f.rows.House.value:SetTextColor(1, 1, 1)
  f.rows.Pronouns.value:SetText(p and C(p.pronouns) ~= "" and C(p.pronouns) or "|cff808080-|r")
  f.rows.Pronouns.value:SetTextColor(1, 1, 1)

  local list = (P and p) and P.Glances(p) or {}
  for i, m in ipairs(f.glances.icons) do
    m.glance = list[i]
    if list[i] then P.SetIcon(m.icon, list[i].icon); m:Show() else m:Hide() end
  end
  local effects = K.Auras and K.Auras:Of(name) or {}
  for i, m in ipairs(f.effects.icons) do
    local e = effects[i]
    m.entry = e
    if e then
      m.icon:SetTexture(e.icon)
      m.color = K.Auras.Color(e.kind)
      m:Paint(UI.Progress(m))
      m.time:SetText(e.expires and K.Auras.LeftShort(e.expires) or "")
      m:Show()
    else
      m:Hide()
    end
  end

  if not p then
    f.body:SetText("|cff9a9a9aNo roleplay profile has reached you from this player yet.|r")
    return
  end
  local parts = {}
  local head = UI.Hex(K:Theme().deskHeading)
  local function add(label, text)
    text = text and strtrim(C(text)) or ""
    if text ~= "" then parts[#parts + 1] = "|cff" .. head .. label .. "|r\n" .. text end
  end
  add("Currently", p.currently)
  add("At a glance", p.glance)
  add("Out of character", p.ooc)
  add("Appearance", p.appearance)
  f.body:SetText(table.concat(parts, "\n\n"))
end

local function HookInspect()
  if CP.inspectHooked or not _G.InspectFrame then return end
  CP.inspectHooked = true
  CP:BuildTheirs()
  HookTitle(TitleOf(_G.InspectFrame, "InspectFrameTitleText"), TheirTitle)
  _G.InspectFrame:HookScript("OnShow", function() C_Timer.After(0, function() CP:RefreshTheirs() end) end)
  if _G.InspectFrame_UpdateTabs then hooksecurefunc("InspectFrame_UpdateTabs", function() CP:RefreshTheirs() end) end
end

---------------------------------------------------------------------------
-- Start-up
---------------------------------------------------------------------------
K:On("LOGIN", function()
  local s = S()
  if s.charPanel == nil then s.charPanel = true end
  if s.inspectPanel == nil then s.inspectPanel = true end
  if s.rpTitles == nil then s.rpTitles = false end
  HookCharacter()
  HookInspect()
  local ev = CreateFrame("Frame")
  ev:RegisterEvent("ADDON_LOADED")
  ev:SetScript("OnEvent", function(_, _, name) if name == "Blizzard_InspectUI" then HookInspect() end end)
end)

-- Your roleplay name changed: re-title an open character window.
K:On("PROFILE", function() if S().rpTitles then CP:ApplyTitles() end end)

K:RegisterSettings({ id = "characterPanel", title = "Character sheet", order = 40, build = function(card)
  card:Toggle("Roleplay tab on the character sheet", "A Kinship tab in the sheet's own column: your roleplay details in the right pane.", {
    get = function() return S().charPanel ~= false end,
    set = function(v) S().charPanel = v; ApplySetting() end,
  })
  card:Toggle("Roleplay when inspecting", "Their profile beside the inspect window.", {
    get = function() return S().inspectPanel ~= false end,
    set = function(v) S().inspectPanel = v; CP:RefreshTheirs() end,
  })
  card:Toggle("Roleplay items on the gear slots", "On the Roleplay tab, the character screen's gear slots show what your "
    .. "character wears in roleplay instead. Click one to put something on or take it off.", {
    get = function() return S().rpDoll ~= false end,
    set = function(v) S().rpDoll = v; ShowDoll(active) end,
  })
  card:Toggle("Roleplay name in window titles", "The character window shows your roleplay name, with your character's name "
    .. "beside it; the inspect window does the same for anyone whose profile has arrived.", {
    get = function() return S().rpTitles == true end,
    set = function(v) S().rpTitles = v; CP:ApplyTitles() end,
  })
end })

-- The gear-slot overlay follows what you wear.
K:On("WORN", function() CP:RefreshDoll() end)
