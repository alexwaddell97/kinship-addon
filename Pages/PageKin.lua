-- Kinship RP: Kin page (everyone you've adventured with).

local ADDON, ns = ...
local K = ns.K
local UI = K.UI

local GROUPS = {
  { key = "all", label = "Everyone" }, { key = "group", label = "Travelled together" },
  { key = "manual", label = "Added by you" },
}

local function ClassColor(class)
  local c = class and (C_ClassColor and C_ClassColor.GetClassColor(class) or (RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]))
  if c then return c.r, c.g, c.b end
end

local function Ago(t)
  if not t then return "never" end
  local d = math.floor((time() - t) / 86400)
  if d <= 0 then return "today" elseif d == 1 then return "yesterday" else return d .. " days ago" end
end

local function RelationMenu(owner, e)
  UI.Menu(owner, function(root)
    root:CreateTitle(e.name)
    for _, r in ipairs(K.RELATIONS) do
      root:CreateRadio(r.label, function() return (e.rel or "") == r.key end,
        function() e.rel = r.key; K:Fire("KIN") end)
    end
    root:CreateDivider()
    root:CreateButton("View profile", function() K:ViewProfile(e.name) end)
    root:CreateButton("Whisper", function()
      K:Whisper(e.name)
    end)
    root:CreateButton("|cffff6060Remove from Kin|r", function() K:RemoveKin(e.name:lower()) end)
  end)
end

K:RegisterPage({
  id = "kin", title = "Kin", heading = "Kin",
  subtitle = "Everyone you've adventured with, and where you met.",

  build = function(c)
    c.group, c.search = "all", ""
    c.groups = UI.Segments(c, GROUPS, 128, function(key) c.group = key; K.Journal:RefreshCurrent() end)
    c.groups:SetPoint("TOPLEFT", 0, 0)
    local search = UI.Search(c, 170, "Search Kin", function(t) c.search = t; K.Journal:RefreshCurrent() end)
    search:SetPoint("TOPRIGHT", 0, 0)
    c.searchBox = search

    -- Column headings
    local head = CreateFrame("Frame", nil, c)
    head:SetPoint("TOPLEFT", 0, -32)
    head:SetSize(696, 16)
    local function col(text, x)
      local t = UI.Text(head, text, "GameFontNormalSmall", "deskSubtle")
      t:SetPoint("LEFT", x, 0)
      return t
    end
    col("Name", 40); col("Bond", 246); col("Where you met", 358); col("Last seen", 598)

    c.list = UI.List(c, 696, 370, 28, "No Kin yet. Group up with someone, or add a name below.",
      function(row)
        row.icon = row:CreateTexture(nil, "ARTWORK")
        row.icon:SetSize(22, 22)
        row.icon:SetPoint("LEFT", 8, 0)
        row.name = UI.Text(row, "", "GameFontHighlight", "plain")
        row.name:SetPoint("LEFT", 34, 0)
        row.name:SetWidth(200)
        row.name:SetWordWrap(false)
        row.bond = UI.Button(row, "", 100, 20)
        row.bond:SetPoint("LEFT", 240, 0)
        row.met = UI.Text(row, "", "GameFontHighlightSmall", "text")
        row.met:SetPoint("LEFT", 352, 0)
        row.met:SetWidth(230)
        row.met:SetWordWrap(false)
        row.seen = UI.Text(row, "", "GameFontHighlightSmall", "subtle")
        row.seen:SetPoint("LEFT", 592, 0)
        row:SetScript("OnClick", function(self, button)
          if button == "RightButton" then RelationMenu(self, self.item) else K:ViewProfile(self.item.name) end
        end)
        row.bond:SetScript("OnClick", function(self) RelationMenu(self, row.item) end)
      end, { emptyIcon = K.Art("IconKin") })
    c.list:SetPoint("TOPLEFT", 0, -50)

    local tip = UI.Text(c, "Click someone to view their profile. Right-click to set your bond with them.",
      "GameFontHighlightSmall", "deskSubtle", 370)
    tip:SetPoint("TOPLEFT", c.list, "BOTTOMLEFT", 2, -10)

    local add = UI.Field(c, "Add someone by name", 220, 60, nil, "desk")
    add:SetPoint("BOTTOMRIGHT", -84, -3)
    c.addBox = add
    local addBtn = UI.Button(c, "Add", 76, 23)
    addBtn:SetPoint("BOTTOMRIGHT", 0, 0)
    local function doAdd()
      if K:AddKinByName(add.edit:GetText()) then add.edit:SetText(""); add.edit:ClearFocus() end
    end
    addBtn:SetScript("OnClick", doAdd)
    add.edit:SetScript("OnEnterPressed", doAdd)
    K.Suggest(add.edit, nil, true)   -- names you know, as you type (opening upward)
  end,

  refresh = function(c)
    c.groups:Select(c.group)
    local items = {}
    for _, e in pairs(K:KinList()) do
      if (c.group == "all" or e.how == c.group) and (c.search == "" or e.name:lower():find(c.search, 1, true)) then
        items[#items + 1] = e
      end
    end
    table.sort(items, function(a, b) return (a.seen or a.met.t or 0) > (b.seen or b.met.t or 0) end)

    c.list:SetItems(items, function(row, e)
      local icon = K.Art(e.how == "manual" and "IconNote" or "IconKin")
      row.icon:SetTexture(icon)
      row.name:SetText(e.name)
      local r, g, b = ClassColor(e.class)
      local t = K:Theme()
      if r and t.light then row.name:SetTextColor(r * 0.55, g * 0.55, b * 0.55) -- class colours, inked
      elseif r then row.name:SetTextColor(r, g, b)
      else row.name:SetTextColor(unpack(t.text)) end
      row.bond:SetText(K.RelationLabel(e.rel))
      local m = e.met or {}
      row.met:SetText(("%s, level %d, %s"):format(m.place or "?", m.level or 0, date("%d %b", m.t or time())))
      row.seen:SetText(Ago(e.seen or m.t))
    end)
  end,
})
