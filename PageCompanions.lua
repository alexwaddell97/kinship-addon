-- Kinship RP: Companions page. Your pets and mounts as cards on the left, the
-- chosen one's story on the right: name, title, icon, glance, description,
-- and the pet or mount names it's bound to (whose tooltips then tell it).

local ADDON, ns = ...
local K = ns.K
local UI = K.UI
local Comp = K.Companions

local CW, CH = 696, 466
local LEFT_W, GAP = 250, 10
local ED_W = CW - LEFT_W - GAP          -- 436
local IN = ED_W - 32                    -- 404, the editor's inner width
local ROW_H, ROW_GAP = 70, 8
local WHITE = "Interface\\Buttons\\WHITE8X8"

local function Ref(c) return c.selectedId and Comp:Get(c.selectedId) or nil end

-- A path or file ID typed by hand: "Ability_Hunter_Pet_Wolf", "Interface\Icons\...", or 132203.
local function ParseIcon(text)
  text = strtrim(text or "")
  if text == "" then return nil end
  local n = tonumber(text)
  if n then return n > 0 and math.floor(n) or nil end
  if text:find("^[%w_%-]+$") then return "Interface\\Icons\\" .. text end
  if text:lower():find("^interface\\") then return text end
  return nil
end

local function IconText(icon)
  if type(icon) == "number" then return tostring(icon) end
  if type(icon) == "string" then return (icon:gsub("^[Ii]nterface\\[Ii]cons\\", "")) end
  return ""
end

