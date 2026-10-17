-- Kinship RP: the icon picker. A Kinship window with a virtualised grid of
-- every macro icon (spells and items, as file IDs), a shelf of recently
-- chosen icons, and a box for typing an icon name or file ID. For everyone:
--   K.IconPicker:Open(anchorFrame, currentIcon, function(icon) ... end)
-- icon is a file ID (number), or a texture path when typed by name and the
-- client can't turn it into an ID.

local ADDON, ns = ...
local K = ns.K
local UI = K.UI
local IP = {}
K.IconPicker = IP

local WHITE = "Interface\\Buttons\\WHITE8X8"
local QUESTION = "Interface\\Icons\\INV_Misc_QuestionMark"
local W, H = 420, 456
local COLS, ROWS, CELL = 10, 8, 36
local GRID_W, GRID_H = COLS * CELL, ROWS * CELL     -- 360 x 288
local CARD_Y, CARD_H = -80, GRID_H + 16             -- the grid's card
local FOOT_Y = CARD_Y - CARD_H - 14                 -- -398
local MAX_RECENT = 40

local FILTERS = {
  { key = "all", label = "All" }, { key = "spells", label = "Spells" },
  { key = "items", label = "Items" }, { key = "recent", label = "Recent" },
}

---------------------------------------------------------------------------
-- Icon lists (built once, on first open)
---------------------------------------------------------------------------
local lists

local function Same(a, b)
  if a == nil or b == nil then return false end
  return tostring(a):lower() == tostring(b):lower()
end

