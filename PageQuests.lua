-- Kinship RP: Quests page. Three tabs:
--   Journal    - the quests you're on (and the ones you've finished), read
--                like a quest giver's page, with an objective checklist
--   Write      - write a quest with a live preview, then share or run it
--   Campaigns  - quests gathered by campaign, with progress

local ADDON, ns = ...
local K = ns.K
local UI = K.UI
local Q = K.Quests

local WHITE = "Interface\\Buttons\\WHITE8X8"
local CW, CH, TOP = 696, 466, 40
local BODY_H = CH - TOP
local LIST_W = 262
local ROW_W = LIST_W - 24          -- UI.List rows: width minus padding and scrollbar
local STATES = Q.STATES
local Short = Q.Short

local function Clean(s) return UI.Clean(s or "") end

-- A thin progress bar that glides to its value.
local function Bar(parent, w, h)
  local b = CreateFrame("Frame", nil, parent)
  b:SetSize(w, h)
  b.track = b:CreateTexture(nil, "ARTWORK")
  b.track:SetAllPoints()
  b.track:SetTexture(WHITE)
  b.fill = b:CreateTexture(nil, "ARTWORK", nil, 1)
  b.fill:SetPoint("TOPLEFT")
  b.fill:SetPoint("BOTTOMLEFT")
  b.fill:SetTexture(WHITE)
  b.fill:SetWidth(1)
  b.p = 0
  local function draw(v)
    b.fill:SetWidth(math.max(1, w * v))
    b.fill:SetShown(v > 0.002)
  end
  function b:SetValue(p, color, animate)
    p = math.max(0, math.min(1, p or 0))
    local c = color or K:Theme().accent
    self.fill:SetVertexColor(c[1], c[2], c[3], 1)
    if animate and math.abs(p - self.p) > 0.001 then
      local from = self.p
      UI.SetProgress(self, 0)
      UI.Tween(self, 1, 0.5, function(e) draw(from + (p - from) * e) end, UI.Ease.outQuart)
    else
      draw(p)
    end
    self.p = p
  end
  UI:OnTheme(function(t) b.track:SetVertexColor(t.panelEdge[1], t.panelEdge[2], t.panelEdge[3], 0.16) end)
  return b
end

-- Round icon in a coloured ring (list rows, headers).
local function Medal(parent, size)
  local m = {}
  m.ring = UI.Circle(parent, size, "ARTWORK", 0)
  m.icon = parent:CreateTexture(nil, "ARTWORK", nil, 1)
  m.icon:SetSize(size - 4, size - 4)
  m.icon:SetPoint("CENTER", m.ring)
  m.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
  UI.Round(m.icon)
  function m:Set(icon, color)
    self.icon:SetTexture(icon or Q.DEFAULT_ICON)
    local c = color or K:Theme().ui
    self.ring:SetVertexColor(c[1], c[2], c[3], 1)
  end
  return m
end

-- An empty-state medallion with a line of text, laid over a card.
local function EmptyState(parent, icon, text)
  local e = CreateFrame("Frame", nil, parent)
  e:SetAllPoints()
  local art = e:CreateTexture(nil, "ARTWORK")
  art:SetTexture(K.Art(icon))
  art:SetSize(64, 64)
  art:SetPoint("CENTER", 0, 28)
  art:SetAlpha(0.8)
  local t = UI.Text(e, text, "Read", "subtle", 280)
  t:SetPoint("TOP", art, "BOTTOM", 0, -12)
  t:SetJustifyH("CENTER")
  t:SetSpacing(3)
  return e
end

local function SortByTime(field)
  return function(a, b) return (a[field] or 0) > (b[field] or 0) end
end

---------------------------------------------------------------------------
-- Journal
---------------------------------------------------------------------------
local function QuestMenu(owner, e)
  UI.Menu(owner, function(root)
    root:CreateTitle(Clean(e.title))
    if e.state == "active" then
      root:CreateButton(e.tracked and "Stop tracking" or "Track", function() Q:Track(e.id, not e.tracked) end)
      root:CreateButton("Set aside", function() Q:Abandon(e.id) end)
    else
      root:CreateButton("Take it up again", function() Q:Resume(e.id) end)
      root:CreateButton("Remove from journal", function() Q:Forget(e.id) end)
    end
  end)
end

