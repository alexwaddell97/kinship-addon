-- Kinship RP: roleplay quests in the game's own quest places.
--
-- Objective tracker: a "Roleplay Quests" section just below the game's
-- objective tracker, in its fonts and colours. It's Kinship's own frame,
-- never part of the game's tracker, so nothing Kinship does can spread into
-- the tracker's own sections. Each tracked Kinship quest shows with its own
-- icon, its title and its objectives, ticked as they're done. Click to open
-- it in the journal; right-click to stop tracking; click the heading to fold it.
--
-- Quest log: a "Roleplay" tab beside the quest log's own tabs (Quests, Map
-- Legend...). It lays a Kinship card over the quest list showing your
-- roleplay quests with their icons, objectives and progress. The game's own
-- list is never touched.
--
-- Everything that talks to the game's frames is guarded: if the client's
-- tracker or quest log is different from what's expected, the feature steps
-- aside quietly instead of breaking them.

local ADDON, ns = ...
local K = ns.K
local UI = K.UI
local T = {}
K.QuestTracker = T

local DEFAULT_ICON = "Interface\\Icons\\INV_Scroll_03"

local S = K.Settings
local function On() return K.db ~= nil and K:ExtOn("campaigns") and K.Quests ~= nil end
local function Debug(msg) K:CaughtError("quest tracker", msg) end

-- Active quests in your log, tracked ones only if asked, by title.
local function Quests(trackedOnly)
  local out = {}
  if not On() then return out end
  for _, e in pairs(K.Quests:Log()) do
    if type(e) == "table" and e.state == "active" and (not trackedOnly or e.tracked) then out[#out + 1] = e end
  end
  table.sort(out, function(a, b) return (a.title or ""):lower() < (b.title or ""):lower() end)
  return out
end

---------------------------------------------------------------------------
-- The objective tracker section
---------------------------------------------------------------------------
-- A round icon to the left of a block's title, set in a dark disc with a
-- thin gold edge, the size of the game's own quest buttons.
local function BlockIcon(block, icon)
  local header = block.HeaderText or block.Header
  if not header then return end
  local tex = block.kinshipIcon
  if not tex then
    block.kinshipEdge = UI.Circle(block, 22, "ARTWORK", 0)
    block.kinshipEdge:SetVertexColor(0.86, 0.68, 0.30, 0.85)
    block.kinshipDisc = UI.Circle(block, 20, "ARTWORK", 1)
    block.kinshipDisc:SetVertexColor(0.07, 0.05, 0.03, 0.95)
    block.kinshipDisc:SetPoint("CENTER", block.kinshipEdge)
    tex = block:CreateTexture(nil, "ARTWORK", nil, 2)
    tex:SetSize(17, 17)
    tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    tex:SetPoint("CENTER", block.kinshipEdge)
    UI.Round(tex)
    block.kinshipIcon = tex
  end
  block.kinshipEdge:ClearAllPoints()
  block.kinshipEdge:SetPoint("TOPRIGHT", header, "TOPLEFT", -4, 4)
  tex:SetTexture(icon or DEFAULT_ICON)
  tex:Show()
  block.kinshipEdge:Show()
  block.kinshipDisc:Show()
end

-- The quest's action, like the game's quest-item buttons: a round button
-- beside the block (left of its icon) for the first open objective with
-- something to do: search the area, roll, answer, or try again.
local function ActionButton(block, e)
  local QA = K.QuestAuto
  local label, fn, tip, icon
  if QA then
    for i in ipairs(e.objectives or {}) do
      if QA.Visible(e, i) then
        label, fn, tip, icon = QA.Action(e, i)
        if label then break end
      end
    end
  end
  local b = block.kinshipAct
  if not label then
    if b then b:Hide() end
    return
  end
  if not b then
    b = CreateFrame("Button", nil, block)
    b:SetSize(26, 26)
    b.edge = UI.Circle(b, 26, "BACKGROUND", 0)
    b.edge:SetPoint("CENTER")
    b.disc = UI.Circle(b, 24, "BACKGROUND", 1)
    b.disc:SetPoint("CENTER")
    b.disc:SetVertexColor(0.07, 0.05, 0.03, 0.95)
    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetSize(20, 20)
    b.icon:SetPoint("CENTER")
    b.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    UI.Round(b.icon)
    b.shine = UI.Circle(b, 20, "OVERLAY", 0)
    b.shine:SetPoint("CENTER")
    b.shine:SetBlendMode("ADD")
    b.shine:SetVertexColor(1, 1, 1, 0)
    b:SetScript("OnEnter", function(self)
      self.shine:SetVertexColor(1, 1, 1, 0.18)
      GameTooltip:SetOwner(self, "ANCHOR_LEFT")
      GameTooltip:SetText(self.label or "", 1, 0.82, 0)
      if self.tip then GameTooltip:AddLine(UI.Escape(self.tip), 1, 1, 1, true) end
      GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function(self) self.shine:SetVertexColor(1, 1, 1, 0); GameTooltip:Hide() end)
    b:SetScript("OnClick", function(self)
      if SOUNDKIT then PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON) end
      if self.fn then self.fn() end
    end)
    block.kinshipAct = b
  end
  b.label, b.fn, b.tip = label, fn, tip
  b.icon:SetTexture(icon or "Interface\\Icons\\Spell_Nature_Lightning")
  b.edge:SetVertexColor(0.86, 0.68, 0.30, 0.9)
  b:ClearAllPoints()
  if block.kinshipEdge then
    b:SetPoint("RIGHT", block.kinshipEdge, "LEFT", -4, 0)
  else
    b:SetPoint("TOPRIGHT", block, "TOPLEFT", -30, 4)
  end
  b:Show()
