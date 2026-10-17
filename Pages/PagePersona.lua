-- Kinship RP: Persona page. Four tabs:
--   Glances - five "at first glance" details, with a live preview of the
--             target bar and the hover tooltip, and saved presets
--   Traits  - personality sliders (Total RP 3's pairs or your own)
--   Look    - profile icon, name colour and theme music
--   Effects - timed wounds, boons and states (AurasTab.lua)

local ADDON, ns = ...
local K = ns.K
local UI = K.UI
local P   -- K.Persona, picked up when the page is built

local WHITE = "Interface\\Buttons\\WHITE8X8"
local CW, CH, TOP = 696, 466, 40
local BODY_H = CH - TOP
-- Fixed tooltip look for the "as others see it" previews.
local TIP_BG, TIP_EDGE = { 0.035, 0.035, 0.05, 0.95 }, { 0.55, 0.55, 0.60, 0.75 }
local TIP_TITLE, TIP_TEXT = { 1, 0.82, 0 }, { 0.95, 0.93, 0.88 }

local function Refresh() K.Journal:RefreshCurrent() end

---------------------------------------------------------------------------
-- Shared pieces
---------------------------------------------------------------------------
-- A round icon inside a coloured ring.
local function Medallion(parent, size, ring)
  local m = CreateFrame("Frame", nil, parent)
  m:SetSize(size + 2 * ring, size + 2 * ring)
  m.ring = UI.Circle(m, size + 2 * ring, "ARTWORK", 0)
  m.ring:SetPoint("CENTER")
  m.icon = m:CreateTexture(nil, "ARTWORK", nil, 1)
  m.icon:SetSize(size, size)
  m.icon:SetPoint("CENTER")
  UI.Round(m.icon)
  return m
end

-- A dark box drawn like the game's tooltip.
local function TooltipBox(parent, w)
  local f = CreateFrame("Frame", nil, parent)
  f:SetSize(w, 60)
  f.bg = f:CreateTexture(nil, "BACKGROUND")
  f.bg:SetAllPoints()
  f.bg:SetColorTexture(unpack(TIP_BG))
  f.edge = UI.Border(f, TIP_EDGE)
  return f
end

-- Small chevron button (up / down), drawn with two strokes.
local function Chevron(parent, up)
  local b = CreateFrame("Button", nil, parent)
  b:SetSize(20, 20)
  b.bg = b:CreateTexture(nil, "BACKGROUND")
  b.bg:SetAllPoints()
  b.bg:SetTexture(WHITE)
  b.strokes = {}
  for i, side in ipairs({ -1, 1 }) do
    local l = b:CreateTexture(nil, "ARTWORK")
    l:SetTexture(WHITE)
    l:SetSize(7, 1.6)
    l:SetPoint("CENTER", side * 2.4, 0)
    l:SetRotation(math.rad((up and -45 or 45) * side))
    b.strokes[i] = l
  end
  local function paint(p)
    local c = K:Theme().text
    local on = b:IsEnabled()
    b.bg:SetVertexColor(c[1], c[2], c[3], on and 0.10 * p or 0)
    for _, l in ipairs(b.strokes) do l:SetVertexColor(c[1], c[2], c[3], on and (0.55 + 0.45 * p) or 0.18) end
  end
  b:SetScript("OnEnter", function(self) UI.Tween(self, 1, 0.1, paint) end)
  b:SetScript("OnLeave", function(self) UI.Tween(self, 0, 0.1, paint) end)
  b:SetScript("OnEnable", function() paint(UI.Progress(b)) end)
  b:SetScript("OnDisable", function() UI.SetProgress(b, 0); paint(0) end)
  UI:OnTheme(function() paint(UI.Progress(b)) end)
  return b
end

-- Faint medallion and a friendly sentence, for empty states.
local function EmptyState(parent, icon, text, w, dy)
  local f = CreateFrame("Frame", nil, parent)
  f:SetAllPoints()
  f.art = f:CreateTexture(nil, "ARTWORK")
  f.art:SetTexture(K.Art(icon))
  f.art:SetSize(60, 60)
  f.art:SetPoint("CENTER", 0, dy or 30)
  f.art:SetAlpha(0.75)
  f.text = UI.Text(f, text, "Read", "subtle", w or 280)
  f.text:SetPoint("TOP", f.art, "BOTTOM", 0, -12)
  f.text:SetJustifyH("CENTER")
  f.text:SetSpacing(3)
  return f
end

-- Open the game's colour picker. onChange(r, g, b) while choosing; onCancel() restores.
local function PickColor(r, g, b, onChange, onCancel)
  local cpf = ColorPickerFrame
  if not cpf then return end
  local function current() return cpf:GetColorRGB() end
  if cpf.SetupColorPickerAndShow then
    cpf:SetupColorPickerAndShow({
      r = r, g = g, b = b, hasOpacity = false,
      swatchFunc = function() onChange(current()) end,
      cancelFunc = function() onCancel() end,
    })
  else
    cpf.hasOpacity, cpf.opacityFunc = false, nil
    cpf.previousValues = { r, g, b }
    cpf.func = function() onChange(current()) end
    cpf.cancelFunc = function() onCancel() end
    cpf:SetColorRGB(r, g, b)
    cpf:Hide()
    cpf:Show()
  end
end

---------------------------------------------------------------------------
-- Glance presets: saving asks for a name
---------------------------------------------------------------------------
local function SavePreset(name)
  name = strtrim(name or "")
  if name == "" then return end
  local existed = K.db.glancePresets[name] ~= nil
  if K.Persona:SavePreset(name) then
    UI.Toast({ icon = K.Art("IconNote"), title = existed and "Preset updated" or "Preset saved",
      text = ("\"%s\" keeps these glances for any of your characters."):format(name), duration = 4 })
  end
end

StaticPopupDialogs["KINSHIPRP_GLANCE_PRESET"] = {
  text = "Name this set of glances:",
  button1 = SAVE or "Save", button2 = CANCEL or "Cancel",
  hasEditBox = true, maxLetters = 32,
  OnAccept = function(self)
    local eb = self.editBox or self.EditBox or (self.GetEditBox and self:GetEditBox())
    if eb then SavePreset(eb:GetText()) end
  end,
  EditBoxOnEnterPressed = function(self) SavePreset(self:GetText()); self:GetParent():Hide() end,
  EditBoxOnEscapePressed = function(self) self:GetParent():Hide() end,
  timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
}

local function PresetMenu(owner, c)
  UI.Menu(owner, function(root)
    root:CreateTitle("Glance presets")
    root:CreateButton("Save these glances as...", function() StaticPopup_Show("KINSHIPRP_GLANCE_PRESET") end)
    local names = P:PresetNames()
    root:CreateDivider()
    if #names == 0 then
      root:CreateTitle("No presets saved yet")
      return
    end
    root:CreateTitle("Load (replaces your glances)")
    for _, name in ipairs(names) do
      root:CreateButton(name, function()
        if P:LoadPreset(name) then
          c.gsel = 1
          UI.Toast({ icon = K.Art("IconNote"), title = "Glances loaded", text = ("From \"%s\"."):format(name), duration = 3 })
          Refresh()
        end
      end)
    end
    root:CreateDivider()
    local del = root:CreateButton("Delete a preset")
    for _, name in ipairs(names) do del:CreateButton(name, function() P:DeletePreset(name) end) end
  end)
end

---------------------------------------------------------------------------
-- Glances
---------------------------------------------------------------------------
local SLOT_W, SLOT_H, SLOT_GAP = 132, 84, 9
local EDIT_W, EDIT_H = 430, BODY_H - SLOT_H - 10   -- 430 x 332
local PREV_W = CW - EDIT_W - 10                    -- 256

local function BuildSlot(tab, c, i)
  local s = CreateFrame("Button", nil, tab)
  s:SetSize(SLOT_W, SLOT_H)
  s:SetPoint("TOPLEFT", (i - 1) * (SLOT_W + SLOT_GAP), 0)
  s.bg = s:CreateTexture(nil, "BACKGROUND")
  s.bg:SetAllPoints()
  s.tint = s:CreateTexture(nil, "BACKGROUND", nil, 1)
  s.tint:SetAllPoints()
  s.edge = UI.Border(s)
  s.bar = s:CreateTexture(nil, "ARTWORK", nil, 2)
  s.bar:SetTexture(WHITE)
  s.bar:SetHeight(2)
  s.bar:SetPoint("TOPLEFT"); s.bar:SetPoint("TOPRIGHT")
  s.num = UI.Text(s, tostring(i), "Label", "subtle")
  s.num:SetPoint("TOPLEFT", 8, -7)
  s.chip = UI.Chip(s)
  s.chip:SetPoint("TOPRIGHT", -6, -6)
  s.chip:SetHeight(16)
  s.med = Medallion(s, 38, 2)
  s.med:SetPoint("TOP", 0, -10)
  s.plus = {}
  for k, size in ipairs({ { 14, 2 }, { 2, 14 } }) do
    local l = s:CreateTexture(nil, "OVERLAY")
    l:SetTexture(WHITE)
    l:SetSize(size[1], size[2])
    l:SetPoint("CENTER", s.med)
    s.plus[k] = l
  end
  s.title = UI.Text(s, "", "Small", "heading", SLOT_W - 14)
  s.title:SetPoint("TOP", 0, -59)
  s.title:SetJustifyH("CENTER")
  s.title:SetWordWrap(false)

  function s:Paint(p)
    p = p or UI.Progress(self)
    local t = K:Theme()
    local a = t.accent
    local sel = self.glance ~= nil and c.gsel == i
    self.bg:SetColorTexture(unpack(t.panel))
    self.tint:SetColorTexture(a[1], a[2], a[3], (sel and 0.10 or 0) + 0.07 * p)
    if sel then self.edge:SetColor(a[1], a[2], a[3], 0.9)
    else self.edge:SetColor(UI.Mix(t.panelEdge, { a[1], a[2], a[3], 0.6 }, p)) end
    self.bar:SetVertexColor(a[1], a[2], a[3], sel and 1 or 0)
    local g = self.glance
    if g then
      local on = g.active ~= false
      self.med:Show()
      self.med.ring:SetVertexColor(a[1], a[2], a[3], on and (0.75 + 0.25 * p) or 0.3)
      P.SetIcon(self.med.icon, g.icon)
      self.med.icon:SetDesaturated(not on)
      self.med:SetAlpha(on and 1 or 0.55)
      for _, l in ipairs(self.plus) do l:Hide() end
      local title = strtrim(g.title or "")
      self.title:SetText(title ~= "" and title or "Untitled")
      self.title:SetTextColor(unpack(title ~= "" and t.heading or t.subtle))
      self.chip:Set(not on and "Hidden" or nil, t.subtle)
    else
      local first = i == #P:MyGlances() + 1
      self.med:Show()
      self.med.ring:SetVertexColor(a[1], a[2], a[3], (first and 0.16 or 0.08) + 0.14 * p)
      self.med.icon:SetTexture(nil)
      self.med:SetAlpha(1)
      for _, l in ipairs(self.plus) do l:Show(); l:SetVertexColor(a[1], a[2], a[3], (first and 0.7 or 0.35) + 0.3 * p) end
      self.title:SetText(first and "Add a glance" or "Empty")
      self.title:SetTextColor(unpack(t.subtle))
      self.chip:Set(nil)
    end
    self.num:SetAlpha((g or i == #P:MyGlances() + 1) and 1 or 0.5)
  end
  s:SetScript("OnEnter", function(self) UI.Tween(self, 1, 0.12, function(p) self:Paint(p) end) end)
  s:SetScript("OnLeave", function(self) UI.Tween(self, 0, 0.15, function(p) self:Paint(p) end) end)
  s:SetScript("OnClick", function(self)
    if SOUNDKIT then PlaySound(SOUNDKIT.IG_CHARACTER_INFO_TAB) end
    if self.glance then
      c.gsel = i
      Refresh()
    else
      c.gsel = #P:MyGlances() + 1
      if not P:AddGlance() then c.gsel = nil end
      Refresh()
      if c.gsel then tab.editor.title.edit:SetFocus() end
    end
  end)
  UI:OnTheme(function() s:Paint() end)
  return s
end

local function BuildGlances(tab, c)
  tab.slots = {}
  for i = 1, 5 do tab.slots[i] = BuildSlot(tab, c, i) end

  -- Editor -------------------------------------------------------------------
  local e = UI.Panel(tab)
  e:SetPoint("TOPLEFT", 0, -(SLOT_H + 10))
  e:SetSize(EDIT_W, EDIT_H)
  tab.editor = e
  local function G() return tab.loaded end

  e.head = UI.Section(e, "Glance")
  e.head:SetPoint("TOPLEFT", 21, -15)
  e.active = UI.Toggle(e, "Show to others", nil,
    function() local g = G(); return g ~= nil and g.active ~= false end,
    function(v) local g = G(); if g then g.active = v; K:Fire("PROFILE") end end, 150, true)
  e.active:SetPoint("TOPRIGHT", -16, -12)

  e.iconBtn = CreateFrame("Button", nil, e)
  e.iconBtn:SetSize(60, 60)
  e.iconBtn:SetPoint("TOPLEFT", 16, -44)
  e.med = Medallion(e.iconBtn, 54, 3)
  e.med:SetPoint("CENTER")
  local function paintIcon(p)
    local a = K:Theme().accent
    e.med.ring:SetVertexColor(a[1], a[2], a[3], 0.55 + 0.45 * p)
    e.med.icon:SetSize(54 + 2 * p, 54 + 2 * p)
  end
  e.iconBtn:SetScript("OnEnter", function(self)
    UI.Tween(self, 1, 0.12, paintIcon)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:SetText("Choose an icon", 1, 0.82, 0)
    GameTooltip:AddLine("It shows on your target bar and in tooltips.", 1, 1, 1, true)
    GameTooltip:Show()
  end)
  e.iconBtn:SetScript("OnLeave", function(self) UI.Tween(self, 0, 0.15, paintIcon); GameTooltip:Hide() end)
  e.iconBtn:SetScript("OnClick", function(self)
    local g = G()
    if not g then return end
    K.IconPicker:Open(self, g.icon, function(icon) g.icon = icon; K:Fire("PROFILE") end)
  end)
  UI:OnTheme(function() paintIcon(UI.Progress(e.iconBtn)) end)

  e.title = UI.Field(e, "Title", EDIT_W - 100, P.MAX_TITLE, function(text)
    local g = G(); if g then g.title = text; K:Fire("PROFILE") end
  end)
  e.title:SetPoint("TOPLEFT", 84, -46)
  e.titleHint = UI.Text(e, "A few words: \"Scarred hands\", \"Smells of pipe smoke\".", "Small", "subtle", EDIT_W - 100)
  e.titleHint:SetPoint("TOPLEFT", 85, -90)
  e.titleHint:SetWordWrap(false)

  local dl = UI.Text(e, "What people notice", "Label", "subtle")
  dl:SetPoint("TOPLEFT", 17, -118)
  e.count = UI.Text(e, "", "Label", "subtle")
  e.count:SetPoint("TOPRIGHT", -17, -118)
  e.text = UI.TextArea(e, EDIT_W - 32, 146, P.MAX_TEXT, function(text)
    local g = G(); if g then g.text = text; K:Fire("PROFILE") end
  end)
  e.text:SetPoint("TOPLEFT", 16, -132)
  e.text.edit:HookScript("OnTextChanged", function(self) e.count:SetText(("%d / %d"):format(self:GetNumLetters(), P.MAX_TEXT)) end)

  e.left = UI.Button(e, "Move left", 92, 24)
  e.left:SetPoint("BOTTOMLEFT", 16, 14)
  e.left:SetScript("OnClick", function() if c.gsel then c.gsel = P:MoveGlance(c.gsel, -1) end end)
  e.right = UI.Button(e, "Move right", 96, 24)
  e.right:SetPoint("LEFT", e.left, "RIGHT", 6, 0)
  e.right:SetScript("OnClick", function() if c.gsel then c.gsel = P:MoveGlance(c.gsel, 1) end end)
  e.remove = UI.Button(e, "Remove", 84, 24)
  e.remove:SetPoint("BOTTOMRIGHT", -16, 14)
  e.remove:SetScript("OnClick", function()
    if not c.gsel then return end
    local i = c.gsel
    c.gsel = math.max(1, i - 1)
    P:RemoveGlance(i)
  end)
  UI.Tooltip(e.remove, "Remove this glance", "The others move along to fill the gap.")

  e.body = { e.head, e.active, e.iconBtn, e.title, e.titleHint, dl, e.count, e.text, e.left, e.right, e.remove }
  e.empty = EmptyState(e, "IconNote",
    "Add your first glance: something people notice the moment they see you. A scar, a scent, a sigil.", 320, 40)
  e.add = UI.Button(e.empty, "Add a glance", 130, 26)
  e.add:SetPoint("TOP", e.empty.text, "BOTTOM", 0, -14)
  e.add:SetScript("OnClick", function()
    c.gsel = #P:MyGlances() + 1
    if not P:AddGlance() then c.gsel = nil end
    Refresh()
    tab.editor.title.edit:SetFocus()
  end)

  -- Preview ------------------------------------------------------------------
  local pv = UI.Panel(tab)
  pv:SetPoint("TOPLEFT", EDIT_W + 10, -(SLOT_H + 10))
  pv:SetSize(PREV_W, EDIT_H)
  tab.preview = pv
  local ph = UI.Section(pv, "On the target bar")
  ph:SetPoint("TOPLEFT", 21, -15)

  local bar = CreateFrame("Frame", nil, pv)
  bar:SetSize(PREV_W - 32, 44)
  bar:SetPoint("TOPLEFT", 16, -40)
  bar.bg = bar:CreateTexture(nil, "BACKGROUND")
  bar.bg:SetAllPoints()
  bar.edge = UI.Border(bar)
  bar.line = bar:CreateTexture(nil, "ARTWORK")
  bar.line:SetTexture(WHITE)
  bar.line:SetHeight(1)
  bar.line:SetPoint("BOTTOMLEFT", 1, 1); bar.line:SetPoint("BOTTOMRIGHT", -1, 1)
  UI:OnTheme(function(t)
    bar.bg:SetColorTexture(unpack(t.chrome))
    bar.edge:SetColor(unpack(t.chromeEdge))
    bar.line:SetVertexColor(t.ui[1], t.ui[2], t.ui[3], 0.45)
  end)
  bar.none = UI.Text(bar, "Nothing showing yet", "Small", "deskSubtle")
  bar.none:SetPoint("CENTER")
  bar.icons = {}
  for i = 1, 5 do
    local b = CreateFrame("Button", nil, bar)
    b:SetSize(32, 32)
    b:SetPoint("LEFT", 8 + (i - 1) * 36, 0)
    b.med = Medallion(b, 28, 2)
    b.med:SetPoint("CENTER")
    local function paint(p)
      local u = K:Theme().ui
      b.med.ring:SetVertexColor(u[1], u[2], u[3], 0.5 + 0.5 * p)
      b.med.icon:SetSize(28 + 2 * p, 28 + 2 * p)
    end
    b:SetScript("OnEnter", function(self) UI.Tween(self, 1, 0.1, paint); P.GlanceTooltip(self, self.glance, false) end)
    b:SetScript("OnLeave", function(self) UI.Tween(self, 0, 0.12, paint); P.HideTooltip() end)
    b:SetScript("OnClick", function(self) if self.index then c.gsel = self.index; Refresh() end end)
    UI:OnTheme(function() paint(UI.Progress(b)) end)
    bar.icons[i] = b
  end
  tab.bar = bar

  local th = UI.Section(pv, "When someone hovers")
  th:SetPoint("TOPLEFT", 21, -102)
  local tip = TooltipBox(pv, PREV_W - 32)
  tip:SetPoint("TOPLEFT", 16, -124)
  tip.icon = tip:CreateTexture(nil, "ARTWORK")
  tip.icon:SetSize(22, 22)
  tip.icon:SetPoint("TOPLEFT", 10, -9)
  tip.title = UI.Text(tip, "", "Header", "plain", PREV_W - 32 - 48)
  tip.title:SetPoint("LEFT", tip.icon, "RIGHT", 7, 0)
  tip.title:SetWordWrap(false)
  tip.title:SetTextColor(unpack(TIP_TITLE))
  tip.text = UI.Text(tip, "", "Small", "plain", PREV_W - 32 - 20)
  tip.text:SetPoint("TOPLEFT", 10, -40)
  tip.text:SetTextColor(unpack(TIP_TEXT))
  tip.text:SetSpacing(2)
  if tip.text.SetMaxLines then tip.text:SetMaxLines(7) end
  tab.tip = tip
  tab.tipNone = UI.Text(pv, "Choose a glance to preview it.", "Small", "subtle", PREV_W - 32)
  tab.tipNone:SetPoint("TOPLEFT", 16, -126)

  local foot = UI.Text(pv, "Total RP 3 and other roleplay addons show your glances too.", "Small", "subtle", PREV_W - 32)
  foot:SetPoint("BOTTOMLEFT", 16, 14)
  foot:SetSpacing(2)
end

local function RefreshGlances(tab, c)
  local list = P:MyGlances()
  local n = #list
  if n == 0 then c.gsel = nil
  elseif not c.gsel or c.gsel > n or c.gsel < 1 then c.gsel = math.max(1, math.min(c.gsel or 1, n)) end
  for i, s in ipairs(tab.slots) do
    s.glance = list[i]
    s:SetEnabled(list[i] ~= nil or i <= n + 1)
    s:Paint()
  end

  -- Editor
  local e = tab.editor
  local g = c.gsel and list[c.gsel]
  for _, w in ipairs(e.body) do w:SetShown(g ~= nil) end
  e.empty:SetShown(g == nil)
  if g ~= tab.loaded then
    tab.loaded = g
    e.title.edit:ClearFocus()
    e.text.edit:ClearFocus()
    if g then UI.FadeIn(e, 0.2) end
  end
  if g then
    e.head:SetText(("Glance %d"):format(c.gsel))
    e.head.bg:SetPoint("BOTTOMRIGHT", e.head, "BOTTOMRIGHT", 7, -4)
    P.SetIcon(e.med.icon, g.icon)
    if not e.title.edit:HasFocus() then e.title.edit:SetText(g.title or ""); e.title.edit:SetCursorPosition(0) end
    if not e.text.edit:HasFocus() then e.text.edit:SetText(g.text or ""); e.text.edit:SetCursorPosition(0) end
    e.active:Refresh()
    e.left:SetEnabled(c.gsel > 1)
    e.right:SetEnabled(c.gsel < n)
  end

  -- Target bar preview: the glances that are showing
  local shown = 0
  for i, b in ipairs(tab.bar.icons) do b.glance, b.index = nil, nil end
  for i, gl in ipairs(list) do
    if gl.active ~= false and P.HasContent(gl) and shown < 5 then
      shown = shown + 1
      local b = tab.bar.icons[shown]
      b.glance, b.index = gl, i
      P.SetIcon(b.med.icon, gl.icon)
    end
  end
  for i, b in ipairs(tab.bar.icons) do b:SetShown(i <= shown) end
  tab.bar.none:SetShown(shown == 0)

  -- Tooltip preview of the selected glance
  local tip = tab.tip
  tip:SetShown(g ~= nil)
  tab.tipNone:SetShown(g == nil)
  if g then
    P.SetIcon(tip.icon, g.icon)
    local title = strtrim(g.title or "")
    tip.title:SetText(title ~= "" and title or "At first glance")
    local text = strtrim(g.text or "")
    tip.text:SetText(text ~= "" and text or "|cff8c8c8c(no description)|r")
    tip:SetHeight(math.min(150, math.ceil(40 + tip.text:GetStringHeight() + 12)))
    tip:SetAlpha(g.active == false and 0.55 or 1)
  end
end

---------------------------------------------------------------------------
-- Traits
---------------------------------------------------------------------------
local LIST_W = CW - 230                 -- 466
local ADD_W = CW - LIST_W - 10          -- 220
local ROW_W, ROW_H = LIST_W - 44, 72    -- 422 x 72: room for the value under the bar
local BAR_W = ROW_W - 72                -- 350; the controls take the rest

-- One side's colour handle: the preset icon (or a disc of the colour) in a coloured ring.
local function SideButton(row, side)
  local b = CreateFrame("Button", nil, row)
  b:SetSize(26, 26)
  b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  b.ring = UI.Circle(b, 26, "ARTWORK", 0)
  b.ring:SetPoint("CENTER")
  b.disc = UI.Circle(b, 20, "ARTWORK", 1)
  b.disc:SetPoint("CENTER")
  b.icon = b:CreateTexture(nil, "ARTWORK", nil, 2)
  b.icon:SetSize(20, 20)
  b.icon:SetPoint("CENTER")
  UI.Round(b.icon)
  b.side = side
  b:SetScript("OnEnter", function(self)
    self.ring:SetSize(28, 28)
    GameTooltip:SetOwner(self, "ANCHOR_TOP")
    GameTooltip:SetText((side == "left" and "Left" or "Right") .. " colour", 1, 0.82, 0)
    GameTooltip:AddLine("Click to choose a colour. Right-click to go back to the default.", 1, 1, 1, true)
    GameTooltip:Show()
  end)
  b:SetScript("OnLeave", function(self) self.ring:SetSize(26, 26); GameTooltip:Hide() end)
  return b
end

local function PaintTraitRow(row, v)
  local t, trait = K:Theme(), row.trait
  if not trait then return end
  local L, R = P.LeftColor(trait), P.RightColor(trait)
  local x = (1 - v / 20) * BAR_W
  local mid = BAR_W / 2
  row.trackL:SetColorTexture(L[1], L[2], L[3], 0.30)
  row.trackR:SetColorTexture(R[1], R[2], R[3], 0.30)
  local dom = v > 10 and L or (v < 10 and R or nil)
  row.fill:ClearAllPoints()
  if dom then
    row.fill:SetPoint("LEFT", row.bar, "LEFT", math.min(x, mid), 0)
    row.fill:SetSize(math.max(1, math.abs(x - mid)), 8)
    row.fill:SetColorTexture(dom[1], dom[2], dom[3], 0.95)
    row.fill:Show()
  else
    row.fill:Hide()
  end
  row.thumb:ClearAllPoints()
  row.thumb:SetPoint("CENTER", row.bar, "LEFT", x, 0)
  local rc = dom or t.subtle
  row.thumb.ring:SetVertexColor(rc[1], rc[2], rc[3], 1)
  local lc = v > 10 and UI.OnCard(L) or (v == 10 and t.heading or t.subtle)
  local rcol = v < 10 and UI.OnCard(R) or (v == 10 and t.heading or t.subtle)
  row.lName:SetTextColor(lc[1], lc[2], lc[3])
  row.rName:SetTextColor(rcol[1], rcol[2], rcol[3])
  row.hint:SetText(P.TraitHint(trait))
  row.hint:ClearAllPoints()
  row.hint:SetPoint("TOP", row.bar, "BOTTOMLEFT", math.max(44, math.min(BAR_W - 44, x)), -6)
  for _, b in ipairs({ row.lSide, row.rSide }) do
    local c = b.side == "left" and L or R
    b.ring:SetVertexColor(c[1], c[2], c[3], 1)
    b.disc:SetVertexColor(c[1], c[2], c[3], 1)
  end
end

local function ValueAtCursor(bar)
  local x = GetCursorPosition() / bar:GetEffectiveScale()
  local left, w = bar:GetLeft(), bar:GetWidth()
  if not left or not w or w <= 0 then return nil end
  local frac = math.max(0, math.min(1, (x - left) / w))
  return math.floor((1 - frac) * 20 + 0.5)
end

local function BuildTraitRow(parent, c, i)
  local row = CreateFrame("Frame", nil, parent)
  row:SetSize(ROW_W, ROW_H)
  row:SetPoint("TOPLEFT", 0, -(i - 1) * ROW_H)
  row.index = i
  row.div = UI.Divider(row, ROW_W)
  row.div:SetPoint("BOTTOMLEFT", 0, 0)

  row.lSide = SideButton(row, "left")
  row.lSide:SetPoint("TOPLEFT", 0, -5)
  row.rSide = SideButton(row, "right")
  row.rSide:SetPoint("TOPLEFT", BAR_W - 26, -5)
  row.lName = UI.Text(row, "", "Header", "plain", 140)
  row.lName:SetPoint("LEFT", row.lSide, "RIGHT", 8, 0)
  row.lName:SetWordWrap(false)
  row.rName = UI.Text(row, "", "Header", "plain", 140)
  row.rName:SetPoint("RIGHT", row.rSide, "LEFT", -8, 0)
  row.rName:SetJustifyH("RIGHT")
  row.rName:SetWordWrap(false)

  row.bar = CreateFrame("Frame", nil, row)
  row.bar:SetSize(BAR_W, 8)
  row.bar:SetPoint("TOPLEFT", 0, -38)
  row.trackL = row.bar:CreateTexture(nil, "BACKGROUND")
  row.trackL:SetPoint("TOPLEFT"); row.trackL:SetPoint("BOTTOMLEFT")
  row.trackL:SetWidth(BAR_W / 2)
  row.trackR = row.bar:CreateTexture(nil, "BACKGROUND")
  row.trackR:SetPoint("TOPRIGHT"); row.trackR:SetPoint("BOTTOMRIGHT")
  row.trackR:SetWidth(BAR_W / 2)
  row.fill = row.bar:CreateTexture(nil, "ARTWORK")
  row.tick = UI.Line(row.bar, true, "OVERLAY")
  row.tick:SetHeight(14)
  row.tick:SetPoint("CENTER", row.bar, "CENTER")
  UI:OnTheme(function(t) row.tick:SetVertexColor(t.text[1], t.text[2], t.text[3], 0.35) end)

  local thumb = CreateFrame("Frame", nil, row.bar)
  thumb:SetSize(20, 20)
  thumb:SetFrameLevel(row.bar:GetFrameLevel() + 3)
  thumb.shadow = UI.Circle(thumb, 18, "BACKGROUND")
  thumb.shadow:SetPoint("CENTER", 0, -1)
  thumb.shadow:SetVertexColor(0, 0, 0, 0.25)
  thumb.ring = UI.Circle(thumb, 16, "ARTWORK", 0)
  thumb.ring:SetPoint("CENTER")
  thumb.dot = UI.Circle(thumb, 8, "ARTWORK", 1)
  thumb.dot:SetPoint("CENTER")
  thumb.dot:SetVertexColor(1, 1, 1, 1)
  row.thumb = thumb

  row.hint = UI.Text(row, "", "Small", "accent")
  row.hint:SetAlpha(0)

  -- Dragging: a generous hit area over the bar
  local hit = CreateFrame("Button", nil, row)
  hit:SetPoint("TOPLEFT", row.bar, "TOPLEFT", -8, 10)
  hit:SetPoint("BOTTOMRIGHT", row.bar, "BOTTOMRIGHT", 8, -10)
  hit:SetFrameLevel(thumb:GetFrameLevel() + 1)
  local function grow(p)
    thumb.ring:SetSize(16 + 4 * p, 16 + 4 * p)
    thumb.shadow:SetSize(18 + 4 * p, 18 + 4 * p)
    row.hint:SetAlpha(p)
  end
  local function update()
    local v = ValueAtCursor(row.bar)
    if v and row.trait and v ~= P.TraitValue(row.trait) then
      row.trait.value = v
      PaintTraitRow(row, v)
    end
  end
  hit:SetScript("OnEnter", function(self) UI.Tween(self, 1, 0.12, grow) end)
  hit:SetScript("OnLeave", function(self) if not self.dragging then UI.Tween(self, 0, 0.15, grow) end end)
  hit:SetScript("OnMouseDown", function(self, button)
    if button ~= "LeftButton" or not row.trait then return end
    self.dragging, self.start = true, P.TraitValue(row.trait)
    update()
    self:SetScript("OnUpdate", update)
  end)
  hit:SetScript("OnMouseUp", function(self)
    if not self.dragging then return end
    self.dragging = false
    self:SetScript("OnUpdate", nil)
    if not self:IsMouseOver() then UI.Tween(self, 0, 0.15, grow) end
    if row.trait and P.TraitValue(row.trait) ~= self.start then K:Fire("PROFILE") end
  end)
  row.hit = hit

  -- Colours
  for _, b in ipairs({ row.lSide, row.rSide }) do
    b:SetScript("OnClick", function(self, button)
      local trait = row.trait
      if not trait then return end
      local key = self.side == "left" and "leftColor" or "rightColor"
      if button == "RightButton" then
        trait[key] = nil
        K:Fire("PROFILE")
        return
      end
      local old = trait[key] and CopyTable(trait[key]) or nil
      local cur = self.side == "left" and P.LeftColor(trait) or P.RightColor(trait)
      PickColor(cur[1], cur[2], cur[3],
        function(r, g, bl) trait[key] = { r, g, bl }; K:Fire("PROFILE") end,
        function() trait[key] = old; K:Fire("PROFILE") end)
    end)
  end

  -- Order and removal
  row.up = Chevron(row, true)
  row.up:SetPoint("TOPLEFT", BAR_W + 8, -20)
  row.up:SetScript("OnClick", function() P:MoveTrait(row.index, -1) end)
  row.down = Chevron(row, false)
  row.down:SetPoint("LEFT", row.up, "RIGHT", 2, 0)
  row.down:SetScript("OnClick", function() P:MoveTrait(row.index, 1) end)
  row.remove = UI.CloseButton(row, true, 20)
  row.remove:SetPoint("LEFT", row.down, "RIGHT", 6, 0)
  row.remove:SetScript("OnClick", function() P:RemoveTrait(row.index) end)
  UI.Tooltip(row.remove, "Remove this trait")
  UI:OnTheme(function() if row.trait then PaintTraitRow(row, P.TraitValue(row.trait)) end end)
  row:Hide()
  return row
end

-- A preset pair in the "Add a trait" list.
local function BuildPresetRow(parent, i, w)
  local preset = P.TRAIT_PRESETS[i]
  local b = CreateFrame("Button", nil, parent)
  b:SetSize(w, 24)
  b.tint = b:CreateTexture(nil, "BACKGROUND")
  b.tint:SetAllPoints()
  local icons = {}
  for k, name in ipairs({ preset[3], preset[4] }) do
    local ring = UI.Circle(b, 18, "ARTWORK", k * 2 - 2)
    ring:SetPoint("LEFT", 4 + (k - 1) * 11, 0)
    local ic = b:CreateTexture(nil, "ARTWORK", nil, k * 2 - 1)
    ic:SetSize(16, 16)
    ic:SetPoint("CENTER", ring)
    UI.Round(ic)
    P.SetIcon(ic, name)
    icons[k] = { ring = ring, icon = ic }
  end
  b.text = UI.Text(b, preset[1] .. " · " .. preset[2], "Small", "text", w - 42)
  b.text:SetPoint("LEFT", 38, 0)
  b.text:SetWordWrap(false)
  local function paint(p)
    local t = K:Theme()
    local h = t.hover
    b.tint:SetColorTexture(h[1], h[2], h[3], (h[4] or 0.07) * 1.6 * p)
    for _, ic in ipairs(icons) do ic.ring:SetVertexColor(t.panel[1], t.panel[2], t.panel[3], 1) end
    b.text:SetTextColor(unpack(p > 0.5 and t.heading or t.text))
  end
  b:SetScript("OnEnter", function(self)
    UI.Tween(self, 1, 0.1, paint)
    if self.taken then
      GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
      GameTooltip:SetText(self.full and "You have ten traits" or "Already in your list", 1, 0.82, 0)
      GameTooltip:Show()
    end
  end)
  b:SetScript("OnLeave", function(self) UI.Tween(self, 0, 0.12, paint); GameTooltip:Hide() end)
  b:SetScript("OnClick", function(self)
    if self.taken then return end
    if SOUNDKIT then PlaySound(SOUNDKIT.IG_CHARACTER_INFO_TAB) end
    P:AddTrait(preset[1], preset[2])
  end)
  UI:OnTheme(function() paint(UI.Progress(b)) end)
  return b
end

-- An edit box with a hint shown while it's empty.
local function HintEdit(parent, w, hint, max)
  local eb = UI.Edit(parent, w, 24, nil, max)
  eb.hint = UI.Text(eb, hint, "Small", "subtle")
  eb.hint:SetPoint("LEFT", 8, 0)
  local function update() eb.hint:SetShown(eb:GetText() == "" and not eb:HasFocus()) end
  eb:HookScript("OnTextChanged", update)
  eb:HookScript("OnEditFocusGained", update)
  eb:HookScript("OnEditFocusLost", update)
  return eb
end

local function BuildTraits(tab, c)
  local L = UI.Panel(tab)
  L:SetPoint("TOPLEFT")
  L:SetSize(LIST_W, BODY_H)
  local lh = UI.Section(L, "Your traits")
  lh:SetPoint("TOPLEFT", 21, -15)
  tab.count = UI.Chip(L)
  tab.count:SetPoint("TOPRIGHT", -16, -12)
  local hint = UI.Text(L, "Drag each slider toward the side that fits. Click a side's icon to change its colour.",
    "Small", "subtle", LIST_W - 32)
  hint:SetPoint("TOPLEFT", 16, -40)
  hint:SetSpacing(2)

  local sf = CreateFrame("ScrollFrame", nil, L)
  sf:SetPoint("TOPLEFT", 16, -76)
  sf:SetSize(ROW_W, BODY_H - 76 - 12)
  local child = CreateFrame("Frame", nil, sf)
  child:SetSize(ROW_W, 1)
  sf:SetScrollChild(child)
  tab.sf, tab.child = sf, child
  tab.rows = {}
  for i = 1, P.MAX_TRAITS do tab.rows[i] = BuildTraitRow(child, c, i) end
  tab.scroll = UI.ScrollBar(sf, false, ROW_H)
  tab.empty = EmptyState(sf, "IconKin", "No traits yet. Pick a pair on the right, or make up your own.", 300, 34)

  -- Adding -------------------------------------------------------------------
  local A = UI.Panel(tab)
  A:SetPoint("TOPLEFT", LIST_W + 10, 0)
  A:SetSize(ADD_W, BODY_H)
  local ah = UI.Section(A, "Add a trait")
  ah:SetPoint("TOPLEFT", 21, -15)
  tab.presets = {}
  for i = 1, #P.TRAIT_PRESETS do
    local b = BuildPresetRow(A, i, ADD_W - 32)
    b:SetPoint("TOPLEFT", 16, -40 - (i - 1) * 24)
    tab.presets[i] = b
  end
  local ch = UI.Section(A, "Your own pair")
  ch:SetPoint("TOPLEFT", 21, -320)
  local half = math.floor((ADD_W - 32 - 6) / 2)
  tab.customL = HintEdit(A, half, "Left", 30)
  tab.customL:SetPoint("TOPLEFT", 16, -342)
  tab.customR = HintEdit(A, half, "Right", 30)
  tab.customR:SetPoint("TOPLEFT", 16 + half + 6, -342)
  local function addCustom()
    if P:AddTrait(tab.customL:GetText(), tab.customR:GetText()) then
      tab.customL:SetText(""); tab.customR:SetText("")
      tab.customL:ClearFocus(); tab.customR:ClearFocus()
    end
  end
  tab.customL:SetScript("OnEnterPressed", function() tab.customR:SetFocus() end)
  tab.customR:SetScript("OnEnterPressed", addCustom)
  tab.addCustom = UI.Button(A, "Add this pair", ADD_W - 32, 24)
  tab.addCustom:SetPoint("TOPLEFT", 16, -374)
  tab.addCustom:SetScript("OnClick", addCustom)
end

local function RefreshTraits(tab)
  local list = P:MyTraits()
  local n = math.min(#list, P.MAX_TRAITS)
  tab.count:Set(("%d of %d"):format(n, P.MAX_TRAITS), K:Theme().accent)
  tab.child:SetHeight(math.max(1, n * ROW_H))
  for i, row in ipairs(tab.rows) do
    local trait = list[i]
    row.trait = trait
    row:SetShown(trait ~= nil and i <= n)
    if trait then
      row.lName:SetText(UI.Escape(trait.left or ""))
      row.rName:SetText(UI.Escape(trait.right or ""))
      local li, ri = P.TraitIcons(trait)
      for _, pair in ipairs({ { row.lSide, li }, { row.rSide, ri } }) do
        local b, icon = pair[1], pair[2]
        b.icon:SetShown(icon ~= nil)
        if icon then P.SetIcon(b.icon, icon) end
      end
      if not row.hit.dragging then PaintTraitRow(row, P.TraitValue(trait)) end
      row.up:SetEnabled(i > 1)
      row.down:SetEnabled(i < n)
      row.div:SetShown(i < n)
    end
  end
  tab.empty:SetShown(n == 0)
  tab.scroll.Update()
  local full = n >= P.MAX_TRAITS
  for i, b in ipairs(tab.presets) do
    local preset = P.TRAIT_PRESETS[i]
    b.taken = full or P:HasTrait(preset[1], preset[2])
    b.full = full
    b:SetAlpha(b.taken and 0.4 or 1)
  end
  tab.addCustom:SetEnabled(not full)
end

---------------------------------------------------------------------------
-- Look
---------------------------------------------------------------------------
local LOOK_L = 340
local LOOK_R = CW - LOOK_L - 10   -- 346

local function SameColor(a, r, g, b)
  return a and math.abs(a[1] - r) < 0.01 and math.abs(a[2] - g) < 0.01 and math.abs(a[3] - b) < 0.01
end

local function SetNameColor(c)
  K:Profile().nameColor = c and { c[1], c[2], c[3] } or nil
  K:Fire("PROFILE")
end

local function BuildLook(tab)
  local lc = UI.Panel(tab)
  lc:SetPoint("TOPLEFT")
  lc:SetSize(LOOK_L, BODY_H)
  local IW = LOOK_L - 32
  local h1 = UI.Section(lc, "Profile icon")
  h1:SetPoint("TOPLEFT", 21, -15)

  local ib = CreateFrame("Button", nil, lc)
  ib:SetSize(64, 64)
  ib:SetPoint("TOPLEFT", 16, -40)
  ib.med = Medallion(ib, 58, 3)
  ib.med:SetPoint("CENTER")
  local function paintIcon(p)
    local a = K:Theme().accent
    ib.med.ring:SetVertexColor(a[1], a[2], a[3], 0.6 + 0.4 * p)
    ib.med.icon:SetSize(58 + 2 * p, 58 + 2 * p)
  end
  local function pick(anchor)
    K.IconPicker:Open(anchor, K:Profile().icon, function(icon) K:SetField("icon", icon) end)
  end
  ib:SetScript("OnEnter", function(self) UI.Tween(self, 1, 0.12, paintIcon) end)
  ib:SetScript("OnLeave", function(self) UI.Tween(self, 0, 0.15, paintIcon) end)
  ib:SetScript("OnClick", function(self) pick(self) end)
  UI:OnTheme(function() paintIcon(UI.Progress(ib)) end)
  tab.iconBtn = ib
  local it = UI.Text(lc, "Your emblem", "Header", "heading")
  it:SetPoint("TOPLEFT", 92, -44)
  local idesc = UI.Text(lc, "Shown beside your name in tooltips, and to Total RP 3 users.", "Small", "subtle", IW - 76)
  idesc:SetPoint("TOPLEFT", it, "BOTTOMLEFT", 0, -4)
  idesc:SetSpacing(2)
  local change = UI.Button(lc, "Change...", 96, 24)
  change:SetPoint("TOPLEFT", 92, -98)
  change:SetScript("OnClick", function(self) pick(self) end)
  tab.resetIcon = UI.Button(lc, "Reset", 70, 24)
  tab.resetIcon:SetPoint("LEFT", change, "RIGHT", 6, 0)
  tab.resetIcon:SetScript("OnClick", function() K:SetField("icon", nil) end)

  local h2 = UI.Section(lc, "Name colour")
  h2:SetPoint("TOPLEFT", 21, -140)
  tab.swatches = {}
  for i, col in ipairs(P.NAME_COLORS) do
    local s = CreateFrame("Button", nil, lc)
    s:SetSize(22, 22)
    s:SetPoint("TOPLEFT", 16 + ((i - 1) % 6) * 28, -164 - math.floor((i - 1) / 6) * 28)
    s.ring = UI.Circle(s, 22, "ARTWORK", 0)
    s.ring:SetPoint("CENTER")
    s.dot = UI.Circle(s, 16, "ARTWORK", 1)
    s.dot:SetPoint("CENTER")
    s.dot:SetVertexColor(col[1], col[2], col[3], 1)
    s.color = col
    function s:Paint()
      local t = K:Theme()
      local c = self.selected and t.accent or t.panelEdge
      self.ring:SetVertexColor(c[1], c[2], c[3], self.selected and 1 or (self.hover and 0.9 or 0.45))
      self.dot:SetSize(self.selected and 14 or 16, self.selected and 14 or 16)
    end
    s:SetScript("OnEnter", function(self) self.hover = true; self:Paint() end)
    s:SetScript("OnLeave", function(self) self.hover = false; self:Paint() end)
    s:SetScript("OnClick", function(self)
      if SOUNDKIT then PlaySound(SOUNDKIT.IG_CHARACTER_INFO_TAB) end
      SetNameColor(self.color)
    end)
    UI:OnTheme(function() s:Paint() end)
    tab.swatches[i] = s
  end
  local custom = UI.Button(lc, "Custom...", 112, 24)
  custom:SetPoint("TOPLEFT", 196, -163)
  custom:SetScript("OnClick", function()
    local p = K:Profile()
    local old = p.nameColor and CopyTable(p.nameColor) or nil
    local r, g, b = P.NameColor(p)
    if not r then r, g, b = UI.ClassColor(select(2, UnitClass("player"))) end
    PickColor(r, g, b, function(nr, ng, nb) SetNameColor({ nr, ng, nb }) end, function() SetNameColor(old) end)
  end)
  tab.noColor = UI.Button(lc, "Game colour", 112, 24)
  tab.noColor:SetPoint("TOPLEFT", 196, -191)
  tab.noColor:SetScript("OnClick", function() SetNameColor(nil) end)
  UI.Tooltip(tab.noColor, "Game colour", "Use the colour the game gives your name.")

  local tl = UI.Text(lc, "In a tooltip", "Label", "subtle")
  tl:SetPoint("TOPLEFT", 17, -228)
  local tip = TooltipBox(lc, IW)
  tip:SetPoint("TOPLEFT", 16, -244)
  tip.name = UI.Text(tip, "", "Header", "plain", IW - 20)
  tip.name:SetPoint("TOPLEFT", 10, -10)
  tip.name:SetWordWrap(false)
  tip.epithet = UI.Text(tip, "", "Small", "plain", IW - 20)
  tip.epithet:SetTextColor(0.30, 0.72, 0.68)
  tip.epithet:SetWordWrap(false)
  tip.who = UI.Text(tip, "", "Small", "plain", IW - 20)
  tip.who:SetTextColor(0.75, 0.75, 0.75)
  tip.glances = UI.Text(tip, "", "Small", "plain", IW - 20)
  tab.tip = tip
  local note = UI.Text(lc, "Your target bar and Total RP 3 users show your name in this colour too.", "Small", "subtle", IW)
  note:SetPoint("BOTTOMLEFT", 16, 14)
  note:SetSpacing(2)

  -- Music ----------------------------------------------------------------------
  local rc = UI.Panel(tab)
  rc:SetPoint("TOPLEFT", LOOK_L + 10, 0)
  rc:SetSize(LOOK_R, BODY_H)
  local RW = LOOK_R - 32
  local h3 = UI.Section(rc, "Theme music")
  h3:SetPoint("TOPLEFT", 21, -15)
  local mdesc = UI.Text(rc, "A tune others can play from your target bar. Enter a game music file ID, or pick one below.",
    "Small", "subtle", RW)
  mdesc:SetPoint("TOPLEFT", 16, -40)
  mdesc:SetSpacing(2)
  tab.music = UI.Field(rc, "Music file ID", 130, 10, function(text)
    local n = tonumber(text)
    K:Profile().music = (n and n > 0) and math.floor(n) or nil
    K:Fire("PROFILE")
  end)
  tab.music:SetPoint("TOPLEFT", 16, -86)
  tab.play = UI.Button(rc, "Play", 72, 24)
  tab.play:SetPoint("TOPLEFT", 156, -99)
  tab.play:SetScript("OnClick", function() P:PlayMusic(P.Music(K:Profile())) end)
  tab.stop = UI.Button(rc, "Stop", 72, 24)
  tab.stop:SetPoint("LEFT", tab.play, "RIGHT", 6, 0)
  tab.stop:SetScript("OnClick", function() P:StopMusic() end)
  tab.status = UI.Text(rc, "", "Small", "accent", RW)
  tab.status:SetPoint("TOPLEFT", 16, -134)
  tab.status:SetWordWrap(false)

  local h4 = UI.Section(rc, "Suggestions")
  h4:SetPoint("TOPLEFT", 21, -164)
  tab.list = UI.List(rc, RW, BODY_H - 186 - 14, 38, "No suggestions are available on this client. A file ID still works.",
    function(row)
      row.med = Medallion(row, 22, 2)
      row.med:SetPoint("LEFT", 6, 0)
      P.SetIcon(row.med.icon, "INV_Misc_Drum_06")
      row.name = UI.Text(row, "", "Body", "heading", 150)
      row.name:SetPoint("TOPLEFT", 40, -5)
      row.name:SetWordWrap(false)
      row.sub = UI.Text(row, "", "Small", "subtle", 150)
      row.sub:SetPoint("TOPLEFT", row.name, "BOTTOMLEFT", 0, -2)
      row.sub:SetWordWrap(false)
      row.play = UI.Button(row, "Play", 54, 22)
      row.play:SetPoint("RIGHT", -6, 0)
      row.play:SetScript("OnClick", function(self) P:ToggleMusic(self:GetParent().item.id) end)
      row.chip = UI.Chip(row)
      row.chip:SetPoint("RIGHT", row.play, "LEFT", -8, 0)
      row:SetScript("OnClick", function(self)
        K:Profile().music = self.item.id
        K:Fire("PROFILE")
      end)
      row.onEnter = function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(self.item.name, 1, 0.82, 0)
        GameTooltip:AddLine(("Music file %d. Click to make it your theme."):format(self.item.id), 1, 1, 1, true)
        GameTooltip:Show()
      end
    end, { bare = true, emptyIcon = K.Art("IconFire") })
  tab.list:SetPoint("TOPLEFT", 16, -186)
end

local function RefreshLook(tab)
  local p, t = K:Profile(), K:Theme()
  P.SetIcon(tab.iconBtn.med.icon, p.icon, "Interface\\Icons\\INV_Misc_GroupLooking")
  tab.resetIcon:SetEnabled(p.icon ~= nil)

  local r, g, b = P.NameColor(p)
  for _, s in ipairs(tab.swatches) do
    s.selected = r ~= nil and SameColor(s.color, r, g, b)
    s:Paint()
  end
  tab.noColor:SetEnabled(r ~= nil)

  -- Tooltip preview: your name as others see it
  local tip = tab.tip
  local _, class = UnitClass("player")
  if not r then r, g, b = UI.ClassColor(class) end
  tip.name:SetText(P.IconMarkup(p.icon or "INV_Misc_GroupLooking", 16) .. " " .. K:DisplayName(p))
  tip.name:SetTextColor(r, g, b)
  local y = -10 - 18
  local function place(fs, text, gap)
    fs:SetShown(text ~= nil and text ~= "")
    if not fs:IsShown() then return end
    fs:SetText(text)
    fs:ClearAllPoints()
    fs:SetPoint("TOPLEFT", 10, y - gap)
    y = y - gap - math.ceil(fs:GetStringHeight())
  end
  place(tip.epithet, strtrim(p.epithet or ""), 3)
  local race = strtrim(p.race or "") ~= "" and p.race or UnitRace("player")
  local cls = strtrim(p.class or "") ~= "" and p.class or UnitClass("player")
  place(tip.who, strtrim((race or "") .. " " .. (cls or "")), 3)
  local icons = {}
  for _, gl in ipairs(P.Glances(p)) do icons[#icons + 1] = P.IconMarkup(gl.icon, 18) end
  place(tip.glances, table.concat(icons, " "), 5)
  tip:SetHeight(-y + 10)

  -- Music
  local mu = P.Music(p)
  if not tab.music.edit:HasFocus() then tab.music.edit:SetText(mu and tostring(mu) or "") end
  tab.play:SetEnabled(mu ~= nil)
  tab.stop:SetEnabled(P.playing ~= nil)
  if P.playing then
    tab.status:SetText("Now playing: " .. P.MusicLabel(P.playing))
  elseif mu then
    tab.status:SetText("Your theme: " .. P.MusicLabel(mu))
  else
    tab.status:SetText("|cff" .. UI.Hex(t.subtle) .. "No theme yet.|r")
  end
  tab.list:SetItems(P.MUSIC, function(row, m)
    row.name:SetText(m.name)
    row.sub:SetText(P.FormatTime(m.time) .. "  ·  file " .. m.id)
    local mine = mu == m.id
    row.chip:Set(mine and "Your theme" or nil, t.accent)
    row.play:SetText(P.playing == m.id and "Stop" or "Play")
    row.sel:SetShown(mine)
    -- The name and its line stop short of the buttons (and the chip, when shown).
    local rw = row:GetWidth()
    if not rw or rw < 100 then rw = LOOK_R - 32 - 24 end   -- the list's width, less its padding and scrollbar
    local room = rw - 40 - 6 - row.play:GetWidth() - 8 - (mine and (row.chip:GetWidth() + 8) or 0)
    row.name:SetWidth(math.max(60, room))
    row.sub:SetWidth(math.max(60, room))
  end)
end

---------------------------------------------------------------------------
-- The page
---------------------------------------------------------------------------
K:RegisterPage({
  id = "persona", title = "Persona", heading = "Persona", group = "You",
  subtitle = "Glances, traits, effects and the look of your character at first sight.",
  icon = { "Interface\\Icons\\Ability_Hunter_EagleEye", round = true },

  build = function(c)
    P = K.Persona
    c.tab = 1
    c.tabs = UI.TabBar(c, K.Auras and { "Glances", "Traits", "Look", "Effects" } or { "Glances", "Traits", "Look" },
      function(i) c.tab = i; Refresh() end, true)
    c.tabs:SetPoint("TOPLEFT", -10, 2)
    c.preview = UI.Button(c, "Preview profile", 130, 24)
    c.preview:SetPoint("TOPRIGHT", 0, 0)
    c.preview:SetScript("OnClick", function() K.Viewer:ShowSelf() end)
    if K:Compat() then
      c.preview:SetText("Kinship preview")
      UI.Tooltip(c.preview, "Kinship preview", "Your stage, what you wear and your effects, the way other Kinship users see them.")
    else
      UI.Tooltip(c.preview, "Preview", "See your profile the way other players will.")
    end
    c.presets = UI.Button(c, "Glance presets", 130, 24)
    c.presets:SetPoint("RIGHT", c.preview, "LEFT", -6, 0)
    c.presets:SetScript("OnClick", function(self) PresetMenu(self, c) end)
    UI.Tooltip(c.presets, "Glance presets", "Save your glances under a name and swap between sets, on any character.")
    c.frames = {}
    for i = 1, K.Auras and 4 or 3 do
      local f = CreateFrame("Frame", nil, c)
      f:SetPoint("TOPLEFT", 0, -TOP)
      f:SetSize(CW, BODY_H)
      f:Hide()
      c.frames[i] = f
    end
    BuildGlances(c.frames[1], c)
    BuildTraits(c.frames[2], c)
    BuildLook(c.frames[3])
    if K.Auras then K.Auras:BuildTab(c.frames[4], c) end
  end,

  refresh = function(c)
    -- Switching profiles: start again on the first glance
    local prof = K:Profile()
    if c.profile ~= prof then c.profile, c.gsel = prof, 1 end
    if K.Auras and K.Auras.wantTab then c.tab = 4; K.Auras.wantTab = nil end
    -- Alongside Total RP 3: its glances and traits are the ones others see
    local compat = K:Compat()
    c.tabs:SetTabShown(1, not compat)
    c.tabs:SetTabShown(2, not compat)
    if compat and c.tab <= 2 then c.tab = 3 end
    if K.Auras then
      local on = K:ExtOn("auras")
      c.tabs:SetTabShown(4, on)
      if not on and c.tab == 4 then c.tab = 1 end
    end
    c.tabs:Select(c.tab)
    for i, f in ipairs(c.frames) do f:SetShown(i == c.tab) end
    if c.shownTab ~= c.tab then
      if c.shownTab then UI.FadeIn(c.frames[c.tab], 0.2) end
      c.shownTab = c.tab
    end
    c.presets:SetShown(c.tab == 1)
    if c.tab == 1 then RefreshGlances(c.frames[1], c)
    elseif c.tab == 2 then RefreshTraits(c.frames[2])
    elseif c.tab == 3 then RefreshLook(c.frames[3])
    else K.Auras:RefreshTab(c.frames[4]) end
  end,
})

K:On("PERSONA_MUSIC", function() if K.Journal:IsShowing("persona") then Refresh() end end)