local function BuildJournal(tab)
  tab.filter = "active"
  tab.seg = UI.Segments(tab, {
    { key = "active", label = "Active" }, { key = "complete", label = "Completed" }, { key = "failed", label = "Failed" },
    { key = "abandoned", label = "Set aside" },
  }, 65, function(k) tab.filter = k; tab.selected = nil; K.Journal:RefreshCurrent() end)
  tab.seg:Fit(56)   -- "Completed" needs more than a quarter of the list's width
  tab.seg:SetPoint("TOPLEFT", 0, 0)

  tab.list = UI.List(tab, LIST_W, BODY_H - 34, 56,
    "No quests here yet. Accept one from a friend, or write your own under Write.",
    function(row)
      row.medal = Medal(row, 34)
      row.medal.ring:SetPoint("LEFT", 10, 0)
      row.title = UI.Text(row, "", "Header", "heading", ROW_W - 54 - 46)
      row.title:SetPoint("TOPLEFT", 54, -9)
      row.title:SetWordWrap(false)
      row.sub = UI.Text(row, "", "Small", "subtle", ROW_W - 54 - 12)
      row.sub:SetPoint("TOPLEFT", row.title, "BOTTOMLEFT", 0, -3)
      row.sub:SetWordWrap(false)
      row.count = UI.Text(row, "", "Small", "accent")
      row.count:SetPoint("TOPRIGHT", -10, -11)
      row.bar = Bar(row, ROW_W - 54 - 10, 2)
      row.bar:SetPoint("BOTTOMLEFT", 54, 8)
      row.pin = UI.Circle(row, 8, "OVERLAY")
      row.pin:SetPoint("CENTER", row.medal.ring, "TOPRIGHT", -4, -4)
      row:SetScript("OnClick", function(self, button)
        if button == "RightButton" then QuestMenu(self, self.item) return end
        tab.selected = self.item.id
        K.Journal:RefreshCurrent()
      end)
    end, { emptyIcon = K.Art("IconMilestone") })
  tab.list:SetPoint("TOPLEFT", 0, -34)

  -- The reading view
  local SW = CW - LIST_W - 10
  local sheet = Q.Sheet(tab, SW, BODY_H, { bottom = 54 })
  sheet:SetPoint("TOPLEFT", LIST_W + 10, 0)
  tab.sheet = sheet
  local fdiv = UI.Divider(sheet, SW - 36)
  fdiv:SetPoint("BOTTOMLEFT", 18, 46)

  tab.primary = UI.Button(sheet, "", 104, 26)
  tab.primary:SetPoint("BOTTOMRIGHT", -16, 12)
  tab.secondary = UI.Button(sheet, "", 96, 26)
  tab.secondary:SetPoint("RIGHT", tab.primary, "LEFT", -6, 0)
  tab.tertiary = UI.Button(sheet, "", 104, 26)
  tab.tertiary:SetPoint("RIGHT", tab.secondary, "LEFT", -6, 0)

  -- Storyteller: who is following the quest
  tab.following = CreateFrame("Button", nil, sheet)
  tab.following:SetSize(90, 26)
  tab.following:SetPoint("BOTTOMLEFT", 16, 12)
  tab.following.text = UI.Text(tab.following, "", "Small", "accent", 90)
  tab.following.text:SetPoint("LEFT", 2, 0)
  tab.following.text:SetWordWrap(false)
  tab.following:SetScript("OnEnter", function(self)
    local e = tab.shown
    if not e or not e.players then return end
    GameTooltip:SetOwner(self, "ANCHOR_TOP")
    GameTooltip:SetText("Following your quest", 1, 0.82, 0)
    for _, p in pairs(e.players) do
      local st = STATES[p.s] or STATES.abandoned
      local label = p.s == "declined" and "Declined" or st.label
      GameTooltip:AddDoubleLine(Short(p.name), label, 1, 1, 1, st.color[1], st.color[2], st.color[3])
    end
    GameTooltip:AddLine(" ")
    GameTooltip:AddLine("Tick objectives and everyone who accepted sees your progress.", 0.8, 0.8, 0.8, true)
    GameTooltip:Show()
  end)
  tab.following:SetScript("OnLeave", function() GameTooltip:Hide() end)

  tab.empty = CreateFrame("Frame", nil, tab)
  tab.empty:SetPoint("TOPLEFT", sheet)
  tab.empty:SetPoint("BOTTOMRIGHT", sheet)
  local ebg = UI.Panel(tab.empty)
  ebg:SetAllPoints()
  local es = EmptyState(ebg, "IconMilestone", "Choose a quest to read it, or write one of your own under Write.")
  es:SetAllPoints()
end

local function Button(b, label, fn, w)
  b:SetShown(label ~= nil)
  if not label then return end
  b:SetText(label)
  b:SetWidth(w or 96)
  b:SetScript("OnClick", fn)
end

