-- Kinship RP: the roleplay satchel. Your Kinship items in a small bag of
-- their own beside your game bags: a button by the bag bar, and a window
-- that opens and closes with your bags, docked to their side.
--
-- It takes on the look of whichever bags you use:
--   ellesmere  EllesmereUI Bags: its textured dark window, fine borders, flat
--              34px slots with quality edges, its font; pinned flush to its
--              window (moving and scaling with it) and filtered by its search box
--   blizzard   the game's own bags: the game's bag window, with the satchel as
--              its portrait, the game's item buttons, docked beside the bags,
--              filtered by the game's bag search
--   kinship    Kinship's own look, for anything else
-- Same slots everywhere: hover for the tooltip, right-click to use, drag to
-- move or merge, shift-click to split. /kin satchel, or the "Roleplay
-- satchel" key binding, opens it on its own.
--
-- Search and Stashes open a small stash pane on the satchel's other side, in
-- the same look: the stashes found nearby or your own, and what's in them.
-- The button by the bag bar copies the bag bar's own buttons, including
-- EllesmereUI's skin of them when that's on, and follows the bar's
-- visibility: hidden when the bar is hidden, faded when it's faded (as with
-- EllesmereUI's mouseover and combat settings for the bag bar).
--
-- The minimise button narrows the satchel to a thin strip of the same
-- height beside your bags. Minimised, it still comes up with your bags but
-- stays out of the way until you click it (the satchel button, the key
-- binding and /kin satchel open it in full too).
--
-- Kinship items are Kinship's own records, not game items, so they live here
-- rather than in the game's bags (and are safe from vendors and the bank).
-- Nothing is put inside another addon's frames or the game's protected bag
-- bar: the satchel only anchors beside them, and the button is placed by
-- reading where the bag bar is.

local ADDON, ns = ...
local K = ns.K
local UI = K.UI
local I = K.Items
local SA = { frames = {}, panes = {}, query = "" }
K.Satchel = SA

local ICON = "Interface\\Icons\\INV_Misc_Bag_08"
local STASH_ICON = "Interface\\Icons\\INV_Box_02"
local WHITE = "Interface\\Buttons\\WHITE8X8"

local function S() return K.db.settings end
local function On() return K:ExtOn("inventory") end
local function EUI() return _G.EllesmereUI end

-- Which bags are in use, and which look the satchel takes.
local function Look()
  if _G.EUI_MainBagFrame then return "ellesmere" end
  if _G.ContainerFrameCombinedBags or _G.ContainerFrame1 then return "blizzard" end
  return "kinship"
end

-- The bags that are open now, if any.
local function OpenBags()
  local eui = _G.EUI_MainBagFrame
  if eui and eui:IsShown() then return eui end
  for _, name in ipairs({ "ContainerFrameCombinedBags", "ContainerFrame1" }) do
    local fr = _G[name]
    if fr and fr:IsShown() then return fr end
  end
end

local function EFont()
  local E = EUI()
  return E and E.GetFontPath and E.GetFontPath("bags") or STANDARD_TEXT_FONT
end

local function EAccent()
  local E = EUI()
  if E and E.GetAccentColor then
    local ok, r, g, b = pcall(E.GetAccentColor)
    if ok and r then return r, g, b end
  end
  return 0.047, 0.824, 0.616
end

local function Tip(b, title, text)
  b:HookScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_TOP")
    GameTooltip:SetText(title, 1, 0.82, 0)
    if text then GameTooltip:AddLine(text, 1, 1, 1, true) end
    GameTooltip:Show()
  end)
  b:HookScript("OnLeave", function() GameTooltip:Hide() end)
end

local function MinTip(b)
  b:HookScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_TOP")
    GameTooltip:SetText("Minimise", 1, 0.82, 0)
    GameTooltip:AddLine("Narrow it to a thin strip beside your bags. It still comes up with them, out of the way, until you click it.", 1, 1, 1, true)
    GameTooltip:Show()
  end)
  b:HookScript("OnLeave", function() GameTooltip:Hide() end)
end

-- A drawn minus for the flat looks.
local function MinButton(parent, size, colour)
  local b = CreateFrame("Button", nil, parent)
  b:SetSize(size, size)
  local len = math.floor(size * 0.5)
  b.h = b:CreateTexture(nil, "ARTWORK"); b.h:SetTexture(WHITE); b.h:SetSize(len, 2); b.h:SetPoint("CENTER")
  function b:Paint()
    local r, g, bl = colour()
    local a = self.hover and 1 or 0.7
    self.h:SetVertexColor(r, g, bl, a)
  end
  function b:SetState(collapsed)
    self.collapsed = collapsed
  end
  b:SetScript("OnEnter", function(self) self.hover = true; self:Paint() end)
  b:SetScript("OnLeave", function(self) self.hover = nil; self:Paint() end)
  b:SetScript("OnClick", function() SA:SetCollapsed(true) end)
  MinTip(b)
  b:SetState(false)
  b:Paint()
  return b
end

-- The game's own condense / expand button, beside the window's close button.
local function BlizzardMinButton(parent)
  local b = CreateFrame("Button", nil, parent)
  local atlas = C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo("RedButton-Condense")
  b.atlas = atlas and true or false
  b:SetSize(atlas and 24 or 32, atlas and 24 or 32)
  function b:SetState(collapsed)
    self.collapsed = collapsed
    if self.atlas then
      local base = collapsed and "RedButton-Expand" or "RedButton-Condense"
      self:SetNormalAtlas(base)
      self:SetPushedAtlas(base .. "-Pressed")
      self:SetHighlightAtlas("RedButton-Highlight", "ADD")
    else
      local base = collapsed and "Interface\\Buttons\\UI-Panel-BiggerButton-" or "Interface\\Buttons\\UI-Panel-SmallerButton-"
      self:SetNormalTexture(base .. "Up")
      self:SetPushedTexture(base .. "Down")
      self:SetHighlightTexture("Interface\\Buttons\\UI-Panel-MinimizeButton-Highlight", "ADD")
    end
  end
  b:SetScript("OnClick", function() SA:SetCollapsed(true) end)
  MinTip(b)
  b:SetState(false)
  return b
end

---------------------------------------------------------------------------
-- Slots for each look. Each has :SetItem(def, count, unknown), :SetMatch(on)
-- and :Pop(); the satchel wires the same clicks and drags to all of them.
---------------------------------------------------------------------------
local function TooltipScripts(b)
  b:SetScript("OnEnter", function(self)
    if self.hl then self.hl:Show() end
    if self.def or self.unknown then I:ShowTooltip(self, self.def, self.n, "ANCHOR_LEFT") end
  end)
  b:SetScript("OnLeave", function(self)
    if self.hl then self.hl:Hide() end
    GameTooltip:Hide()
  end)
end

local function KinshipSlot(parent, size)
  local s = I.NewSlot(parent, size)
  s.tooltipAnchor = "ANCHOR_LEFT"
  function s:SetMatch(on) self:SetAlpha(on and 1 or 0.3) end
  return s
end

