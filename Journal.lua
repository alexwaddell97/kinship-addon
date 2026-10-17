-- Kinship RP: the journal window. A grouped sidebar on the left (You, People,
-- Stories, World), a gear for Settings, a page header across the top and the
-- page itself on the desk below it.

local ADDON, ns = ...
local K = ns.K
local UI = K.UI
local J = { pages = {} }
K.Journal = J

-- Every page is laid out for a 696 x 466 content area.
local SIDE, HEAD, PAD = 176, 72, 14
local CW, CH = 696, 466
J.W, J.H = SIDE + CW + 2 * PAD, HEAD + CH + 12 + PAD

-- Sidebar icons: Kinship medallions, your portrait, or a round-cropped game icon.
-- A page can also bring its own (def.icon).
local ICONS = {
  profile = "portrait", chronicle = "IconMilestone", kin = "IconKin", directory = "IconPlace",
  house = { "Interface\\Icons\\INV_Shield_05", round = true }, gatherings = "IconFire",
  warfront = "IconDungeon", letters = "IconNote",
}

-- Sidebar groups, in order. A page names its group (def.group), or gets one here.
local GROUPS = { "You", "People", "Stories", "World" }
local DEFAULT_GROUP = {
  profile = "You", persona = "You", companions = "You",
  directory = "People", kin = "People", house = "People", letters = "People",
  chronicle = "Stories", quests = "Stories", gatherings = "Stories",
  warfront = "World", inventory = "World",
}
-- 12 pages in 4 groups: 64 + 12*28 + 4*20 + 3*4 = 492px, clear of the Settings row at the foot.
local ROW, GROUP_GAP = 28, 20

local function NavIcon(page)
  local icon = page.icon or ICONS[page.id] or "IconNote"
  if type(icon) == "string" and icon:find("^Icon") then return K.Art(icon) end
  return icon
end

-- Pages register themselves:
-- { id, title, heading, subtitle, group, icon, hidden, enabled, build(content), refresh(content) }
-- hidden = reachable by id (J:Open) but not listed in the sidebar (Settings).
-- enabled = fn() -> false while the page's feature is switched off; it then
-- leaves the sidebar and can't be opened (fire "EXTENDED" when it changes).
function K:RegisterPage(def) table.insert(J.pages, def) end

local function Group(page) return page.group or DEFAULT_GROUP[page.id] or "World" end

local function Enabled(page)
  if page and page.trp3 == "hide" and K:Compat() then return false end   -- Total RP 3 has its own
  if not page or not page.enabled then return page ~= nil end
  local ok, on = K.Try("journal " .. tostring(page.id), page.enabled)
  return not ok or on ~= false
end

