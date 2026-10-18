-- Kinship RP: the Effects tab of the Persona page. On the left, what's on
-- you now with the time left; on the right, a library of effects (presets
-- and your own) to take on yourself or lay on your target, with a duration
-- and a note. Your own effects are designed in a pop-over editor.
--   K.Auras:BuildTab(frame, page), K.Auras:RefreshTab(frame)

local ADDON, ns = ...
local K = ns.K
local UI = K.UI
local Safe = K.Safe
local A = K.Auras

local BODY_H = 426
local LW = 300
local RW = 696 - LW - 10
local RIW = RW - 32

local function Refresh() K.Journal:RefreshCurrent() end
local Short = K.Short
local function Err(msg)
  if UIErrorsFrame and UIErrorsFrame.AddMessage then UIErrorsFrame:AddMessage(msg, 1, 0.25, 0.2) else K:Print(msg) end
end

-- A button that asks twice before doing something it can't undo.
local function Confirming(b, label, ask, fn)
  b:SetText(label)
  b:SetScript("OnClick", function(self)
    if self.armed then
      self.armed = nil
      self:SetText(label)
      fn()
    else
      self.armed = true
      self:SetText(ask)
      C_Timer.After(3, function() if self.armed then self.armed = nil; self:SetText(label) end end)
    end
  end)
  b:HookScript("OnHide", function(self) self.armed = nil; self:SetText(label) end)
end

-- A round icon inside a ring in the effect's colour.
local function Medallion(parent, size)
  local m = CreateFrame("Frame", nil, parent)
  m:SetSize(size + 4, size + 4)
  m.ring = UI.Circle(m, size + 4, "ARTWORK", 0)
  m.ring:SetPoint("CENTER")
  m.icon = m:CreateTexture(nil, "ARTWORK", nil, 1)
  m.icon:SetSize(size, size)
  m.icon:SetPoint("CENTER")
  m.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
  UI.Round(m.icon)
  function m:Set(icon, kind)
    self.icon:SetTexture(icon)
    local c = A.Color(kind)
    self.ring:SetVertexColor(c[1], c[2], c[3], 1)
  end
  return m
end

local function TargetName()
  if not UnitExists("target") then return nil end
  local isPlayer, me = UnitIsPlayer("target"), UnitIsUnit("target", "player")
  if not (Safe(isPlayer) and isPlayer) or not Safe(me) or me then return nil end
  local n = GetUnitName("target", true)
  if Safe(n) and type(n) == "string" and n ~= "" then return n end
end

local function ChooseIcon(anchor, current, onPick)
  if K.IconPicker then K.IconPicker:Open(anchor, current, onPick)
  elseif K.Items then K.Items:ChooseIcon(anchor, current, onPick) end
end

---------------------------------------------------------------------------
-- Editor for your own effects (a pop-over on the page)
---------------------------------------------------------------------------
local EW, EH = 440, 372
local EIW = EW - 32