end

-- The section is Kinship's own frame, laid just below the game's tracker
-- and moved along after each of its updates. It is never added to the
-- game's tracker or asked to redraw it: anything an addon does inside the
-- tracker's update spreads to the game's own sections (a scenario's aura
-- check, say) and the game then blocks them.
local TITLE = "Roleplay Quests"
local WIDTH, HEADER_H, GAP = 248, 26, 10

local function Font(names, fallback)
  for _, n in ipairs(names) do if _G[n] then return _G[n] end end
  return fallback
end

local function Color(c, r, g, b)
  if type(c) == "table" then return c.r or c[1] or r, c.g or c[2] or g, c.b or c[3] or b end
  return r, g, b
end

local frame
local function Frame()
  if frame then return frame end
  local f = CreateFrame("Frame", "KinshipRPQuestTracker", UIParent)
  f:SetSize(WIDTH, HEADER_H)
  f:SetFrameStrata("LOW")
  f:Hide()
  local head = CreateFrame("Button", nil, f)
  head:SetPoint("TOPLEFT")
  head:SetPoint("TOPRIGHT")
  head:SetHeight(HEADER_H)
  head.text = head:CreateFontString(nil, "OVERLAY")
  head.text:SetFontObject(Font({ "ObjectiveTrackerHeaderFont", "GameFontNormalMed2" }, GameFontNormal))
  head.text:SetPoint("LEFT", 8, 0)
  head.text:SetText(TITLE)
  head.line = head:CreateTexture(nil, "ARTWORK")
  head.line:SetColorTexture(0.86, 0.68, 0.30, 0.45)
  head.line:SetHeight(1)
  head.line:SetPoint("BOTTOMLEFT", 4, 2)
  head.line:SetPoint("BOTTOMRIGHT", -4, 2)
  head.toggle = head:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  head.toggle:SetPoint("RIGHT", -8, 0)
  head:SetScript("OnClick", function()
    f.collapsed = not f.collapsed
    T:Refresh()
  end)
  f.head = head
  f.blocks = {}
  frame = f
  return f
end

local function OnBlockClick(block, mouseButton)
  local id = block.kinshipId
  if not id then return end
  if mouseButton == "RightButton" then
    UI.Menu(block, function(root)
      local e = K.Quests:Log()[id]
      root:CreateTitle(e and e.title or "Quest")
      root:CreateButton("Open in your journal", function() K.Quests:Open(id) end)
      local QA = K.QuestAuto
      for i in ipairs(e and e.objectives or {}) do
        local label, fn, menuText = nil, nil, nil
        if QA then label, fn, menuText = QA.Action(e, i) end
        if label then root:CreateButton(menuText or label, fn) end
      end
      root:CreateButton("Stop tracking", function() K.Quests:Track(id, false) end)
    end)
  else
    K.Quests:Open(id)
  end
end