function J:Build()
  if self.frame then return end
  local f = UI.Window("KinshipRPJournal", "Kinship", self.W, self.H, { bare = true })
  self.frame = f

  -- Sidebar --------------------------------------------------------------
  local side = CreateFrame("Frame", nil, f)
  side:SetPoint("TOPLEFT")
  side:SetPoint("BOTTOMLEFT")
  side:SetWidth(SIDE)
  side.bg = side:CreateTexture(nil, "BACKGROUND")
  side.bg:SetAllPoints()
  side.line = UI.Line(side, true)
  side.line:SetPoint("TOPRIGHT")
  side.line:SetPoint("BOTTOMRIGHT")
  UI:OnTheme(function(t)
    side.bg:SetColorTexture(unpack(t.bar))
    side.line:SetVertexColor(unpack(t.line))
  end)

  local logo = side:CreateTexture(nil, "ARTWORK")
  logo:SetSize(32, 32)
  logo:SetPoint("TOPLEFT", 16, -18)
  logo:SetTexture(K.ICON)
  local name = UI.Text(side, "Kinship", "Title", "deskHeading")
  name:SetPoint("TOPLEFT", logo, "TOPRIGHT", 10, 0)
  local tag = UI.Text(side, "Roleplay journal", "Small", "deskSubtle")
  tag:SetPoint("TOPLEFT", name, "BOTTOMLEFT", 0, -3)

  -- Settings sits at the foot of the sidebar, apart from the pages, under a hairline.
  local footLine = UI.Line(side)
  footLine:SetPoint("BOTTOMLEFT", 14, 50)
  footLine:SetPoint("BOTTOMRIGHT", -14, 50)
  UI:OnTheme(function(t) footLine:SetVertexColor(unpack(t.line)) end)
  local gear = UI.NavButton(side, "Settings", { "Interface\\Icons\\INV_Misc_Gear_01", round = true }, SIDE - 1, function()
    local i = J:Index("settings")
    if i then J:Show(i) end
  end)
  gear:SetPoint("BOTTOMLEFT", 0, 10)
  gear:SetHeight(ROW + 4)
  self.gear = gear

  -- The list, grouped under small headings (placed by J:LayoutNav)
  self.nav, self.navGroups = {}, {}
  for _, group in ipairs(GROUPS) do
    local g = { buttons = {} }
    for i, page in ipairs(self.pages) do
      if not page.hidden and Group(page) == group then
        if not g.header then
          g.header = UI.Text(side, group:upper(), "Label", "deskSubtle")
          g.header:SetAlpha(0.8)
        end
        local b = UI.NavButton(side, page.title, NavIcon(page), SIDE - 1, function() J:Show(i) end)
        b:SetHeight(ROW)
        b.id, b.index = page.id, i
        if page.id == "letters" then
          b.badge = UI.Chip(b, nil, true)
          b.badge:SetPoint("RIGHT", -12, 0)
        end
        self.nav[#self.nav + 1] = b
        g.buttons[#g.buttons + 1] = b
      end
    end
    self.navGroups[#self.navGroups + 1] = g
  end
  self:LayoutNav()

  UI:OnTheme(function() J:RefreshCurrent() end)

  -- Page header ------------------------------------------------------------
  f.heading = UI.Text(f, "", "Huge", "deskHeading")
  f.heading:SetPoint("TOPLEFT", SIDE + 20, -16)
  f.sub = UI.Text(f, "", "Small", "deskSubtle", CW - 40)
  f.sub:SetPoint("TOPLEFT", f.heading, "BOTTOMLEFT", 1, -5)
  local rule = UI.Line(f)
  rule:SetPoint("TOPLEFT", SIDE, -HEAD)
  rule:SetPoint("TOPRIGHT", 0, -HEAD)
  UI:OnTheme(function(t) rule:SetVertexColor(unpack(t.line)) end)

  f.desk = UI.Desk(f)
  f.desk:SetPoint("TOPLEFT", SIDE + 1, -HEAD - 1)
  f.desk:SetPoint("BOTTOMRIGHT", -1, 1)

  -- Each page is built the first time it's shown (see J:Ensure).
  self.content = {}
  for i in ipairs(self.pages) do
    local c = CreateFrame("Frame", nil, f)
    c:SetPoint("TOPLEFT", SIDE + PAD, -HEAD - 12)
    c:SetSize(CW, CH)
    c:Hide()
    self.content[i] = c
  end
end

-- Stack the sidebar: switched-off pages drop out, and so does a heading with nothing under it.
function J:LayoutNav()
  if not self.navGroups then return end
  local y = -HEAD + 8
  for _, g in ipairs(self.navGroups) do
    local any = false
    for _, b in ipairs(g.buttons) do
      local on = Enabled(self.pages[b.index])
      if on and not any then
        g.header:ClearAllPoints()
        g.header:SetPoint("TOPLEFT", 18, y - 6)
        y = y - GROUP_GAP
        any = true
      end
      b:SetShown(on)
      if on then
        b:ClearAllPoints()
        b:SetPoint("TOPLEFT", 0, y)
        y = y - ROW
      end
    end
    if g.header then g.header:SetShown(any) end
    if any then y = y - 4 end
  end
end

-- The first page that's switched on (the fallback when one is switched off).
function J:FirstEnabled()
  for i, p in ipairs(self.pages) do
    if not p.hidden and Enabled(p) then return i end
  end
  return 1
end

-- Build a page if it hasn't been yet. A page that fails to build shows a
-- short apology instead, and every other page carries on working.
function J:Ensure(i)
  local c, page = self.content[i], self.pages[i]
  if not c or not page then return false end
  if c.built then return c.ok end
  c.built = true
  local ok, err = pcall(page.build, c)
  c.ok = ok
  if ok then return true end
  K:Print(("The %s page couldn't open. Please report this: %s"):format(page.title or page.id, tostring(err)))
  for _, child in ipairs({ c:GetChildren() }) do child:Hide() end
  for _, region in ipairs({ c:GetRegions() }) do region:Hide() end
  local card = UI.Panel(c)
  card:SetAllPoints()
  local art = card:CreateTexture(nil, "ARTWORK")
  art:SetTexture(K.Art("IconNote"))
  art:SetSize(64, 64)
  art:SetPoint("CENTER", 0, 40)
  art:SetAlpha(0.8)
  local text = UI.Text(card, "This page ran into a problem and couldn't open. The rest of your journal still works. "
    .. "The details are in your chat window.", "Read", "subtle", 380)
  text:SetPoint("TOP", art, "BOTTOM", 0, -12)
  text:SetJustifyH("CENTER")
  text:SetSpacing(3)
  return false
end

-- Icons and badges that follow your data: portrait, house crest, unread letters.
function J:RefreshNav()
  if not self.nav then return end
  for _, b in ipairs(self.nav) do
    if b.RefreshIcon then b:RefreshIcon() end
    if b.id == "house" then
      local h = K:House()
      b.icon:SetTexture(h and h.crest or "Interface\\Icons\\INV_Shield_05")
    elseif b.badge then
      local n = K.Letters:Unread()
      b.badge:Set(n > 0 and tostring(n) or nil, K:Theme().ui)
    end
  end
end

function J:Index(id)
  for i, p in ipairs(self.pages) do if p.id == id then return i end end
end

function J:Show(i)
  if not Enabled(self.pages[i]) then i = self:FirstEnabled() end
  local changed = self.current ~= i
  self.current = i
  self:Ensure(i)
  for n, c in ipairs(self.content) do c:SetShown(n == i) end
  for _, b in ipairs(self.nav) do b:SetSelected(b.index == i) end
  local page = self.pages[i]
  self.gear:SetSelected(page.id == "settings")
  self.frame.heading:SetText(page.heading or page.title)
  self.frame.sub:SetText(page.subtitle or "")
  self:Refresh(i)
  if changed then UI.FadeIn(self.content[i], 0.25) end
end

-- Run a page's refresh, reporting errors when /kin debug is on.
function J:Refresh(i)
  local page = self.pages[i]
  if not page or not page.refresh or not self.content[i].ok then return end
  local ok, err = pcall(page.refresh, self.content[i])
  if not ok then K:CaughtError(page.id, err) end
end

function J:Open(id)
  self:Build()
  local i = self:Index(id)
  if i and not Enabled(self.pages[i]) then
    K:Print(("%s is switched off (Settings > Extended features)."):format(self.pages[i].title or id))
    i = nil
  end
  self.frame:Show()
  self:RefreshNav()
  self:Show(i or self.current or 1)
end

function J:Toggle(id)
  self:Build()
  if self.frame:IsShown() and (not id or self.pages[self.current].id == id) then
    self.frame:Hide()
  else
    self:Open(id)
  end
end

function J:RefreshCurrent()
  if self.frame and self.frame:IsShown() and self.current then self:Refresh(self.current) end
end

-- True when the journal is open on this page (for features refreshing on their own events).
function J:IsShowing(id)
  return self.frame and self.frame:IsShown() and self.current and self.pages[self.current].id == id
end

for _, e in ipairs({ "PROFILE", "CHRONICLE", "KIN", "GATHERINGS" }) do
  K:On(e, function() J:RefreshCurrent() end)
end
for _, e in ipairs({ "LETTERS", "HOUSE", "PROFILE", "IGNORE" }) do
  K:On(e, function() J:RefreshNav() end)
end

-- An Extended switch changed: re-stack the sidebar and leave a page that went away.
K:On("EXTENDED", function()
  if not J.frame then return end
  J:LayoutNav()
  if J.current and not Enabled(J.pages[J.current]) then
    if J.frame:IsShown() then J:Show(J:FirstEnabled()) else J.current = nil end
  else
    J:RefreshCurrent()
  end
end)
