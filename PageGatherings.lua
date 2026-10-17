-- Kinship RP: Gatherings page, a grid of event cards on three boards (guild,
-- house, public; see Sync.lua for how each travels). Clicking a card opens it
-- over the grid; "Post a gathering" posts to the board you're looking at.

local ADDON, ns = ...
local K = ns.K
local UI = K.UI

local WHITE = "Interface\\Buttons\\WHITE8X8"
local SCOPES = {
  { key = "guild", label = "Guild" }, { key = "house", label = "House" }, { key = "public", label = "Public" },
}
local COLS, ROWS, GAP = 3, 3, 10
local W, H, TOP, FOOT = 696, 466, 36, 30

local function GoingCount(g) return #K:GoingNames(g) end

-- What each board says about itself, and when it's empty.
local function BoardNote(scope)
  local S = K.Sync
  if scope == "house" then
    local house = K:HouseName()
    if house == "" then return "Give your character a house name on the Profile page to share with your house." end
    if K.db.settings.gatherHouse == false then return "House gatherings are switched off in Settings." end
    return ("Shared with House %s, passed between members as you see each other."):format(house)
  elseif scope == "public" then
    if K.db.settings.gatherPublic == false then return "Public gatherings are switched off in Settings." end
    return "Shared with Kinship users near you, and passed along as people meet."
  end
  return S.GuildName() and "Shared with your guild. Everyone with Kinship sees the same gatherings."
    or "You're not in a guild, so gatherings here stay on this computer."
end
local EMPTY = {
  guild = "Nothing posted yet. Post a gathering to bring people together.",
  house = "No house gatherings yet. A family dinner, a feud to settle, a wedding: post one for your kin.",
  public = "Nothing nearby yet. Gatherings posted by Kinship users around you appear here, and more arrive as you meet people.",
}
local function Short(n) return Ambiguate and Ambiguate(n, "none") or n end

-- Dates: a gathering's day is noon on that day (see Sync.lua), so it reads
-- as the same day almost everywhere.
local DATE_CHOICES = 42   -- days offered when posting, from today
local function Noon(offset)
  local d = date("*t")
  return time({ year = d.year, month = d.month, day = d.day + (offset or 0), hour = 12 })
end
local function DayText(day, long)
  if type(day) ~= "number" then return nil end
  local diff = math.floor((day - Noon(0)) / 86400 + 0.5)
  if diff == 0 then return "Today" elseif diff == 1 then return "Tomorrow" elseif diff == -1 then return "Yesterday" end
  return date(long and "%A %d %B" or "%a %d %b", day)
end
-- "Fri 23 Oct, 8pm server time", or whichever half is there.
local function WhenText(g, none, long)
  local d, w = DayText(g.day, long), (g.when and g.when ~= "") and g.when or nil
  if d and w then return d .. ", " .. w end
  return d or w or none
end