-- EllesmereUI Bags' slot: a flat icon with a 1px border inside its edge, grey
-- when plain and coloured by quality from Uncommon up, and an 8% white hover.
local function EllesmereSlot(parent, size)
  local b = CreateFrame("Button", nil, parent)
  b:SetSize(size, size)
  b.bg = b:CreateTexture(nil, "BACKGROUND")
  b.bg:SetAllPoints()
  b.bg:SetColorTexture(0, 0, 0, 0.35)
  b.icon = b:CreateTexture(nil, "ARTWORK")
  b.icon:SetAllPoints()
  b.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
  b.hl = b:CreateTexture(nil, "OVERLAY", nil, 1)
  b.hl:SetAllPoints()
  b.hl:SetColorTexture(1, 1, 1, 0.08)
  b.hl:Hide()
  b.edges = {}
  for _, side in ipairs({ "TOP", "BOTTOM", "LEFT", "RIGHT" }) do
    local t = b:CreateTexture(nil, "OVERLAY", nil, 2)
    t:SetTexture(WHITE)
    if side == "TOP" or side == "BOTTOM" then
      t:SetPoint(side .. "LEFT"); t:SetPoint(side .. "RIGHT"); t:SetHeight(1)
    else
      t:SetPoint("TOP" .. side); t:SetPoint("BOTTOM" .. side); t:SetWidth(1)
    end
    b.edges[#b.edges + 1] = t
  end
  b.count = b:CreateFontString(nil, "OVERLAY")
  b.count:SetFont(EFont(), 11, "OUTLINE")
  b.count:SetPoint("BOTTOMRIGHT", -2, 2)
  function b:SetItem(def, n, unknown)
    self.def, self.n, self.unknown = def, n, (not def and unknown) and true or nil
    local has = def ~= nil or self.unknown
    self.icon:SetTexture(has and (def and I.IconTexture(def.icon) or I.DEFAULT_ICON) or nil)
    self.icon:SetShown(has)
    self.count:SetText((n and n > 1) and tostring(n) or "")
    local q = def and def.quality
    local r, g, bl = 0.25, 0.25, 0.25
    if q and q >= 2 then local c = I.Quality(q).color; r, g, bl = c[1], c[2], c[3] end
    for _, t in ipairs(self.edges) do t:SetColorTexture(r, g, bl, 1) end
  end
  function b:SetMatch(on) self:SetAlpha(on and 1 or 0.25) end
  function b:Pop() end
  TooltipScripts(b)
  return b
end

-- The game's own item button: its art, count, quality border and empty-slot look.
local function BlizzardSlot(parent, size)
  local ok, b = pcall(CreateFrame, "ItemButton", nil, parent, "ItemButtonTemplate")
  if not ok or not b or not b.SetItemButtonTexture then return KinshipSlot(parent, size) end
  b:SetSize(size, size)
  b.empty = b:CreateTexture(nil, "BACKGROUND", nil, -1)
  b.empty:SetAllPoints()
  b.empty:SetTexture("Interface\\PaperDoll\\UI-Backpack-EmptySlot")
  function b:SetItem(def, n, unknown)
    self.def, self.n, self.unknown = def, n, (not def and unknown) and true or nil
    local has = def ~= nil or self.unknown
    pcall(self.SetItemButtonTexture, self, has and (def and I.IconTexture(def.icon) or I.DEFAULT_ICON) or nil)
    if self.SetItemButtonCount then pcall(self.SetItemButtonCount, self, n or 0) end
    if self.SetItemButtonQuality then pcall(self.SetItemButtonQuality, self, def and def.quality or nil) end
    self.empty:SetShown(not has)
  end
  function b:SetMatch(on)
    if self.SetMatchesSearch then pcall(self.SetMatchesSearch, self, on) else self:SetAlpha(on and 1 or 0.3) end
  end
  function b:Pop() end
  TooltipScripts(b)
  return b
end

---------------------------------------------------------------------------
-- The three looks: a window, text, buttons, tabs, list rows and slots in
-- each. The satchel and its stash pane are both built from these.
--   New(name, w, h, title, icon, onClose) -> frame, with f.top (where the
--   content starts, below the title) and f.head (the title bar, if any)
---------------------------------------------------------------------------
local KIT = {}

-- EllesmereUI Bags
KIT.ellesmere = { cell = 34, gap = 4, pad = 8, dock = 2, slot = EllesmereSlot }
do
  local L = KIT.ellesmere
  function L.New(name, w, h, title, _, onClose)
    local f = CreateFrame("Frame", name, UIParent)
    f:SetSize(w, h)
    f.bg = f:CreateTexture(nil, "BACKGROUND", nil, 0)
    f.bg:SetAllPoints()
    f.bg:SetTexture("Interface\\AddOns\\EllesmereUI\\media\\modern_blizz.png")
    f.shade = f:CreateTexture(nil, "BACKGROUND", nil, 1)
    f.shade:SetAllPoints()
    f.shade:SetColorTexture(0, 0, 0, 0.25)
    local E = EUI()
    if not (E and E.PanelPP and E.PanelPP.CreateBorder and pcall(E.PanelPP.CreateBorder, f, 0.1, 0.1, 0.1, 1, 1, "OVERLAY", 7)) then
      f.edge = UI.Border(f); f.edge:SetColor(0.1, 0.1, 0.1, 1)
    end
    local head = CreateFrame("Frame", nil, f)
    head:SetPoint("TOPLEFT", 1, -1); head:SetPoint("TOPRIGHT", -1, -1); head:SetHeight(35)
    head.bg = head:CreateTexture(nil, "BACKGROUND"); head.bg:SetAllPoints(); head.bg:SetColorTexture(0, 0, 0, 0.5)
    f.head = head
    f.title = L.Text(head, 13, "title")
    f.title:SetPoint("LEFT", 8, 0)
    f.title:SetText(title)
    f.close = UI.CloseButton(head, false, 18)
    f.close:SetPoint("RIGHT", -6, 0)
    f.close:SetScript("OnClick", onClose)
    f.top = -36
    return f
  end
  function L.Text(parent, size, role)
    local fs = parent:CreateFontString(nil, "OVERLAY")
    fs:SetFont(EFont(), size or 11, "")
    fs:SetShadowOffset(1, -1)
    fs:SetJustifyH("LEFT")
    if role == "dim" then fs:SetTextColor(0.6, 0.6, 0.6) else fs:SetTextColor(1, 1, 1) end
    return fs
  end
  -- Small flat buttons, as EllesmereUI draws its own
  function L.Button(parent, label, w, h, fn)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(w, h)
    b.bg = b:CreateTexture(nil, "BACKGROUND"); b.bg:SetAllPoints(); b.bg:SetColorTexture(0.12, 0.12, 0.12, 0.9)
    b.edge = UI.Border(b); b.edge:SetColor(0.25, 0.25, 0.25, 1)
    b.text = L.Text(b, 11); b.text:SetPoint("CENTER"); b.text:SetText(label)
    b:SetScript("OnEnter", function(self) self.bg:SetColorTexture(0.2, 0.2, 0.2, 0.95) end)
    b:SetScript("OnLeave", function(self) self.bg:SetColorTexture(0.12, 0.12, 0.12, 0.9) end)
    b:SetScript("OnClick", fn)
    function b:SetText(t) self.text:SetText(t) end
    b:SetMotionScriptsWhileDisabled(true)
    hooksecurefunc(b, "SetEnabled", function(self, on) self.text:SetAlpha(on and 1 or 0.4) end)
    return b
  end
  -- Tabs: flat buttons, the chosen one lit and underlined in the accent colour.
  function L.Tabs(parent, items, w, onSelect)
    local holder = CreateFrame("Frame", nil, parent)
    holder:SetSize(w, 22)
    local bw = (w - 4 * (#items - 1)) / #items
    holder.tabs = {}
    for i, it in ipairs(items) do
      local b = L.Button(holder, it.label, bw, 22, function() onSelect(it.key) end)
      b:SetPoint("LEFT", (i - 1) * (bw + 4), 0)
      b.key = it.key
      b.line = b:CreateTexture(nil, "OVERLAY")
      b.line:SetPoint("BOTTOMLEFT", 1, 1); b.line:SetPoint("BOTTOMRIGHT", -1, 1); b.line:SetHeight(2)
      holder.tabs[i] = b
    end
    function holder:Select(key)
      local r, g, bl = EAccent()
      for _, b in ipairs(self.tabs) do
        local on = b.key == key
        b.line:SetColorTexture(r, g, bl, 1)
        b.line:SetShown(on)
        b.text:SetTextColor(on and 1 or 0.65, on and 1 or 0.65, on and 1 or 0.65)
      end
    end
    return holder
  end
  function L.PaintRow(row, hover, sel)
    if sel then local r, g, b = EAccent(); row.bg:SetColorTexture(r, g, b, 0.22)
    elseif hover then row.bg:SetColorTexture(1, 1, 1, 0.08)
    else row.bg:SetColorTexture(0, 0, 0, 0.3) end
  end
end

-- The game's own bags
KIT.blizzard = { cell = 37, gap = 5, pad = 12, dock = 4, slot = BlizzardSlot, template = true }
do
  local L = KIT.blizzard
  function L.New(name, w, h, title, icon, onClose)
    local ok, f = pcall(CreateFrame, "Frame", name, UIParent, "ButtonFrameTemplate")
    if not ok or not f then return nil end
    f:SetSize(w, h)
    local portrait = f.PortraitContainer and f.PortraitContainer.portrait or f.portrait
    if portrait then
      if SetPortraitToTexture then pcall(SetPortraitToTexture, portrait, icon) else portrait:SetTexture(icon) end
    end
    f.title = (f.TitleContainer and f.TitleContainer.TitleText) or f.TitleText
    if f.title then f.title:SetText(title) end
    if f.CloseButton then f.CloseButton:SetScript("OnClick", onClose) end
    if ButtonFrameTemplate_HideButtonBar then pcall(ButtonFrameTemplate_HideButtonBar, f) end
    f.top = -58
    return f
  end
  function L.Text(parent, _, role)
    local fs = parent:CreateFontString(nil, "OVERLAY",
      role == "title" and "GameFontNormalSmall" or (role == "dim" and "GameFontDisableSmall" or "GameFontHighlightSmall"))
    fs:SetJustifyH("LEFT")
    return fs
  end
  function L.Button(parent, label, w, h, fn)
    local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    b:SetSize(w, h)
    b:SetText(label)
    b:SetScript("OnClick", fn)
    b:SetMotionScriptsWhileDisabled(true)
    return b
  end
  -- Tabs: the game's panel buttons, the chosen one held lit.
  function L.Tabs(parent, items, w, onSelect)
    local holder = CreateFrame("Frame", nil, parent)
    holder:SetSize(w, 22)
    local bw = (w - 4 * (#items - 1)) / #items
    holder.tabs = {}
    for i, it in ipairs(items) do
      local b = L.Button(holder, it.label, bw, 22, function() onSelect(it.key) end)
      b:SetPoint("LEFT", (i - 1) * (bw + 4), 0)
      b.key = it.key
      holder.tabs[i] = b
    end
    function holder:Select(key)
      for _, b in ipairs(self.tabs) do
        if b.key == key then b:LockHighlight(); b:GetFontString():SetTextColor(1, 1, 1)
        else b:UnlockHighlight(); b:GetFontString():SetTextColor(1, 0.82, 0) end
      end
    end
    return holder
  end
  function L.PaintRow(row, hover, sel)
    if sel then row.bg:SetColorTexture(1, 0.82, 0, 0.18)
    elseif hover then row.bg:SetColorTexture(1, 1, 1, 0.08)
    else row.bg:SetColorTexture(0, 0, 0, 0.25) end
  end
end

-- Kinship's own look
KIT.kinship = { cell = 36, gap = 4, pad = 14, dock = 8, slot = KinshipSlot }
do
  local L = KIT.kinship
  function L.New(name, w, h, title, icon, onClose)
    local f = CreateFrame("Frame", name, UIParent)
    f:SetSize(w, h)
    f.bg = f:CreateTexture(nil, "BACKGROUND")
    f.bg:SetAllPoints()
    f.bg:SetTexture(WHITE)
    f.edge = UI.Border(f)
    UI:OnTheme(function(t)
      f.bg:SetVertexColor(unpack(t.chrome))
      f.edge:SetColor(unpack(t.chromeEdge))
    end)
    f.icon = f:CreateTexture(nil, "ARTWORK")
    f.icon:SetTexture(icon)
    f.icon:SetSize(24, 24)
    f.icon:SetPoint("TOPLEFT", 14, -11)
    f.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    UI.Round(f.icon)
    f.title = UI.Text(f, title, "Header", "deskHeading", w - 90)
    f.title:SetPoint("TOPLEFT", f.icon, "TOPRIGHT", 8, 1)
    f.close = UI.CloseButton(f, false, 20)
    f.close:SetPoint("TOPRIGHT", -8, -10)
    f.close:SetScript("OnClick", onClose)
    f.top = -46
    return f
  end
  function L.Text(parent, _, role)
    return UI.Text(parent, "", role == "title" and "Body" or "Small", role == "dim" and "deskSubtle" or "deskText")
  end
  function L.Button(parent, label, w, h, fn)
    local b = UI.Button(parent, label, w, h)
    b:SetScript("OnClick", fn)
    return b
  end
  function L.Tabs(parent, items, w, onSelect)
    return UI.Segments(parent, items, math.floor(w / #items), onSelect)
  end
  function L.PaintRow(row, hover, sel)
    local t = K:Theme()
    local u = t.ui
    if sel then row.bg:SetColorTexture(u[1], u[2], u[3], 0.22)
    elseif hover then row.bg:SetColorTexture(u[1], u[2], u[3], 0.10)
    else row.bg:SetColorTexture(0, 0, 0, t.light and 0.06 or 0.18) end
  end
end

---------------------------------------------------------------------------
-- Building a satchel window in one look
---------------------------------------------------------------------------
local ghost
local function Ghost()
  if ghost then return ghost end
  ghost = CreateFrame("Frame", nil, UIParent)
  ghost:SetSize(36, 36)
  ghost:SetFrameStrata("TOOLTIP")
  ghost.icon = ghost:CreateTexture(nil, "ARTWORK")
  ghost.icon:SetAllPoints()
  ghost.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
  ghost.icon:SetAlpha(0.85)
  ghost:SetScript("OnUpdate", function(self)
    local x, y = GetCursorPosition()
    local s = UIParent:GetEffectiveScale()
    self:ClearAllPoints()
    self:SetPoint("CENTER", UIParent, "BOTTOMLEFT", x / s, y / s)
  end)
  ghost:Hide()
  return ghost
end

-- The slots, laid out on f from (x0, y0), with the same handling in every look.
local function MakeCells(f, makeSlot, cols, cell, gap, x0, y0)
  f.cells = {}
  for i = 1, I.SLOTS do
    local s = makeSlot(f, cell)
    s:SetPoint("TOPLEFT", x0 + ((i - 1) % cols) * (cell + gap), y0 - math.floor((i - 1) / cols) * (cell + gap))
    s.index = i
    s:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    s:RegisterForDrag("LeftButton")
    s:SetScript("OnClick", function(self, button)
      local slot = I:Slot(self.index)
      if not slot then return end
      if button == "RightButton" and K.TradeWindow and K.TradeWindow:TryAdd(slot.def) then
        return
      elseif button == "RightButton" then
        I:Use(self.index)
      elseif K.ItemLinks and K.ItemLinks:TryLink(slot.def) then
        return
      elseif IsShiftKeyDown() and slot.count > 1 then
        local to = I:Split(self.index, math.floor(slot.count / 2))
        if to then f.cells[to]:Pop() end
      end
      SA:Refresh()
    end)
    s:SetScript("OnDragStart", function(self)
      local slot = I:Slot(self.index)
      if not slot then return end
      f.dragFrom = self.index
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
      local from = f.dragFrom
      f.dragFrom = nil
      if not from then return end
      for j, c in ipairs(f.cells) do
        if j ~= from and c:IsMouseOver() then
          if I:Move(from, j) then
            if SOUNDKIT and SOUNDKIT.IG_ABILITY_ICON_DROP then PlaySound(SOUNDKIT.IG_ABILITY_ICON_DROP) end
            SA:Refresh()
            c:Pop()
          end
          return
        end
      end
      -- Let go over a worn slot (the character screen's, say): put it on
      if K.Worn then K.Worn:DropFromBag(from) end
      SA:Refresh()
    end)
    f.cells[i] = s
  end
  if K.Worn then K.Worn:BagCells(f.cells) end
end

local function Common(f, name)
  f:SetFrameStrata("HIGH")
  f:SetToplevel(true)
  f:SetClampedToScreen(true)
  f:EnableMouse(true)
  f:SetMovable(true)
  f:RegisterForDrag("LeftButton")
  f:SetScript("OnDragStart", function(self) self.loose = true; self:StartMoving() end)
  f:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)
  f:Hide()
  tinsert(UISpecialFrames, name)   -- Esc closes it, like a bag
  f:HookScript("OnShow", function()
    if SOUNDKIT and SOUNDKIT.IG_BACKPACK_OPEN then PlaySound(SOUNDKIT.IG_BACKPACK_OPEN) end
    SA:Refresh()
  end)
  f:HookScript("OnHide", function(self)
    if not SA.quiet and SOUNDKIT and SOUNDKIT.IG_BACKPACK_CLOSE then PlaySound(SOUNDKIT.IG_BACKPACK_CLOSE) end
    self.withBags = nil
    SA:ClosePane()
    if SA.button then SA.button:Paint() end
  end)
end

local SEARCH_TIP = "Look for stashes other players have left near where you stand."
local STASH_TIP = "The stashes you've left out in the world, and what's in them."
local MORE_TIP = "The full Inventory page: item details, the Workshop and documents."

-- The satchel's three buttons, spread evenly across the given width.
local function Buttons(f, L, parent, x, y, w, h)
  local bw = math.floor((w - 8) / 3)
  f.search = L.Button(parent, "Search", bw, h, function() SA:OpenPane("near") end)
  f.search:SetPoint("BOTTOMLEFT", x, y)
  Tip(f.search, "Search the area", SEARCH_TIP)
  f.stashes = L.Button(parent, "Stashes", bw, h, function() SA:OpenPane("mine") end)
  f.stashes:SetPoint("LEFT", f.search, "RIGHT", 4, 0)
  Tip(f.stashes, "Your stashes", STASH_TIP)
  f.more = L.Button(parent, "Journal", w - 2 * bw - 8, h, function() K.Journal:Open("inventory") end)
  f.more:SetPoint("LEFT", f.stashes, "RIGHT", 4, 0)
  Tip(f.more, "Inventory", MORE_TIP)
end

local BUILD = {}

-- EllesmereUI Bags' look: title bar with whose satchel it is and how full,
-- the slots, and a footer of three even buttons.
function BUILD.ellesmere()
  local L = KIT.ellesmere
  local COLS, CELL, GAP, PAD, FOOT = 6, L.cell, L.gap, L.pad, 32
  local w = PAD * 2 + COLS * CELL + (COLS - 1) * GAP
  local rows = math.ceil(I.SLOTS / COLS)
  local h = 36 + PAD + rows * CELL + (rows - 1) * GAP + PAD + FOOT
  local name = "KinshipRPSatchelEllesmere"
  local f = L.New(name, w, h, "Satchel", ICON, function() SA:Close() end)
  Common(f, name)
  f.min = MinButton(f.head, 18, function() return 0.85, 0.85, 0.85 end)
  f.min:SetPoint("RIGHT", f.close, "LEFT", -2, 0)
  f.free = L.Text(f.head, 11, "dim")
  f.free:SetPoint("RIGHT", f.min, "LEFT", -6, 0)
  f.free:SetJustifyH("RIGHT")
  f.whose = L.Text(f.head, 11, "dim")
  f.whose:SetPoint("LEFT", f.title, "RIGHT", 8, 0)
  f.whose:SetPoint("RIGHT", f.free, "LEFT", -8, 0)
  f.whose:SetWordWrap(false)
  MakeCells(f, L.slot, COLS, CELL, GAP, PAD, f.top - PAD)
  local foot = CreateFrame("Frame", nil, f)
  foot:SetPoint("BOTTOMLEFT", 1, 1); foot:SetPoint("BOTTOMRIGHT", -1, 1); foot:SetHeight(FOOT)
  foot.bg = foot:CreateTexture(nil, "BACKGROUND"); foot.bg:SetAllPoints(); foot.bg:SetColorTexture(0, 0, 0, 0.35)
  Buttons(f, L, foot, PAD - 1, 5, w - 2 * PAD, 22)
  f.gap = L.dock
  return f
end

-- The game's bags lay their slots out in rows between the search row and
-- the money bar. The satchel does the same: docked, it
-- takes as many rows as fit the bags' height (so it stands exactly as tall),
-- and as many columns as that needs; on its own, six columns.
local B_TOP, B_BOTTOM = 62, 40
local function LayoutBlizzard(f, h)
  local L = KIT.blizzard
  local CELL, GAP = L.cell, L.gap
  local rows = 5
  if h then rows = math.max(3, math.min(10, math.floor((h - B_TOP - B_BOTTOM + GAP) / (CELL + GAP)))) end
  local cols = math.ceil(I.SLOTS / rows)
  rows = math.ceil(I.SLOTS / cols)
  local gridW = cols * CELL + (cols - 1) * GAP
  local w = math.max(gridW + 24, 260)
  h = h or (B_TOP + rows * CELL + (rows - 1) * GAP + B_BOTTOM)
  local key = cols .. ":" .. math.floor(h + 0.5)
  if f.layoutKey == key then return end
  f.layoutKey = key
  f:SetSize(w, h)
  local x0 = math.floor((w - gridW) / 2)
  for i, s in ipairs(f.cells) do
    s:ClearAllPoints()
    s:SetPoint("TOPLEFT", x0 + ((i - 1) % cols) * (CELL + GAP), -B_TOP - math.floor((i - 1) / cols) * (CELL + GAP))
  end
  local bw = math.floor((w - 24 - 8) / 3)
  f.search:SetWidth(bw)
  f.stashes:SetWidth(bw)
  f.more:SetWidth(w - 24 - 2 * bw - 8)
end

-- The game's own bag look
function BUILD.blizzard()
  local L = KIT.blizzard
  local COLS, CELL, GAP = 6, L.cell, L.gap
  local rows = math.ceil(I.SLOTS / COLS)
  local gridW = COLS * CELL + (COLS - 1) * GAP
  local gridH = rows * CELL + (rows - 1) * GAP
  local name = "KinshipRPSatchelBlizzard"
  local f = L.New(name, gridW + 24, gridH + 64 + 52, "Satchel", ICON, function() SA:Close() end)
  if not f then return nil end
  Common(f, name)
  if f.CloseButton then
    f.min = BlizzardMinButton(f)
    f.min:SetPoint("RIGHT", f.CloseButton, "LEFT", f.min.atlas and 0 or 8, 0)
    f.min:SetFrameLevel(f.CloseButton:GetFrameLevel())   -- above the title bar's border
  end
  f.whose = L.Text(f, nil, "body")
  f.whose:SetPoint("TOPLEFT", 64, -34)
  f.whose:SetPoint("RIGHT", -70, 0)
  f.whose:SetWordWrap(false)
  f.free = L.Text(f, nil, "dim")
  f.free:SetPoint("TOPRIGHT", -12, -34)
  f.free:SetJustifyH("RIGHT")
  MakeCells(f, L.slot, COLS, CELL, GAP, 12, -B_TOP)
  Buttons(f, L, f, 12, 12, gridW, 22)
  f.layout = LayoutBlizzard
  f.layout(f)
  f.gap = L.dock
  return f
end

-- Kinship's own look
function BUILD.kinship()
  local L = KIT.kinship
  local COLS, CELL, GAP, PAD, FOOT = 6, L.cell, L.gap, L.pad, 74
  local w = PAD * 2 + COLS * CELL + (COLS - 1) * GAP
  local rows = math.ceil(I.SLOTS / COLS)
  local name = "KinshipRPSatchel"
  local f = L.New(name, w, 100, "Satchel", ICON, function() SA:Close() end)
  f:SetHeight(-f.top + rows * CELL + (rows - 1) * GAP + FOOT)
  Common(f, name)
  f.min = MinButton(f, 20, function() local c = K:Theme().deskSubtle or { 0.8, 0.8, 0.8 }; return c[1], c[2], c[3] end)
  f.min:SetPoint("RIGHT", f.close, "LEFT", -4, 0)
  UI:OnTheme(function() f.min:Paint() end)
  f.whose = UI.Text(f, "", "Small", "deskSubtle", w - 90)
  f.whose:SetPoint("TOPLEFT", f.title, "BOTTOMLEFT", 0, -2)
  f.whose:SetWordWrap(false)
  MakeCells(f, L.slot, COLS, CELL, GAP, PAD, f.top)
  f.free = UI.Text(f, "", "Small", "deskSubtle", w - 2 * PAD)
  f.free:SetPoint("BOTTOMLEFT", PAD, FOOT - 22)
  f.freeFormat = "%d/%d used"
  Buttons(f, L, f, PAD, 14, w - 2 * PAD, 24)
  f.gap = L.dock
  return f
end

-- The satchel window for the look in use (built the first time it's needed).
function SA:Frame()
  local look = Look()
  if not self.frames[look] then
    local ok, f = pcall(BUILD[look])
    if not (ok and f) then
      if not ok then K:CaughtError("satchel " .. look, f) end
      look = "kinship"
      self.frames[look] = self.frames[look] or BUILD.kinship()
    else
      self.frames[look] = f
    end
  end
  if self.frame and self.frame ~= self.frames[look] and self.frame:IsShown() then self.frame:Hide() end
  self.frame, self.look = self.frames[look], look
  return self.frame
end

---------------------------------------------------------------------------
-- Minimised: the satchel narrowed to a thin strip, the same height and in
-- the same place, in the satchel's look: its icon and how full it is.
-- Click it to open the satchel.
---------------------------------------------------------------------------
local function BuildStrip(look)
  local name = "KinshipRPSatchelStrip" .. look
  local blizz = look == "blizzard"
  local st
  if blizz then
    local ok, b = pcall(CreateFrame, "Button", name, UIParent, "BackdropTemplate")
    st = ok and b or nil
  end
  st = st or CreateFrame("Button", name, UIParent)
  local W = look == "ellesmere" and 37 or 44
  st:SetSize(W, 200)
  st:SetFrameStrata("HIGH")
  st:SetToplevel(true)
  st:SetClampedToScreen(true)
  st:RegisterForClicks("LeftButtonUp")
  st:Hide()
  tinsert(UISpecialFrames, name)
  st.gap = (KIT[look] or KIT.kinship).dock

  local E = EUI()
  if look == "ellesmere" then
    st.bg = st:CreateTexture(nil, "BACKGROUND", nil, 0)
    st.bg:SetAllPoints()
    st.bg:SetTexture("Interface\\AddOns\\EllesmereUI\\media\\modern_blizz.png")
    st.shade = st:CreateTexture(nil, "BACKGROUND", nil, 1)
    st.shade:SetAllPoints()
    st.shade:SetColorTexture(0, 0, 0, 0.25)
    if not (E and E.PanelPP and E.PanelPP.CreateBorder and pcall(E.PanelPP.CreateBorder, st, 0.1, 0.1, 0.1, 1, 1, "OVERLAY", 7)) then
      st.edge = UI.Border(st); st.edge:SetColor(0.1, 0.1, 0.1, 1)
    end
    -- the top, dark like the bags' title bar, holding the close button
    st.cap = st:CreateTexture(nil, "BACKGROUND", nil, 2)
    st.cap:SetPoint("TOPLEFT", 1, -1); st.cap:SetPoint("TOPRIGHT", -1, -1); st.cap:SetHeight(26)
    st.cap:SetColorTexture(0, 0, 0, 0.5)
  elseif blizz and st.SetBackdrop then
    st:SetBackdrop({ bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark",
      edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", tile = true, tileSize = 16, edgeSize = 16,
      insets = { left = 4, right = 4, top = 4, bottom = 4 } })
    st:SetBackdropBorderColor(0.7, 0.7, 0.7, 1)
  else
    st.bg = st:CreateTexture(nil, "BACKGROUND")
    st.bg:SetAllPoints()
    st.bg:SetTexture(WHITE)
    st.edge = UI.Border(st)
    UI:OnTheme(function(t)
      st.bg:SetVertexColor(unpack(t.chrome))
      st.edge:SetColor(unpack(t.chromeEdge))
    end)
  end

  if blizz then
    st.close = CreateFrame("Button", nil, st, "UIPanelCloseButton")
    st.close:SetSize(24, 24)
    st.close:SetPoint("TOP", 0, -4)
  else
    st.close = UI.CloseButton(st, false, 16)
    st.close:SetPoint("TOP", 0, -5)
  end
  st.close:SetScript("OnClick", function() SA:Close() end)

  st.icon = st:CreateTexture(nil, "ARTWORK")
  st.icon:SetSize(W - 13, W - 13)
  st.icon:SetPoint("TOP", 0, blizz and -32 or -33)
  if blizz and SetPortraitToTexture then
    pcall(SetPortraitToTexture, st.icon, ICON)
  else
    st.icon:SetTexture(ICON)
    st.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    if look == "kinship" then UI.Round(st.icon) end
  end

  -- how full it is, under the icon
  if look == "ellesmere" then
    st.count = st:CreateFontString(nil, "OVERLAY")
    st.count:SetFont(EFont(), 10, "")
    st.count:SetShadowOffset(1, -1)
    st.count:SetTextColor(0.6, 0.6, 0.6)
  elseif blizz then
    st.count = st:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  else
    st.count = UI.Text(st, "", "Small", "deskSubtle")
  end
  st.count:SetJustifyH("CENTER")
  st.count:SetPoint("TOP", st.icon, "BOTTOM", 0, -6)

  st.hl = st:CreateTexture(nil, "HIGHLIGHT")
  st.hl:SetPoint("TOPLEFT", 1, -1); st.hl:SetPoint("BOTTOMRIGHT", -1, 1)
  st.hl:SetColorTexture(1, 1, 1, 0.05)

  st:SetScript("OnClick", function() SA:SetCollapsed(false) end)
  st:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_LEFT")
    GameTooltip:SetText("Roleplay satchel", 1, 0.82, 0)
    local used = 0
    for i = 1, I.SLOTS do if I:Slot(i) then used = used + 1 end end
    GameTooltip:AddLine(("%d of %d slots used"):format(used, I.SLOTS), 1, 1, 1)
    GameTooltip:AddLine("Click to open it.", 0.62, 0.62, 0.62)
    GameTooltip:Show()
  end)
  st:SetScript("OnLeave", function() GameTooltip:Hide() end)
  st:HookScript("OnHide", function(self) self.withBags = nil; if SA.button then SA.button:Paint() end end)
  return st
end

function SA:Strip()
  local look = self.look or Look()
  if not self.strips then self.strips = {} end
  if not self.strips[look] then self.strips[look] = BuildStrip(look) end
  for l, st in pairs(self.strips) do if l ~= look and st:IsShown() then st:Hide() end end
  self.strip = self.strips[look]
  return self.strip
end

-- Where the satchel stands and just as tall: only narrower.
function SA:DockStrip()
  local st, f = self.strip, self.frame
  if not (st and f) then return end
  self:Dock()   -- places the satchel itself, shown or not
  st:SetScale(f:GetScale())
  st:ClearAllPoints()
  st:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, 0)
  st:SetHeight(f:GetHeight())
end

function SA:Collapsed() return S().satchelMin and true or false end

-- Shown at all, in full or as the strip.
function SA:Visible()
  return (self.frame and self.frame:IsShown()) or (self.strip and self.strip:IsShown()) or false
end

local function ShowFull(withBags)
  local f = SA:Frame()
  if SA.strip then SA.strip:Hide() end
  f.withBags = withBags or nil
  SA:Dock()
  f:Show()
  f:Raise()
  SA:Refresh()
end

local function ShowStrip(withBags)
  local f = SA:Frame()
  if f:IsShown() then SA.quiet = true; f:Hide(); SA.quiet = nil end
  local st = SA:Strip()
  st.withBags = withBags or nil
  SA:DockStrip()
  st:Show()
  st:Raise()
  SA:Refresh()
end

function SA:SetCollapsed(on)
  S().satchelMin = on or nil
  local f, st = self.frame, self.strip
  if on and f and f:IsShown() then
    ShowStrip(f.withBags)
  elseif not on and st and st:IsShown() then
    local withBags = st.withBags
    st:Hide()
    ShowFull(withBags)
  end
  self:Refresh()
end

---------------------------------------------------------------------------
-- The stash pane: on the satchel's free side, in the satchel's look. Two
-- tabs (stashes found nearby, your own), a short list, and the chosen
-- stash's contents to click and take.
---------------------------------------------------------------------------
local ROWS, ROW_H, CONTENT_COLS = 4, 24, 5

local function PaneRow(p, L, w)
  local r = CreateFrame("Button", nil, p)
  r:SetSize(w, ROW_H)
  r:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  r.bg = r:CreateTexture(nil, "BACKGROUND")
  r.bg:SetAllPoints()
  r.icon = r:CreateTexture(nil, "ARTWORK")
  r.icon:SetSize(ROW_H - 6, ROW_H - 6)
  r.icon:SetPoint("LEFT", 3, 0)
  r.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
  r.sub = L.Text(r, 10, "dim")
  r.sub:SetPoint("RIGHT", -6, 0)
  r.sub:SetJustifyH("RIGHT")
  r.name = L.Text(r, 11, "body")
  r.name:SetPoint("LEFT", r.icon, "RIGHT", 6, 0)
  r.name:SetPoint("RIGHT", r.sub, "LEFT", -6, 0)
  r.name:SetWordWrap(false)
  r:SetScript("OnEnter", function(self) self.hover = true; L.PaintRow(self, true, self.sel) end)
  r:SetScript("OnLeave", function(self) self.hover = nil; L.PaintRow(self, false, self.sel) end)
  r:SetScript("OnClick", function(self, button)
    if not self.item then return end
    if button == "RightButton" and self.item.pos and K.Stashes then K.Stashes:MarkOnMap(self.item) return end
    p.selected = self.item
    SA:RefreshPane()
  end)
  r:EnableMouseWheel(true)
  r:SetScript("OnMouseWheel", function(_, d) p.offset = (p.offset or 0) - d; SA:RefreshPane() end)
  L.PaintRow(r, false, false)
  return r
end

local function BuildPane(look)
  local L = KIT[look]
  local satchel = SA.frames[look]
  local w = satchel:GetWidth()
  local PAD = L.pad
  local IW = w - 2 * PAD
  local CELL, GAP = L.cell, L.gap
  local name = "KinshipRPStashPane" .. look
  local p = L.New(name, w, 100, "Stashes", STASH_ICON, function() SA:ClosePane() end)
  if not p then return nil end
  p:SetFrameStrata("HIGH")
  p:EnableMouse(true)
  p:Hide()
  tinsert(UISpecialFrames, name)
  p.mode = "near"

  local y = p.top - (L.template and 4 or PAD)
  p.tabs = L.Tabs(p, { { key = "near", label = "Nearby" }, { key = "mine", label = "Yours" } }, IW, function(key)
    p.mode, p.selected, p.offset = key, nil, 0
    SA:RefreshPane()
  end)
  p.tabs:SetPoint("TOPLEFT", PAD, y)
  y = y - 22 - 8

  p.again = L.Button(p, "Search again", 96, 20, function() if K.Stashes then K.Stashes:Search() end end)
  p.again:SetPoint("TOPRIGHT", -PAD, y)
  Tip(p.again, "Search the area", SEARCH_TIP)
  p.status = L.Text(p, 12, "title")
  p.status:SetPoint("LEFT", p, "TOPLEFT", PAD, y - 10)
  p.status:SetPoint("RIGHT", p.again, "LEFT", -6, 0)
  p.status:SetWordWrap(false)
  y = y - 20 - 6

  p.rows = {}
  for i = 1, ROWS do
    local r = PaneRow(p, L, IW)
    r:SetPoint("TOPLEFT", PAD, y - (i - 1) * (ROW_H + 2))
    p.rows[i] = r
  end
  p.empty = L.Text(p, 11, "dim")
  p.empty:SetPoint("TOPLEFT", PAD + 4, y - 8)
  p.empty:SetWidth(IW - 8)
  p.empty:SetSpacing(2)
  y = y - ROWS * (ROW_H + 2) - 6

  p.cells = {}
  for i = 1, 10 do
    local s = L.slot(p, CELL)
    s:SetPoint("TOPLEFT", PAD + ((i - 1) % CONTENT_COLS) * (CELL + GAP), y - math.floor((i - 1) / CONTENT_COLS) * (CELL + GAP))
    s:RegisterForClicks("LeftButtonUp")
    s:SetScript("OnClick", function(self)
      local St, sel = K.Stashes, p.selected
      if not (St and sel and self.index) then return end
      if p.mode == "mine" then St:Withdraw(sel, self.index) else St:Take(sel, self.index) end
    end)
    p.cells[i] = s
  end
  y = y - 2 * CELL - GAP - 6

  p.hint = L.Text(p, 10, "dim")
  p.hint:SetPoint("TOPLEFT", PAD, y)
  p.hint:SetWidth(IW)
  p.hint:SetSpacing(2)
  p:SetHeight(-y + 30 + (L.template and 4 or PAD - 4))

  p:SetScript("OnShow", function() SA:RefreshPane() end)
  K:On("STASHES", function() if p:IsShown() then SA:RefreshPane() end end)
  K:On("INVENTORY", function() if p:IsShown() then SA:RefreshPane() end end)
  return p
end

local function Short(n) return I.Short and I.Short(n) or tostring(n or "?") end

function SA:RefreshPane()
  local p, St = self.pane, K.Stashes
  if not (p and p:IsShown() and St) then return end
  p.tabs:Select(p.mode)
  local near = p.mode == "near"
  local items, sel = {}, nil
  if near then
    for _, r in ipairs(St.results or {}) do items[#items + 1] = r end
    table.sort(items, function(a, b) return a.dist < b.dist end)
    for _, r in ipairs(items) do if r == p.selected then sel = r end end
    local sweeping = St:Searching()
    if not sel and items[1] and not sweeping then sel = items[1] end
    local s = St.search
    if sweeping then p.status:SetText("Searching the area...")
    elseif not s then p.status:SetText("Look around you")
    elseif #items == 0 then p.status:SetText("Nothing hidden here")
    else p.status:SetText(#items == 1 and "You found a stash" or ("You found %d stashes"):format(#items)) end
    p.again:Show()
    p.again:SetEnabled(not sweeping)
    p.empty:SetText(sweeping and "Listening for answers..." or
      (s and "Nothing turned up. Stashes only answer while their keeper is online and nearby." or
        "Search the area to find stashes others have left nearby."))
  else
    for _, st in ipairs(St:Mine()) do items[#items + 1] = st end
    for _, st in ipairs(items) do if st == p.selected then sel = st end end
    sel = sel or items[1]
    p.status:SetText(#items == 0 and "No stashes yet" or (#items == 1 and "One stash" or ("%d stashes"):format(#items)))
    p.again:Hide()
    p.empty:SetText("Leave an item somewhere with Stash it on the Inventory page, and it will be listed here.")
  end
  p.selected = sel

  -- The list, scrolled with the mouse wheel when there are more than fit
  local maxOff = math.max(0, #items - ROWS)
  p.offset = math.max(0, math.min(p.offset or 0, maxOff))
  local L = KIT[self.look] or KIT.kinship
  for i, r in ipairs(p.rows) do
    local it = items[i + p.offset]
    r.item = it
    r:SetShown(it ~= nil)
    if it then
      r.icon:SetTexture(I.IconTexture(it.icon))
      r.name:SetText(it.name or "?")
      if near then
        r.sub:SetText(("%s, %dy"):format(it.own and "Yours" or Short(it.owner), math.floor(it.dist + 0.5)))
      else
        local n = 0
        for _, x in ipairs(it.items) do n = n + (x.count or 0) end
        r.sub:SetText(n == 0 and "Empty" or (n == 1 and "1 item" or (n .. " items")))
      end
      r.sel = it == sel
      L.PaintRow(r, r.hover, r.sel)
    end
  end
  p.empty:SetShown(#items == 0)

  -- What the chosen stash holds
  local contents = {}
  if sel then
    for _, x in ipairs(sel.items) do
      if near then contents[#contents + 1] = { def = x.def, n = x.n, asking = x.asking }
      else contents[#contents + 1] = { def = I:Get(x.def), n = x.count } end
    end
  end
  for i, cell in ipairs(p.cells) do
    local c = contents[i]
    cell:SetShown(sel ~= nil)
    cell.index = c and i or nil
    if c then cell:SetItem(c.def, c.n, true) else cell:SetItem(nil) end
    cell:SetMatch(not (c and c.asking))
  end
  if not sel then
    p.hint:SetText(near and "Stashes show from about 25 yards. Hidden ones only when you're right on top of them." or "")
  elseif #contents == 0 then
    p.hint:SetText("It's empty.")
  elseif near and sel.own then
    p.hint:SetText("Your own stash. Click an item to take it back.")
  elseif near then
    p.hint:SetText("Click an item to take it. " .. Short(sel.owner) .. "'s client hands it over while you're close.")
  else
    p.hint:SetText("Click an item to take it back. Right-click a stash to mark it on your map.")
  end
end

-- Beside the satchel, on the side away from the bags.
function SA:DockPane()
  local p, f = self.pane, self.frame
  if not (p and f) then return end
  p:SetScale(f:GetScale())
  p:ClearAllPoints()
  local bags = OpenBags()
  local right = bags and bags:GetLeft() and f:GetLeft() and f:GetLeft() > bags:GetLeft()
  if right then
    p:SetPoint("TOPLEFT", f, "TOPRIGHT", f.gap or 4, 0)
  else
    p:SetPoint("TOPRIGHT", f, "TOPLEFT", -(f.gap or 4), 0)
  end
end

function SA:OpenPane(mode)
  if not K.Stashes then return end
  local f = self.frame
  if not (f and f:IsShown()) then self:Open(false); f = self.frame end
  if self:Collapsed() then self:SetCollapsed(false) end
  local look = self.look
  if not self.panes[look] then
    local ok, p = pcall(BuildPane, look)
    if not (ok and p) then
      if not ok then K:CaughtError("stash pane " .. look, p) end
      return
    end
    self.panes[look] = p
  end
  if self.pane and self.pane ~= self.panes[look] then self.pane:Hide() end
  local p = self.panes[look]
  self.pane = p
  -- The same button again closes it
  if p:IsShown() and p.mode == mode then
    self:ClosePane()
    return
  end
  p.mode = mode
  p.offset = 0
  if mode == "near" then p.selected = nil end
  self:DockPane()
  p:Show()
  p:Raise()
  self:RefreshPane()
  if mode == "near" and not K.Stashes:Searching() then K.Stashes:Search() end
end

function SA:ClosePane() if self.pane then self.pane:Hide() end end

---------------------------------------------------------------------------
-- Filling it, searching it, docking it
---------------------------------------------------------------------------
local function Matches(def, q)
  if q == "" then return true end
  if not def then return false end
  local hay = ((def.name or "") .. " " .. (def.description or "") .. " " .. (I.Quality(def.quality).label or "")):lower()
  return hay:find(q, 1, true) ~= nil
end

function SA:Refresh()
  local f = self.frame
  if f and f:IsShown() then
    local used = 0
    local q = (self.query or ""):lower()
    for i, cell in ipairs(f.cells) do
      local slot = I:Slot(i)
      local def = slot and I:Get(slot.def)
      cell:SetItem(def, slot and slot.count, slot ~= nil and def == nil)
      cell:SetMatch(q == "" or Matches(def, q))
      if slot then used = used + 1 end
    end
    local name = K:DisplayName(K:Profile())
    if f.whose then f.whose:SetText(name or "") end
    if f.free then f.free:SetText((f.freeFormat or "%d/%d"):format(used, I.SLOTS)) end
  end
  local st = self.strip
  if st and st:IsShown() then
    local used = 0
    for i = 1, I.SLOTS do if I:Slot(i) then used = used + 1 end end
    st.count:SetText(("%d/%d"):format(used, I.SLOTS))
  end
  if self.button then self.button:Paint() end
end

-- Beside the open bags, flush to their edge: pinned to the window itself when
-- it's an ordinary frame (so it follows a move or a rescale), placed by
-- reading its position otherwise. On its own it keeps the bags' scale, so it
-- never looks smaller than they do.
function SA:Dock()
  local f = self.frame
  if not f then return end
  local eui = self.look == "ellesmere" and _G.EUI_MainBagFrame
  if eui and eui.GetScale then f:SetScale(eui:GetScale()) end
  if f.loose then self:DockPane() return end
  local bags = OpenBags()
  f:ClearAllPoints()
  if bags and bags:GetLeft() then
    local protected = bags.IsProtected and bags:IsProtected()
    if not protected and bags:GetParent() == UIParent then
      f:SetScale(bags:GetScale())
      f:SetPoint("TOPRIGHT", bags, "TOPLEFT", -(f.gap or 4), 0)
    else
      local s = bags:GetEffectiveScale() / f:GetEffectiveScale()
      f:SetPoint("TOPRIGHT", UIParent, "BOTTOMLEFT", bags:GetLeft() * s - (f.gap or 4), bags:GetTop() * s)
    end
  else
    if not eui then f:SetScale(1) end
    local s = 1 / f:GetScale()
    f:SetPoint("BOTTOMRIGHT", UIParent, "BOTTOMRIGHT", -60 * s, 120 * s)
  end
  if f.layout then
    local h = bags and bags:GetHeight() and bags:GetHeight() * bags:GetEffectiveScale() / f:GetEffectiveScale()
    f.layout(f, (h and h >= 200) and h or nil)
  end
  self:DockPane()
end

function SA:Open(withBags)
  if not On() then K:Print("Kinship items are switched off (Settings > Extended features).") return end
  -- Opened on purpose, it opens in full; with the bags it stays as it was.
  if not withBags and self:Collapsed() then S().satchelMin = nil end
  if self:Collapsed() then ShowStrip(withBags) else ShowFull(withBags) end
end

function SA:Close()
  if self.frame then self.frame:Hide() end
  if self.strip then self.strip:Hide() end
end

function SA:Toggle()
  if self.strip and self.strip:IsShown() then self:SetCollapsed(false)
  elseif self.frame and self.frame:IsShown() then self:Close()
  else self:Open(false) end
end

function KinshipRP_SatchelKey() SA:Toggle() end

-- The bags' own search box filters the satchel too.
local searchHooked = {}
local function HookSearch()
  local boxes = { _G.EUI_BagSearchBox, _G.BagItemSearchBox,
                  _G.ContainerFrameCombinedBags and _G.ContainerFrameCombinedBags.SearchBox }
  for _, box in pairs(boxes) do
    if box and box.HookScript and not searchHooked[box] then
      searchHooked[box] = true
      box:HookScript("OnTextChanged", function(self)
        local text = self:GetText()
        if type(text) ~= "string" then return end
        SA.query = strtrim(text)
        SA:Refresh()
      end)
    end
  end
end

---------------------------------------------------------------------------
-- Opening and closing with the bags
---------------------------------------------------------------------------
local function BagsShown()
  if not (On() and S().satchelWithBags ~= false) then return end
  C_Timer.After(0, function()   -- once the bags have their final size and place
    HookSearch()
    if OpenBags() then SA:Open(true) end
    SA:PlaceButton()
  end)
end

local function BagsHidden()
  C_Timer.After(0, function()
    local f, st = SA.frame, SA.strip
    if f and f:IsShown() and f.withBags and not OpenBags() then f:Hide() end
    if st and st:IsShown() and st.withBags and not OpenBags() then st:Hide() end
    if not OpenBags() then SA.query = "" end
  end)
end

local hooked = {}
local function HookBags()
  for _, name in ipairs({ "EUI_MainBagFrame", "ContainerFrameCombinedBags", "ContainerFrame1" }) do
    local fr = _G[name]
    if fr and not hooked[fr] then
      hooked[fr] = true
      fr:HookScript("OnShow", BagsShown)
      fr:HookScript("OnHide", BagsHidden)
    end
  end
  HookSearch()
end

---------------------------------------------------------------------------
-- The button by the bag bar, made like the bag bar's own buttons
---------------------------------------------------------------------------
local BAR = { "MainMenuBarBackpackButton", "CharacterBag0Slot", "CharacterBag1Slot", "CharacterBag2Slot",
              "CharacterBag3Slot", "CharacterReagentBag0Slot", "KeyRingButton" }

local function Used()
  local n = 0
  for i = 1, I.SLOTS do if I:Slot(i) then n = n + 1 end end
  return n
end

-- EllesmereUI's skin of the bag bar fades the buttons' bevel art.
local function BarSkinned()
  if not EUI() then return false end
  local ref = _G.CharacterBag0Slot or _G.MainMenuBarBackpackButton
  local nt = ref and ref.GetNormalTexture and ref:GetNormalTexture()
  return nt ~= nil and nt:GetAlpha() < 0.05
end

local function ButtonTooltip(self)
  GameTooltip:SetOwner(self, "ANCHOR_TOPLEFT")
  GameTooltip:SetText("Roleplay satchel", 1, 0.82, 0)
  GameTooltip:AddLine(("%d of %d slots used"):format(Used(), I.SLOTS), 1, 1, 1)
  GameTooltip:AddLine("Click to open. Right-click for the Inventory page.", 0.62, 0.62, 0.62)
  GameTooltip:Show()
end

local function ButtonClicks(b)
  b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  b:SetScript("OnClick", function(_, button)
    if button == "RightButton" then K.Journal:Open("inventory") else SA:Toggle() end
  end)
end

-- A bag-slot button like the game's, which takes EllesmereUI's skin when the
-- bag bar wears it: the same theme cell background, 1px border, cropped icon
-- and white hover wash.
local function BagSlotButton()
  local ok, b = pcall(CreateFrame, "ItemButton", "KinshipRPSatchelButton", UIParent, "ItemButtonTemplate")
  if not ok or not b or not b.SetItemButtonTexture then return nil end
  b:SetFrameStrata("MEDIUM")
  pcall(b.SetItemButtonTexture, b, ICON)
  b.lit = b:CreateTexture(nil, "OVERLAY", nil, 1)
  b.lit:SetAllPoints()
  b.lit:SetTexture("Interface\\Buttons\\CheckButtonHilight")
  b.lit:SetBlendMode("ADD")
  b.lit:Hide()
  function b:Skin(on)
    if self.skinned == on then return end
    self.skinned = on
    local icon = self.icon or _G[self:GetName() .. "IconTexture"]
    local nt = self:GetNormalTexture()
    local hl = self:GetHighlightTexture()
    if on and not self.box then
      self.cellBg = self:CreateTexture(nil, "BACKGROUND", nil, -8)
      self.cellBg:SetAllPoints()
      self.cellBg:SetColorTexture(0.08, 0.08, 0.08, 0.45)
      self.box = CreateFrame("Frame", nil, self)
      self.box:SetAllPoints()
      self.box:EnableMouse(false)
      local E = EUI()
      local PP = E and (E.PanelPP or E.PP)
      local made = PP and PP.CreateBorder and pcall(PP.CreateBorder, self.box, 0.2, 0.2, 0.2, 1, 1, "BORDER", -7)
      if made then
        self.SetEdge = function(_, r, g, bl) pcall(PP.SetBorderColor, self.box, r, g, bl, 1) end
      else
        self.box.edge = UI.Border(self.box)
        self.SetEdge = function(_, r, g, bl) self.box.edge:SetColor(r, g, bl, 1) end
      end
    end
    if self.box then self.box:SetShown(on) end
    if self.cellBg then self.cellBg:SetShown(on) end
    if nt then nt:SetAlpha(on and 0 or 1) end
    if self.IconBorder then self.IconBorder:SetAlpha(on and 0 or 1) end
    if icon then
      if on then icon:SetTexCoord(0.08, 0.92, 0.08, 0.92) else icon:SetTexCoord(0, 1, 0, 1) end
    end
    if hl then
      if on then
        hl:SetColorTexture(1, 1, 1, 0.1)
        hl:SetTexCoord(0, 1, 0, 1)
      else
        hl:SetTexture("Interface\\Buttons\\ButtonHilight-Square")
        hl:SetBlendMode("ADD")
      end
    end
  end
  function b:Paint()
    self:Skin(BarSkinned())
    local open = SA:Visible()
    if self.SetItemButtonCount then pcall(self.SetItemButtonCount, self, Used()) end
    if self.skinned and self.SetEdge then
      local v = open and 0.55 or 0.2
      self:SetEdge(v, v, v)
      self.lit:Hide()
    else
      self.lit:SetShown(open)
    end
  end
  b:SetScript("OnEnter", function(self) self.hover = true; ButtonTooltip(self) end)
  b:SetScript("OnLeave", function(self) self.hover = nil; GameTooltip:Hide() end)
  ButtonClicks(b)
  return b
end

-- Kinship's own flat button, if the game's item button can't be made.
local function FlatButton()
  local b = CreateFrame("Button", "KinshipRPSatchelButton", UIParent)
  b:SetSize(32, 32)
  b:SetFrameStrata("MEDIUM")
  b.bg = b:CreateTexture(nil, "BACKGROUND")
  b.bg:SetAllPoints()
  b.bg:SetTexture(WHITE)
  b.icon = b:CreateTexture(nil, "ARTWORK")
  b.icon:SetPoint("TOPLEFT", 1, -1)
  b.icon:SetPoint("BOTTOMRIGHT", -1, 1)
  b.icon:SetTexture(ICON)
  b.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
  b.wash = b:CreateTexture(nil, "OVERLAY")
  b.wash:SetAllPoints(b.icon)
  b.wash:SetColorTexture(1, 1, 1, 0.10)
  b.wash:Hide()
  b.edge = UI.Border(b)
  b.count = b:CreateFontString(nil, "OVERLAY")
  b.count:SetFont(EFont(), 11, "OUTLINE")
  b.count:SetPoint("BOTTOMRIGHT", -2, 2)
  function b:Paint()
    local open = SA:Visible()
    local t = K:Theme()
    self.bg:SetVertexColor(unpack(t.chrome))
    local u = open and t.ui or t.chromeEdge
    self.edge:SetColor(u[1], u[2], u[3], 1)
    local n = Used()
    self.count:SetText(n > 0 and tostring(n) or "")
  end
  b:SetScript("OnEnter", function(self) self.hover = true; self.wash:Show(); ButtonTooltip(self) end)
  b:SetScript("OnLeave", function(self) self.hover = nil; self.wash:Hide(); GameTooltip:Hide() end)
  ButtonClicks(b)
  UI:OnTheme(function() b:Paint() end)
  return b
end

-- One more cell at the left end of the bag bar: the size of its bag slots,
-- on their row, the same gap from the last one as they have between them.
function SA:PlaceButton()
  local b = self.button
  if not b then
    b = BagSlotButton() or FlatButton()
    b:Hide()
    self.button = b
  end
  b.wanted = On() and S().satchelButton ~= false
  if not b.wanted then b:Hide() return end
  local shown = {}
  for _, name in ipairs(BAR) do
    local x = _G[name]
    if x and x:IsVisible() and x:GetLeft() then shown[#shown + 1] = x end
  end
  if #shown == 0 then b:Hide() return end
  table.sort(shown, function(a, c) return a:GetLeft() * a:GetEffectiveScale() < c:GetLeft() * c:GetEffectiveScale() end)
  -- A bag slot gives the size and the row; the keyring is an odd shape.
  local ref
  for _, name in ipairs({ "CharacterBag0Slot", "CharacterBag1Slot", "MainMenuBarBackpackButton" }) do
    local x = _G[name]
    if x and x:IsVisible() and x:GetLeft() then ref = x break end
  end
  ref = ref or shown[#shown]
  local gap = 4
  local b0, b1 = _G.CharacterBag0Slot, _G.CharacterBag1Slot
  if b0 and b1 and b0:IsVisible() and b1:IsVisible() and b0:GetLeft() and b1:GetRight() then
    local g = math.abs(b0:GetLeft() - b1:GetRight())
    if math.abs(b1:GetLeft() - b0:GetRight()) < g then g = math.abs(b1:GetLeft() - b0:GetRight()) end
    if g <= 16 then gap = g end
  end
  -- Drawn at the bag bar's scale, so the size, gap and border all match.
  b:SetScale(ref:GetEffectiveScale() / UIParent:GetEffectiveScale())
  b:SetSize(ref:GetWidth(), ref:GetHeight())
  local first = shown[1]
  local s = first:GetEffectiveScale() / b:GetEffectiveScale()
  local _, cy = ref:GetCenter()
  local rs = ref:GetEffectiveScale() / b:GetEffectiveScale()
  b:ClearAllPoints()
  b:SetPoint("RIGHT", UIParent, "BOTTOMLEFT", first:GetLeft() * s - gap * rs, cy * rs)
  b:SetAlpha(first:GetEffectiveAlpha())
  b:Show()
  b:Paint()
end

-- Follow the bag bar: hide with it, come back with it, and fade as it fades
-- (hovering the button itself shows it, as hovering the bar shows the bar).
-- Only reads the bar; nothing of the game's or EllesmereUI's is touched.
local follow = CreateFrame("Frame")
local since, step = 0, 0
follow:SetScript("OnUpdate", function(_, elapsed)
  -- Twenty looks a second: smooth enough to follow a fade.
  step = step + elapsed
  if step < 0.05 then return end
  elapsed, step = step, 0
  local b = SA.button
  if not (b and b.wanted) then return end
  local bar = _G.BagsBar
  if not (bar and bar:IsVisible()) then bar = _G.MainMenuBarBackpackButton end
  if not (bar and bar:IsVisible()) then
    if b:IsShown() then b:Hide() end
    return
  end
  if not b:IsShown() then
    since = since + elapsed
    if since > 0.25 then since = 0; SA:PlaceButton() end
    return
  end
  local a = b.hover and 1 or bar:GetEffectiveAlpha()
  if math.abs(b:GetAlpha() - a) > 0.01 then b:SetAlpha(a) end
end)

---------------------------------------------------------------------------
-- Start-up, events and settings
---------------------------------------------------------------------------
K:On("LOGIN", function()
  local s = S()
  if s.satchelButton == nil then s.satchelButton = true end
  if s.satchelWithBags == nil then s.satchelWithBags = true end
  -- Bag addons set up their frames at login too: look a little later.
  C_Timer.After(2, function() HookBags(); SA:PlaceButton() end)
  C_Timer.After(6, function() HookBags(); SA:PlaceButton() end)
end)

for _, e in ipairs({ "INVENTORY", "ITEMDEFS", "PROFILE" }) do K:On(e, function() SA:Refresh() end) end
K:On("EXTENDED", function()
  if not On() then SA:Close() end
  SA:PlaceButton()
end)

local ev = CreateFrame("Frame")
ev:RegisterEvent("PLAYER_REGEN_ENABLED")
ev:RegisterEvent("UI_SCALE_CHANGED")
ev:RegisterEvent("DISPLAY_SIZE_CHANGED")
ev:RegisterEvent("BAG_UPDATE_DELAYED")
ev:SetScript("OnEvent", function() C_Timer.After(0.2, function() SA:PlaceButton() end) end)

_G["BINDING_NAME_KINSHIPRP_SATCHEL"] = "Open the roleplay satchel"