local function OnBlockEnter(block)
  local e = block.kinshipId and K.Quests:Log()[block.kinshipId]
  if not e then return end
  GameTooltip:SetOwner(block, "ANCHOR_LEFT")
  GameTooltip:SetText(("|T%s:16:16:0:0:64:64:5:59:5:59|t  %s"):format(tostring(e.icon or DEFAULT_ICON), UI.Escape(e.title or "")), 1, 0.82, 0)
  if e.giver and e.giver ~= "" then GameTooltip:AddLine("From " .. UI.Escape(e.giver), 0.8, 0.8, 0.8) end
  local done, total = K.Quests.Progress(e)
  if total > 0 then GameTooltip:AddLine(("%d/%d done"):format(done, total), 0.55, 0.80, 1) end
  -- How far the pins are
  local QM, QA = K.QuestMarkers, K.QuestAuto
  if QM then
    local function Far(mk)
      local d = QM.Distance(mk)
      return d and QM.DistText(d) or QM.Label(mk) or "?"
    end
    if e.marker then GameTooltip:AddDoubleLine("The quest", Far(e.marker), 0.8, 0.8, 0.8, 0.60, 0.72, 0.72) end
    for i, o in ipairs(e.objectives or {}) do
      if o.marker and not o.done and (not QA or (QA.Visible(e, i) and QA.Open(e, i))) then
        GameTooltip:AddDoubleLine(UI.Escape(o.text), Far(o.marker), 0.8, 0.8, 0.8, 0.60, 0.72, 0.72)
      end
    end
  end
  GameTooltip:AddLine("Click to open. Right-click for more.", 0.62, 0.62, 0.62)
  GameTooltip:Show()
end

local function Block(f, i)
  local b = f.blocks[i]
  if b then return b end
  b = CreateFrame("Button", nil, f)
  b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  b:SetWidth(WIDTH)
  b.HeaderText = b:CreateFontString(nil, "OVERLAY")
  b.HeaderText:SetFontObject(Font({ "ObjectiveTrackerLineFont", "ObjectiveFont" }, GameFontNormal))
  b.HeaderText:SetPoint("TOPLEFT", 30, 0)
  b.HeaderText:SetWidth(WIDTH - 36)
  b.HeaderText:SetJustifyH("LEFT")
  b.HeaderText:SetWordWrap(true)
  b.lines = {}
  b:SetScript("OnClick", OnBlockClick)
  b:SetScript("OnEnter", OnBlockEnter)
  b:SetScript("OnLeave", function() GameTooltip:Hide() end)
  f.blocks[i] = b
  return b
end

local function Line(b, j)
  local l = b.lines[j]
  if l then return l end
  l = b:CreateFontString(nil, "OVERLAY")
  l:SetFontObject(Font({ "ObjectiveTrackerLineFont", "ObjectiveFont" }, _G.GameFontHighlightSmall))
  l:SetWidth(WIDTH - 46)
  l:SetJustifyH("LEFT")
  l:SetWordWrap(true)
  b.lines[j] = l
  return l
end