---------------------------------------------------------------------------
-- The list of companions (left)
---------------------------------------------------------------------------
local function BuildList(c)
  c.newBtn = UI.Button(c, "+  New companion", LEFT_W, 28)
  c.newBtn:SetPoint("TOPLEFT")
  c.newBtn:SetScript("OnClick", function()
    local rec = Comp:New("pet")
    if rec then c.selectedId = rec.id; c.focusName = true; K.Journal:RefreshCurrent() end
  end)

  c.list = UI.List(c, LEFT_W, CH - 38, ROW_H, "No companions yet.\nEvery hound, horse and imp has a story.",
    function(row)
      -- Each row is a small card with a gap below it. The fill lives on the row
      -- (under the list's hover and selection layers), the hairline edge on a
      -- child frame the size of the card.
      row.bg = row:CreateTexture(nil, "BACKGROUND", nil, -1)
      row.bg:SetPoint("TOPLEFT")
      row.bg:SetPoint("BOTTOMRIGHT", 0, ROW_GAP)
      row.frame = CreateFrame("Frame", nil, row)
      row.frame:SetPoint("TOPLEFT")
      row.frame:SetPoint("BOTTOMRIGHT", 0, ROW_GAP)
      row.edge = UI.Border(row.frame)
      -- The list's hover and selection fills sit on the card, not the gap below it
      for _, tex in ipairs({ row.hover, row.sel }) do
        tex:ClearAllPoints()
        tex:SetPoint("TOPLEFT", row.bg)
        tex:SetPoint("BOTTOMRIGHT", row.bg)
      end
      row.selBar:ClearAllPoints()
      row.selBar:SetPoint("TOPLEFT", row.bg)
      row.selBar:SetPoint("BOTTOMLEFT", row.bg)
      row.selBar:SetWidth(3)

      row.content = CreateFrame("Frame", nil, row)
      row.content:SetSize(LEFT_W - 12, ROW_H - ROW_GAP)
      row.content:SetPoint("TOPLEFT")
      local ct = row.content
      row.ring = UI.Circle(ct, 46, "ARTWORK", 0)
      row.ring:SetPoint("LEFT", 9, 0)
      row.icon = ct:CreateTexture(nil, "ARTWORK", nil, 1)
      row.icon:SetSize(42, 42)
      row.icon:SetPoint("CENTER", row.ring)
      row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
      UI.Round(row.icon)
      local tw = LEFT_W - 12 - 66 - 10
      row.name = UI.Text(ct, "", "Header", "heading", tw)
      row.name:SetPoint("TOPLEFT", 64, -9)
      row.name:SetWordWrap(false)
      row.title = UI.Text(ct, "", "Small", "text", tw)
      row.title:SetPoint("TOPLEFT", row.name, "BOTTOMLEFT", 0, -3)
      row.title:SetWordWrap(false)
      row.meta = UI.Text(ct, "", "Label", "subtle", tw)
      row.meta:SetPoint("TOPLEFT", row.title, "BOTTOMLEFT", 0, -3)
      row.meta:SetWordWrap(false)

      local function slide(p) ct:SetPoint("TOPLEFT", 4 * p, 0) end
      row.onEnter = function(self) UI.Tween(self, 1, 0.2, slide, UI.Ease.outQuart) end
      row:HookScript("OnLeave", function(self) UI.Tween(self, 0, 0.2, slide, UI.Ease.outQuart) end)
      row:SetScript("OnClick", function(self)
        if not self.item then return end
        if SOUNDKIT then PlaySound(SOUNDKIT.IG_CHARACTER_INFO_TAB) end
        c.selectedId = self.item.id
        K.Journal:RefreshCurrent()
      end)
      UI:OnTheme(function(t)
        row.bg:SetColorTexture(unpack(t.panel))
        row.ring:SetVertexColor(t.accent[1], t.accent[2], t.accent[3], 0.35)
      end)
    end, { bare = true, emptyIcon = K.Art("IconKin") })
  c.list:SetPoint("TOPLEFT", 0, -38)
  -- The list sits on the window, not on a card
  UI:OnTheme(function(t) c.list.empty:SetTextColor(unpack(t.deskSubtle)) end)
end

local function FillRow(c)
  return function(row, rec)
    local t = K:Theme()
    local sel = rec.id == c.selectedId
    row.icon:SetTexture(Comp.IconOf(rec))
    local name = strtrim(rec.name or "")
    row.name:SetText(name ~= "" and name or "Unnamed companion")
    row.name:SetAlpha(name ~= "" and 1 or 0.6)
    local title = strtrim(rec.title or "")
    row.title:SetText(title ~= "" and title or "No title yet")
    row.title:SetAlpha(title ~= "" and 1 or 0.6)
    local kind = (Comp.KINDS[rec.kind] or Comp.KINDS.pet).label
    local binds = rec.bindings or {}
    row.meta:SetText(#binds > 0 and (kind .. "  ·  " .. table.concat(binds, ", ")) or (kind .. "  ·  not bound yet"))
    row.sel:SetShown(sel)
    if sel then row.edge:SetColor(t.accent[1], t.accent[2], t.accent[3], 0.85) else row.edge:SetColor(unpack(t.panelEdge)) end
    row.ring:SetVertexColor(t.accent[1], t.accent[2], t.accent[3], sel and 1 or 0.35)
  end
end

---------------------------------------------------------------------------
-- The editor (right)
---------------------------------------------------------------------------
local function NewChip(parent, onRemove)
  local b = CreateFrame("Frame", nil, parent)
  b:SetHeight(24)
  b:EnableMouse(true)
  b.bg = b:CreateTexture(nil, "BACKGROUND")
  b.bg:SetAllPoints()
  b.bg:SetTexture(WHITE)
  b.edge = UI.Border(b)
  b.icon = b:CreateTexture(nil, "ARTWORK")
  b.icon:SetSize(16, 16)
  b.icon:SetPoint("LEFT", 5, 0)
  b.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
  UI.Round(b.icon)
  b.text = UI.Text(b, "", "Small", "text")
  b.text:SetPoint("LEFT", b.icon, "RIGHT", 6, 0)
  b.x = UI.CloseButton(b, true, 18)
  b.x:SetPoint("RIGHT", -3, 0)
  b.x:SetScript("OnClick", function() onRemove(b.value) end)
  b.x:HookScript("OnEnter", function()
    GameTooltip:SetOwner(b, "ANCHOR_TOP")
    GameTooltip:SetText("Unbind " .. (b.value or ""), 1, 0.82, 0)
    GameTooltip:Show()
  end)
  b.x:HookScript("OnLeave", function() GameTooltip:Hide() end)
  local function paint(p)
    local a = K:Theme().accent
    b.bg:SetVertexColor(a[1], a[2], a[3], 0.10 + 0.08 * p)
    b.edge:SetColor(a[1], a[2], a[3], 0.40 + 0.45 * p)
  end
  b:SetScript("OnEnter", function(self) UI.Tween(self, 1, 0.12, paint) end)
  b:SetScript("OnLeave", function(self) UI.Tween(self, 0, 0.12, paint) end)
  UI:OnTheme(function() paint(UI.Progress(b)) end)
  function b:Set(value, icon)
    self.value = value
    self.icon:SetTexture(icon)
    self.text:SetText(UI.Escape(value))
    self:SetWidth(5 + 16 + 6 + math.ceil(self.text:GetStringWidth()) + 6 + 18 + 3)
  end
  return b
end

local function Feedback(c, text, good)
  local ed = c.ed
  local col = good and UI.OnCard({ 0.40, 0.80, 0.48 }) or K:Theme().subtle
  ed.feedback:SetText(text or "")
  ed.feedback:SetTextColor(col[1], col[2], col[3])
  UI.FadeIn(ed.feedback, 0.2)
  local token = {}
  ed.feedbackToken = token
  C_Timer.After(5, function() if ed.feedbackToken == token then ed.feedback:SetText("") end end)
end

local function BindName(c, name)
  local rec = Ref(c)
  if not rec then return end
  local ok, err = Comp:Bind(rec, name)
  if ok then Feedback(c, "Bound to " .. strtrim(name) .. ". Its tooltip now tells this story.", true)
  else Feedback(c, err) end
  return ok
end

local function BindCurrent(c, button)
  local rec = Ref(c)
  if not rec then return end
  if rec.kind == "mount" then
    local list = Comp:MountCandidates()
    if not list then return Feedback(c, "Mount up first, then bind your mount.") end
    if #list == 0 then return Feedback(c, "Couldn't tell which aura is your mount. Type its name instead.") end
    if #list == 1 or not (MenuUtil and MenuUtil.CreateContextMenu) then return BindName(c, list[1].name) end
    UI.Menu(button, function(root)
      root:CreateTitle("Which one is your mount?")
      for _, a in ipairs(list) do
        root:CreateButton(a.name, function() BindName(c, a.name) end)
      end
    end)
  else
    local pet = Comp:CurrentPetName()
    if not pet then return Feedback(c, "Summon your pet first, then bind it.") end
    BindName(c, pet)
  end
end

local function PickIcon(c, anchor)
  local rec = Ref(c)
  if not rec then return end
  local P = K.IconPicker
  if P and P.Open then
    P:Open(anchor, rec.icon, function(icon)
      local r = Ref(c)
      if r and icon then r.icon = icon; Comp:Changed() end
    end)
  else
    c.ed.iconField.edit:SetFocus()
    c.ed.iconField.edit:HighlightText()
  end
end

local function BuildEditor(c)
  local panel = UI.Panel(c)
  panel:SetPoint("TOPLEFT", LEFT_W + GAP, 0)
  panel:SetSize(ED_W, CH)
  c.panel = panel

  local ed = CreateFrame("Frame", nil, panel)
  ed:SetAllPoints()
  c.ed = ed

  -- Icon
  local ib = CreateFrame("Button", nil, ed)
  ib:SetSize(62, 62)
  ib:SetPoint("TOPLEFT", 16, -16)
  ib.ring = UI.Circle(ib, 62, "ARTWORK", 0)
  ib.ring:SetPoint("CENTER")
  ib.icon = ib:CreateTexture(nil, "ARTWORK", nil, 1)
  ib.icon:SetSize(56, 56)
  ib.icon:SetPoint("CENTER")
  ib.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
  UI.Round(ib.icon)
  local function paintIcon(p)
    local t = K:Theme()
    ib.ring:SetVertexColor(UI.Mix({ t.accent[1], t.accent[2], t.accent[3], 0.75 }, { 0.78, 0.58, 0.18, 1 }, p))
    ib.icon:SetAlpha(0.9 + 0.1 * p)
  end
  ib:SetScript("OnEnter", function(self)
    UI.Tween(self, 1, 0.12, paintIcon)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:SetText("Choose an icon", 1, 0.82, 0)
    GameTooltip:AddLine(K.IconPicker and "Click to browse icons." or "Type an icon name in the Icon field, such as Ability_Hunter_Pet_Cat.", 1, 1, 1, true)
    GameTooltip:Show()
  end)
  ib:SetScript("OnLeave", function(self) UI.Tween(self, 0, 0.15, paintIcon); GameTooltip:Hide() end)
  ib:SetScript("OnClick", function(self) PickIcon(c, self) end)
  UI:OnTheme(function() paintIcon(UI.Progress(ib)) end)
  ed.iconBtn = ib

  local function Set(key, max)
    return function(text)
      local rec = Ref(c)
      if rec then rec[key] = max and text:sub(1, max) or text; Comp:Changed() end
    end
  end
  local L = Comp.LIMITS

  ed.nameField = UI.Field(ed, "Name", 200, L.name, Set("name"))
  ed.nameField:SetPoint("TOPLEFT", 92, -14)

  local kinds = {}
  for _, k in ipairs(Comp.KIND_ORDER) do kinds[#kinds + 1] = { key = k, label = Comp.KINDS[k].label } end
  local kl = UI.Text(ed, "Kind", "Label", "subtle")
  kl:SetPoint("TOPLEFT", ED_W - 16 - 116 + 1, -14)
  ed.kind = UI.Segments(ed, kinds, 58, function(key)
    local rec = Ref(c)
    if not rec or rec.kind == key then return end
    local old = Comp.KINDS[rec.kind or "pet"]
    if not rec.icon or (old and rec.icon == old.icon) then rec.icon = Comp.KINDS[key].icon end
    rec.kind = key
    Comp:Changed()
  end)
  ed.kind:SetPoint("TOPRIGHT", -16, -28)

  ed.titleField = UI.Field(ed, "Title", 200, L.title, Set("title"))
  ed.titleField:SetPoint("TOPLEFT", 92, -58)
  ed.iconField = UI.Field(ed, "Icon", 116, 120, function(text)
    local rec = Ref(c)
    local icon = ParseIcon(text)
    if rec and icon then rec.icon = icon; ed.iconBtn.icon:SetTexture(icon); Comp:Changed() end
  end)
  ed.iconField:SetPoint("TOPRIGHT", -16, -58)

  ed.glanceField = UI.Field(ed, "At a glance  (one line, shown on the tooltip)", IN, L.glance, Set("glance"))
  ed.glanceField:SetPoint("TOPLEFT", 16, -104)

  local dl = UI.Text(ed, "Description", "Label", "subtle")
  dl:SetPoint("TOPLEFT", 17, -152)
  ed.desc = UI.TextArea(ed, IN, 116, L.desc, Set("desc"))
  ed.desc:SetPoint("TOPLEFT", 16, -166)

  -- Bindings
  local bl = UI.Text(ed, "Bound to", "Label", "subtle")
  bl:SetPoint("TOPLEFT", 17, -296)
  local bh = UI.Text(ed, "These pets' or mounts' tooltips tell this story", "Label", "subtle")
  bh:SetPoint("TOPRIGHT", -17, -296)
  bh:SetAlpha(0.8)
  ed.chipArea = CreateFrame("Frame", nil, ed)
  ed.chipArea:SetPoint("TOPLEFT", 16, -312)
  ed.chipArea:SetSize(IN, 54)
  ed.chips = {}
  ed.noChips = UI.Text(ed.chipArea, "Not bound yet. Bind your current pet or mount, or type its name below.", "Small", "subtle", IN)
  ed.noChips:SetPoint("TOPLEFT", 1, -4)
  ed.noChips:SetAlpha(0.85)

  ed.bindEdit = UI.Edit(ed, 170, 26, nil, 60)
  ed.bindEdit:SetPoint("TOPLEFT", 16, -372)
  ed.bindHint = UI.Text(ed.bindEdit, "Pet or mount name", "Small", "subtle")
  ed.bindHint:SetPoint("LEFT", 8, 0)
  ed.bindHint:SetAlpha(0.7)
  local function addTyped()
    local text = ed.bindEdit:GetText() or ""
    if BindName(c, text) then ed.bindEdit:SetText("") end
  end
  ed.bindEdit:SetScript("OnTextChanged", function(self) ed.bindHint:SetShown((self:GetText() or "") == "") end)
  ed.bindEdit:SetScript("OnEnterPressed", function(self) addTyped(); self:ClearFocus() end)
  ed.addBtn = UI.Button(ed, "Add", 56, 26)
  ed.addBtn:SetPoint("LEFT", ed.bindEdit, "RIGHT", 6, 0)
  ed.addBtn:SetScript("OnClick", addTyped)
  ed.current = UI.Button(ed, "Bind current pet", 166, 26)
  ed.current:SetPoint("TOPRIGHT", -16, -372)
  ed.current:SetScript("OnClick", function(self) BindCurrent(c, self) end)
  ed.current:HookScript("OnEnter", function(self)
    local rec = Ref(c)
    GameTooltip:SetOwner(self, "ANCHOR_TOP")
    if rec and rec.kind == "mount" then
      GameTooltip:SetText("Bind current mount", 1, 0.82, 0)
      GameTooltip:AddLine("While riding, binds the mount you're on. Others see this companion on your tooltip while you ride it.", 1, 1, 1, true)
    else
      local pet = Comp:CurrentPetName()
      GameTooltip:SetText("Bind current pet", 1, 0.82, 0)
      GameTooltip:AddLine(pet and ("Binds " .. pet .. ", your pet right now.") or "Summon your hunter or warlock pet first.", 1, 1, 1, true)
    end
    GameTooltip:Show()
  end)
  ed.current:HookScript("OnLeave", function() GameTooltip:Hide() end)

  ed.feedback = UI.Text(ed, "", "Small", "subtle", IN)
  ed.feedback:SetPoint("TOPLEFT", 17, -406)
  ed.feedback:SetWordWrap(false)

  -- Footer
  local line = UI.Divider(ed, IN)
  line:SetPoint("BOTTOMLEFT", 16, 42)
  local saved = UI.Text(ed, "Saved as you type, and shared with your profile.", "Label", "subtle", IN - 124)
  saved:SetPoint("BOTTOMLEFT", 17, 20)
  ed.delete = UI.Button(ed, "Delete", 112, 24)
  ed.delete:SetPoint("BOTTOMRIGHT", -16, 14)
  ed.delete:SetScript("OnClick", function(self)
    local rec = Ref(c)
    if not rec then return end
    if not self.armed then
      self.armed = true
      self:SetText("Really delete?")
      C_Timer.After(3, function() if self.armed then self.armed = false; self:SetText("Delete") end end)
      return
    end
    self.armed = false
    self:SetText("Delete")
    Comp:Delete(rec.id)
    c.selectedId = nil
    K.Journal:RefreshCurrent()
  end)
  ed.delete:HookScript("OnLeave", function(self)
    if self.armed then self.armed = false; self:SetText("Delete") end
  end)

  -- Empty state: no companions at all
  local empty = CreateFrame("Frame", nil, panel)
  empty:SetAllPoints()
  c.empty = empty
  empty.ring = UI.Circle(empty, 92, "ARTWORK", 0)
  empty.ring:SetPoint("CENTER", 0, 92)
  empty.icon = empty:CreateTexture(nil, "ARTWORK", nil, 1)
  empty.icon:SetSize(84, 84)
  empty.icon:SetPoint("CENTER", empty.ring)
  empty.icon:SetTexture(Comp.KINDS.pet.icon)
  empty.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
  UI.Round(empty.icon)
  UI:OnTheme(function(t) empty.ring:SetVertexColor(t.accent[1], t.accent[2], t.accent[3], 0.55) end)
  empty.heading = UI.Text(empty, "Give your companions a story", "Title", "heading")
  empty.heading:SetPoint("TOP", empty.ring, "BOTTOM", 0, -16)
  empty.text = UI.Text(empty, "A loyal wolf, a stubborn kodo, an imp with opinions. Name them, describe them, and bind "
    .. "them to your pet or mount: anyone hovering over it then meets them properly.", "Body", "subtle", 330)
  empty.text:SetPoint("TOP", empty.heading, "BOTTOM", 0, -10)
  empty.text:SetJustifyH("CENTER")
  empty.text:SetSpacing(3)
  empty.create = UI.Button(empty, "Create a companion", 170, 28)
  empty.create:SetScript("OnClick", function()
    local rec = Comp:New("pet")
    if rec then c.selectedId = rec.id; c.focusName = true; K.Journal:RefreshCurrent() end
  end)
  empty.fromPet = UI.Button(empty, "", 170, 28)
  empty.fromPet:SetScript("OnClick", function()
    local pet = Comp:CurrentPetName()
    if not pet then return end
    local rec = Comp:New("pet", pet)
    if rec then
      Comp:Bind(rec, pet)
      c.selectedId = rec.id
      K.Journal:RefreshCurrent()
    end
  end)
end

local function LayoutChips(c, rec)
  local ed = c.ed
  local binds = rec.bindings or {}
  local icon = Comp.IconOf(rec)
  local x, y = 0, 0
  for i, name in ipairs(binds) do
    local chip = ed.chips[i]
    if not chip then
      chip = NewChip(ed.chipArea, function(value)
        local r = Ref(c)
        if r and value then Comp:Unbind(r, value); Feedback(c, "Unbound " .. value .. ".") end
      end)
      ed.chips[i] = chip
    end
    chip:Set(name, icon)
    local w = chip:GetWidth()
    if x > 0 and x + w > IN then x, y = 0, y - 30 end
    chip:ClearAllPoints()
    chip:SetPoint("TOPLEFT", x, y)
    chip:Show()
    x = x + w + 6
  end
  for i = #binds + 1, #ed.chips do ed.chips[i]:Hide() end
  ed.noChips:SetShown(#binds == 0)
end

local function SyncText(field, value)
  if not field:HasFocus() then field:SetText(value or "") end
end

local function ShowEditor(c, rec)
  local ed = c.ed
  local switched = c.shownId ~= rec.id
  if switched then
    c.shownId = rec.id
    for _, f in ipairs({ ed.nameField.edit, ed.titleField.edit, ed.iconField.edit, ed.glanceField.edit, ed.desc.edit, ed.bindEdit }) do
      f:ClearFocus()
    end
    ed.bindEdit:SetText("")
    ed.feedback:SetText("")
    ed.delete.armed = false
    ed.delete:SetText("Delete")
    UI.FadeIn(ed, 0.2)
  end
  SyncText(ed.nameField.edit, rec.name)
  SyncText(ed.titleField.edit, rec.title)
  SyncText(ed.iconField.edit, IconText(rec.icon))
  SyncText(ed.glanceField.edit, rec.glance)
  SyncText(ed.desc.edit, rec.desc)
  ed.iconBtn.icon:SetTexture(Comp.IconOf(rec))
  ed.kind:Select(rec.kind or "pet")
  ed.current:SetText(rec.kind == "mount" and "Bind current mount" or "Bind current pet")
  LayoutChips(c, rec)
  if c.focusName then
    c.focusName = nil
    ed.nameField.edit:SetFocus()
  end
end

local function ShowEmpty(c)
  local e = c.empty
  local pet = Comp:CurrentPetName()
  e.create:ClearAllPoints()
  e.fromPet:SetShown(pet ~= nil)
  if pet then
    e.fromPet:SetText("Start from " .. pet)
    e.create:SetPoint("TOPRIGHT", e.text, "BOTTOM", -5, -18)
    e.fromPet:ClearAllPoints()
    e.fromPet:SetPoint("TOPLEFT", e.text, "BOTTOM", 5, -18)
  else
    e.create:SetPoint("TOP", e.text, "BOTTOM", 0, -18)
  end
end

---------------------------------------------------------------------------
-- The page
---------------------------------------------------------------------------
K:RegisterPage({
  id = "companions", trp3 = "hide", title = "Companions", heading = "Companions",
  subtitle = "Your pets and mounts, with stories of their own. Others see them on their tooltips.",
  group = "You",
  icon = { "Interface\\Icons\\Ability_Hunter_Pet_Wolf", round = true },

  build = function(c)
    BuildList(c)
    BuildEditor(c)
    local ev = CreateFrame("Frame", nil, c)
    ev:RegisterEvent("UNIT_PET")
    ev:SetScript("OnEvent", function(_, _, unit)
      if unit == "player" and K.Journal:IsShowing("companions") then K.Journal:RefreshCurrent() end
    end)
  end,

  refresh = function(c)
    local list = Comp:Sorted()
    if c.selectedId and not Comp:Get(c.selectedId) then c.selectedId = nil end
    if not c.selectedId and list[1] then c.selectedId = list[1].id end
    c.list:SetItems(list, FillRow(c))
    c.newBtn:SetEnabled(#list < Comp.LIMITS.count)
    local rec = Ref(c)
    c.ed:SetShown(rec ~= nil)
    c.empty:SetShown(rec == nil)
    if rec then
      ShowEditor(c, rec)
    else
      if c.shownId ~= false then c.shownId = false; UI.FadeIn(c.empty, 0.25) end
      ShowEmpty(c)
    end
  end,
})

K:On("COMPANIONS", function()
  if K.Journal:IsShowing("companions") then K.Journal:RefreshCurrent() end
end)