local function Collect(fns, out, seen)
  for _, fn in ipairs(fns) do
    if type(fn) == "function" then
      local t = {}
      local ok, r = pcall(fn, t)
      if ok and type(r) == "table" then t = r end
      for _, v in ipairs(t) do
        local icon = v
        if type(v) == "string" and not v:find("[\\/]") then icon = "Interface\\Icons\\" .. v end
        if (type(icon) == "number" or type(icon) == "string") and not seen[icon] then
          seen[icon] = true
          out[#out + 1] = icon
        end
      end
    end
  end
  return out
end

local function Lists()
  if lists then return lists end
  local spells = Collect({ rawget(_G, "GetLooseMacroIcons"), rawget(_G, "GetMacroIcons") }, {}, {})
  local items = Collect({ rawget(_G, "GetLooseMacroItemIcons"), rawget(_G, "GetMacroItemIcons") }, {}, {})
  local all, seen = {}, {}
  for _, l in ipairs({ spells, items }) do
    for _, v in ipairs(l) do
      if not seen[v] then seen[v] = true; all[#all + 1] = v end
    end
  end
  lists = { all = all, spells = spells, items = items }
  return lists
end

local function Recent()
  if not K.db then return {} end
  K.db.recentIcons = K.db.recentIcons or {}
  return K.db.recentIcons
end

function IP:Remember(icon)
  local r = Recent()
  for i = #r, 1, -1 do if Same(r[i], icon) then table.remove(r, i) end end
  table.insert(r, 1, icon)
  while #r > MAX_RECENT do table.remove(r) end
end

-- Text typed in the box: a file ID, an icon name or an icon path.
local function Resolve(text)
  text = strtrim(text or "")
  if text == "" then return nil end
  local n = tonumber(text)
  if n then return (n > 0 and n == math.floor(n)) and n or nil end
  local name = text:match("^[Ii][Nn][Tt][Ee][Rr][Ff][Aa][Cc][Ee]\\[Ii][Cc][Oo][Nn][Ss]\\([%w_%-]+)$") or text:match("^([%w_%-]+)$")
  if not name then return nil end
  local path = "Interface\\Icons\\" .. name
  local byPath = rawget(_G, "GetFileIDFromPath")
  if type(byPath) == "function" then
    local ok, id = pcall(byPath, path)
    if ok and type(id) == "number" and id > 0 then return id end
    if ok then return nil end   -- the client doesn't know this icon
  end
  return path
end

local function Describe(icon)
  if type(icon) == "number" then return ("Icon %d"):format(icon) end
  if type(icon) == "string" then return icon:match("([^\\/]+)$") or icon end
  return "No icon"
end

---------------------------------------------------------------------------
-- Building the window
---------------------------------------------------------------------------
local function NewCell(parent)
  local b = CreateFrame("Button", nil, parent)
  b:SetSize(CELL - 2, CELL - 2)
  b.glow = b:CreateTexture(nil, "BACKGROUND")
  b.glow:SetAllPoints()
  b.glow:SetTexture(WHITE)
  b.icon = b:CreateTexture(nil, "ARTWORK")
  b.icon:SetPoint("TOPLEFT", 2, -2)
  b.icon:SetPoint("BOTTOMRIGHT", -2, 2)
  b.edge = UI.Border(b)
  b.ring = CreateFrame("Frame", nil, b)
  b.ring:SetPoint("TOPLEFT", -1, 1)
  b.ring:SetPoint("BOTTOMRIGHT", 1, -1)
  b.ring.edge = UI.Border(b.ring)

  function b:Paint(p)
    p = p or UI.Progress(self)
    local t = K:Theme()
    local a = t.accent
    if self.selected then
      self.glow:SetVertexColor(a[1], a[2], a[3], 0.28)
      self.edge:SetColor(a[1], a[2], a[3], 1)
      self.ring.edge:SetColor(a[1], a[2], a[3], 1)
    else
      self.glow:SetVertexColor(a[1], a[2], a[3], 0.14 * p)
      self.edge:SetColor(UI.Mix(t.panelEdge, { a[1], a[2], a[3], 0.9 }, p))
      self.ring.edge:SetColor(0, 0, 0, 0)
    end
    local inset = 2 - p
    self.icon:SetPoint("TOPLEFT", inset, -inset)
    self.icon:SetPoint("BOTTOMRIGHT", -inset, inset)
  end
  b:SetScript("OnEnter", function(self)
    UI.Tween(self, 1, 0.1, function(p) self:Paint(p) end)
    IP:ShowPreview(self.value)
  end)
  b:SetScript("OnLeave", function(self)
    UI.Tween(self, 0, 0.12, function(p) self:Paint(p) end)
    IP:ShowPreview(nil)
  end)
  b:SetScript("OnClick", function(self) IP:Select(self.value) end)
  b:SetScript("OnDoubleClick", function(self) IP:Select(self.value); IP:Commit() end)
  b:Hide()
  return b
end

function IP:Build()
  if self.frame then return end
  local f = UI.Window("KinshipRPIconPicker", "Choose an icon", W, H)
  f:SetFrameStrata("DIALOG")
  f:SetScript("OnShow", function(s) UI.FadeIn(s, 0.15) end)
  f:SetScript("OnHide", function()
    IP.onPick = nil
    if IP.search then IP.search:ClearFocus() end
  end)
  self.frame = f
  local desk = UI.Desk(f)
  desk:SetPoint("TOPLEFT", 1, -35)
  desk:SetPoint("BOTTOMRIGHT", -1, 1)

  -- Filters and the name / ID box
  self.filter = "all"
  f.filters = UI.Segments(f, FILTERS, 64, function(key) IP:SetFilter(key) end)
  f.filters:SetPoint("TOPLEFT", 16, -46)
  local search = UI.Search(f, 124, "Name or ID", function() end)
  search:SetPoint("TOPRIGHT", -16, -46)
  search:SetMaxLetters(80)
  search:SetScript("OnEnterPressed", function(eb)
    local icon = Resolve(eb:GetText())
    if icon then
      IP:Select(icon, true)
      eb:ClearFocus()
    else
      IP:Flash("No icon by that name or ID.")
    end
  end)
  UI.Tooltip(search, "Find an icon", "Type an icon's name (INV_Misc_Book_09) or file ID, then press Enter.")
  self.search = search

  -- The grid, on a card
  local card = UI.Panel(f)
  card:SetPoint("TOPLEFT", 16, CARD_Y)
  card:SetSize(W - 32, CARD_H)
  local sf = CreateFrame("ScrollFrame", nil, card)
  sf:SetPoint("TOPLEFT", 8, -8)
  sf:SetSize(GRID_W, GRID_H)
  local content = CreateFrame("Frame", nil, sf)
  content:SetSize(GRID_W, 1)
  sf:SetScrollChild(content)
  self.sf, self.content = sf, content
  self.cells = {}
  for i = 1, (ROWS + 1) * COLS do self.cells[i] = NewCell(content) end
  self.bar = UI.ScrollBar(sf, false, CELL * 2)
  sf:HookScript("OnVerticalScroll", function() IP:Render() end)

  card.emptyArt = card:CreateTexture(nil, "ARTWORK")
  card.emptyArt:SetTexture(K.Art("IconNote"))
  card.emptyArt:SetSize(56, 56)
  card.emptyArt:SetPoint("CENTER", 0, 26)
  card.emptyArt:SetAlpha(0.75)
  card.empty = UI.Text(card, "", "Body", "subtle", 280)
  card.empty:SetPoint("TOP", card.emptyArt, "BOTTOM", 0, -10)
  card.empty:SetJustifyH("CENTER")
  card.empty:SetSpacing(3)
  self.card = card

  -- Footer: preview, name, buttons
  local pv = CreateFrame("Frame", nil, f)
  pv:SetSize(40, 40)
  pv:SetPoint("TOPLEFT", 16, FOOT_Y)
  pv.bg = pv:CreateTexture(nil, "BACKGROUND")
  pv.bg:SetAllPoints()
  pv.bg:SetColorTexture(0, 0, 0, 0.35)
  pv.icon = pv:CreateTexture(nil, "ARTWORK")
  pv.icon:SetPoint("TOPLEFT", 2, -2)
  pv.icon:SetPoint("BOTTOMRIGHT", -2, 2)
  pv.edge = UI.Border(pv)
  UI:OnTheme(function(t) pv.edge:SetColor(t.ui[1], t.ui[2], t.ui[3], 0.6) end)
  self.preview = pv
  f.selName = UI.Text(f, "", "Header", "deskText", 150)
  f.selName:SetPoint("TOPLEFT", pv, "TOPRIGHT", 10, -3)
  f.selName:SetWordWrap(false)
  f.hint = UI.Text(f, "", "Small", "deskSubtle", 150)
  f.hint:SetPoint("TOPLEFT", f.selName, "BOTTOMLEFT", 0, -4)
  f.hint:SetWordWrap(false)

  local choose = UI.Button(f, "Choose", 96, 26)
  choose:SetPoint("RIGHT", f, "TOPRIGHT", -16, FOOT_Y - 20)
  choose:SetScript("OnClick", function() IP:Commit() end)
  local cancel = UI.Button(f, "Cancel", 76, 26)
  cancel:SetPoint("RIGHT", choose, "LEFT", -6, 0)
  cancel:SetScript("OnClick", function() f:Hide() end)
  f.choose = choose

  UI:OnTheme(function() for _, b in ipairs(IP.cells) do if b:IsShown() then b:Paint() end end end)
end

---------------------------------------------------------------------------
-- Grid
---------------------------------------------------------------------------
function IP:Render()
  local items = self.items or {}
  local offset = math.floor(self.sf:GetVerticalScroll() / CELL)
  for i, b in ipairs(self.cells) do
    local r, col = math.floor((i - 1) / COLS), (i - 1) % COLS
    local row = offset + r
    local v = items[row * COLS + col + 1]
    if v ~= nil then
      b:ClearAllPoints()
      b:SetPoint("TOPLEFT", col * CELL + 1, -(row * CELL) - 1)
      b.value = v
      b.icon:SetTexture(v)
      b.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
      b.selected = Same(v, self.selected)
      b:Paint()
      b:Show()
    else
      b.value = nil
      b:Hide()
    end
  end
end

function IP:IndexOf(icon)
  if icon == nil then return nil end
  for i, v in ipairs(self.items or {}) do if Same(v, icon) then return i end end
end

function IP:ScrollTo(index)
  if not index then return end
  local row = math.floor((index - 1) / COLS)
  local range = math.max(0, self.content:GetHeight() - GRID_H)
  self.sf:SetVerticalScroll(math.max(0, math.min(range, row * CELL - GRID_H / 2 + CELL / 2)))
end

function IP:SetFilter(key)
  self.filter = key
  self.frame.filters:Select(key)
  local items = key == "recent" and Recent() or Lists()[key] or Lists().all
  self.items = items
  self.content:SetHeight(math.max(1, math.ceil(#items / COLS) * CELL))
  self.sf:SetVerticalScroll(0)
  local empty = #items == 0
  self.card.emptyArt:SetShown(empty)
  self.card.empty:SetShown(empty)
  self.card.empty:SetText(key == "recent" and "Icons you choose will gather here, ready for next time."
    or "The game didn't hand over any icons. Type a name or file ID above instead.")
  self:ScrollTo(self:IndexOf(self.selected))
  self:Render()
  self.bar.Update()
  self:ShowPreview(nil)
  if self.frame:IsShown() then UI.FadeIn(self.content, 0.15) end
end

---------------------------------------------------------------------------
-- Selection
---------------------------------------------------------------------------
function IP:ShowPreview(icon)
  local f = self.frame
  local shown = icon
  if shown == nil then shown = self.selected end
  self.preview.icon:SetTexture(shown or QUESTION)
  self.preview.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
  self.preview.icon:SetAlpha(shown and 1 or 0.4)
  f.selName:SetText(Describe(shown))
  if self.flash then return end
  local n = #(self.items or {})
  local count = (BreakUpLargeNumbers and BreakUpLargeNumbers(n) or tostring(n)) .. (n == 1 and " icon" or " icons")
  f.hint:SetText(icon ~= nil and "Double-click to choose" or count)
  f.choose:SetEnabled(self.selected ~= nil)
end

function IP:Flash(text)
  local f = self.frame
  self.flash = true
  f.hint:SetText("|cffe6a04c" .. text .. "|r")
  C_Timer.After(2.5, function() IP.flash = nil; if f:IsShown() then IP:ShowPreview(nil) end end)
end

function IP:Select(icon, reveal)
  if icon == nil then return end
  self.selected = icon
  if reveal then
    local i = self:IndexOf(icon)
    if not i and self.filter ~= "all" then self:SetFilter("all"); i = self:IndexOf(icon) end
    self:ScrollTo(i)
  end
  self:Render()
  self:ShowPreview(nil)
  if SOUNDKIT then PlaySound(SOUNDKIT.U_CHAT_SCROLL_BUTTON or SOUNDKIT.IG_CHARACTER_INFO_TAB) end
end

function IP:Commit()
  local icon, cb = self.selected, self.onPick
  if icon == nil then return end
  self:Remember(icon)
  self.frame:Hide()
  if cb then
    local ok, err = pcall(cb, icon)
    if not ok then K:CaughtError("icon picker", err) end
  end
end

---------------------------------------------------------------------------
-- Public
---------------------------------------------------------------------------
-- Put the window beside anchor (right if there's room, else left).
local function Place(f, anchor)
  f:ClearAllPoints()
  local ok, left, right, top = pcall(function() return anchor:GetLeft(), anchor:GetRight(), anchor:GetTop() end)
  if not ok or not right or not top then f:SetPoint("CENTER") return end
  local s = anchor:GetEffectiveScale() / UIParent:GetEffectiveScale()
  left, right, top = left * s, right * s, top * s
  if right + 10 + W <= UIParent:GetWidth() then
    f:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", right + 10, top + 8)
  else
    f:SetPoint("TOPRIGHT", UIParent, "BOTTOMLEFT", left - 10, top + 8)
  end
end

function IP:Open(anchorFrame, currentIcon, onPick)
  self:Build()
  local f = self.frame
  self.onPick = onPick
  self.selected = currentIcon
  self.flash = nil
  self.search:SetText("")
  Place(f, anchorFrame)
  f:Show()
  f:Raise()
  local start = "all"
  if currentIcon ~= nil and not self:IndexOfIn(Lists().all, currentIcon) and self:IndexOfIn(Recent(), currentIcon) then start = "recent" end
  self:SetFilter(start)
end

function IP:IndexOfIn(list, icon)
  for i, v in ipairs(list) do if Same(v, icon) then return i end end
end

function IP:Close() if self.frame then self.frame:Hide() end end

function IP:IsShown() return self.frame ~= nil and self.frame:IsShown() end

K:On("LOGIN", function() K.db.recentIcons = K.db.recentIcons or {} end)