local function RefreshJournal(tab, c)
  tab.seg:Select(tab.filter)
  local items = {}
  for _, e in pairs(Q:Log()) do if e.state == tab.filter then items[#items + 1] = e end end
  table.sort(items, SortByTime(tab.filter == "active" and "accepted" or "completed"))

  tab.list:SetItems(items, function(row, e)
    local st = STATES[e.state] or STATES.active
    row.medal:Set(e.icon, Q:IsMine(e) and K:Theme().accent or st.color)
    row.title:SetText(Clean(e.title))
    local camp = Clean(e.campaign)
    local giver = Clean(e.giver)
    row.sub:SetText(camp ~= "" and camp or (giver ~= "" and giver or (Q:IsMine(e) and "Your own story" or ("From " .. Short(e.author)))))
    local done, total = Q.Progress(e)
    row.count:SetText(total > 0 and ("%d/%d"):format(done, total) or "")
    row.bar:SetShown(total > 0)
    if total > 0 then row.bar:SetValue(done / total, e.state == "complete" and Q.DONE or nil) end
    local u = K:Theme().accent
    row.pin:SetVertexColor(u[1], u[2], u[3], 1)
    row.pin:SetShown(e.tracked and e.state == "active")
    row.sel:SetShown(e.id == tab.selected)
  end)

  local e = tab.selected and Q:Log()[tab.selected]
  if not e and items[1] then e = items[1]; tab.selected = e.id; tab.list:SetItems(items) end
  tab.sheet:SetShown(e ~= nil)
  tab.empty:SetShown(e == nil)
  tab.shown = e
  if not e then return end

  local animate = c.animate and c.animate.id == e.id and c.animate.i or nil
  c.animate = nil
  if tab.lastShown ~= e.id then tab.lastShown = e.id; UI.FadeIn(tab.sheet, 0.2) end
  local mine = Q:IsMine(e)
  tab.sheet:SetQuest(e, {
    interactive = Q:CanTick(e), animate = animate, keepScroll = true,
    onToggle = function(i) local o = e.objectives[i]; if o then Q:SetObjective(e.id, i, not o.done) end end,
  })
  local st = STATES[e.state] or STATES.active
  if e.state == "active" and mine then tab.sheet.chip:Set("Storyteller", K:Theme().accent)
  else tab.sheet.chip:Set(st.label, st.color) end

  -- Footer buttons, right to left
  if e.state == "active" then
    Button(tab.primary, e.tracked and "Untrack" or "Track", function() Q:Track(e.id, not e.tracked) end, 92)
    Button(tab.secondary, "Set aside", function() Q:Abandon(e.id) end, 92)
    local _, total = Q.Required(e)
    if mine then
      Button(tab.tertiary, "Mark complete", function() Q:Complete(e.id) end, 112)
    elseif total == 0 or not e.st then
      Button(tab.tertiary, "Complete", function() Q:Complete(e.id) end, 96)
    else
      Button(tab.tertiary, nil)
    end
  else
    Button(tab.primary, "Remove", function() Q:Forget(e.id); tab.selected = nil end, 92)
    Button(tab.secondary, "Take it up", function() Q:Resume(e.id); tab.filter = "active" end, 100)
    Button(tab.tertiary, nil)
  end

  local n = 0
  for _, p in pairs(e.players or {}) do if p.s == "active" or p.s == "complete" then n = n + 1 end end
  tab.following:SetShown(mine and n > 0)
  tab.following.text:SetText(n == 1 and "1 following" or (n .. " following"))
end

---------------------------------------------------------------------------
-- Write
---------------------------------------------------------------------------
local ED_W = 350
local OBJ_MIN = 3

-- A small round map-pin button: lit when a marker is set; click for the menu.
local function PinButton(parent, title, get, set)
  local QM = K.QuestMarkers
  local b = CreateFrame("Button", nil, parent)
  b:SetSize(24, 24)
  b.ring = UI.Circle(b, 22, "ARTWORK", 0)
  b.ring:SetPoint("CENTER")
  b.icon = b:CreateTexture(nil, "ARTWORK", nil, 1)
  b.icon:SetSize(18, 18)
  b.icon:SetPoint("CENTER")
  b.icon:SetTexture(QM and QM.PIN_ICON or (K.Art("IconPlace")))
  function b:Paint(p)
    local a, on = K:Theme().accent, get() ~= nil
    self.ring:SetVertexColor(a[1], a[2], a[3], on and (0.75 + 0.25 * (p or 0)) or (0.15 + 0.35 * (p or 0)))
    self.icon:SetDesaturated(not on)
    self.icon:SetAlpha(on and 1 or 0.55)
  end
  b:SetScript("OnEnter", function(self)
    UI.Tween(self, 1, 0.1, function(p) self:Paint(p) end)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:SetText(title, 1, 0.82, 0)
    local mk = get()
    GameTooltip:AddLine(mk and QM and QM.Label(mk) or "No marker. Click to set one.", 1, 1, 1, true)
    if mk and mk.r then GameTooltip:AddLine(("An area %d yards across."):format(mk.r * 2), 0.75, 0.75, 0.75) end
    GameTooltip:Show()
  end)
  b:SetScript("OnLeave", function(self) UI.Tween(self, 0, 0.12, function(p) self:Paint(p) end); GameTooltip:Hide() end)
  b:SetScript("OnClick", function(self)
    if QM then QM:Menu(self, title, get, function(mk) set(mk); self:Paint(UI.Progress(self)) end) end
  end)
  UI:OnTheme(function() b:Paint(UI.Progress(b)) end)
  return b
end

-- A small round button for how an objective completes: its rule's icon when it has one.
local function RuleButton(parent, get, onClick)
  local b = CreateFrame("Button", nil, parent)
  b:SetSize(24, 24)
  b.ring = UI.Circle(b, 22, "ARTWORK", 0)
  b.ring:SetPoint("CENTER")
  b.icon = b:CreateTexture(nil, "ARTWORK", nil, 1)
  b.icon:SetSize(18, 18)
  b.icon:SetPoint("CENTER")
  b.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
  UI.Round(b.icon)
  function b:Paint(p)
    local QA = K.QuestAuto
    local rule, opts = get()
    local set = rule ~= nil or (opts ~= nil and next(opts) ~= nil)
    local kind = rule and QA and QA.KINDS[rule.k]
    self.icon:SetTexture(kind and kind.icon or "Interface\\Icons\\Spell_Nature_Lightning")
    self.icon:SetDesaturated(not set)
    self.icon:SetAlpha(set and 1 or 0.55)
    local a = K:Theme().accent
    self.ring:SetVertexColor(a[1], a[2], a[3], set and (0.75 + 0.25 * (p or 0)) or (0.15 + 0.35 * (p or 0)))
  end
  b:SetScript("OnEnter", function(self)
    UI.Tween(self, 1, 0.1, function(p) self:Paint(p) end)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:SetText("Completes when...", 1, 0.82, 0)
    local QA = K.QuestAuto
    local rule, opts = get()
    GameTooltip:AddLine(rule and QA and QA.Describe(rule, parent.objectiveForRule and parent:objectiveForRule())
      or "Ticked by hand. Click to make it complete itself.", 1, 1, 1, true)
    local more = QA and QA.DescribeOptions(opts)
    if more then GameTooltip:AddLine(more, 0.75, 0.75, 0.75, true) end
    GameTooltip:Show()
  end)
  b:SetScript("OnLeave", function(self) UI.Tween(self, 0, 0.12, function(p) self:Paint(p) end); GameTooltip:Hide() end)
  b:SetScript("OnClick", function(self) onClick(self) end)
  UI:OnTheme(function() b:Paint(UI.Progress(b)) end)
  return b
end

local function BuildWrite(tab)
  tab.draft = tab.draft or Q:NewDraft()   -- the widgets read it as they're built
  tab.pick = UI.Button(tab, "", 200, 24)
  tab.pick:SetPoint("TOPLEFT", 0, 0)
  tab.pick:SetScript("OnClick", function(self)
    UI.Menu(self, function(root)
      root:CreateTitle("Your quests")
      local list = {}
      for _, q in pairs(Q:Library()) do list[#list + 1] = q end
      table.sort(list, SortByTime("edited"))
      if #list == 0 then root:CreateTitle("Nothing written yet") end
      for _, q in ipairs(list) do
        root:CreateButton(Clean(q.title), function() tab:Load(q) end)
      end
      root:CreateDivider()
      root:CreateButton("Start a new quest", function() tab:Load(nil) end)
    end)
  end)
  UI.Tooltip(tab.pick, "Your quests", "Choose a quest from your library to edit it.")
  tab.new = UI.Button(tab, "New quest", 96, 24)
  tab.new:SetPoint("LEFT", tab.pick, "RIGHT", 6, 0)
  tab.new:SetScript("OnClick", function() tab:Load(nil) end)
  tab.status = UI.Text(tab, "", "Small", "deskSubtle", 124)
  tab.status:SetPoint("LEFT", tab.new, "RIGHT", 10, 0)
  tab.status:SetWordWrap(false)

  tab.save = UI.Button(tab, "Save", 80, 24)
  tab.save:SetPoint("TOPRIGHT", 0, 0)
  tab.save:SetScript("OnClick", function() tab:SaveDraft() end)
  tab.share = UI.Button(tab, "Share...", 90, 24)
  tab.share:SetPoint("RIGHT", tab.save, "LEFT", -6, 0)
  tab.share:SetScript("OnClick", function(self)
    UI.Menu(self, function(root)
      root:CreateTitle("Share this quest")
      local function go(how)
        local q = tab:SaveDraft()
        if not q then return end
        local ok, msg = Q:Share(q.id, how)
        tab:Say(msg, not ok)
        if ok then K:Print(msg) end
      end
      root:CreateButton("Offer to my group", function() go("group") end)
      root:CreateButton("Offer to my target", function() go("target") end)
      root:CreateDivider()
      root:CreateButton("Run it myself", function()
        local q = tab:SaveDraft()
        if q and Q:Start(q.id) then tab:Say("It's in your journal.") end
      end)
    end)
  end)
  tab.del = UI.Button(tab, "Delete", 74, 24)
  tab.del:SetPoint("RIGHT", tab.share, "LEFT", -6, 0)
  tab.del:SetScript("OnClick", function(self)
    local id = tab.draft.id
    if not id or not Q:Library()[id] then tab:Load(nil) return end
    if not self.armed then
      self.armed = true
      self:SetText("Sure?")
      C_Timer.After(3, function() self.armed = false; self:SetText("Delete") end)
      return
    end
    self.armed = false
    self:SetText("Delete")
    Q:Delete(id)
    tab:Load(nil)
    tab:Say("Deleted. Anyone already on it keeps their copy.")
  end)
  UI.Tooltip(tab.del, "Delete", "Remove this quest from your library. Copies in journals stay.")

  -- The editor card (scrolls)
  local ed = UI.Panel(tab)
  ed:SetPoint("TOPLEFT", 0, -34)
  ed:SetSize(ED_W, BODY_H - 34)
  local sf = CreateFrame("ScrollFrame", nil, ed)
  sf:SetPoint("TOPLEFT", 16, -14)
  sf:SetPoint("BOTTOMRIGHT", -22, 14)
  local IW = ED_W - 16 - 22
  local body = CreateFrame("Frame", nil, sf)
  body:SetSize(IW, 1)
  sf:SetScrollChild(body)
  tab.edScroll = UI.ScrollBar(sf, false, 48)
  tab.body = body

  local function changed() tab:Changed() end
  tab.title = UI.Field(body, "Quest title", IW - 52, Q.MAX.title, function(v) tab.draft.title = v; changed() end)
  tab.title:SetPoint("TOPLEFT", 0, 0)

  local ib = CreateFrame("Button", nil, body)
  ib:SetSize(42, 42)
  ib:SetPoint("TOPRIGHT", 0, 0)
  ib.ring = UI.Circle(ib, 42, "ARTWORK", 0)
  ib.ring:SetPoint("CENTER")
  ib.icon = ib:CreateTexture(nil, "ARTWORK", nil, 1)
  ib.icon:SetSize(38, 38)
  ib.icon:SetPoint("CENTER")
  ib.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
  UI.Round(ib.icon)
  local function paintIcon(p)
    local a = K:Theme().accent
    ib.ring:SetVertexColor(a[1], a[2], a[3], 0.45 + 0.55 * p)
  end
  ib:SetScript("OnEnter", function(self)
    UI.Tween(self, 1, 0.12, paintIcon)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:SetText("Quest icon", 1, 0.82, 0)
    GameTooltip:AddLine("Click to choose an icon.", 1, 1, 1)
    GameTooltip:Show()
  end)
  ib:SetScript("OnLeave", function(self) UI.Tween(self, 0, 0.15, paintIcon); GameTooltip:Hide() end)
  ib:SetScript("OnClick", function(self)
    Q.PickIcon(self, tab.draft.icon, function(icon) tab.draft.icon = icon; changed() end)
  end)
  UI:OnTheme(function() paintIcon(UI.Progress(ib)) end)
  tab.iconBtn = ib

  local half = math.floor((IW - 10) / 2)
  tab.giver = UI.Field(body, "Quest giver", half, Q.MAX.giver, function(v) tab.draft.giver = v; changed() end)
  tab.giver:SetPoint("TOPLEFT", 0, -50)
  tab.campaign = UI.Field(body, "Campaign (optional)", half, Q.MAX.campaign, function(v) tab.draft.campaign = v; changed() end)
  tab.campaign:SetPoint("TOPLEFT", half + 10, -50)

  local dl = UI.Text(body, "The story", "Label", "subtle")
  dl:SetPoint("TOPLEFT", 1, -98)
  tab.desc = UI.TextArea(body, IW, 110, Q.MAX.desc, function(v) tab.draft.description = v; changed() end)
  tab.desc:SetPoint("TOPLEFT", 0, -112)

  local ol = UI.Text(body, "Objectives", "Label", "subtle")
  ol:SetPoint("TOPLEFT", 1, -232)
  tab.objectives = {}
  for i = 1, Q.MAX.objectives do
    local r = CreateFrame("Frame", nil, body)
    r:SetSize(IW, 24)
    r.dot = UI.Circle(r, 8, "ARTWORK")
    r.dot:SetPoint("LEFT", 4, 0)
    r.edit = UI.Edit(r, IW - 18 - 58, 24, nil, Q.MAX.objective)
    r.edit:SetPoint("LEFT", 18, 0)
    function r:objectiveForRule() return { marker = self.marker } end
    r.rule = RuleButton(r, function() return r.auto, r.opts end, function()
      if not K.QuestAuto then return end
      local text = strtrim(r.edit:GetText() or "")
      -- The objective, with the others it could open if it fails (numbered as players will see them).
      local here
      here = { marker = r.marker, index = 0, others = function()
        local out, n = {}, 0
        for _, other in ipairs(tab.objectives) do
          local t = other:IsShown() and strtrim(other.edit:GetText() or "") or ""
          if t ~= "" then
            n = n + 1
            out[#out + 1] = { index = n, text = t }
            if other == r then here.index = n end
          end
        end
        return out
      end }
      here.others()
      K.QuestAuto:Edit(tab, here, text ~= "" and text or ("Objective " .. i),
        function() return r.auto, r.opts end,
        function(rule, opts)
          r.auto = rule
          r.opts = (opts and next(opts)) and opts or nil
          r.rule:Paint(0)
          tab:ReadObjectives()
          tab:Changed()
        end)
    end)
    r.rule:SetPoint("RIGHT", -28, 0)
    r.pin = PinButton(r, "Where for this objective", function() return r.marker end, function(mk)
      r.marker = mk
      tab:ReadObjectives()
      tab:Changed()
    end)
    r.pin:SetPoint("RIGHT", 0, 0)
    r.edit:SetScript("OnTextChanged", function(self, user) if user then tab:ReadObjectives(); changed() end end)
    r.edit:SetScript("OnTabPressed", function()
      local nxt = tab.objectives[i + 1]
      if nxt and nxt:IsShown() then nxt.edit:SetFocus() end
    end)
    UI:OnTheme(function(t) r.dot:SetVertexColor(t.subtle[1], t.subtle[2], t.subtle[3], 0.6) end)
    tab.objectives[i] = r
  end

  tab.reward = UI.Field(body, "Reward (optional)", IW - 140, Q.MAX.reward, function(v) tab.draft.reward = v; changed() end)

  -- Kinship items as rewards: made from your designs, sent when players finish (QuestRewards.lua)
  local ir = CreateFrame("Frame", nil, body)
  ir:SetSize(IW, 48)
  tab.itemsRow = ir
  ir.label = UI.Text(ir, "Reward items (made from your designs and sent for you)", "Label", "subtle")
  ir.label:SetPoint("TOPLEFT", 1, 0)
  ir.slots = {}
  local function Items() tab.draft.items = tab.draft.items or {}; return tab.draft.items end
  for j = 1, 4 do
    local sl = K.Items.NewSlot(ir, 30)
    sl:SetScript("OnEnter", function(self)
      local it = tab.draft.items and tab.draft.items[j]
      if it then K.Items:ShowTooltip(self, K.Items:Get(it.d), it.n) end
    end)
    sl:SetScript("OnLeave", function() GameTooltip:Hide() end)
    sl:SetScript("OnClick", function(self)
      local list = Items()
      local it = list[j]
      if not it then return end
      UI.Menu(self, function(root)
        root:CreateTitle(K.Items:Label(K.Items:Get(it.d)))
        for _, n in ipairs({ 1, 2, 3, 5, 10, 20 }) do
          root:CreateRadio(n == 1 and "One" or (n .. " of them"), function() return it.n == n end,
            function() it.n = n; tab:PaintItems(); changed() end)
        end
        root:CreateButton("Remove", function()
          table.remove(list, j)
          if #list == 0 then tab.draft.items = nil end
          tab:PaintItems()
          changed()
        end)
      end)
    end)
    ir.slots[j] = sl
  end
  ir.add = UI.Button(ir, "Add an item", 110, 26)
  ir.add:SetScript("OnClick", function(self)
    UI.Menu(self, function(root)
      root:CreateTitle("Your item designs")
      local designs = K.Items:Designs()
      if #designs == 0 then root:CreateTitle("Design one in Inventory > Workshop first") end
      local have = {}
      for _, it in ipairs(tab.draft.items or {}) do have[it.d] = true end
      for _, def in ipairs(designs) do
        if not have[def.id] then
          root:CreateButton(def.name, function()
            local list = Items()
            if #list < 4 then list[#list + 1] = { d = def.id, n = 1 } end
            tab:PaintItems()
            changed()
          end)
        end
      end
    end)
  end)
  ir.pick = UI.Toggle(ir, "They choose one", nil, function() return tab.draft.pick and true or false end,
    function(v) tab.draft.pick = v or nil; changed() end, 160, true)
  function tab:PaintItems()
    local list = self.draft.items or {}
    local x = 0
    for j, sl in ipairs(ir.slots) do
      local it = list[j]
      sl:SetShown(it ~= nil)
      if it then
        sl:ClearAllPoints()
        sl:SetPoint("TOPLEFT", x, -16)
        sl:SetItem(K.Items:Get(it.d), it.n, K.Items:Get(it.d) == nil)
        x = x + 34
      end
    end
    ir.add:SetShown(#list < 4)
    ir.add:ClearAllPoints()
    ir.add:SetPoint("TOPLEFT", x + (x > 0 and 6 or 0), -18)
    ir.pick:SetShown(#list > 1)
    ir.pick:ClearAllPoints()
    ir.pick:SetPoint("TOPRIGHT", 0, -20)
    ir.pick:Refresh()
  end
  -- Level, or a range
  local function lvl(field) return function(v) tab.draft[field] = tonumber(v); changed() end end
  tab.levelMin = UI.Field(body, "Level", 56, 3, lvl("level"))
  tab.levelMin.edit:SetNumeric(true)
  tab.levelMax = UI.Field(body, "to (optional)", 70, 3, lvl("levelMax"))
  tab.levelMax.edit:SetNumeric(true)
  UI.Tooltip(tab.levelMin.edit, "Level", "The level this quest is meant for. Shown in the colour the game uses for quests at that level.")
  -- Where it happens
  tab.whereRow = CreateFrame("Frame", nil, body)
  tab.whereRow:SetSize(IW, 40)
  local wl = UI.Text(tab.whereRow, "Where it happens (optional)", "Label", "subtle")
  wl:SetPoint("TOPLEFT", 1, 0)
  tab.wherePin = PinButton(tab.whereRow, "Where it happens", function() return tab.draft.marker end, function(mk)
    tab.draft.marker = mk
    changed()
  end)
  tab.wherePin:SetPoint("TOPLEFT", 0, -14)
  tab.whereText = UI.Text(tab.whereRow, "", "Small", "text", IW - 34)
  tab.whereText:SetPoint("LEFT", tab.wherePin, "RIGHT", 8, 0)
  tab.whereText:SetWordWrap(false)
  tab.st = UI.Toggle(body, "Storyteller mode", "Only you tick objectives. Everyone who accepted sees your progress as it happens.",
    function() return tab.draft.st ~= false end,
    function(v) tab.draft.st = v; changed() end, IW, true)
  tab.au = UI.Toggle(body, "Let objectives complete themselves",
    "Objectives with a rule tick when a player meets it, for everyone. Off: only you tick them, and you're told when someone meets one.",
    function() return tab.draft.au ~= false end,
    function(v) tab.draft.au = v; changed() end, IW, true)
  tab.seq = UI.Toggle(body, "In order", "One objective at a time: each opens when the one before is done.",
    function() return tab.draft.seq and true or false end,
    function(v) tab.draft.seq = v or nil; changed() end, IW, true)

  -- Live preview
  tab.preview = Q.Sheet(tab, CW - ED_W - 10, BODY_H - 34)
  tab.preview:SetPoint("TOPLEFT", ED_W + 10, -34)

  function tab:ReadObjectives()
    local list = {}
    for _, r in ipairs(self.objectives) do
      if r:IsShown() then
        local text = strtrim(r.edit:GetText() or "")
        if text ~= "" then
          local op = r.opts or {}
          list[#list + 1] = { text = text, marker = r.marker, auto = r.auto, opt = op.opt, hid = op.hid, fl = op.fl }
        end
      end
    end
    self.draft.objectives = list
  end

  -- Objective rows: the filled ones plus one empty (at least three).
  function tab:Layout()
    local last = 0
    for i, r in ipairs(self.objectives) do
      if strtrim(r.edit:GetText() or "") ~= "" then last = i end
    end
    local n = math.min(Q.MAX.objectives, math.max(OBJ_MIN, last + 1))
    local y = -246
    for i, r in ipairs(self.objectives) do
      r:SetShown(i <= n)
      if i <= n then
        r:ClearAllPoints()
        r:SetPoint("TOPLEFT", 0, y)
        y = y - 28
      end
    end
    self.reward:ClearAllPoints()
    self.reward:SetPoint("TOPLEFT", 0, y - 6)
    self.levelMin:ClearAllPoints()
    self.levelMin:SetPoint("TOPLEFT", IW - 130, y - 6)
    self.levelMax:ClearAllPoints()
    self.levelMax:SetPoint("TOPLEFT", IW - 66, y - 6)
    y = y - 6 - 40 - 6
    self.itemsRow:ClearAllPoints()
    self.itemsRow:SetPoint("TOPLEFT", 0, y)
    self:PaintItems()
    y = y - 48 - 6
    self.whereRow:ClearAllPoints()
    self.whereRow:SetPoint("TOPLEFT", 0, y)
    local QM = K.QuestMarkers
    local mk = self.draft.marker
    self.whereText:SetText(mk and QM and QM.Label(mk) or "|cff8a8a8aNo marker: click the pin to mark where you stand or pick a spot on the map.|r")
    y = y - 40 - 6
    self.st:ClearAllPoints()
    self.st:SetPoint("TOPLEFT", 0, y)
    self.st:Refresh()
    y = y - self.st:GetHeight() - 8
    local storyteller = self.draft.st ~= false
    self.au:SetShown(storyteller)
    if storyteller then
      self.au:ClearAllPoints()
      self.au:SetPoint("TOPLEFT", 0, y)
      self.au:Refresh()
      y = y - self.au:GetHeight() - 8
    end
    self.seq:ClearAllPoints()
    self.seq:SetPoint("TOPLEFT", 0, y)
    self.seq:Refresh()
    y = y - self.seq:GetHeight() - 8
    self.body:SetHeight(-y)
    self.edScroll.Update()
  end

  function tab:Preview()
    local d = self.draft
    local p = {
      title = d.title, giver = d.giver, campaign = d.campaign, description = d.description, reward = d.reward,
      icon = Q.ValidIcon(d.icon) or Q.DEFAULT_ICON, objectives = {}, author = K:MyName(),
      level = d.level, levelMax = d.levelMax, marker = d.marker, seq = d.seq,
      items = K.QuestRewards and K.QuestRewards.Sanitize(d.items) or nil,
    }
    p.pick = p.items and #p.items > 1 and d.pick or nil
    for i, o in ipairs(d.objectives or {}) do
      p.objectives[i] = { text = o.text, done = false, marker = o.marker, auto = o.auto, opt = o.opt, hid = o.hid, fl = o.fl }
    end
    self.preview:SetQuest(p, { keepScroll = true })
    self.preview.chip:Set("Preview", K:Theme().accent)
    self.iconBtn.icon:SetTexture(p.icon)
  end

  function tab:Say(text, bad)
    self.status:SetText(text or "")
    local c = bad and UI.OnCard({ 0.95, 0.45, 0.35 }) or nil
    if bad then self.status:SetTextColor(0.95, 0.55, 0.45) else self.status:SetTextColor(unpack(K:Theme().deskSubtle)) end
    if c then return end
  end

  function tab:Changed()
    self.dirty = true
    self:Say("Unsaved changes")
    self:Layout()
    self:Preview()
  end

  function tab:Load(q)
    self.draft = q and CopyTable(q) or Q:NewDraft()
    self.dirty = false
    local d = self.draft
    for _, f in ipairs({ self.title, self.giver, self.campaign }) do f.edit:ClearFocus() end
    self.title.edit:SetText(d.title or "")
    self.giver.edit:SetText(d.giver or "")
    self.campaign.edit:SetText(d.campaign or "")
    -- A set text leaves the cursor, and the view, at its end: show the start.
    for _, f in ipairs({ self.title, self.giver, self.campaign }) do f.edit:SetCursorPosition(0) end
    self.desc.edit:SetText(d.description or "")
    self.reward.edit:SetText(d.reward or "")
    self.levelMin.edit:SetText(d.level and tostring(d.level) or "")
    self.levelMax.edit:SetText(d.levelMax and tostring(d.levelMax) or "")
    for i, r in ipairs(self.objectives) do
      local o = d.objectives and d.objectives[i]
      r.edit:SetText(o and o.text or "")
      r.marker = o and o.marker or nil
      r.auto = o and o.auto or nil
      r.opts = (o and (o.opt or o.hid or o.fl)) and { opt = o.opt, hid = o.hid, fl = o.fl } or nil
      r.pin:Paint(0)
      r.rule:Paint(0)
    end
    self.wherePin:Paint(0)
    self:Layout()
    self:Preview()
    self:Say(q and ("Editing " .. (q.edited and UI.Ago(q.edited) or "")) or "A fresh page")
    self.pick:SetText(q and Clean(q.title) or "Your quests...")
    sf:SetVerticalScroll(0)
    UI.FadeIn(self.preview, 0.2)
  end

  -- Returns the saved quest, or nil (and says why).
  function tab:SaveDraft()
    self:ReadObjectives()
    local q, err = Q:Save(self.draft)
    if not q then self:Say(err, true) return nil end
    self.draft.id = q.id
    self.dirty = false
    self:Say("Saved")
    self.pick:SetText(Clean(q.title))
    if SOUNDKIT and SOUNDKIT.IG_QUEST_LOG_CLOSE then PlaySound(SOUNDKIT.IG_QUEST_LOG_CLOSE) end
    return q
  end

  tab:Load(nil)
end

local function RefreshWrite(tab)
  local id = tab.draft.id
  if id and not Q:Library()[id] then tab.draft.id = nil end
  local any = next(Q:Library()) ~= nil
  if not tab.draft.id then tab.pick:SetText(any and "Your quests..." or "No quests yet") end
end

---------------------------------------------------------------------------
-- Campaigns
---------------------------------------------------------------------------
local function Campaigns()
  local groups, order = {}, {}
  local function add(q, inLog)
    local name = strtrim(q.campaign or "")
    local key = name ~= "" and name:lower() or ""
    local g = groups[key]
    if not g then
      g = { key = key, name = name ~= "" and name or "Standalone quests", quests = {}, done = 0, authors = {}, mine = false }
      groups[key] = g
      order[#order + 1] = g
    end
    g.quests[#g.quests + 1] = { q = q, inLog = inLog }
    if inLog and q.state == "complete" then g.done = g.done + 1 end
    if Q:IsMine(q) or not inLog then g.mine = true
    elseif q.author then g.authors[Short(q.author)] = true end
    g.icon = g.icon or q.icon
    g.t = math.max(g.t or 0, q.accepted or q.edited or 0)
  end
  local log = Q:Log()
  for _, e in pairs(log) do add(e, true) end
  for id, q in pairs(Q:Library()) do if not log[id] then add(q, false) end end
  table.sort(order, function(a, b)
    if (a.key == "") ~= (b.key == "") then return b.key == "" end
    return (a.t or 0) > (b.t or 0)
  end)
  return order
end

local function By(g)
  local names = {}
  for n in pairs(g.authors) do names[#names + 1] = n end
  table.sort(names)
  if g.mine then table.insert(names, 1, "you") end
  if #names == 0 then return "" end
  if #names > 3 then return "By " .. table.concat(names, ", ", 1, 3) .. " and others" end
  return "By " .. table.concat(names, ", ")
end

local function BuildCampaigns(tab, c)
  tab.list = UI.List(tab, LIST_W, BODY_H, 60,
    "No campaigns yet. Give your quests a campaign name under Write and they'll gather here.",
    function(row)
      row.medal = Medal(row, 36)
      row.medal.ring:SetPoint("LEFT", 10, 0)
      row.name = UI.Text(row, "", "Header", "heading", ROW_W - 56 - 44)
      row.name:SetPoint("TOPLEFT", 56, -10)
      row.name:SetWordWrap(false)
      row.sub = UI.Text(row, "", "Small", "subtle", ROW_W - 56 - 12)
      row.sub:SetPoint("TOPLEFT", row.name, "BOTTOMLEFT", 0, -3)
      row.sub:SetWordWrap(false)
      row.pct = UI.Text(row, "", "Small", "accent")
      row.pct:SetPoint("TOPRIGHT", -10, -12)
      row.bar = Bar(row, ROW_W - 56 - 10, 3)
      row.bar:SetPoint("BOTTOMLEFT", 56, 9)
      row:SetScript("OnClick", function(self) tab.selected = self.item.key; K.Journal:RefreshCurrent() end)
    end, { emptyIcon = K.Art("IconPlace") })
  tab.list:SetPoint("TOPLEFT", 0, 0)

  local DW = CW - LIST_W - 10
  local card = UI.Panel(tab)
  card:SetPoint("TOPLEFT", LIST_W + 10, 0)
  card:SetSize(DW, BODY_H)
  tab.card = card
  local d = CreateFrame("Frame", nil, card)
  d:SetAllPoints()
  tab.detail = d
  d.medal = Medal(d, 58)
  d.medal.ring:SetPoint("TOPLEFT", 18, -18)
  d.kicker = UI.Text(d, "CAMPAIGN", "Label", "accent")
  d.kicker:SetPoint("TOPLEFT", d.medal.ring, "TOPRIGHT", 12, -4)
  d.name = UI.Text(d, "", "Huge", "heading", DW - 18 - 58 - 12 - 18)
  d.name:SetPoint("TOPLEFT", d.kicker, "BOTTOMLEFT", 0, -5)
  d.name:SetWordWrap(false)
  d.by = UI.Text(d, "", "Small", "subtle", DW - 18 - 58 - 12 - 18)
  d.by:SetPoint("TOPLEFT", d.name, "BOTTOMLEFT", 0, -5)
  d.by:SetWordWrap(false)
  d.progress = UI.Text(d, "", "Small", "text", DW - 36)
  d.progress:SetPoint("TOPLEFT", 18, -92)
  d.bar = Bar(d, DW - 36, 6)
  d.bar:SetPoint("TOPLEFT", 18, -110)
  local qs = UI.Section(d, "Quests")
  qs:SetPoint("TOPLEFT", 25, -134)

  d.quests = UI.List(d, DW - 24, BODY_H - 156 - 12, 46, "No quests in this campaign.", function(row)
    row.medal = Medal(row, 30)
    row.medal.ring:SetPoint("LEFT", 6, 0)
    row.title = UI.Text(row, "", "Body", "heading", DW - 24 - 12 - 46 - 100)
    row.title:SetPoint("TOPLEFT", 46, -7)
    row.title:SetWordWrap(false)
    row.sub = UI.Text(row, "", "Small", "subtle", DW - 24 - 12 - 46 - 100)
    row.sub:SetPoint("TOPLEFT", row.title, "BOTTOMLEFT", 0, -3)
    row.sub:SetWordWrap(false)
    row.chip = UI.Chip(row)
    row.chip:SetPoint("RIGHT", -8, 0)
    row:SetScript("OnClick", function(self)
      local it = self.item
      if it.inLog then
        local j = c.frames[1]
        j.filter, j.selected = it.q.state, it.q.id
        c.tab = 1
      else
        c.tab = 2
        c.frames[2]:Load(Q:Library()[it.q.id])
      end
      K.Journal:RefreshCurrent()
    end)
    row.onEnter = function(self)
      GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
      GameTooltip:SetText(Clean(self.item.q.title), 1, 0.82, 0)
      GameTooltip:AddLine(self.item.inLog and "Click to read it in your journal." or "Click to open it in the editor.", 1, 1, 1)
      GameTooltip:Show()
    end
  end, { bare = true })
  d.quests:SetPoint("TOPLEFT", 12, -156)

  tab.empty = EmptyState(card, "IconPlace", "Choose a campaign to see how far along it is.")
end

local function RefreshCampaigns(tab)
  local groups = Campaigns()
  tab.list:SetItems(groups, function(row, g)
    row.medal:Set(g.icon, g.key == "" and K:Theme().subtle or K:Theme().ui)
    row.name:SetText(Clean(g.name))
    local n = #g.quests
    row.sub:SetText(("%d quest%s%s"):format(n, n == 1 and "" or "s", g.mine and "  ·  yours" or ""))
    local p = n > 0 and g.done / n or 0
    row.pct:SetText(("%d%%"):format(math.floor(p * 100 + 0.5)))
    row.bar:SetValue(p, g.done == n and n > 0 and Q.DONE or nil)
    row.sel:SetShown(g.key == tab.selected)
  end)

  local g
  for _, x in ipairs(groups) do if x.key == tab.selected then g = x end end
  if not g and groups[1] then g = groups[1]; tab.selected = g.key; tab.list:SetItems(groups) end
  tab.detail:SetShown(g ~= nil)
  tab.empty:SetShown(g == nil)
  if not g then return end
  local fresh = tab.shownKey ~= g.key
  if fresh then tab.shownKey = g.key; UI.FadeIn(tab.detail, 0.2) end

  local d = tab.detail
  d.medal:Set(g.icon, g.key == "" and K:Theme().subtle or K:Theme().ui)
  d.kicker:SetText(g.key == "" and "NO CAMPAIGN" or "CAMPAIGN")
  d.name:SetText(Clean(g.name))
  d.by:SetText(By(g))
  local n = #g.quests
  d.progress:SetText(("%d/%d quest%s complete"):format(g.done, n, n == 1 and "" or "s"))
  if fresh then d.bar.p = 0 end
  d.bar:SetValue(n > 0 and g.done / n or 0, (n > 0 and g.done == n) and Q.DONE or nil, true)

  local rows = {}
  for _, it in ipairs(g.quests) do rows[#rows + 1] = it end
  local rank = { active = 1, complete = 2, failed = 3, abandoned = 4 }
  table.sort(rows, function(a, b)
    local ra, rb = a.inLog and rank[a.q.state] or 4, b.inLog and rank[b.q.state] or 4
    if ra ~= rb then return ra < rb end
    return (a.q.accepted or a.q.edited or 0) > (b.q.accepted or b.q.edited or 0)
  end)
  d.quests:SetItems(rows, function(row, it)
    local q = it.q
    local st = it.inLog and STATES[q.state] or nil
    row.medal:Set(q.icon, st and st.color or K:Theme().subtle)
    row.title:SetText(Clean(q.title))
    if it.inLog then
      local done, total = Q.Progress(q)
      row.sub:SetText(total > 0 and ("%d/%d objectives"):format(done, total) or (Q:IsMine(q) and "Your own story" or ("From " .. Short(q.author))))
      row.chip:Set(Q:IsMine(q) and q.state == "active" and "Storyteller" or st.label, st.color)
    else
      row.sub:SetText("In your library, not yet begun")
      row.chip:Set("Draft", K:Theme().subtle)
    end
  end)
end

---------------------------------------------------------------------------
-- The page
---------------------------------------------------------------------------
K:RegisterPage({
  id = "quests", title = "Quests", heading = "Quests",
  subtitle = "Stories you follow, and the ones you write for others.",
  enabled = function() return K:ExtOn("campaigns") end,
  group = "Stories", icon = { "Interface\\Icons\\INV_Scroll_03", round = true },

  build = function(c)
    c.tab = 1
    c.tabs = UI.TabBar(c, { "Journal", "Write", "Campaigns" }, function(i) c.tab = i; K.Journal:RefreshCurrent() end, true)
    c.tabs:SetPoint("TOPLEFT", -10, 2)
    c.count = UI.Chip(c, "Small", true)
    c.count:SetPoint("TOPRIGHT", 0, -4)
    c.count:SetHeight(22)
    c.frames = {}
    for i = 1, 3 do
      local f = CreateFrame("Frame", nil, c)
      f:SetPoint("TOPLEFT", 0, -TOP)
      f:SetSize(CW, BODY_H)
      f:Hide()
      c.frames[i] = f
    end
    BuildJournal(c.frames[1])
    BuildWrite(c.frames[2])
    BuildCampaigns(c.frames[3], c)

    K:On("QUEST_OBJECTIVE", function(id, i, done)
      if done then c.animate = { id = id, i = i } end
    end)
  end,

  refresh = function(c)
    local focus = Q.focus
    if focus then
      Q.focus = nil
      c.tab = focus.tab or 1
      if c.tab == 1 and focus.id then
        local e = Q:Log()[focus.id]
        if e then c.frames[1].filter, c.frames[1].selected = e.state, e.id end
      elseif c.tab == 2 then
        c.frames[2]:Load(focus.id and Q:Library()[focus.id] or nil)
      end
    end
    c.tabs:Select(c.tab)
    for i, f in ipairs(c.frames) do f:SetShown(i == c.tab) end
    if c.shownTab ~= c.tab then
      if c.shownTab then UI.FadeIn(c.frames[c.tab], 0.2) end
      c.shownTab = c.tab
    end
    local n = 0
    for _, e in pairs(Q:Log()) do if e.state == "active" then n = n + 1 end end
    c.count:Set(n > 0 and (n .. " active") or nil, K:Theme().ui)
    if c.tab == 1 then RefreshJournal(c.frames[1], c)
    elseif c.tab == 2 then RefreshWrite(c.frames[2])
    else RefreshCampaigns(c.frames[3]) end
  end,
})

K:On("QUESTS", function()
  if K.Journal:IsShowing("quests") then K.Journal:RefreshCurrent() end
end)
-- Holds, watches and time limits counting: redraw now and then, unless someone's typing.
K:On("QUEST_TICK", function()
  if K.Journal:IsShowing("quests") and not GetCurrentKeyBoardFocus() then K.Journal:RefreshCurrent() end
end)
