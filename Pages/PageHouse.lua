-- Kinship RP: Community page. Your house (a family, on a shared surname),
-- your group, and Gatherings (PageGatherings.lua) as a third tab.

local ADDON, ns = ...
local K = ns.K
local UI = K.UI

local ICON_DIR = "Interface\\Icons\\"

-- A crest as a medallion: a gold ring, a dark well, a fine inner ring, and the
-- icon set inside it, trimmed of its square border and kept small enough to
-- stay sharp. onCard: on a card (the well takes the card's colour).
-- Returns a frame (a Button when button) with :SetCrest(path) and :SetLit(v).
local function Medallion(parent, size, button, onCard)
  local f = CreateFrame(button and "Button" or "Frame", nil, parent)
  f:SetSize(size, size)
  local inner = math.floor(size * 0.82)
  f.ring = UI.Circle(f, size, "BACKGROUND", 0)
  f.ring:SetPoint("CENTER")
  f.well = UI.Circle(f, size - 6, "BACKGROUND", 1)
  f.well:SetPoint("CENTER")
  f.inner = UI.Circle(f, inner, "BORDER", 0)
  f.inner:SetPoint("CENTER")
  f.hole = UI.Circle(f, inner - 3, "BORDER", 1)
  f.hole:SetPoint("CENTER")
  f.icon = f:CreateTexture(nil, "ARTWORK")
  f.icon:SetSize(inner - 9, inner - 9)
  f.icon:SetPoint("CENTER")
  f.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
  UI.Round(f.icon)
  f.shine = UI.Circle(f, inner - 9, "OVERLAY", 0)
  f.shine:SetPoint("CENTER")
  f.shine:SetBlendMode("ADD")
  f.shine:SetVertexColor(1, 1, 1, 0)
  function f:SetCrest(path) self.icon:SetTexture(path or "Interface\\Icons\\INV_Shield_05") end
  function f:SetLit(v)
    local t = K:Theme()
    self.ring:SetVertexColor(t.ui[1], t.ui[2], t.ui[3], v and 1 or 0.9)
    self.shine:SetVertexColor(1, 1, 1, v and 0.08 or 0)
  end
  UI:OnTheme(function(t)
    f.well:SetVertexColor(unpack(onCard and t.panel or t.chrome))
    f.inner:SetVertexColor(t.ui[1], t.ui[2], t.ui[3], 0.5)
    f.hole:SetVertexColor(0.04, 0.03, 0.02, 0.92)
    f:SetLit(false)
  end)
  return f
end

---------------------------------------------------------------------------
-- Choosing a crest: the icon picker (IconPicker.lua), searched by name. A
-- crest is shared by its icon's name, so it needs one other players can take.
---------------------------------------------------------------------------
local function CrestPath(icon)
  local IP = K.IconPicker
  local name = (type(icon) == "number" and IP and IP.NameOf and IP.NameOf(icon))
    or (type(icon) == "string" and icon:match("([^\\/]+)$"))
  if name and name:find("^[%w_]+$") then return ICON_DIR .. name end
end

-- current: the crest now; onPick(path) when one is chosen.
local function ShowPicker(anchor, current, onPick)
  local IP = K.IconPicker
  if not IP then return end
  local name = type(current) == "string" and current:match("([^\\]+)$")
  IP:Open(anchor, (name and IP.IdOf and IP.IdOf(name)) or current, function(icon)
    local path = CrestPath(icon)
    if path then
      onPick(path)
    elseif UIErrorsFrame then
      UIErrorsFrame:AddMessage("That icon can't be shared as a crest. Try another.", 1, 0.25, 0.2)
    end
  end)
end

-- Recognition: [nameKey] = { name, state = "recognised" | "ignored" }
function K:SetHouseMember(key, name, state)
  local h = self:House()
  if not h or not key then return end
  h.members = h.members or {}
  h.members[key] = state and { name = name, state = state } or nil
  if state == "recognised" then self:Print(name .. " is now recognised as family.")
  elseif state == "ignored" then self:Print(name .. "'s claim will no longer be shown.") end
  self:Fire("HOUSE")
  K.Journal:RefreshCurrent()
end

function K:HouseState(name)
  local h = self:House()
  local key = K.NameKey(name)
  local m = h and h.members and key and h.members[key]
  return m and m.state or nil
end

-- Returns recognised members and unconfirmed claims for your house.
function K:HouseMembers()
  local key = self:HouseKey()
  local house = self:House()
  local recognised, claims, seen = {}, {}, {}
  if not key or not house then return recognised, claims end
  house.members = house.members or {}

  for guid, p in pairs(self.db.profiles) do
    local prof = p.list and p.list[p.active]
    if prof and self:HouseKey(strtrim(prof.house or "")) == key and p.name then
      local k = K.NameKey(p.name) or p.name:lower()
      if not seen[k] then
        seen[k] = true
        recognised[#recognised + 1] = { name = p.name, key = k, mine = true, state = "recognised",
          role = guid == self:CharKey() and "You" or "Your character" }
      end
    end
  end

  local recent = time() - 600
  local function add(name, raw, role)
    local k = K.NameKey(raw or name) or name:lower()
    if seen[k] then return end
    seen[k] = true
    local state = house.members[k] and house.members[k].state
    if state == "ignored" then return end
    local m = { name = name, raw = raw, key = k, state = state, role = role }
    if state == "recognised" then recognised[#recognised + 1] = m else claims[#claims + 1] = m end
  end

  -- People whose shared profile names this house
  for _, reg in pairs(self.Registry) do
    local house = reg.profile and strtrim(reg.profile.house or "") or ""
    if house:lower() == key then
      add(Ambiguate and Ambiguate(reg.name, "none") or reg.name, reg.name,
        (reg.t or 0) > recent and "|cff5fd35fNearby|r" or nil)
    end
  end
  -- Kin who share the surname
  for _, e in pairs(self:KinList()) do
    local _, surname = K.SplitName(e.name)
    if surname and surname:lower() == key then add(e.name, nil, K.RelationLabel(e.rel)) end
  end
  -- Anyone recognised earlier who isn't nearby right now
  for k, m in pairs(house.members) do
    if m.state == "recognised" and not seen[k] then
      seen[k] = true
      recognised[#recognised + 1] = { name = Ambiguate and Ambiguate(m.name, "none") or m.name, raw = m.name, key = k, state = "recognised" }
    end
  end

  local byName = function(a, b)
    if a.mine ~= b.mine then return a.mine and true or false end
    return a.name < b.name
  end
  table.sort(recognised, byName); table.sort(claims, byName)
  return recognised, claims
end


---------------------------------------------------------------------------
-- The page: two tabs built the same way, your house (a family, on a shared
-- surname) and your group (a company, an order, an RP guild).
---------------------------------------------------------------------------
local TOP, PANE_H = 40, 466 - 40

local HOUSE = {
  arms = "Your arms", seal = true, event = "HOUSE",
  Name = function() return K:HouseName() end,
  Record = function() return K:House() end,
  Title = function(name) return "House " .. name end,
  Members = function() return K:HouseMembers() end,
  SetMember = function(key, name, state) K:SetHouseMember(key, name, state) end,
  crestTip = "Click to choose your house's crest.",
  mottoTip = "A few words your house lives by.",
  story = "The house's story",
  recognise = "Recognise as family",
  claims = "Claims to be of this house",
  membersNote = "Anyone can write a house name into their profile. Recognise the people who truly belong; only you see these choices.",
}

local GROUP = {
  arms = "Your banner", seal = false, event = "HOUSE",
  Name = function() return K:GroupName() end,
  Record = function() return K:Group() end,
  Title = function(name) return name end,
  Members = function() return K:GroupMembers() end,
  SetMember = function(key, name, state) K:SetGroupMember(key, name, state) end,
  crestTip = "Click to choose your group's banner.",
  mottoTip = "A few words your group stands for.",
  story = "The group's story",
  recognise = "Recognise as a member",
  claims = "Claims to belong",
  membersNote = "Anyone can write a group name into their profile. Recognise the people who truly belong; only you see these choices.",
}

-- Shared by both tabs: crest, name, motto, story and members.
local function BuildPane(c, kind)
  local pane = CreateFrame("Frame", nil, c)
  pane:SetPoint("TOPLEFT", 0, -TOP)
  pane:SetSize(696, PANE_H)
  pane.kind = kind

  -- Hero: the crest in a gold ring, the name and its motto ----------------------
  local hero = CreateFrame("Frame", nil, pane)
  hero:SetPoint("TOPLEFT")
  hero:SetPoint("TOPRIGHT")
  hero:SetHeight(104)
  pane.hero = hero
  pane.crest = Medallion(hero, 100, true)
  pane.crest:SetPoint("LEFT", 2, 0)
  local ring = pane.crest
  pane.crest:HookScript("OnEnter", function(self) self:SetLit(true) end)
  pane.crest:HookScript("OnLeave", function(self) self:SetLit(false) end)
  pane.crest:SetScript("OnClick", function(self)
    local r = kind.Record()
    ShowPicker(self, r and r.crest, function(path)
      local rec = kind.Record()
      if rec then rec.crest = path; K:Fire(kind.event); K.Journal:RefreshCurrent() end
    end)
  end)
  UI.Tooltip(pane.crest, kind.arms, kind.crestTip)

  pane.title = UI.Text(hero, "", "GameFontNormalHuge", "deskHeading", kind.seal and 560 or 440)
  pane.title:SetPoint("TOPLEFT", ring, "TOPRIGHT", 22, -6)
  pane.title:SetWordWrap(false)
  pane.summary = UI.Text(hero, "", "GameFontHighlightSmall", "deskSubtle")
  pane.summary:SetPoint("TOPLEFT", pane.title, "BOTTOMLEFT", 1, -5)
  pane.motto = UI.Field(hero, "Motto", kind.seal and 400 or 380, 90, function(text)
    local r = kind.Record(); if r then r.motto = text; K:Fire(kind.event) end
  end, "desk")
  pane.motto:SetPoint("TOPLEFT", ring, "TOPRIGHT", 22, -54)
  UI.Tooltip(pane.motto.edit, "Motto", kind.mottoTip)

  local rule = UI.Line(hero)
  rule:SetPoint("TOPLEFT", hero, "BOTTOMLEFT", 0, -10)
  rule:SetPoint("TOPRIGHT", hero, "BOTTOMRIGHT", 0, -10)
  UI:OnTheme(function(t) rule:SetVertexColor(unpack(t.line)) end)

  -- Not in one yet: an empty crest ring, waiting for a name ----------------------
  pane.none = CreateFrame("Frame", nil, pane)
  pane.none:SetAllPoints()
  local nring = Medallion(pane.none, 100)
  nring:SetPoint("TOP", 0, -50)
  nring:SetCrest("Interface\\Icons\\INV_Misc_QuestionMark")
  nring.icon:SetDesaturated(true)
  nring.icon:SetAlpha(0.45)
  nring:SetAlpha(0.7)
  pane.noneTitle = UI.Text(pane.none, "", "GameFontNormalLarge", "deskHeading")
  pane.noneTitle:SetPoint("TOP", nring, "BOTTOM", 0, -20)
  pane.noneText = UI.Text(pane.none, "", "QuestFont", "deskText", 420)
  pane.noneText:SetPoint("TOP", pane.noneTitle, "BOTTOM", 0, -10)
  pane.noneText:SetJustifyH("CENTER")
  pane.noneText:SetSpacing(3)

  -- Details --------------------------------------------------------------
  local bodyTop = 124
  pane.body = CreateFrame("Frame", nil, pane)
  pane.body:SetPoint("TOPLEFT", 0, -bodyTop)
  pane.body:SetPoint("BOTTOMRIGHT", 0, 0)
  local bodyH = PANE_H - bodyTop

  local about = UI.Panel(pane.body)
  about:SetPoint("TOPLEFT", 0, 0)
  about:SetSize(380, bodyH)
  local ah = UI.Section(about, kind.story)
  ah:SetPoint("TOPLEFT", 21, -13)
  pane.desc = UI.TextArea(about, 348, bodyH - 54, 2000, function(text)
    local r = kind.Record(); if r then r.desc = text; K:Fire(kind.event) end
  end)
  pane.desc:SetPoint("TOPLEFT", 16, -38)

  pane.members = UI.List(pane.body, 306, bodyH - 62, 28, "", function(row)
    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetSize(18, 18)
    row.icon:SetPoint("LEFT", 6, 0)
    row.btn = UI.Button(row, "", 82, 18)
    row.btn:SetPoint("RIGHT", -2, 0)
    row.role = UI.Text(row, "", "GameFontHighlightSmall", "subtle")
    row.role:SetPoint("RIGHT", row.btn, "LEFT", -6, 0)
    row.name = UI.Text(row, "", "GameFontHighlight", "text")
    row.name:SetPoint("LEFT", 30, 0)
    row.name:SetPoint("RIGHT", row.role, "LEFT", -4, 0)
    row.name:SetWordWrap(false)
    row.header = UI.Text(row, "", "GameFontNormalSmall", "section")
    row.header:SetPoint("LEFT", 8, -2)
    row:SetScript("OnClick", function(self, button)
      local m = self.item
      if not m or m.header then return end
      if button == "RightButton" and not m.mine then
        UI.Menu(self, function(root)
          root:CreateTitle(m.name)
          root:CreateButton("View profile", function() K:ViewProfile(m.raw or m.name) end)
          if m.state == "recognised" then
            root:CreateButton("Stop recognising", function() kind.SetMember(m.key, m.name, nil) end)
          else
            root:CreateButton(kind.recognise, function() kind.SetMember(m.key, m.name, "recognised") end)
          end
          root:CreateButton("|cffff6060Ignore this claim|r", function() kind.SetMember(m.key, m.name, "ignored") end)
        end)
      else
        K:ViewProfile(m.raw or m.name)
      end
    end)
    row.btn:SetScript("OnClick", function()
      local m = row.item
      kind.SetMember(m.key, m.name, m.state == "recognised" and nil or "recognised")
    end)
  end)
  pane.members:SetPoint("TOPRIGHT", 0, -24)
  local mh = UI.Section(pane.body, "Members", true)
  mh:SetPoint("BOTTOMLEFT", pane.members, "TOPLEFT", 7, 7)
  pane.membersNote = UI.Text(pane.body, kind.membersNote, "GameFontHighlightSmall", "deskSubtle", 300)
  pane.membersNote:SetPoint("TOPLEFT", pane.members, "BOTTOMLEFT", 2, -6)
  return pane
end

local function RefreshPane(pane)
  local kind = pane.kind
  local name, rec = kind.Name(), kind.Record()
  pane.none:SetShown(rec == nil)
  for _, w in ipairs({ pane.body, pane.hero }) do w:SetShown(rec ~= nil) end
  if not rec then return end
  pane.title:SetText(kind.Title(name))
  pane.crest:SetCrest(rec.crest)
  if not pane.motto.edit:HasFocus() then pane.motto.edit:SetText(rec.motto or "") end
  if not pane.desc.edit:HasFocus() then pane.desc.edit:SetText(rec.desc or "") end

  -- Your own characters always belong. Everyone else is a claim until you
  -- recognise them: anyone can type a name into their profile.
  local recognised, claims = kind.Members()
  local summary = #recognised == 1 and "1 member" or (#recognised .. " members")
  if #claims > 0 then summary = summary .. ("  ·  %d %s"):format(#claims, #claims == 1 and "claim" or "claims") end
  pane.summary:SetText(summary)
  local items = {}
  items[#items + 1] = { header = "Recognised" }
  for _, m in ipairs(recognised) do items[#items + 1] = m end
  if #claims > 0 then
    items[#items + 1] = { header = kind.claims }
    for _, m in ipairs(claims) do items[#items + 1] = m end
  end
  pane.members:SetItems(items, function(row, m)
    local isHeader = m.header ~= nil
    row.header:SetShown(isHeader)
    row.icon:SetShown(not isHeader); row.name:SetShown(not isHeader); row.role:SetShown(not isHeader)
    row.btn:SetShown(not isHeader and not m.mine)
    if isHeader then row.header:SetText(m.header) return end
    row.icon:SetTexture(m.mine and K.ICON or (K.Art("IconKin")))
    row.icon:SetDesaturated(m.state ~= "recognised" and not m.mine)
    row.name:SetText(m.name)
    row.role:SetText(m.role or "")
    row.btn:SetText(m.state == "recognised" and "Remove" or "Recognise")
  end)
end

K:RegisterPage({
  id = "house", title = "Community", heading = "Community",
  subtitle = "Your family, the company or order you belong to, and gatherings to share.",
  guide = function(c)
    if c.tab == 3 and K.Guide and K.Guide.PageGuide then return K.Guide.PageGuide("gatherings"), c.gatherings end
  end,

  build = function(c)
    c.tab = 1
    c.tabs = UI.TabBar(c, { "House", "Group", "Gatherings" }, function(i) c.tab = i; K.Journal:RefreshCurrent() end, true)
    c.tabKeys = { "house", "group", "gatherings" }
    c.tabs:SetPoint("TOPLEFT", -10, 2)

    -- House: its name comes from your profile (your surname, to start with)
    local h = BuildPane(c, HOUSE)
    h.noneTitle:SetText("No house yet")
    h.noneText:SetText(K:Compat()
      and "In Total RP 3, edit your Characteristics and add a House name under Additional Information to found a house. Other characters who share that name can join it."
      or ("Set a house name on your Profile page to found a house. " ..
      "Other characters who share that name can join it."))
    local go = UI.Button(h.none, K:Compat() and "Open Total RP 3" or "Go to Profile", 140, 24)
    go:SetPoint("TOP", h.noneText, "BOTTOM", 0, -18)
    go:SetScript("OnClick", function() K:OpenProfileEditor() end)

    -- Group: named right here, with your place in it
    local g = BuildPane(c, GROUP)
    g.noneTitle:SetText("No group yet")
    g.noneText:SetText("A company, an order, an RP guild: anything you belong to that isn't a family. "
      .. "Name one to found it, or use the same name as others to join them.")
    g.join = UI.Field(g.none, "Group name", 240, K.MAX_GROUP_NAME, nil, "desk")
    g.join:SetPoint("TOP", g.noneText, "BOTTOM", -59, -18)
    g.joinBtn = UI.Button(g.none, "Found or join", 110, 23)
    g.joinBtn:SetPoint("BOTTOMLEFT", g.join.edit, "BOTTOMRIGHT", 8, 0)
    local function join()
      local name = strtrim(g.join.edit:GetText() or "")
      if name == "" then return end
      g.join.edit:ClearFocus()
      g.join.edit:SetText("")
      K:SetGroup(name)
      K.Journal:RefreshCurrent()
    end
    g.joinBtn:SetScript("OnClick", join)
    g.join.edit:SetScript("OnEnterPressed", join)

    g.role = UI.Field(g.hero, "Your place in it", 150, K.MAX_GROUP_ROLE, function(text) K:SetGroupRole(text) end, "desk")
    g.role:SetPoint("TOPRIGHT", 0, -54)
    g.role:Info("Your place in it", "What you are in the group, like \"Sergeant\", \"Founder\" or \"Recruit\". "
      .. "It shows beside your name in the members list, and on your tooltip.")
    g.leave = UI.Button(g.hero, "Leave", 70, 22)
    g.leave:SetPoint("TOPRIGHT", 0, -4)
    g.leave:SetScript("OnClick", function()
      K:SetGroup("")
      K.Journal:RefreshCurrent()
    end)
    UI.Tooltip(g.leave, "Leave the group", "Takes it off your profile. Its crest and story stay saved here, "
      .. "so naming it again brings them back.")

    -- Gatherings, built by its own page
    local gf = CreateFrame("Frame", nil, c)
    gf:SetPoint("TOPLEFT", 0, -TOP)
    gf:SetSize(696, PANE_H)
    K.Journal:Embed("gatherings", gf)
    c.gatherings = gf

    c.panes = { h, g, gf }
    -- The house tour lights these
    c.hero, c.none, c.crest, c.motto, c.desc, c.members = h.hero, h.none, h.crest, h.motto, h.desc, h.members
    c.group = g
  end,

  refresh = function(c)
    c.tab = K.Journal:WantedTab(c) or c.tab
    c.tabs:Select(c.tab)
    for i, pane in ipairs(c.panes) do pane:SetShown(i == c.tab) end
    if c.shownTab ~= c.tab then
      if c.shownTab then UI.FadeIn(c.panes[c.tab], 0.2) end
      c.shownTab = c.tab
    end
    local pane = c.panes[c.tab]
    if pane == c.gatherings then K.Journal:RefreshEmbedded(pane) return end
    RefreshPane(pane)
    if pane == c.group and not c.group.role.edit:HasFocus() then c.group.role.edit:SetText(K:GroupRole()) end
  end,
})
