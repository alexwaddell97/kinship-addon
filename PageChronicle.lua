-- Kinship RP: Chronicle page, laid out as two cards side by side.
-- Left: the timeline. Right: the chosen entry, or a new page being written.

local ADDON, ns = ...
local K = ns.K
local UI = K.UI

local FILTERS = {
  { key = "all", label = "Everything" }, { key = "place", label = "Places" }, { key = "milestone", label = "Milestones" },
  { key = "dungeon", label = "Dungeons" }, { key = "kin", label = "Kin" }, { key = "battle", label = "Battles" },
  { key = "letter", label = "Letters" }, { key = "note", label = "Your own pages" },
}

local W, H = 696, 466
local LEFT_W, GAP, PAD = 296, 10, 16

-- A card with a padded inner frame to lay content on.
local function Card(parent, w, h)
  local card = UI.Panel(parent)
  card:SetSize(w, h)
  local inner = CreateFrame("Frame", nil, card)
  inner:SetPoint("TOPLEFT", PAD, -PAD)
  inner:SetPoint("BOTTOMRIGHT", -PAD + 4, PAD)
  return card, inner, w - 2 * PAD + 4, h - 2 * PAD
end

K:RegisterPage({
  id = "chronicle", title = "Chronicle", heading = "Chronicle",
  subtitle = "Your character's story, written as you play.",

  build = function(c)
    c.filter = "all"

    -- Left card: timeline -------------------------------------------------------
    local leftCard, left, lw, lh = Card(c, LEFT_W, H)
    leftCard:SetPoint("TOPLEFT")

    local title = UI.Text(left, "My Chronicle", "GameFontNormalLarge", "heading")
    title:SetPoint("TOPLEFT", 0, -3)

    c.filterBtn = UI.Button(left, "", 124, 24)
    c.filterBtn:SetPoint("TOPRIGHT", 0, 0)
    c.filterBtn:SetScript("OnClick", function(self)
      UI.Menu(self, function(root)
        root:CreateTitle("Show")
        for _, f in ipairs(FILTERS) do
          root:CreateRadio(f.label, function() return c.filter == f.key end,
            function() c.filter = f.key; c.selected = nil; K.Journal:RefreshCurrent() end)
        end
      end)
    end)

    local div = UI.Divider(left, lw)
    div:SetPoint("TOPLEFT", 0, -34)

    c.list = UI.List(left, lw, lh - 82, 28,
      "Your Chronicle is empty for now. It fills itself in as you explore, level up and travel with others.",
      function(row)
        row.icon = row:CreateTexture(nil, "ARTWORK")
        row.icon:SetSize(22, 22)
        row.icon:SetPoint("LEFT", 6, 0)
        row.date = UI.Text(row, "", "GameFontHighlightSmall", "subtle")
        row.date:SetPoint("RIGHT", -4, 0)
        row.title = UI.Text(row, "", "GameFontHighlightSmall", "text")
        row.title:SetPoint("LEFT", row.icon, "RIGHT", 8, 0)
        row.title:SetPoint("RIGHT", row.date, "LEFT", -6, 0)
        row.title:SetWordWrap(false)
        row:SetScript("OnClick", function(self) c.selected = self.item; c.editing = false; K.Journal:RefreshCurrent() end)
      end, { bare = true, emptyIcon = K.Art("IconMilestone") })
    c.list:SetPoint("TOPLEFT", 0, -42)

    local write = UI.Button(left, "Write a new page", 150, 24)
    write:SetPoint("BOTTOMLEFT", 0, 0)
    c.writeBtn = write
    write:SetScript("OnClick", function() c:Edit(nil) end)
    UI.Tooltip(write, "Write a new page", "Add a page to your Chronicle in your character's own words.")
    c.count = UI.Text(left, "", "GameFontHighlightSmall", "subtle")
    c.count:SetPoint("BOTTOMRIGHT", -2, 6)

    -- Right card: reading ----------------------------------------------------------
    local rightCard, right, rw, rh = Card(c, W - LEFT_W - GAP, H)
    rightCard:SetPoint("TOPLEFT", leftCard, "TOPRIGHT", GAP, 0)

    local read = CreateFrame("Frame", nil, right)
    read:SetAllPoints()
    c.read = read
    read.icon = read:CreateTexture(nil, "ARTWORK")
    read.icon:SetSize(38, 38)
    read.icon:SetPoint("TOPLEFT", 0, 0)
    read.title = UI.Text(read, "", "GameFontNormalLarge", "heading", rw - 48)
    read.title:SetPoint("TOPLEFT", read.icon, "TOPRIGHT", 10, -2)
    read.title:SetWordWrap(false)
    read.meta = UI.Text(read, "", "GameFontHighlightSmall", "subtle", rw - 48)
    read.meta:SetPoint("TOPLEFT", read.title, "BOTTOMLEFT", 0, -4)
    local rdiv = UI.Divider(read, rw)
    rdiv:SetPoint("TOPLEFT", 0, -50)
    read.body = UI.ReadArea(read, rw, rh - 96, "QuestFont", "text")
    read.body:SetPoint("TOPLEFT", 0, -62)
    read.editBtn = UI.Button(read, "Write", 90, 24)
    read.editBtn:SetPoint("BOTTOMLEFT", 0, 0)
    read.editBtn:SetScript("OnClick", function() c:Edit(c.selected) end)
    read.removeBtn = UI.Button(read, "Remove", 90, 24)
    read.removeBtn:SetPoint("LEFT", read.editBtn, "RIGHT", 8, 0)
    read.removeBtn:SetScript("OnClick", function()
      if c.selected then K:RemoveEntry(c.selected); c.selected = nil end
    end)
    read.emptyIcon = read:CreateTexture(nil, "ARTWORK")
    read.emptyIcon:SetTexture(K.Art("IconMilestone"))
    read.emptyIcon:SetSize(64, 64)
    read.emptyIcon:SetPoint("CENTER", 0, 30)
    read.emptyIcon:SetAlpha(0.75)
    read.empty = UI.Text(read, "Choose a moment from your Chronicle to read it here.", "QuestFont", "subtle", rw - 60)
    read.empty:SetPoint("TOP", read.emptyIcon, "BOTTOM", 0, -12)
    read.empty:SetJustifyH("CENTER")

    -- Right card: writing ----------------------------------------------------------
    local edit = CreateFrame("Frame", nil, right)
    edit:SetAllPoints()
    edit:Hide()
    c.edit = edit
    edit.heading = UI.Text(edit, "", "GameFontNormalLarge", "heading")
    edit.heading:SetPoint("TOPLEFT", 0, -2)
    local tl = UI.Text(edit, "Title", "GameFontNormalSmall", "subtle")
    tl:SetPoint("TOPLEFT", 1, -32)
    edit.titleBox = UI.Edit(edit, rw, 24, nil, 80)
    edit.titleBox:SetPoint("TOPLEFT", 0, -46)
    local bl = UI.Text(edit, "In your character's words", "GameFontNormalSmall", "subtle")
    bl:SetPoint("TOPLEFT", 1, -82)
    edit.area = UI.TextArea(edit, rw, rh - 132, 3000)
    edit.area:SetPoint("TOPLEFT", 0, -96)
    local save = UI.Button(edit, "Save", 90, 24)
    save:SetPoint("BOTTOMLEFT", 0, 0)
    local cancel = UI.Button(edit, "Cancel", 90, 24)
    cancel:SetPoint("LEFT", save, "RIGHT", 8, 0)
    cancel:SetScript("OnClick", function() c.editing = false; K.Journal:RefreshCurrent() end)
    save:SetScript("OnClick", function()
      local t = strtrim(edit.titleBox:GetText() or "")
      local text = edit.area.edit:GetText() or ""
      if t == "" then t = "A page from my journal" end
      if c.editEntry then
        c.editEntry.title, c.editEntry.text = t, text
        c.selected = c.editEntry
        K:Fire("CHRONICLE")
      else
        c.selected = K:AddEntry("note", t, text)
      end
      c.editing = false
      K.Journal:RefreshCurrent()
    end)

    function c:Edit(entry)
      self.editing, self.editEntry = true, entry
      K.Journal:RefreshCurrent()
      edit.heading:SetText(entry and "Add your words" or "A new page")
      edit.titleBox:SetText(entry and entry.title or "")
      edit.area.edit:SetText(entry and entry.text or "")
      if entry then edit.area.edit:SetFocus() else edit.titleBox:SetFocus() end
    end
  end,

  refresh = function(c)
    local label = "Everything"
    for _, f in ipairs(FILTERS) do if f.key == c.filter then label = f.label end end
    c.filterBtn:SetText("Show: " .. label)

    local items, all = {}, K:Chronicle().entries
    for i = #all, 1, -1 do
      local e = all[i]
      if c.filter == "all" or e.kind == c.filter then items[#items + 1] = e end
    end
    c.count:SetText(#all == 1 and "1 moment" or (#all .. " moments"))
    c.list:SetItems(items, function(row, e)
      row.icon:SetTexture((K.ENTRY[e.kind] or K.ENTRY.note).icon)
      row.title:SetText(e.title)
      row.date:SetText(date("%d %b", e.t))
      row.sel:SetShown(e == c.selected)
    end)

    local editing, wasEditing = c.editing and true or false, c.edit:IsShown()
    c.read:SetShown(not editing)
    c.edit:SetShown(editing)
    if editing ~= wasEditing then UI.FadeIn(editing and c.edit or c.read, 0.2) end
    if c.editing then return end

    local e, r = c.selected, c.read
    local has = e ~= nil
    for _, w in ipairs({ r.icon, r.title, r.meta, r.body, r.editBtn, r.removeBtn }) do w:SetShown(has) end
    r.empty:SetShown(not has)
    r.emptyIcon:SetShown(not has)
    if not has then return end
    if r.shown ~= e then r.shown = e; UI.FadeIn(r, 0.2) end
    r.icon:SetTexture((K.ENTRY[e.kind] or K.ENTRY.note).icon)
    r.title:SetText(e.title)
    r.meta:SetText(("%s  ·  %s  ·  level %d"):format(K.FormatDate(e.t), e.place or "?", e.level or 0))
    r.body:SetText(e.text ~= "" and e.text or
      "No words written for this moment yet.\n\nClick Write to add what your character thought or felt.")
    r.editBtn:SetText(e.text ~= "" and "Edit" or "Write")
  end,
})