local function BuildEditor(tab, page)
  local m = UI.Modal(page, EW, EH, function() tab.editor:Hide() end)
  tab.editor = m
  local card = m.card
  m.title = UI.Section(card, "Your effect")
  m.title:SetPoint("TOPLEFT", 21, -15)

  m.med = CreateFrame("Button", nil, card)
  m.med:SetSize(48, 48)
  m.med:SetPoint("TOPLEFT", 16, -42)
  m.med.m = Medallion(m.med, 42)
  m.med.m:SetPoint("CENTER")
  m.med:SetScript("OnClick", function(self)
    ChooseIcon(self, m.draft.icon, function(icon) m.draft.icon = icon; m:Paint() end)
  end)
  UI.Tooltip(m.med, "Icon", "Click to choose one.")
  m.name = UI.Field(card, "Name", EIW - 64, 40, function(text) m.draft.name = text end)
  m.name:SetPoint("TOPLEFT", 80, -46)

  local kl = UI.Text(card, "Kind", "Label", "subtle")
  kl:SetPoint("TOPLEFT", 17, -100)
  local kinds = {}
  for _, k in ipairs(A.KIND_ORDER) do kinds[#kinds + 1] = { key = k, label = A.KINDS[k].label, color = A.KINDS[k].color } end
  m.kind = UI.Segments(card, kinds, math.floor(EIW / 5), function(k) m.draft.kind = k; m:Paint() end)
  m.kind:SetPoint("TOPLEFT", 16, -114)
  m.kindNote = UI.Text(card, "", "Small", "subtle", EIW)
  m.kindNote:SetPoint("TOPLEFT", 17, -144)

  local dl = UI.Text(card, "What others notice", "Label", "subtle")
  dl:SetPoint("TOPLEFT", 17, -166)
  m.desc = UI.TextArea(card, EIW, 72, 300, function(text) m.draft.desc = text end)
  m.desc:SetPoint("TOPLEFT", 16, -180)

  local tl = UI.Text(card, "Usually lasts", "Label", "subtle")
  tl:SetPoint("TOPLEFT", 17, -262)
  m.dur = UI.Segments(card, A.DURATIONS, math.floor(EIW / #A.DURATIONS), function(d) m.draft.dur = d end)
  m.dur:SetPoint("TOPLEFT", 16, -276)

  m.save = UI.Button(card, "Save", 100, 26)
  m.save:SetPoint("BOTTOMRIGHT", -16, 14)
  m.save:SetScript("OnClick", function()
    local def, err = A:SaveCustom(m.draft, m.editing)
    if not def then Err(err) return end
    tab.selId = def.id
    m:Hide()
    Refresh()
  end)
  m.cancel = UI.Button(card, "Cancel", 80, 26)
  m.cancel:SetPoint("RIGHT", m.save, "LEFT", -8, 0)
  m.cancel:SetScript("OnClick", function() m:Hide() end)
  m.del = UI.Button(card, "Delete", 80, 26)
  m.del:SetPoint("BOTTOMLEFT", 16, 14)
  Confirming(m.del, "Delete", "Sure?", function()
    if m.editing then A:DeleteCustom(m.editing); tab.selId = nil end
    m:Hide()
    Refresh()
  end)

  function m:Paint()
    self.med.m:Set(self.draft.icon, self.draft.kind)
    self.kind:Select(self.draft.kind)
    local field = A.Kind(self.draft.kind).consent
    self.kindNote:SetText(field == "RI" and "Others only receive it if their Injury boundary allows."
      or field == "RO" and "Others only receive it if their Capture boundary allows." or "")
  end

  function m:Open(def)
    self.editing = def and def.custom and def.id or nil
    self.draft = {
      name = def and def.name or "", icon = def and def.icon or "Interface\\Icons\\Spell_Holy_MagicalSentry",
      kind = def and def.kind or "state", desc = def and def.desc or "", dur = def and def.dur or 3600,
    }
    self.title:SetText(self.editing and "Edit your effect" or "A new effect")
    self.title.bg:SetPoint("BOTTOMRIGHT", self.title, "BOTTOMRIGHT", 7, -4)
    self.name.edit:SetText(self.draft.name)
    self.desc.edit:SetText(self.draft.desc)
    self.dur:Select(self.draft.dur)
    self.del:SetShown(self.editing ~= nil)
    self:Paint()
    self:Show()
    self.name.edit:SetFocus()
  end
end

local function CustomMenu(owner, tab, def)
  UI.Menu(owner, function(root)
    root:CreateTitle(def.name)
    root:CreateButton("Edit...", function() tab.editor:Open(def) end)
    root:CreateButton("Make a copy...", function()
      local copy = {}
      for k, v in pairs(def) do copy[k] = v end
      copy.custom = nil
      tab.editor:Open(copy)
    end)
    if def.custom then
      root:CreateButton("|cffff6060Delete|r", function() A:DeleteCustom(def.id); Refresh() end)
    end
  end)
end

---------------------------------------------------------------------------
-- Building the tab
---------------------------------------------------------------------------
function A:BuildTab(tab, page)
  tab.kind, tab.who = "all", "me"

  -- On you now ------------------------------------------------------------
  local left = UI.Panel(tab)
  left:SetPoint("TOPLEFT")
  left:SetSize(LW, BODY_H)
  local lp = UI.Section(left, "On you now")
  lp:SetPoint("TOPLEFT", 21, -15)
  tab.clear = UI.Button(left, "End all", 70, 22)
  tab.clear:SetPoint("TOPRIGHT", -16, -10)
  Confirming(tab.clear, "End all", "Sure?", function() A:Clear() end)

  tab.active = UI.List(left, LW - 24, 312, 52,
    "Nothing on you right now. Take on an effect from the library: a wound, a blessing, a bottle too many.",
    function(row)
      row.med = Medallion(row, 30)
      row.med:SetPoint("LEFT", 6, 0)
      row.name = UI.Text(row, "", "Header", "heading", LW - 24 - 12 - 50 - 52)
      row.name:SetPoint("TOPLEFT", 50, -9)
      row.name:SetWordWrap(false)
      row.sub = UI.Text(row, "", "Small", "subtle", LW - 24 - 12 - 50 - 52)
      row.sub:SetPoint("TOPLEFT", row.name, "BOTTOMLEFT", 0, -4)
      row.sub:SetWordWrap(false)
      row.stop = UI.Button(row, "End", 42, 20)
      row.stop:SetPoint("RIGHT", -6, 0)
      row.stop:SetScript("OnClick", function(self) if self:GetParent().item then A:Remove(self:GetParent().item.key) end end)
      row.onEnter = function(self) A:ShowTooltip(self, self.item, false) end
    end, { bare = true, emptyIcon = K.Art("IconFire") })
  tab.active:SetPoint("TOPLEFT", 12, -40)

  tab.barToggle = UI.Toggle(left, "Effects bar on screen", "Icons with time left. Right-click one to end it.",
    function() return K.db.settings.auraBar ~= false end,
    function(v) K.db.settings.auraBar = v; A.Bar:Update() end, LW - 32, true)
  tab.barToggle:SetPoint("BOTTOMLEFT", 16, 16)

  -- The library ---------------------------------------------------------------
  local right = UI.Panel(tab)
  right:SetPoint("TOPLEFT", LW + 10, 0)
  right:SetSize(RW, BODY_H)
  tab.right = right
  local rp = UI.Section(right, "Lay an effect")
  rp:SetPoint("TOPLEFT", 21, -15)
  tab.new = UI.Button(right, "New effect", 100, 22)
  tab.new:SetPoint("TOPRIGHT", -16, -10)
  tab.new:SetScript("OnClick", function() tab.editor:Open(nil) end)
  UI.Tooltip(tab.new, "New effect", "Design your own: a curse with a name, a family blessing, a hangover.")

  local kinds = { { key = "all", label = "All" } }
  for _, k in ipairs(A.KIND_ORDER) do kinds[#kinds + 1] = { key = k, label = A.KINDS[k].plural, color = A.KINDS[k].color } end
  tab.kinds = UI.Segments(right, kinds, math.floor(RIW / #kinds), function(k) tab.kind = k; Refresh() end)
  tab.kinds:SetPoint("TOPLEFT", 16, -40)

  tab.lib = UI.List(right, RIW + 6, 146, 34, "Nothing of that kind yet.", function(row)
    row.med = Medallion(row, 22)
    row.med:SetPoint("LEFT", 4, 0)
    row.name = UI.Text(row, "", "Body", "heading", 200)
    row.name:SetPoint("LEFT", 36, 0)
    row.name:SetWordWrap(false)
    row.sub = UI.Text(row, "", "Small", "subtle")
    row.sub:SetPoint("RIGHT", -8, 0)
    row:SetScript("OnClick", function(self, button)
      if button == "RightButton" then CustomMenu(self, tab, self.item) return end
      tab.selId = self.item.id
      tab.dur = self.item.dur
      Refresh()
    end)
    row:SetScript("OnDoubleClick", function(self) if self.item.custom then tab.editor:Open(self.item) end end)
    row.onEnter = function(self) A:ShowTooltip(self, self.item, false) end
  end, { bare = true, emptyIcon = K.Art("IconFire") })
  tab.lib:SetPoint("TOPLEFT", 13, -70)

  local div = UI.Divider(right, RIW)
  div:SetPoint("TOPLEFT", 16, -224)

  tab.med = Medallion(right, 32)
  tab.med:SetPoint("TOPLEFT", 14, -232)
  tab.name = UI.Text(right, "", "Header", "heading", RIW - 46)
  tab.name:SetPoint("TOPLEFT", 56, -236)
  tab.name:SetWordWrap(false)
  tab.desc = UI.Text(right, "", "Small", "subtle", RIW - 46)
  tab.desc:SetPoint("TOPLEFT", tab.name, "BOTTOMLEFT", 0, -4)
  tab.desc:SetMaxLines(2)
  tab.desc:SetSpacing(2)

  local fl = UI.Text(right, "For", "Label", "subtle")
  fl:SetPoint("TOPLEFT", 17, -288)
  tab.durs = UI.Segments(right, A.DURATIONS, math.floor(RIW / #A.DURATIONS), function(d) tab.dur = d end)
  tab.durs:SetPoint("TOPLEFT", 16, -302)

  tab.note = UI.Field(right, "Note  (optional: where, how, what it looks like)", RIW, 120)
  tab.note:SetPoint("TOPLEFT", 16, -330)
  tab.status = UI.Text(right, "", "Small", "subtle", RIW)
  tab.status:SetPoint("TOPLEFT", 17, -374)
  tab.status:SetWordWrap(false)

  tab.whoSeg = UI.Segments(right, { { key = "me", label = "On me" }, { key = "them", label = "On your target" } }, 112,
    function(k) tab.who = k; Refresh() end)
  tab.whoSeg:SetPoint("BOTTOMLEFT", 16, 13)
  tab.go = UI.Button(right, "Take it on", 120, 26)
  tab.go:SetPoint("BOTTOMRIGHT", -16, 12)
  tab.go:SetScript("OnClick", function()
    local def = A:Def(tab.selId)
    if not def then Err("Choose an effect first.") return end
    local note = tab.note.edit:GetText()
    if tab.who == "them" then
      local ok, why = A:Offer(tab.them, def, tab.dur, note)
      if not ok then Err(why) return end
      tab.sentTo = tab.them
      tab.status:SetText("Offered to " .. UI.Escape(Short(tab.them)) .. ". They'll see it now.")
    else
      A:Apply(def, tab.dur, nil, note)
    end
    tab.note.edit:SetText("")
    tab.note.edit:ClearFocus()
  end)

  BuildEditor(tab, page)

  -- Count down while the tab is open
  tab.tick = 0
  tab:SetScript("OnUpdate", function(self, elapsed)
    self.tick = self.tick + elapsed
    if self.tick >= 1 then self.tick = 0; self.active:Render() end
  end)
end

---------------------------------------------------------------------------
-- Refreshing it
---------------------------------------------------------------------------
local function FillActive(row, e)
  row.med:Set(e.icon, e.kind)
  row.name:SetText(UI.Escape(e.name))
  row.name:SetTextColor(unpack(UI.OnCard(A.Color(e.kind))))
  local bits = { e.expires and (A.Left(e.expires) .. " left") or "Ongoing" }
  if e.from then bits[#bits + 1] = "from " .. UI.Escape(Short(e.from)) end
  if e.note then bits[#bits + 1] = "\"" .. UI.Escape(e.note) .. "\"" end
  row.sub:SetText(table.concat(bits, "  ·  "))
end

function A:RefreshTab(tab)
  if A.target then
    tab.them = A.target
    tab.who = "them"
    A.target = nil
  else
    tab.them = TargetName() or (tab.who == "them" and tab.them) or nil
  end
  if not tab.them then tab.who = "me" end

  -- On you now
  local mine = self:Of(nil, true)
  tab.active:SetItems(mine, FillActive)
  tab.clear:SetShown(#mine > 1)
  tab.barToggle:Refresh()

  -- Library
  tab.kinds:Select(tab.kind)
  local lib = self:Library(tab.kind)
  local def = self:Def(tab.selId)
  if not def then
    def = lib[1]
    tab.selId = def and def.id
    tab.dur = def and def.dur
  end
  tab.lib:SetItems(lib, function(row, d)
    row.med:Set(d.icon, d.kind)
    row.name:SetText(UI.Escape(d.name))
    row.name:SetTextColor(unpack(UI.OnCard(A.Color(d.kind))))
    row.sub:SetText((d.custom and "Yours  ·  " or "") .. A.DurLabel(d.dur))
    row.sel:SetShown(d.id == tab.selId)
  end)

  -- The chosen effect
  if def then
    tab.med:Set(def.icon, def.kind)
    tab.name:SetText(UI.Escape(def.name))
    tab.name:SetTextColor(unpack(UI.OnCard(A.Color(def.kind))))
    tab.desc:SetText(def.desc ~= "" and UI.Escape(def.desc) or (A.Kind(def.kind).label .. "."))
  end
  tab.durs:Select(tab.dur or (def and def.dur) or 0)

  -- Whom it's for
  local btn = tab.whoSeg.buttons[2]
  btn:SetEnabled(tab.them ~= nil)
  btn.text:SetText(tab.them and ("On " .. Short(tab.them)) or "No target")
  tab.whoSeg:Select(tab.who)
  local status, canGo = "", def ~= nil
  if tab.who == "them" and def then
    local ok, why = self:CanOffer(tab.them, def.kind)
    canGo = ok
    status = why or "They'll be asked unless they trust you."
    if tab.sentTo == tab.them and tab.status:GetText() ~= "" and not why then status = tab.status:GetText() end
    tab.go:SetText("Offer it")
  else
    tab.go:SetText("Take it on")
    if def and A.Kind(def.kind).consent and self:ConsentOf(nil, def.kind, true) == "2" then
      status = "Your own boundaries say no to " .. A.Kind(def.kind).plural:lower() .. ", but it's your choice."
    end
  end
  local ok2 = status:find("^Their") or status:find("^You've")
  tab.status:SetText(status)
  tab.status:SetTextColor(unpack(ok2 and UI.OnCard({ 0.90, 0.36, 0.30 }) or K:Theme().subtle))
  tab.go:SetEnabled(canGo)
end

K:On("AURAS", function()
  if K.Journal:IsShowing("persona") then Refresh() end
end)