local function DiscordText(g)
  local lines = {
    ("**%s**"):format(g.title),
    ("**When:** %s"):format(WhenText(g, "To be decided", true)),
    ("**Where:** %s"):format(g.where ~= "" and g.where or "To be decided"),
    ("**Host:** %s"):format(Short(g.host)),
  }
  if g.desc and g.desc ~= "" then lines[#lines + 1] = ""; lines[#lines + 1] = g.desc end
  lines[#lines + 1] = ""
  lines[#lines + 1] = "_Posted with Kinship RP_"
  return table.concat(lines, "\n")
end

---------------------------------------------------------------------------
-- The game's calendar. A gathering with a date can go on your own calendar
-- as a personal event: from the "Add to calendar" button, or as you say
-- you're going (unless that's switched off in Settings). The game only lets
-- this happen from a click, so it's done right in the click, never later.
-- It's your calendar only: others add it themselves.
---------------------------------------------------------------------------
local Cal = {}
K.GatherCalendar = Cal

-- "8pm", "8.30 pm", "20:00", "8:30pm server" -> 20, 0 / 20, 30. nil when there's no time in it.
function Cal.ParseTime(text)
  if type(text) ~= "string" then return nil end
  local s = text:lower()
  local h, m, ap = s:match("(%d%d?)[:%.](%d%d)%s*([ap])%.?m")
  if not h then h, ap = s:match("(%d%d?)%s*([ap])%.?m"); m = "0" end
  if not h then h, m = s:match("(%d%d?)[:%.](%d%d)") end
  h, m = tonumber(h), tonumber(m)
  if not h or not m or m > 59 then return nil end
  if ap == "p" and h < 12 then h = h + 12 elseif ap == "a" and h == 12 then h = 0 end
  if h > 23 then return nil end
  return h, m
end

local function Added()
  K.db.gatherCalendar = K.db.gatherCalendar or {}
  local key = K:CharKey()
  K.db.gatherCalendar[key] = K.db.gatherCalendar[key] or {}
  return K.db.gatherCalendar[key]
end

function Cal.Available()
  return C_Calendar and C_Calendar.CreatePlayerEvent and C_Calendar.AddEvent and C_Calendar.EventSetDate and true or false
end

function Cal.IsAdded(g) return g and g.id and Added()[g.id] ~= nil end

-- Why a gathering can't go on the calendar, or nil when it can.
function Cal.Blocked(g)
  if not Cal.Available() then return "The game's calendar isn't available here." end
  if type(g.day) ~= "number" then return "Give it a date first: only gatherings with a date can go on the calendar." end
  if g.day + 43200 < time() then return "That day has already gone." end
end

-- Cut to n bytes without splitting a letter.
local function Cut(s, n)
  s = tostring(s or "")
  if #s <= n then return s end
  return (s:sub(1, n):gsub("[\192-\255][\128-\191]*$", ""))
end

-- Put a gathering on your calendar. Must run inside a click. quiet: no message when it can't.
function Cal.Add(g, quiet)
  local why = Cal.Blocked(g)
  if why then if not quiet then K:Print(why) end return false end
  local d = date("*t", g.day)
  local hour, minute = Cal.ParseTime(g.when)
  local timed = hour ~= nil
  hour, minute = hour or 20, minute or 0
  local lines = {}
  if g.where and g.where ~= "" then lines[#lines + 1] = "Where: " .. g.where end
  lines[#lines + 1] = "Host: " .. (Ambiguate and Ambiguate(g.host or "", "none") or g.host or "")
  if not timed then lines[#lines + 1] = (g.when and g.when ~= "") and ("Time: " .. g.when) or "Time to be decided" end
  if g.desc and g.desc ~= "" then lines[#lines + 1] = ""; lines[#lines + 1] = g.desc end
  lines[#lines + 1] = ""
  lines[#lines + 1] = "A Kinship gathering"
  local C = C_Calendar
  local ok, err = pcall(function()
    C.CreatePlayerEvent()
    C.EventSetTitle(Cut(g.title, 31))
    if C.EventSetDescription then C.EventSetDescription(Cut(table.concat(lines, "\n"), 255)) end
    if C.EventSetType and Enum and Enum.CalendarEventType and Enum.CalendarEventType.Other then
      C.EventSetType(Enum.CalendarEventType.Other)
    end
    C.EventSetDate(d.month, d.day, d.year)
    C.EventSetTime(hour, minute)
    C.AddEvent()
  end)
  if not ok then
    if not quiet then K:Print("The calendar wouldn't take it: " .. tostring(err)) end
    return false
  end
  Added()[g.id] = time()
  UI.Toast({ icon = K.Art("IconFire"), title = "Added to your calendar", duration = 5,
    text = ("%s, %s at %d:%02d%s"):format(Cut(g.title, 40), date("%a %d %b", g.day), hour, minute,
      timed and "" or " (time to be confirmed)") })
  return true
end

-- The calendar loads its data when it's first asked; ask a little after login
-- (as the game's own clock does), so it's ready by the time you add anything.
K:On("LOGIN", function()
  if C_Calendar and C_Calendar.OpenCalendar then C_Timer.After(10, function() pcall(C_Calendar.OpenCalendar) end) end
end)

-- One gathering on the grid.
local function EventCard(parent, w, h)
  local b = CreateFrame("Button", nil, parent)
  b:SetSize(w, h)
  b.bg = b:CreateTexture(nil, "BACKGROUND")
  b.bg:SetAllPoints()
  b.tint = b:CreateTexture(nil, "BACKGROUND", nil, 1)
  b.tint:SetAllPoints()
  b.edge = UI.Border(b)
  b.bar = b:CreateTexture(nil, "ARTWORK")
  b.bar:SetTexture(WHITE)
  b.bar:SetWidth(3)
  b.bar:SetPoint("TOPLEFT")
  b.bar:SetPoint("BOTTOMLEFT")
  b.icon = b:CreateTexture(nil, "ARTWORK")
  b.icon:SetTexture(K.Art("IconFire"))
  b.icon:SetSize(28, 28)
  b.icon:SetPoint("TOPRIGHT", -10, -10)

  b.title = UI.Text(b, "", "Header", "heading", w - 62)
  b.title:SetPoint("TOPLEFT", 16, -15)
  b.title:SetWordWrap(false)
  b.when = UI.Text(b, "", "Small", "text", w - 32)
  b.when:SetPoint("TOPLEFT", b.title, "BOTTOMLEFT", 0, -10)
  b.when:SetWordWrap(false)
  b.where = UI.Text(b, "", "Small", "subtle", w - 32)
  b.where:SetPoint("TOPLEFT", b.when, "BOTTOMLEFT", 0, -4)
  b.where:SetWordWrap(false)
  b.going = UI.Text(b, "", "Small", "accent")
  b.going:SetPoint("BOTTOMLEFT", 16, 12)
  b.host = UI.Text(b, "", "Small", "subtle", w / 2)
  b.host:SetPoint("BOTTOMRIGHT", -12, 12)
  b.host:SetJustifyH("RIGHT")
  b.host:SetWordWrap(false)

  local function paint(p)
    local t = K:Theme()
    b.bg:SetColorTexture(unpack(t.panel))
    local h = t.hover
    b.tint:SetColorTexture(h[1], h[2], h[3], (h[4] or 1) * p * 1.5)
    local a = t.accent
    local er, eg, eb, ea = UI.Mix(t.panelEdge, { a[1], a[2], a[3], 0.9 }, p)
    b.edge:SetColor(er, eg, eb, ea)
    b.bar:SetVertexColor(a[1], a[2], a[3], 0.55 + 0.45 * p)
    b.icon:SetAlpha(0.85 + 0.15 * p)
  end
  b:SetScript("OnEnter", function(self) UI.Tween(self, 1, 0.12, paint) end)
  b:SetScript("OnLeave", function(self) UI.Tween(self, 0, 0.15, paint) end)
  UI:OnTheme(function() paint(UI.Progress(b)) end)
  b:Hide()
  return b
end

-- "Label   value" line on the detail card.
local function Line(parent, label, y, width)
  local l = UI.Text(parent, label, "GameFontNormalSmall", "subtle")
  l:SetPoint("TOPLEFT", 24, y)
  local v = UI.Text(parent, "", "GameFontHighlightSmall", "text", width)
  v:SetPoint("TOPLEFT", 90, y)
  v:SetWordWrap(false)
  return v
end

local function Input(parent, label, x, y, w)
  local l = UI.Text(parent, label, "GameFontNormalSmall", "subtle")
  l:SetPoint("TOPLEFT", x + 1, y)
  local eb = UI.Edit(parent, w, 24, nil, 60)
  eb:SetPoint("TOPLEFT", x, y - 14)
  return eb
end

K:RegisterPage({
  id = "gatherings", title = "Gatherings", heading = "Gatherings",
  subtitle = "Roleplay events for your guild and friends.",

  build = function(c)
    c.scope, c.pageNum = "guild", 1

    c.scopes = UI.Segments(c, SCOPES, 90, function(key)
      c.scope, c.pageNum, c.selected = key, 1, nil
      K.Journal:RefreshCurrent()
    end)
    c.scopes:SetPoint("TOPLEFT", 0, 0)

    local post = UI.Button(c, "Post a gathering", 140, 24)
    post:SetPoint("TOPRIGHT", 0, 0)
    c.postBtn = post
    post:SetScript("OnClick", function() c:Compose() end)

    local note = UI.Text(c, "", "GameFontHighlightSmall", "deskSubtle")
    c.shareNote = note
    note:SetPoint("LEFT", c.scopes, "RIGHT", 14, 0)
    note:SetWidth(256)

    -- The grid ---------------------------------------------------------------------
    local cw = math.floor((W - GAP * (COLS - 1)) / COLS)
    local ch = math.floor((H - TOP - FOOT - GAP * (ROWS - 1)) / ROWS)
    c.cards = {}
    for i = 1, COLS * ROWS do
      local col, row = (i - 1) % COLS, math.floor((i - 1) / COLS)
      local b = EventCard(c, cw, ch)
      b:SetPoint("TOPLEFT", col * (cw + GAP), -(TOP + row * (ch + GAP)))
      b:SetScript("OnClick", function(self) c.selected = self.item; c.composing = false; K.Journal:RefreshCurrent() end)
      c.cards[i] = b
    end

    c.emptyArt = c:CreateTexture(nil, "ARTWORK")
    c.emptyArt:SetTexture(K.Art("IconFire"))
    c.emptyArt:SetSize(72, 72)
    c.emptyArt:SetPoint("CENTER", 0, 30)
    c.emptyText = UI.Text(c, "Nothing posted yet. Post a gathering to bring people together.", "QuestFont", "deskText", 320)
    c.emptyText:SetPoint("TOP", c.emptyArt, "BOTTOM", 0, -14)
    c.emptyText:SetJustifyH("CENTER")
    c.emptyText:SetSpacing(3)

    -- Paging, along the bottom
    c.prev = UI.Button(c, "<", 28, 22)
    c.next = UI.Button(c, ">", 28, 22)
    c.pageText = UI.Text(c, "", "GameFontHighlightSmall", "deskSubtle")
    c.pageText:SetPoint("BOTTOM", 0, 5)
    c.prev:SetPoint("RIGHT", c.pageText, "LEFT", -10, 0)
    c.next:SetPoint("LEFT", c.pageText, "RIGHT", 10, 0)
    c.prev:SetScript("OnClick", function() c.pageNum = c.pageNum - 1; K.Journal:RefreshCurrent() end)
    c.next:SetScript("OnClick", function() c.pageNum = c.pageNum + 1; K.Journal:RefreshCurrent() end)

    -- Detail card --------------------------------------------------------------------
    local view = UI.Modal(c, 460, 310, function() c.selected = nil; K.Journal:RefreshCurrent() end)
    c.view = view
    local vc = view.card
    view.icon = vc:CreateTexture(nil, "ARTWORK")
    view.icon:SetTexture(K.Art("IconFire"))
    view.icon:SetSize(40, 40)
    view.icon:SetPoint("TOPLEFT", 24, -24)
    view.title = UI.Text(vc, "", "GameFontNormalLarge", "heading", 330)
    view.title:SetPoint("TOPLEFT", view.icon, "TOPRIGHT", 12, -2)
    view.title:SetWordWrap(false)
    view.host = UI.Text(vc, "", "GameFontHighlightSmall", "subtle", 330)
    view.host:SetPoint("TOPLEFT", view.title, "BOTTOMLEFT", 0, -4)
    view.when = Line(vc, "When", -84, 214)
    -- On the When line: put it on your own calendar
    view.cal = UI.Button(vc, "Add to calendar", 118, 20)
    view.cal:SetPoint("TOPRIGHT", -24, -80)
    view.cal:SetScript("OnClick", function()
      if Cal.Add(c.selected) then K.Journal:RefreshCurrent() end
    end)
    view.cal:SetMotionScriptsWhileDisabled(true)
    view.cal:HookScript("OnEnter", function(self)
      local g = c.selected
      if not g then return end
      GameTooltip:SetOwner(self, "ANCHOR_TOP")
      GameTooltip:SetText(Cal.IsAdded(g) and "On your calendar" or "Add to calendar", 1, 0.82, 0)
      local why = Cal.Blocked(g)
      if Cal.IsAdded(g) then
        GameTooltip:AddLine("It's on your calendar. Delete it there if you no longer want it.", 1, 1, 1, true)
      elseif why then
        GameTooltip:AddLine(why, 1, 1, 1, true)
      else
        GameTooltip:AddLine("Puts it on your own game calendar as a personal event. A time like \"8pm\" is read as server time; "
          .. "without one it's set for 8pm.", 1, 1, 1, true)
      end
      GameTooltip:Show()
    end)
    view.cal:HookScript("OnLeave", function() GameTooltip:Hide() end)
    view.where = Line(vc, "Where", -104, 340)
    view.count = Line(vc, "Going", -124, 340)
    local vdiv = UI.Divider(vc, 412)
    vdiv:SetPoint("TOPLEFT", 24, -150)
    view.desc = UI.ReadArea(vc, 412, 96, "QuestFont", "text")
    view.desc:SetPoint("TOPLEFT", 24, -160)
    view.goBtn = UI.Button(vc, "", 110, 24)
    view.goBtn:SetPoint("BOTTOMLEFT", 24, 20)
    view.goBtn:SetScript("OnClick", function()
      local g = c.selected
      local going = not K:IsGoing(g)
      K:SetRSVP(g, going)
      -- Going: onto your calendar too, in this same click (the game only allows it from one).
      if going and K.db.settings.gatherCalendar ~= false and not Cal.IsAdded(g) and not Cal.Blocked(g) then Cal.Add(g, true) end
    end)
    view.discord = UI.Button(vc, "Copy for Discord", 136, 24)
    view.discord:SetPoint("LEFT", view.goBtn, "RIGHT", 8, 0)
    view.discord:SetScript("OnClick", function() UI:Copy("Copy for Discord", DiscordText(c.selected)) end)
    view.remove = UI.Button(vc, "Remove", 90, 24)
    view.remove:SetPoint("LEFT", view.discord, "RIGHT", 8, 0)
    view.remove:SetScript("OnClick", function() K:RemoveGathering(c.selected); c.selected = nil end)

    -- Compose card -------------------------------------------------------------------
    local form = UI.Modal(c, 460, 300, function() c.composing = false; K.Journal:RefreshCurrent() end)
    c.form = form
    local fc = form.card
    local fh = UI.Text(fc, "Post a gathering", "GameFontNormalLarge", "heading")
    fh:SetPoint("TOPLEFT", 24, -24)
    form.heading = fh
    form.reach = UI.Text(fc, "", "Small", "subtle", 200)
    form.reach:SetPoint("BOTTOMRIGHT", -24, 22)
    form.reach:SetJustifyH("RIGHT")
    form.reach:SetSpacing(2)
    form.title = Input(fc, "What's happening?", 24, -56, 412)
    local dateLabel = UI.Text(fc, "Date", "GameFontNormalSmall", "subtle")
    dateLabel:SetPoint("TOPLEFT", 25, -98)
    form.date = UI.Button(fc, "No date", 128, 24)
    form.date:SetPoint("TOPLEFT", 24, -112)
    local function SetDay(day)
      form.day = day
      form.date:SetText(DayText(day) or "No date")
    end
    form.SetDay = SetDay
    form.date:SetScript("OnClick", function(self)
      UI.Menu(self, function(root)
        if root.SetScrollMode then root:SetScrollMode(320) end
        root:CreateRadio("No date", function() return form.day == nil end, function() SetDay(nil) end)
        for i = 0, DATE_CHOICES - 1 do
          local day = Noon(i)
          root:CreateRadio(DayText(day), function() return form.day == day end, function() SetDay(day) end)
        end
      end)
    end)
    UI.Tooltip(form.date, "Date", "A gathering with a date stays on the board until that day is over. "
      .. "Without one, it's taken down two weeks after you post it.")
    form.when = Input(fc, "Time  (e.g. \"8pm server\")", 162, -98, 136)
    form.where = Input(fc, "Where", 308, -98, 128)
    local dl = UI.Text(fc, "Details", "GameFontNormalSmall", "subtle")
    dl:SetPoint("TOPLEFT", 25, -140)
    form.desc = UI.TextArea(fc, 412, 86, 1000)
    form.desc:SetPoint("TOPLEFT", 24, -154)
    local save = UI.Button(fc, "Post it", 96, 24)
    save:SetPoint("BOTTOMLEFT", 24, 20)
    local cancel = UI.Button(fc, "Cancel", 96, 24)
    cancel:SetPoint("LEFT", save, "RIGHT", 8, 0)
    cancel:SetScript("OnClick", function() c.composing = false; K.Journal:RefreshCurrent() end)
    save:SetScript("OnClick", function()
      local title = strtrim(form.title:GetText() or "")
      if title == "" then K:Print("Give your gathering a name first.") return end
      if c.scope == "house" and K:HouseName() == "" then
        K:Print("Give your character a house name on the Profile page first.")
        return
      end
      c.selected = K:AddGathering({
        title = title,
        when = strtrim(form.when:GetText() or ""),
        day = form.day,
        where = strtrim(form.where:GetText() or ""),
        desc = form.desc.edit:GetText() or "",
      }, c.scope)
      c.composing, c.pageNum = false, 1
      K.Journal:RefreshCurrent()
    end)

    function c:Compose()
      self.composing, self.selected = true, nil
      K.Journal:RefreshCurrent()
      form.title:SetText("")
      form.when:SetText("")
      form.SetDay(nil)
      form.where:SetText((K:CurrentPlace()))
      form.desc.edit:SetText("")
      local label = { guild = "your guild", house = "your house", public = "the public board" }
      form.heading:SetText("Post to " .. (label[self.scope] or "your guild"))
      form.reach:SetText(self.scope == "public" and "Kinship users of your faction near you see it, and it travels as people meet."
        or (self.scope == "house" and "Members of your house receive it as you see each other." or ""))
      form.title:SetFocus()
    end
  end,

  refresh = function(c)
    c.scopes:Select(c.scope)
    local items = K:VisibleGatherings(c.scope)
    c.shareNote:SetText(BoardNote(c.scope))
    c.emptyText:SetText(EMPTY[c.scope] or EMPTY.guild)

    local perPage = COLS * ROWS
    local pages = math.max(1, math.ceil(#items / perPage))
    c.pageNum = math.max(1, math.min(c.pageNum, pages))
    for i, b in ipairs(c.cards) do
      local g = items[(c.pageNum - 1) * perPage + i]
      b.item = g
      if g then
        b.title:SetText(g.title)
        b.when:SetText(WhenText(g, "Time to be decided"))
        b.where:SetText(g.where ~= "" and g.where or "Place to be decided")
        b.going:SetText(("%d going"):format(GoingCount(g)))
        b.host:SetText("by " .. Short(g.host) .. (g.via and " (unconfirmed)" or ""))
        b:Show()
      else
        b:Hide()
      end
    end
    local empty = #items == 0
    c.emptyArt:SetShown(empty); c.emptyText:SetShown(empty)
    c.prev:SetShown(pages > 1); c.next:SetShown(pages > 1); c.pageText:SetShown(pages > 1)
    c.prev:SetEnabled(c.pageNum > 1); c.next:SetEnabled(c.pageNum < pages)
    c.pageText:SetText(("Page %d of %d"):format(c.pageNum, pages))

    c.form:SetShown(c.composing and true or false)
    local g, v = c.selected, c.view
    v:SetShown(g ~= nil and not c.composing)
    if not g or c.composing then return end
    v.title:SetText(g.title)
    v.host:SetText("Hosted by " .. Short(g.host)
      .. (g.via and ("  ·  shared by " .. Short(g.via) .. ", not yet confirmed by the host") or ""))
    v.when:SetText(WhenText(g, "To be decided", true))
    v.where:SetText(g.where ~= "" and g.where or "To be decided")
    local names = K:GoingNames(g)
    for i, n in ipairs(names) do names[i] = Short(n) end
    v.count:SetText(#names > 0 and table.concat(names, ", ") or "Nobody yet")
    v.desc:SetText(g.desc ~= "" and g.desc or "No details yet.")
    v.goBtn:SetText(K:IsGoing(g) and "Not going" or "I'm going")
    v.remove:SetShown(K:IsHost(g))
    local added = Cal.IsAdded(g)
    v.cal:SetShown(Cal.Available())
    v.cal:SetText(added and "On your calendar" or "Add to calendar")
    v.cal:SetEnabled(not added and Cal.Blocked(g) == nil)
  end,
})