-- One quest: "[12] Murloc Gills" in the colour for its level, then its
-- objectives, the way the game writes its own.
local function PaintBlock(b, e)
  b.kinshipId = e.id
  local QM, QA = K.QuestMarkers, K.QuestAuto
  local title = e.title or "?"
  local lvl = QM and QM.LevelText(e)
  if lvl then title = ("[%s] %s"):format(lvl, title) end
  local hex = lvl and QM.LevelHex(e)
  if hex then title = ("|cff%s%s|r"):format(hex, title) end
  -- Distances only when asked for (they're always in the tooltip).
  local showFar = S().questTrackerDistance == true
  local far = showFar and QM and e.marker and QM.TrackerDistance(e.marker)
  if far then title = title .. "  |cff9ab8b8" .. far .. "|r" end
  b.HeaderText:SetText(title)

  local rows = {}
  for i, o in ipairs(e.objectives or {}) do
    -- Hidden ones appear once done; in order, the ones not yet open wait.
    if not QA or (QA.Visible(e, i) and (o.done or QA.Open(e, i))) then
      local text = (QA and QA.CounterPrefix(e, i) or "") .. o.text
      if o.opt then text = text .. "  |cff9ab8b8(optional)|r" end
      if QA and QA.Standby(e, i) then text = text .. "  |cff9ab8b8(backup)|r" end
      if o.failed and not o.done then
        text = text .. "  |cffc0473a(" .. (QA and QA.FailText(o) or "failed"):lower() .. ")|r"
      else
        local progress = QA and not o.done and QA.ProgressText(e, i)
        if progress then text = text .. "  |cff9ab8b8" .. progress .. "|r" end
      end
      local d = showFar and QM and o.marker and not o.done and QM.TrackerDistance(o.marker)
      if d then text = text .. "  |cff9ab8b8" .. d .. "|r" end
      rows[#rows + 1] = { text = "- " .. text, done = o.done }
    end
  end
  if #rows == 0 then rows[1] = { text = (e.giver or "") ~= "" and ("From " .. e.giver) or "No objectives" } end

  local y = -(math.ceil(b.HeaderText:GetStringHeight()) + 3)
  local tc = _G.OBJECTIVE_TRACKER_COLOR
  for j, row in ipairs(rows) do
    local l = Line(b, j)
    l:ClearAllPoints()
    l:SetPoint("TOPLEFT", 40, y)
    l:SetText(row.text)
    if row.done then l:SetTextColor(Color(tc and tc.Complete, 0.6, 0.6, 0.6))
    else l:SetTextColor(Color(tc and tc.Normal, 0.8, 0.8, 0.8)) end
    l:Show()
    y = y - math.ceil(l:GetStringHeight()) - 2
  end
  for j = #rows + 1, #b.lines do b.lines[j]:Hide() end
  b:SetHeight(-y)
  BlockIcon(b, e.icon)
  ActionButton(b, e)
end

-- Just below whatever the game's tracker is showing; on its own on the
-- right of the screen when there's no game tracker to sit under.
local function Place(f)
  f:ClearAllPoints()
  local otf = _G.ObjectiveTrackerFrame
  if otf and otf:IsVisible() then
    -- On the tracker's own layer, so its background (if shown) can't cover us
    f:SetFrameStrata(otf:GetFrameStrata())
    f:SetFrameLevel(otf:GetFrameLevel() + 20)
    local below, low
    for _, m in ipairs(type(otf.modules) == "table" and otf.modules or {}) do
      if type(m) == "table" and m.IsVisible and m:IsVisible() and m.GetBottom then
        local bottom = m:GetBottom()
        if bottom and (not low or bottom < low) then below, low = m, bottom end
      end
    end
    if below then f:SetPoint("TOPLEFT", below, "BOTTOMLEFT", 0, -GAP)
    elseif otf.Header then f:SetPoint("TOPLEFT", otf.Header, "BOTTOMLEFT", 0, -GAP)
    else f:SetPoint("TOPLEFT", otf, "TOPLEFT", 0, -30) end
  else
    f:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", -90, -280)
  end
end

local hooked
local function Hook()
  local otf = _G.ObjectiveTrackerFrame
  if hooked or not (otf and otf.Update) then return end
  hooked = true
  -- Runs after the game's update has finished, so nothing here reaches it.
  hooksecurefunc(otf, "Update", function() if frame and frame:IsShown() then Place(frame) end end)
end

function T:Refresh()
  local list = (On() and S().questTracker ~= false) and Quests(true) or {}
  if #list == 0 then
    if frame then frame:Hide() end
    return
  end
  local f = Frame()
  Hook()
  local fine, err = pcall(function()
    f.head.toggle:SetText(f.collapsed and "+" or "-")
    local y = -HEADER_H - 4
    for i, e in ipairs(list) do
      local b = Block(f, i)
      b:SetShown(not f.collapsed)
      if not f.collapsed then
        PaintBlock(b, e)
        b:ClearAllPoints()
        b:SetPoint("TOPLEFT", 0, y)
        y = y - b:GetHeight() - 8
      end
    end
    for i = #list + 1, #f.blocks do f.blocks[i]:Hide() end
    f:SetHeight(f.collapsed and HEADER_H or -y)
    Place(f)
    f:Show()
  end)
  if not fine then Debug(err); f:Hide() end
end

-- Quests.lua's settings used to offer a position reset for a floating tracker.
function T:Place() self:Refresh() end

---------------------------------------------------------------------------
-- The Roleplay tab in the quest log
---------------------------------------------------------------------------
local tab, pane
local TAB_ICON = "Interface\\Icons\\INV_Scroll_03"

-- The quest log's own tabs, top to bottom.
local function LogTabs(qmf)
  local found, seen = {}, {}
  for _, key in ipairs({ "QuestsTab", "EventsTab", "MapLegendTab" }) do
    local t = qmf[key]
    if t and not seen[t] then seen[t] = true; found[#found + 1] = t end
  end
  for _, child in ipairs({ qmf:GetChildren() }) do
    if child ~= tab and not seen[child] and child.displayMode ~= nil and child.IsObjectType and child:IsObjectType("Button") then
      seen[child] = true
      found[#found + 1] = child
    end
  end
  table.sort(found, function(a, b) return (a:GetTop() or 0) > (b:GetTop() or 0) end)
  return found
end

local function ContentArea(qmf)
  return qmf.ContentsAnchor or qmf.QuestsFrame or _G.QuestScrollFrame
end

local function ShowPane(on)
  if not pane then return end
  pane:SetShown(on)
  if tab and tab.SetChecked then pcall(tab.SetChecked, tab, on) end
  if on then
    local qmf = _G.QuestMapFrame
    for _, t in ipairs(LogTabs(qmf)) do if t.SetChecked then pcall(t.SetChecked, t, false) end end
    T:RefreshLog()
    UI.FadeIn(pane, 0.15)
  end
end

local function BuildPane(qmf)
  local area = ContentArea(qmf)
  if not area then Debug("no quest list area to cover") return nil end
  local p = UI.Panel(qmf)
  p:SetPoint("TOPLEFT", area, "TOPLEFT", 0, 0)
  p:SetPoint("BOTTOMRIGHT", area, "BOTTOMRIGHT", 0, 0)
  p:SetFrameLevel((area:GetFrameLevel() or 1) + 20)
  p:EnableMouse(true)
  p:Hide()

  -- The list's rows take their width when it's made, so measure the space first.
  local W = math.floor(area:GetWidth() or 0)
  local H = math.floor(area:GetHeight() or 0)
  if W < 120 then W = 280 end
  if H < 300 then H = 420 end

  local pill = UI.Section(p, "Roleplay quests")
  pill:SetPoint("TOPLEFT", 14, -12)
  p.count = UI.Text(p, "", "Label", "subtle")
  p.count:SetPoint("TOPRIGHT", -14, -14)

  p.list = UI.List(p, W - 16, math.max(80, H - 36 - 44 - 160), 46, "No roleplay quests yet. Take one from someone, or write your own in the Kinship journal.",
    function(row)
      row.icon = row:CreateTexture(nil, "ARTWORK")
      row.icon:SetSize(30, 30)
      row.icon:SetPoint("LEFT", 6, 0)
      row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
      UI.Round(row.icon)
      row.title = UI.Text(row, "", "Body", "heading")
      row.title:SetPoint("TOPLEFT", 44, -7)
      row.title:SetPoint("RIGHT", -30, 0)
      row.title:SetWordWrap(false)
      row.sub = UI.Text(row, "", "Small", "subtle")
      row.sub:SetPoint("TOPLEFT", row.title, "BOTTOMLEFT", 0, -3)
      row.sub:SetPoint("RIGHT", -30, 0)
      row.sub:SetWordWrap(false)
      row.track = CreateFrame("Button", nil, row)
      row.track:SetSize(18, 18)
      row.track:SetPoint("RIGHT", -6, 0)
      row.track.ring = UI.Circle(row.track, 16, "ARTWORK", 0)
      row.track.ring:SetPoint("CENTER")
      row.track.dot = UI.Circle(row.track, 10, "ARTWORK", 1)
      row.track.dot:SetPoint("CENTER")
      row.track:SetScript("OnClick", function(self)
        local e = self:GetParent().item
        if e then K.Quests:Track(e.id, not e.tracked) end
      end)
      UI.Tooltip(row.track, "Track", "Show it in your objective tracker.")
      row:SetScript("OnClick", function(self)
        p.selected = self.item and self.item.id
        T:RefreshLog()
      end)
      row:SetScript("OnDoubleClick", function(self) if self.item then K.Quests:Open(self.item.id) end end)
    end, { bare = true, emptyIcon = K.Art("IconNote") })
  p.list:SetPoint("TOPLEFT", 8, -36)

  -- The chosen quest, under the list
  local d = CreateFrame("Frame", nil, p)
  d:SetPoint("BOTTOMLEFT", 14, 44)
  d:SetPoint("RIGHT", -14, 0)
  d:SetHeight(150)
  p.detail = d
  d.div = UI.Divider(d, 10)
  d.div:SetPoint("TOPLEFT", 0, 0)
  d.div:SetPoint("TOPRIGHT", 0, 0)
  d.title = UI.Text(d, "", "Header", "heading")
  d.title:SetPoint("TOPLEFT", 0, -10)
  d.title:SetPoint("RIGHT", 0, 0)
  d.title:SetWordWrap(false)
  d.giver = UI.Text(d, "", "Small", "subtle")
  d.giver:SetPoint("TOPLEFT", d.title, "BOTTOMLEFT", 0, -3)
  d.giver:SetPoint("RIGHT", 0, 0)
  d.giver:SetWordWrap(false)
  d.objectives = UI.Text(d, "", "Body", "text")
  d.objectives:SetPoint("TOPLEFT", d.giver, "BOTTOMLEFT", 0, -8)
  d.objectives:SetPoint("RIGHT", 0, 0)
  d.objectives:SetSpacing(4)
  d.objectives:SetJustifyV("TOP")
  d.objectives:SetPoint("BOTTOM", 0, 0)

  p.open = UI.Button(p, "Open in journal", 120, 24)
  p.open:SetPoint("BOTTOMRIGHT", -12, 12)
  p.open:SetScript("OnClick", function() if p.selected then K.Quests:Open(p.selected) end end)
  p.trackBtn = UI.Button(p, "Track", 90, 24)
  p.trackBtn:SetPoint("RIGHT", p.open, "LEFT", -6, 0)
  p.trackBtn:SetScript("OnClick", function()
    local e = p.selected and K.Quests:Log()[p.selected]
    if e then K.Quests:Track(e.id, not e.tracked) end
  end)
  p.write = UI.Button(p, "Write a quest", 110, 24)
  p.write:SetPoint("BOTTOMLEFT", 12, 12)
  p.write:SetScript("OnClick", function() K.Quests:Open(nil, 2) end)

  return p
end

local function BuildTab()
  if tab then return end
  local qmf = _G.QuestMapFrame
  if not qmf then return end
  local own = LogTabs(qmf)
  local last = own[#own]
  if not last then Debug("couldn't find the quest log's tabs") return end
  pane = BuildPane(qmf)
  if not pane then return end
  local ok, t = pcall(CreateFrame, "Button", "KinshipRPQuestLogTab", qmf, "QuestLogTabButtonTemplate")
  if not ok or not t then ok, t = pcall(CreateFrame, "Frame", "KinshipRPQuestLogTab", qmf, "LargeSideTabButtonTemplate") end
  if not ok or not t then Debug("couldn't make a quest log tab") return end
  tab = t
  tab.tooltipText = "Roleplay quests"
  if tab.Icon then
    tab.Icon:SetTexture(TAB_ICON)
    tab.Icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
  end
  tab:SetPoint("TOP", last, "BOTTOM", 0, -3)
  local function Toggle() ShowPane(not pane:IsShown()) end
  if tab.SetCustomOnMouseUpHandler then
    tab:SetCustomOnMouseUpHandler(function(_, button, upInside) if button == "LeftButton" and upInside ~= false then Toggle() end end)
  else
    -- The quest log's tab template would switch the log to this tab's "mode",
    -- which it doesn't have: our own handler instead.
    tab:SetScript("OnMouseUp", function(self, button) if button == "LeftButton" and self:IsMouseOver() then Toggle() end end)
  end
  if not tab.SetCustomOnMouseUpHandler and tab.HookScript then
    tab:HookScript("OnEnter", function(self)
      GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
      GameTooltip:SetText("Roleplay quests", 1, 0.82, 0)
      GameTooltip:Show()
    end)
    tab:HookScript("OnLeave", function() GameTooltip:Hide() end)
  end
  -- Any of the log's own tabs, or the log changing what it shows, gives the space back.
  for _, other in ipairs(own) do
    if other.HookScript then other:HookScript("OnMouseUp", function() ShowPane(false) end) end
  end
  if qmf.SetDisplayMode then pcall(hooksecurefunc, qmf, "SetDisplayMode", function() ShowPane(false) end) end
  if qmf.DetailsFrame then qmf.DetailsFrame:HookScript("OnShow", function() ShowPane(false) end) end
  T:ApplyLogSetting()
end

function T:ApplyLogSetting()
  if not tab then return end
  local want = On() and S().questLogTab ~= false
  tab:SetShown(want)
  if not want then ShowPane(false) end
end

function T:RefreshLog()
  if not pane or not pane:IsShown() then return end
  local list = Quests(false)
  local sel = pane.selected and K.Quests:Log()[pane.selected]
  if not sel or sel.state ~= "active" then sel = list[1]; pane.selected = sel and sel.id end
  pane.count:SetText(#list == 1 and "1 quest" or (#list .. " quests"))
  pane.list:SetItems(list, function(row, e)
    row.icon:SetTexture(e.icon or DEFAULT_ICON)
    row.title:SetText(UI.Escape(e.title or ""))
    local done, total = K.Quests.Progress(e)
    local bits = {}
    local QM = K.QuestMarkers
    local lvl = QM and QM.LevelText(e)
    if lvl then bits[#bits + 1] = ("|cff%sLevel %s|r"):format(QM.LevelHex(e, true) or "000000", lvl) end
    if total > 0 then bits[#bits + 1] = ("%d / %d"):format(done, total) end
    if e.campaign and e.campaign ~= "" then bits[#bits + 1] = UI.Escape(e.campaign)
    elseif e.giver and e.giver ~= "" then bits[#bits + 1] = "From " .. UI.Escape(e.giver) end
    row.sub:SetText(table.concat(bits, "  ·  "))
    local t = K:Theme()
    row.track.ring:SetVertexColor(t.accent[1], t.accent[2], t.accent[3], e.tracked and 1 or 0.35)
    row.track.dot:SetVertexColor(t.accent[1], t.accent[2], t.accent[3], e.tracked and 1 or 0)
    row.sel:SetShown(e.id == pane.selected)
  end)
  local d = pane.detail
  d:SetShown(sel ~= nil)
  pane.open:SetEnabled(sel ~= nil)
  pane.trackBtn:SetShown(sel ~= nil)
  if not sel then return end
  d.title:SetText(UI.Escape(sel.title or ""))
  d.giver:SetText(sel.giver ~= "" and ("From " .. UI.Escape(sel.giver)) or "")
  local lines = {}
  local doneHex = UI.CardHex({ 0.40, 0.80, 0.48 })
  local subHex = UI.Hex(K:Theme().subtle)
  local QM = K.QuestMarkers
  if QM and sel.marker then
    local d = QM.Distance(sel.marker)
    lines[#lines + 1] = ("|cff%s|T%s:12:12|t %s%s|r"):format(subHex, QM.PIN_ICON, QM.Label(sel.marker), d and ("  ·  " .. QM.DistText(d)) or "")
  end
  local QA = K.QuestAuto
  for i, o in ipairs(sel.objectives or {}) do
    if not QA or QA.Visible(sel, i) then
      local words = (QA and QA.CounterPrefix(sel, i) or "") .. UI.Escape(o.text)
      local line = o.done and ("|cff%s- %s|r"):format(doneHex, words) or ("- " .. words)
      if QM and o.marker and not o.done then
        local d = QM.Distance(o.marker)
        line = line .. ("  |cff%s(%s)|r"):format(subHex, d and QM.DistText(d) or QM.Label(o.marker))
      end
      if o.opt then line = line .. ("  |cff%s(optional)|r"):format(subHex) end
      lines[#lines + 1] = line
    end
  end
  d.objectives:SetText(#lines > 0 and table.concat(lines, "\n") or UI.Escape(sel.description or ""))
  pane.trackBtn:SetText(sel.tracked and "Untrack" or "Track")
end

---------------------------------------------------------------------------
-- Start-up and events
---------------------------------------------------------------------------
local ev = CreateFrame("Frame")
ev:RegisterEvent("PLAYER_ENTERING_WORLD")
ev:RegisterEvent("ADDON_LOADED")
ev:SetScript("OnEvent", function(_, event, name)
  if event == "ADDON_LOADED" then
    if name == "Blizzard_WorldMap" or name == "Blizzard_ObjectiveTracker" then C_Timer.After(0, function() K.Try("quest tracker", BuildTab); T:Refresh() end) end
    return
  end
  -- The game builds its tracker sections after entering the world.
  C_Timer.After(1, function() T:Refresh(); K.Try("quest tracker", BuildTab) end)
end)

K:On("LOGIN", function()
  local s = K.db.settings
  if s.questLogTab == nil then s.questLogTab = true end
  if _G.WorldMapFrame then _G.WorldMapFrame:HookScript("OnShow", function() K.Try("quest tracker", BuildTab); T:RefreshLog() end) end
end)
K:On("QUESTS", function() T:Refresh(); T:RefreshLog() end)
K:On("QUEST_TICK", function() T:Refresh() end)
K:On("EXTENDED", function() T:Refresh(); T:ApplyLogSetting() end)
