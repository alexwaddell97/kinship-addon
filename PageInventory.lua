-- Kinship RP: Inventory page. Four tabs:
--   Bags       - the roleplay items you carry: drag to move, right-click to
--                use, give them away or leave them in a stash
--   Workshop   - design items of your own and make as many as you like
--   Documents  - books, notices and contracts (Documents.lua's writing desk)
--   Database   - Total RP 3: Extended objects: browse, import, export (ext/Database.lua)
-- Each tab follows its Extended switch (inventory, documents; the Database
-- only the master switch) and is built the first time it's shown.
-- Stash searching and dropping open as pop-overs from Stashes.lua; giving
-- opens Trade.lua's give window.

local ADDON, ns = ...
local K = ns.K
local UI = K.UI
local I = K.Items

local CW, CH, TOP = 696, 466, 40
local BODY_H = CH - TOP
local CELL, GAP, COLS = 52, 8, 6
local GRID_W = 32 + COLS * CELL + (COLS - 1) * GAP     -- 384
local DETAIL_W = CW - GRID_W - 10                      -- 302
local DIW = DETAIL_W - 32
local LIST_W = 230
local ED_W = CW - LIST_W - 10                          -- 456
local IW = ED_W - 32
local MAKE_MAX = 99
local NEW_ICON = "Interface\\Icons\\INV_Misc_Bag_08"
local BOOK_ICON = "Interface\\Icons\\INV_Misc_Book_09"
local GOLD = { 1, 0.82, 0 }

local function Refresh() K.Journal:RefreshCurrent() end

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

-- Faint medallion, a friendly sentence and an optional button, for empty states.
local function EmptyState(parent, icon, text, w, button)
  local f = CreateFrame("Frame", nil, parent)
  f:SetAllPoints()
  f.art = f:CreateTexture(nil, "ARTWORK")
  f.art:SetTexture(K.Art(icon))
  f.art:SetSize(64, 64)
  f.art:SetPoint("CENTER", 0, 44)
  f.art:SetAlpha(0.8)
  f.text = UI.Text(f, text, "Read", "subtle", w)
  f.text:SetPoint("TOP", f.art, "BOTTOM", 0, -12)
  f.text:SetJustifyH("CENTER")
  f.text:SetSpacing(3)
  if button then
    f.button = UI.Button(f, button, 150, 26)
    f.button:SetPoint("TOP", f.text, "BOTTOM", 0, -16)
  end
  return f
end

local function Hex(c) return UI.CardHex(c) end

---------------------------------------------------------------------------
-- Bags
---------------------------------------------------------------------------
local ghost
local function Ghost()
  if ghost then return ghost end
  ghost = CreateFrame("Frame", nil, UIParent)
  ghost:SetSize(40, 40)
  ghost:SetFrameStrata("TOOLTIP")
  ghost.icon = ghost:CreateTexture(nil, "ARTWORK")
  ghost.icon:SetAllPoints()
  ghost.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
  ghost.icon:SetAlpha(0.85)
  UI.Round(ghost.icon)
  ghost:SetScript("OnUpdate", function(self)
    local x, y = GetCursorPosition()
    local s = UIParent:GetEffectiveScale()
    self:ClearAllPoints()
    self:SetPoint("CENTER", UIParent, "BOTTOMLEFT", x / s, y / s)
  end)
  ghost:Hide()
  return ghost
end

local function BuildBags(tab, c)
  -- The bag grid --------------------------------------------------------------
  local grid = UI.Panel(tab)
  grid:SetPoint("TOPLEFT")
  grid:SetSize(GRID_W, BODY_H)
  local pill = UI.Section(grid, "Your bags")
  pill:SetPoint("TOPLEFT", 21, -15)
  tab.free = UI.Chip(grid)
  tab.free:SetPoint("TOPRIGHT", -16, -12)

  tab.cells = {}
  for i = 1, I.SLOTS do
    local s = I.NewSlot(grid, CELL)
    s:SetPoint("TOPLEFT", 16 + ((i - 1) % COLS) * (CELL + GAP), -42 - math.floor((i - 1) / COLS) * (CELL + GAP))
    s.index = i
    s.tooltipAnchor = "ANCHOR_RIGHT"
    s:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    s:RegisterForDrag("LeftButton")
    s:SetScript("OnClick", function(self, button)
      local slot = I:Slot(self.index)
      if button == "RightButton" then
        if slot then tab.sel = self.index; I:Use(self.index) end
      elseif IsShiftKeyDown() and slot and slot.count > 1 then
        local to = I:Split(self.index, math.floor(slot.count / 2))
        if to then tab.sel = to; tab.cells[to]:Pop() end
      else
        tab.sel = slot and self.index or nil
      end
      Refresh()
    end)
    s:SetScript("OnDragStart", function(self)
      local slot = I:Slot(self.index)
      if not slot then return end
      tab.dragFrom = self.index
      local def = I:Get(slot.def)
      local g = Ghost()
      g.icon:SetTexture(def and I.IconTexture(def.icon) or I.DEFAULT_ICON)
      g:Show()
      self:SetAlpha(0.4)
      GameTooltip:Hide()
    end)
    s:SetScript("OnDragStop", function(self)
      self:SetAlpha(1)
      Ghost():Hide()
      local from = tab.dragFrom
      tab.dragFrom = nil
      if not from then return end
      for j, cell in ipairs(tab.cells) do
        if j ~= from and cell:IsMouseOver() then
          if I:Move(from, j) then
            if tab.sel == from then tab.sel = j elseif tab.sel == j then tab.sel = from end
            if SOUNDKIT and SOUNDKIT.IG_ABILITY_ICON_DROP then PlaySound(SOUNDKIT.IG_ABILITY_ICON_DROP) end
            Refresh()
            cell:Pop()
          end
          return
        end
      end
      -- Let go over a worn slot (the character screen's, say): put it on
      if K.Worn and K.Worn:DropFromBag(from) then Refresh() end
    end)
    tab.cells[i] = s
  end
  if K.Worn then K.Worn:BagCells(tab.cells) end

  local hint = UI.Text(grid, "Drag to move, or onto a worn slot to wear it. Right-click to use. Shift-click to split a stack.", "Small", "subtle", GRID_W - 34)
  hint:SetPoint("TOPLEFT", 17, -348)
  hint:SetSpacing(2)

  local bw = math.floor((GRID_W - 32 - 8) / 2)
  tab.search = UI.Button(grid, "Search the area", bw, 26)
  tab.search:SetPoint("BOTTOMLEFT", 16, 14)
  tab.search:SetScript("OnClick", function() if K.Stashes then K.Stashes:OpenPanel(c, "near") end end)
  UI.Tooltip(tab.search, "Search the area", "Look for stashes other players have left near where you stand.")
  tab.stashes = UI.Button(grid, "Your stashes", bw, 26)
  tab.stashes:SetPoint("LEFT", tab.search, "RIGHT", 8, 0)
  tab.stashes:SetScript("OnClick", function() if K.Stashes then K.Stashes:OpenPanel(c, "mine") end end)
  UI.Tooltip(tab.stashes, "Your stashes", "Everything you've left out in the world, and where.")

  -- The chosen item ---------------------------------------------------------
  local card = UI.Panel(tab)
  card:SetPoint("TOPLEFT", GRID_W + 10, 0)
  card:SetSize(DETAIL_W, BODY_H)
  tab.card = card

  local d = CreateFrame("Frame", nil, card)
  d:SetAllPoints()
  tab.detail = d
  local dp = UI.Section(d, "Selected item")
  dp:SetPoint("TOPLEFT", 21, -15)
  d.slot = I.NewSlot(d, CELL)
  d.slot:SetPoint("TOPLEFT", 16, -42)
  d.slot:SetScript("OnClick", function() if tab.sel then I:Use(tab.sel) end end)
  d.name = UI.Text(d, "", "Header", "heading", DIW - 64)
  d.name:SetPoint("TOPLEFT", d.slot, "TOPRIGHT", 12, -4)
  d.name:SetMaxLines(2)
  d.kind = UI.Text(d, "", "Small", "subtle", DIW - 64)
  d.kind:SetPoint("TOPLEFT", d.name, "BOTTOMLEFT", 0, -4)
  d.kind:SetWordWrap(false)
  d.body = UI.ReadArea(d, DIW + 6, 206, "Read", "text")
  d.body:SetPoint("TOPLEFT", 16, -108)

  local w3 = math.floor((DIW - 12) / 3)
  d.use = UI.Button(d, "Use", w3, 26)
  d.use:SetPoint("BOTTOMLEFT", 16, 46)
  d.use:SetScript("OnClick", function() if tab.sel then I:Use(tab.sel) end end)
  d.give = UI.Button(d, "Give", w3, 26)
  d.give:SetPoint("LEFT", d.use, "RIGHT", 6, 0)
  d.give:SetScript("OnClick", function()
    if not (tab.sel and K.Trade) then return end
    local to
    if UnitExists("target") and UnitIsPlayer("target") and not UnitIsUnit("target", "player") then
      local n = GetUnitName("target", true)
      if K.Safe(n) then to = n end
    end
    K.Trade:OpenGive(to, tab.sel)
  end)
  UI.Tooltip(d.give, "Give", "Offer it to another Kinship player. It leaves your bags once they accept.")
  d.stash = UI.Button(d, "Stash it", w3, 26)
  d.stash:SetPoint("LEFT", d.give, "RIGHT", 6, 0)
  d.stash:SetScript("OnClick", function() if tab.sel and K.Stashes then K.Stashes:OpenDrop(c, tab.sel) end end)
  UI.Tooltip(d.stash, "Stash it", "Leave it here in the world, in plain sight or hidden, for others to find.")

  d.wear = UI.Button(d, "Wear", DIW, 24)
  d.wear:SetPoint("BOTTOMLEFT", 16, 78)
  d.wear:SetScript("OnClick", function()
    if tab.sel and K.Worn and K.Worn:Wear(tab.sel) then tab.sel = I:Slot(tab.sel) and tab.sel or nil; Refresh() end
  end)
  UI.Tooltip(d.wear, "Wear it", "Put it on. It shows around your character on your profile, and goes back in your bags when you take it off.")

  d.split = UI.Button(d, "Split", w3, 26)
  d.split:SetPoint("BOTTOMLEFT", 16, 14)
  d.split:SetScript("OnClick", function()
    local slot = tab.sel and I:Slot(tab.sel)
    if not slot or slot.count < 2 then return end
    local to = I:Split(tab.sel, math.floor(slot.count / 2))
    if to then tab.sel = to; Refresh(); tab.cells[to]:Pop() end
  end)
  UI.Tooltip(d.split, "Split the stack", "Moves half of it into an empty slot.")
  d.edit = UI.Button(d, "Edit design", w3, 26)
  d.edit:SetPoint("LEFT", d.split, "RIGHT", 6, 0)
  d.edit:SetScript("OnClick", function()
    local slot = tab.sel and I:Slot(tab.sel)
    if not slot or not I:IsMine(slot.def) then return end
    c.tab = 2
    c.frames[2].selected = slot.def
    Refresh()
  end)
  d.destroy = UI.Button(d, "Destroy", w3, 26)
  d.destroy:SetPoint("LEFT", d.edit, "RIGHT", 6, 0)
  Confirming(d.destroy, "Destroy", "Sure?", function()
    if tab.sel then I:Destroy(tab.sel); tab.sel = nil end
  end)
  UI.Tooltip(d.destroy, "Destroy", "Throw away the whole stack. Your design stays in the Workshop.")

  tab.none = EmptyState(card, "IconNote", "", DIW - 20, "Open the Workshop")
  tab.none.button:SetScript("OnClick", function() c.tab = 2; Refresh() end)
end

local function DetailText(def, slot)
  local out = {}
  if def.description ~= "" then out[#out + 1] = UI.Clean(def.description) end
  if def.useText ~= "" then
    out[#out + 1] = ("|cff%sUse:|r %s%s"):format(Hex({ 0.12, 1, 0 }), UI.Escape(def.useText), def.consume and " (used up)" or "")
  end
  if def.documentId then
    local doc = K.Documents and K.Documents:Get(def.documentId)
    out[#out + 1] = ("|cff%s%s|r"):format(Hex({ 0.55, 0.80, 1 }),
      doc and ("Read: " .. UI.Escape(K.Documents.Title(doc))) or "Its writing never reached you.")
  end
  if def.flavor ~= "" then out[#out + 1] = ("|cff%s\"%s\"|r"):format(Hex(GOLD), UI.Clean(def.flavor)) end
  local held = I:Reserved(def.id)
  if held > 0 then out[#out + 1] = ("|cff%s%d promised in a trade.|r"):format(UI.Hex(K:Theme().subtle), held) end
  if def.creator ~= "" then out[#out + 1] = ("|cff%sMade by %s|r"):format(UI.Hex(K:Theme().subtle), UI.Escape(I.Short(def.creator))) end
  if #out == 0 then out[1] = ("|cff%sNothing more to say about it.|r"):format(UI.Hex(K:Theme().subtle)) end
  return table.concat(out, "\n\n")
end

local function RefreshBags(tab)
  local bag = I:Bag()
  local used = 0
  for i, cell in ipairs(tab.cells) do
    local s = bag[i]
    if s then
      used = used + 1
      local def = I:Get(s.def)
      cell:SetItem(def, s.count, true)
      cell:SetLocked(I:Available(s.def) < 1)
    else
      cell:SetItem(nil)
      cell:SetLocked(false)
    end
    cell:SetSelected(tab.sel == i and s ~= nil)
  end
  local free = I.SLOTS - used
  tab.free:Set(free == 0 and "Bags full" or (free == 1 and "1 slot free" or (free .. " slots free")),
    free == 0 and { 0.80, 0.25, 0.20 } or nil)
  tab.stashes:SetEnabled(K.Stashes ~= nil)
  tab.search:SetEnabled(K.Stashes ~= nil)

  local s = tab.sel and bag[tab.sel]
  if not s then tab.sel = nil end
  local d = tab.detail
  d:SetShown(s ~= nil)
  tab.none:SetShown(s == nil)
  if not s then
    tab.none.text:SetText(used > 0 and "Choose something from your bags to look at it closely."
      or "Your bags are empty. Design an item in the Workshop, or accept one someone offers you.")
    tab.none.button:SetShown(used == 0)
    return
  end
  if tab.shown ~= tab.sel then
    tab.shown = tab.sel
    UI.FadeIn(d, 0.2)
  end
  local def = I:Get(s.def)
  d.slot:SetItem(def, s.count, true)
  if def then
    d.name:SetText(UI.Escape(def.name))
    d.name:SetTextColor(unpack(I.QualityColor(def.quality, true)))
    local kind = I.Quality(def.quality).label .. " item"
    if def.stack > 1 then kind = kind .. ("  ·  %d of %d"):format(s.count, def.stack) end
    d.kind:SetText(kind)
    d.body:SetText(DetailText(def, s))
  else
    d.name:SetText("Unknown item")
    d.name:SetTextColor(unpack(K:Theme().subtle))
    d.kind:SetText(s.count > 1 and (s.count .. " of them") or "")
    d.body:SetText("Its description never reached you.")
  end
  local avail = def and I:Available(def.id) or 0
  d.use:SetText(def and def.useText == "" and def.documentId and "Read" or "Use")
  d.use:SetEnabled(def ~= nil and (def.useText ~= "" or def.documentId ~= nil))
  d.give:SetEnabled(def ~= nil and avail >= 1 and K.Trade ~= nil)
  d.stash:SetEnabled(def ~= nil and avail >= 1 and K.Stashes ~= nil)
  d.split:SetEnabled(s.count > 1)
  d.edit:SetEnabled(def ~= nil and I:IsMine(def.id))
  local wearable = def ~= nil and def.wear ~= nil and K.Worn ~= nil
  d.wear:SetShown(wearable)
  if wearable then
    local on = K.Worn:In(def.wear)
    d.wear:SetText(on and ("Wear instead of " .. UI.Escape(on.name)) or ("Wear (" .. I.WEAR_LABEL[def.wear]:lower() .. ")"))
    d.wear:SetEnabled(avail >= 1)
  end
end

---------------------------------------------------------------------------
-- Workshop
---------------------------------------------------------------------------
-- Save one change to the selected design (every field travels each time).
local function SaveField(tab, key, value)
  local def = tab.selected and K.db.itemDefs[tab.selected]
  if not def then return end
  local fields = {}
  for k, v in pairs(def) do fields[k] = v end
  fields[key] = value
  local saved = I:SaveDesign(fields, def.id)
  return saved
end

local function NewDesign(tab, fields)
  local def = I:SaveDesign(fields)
  if not def then return end
  tab.selected = def.id
  tab.make = 1
  Refresh()
  return def
end

local function DocMenu(owner, tab)
  UI.Menu(owner, function(root)
    root:CreateTitle("Writing it carries")
    local def = tab.selected and K.db.itemDefs[tab.selected]
    root:CreateRadio("None", function() return def and def.documentId == nil end, function() SaveField(tab, "documentId", nil) end)
    local D = K.Documents
    if D then
      for _, doc in ipairs(D:List()) do
        if D:IsMine(doc.id) then
          root:CreateRadio(UI.Escape(D.Title(doc)), function() return def and def.documentId == doc.id end,
            function() SaveField(tab, "documentId", doc.id) end)
        end
      end
    end
    root:CreateDivider()
    root:CreateButton("Write a new document...", function()
      local c = tab.page
      if not D then return end
      local doc = D:New()
      SaveField(tab, "documentId", doc.id)
      c.tab = 3
      c.frames[3].selected, c.frames[3].page = doc.id, 1
      Refresh()
    end)
  end)
end

local function BuildWorkshop(tab, c)
  tab.page = c
  tab.make = 1

  local new = UI.Button(tab, "New design", LIST_W, 26)
  new:SetPoint("TOPLEFT", 0, 0)
  new:SetScript("OnClick", function()
    if NewDesign(tab, { name = "New item", icon = NEW_ICON, quality = 1, stack = 1 }) then
      tab.ed.name.edit:SetFocus()
      tab.ed.name.edit:HighlightText()
    end
  end)

  tab.list = UI.List(tab, LIST_W, BODY_H - 34, 50,
    "No designs yet. Make a keepsake, a potion, a writ or a trinket, then carry it, give it or leave it somewhere.",
    function(row)
      row.icon = row:CreateTexture(nil, "ARTWORK")
      row.icon:SetSize(34, 34)
      row.icon:SetPoint("LEFT", 10, 0)
      row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
      UI.Round(row.icon)
      row.name = UI.Text(row, "", "Header", "heading", LIST_W - 74)
      row.name:SetPoint("TOPLEFT", 54, -9)
      row.name:SetWordWrap(false)
      row.sub = UI.Text(row, "", "Small", "subtle", LIST_W - 74)
      row.sub:SetPoint("TOPLEFT", row.name, "BOTTOMLEFT", 0, -4)
      row.sub:SetWordWrap(false)
      row:SetScript("OnClick", function(self)
        tab.selected = self.item.id
        tab.make = 1
        Refresh()
      end)
      row.onEnter = function(self) I:ShowTooltip(self, self.item) end
    end, { emptyIcon = K.Art("IconNote") })
  tab.list:SetPoint("TOPLEFT", 0, -34)

  local card = UI.Panel(tab)
  card:SetPoint("TOPLEFT", LIST_W + 10, 0)
  card:SetSize(ED_W, BODY_H)
  tab.card = card

  local ed = CreateFrame("Frame", nil, card)
  ed:SetAllPoints()
  tab.ed = ed
  local pill = UI.Section(ed, "Item design")
  pill:SetPoint("TOPLEFT", 21, -15)
  ed.del = UI.Button(ed, "Delete", 70, 22)
  ed.del:SetPoint("TOPRIGHT", -16, -10)
  Confirming(ed.del, "Delete", "Sure?", function()
    if tab.selected then I:DeleteDesign(tab.selected); tab.selected = nil; Refresh() end
  end)
  UI.Tooltip(ed.del, "Delete design", "Copies already made, by you or anyone you gave them to, are kept.")

  ed.icon = I.NewSlot(ed, CELL)
  ed.icon:SetPoint("TOPLEFT", 16, -42)
  ed.icon:SetScript("OnClick", function(self)
    local def = tab.selected and K.db.itemDefs[tab.selected]
    if not def then return end
    I:ChooseIcon(self, def.icon, function(icon) SaveField(tab, "icon", icon) end)
  end)
  ed.icon:HookScript("OnEnter", function(self)
    GameTooltip:AddLine("Click to choose its icon.", 0.55, 0.80, 1)
    GameTooltip:Show()
  end)

  ed.name = UI.Field(ed, "Name", IW - 64, I.MAX.name, function(text)
    if strtrim(text) ~= "" then SaveField(tab, "name", text) end
  end)
  ed.name:SetPoint("TOPLEFT", 80, -42)
  ed.by = UI.Text(ed, "", "Small", "subtle", IW - 64)
  ed.by:SetPoint("TOPLEFT", 81, -86)
  ed.by:SetWordWrap(false)

  local ql = UI.Text(ed, "Quality", "Label", "subtle")
  ql:SetPoint("TOPLEFT", 17, -104)
  local qitems = {}
  for q = 0, 5 do
    local Q = I.QUALITY[q]
    qitems[#qitems + 1] = { key = q, label = Q.label, color = q ~= 1 and (Q.ink or Q.color) or nil }
  end
  ed.quality = UI.Segments(ed, qitems, math.floor(IW / 6), function(q) SaveField(tab, "quality", q) end)
  ed.quality:SetPoint("TOPLEFT", 16, -118)

  local dl = UI.Text(ed, "Description", "Label", "subtle")
  dl:SetPoint("TOPLEFT", 17, -152)
  ed.desc = UI.TextArea(ed, IW, 70, I.MAX.description, function(text) SaveField(tab, "description", text) end)
  ed.desc:SetPoint("TOPLEFT", 16, -166)

  ed.flavor = UI.Field(ed, "Flavour text  (shown in gold, in quotes)", IW, I.MAX.flavor,
    function(text) SaveField(tab, "flavor", text) end)
  ed.flavor:SetPoint("TOPLEFT", 16, -244)

  ed.use = UI.Field(ed, "When used, you emote  (e.g. \"uncorks a vial and drinks.\")", IW - 150, I.MAX.useText,
    function(text) SaveField(tab, "useText", text) end)
  ed.use:SetPoint("TOPLEFT", 16, -290)
  ed.consume = UI.Toggle(ed, "Used up", nil,
    function() local def = tab.selected and K.db.itemDefs[tab.selected]; return def and def.consume or false end,
    function(v) SaveField(tab, "consume", v or nil) end, 130, true)
  ed.consume:SetPoint("TOPLEFT", IW - 114, -306)
  UI.Tooltip(ed.consume, "Used up", "Each use takes one from the stack. Only matters when it has an emote.")

  ed.stack = UI.Field(ed, "Stacks to", 90, 2, function(text)
    local n = tonumber(text)
    if n and n >= 1 then SaveField(tab, "stack", math.min(I.MAX_STACK, math.floor(n))) end
  end)
  ed.stack:SetPoint("TOPLEFT", 16, -336)
  ed.stack.edit:SetNumeric(true)
  local wo = UI.Text(ed, "Worn on", "Label", "subtle")
  wo:SetPoint("TOPLEFT", 117, -336)
  ed.wear = UI.Button(ed, "", 120, 23)
  ed.wear:SetPoint("TOPLEFT", 116, -350)
  ed.wear:SetScript("OnClick", function(self)
    UI.Menu(self, function(root)
      root:CreateTitle("Worn on")
      local def = tab.selected and K.db.itemDefs[tab.selected]
      root:CreateRadio("Not worn", function() return def and def.wear == nil end, function() SaveField(tab, "wear", nil) end)
      local side
      for _, w in ipairs(I.WEAR) do
        if w.side ~= side then root:CreateDivider(); side = w.side end
        root:CreateRadio(w.label, function() return def and def.wear == w.key end, function() SaveField(tab, "wear", w.key) end)
      end
    end)
  end)
  UI.Tooltip(ed.wear, "Worn on", "Make it something your character wears: a hat, a cloak, a ring, a blade at the hip. "
    .. "Worn items show around your character on your profile, for other Kinship users to see.")
  local wl = UI.Text(ed, "Writing it carries", "Label", "subtle")
  wl:SetPoint("TOPLEFT", 247, -336)
  ed.doc = UI.Button(ed, "", IW - 230, 23)
  ed.doc:SetPoint("TOPLEFT", 246, -350)
  ed.doc:SetScript("OnClick", function(self) DocMenu(self, tab) end)
  UI.Tooltip(ed.doc, "Writing", "Attach one of your documents. Whoever holds the item can read it, and it travels with the item.")

  ed.have = UI.Text(ed, "", "Small", "subtle", 180)
  ed.have:SetPoint("BOTTOMLEFT", 17, 20)
  ed.go = UI.Button(ed, "Put in bags", 110, 26)
  ed.go:SetPoint("BOTTOMRIGHT", -16, 12)
  ed.go:SetScript("OnClick", function()
    local def = tab.selected and K.db.itemDefs[tab.selected]
    if not def then return end
    local n = tab.make or 1
    local left = I:Add(def.id, n)
    local made = n - (left or 0)
    if made <= 0 then I.Error("There's no room in your bags.") return end
    if left and left > 0 then I.Error(("Only room for %d."):format(made)) end
    if SOUNDKIT and SOUNDKIT.IG_BACKPACK_OPEN then PlaySound(SOUNDKIT.IG_BACKPACK_OPEN) end
    UI.Toast({ icon = I.IconTexture(def.icon), iconCoords = { 0.08, 0.92, 0.08, 0.92 },
      title = I:Label(def, made), text = "Into your bags.", color = I.Quality(def.quality).color, duration = 3 })
  end)
  ed.plus = UI.Button(ed, "+", 24, 24)
  ed.plus:SetPoint("RIGHT", ed.go, "LEFT", -10, 0)
  ed.count = UI.Text(ed, "1", "Header", "heading")
  ed.count:SetPoint("RIGHT", ed.plus, "LEFT", -10, 0)
  ed.minus = UI.Button(ed, "-", 24, 24)
  ed.minus:SetPoint("RIGHT", ed.plus, "LEFT", -40, 0)
  local function step(dir)
    tab.make = IsShiftKeyDown() and (dir > 0 and math.min(MAKE_MAX, (tab.make or 1) + 10) or math.max(1, (tab.make or 1) - 10))
      or math.max(1, math.min(MAKE_MAX, (tab.make or 1) + dir))
    Refresh()
  end
  ed.plus:SetScript("OnClick", function() step(1) end)
  ed.minus:SetScript("OnClick", function() step(-1) end)
  UI.Tooltip(ed.plus, "More", "Shift-click for ten more.")
  local ml = UI.Text(ed, "Make", "Label", "subtle")
  ml:SetPoint("RIGHT", ed.minus, "LEFT", -10, 0)

  tab.blank = EmptyState(card, "IconNote",
    "Design the things your character carries: keepsakes, potions, writs, trinkets. Make as many as you like, "
    .. "then give them away or leave them somewhere to be found.", IW - 60, "Design an item")
  tab.blank.button:SetScript("OnClick", function() new:Click() end)
end

local function RefreshWorkshop(tab)
  local designs = I:Designs()
  tab.list:SetItems(designs, function(row, def)
    row.icon:SetTexture(I.IconTexture(def.icon))
    row.name:SetText(UI.Escape(def.name))
    row.name:SetTextColor(unpack(I.QualityColor(def.quality, true)))
    local n = I:CountOf(def.id)
    local sub = I.Quality(def.quality).label
    if def.documentId then sub = sub .. "  ·  writing" end
    if def.wear and I.WEAR_LABEL[def.wear] then sub = sub .. "  ·  " .. I.WEAR_LABEL[def.wear]:lower() end
    if n > 0 then sub = sub .. ("  ·  %d carried"):format(n) end
    row.sub:SetText(sub)
    row.sel:SetShown(def.id == tab.selected)
  end)

  local def = tab.selected and K.db.itemDefs[tab.selected]
  if not def then tab.selected = nil end
  tab.ed:SetShown(def ~= nil)
  tab.blank:SetShown(def == nil)
  if not def then return end
  local ed = tab.ed
  if tab.shown ~= def.id then
    tab.shown = def.id
    UI.FadeIn(tab.card, 0.2)
    for _, f in ipairs({ ed.name, ed.flavor, ed.use, ed.stack, ed.desc }) do f.edit:ClearFocus() end
  end
  ed.icon:SetItem(def, nil)
  if not ed.name.edit:HasFocus() then ed.name.edit:SetText(def.name); ed.name.edit:SetCursorPosition(0) end
  if not ed.flavor.edit:HasFocus() then ed.flavor.edit:SetText(def.flavor or ""); ed.flavor.edit:SetCursorPosition(0) end
  if not ed.use.edit:HasFocus() then ed.use.edit:SetText(def.useText or ""); ed.use.edit:SetCursorPosition(0) end
  if not ed.stack.edit:HasFocus() then ed.stack.edit:SetText(tostring(def.stack or 1)) end
  if not ed.desc.edit:HasFocus() then ed.desc.edit:SetText(def.description or ""); ed.desc.edit:SetCursorPosition(0) end
  ed.quality:Select(def.quality)
  ed.consume:Refresh()
  local edited = def.edited and ("  ·  edited " .. UI.Ago(def.edited)) or ""
  ed.by:SetText("Your design" .. edited)

  local doc = def.documentId and K.Documents and K.Documents:Get(def.documentId)
  ed.doc:SetText(doc and UI.Escape(K.Documents.Title(doc)) or (def.documentId and "A missing document" or "None"))
  ed.wear:SetText(def.wear and I.WEAR_LABEL[def.wear] or "Not worn")
  ed.doc:SetEnabled(K.Documents ~= nil)

  tab.make = math.max(1, math.min(MAKE_MAX, tab.make or 1))
  ed.count:SetText(tab.make)
  ed.minus:SetEnabled(tab.make > 1)
  ed.plus:SetEnabled(tab.make < MAKE_MAX)
  local n, free = I:CountOf(def.id), I:FreeSlots()
  ed.have:SetText((n > 0 and ("You carry %d."):format(n) or "You carry none.") .. (free == 0 and "  Bags full." or ""))
end

---------------------------------------------------------------------------
-- Worn: your character with the roleplay slots around them, laid out as the
-- game's own character screen lays out its gear (eight down each side, the
-- hands along the bottom), and the things in your bags you could wear.
---------------------------------------------------------------------------

StaticPopupDialogs["KINSHIPRP_OUTFIT_DELETE"] = {
  text = "Delete the outfit \"%s\"? Its items stay where they are.",
  button1 = DELETE or "Delete", button2 = CANCEL or "Cancel",
  OnAccept = function(_, o) K.Worn:DeleteOutfit(o) end,
  timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
}

-- Saving (o = nil) or renaming (o) an outfit: a name, whether it goes on
-- when you switch to the profile you're using, and a warning before a save
-- replaces an outfit of the same name. Built over the Worn tab on first use.
local wornTab, namer
local ND_W, ND_H = 380, 252
local WARN = { 1, 0.72, 0.32 }

local function BuildNamer()
  local W = K.Worn
  local parent = wornTab:GetParent()
  local m = UI.Modal(parent, ND_W, ND_H, function() namer:Hide() end)
  local card = m.card
  m.title = UI.Text(card, "", "Title", "heading", ND_W - 60)
  m.title:SetPoint("TOPLEFT", 20, -20)
  m.sub = UI.Text(card, "", "Small", "subtle", ND_W - 40)
  m.sub:SetPoint("TOPLEFT", m.title, "BOTTOMLEFT", 0, -5)
  m.sub:SetSpacing(2)

  local function Check() m:Check() end
  m.field = UI.Field(card, "Name", ND_W - 40, W.OUTFIT_NAME, Check)
  m.field:SetPoint("TOPLEFT", 20, -70)
  m.warn = UI.Text(card, "", "Small", "fixed", ND_W - 40)
  m.warn:SetPoint("TOPLEFT", m.field, "BOTTOMLEFT", 1, -4)
  m.warn:SetTextColor(WARN[1], WARN[2], WARN[3])
  m.warn:SetSpacing(2)

  m.tie = UI.Toggle(card, "", nil, function() return m.tied end, function(v) m.tied = v end, ND_W - 40, true)
  m.tie:SetPoint("TOPLEFT", 20, -150)

  m.save = UI.Button(card, SAVE or "Save", 110, 26)
  m.save:SetPoint("BOTTOMRIGHT", -20, 16)
  local cancel = UI.Button(card, CANCEL or "Cancel", 90, 26)
  cancel:SetPoint("RIGHT", m.save, "LEFT", -8, 0)
  cancel:SetScript("OnClick", function() m:Hide() end)

  -- The name as typed: does it clash, and what would saving do?
  function m:Check()
    local name = strtrim(self.field.edit:GetText() or "")
    local other = name ~= "" and W:FindOutfit(name) or nil
    if other == self.outfit then other = nil end
    self.replacing = nil
    if name == "" then
      self.warn:SetText("")
      self.save:SetEnabled(false)
    elseif other and self.outfit then
      self.warn:SetText(("You already have an outfit called %s. Choose another name."):format(UI.Escape(other.name)))
      self.save:SetEnabled(false)
    elseif other then
      self.replacing = other
      self.warn:SetText(("You already have an outfit called %s. Saving replaces it with what you have on now."):format(UI.Escape(other.name)))
      self.save:SetEnabled(true)
    else
      self.warn:SetText("")
      self.save:SetEnabled(true)
    end
    self.save:SetText(self.replacing and "Replace" or (SAVE or "Save"))
    if self.save.Paint then self.save:Paint() end
  end

  function m:Commit()
    if not self.save:IsEnabled() then return end
    local name = self.field.edit:GetText()
    local o, err
    if self.outfit then
      local ok
      ok, err = W:RenameOutfit(self.outfit, name)
      o = ok and self.outfit or nil
    else
      o, err = W:SaveOutfit(name)
    end
    if not o then K:Print(err) return end
    local profile = K:MyProfiles().active
    if self.tied then W:LinkOutfit(o, profile)
    elseif o.profile == profile then W:LinkOutfit(o, nil) end
    if not self.outfit then
      K:Print(("Saved what you're wearing as %s."):format(UI.Escape(o.name)))
    end
    self:Hide()
  end
  m.save:SetScript("OnClick", function() m:Commit() end)
  m.field.edit:SetScript("OnEnterPressed", function() m:Commit() end)
  m.field.edit:SetScript("OnEscapePressed", function() m:Hide() end)
  return m
end

local function AskOutfitName(o)
  if not wornTab then return end
  namer = namer or BuildNamer()
  wornTab.namer = namer
  local W, m = K.Worn, namer
  local profile = K:MyProfiles().active
  m.outfit = o
  m.title:SetText(o and "Rename outfit" or "Save an outfit")
  m.sub:SetText(o and ("Give %s a new name."):format(UI.Escape(o.name))
    or "Keep what you have on now under a name, to change back into with one click.")
  m.field.edit:SetText(o and o.name or "")
  -- The switch: put it on when you switch to the profile you're using now
  local holder = W:OutfitFor(profile)
  m.tied = (o and o.profile == profile) or false
  m.tie.label:SetText(("Put it on when I switch to my %s profile"):format(UI.Escape(profile or "")))
  if holder and holder ~= o then
    if not m.tie.desc then
      m.tie.desc = UI.Text(m.tie, "", "Small", "subtle", ND_W - 88)
      m.tie.desc:SetPoint("TOPLEFT", m.tie.label, "BOTTOMLEFT", 0, -3)
    end
    m.tie.desc:SetText(("Instead of %s, which goes on now."):format(UI.Escape(holder.name)))
    m.tie.desc:Show()
  elseif m.tie.desc then
    m.tie.desc:SetText("")
    m.tie.desc:Hide()
  end
  m.tie:Refresh()
  m:Check()
  m:Show()
  m.field.edit:SetFocus()
  m.field.edit:HighlightText()
end

local function OutfitMenu(owner, o)
  local W = K.Worn
  UI.Menu(owner, function(root)
    root:CreateTitle(UI.Escape(o.name))
    root:CreateButton("Change into it", function() W:ChangeInto(o) end)
    root:CreateButton("Save what I'm wearing over it", function()
      W:SaveOutfit(o.name)
      K:Print(("Saved what you're wearing as %s."):format(UI.Escape(o.name)))
    end)
    root:CreateButton("Rename...", function() AskOutfitName(o) end)
    -- Tied to a profile: switching to it changes you into this outfit
    local tie = root:CreateButton("Wear with a profile")
    tie:CreateRadio("No profile", function() return o.profile == nil end, function() W:LinkOutfit(o, nil) end)
    for _, name in ipairs(K:ProfileNames()) do
      local other = W:OutfitFor(name)
      local label = UI.Escape(name) .. ((other and other ~= o) and ("  |cff9a9a9a(now " .. UI.Escape(other.name) .. ")|r") or "")
      tie:CreateRadio(label, function() return o.profile == name end, function() W:LinkOutfit(o, name) end)
    end
    root:CreateDivider()
    root:CreateButton("Delete", function() StaticPopup_Show("KINSHIPRP_OUTFIT_DELETE", UI.Escape(o.name), nil, o) end)
  end)
end

local STAGE_W = 404
local WSLOT, WGAP = 36, 6
local ROW_ICONS = 10   -- small icons along an outfit's row
local WROW = 40   -- the bottom row of slots sits this far up, clear of the note
local FIT_W = CW - STAGE_W - 10

local function BuildWorn(tab, c)
  local W = K.Worn
  wornTab = tab
  -- The stage: a softly lit backdrop, your character, slots either side
  local stage = CreateFrame("Frame", nil, tab)
  stage:SetPoint("TOPLEFT", 0, 0)
  stage:SetSize(STAGE_W, BODY_H)
  tab.stage = stage
  local bg = stage:CreateTexture(nil, "BACKGROUND")
  bg:SetAllPoints()
  bg:SetColorTexture(1, 1, 1, 1)
  local edge = CreateFrame("Frame", nil, stage)
  edge:SetAllPoints()
  edge:SetFrameLevel(stage:GetFrameLevel() + 6)
  edge.border = UI.Border(edge)
  UI:OnTheme(function(t)
    local top, bottom = t.stageTop, t.stageBottom
    if bg.SetGradient and CreateColor then
      bg:SetGradient("VERTICAL", CreateColor(bottom[1], bottom[2], bottom[3], 1), CreateColor(top[1], top[2], top[3], 1))
    else
      bg:SetVertexColor(top[1], top[2], top[3], 1)
    end
    edge.border:SetColor(unpack(t.chromeEdge))
  end)
  local model = CreateFrame("PlayerModel", nil, stage)
  model:SetPoint("TOPLEFT", WSLOT + 28, -14)
  model:SetPoint("BOTTOMRIGHT", -(WSLOT + 28), WROW + WSLOT + 6)
  model.facing = 0
  model:EnableMouse(true)
  model:SetScript("OnMouseDown", function(self) self.dragX = GetCursorPosition() end)
  model:SetScript("OnMouseUp", function(self) self.dragX = nil end)
  model:SetScript("OnUpdate", function(self)
    if self.dragX then
      local x = GetCursorPosition()
      self.facing = self.facing + (x - self.dragX) * 0.012
      self.dragX = x
      self:SetFacing(self.facing)
    end
  end)
  tab.model = model
  -- A model lets go of the character while hidden: load it again on each show.
  tab:HookScript("OnShow", function() model:SetUnit("player"); model:SetFacing(model.facing or 0) end)
  local note = UI.Text(stage, "Drag onto a slot to wear it. Right-click to take it off.", "Small", "fixed", STAGE_W - 40)
  note:SetTextColor(0.95, 0.9, 0.8)
  note:SetPoint("BOTTOM", 0, 12)
  note:SetJustifyH("CENTER")

  -- Down each side, labelled; along the bottom, centred, named by their tooltips
  tab.slots = {}
  local along = 0
  for _, w in ipairs(I.WEAR) do if w.side == "bottom" then along = along + 1 end end
  local rowW = along * WSLOT + (along - 1) * (WGAP + 8)
  for i, w in ipairs(I.WEAR) do
    local b = W.SlotButton(stage, WSLOT, w.key, true)
    local at = I.WEAR_PLACE[w.key].at
    if w.side == "bottom" then
      b:SetPoint("BOTTOMLEFT", math.floor((STAGE_W - rowW) / 2) + at * (WSLOT + WGAP + 8), WROW)
    else
      local y = -12 - at * (WSLOT + WGAP)
      if w.side == "left" then b:SetPoint("TOPLEFT", 16, y) else b:SetPoint("TOPRIGHT", -16, y) end
      b.label = UI.Text(stage, w.label, "Label", "fixed")
      b.label:SetTextColor(0.85, 0.82, 0.74)
      if w.side == "left" then b.label:SetPoint("LEFT", b, "RIGHT", 6, 0)
      else b.label:SetPoint("RIGHT", b, "LEFT", -6, 0) end
    end
    b:SetFrameLevel(model:GetFrameLevel() + 3)
    tab.slots[i] = b
  end

  -- Things in your bags you could wear
  local card = UI.Panel(tab)
  card:SetPoint("TOPLEFT", STAGE_W + 10, 0)
  card:SetSize(FIT_W, BODY_H)
  -- Two views: what's in your bags to wear, and your saved outfits
  tab.view = "wear"
  tab.views = UI.Segments(card, { { key = "wear", label = "To wear" }, { key = "outfits", label = "Outfits" } },
    math.floor((FIT_W - 28) / 2), function(key) tab.view = key; Refresh() end)
  tab.views:SetPoint("TOPLEFT", 14, -12)
  tab.views:Select("wear")
  function tab:ShowView(key) self.view = key; self.views:Select(key); Refresh() end
  tab.fit = UI.List(card, FIT_W - 28, BODY_H - 158, 44, "", function(row)
    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetSize(30, 30)
    row.icon:SetPoint("LEFT", 8, 0)
    row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    UI.Round(row.icon)
    row.name = UI.Text(row, "", "Body", "heading", FIT_W - 110)
    row.name:SetPoint("TOPLEFT", 46, -7)
    row.name:SetWordWrap(false)
    row.sub = UI.Text(row, "", "Small", "subtle", FIT_W - 110)
    row.sub:SetPoint("TOPLEFT", row.name, "BOTTOMLEFT", 0, -3)
    row.sub:SetWordWrap(false)
    row:SetScript("OnClick", function(self) if self.item then W:Wear(self.item.index) end end)
    row:RegisterForDrag("LeftButton")
    row:SetScript("OnDragStart", function(self)
      if not self.item then return end
      self.dragging = true
      W.Ghost(I.IconTexture(self.item.def.icon)):Show()
      GameTooltip:Hide()
    end)
    row:SetScript("OnDragStop", function(self)
      W.Ghost():Hide()
      if not (self.dragging and self.item) then return end
      self.dragging = nil
      W:DropFromBag(self.item.index)
    end)
    row.onEnter = function(self)
      if not self.item then return end
      I:ShowTooltip(self, self.item.def, self.item.count, "ANCHOR_LEFT")
      GameTooltip:AddLine("Click to wear it, or drag it onto its slot.", 0.55, 0.80, 1)
      GameTooltip:Show()
    end
  end, { emptyIcon = K.Art("IconNote") })
  tab.fit:SetPoint("TOPLEFT", 14, -44)

  -- Outfits: click to change into one, right-click for the rest
  tab.outfits = UI.List(card, FIT_W - 28, BODY_H - 158, 50, "", function(row)
    row.name = UI.Text(row, "", "Body", "heading", FIT_W - 110)
    row.name:SetPoint("TOPLEFT", 10, -7)
    row.name:SetWordWrap(false)
    row.state = UI.Text(row, "", "Small", "subtle")
    row.state:SetPoint("TOPRIGHT", -8, -9)
    row.icons = {}
    for i = 1, ROW_ICONS do
      local t = row:CreateTexture(nil, "ARTWORK")
      t:SetSize(18, 18)
      t:SetPoint("TOPLEFT", 10 + (i - 1) * 21, -26)
      t:SetTexCoord(0.08, 0.92, 0.08, 0.92)
      UI.Round(t)
      row.icons[i] = t
    end
    row:SetScript("OnClick", function(self, button)
      if not self.item then return end
      GameTooltip:Hide()
      if button == "RightButton" then OutfitMenu(self, self.item) else W:ChangeInto(self.item) end
    end)
    row.onEnter = function(self)
      local o = self.item
      if not o then return end
      GameTooltip:SetOwner(self, "ANCHOR_LEFT")
      GameTooltip:SetText(UI.Escape(o.name), 1, 0.82, 0)
      local worn, any = W:Table(), false
      for _, w in ipairs(I.WEAR) do
        local id = o.slots and o.slots[w.key]
        local def = id and I:Get(id)
        if def then
          any = true
          local has = (worn[w.key] and worn[w.key].def == id) or I:Available(id) > 0
          local col = has and I.QualityColor(def.quality) or { 0.5, 0.5, 0.5 }
          GameTooltip:AddDoubleLine(w.label, UI.Escape(def.name) .. (has and "" or "  (not in your bags)"),
            0.62, 0.62, 0.62, col[1], col[2], col[3])
        end
      end
      if not any then GameTooltip:AddLine("Nothing worn: changing into it takes everything off.", 1, 1, 1, true) end
      if o.profile then
        GameTooltip:AddLine(("You change into it when you switch to your %s profile."):format(UI.Escape(o.profile)),
          1, 0.82, 0, true)
      end
      GameTooltip:AddLine("Click to change into it. Right-click to update, rename, delete or tie it to a profile.", 0.55, 0.80, 1, true)
      GameTooltip:Show()
    end
  end, { emptyIcon = K.Art("IconNote") })
  tab.outfits:SetPoint("TOPLEFT", 14, -44)

  local work = UI.Button(card, "Open the Workshop", FIT_W - 40, 24)
  work:SetPoint("BOTTOMLEFT", 20, 14)
  tab.work = work
  tab.save = UI.Button(card, "Save what I'm wearing", FIT_W - 40, 24)
  tab.save:SetPoint("BOTTOMLEFT", 20, 14)
  tab.save:SetScript("OnClick", function() AskOutfitName(nil) end)
  UI.Tooltip(tab.save, "Save an outfit", "Keep what you have on now under a name, to change back into with one click. "
    .. "Use a name you already have to save over it.")
  -- The note sits just above the button, under the list
  tab.fitNote = UI.Text(card, "", "Small", "subtle", FIT_W - 40)
  tab.fitNote:SetPoint("BOTTOMLEFT", work, "TOPLEFT", 0, 10)
  tab.fitNote:SetSpacing(2)
  work:SetScript("OnClick", function() c.tab = 2; Refresh() end)
  UI.Tooltip(work, "The Workshop", "Choose Worn on for a design to make it something your character can wear.")
end

local function RefreshWorn(tab)
  local W = K.Worn
  for _, b in ipairs(tab.slots) do b:SetItem((W:In(b.slot)), nil) end
  local okM, fileID = pcall(tab.model.GetModelFileID, tab.model)
  if not (okM and fileID) then tab.model:SetUnit("player") end
  -- Everything wearable in your bags, whatever its slot
  local items, bag = {}, I:Bag()
  for i = 1, I.SLOTS do
    local s = bag[i]
    local def = s and I:Get(s.def)
    if def and def.wear and I.WEAR_LABEL[def.wear] then items[#items + 1] = { index = i, def = def, count = s.count } end
  end
  tab.fit.empty:SetText("Nothing in your bags can be worn yet.")
  tab.fit:SetItems(items, function(row, it)
    row.icon:SetTexture(I.IconTexture(it.def.icon))
    row.name:SetText(UI.Escape(it.def.name))
    row.name:SetTextColor(unpack(I.QualityColor(it.def.quality, true)))
    local on = W:In(it.def.wear)
    row.sub:SetText(I.WEAR_LABEL[it.def.wear] .. (on and ("  ·  instead of " .. UI.Escape(on.name)) or ""))
  end)
  local outfits = tab.view == "outfits"
  tab.fit:SetShown(not outfits)
  tab.work:SetShown(not outfits)
  tab.outfits:SetShown(outfits)
  tab.save:SetShown(outfits)
  if outfits then
    tab.outfits.empty:SetText("No outfits yet. Put on what you like, then save it here.")
    local list = {}
    for _, o in ipairs(W:Outfits()) do list[#list + 1] = o end
    tab.outfits:SetItems(list, function(row, o)
      row.name:SetText(UI.Escape(o.name) .. (o.profile and ("  |cff%s· %s|r"):format(UI.Hex(K:Theme().subtle), UI.Escape(o.profile)) or ""))
      local pieces, have, exact = W:OutfitState(o)
      local t = K:Theme()
      if exact then
        row.state:SetText("Wearing")
        row.state:SetTextColor(unpack(t.accent))
      elseif have < pieces then
        row.state:SetText(("%d missing"):format(pieces - have))
        row.state:SetTextColor(unpack(t.subtle))
      else
        row.state:SetText(pieces == 1 and "1 piece" or ("%d pieces"):format(pieces))
        row.state:SetTextColor(unpack(t.subtle))
      end
      local n = 0
      for _, w in ipairs(I.WEAR) do
        local id = o.slots and o.slots[w.key]
        local def = id and I:Get(id)
        if def and n < ROW_ICONS then
          n = n + 1
          local ic = row.icons[n]
          ic:SetTexture(I.IconTexture(def.icon))
          local has = (W:In(w.key) and W:In(w.key).id == id) or I:Available(id) > 0
          ic:SetDesaturated(not has)
          ic:SetAlpha(has and 1 or 0.45)
          ic:Show()
        end
      end
      for i = n + 1, ROW_ICONS do row.icons[i]:Hide() end
    end)
    tab.fitNote:SetText("Change outfits with a click, or from a macro with /kin outfit and its name. "
      .. "Tie one to a profile and switching to that profile puts it on.")
  else
    tab.fitNote:SetText("Worn items show on your profile, where other Kinship users can see them. "
      .. "To wear a design, set Worn on in the Workshop.")
  end
end

---------------------------------------------------------------------------
-- The page
---------------------------------------------------------------------------
-- Worn is fifth in the list but shows second, after Bags (bar.order).
local TAB_NAMES = { "Bags", "Workshop", "Documents", "Database", "Worn" }
local WORN = 5

-- Is this tab's feature switched on (and loaded)?
local function TabOn(i)
  if i == 1 or i == 2 then return K:ExtOn("inventory") end
  if i == 3 then return K.Documents ~= nil and K:ExtOn("documents") end
  if i == 4 then return K.ExtDB ~= nil and K:ExtOn() end
  if i == WORN then return K.Worn ~= nil and K:ExtOn("inventory") end
  return false
end

-- Tabs are built the first time they're shown, so a switched-off feature builds nothing.
local function EnsureTab(c, i)
  if c.built[i] then return end
  c.built[i] = true
  if i == 1 then BuildBags(c.frames[1], c)
  elseif i == 2 then BuildWorkshop(c.frames[2], c)
  elseif i == 3 then
    K.Documents:BuildTab(c.frames[3], {
      onMakeItem = function(doc)
        if not K:ExtOn("inventory") then return end
        c.tab = 2
        EnsureTab(c, 2)
        NewDesign(c.frames[2], { name = K.Documents.Title(doc), icon = BOOK_ICON, quality = 1, stack = 1, documentId = doc.id })
      end,
    })
  elseif i == 4 then K.ExtDB:BuildTab(c.frames[4], c)
  elseif i == WORN then BuildWorn(c.frames[WORN], c) end
end

K:RegisterPage({
  id = "inventory", title = "Inventory", heading = "Inventory",
  subtitle = "What your character carries, makes and writes.",
  group = "World", icon = { "Interface\\Icons\\INV_Misc_Bag_08", round = true },
  enabled = function() return K:ExtOn() end,

  build = function(c)
    c.tab = 1
    c.tabs = UI.TabBar(c, TAB_NAMES, function(i) c.tab = i; Refresh() end, true)
    c.tabs.order = { 1, WORN, 2, 3, 4 }
    c.tabs:SetPoint("TOPLEFT", -10, 2)
    c.frames, c.built = {}, {}
    for i = 1, #TAB_NAMES do
      local f = CreateFrame("Frame", nil, c)
      f:SetPoint("TOPLEFT", 0, -TOP)
      f:SetSize(CW, BODY_H)
      f:Hide()
      c.frames[i] = f
    end
  end,

  refresh = function(c)
    for i in ipairs(TAB_NAMES) do c.tabs:SetTabShown(i, TabOn(i)) end
    if not TabOn(c.tab) then
      for i in ipairs(TAB_NAMES) do if TabOn(i) then c.tab = i break end end
    end
    if not TabOn(c.tab) then return end
    EnsureTab(c, c.tab)
    c.tabs:Select(c.tab)
    for i, f in ipairs(c.frames) do f:SetShown(i == c.tab) end
    if c.shownTab ~= c.tab then
      if c.shownTab then UI.FadeIn(c.frames[c.tab], 0.2) end
      c.shownTab = c.tab
    end
    if c.tab == 1 then RefreshBags(c.frames[1])
    elseif c.tab == 2 then RefreshWorkshop(c.frames[2])
    elseif c.tab == 3 then K.Documents:RefreshTab(c.frames[3])
    elseif c.tab == WORN then
      RefreshWorn(c.frames[WORN])
      -- Its own tour the first time, but only once the page's own tour has had
      -- its turn: never while it's passing through, nor ahead of it.
      local G = K.Guide
      if G and not G.active and G:Seen("inventory") then
        C_Timer.After(0.3, function()
          if c.tab == WORN and c.frames[WORN]:IsVisible() and not G.active then G:Maybe("worn", c, K.Journal.frame) end
        end)
      end
    else K.ExtDB:RefreshTab(c.frames[4]) end
  end,
  -- The ? replays the Worn tour while that tab's showing, the page's otherwise
  guide = function(c) return c.tab == WORN and "worn" or nil end,
})

local function OnChange()
  if K.Journal:IsShowing("inventory") then Refresh() end
end
for _, e in ipairs({ "INVENTORY", "ITEMDEFS", "DOCUMENTS", "TRADE", "EXT_DB", "WORN" }) do K:On(e, OnChange) end
