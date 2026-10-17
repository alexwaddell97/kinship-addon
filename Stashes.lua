-- Kinship RP: drops and stashes in the world. Leave items at your feet in a
-- named stash (kept by your own client). Anyone nearby can "search the area":
-- a YELL carries their position, and the clients of stash owners close by
-- answer by whisper with what their stashes hold. Taking an item asks the
-- owner's client, which checks the distance and hands it over through the
-- Trade protocol. Visible stashes are found from about 25 yards; hidden ones
-- only by someone searching right on top of them.
--   stashSearch  YELL     { sid, m, x, y, c, wx, wy }
--   stashFound   WHISPER  { sid, list = { { id, name, icon, hidden, d, n, e, items = { { d = def, n } } } } }
--   stashTake    WHISPER  { sid, d, n, req, m, x, y, c, wx, wy }
--   stashNo      WHISPER  { req, why }

local ADDON, ns = ...
local K = ns.K
local UI = K.UI
local Safe = K.Safe
local I = K.Items
local Cut, Num = I.Cut, I.Num
local S = { results = {}, takes = {}, answered = {} }
K.Stashes = S
K.Net:Gate({ "stashSearch", "stashFound", "stashNo", "stashTake" }, "inventory")

local WHITE = "Interface\\Buttons\\WHITE8X8"
local VISIBLE, HIDDEN, SLACK = 25, 6, 5   -- yards
local MAX_STASHES, MAX_ITEMS = 30, 10
local SWEEP = 3                            -- seconds a search sweeps for answers
S.DEFAULT_ICON = "Interface\\Icons\\INV_Box_01"
local BLIP = { own = { 0.96, 0.80, 0.40 }, other = { 0.40, 0.92, 0.82 }, hidden = { 0.78, 0.55, 0.98 } }

local function Short(n) return I.Short(n) end

---------------------------------------------------------------------------
-- Where you are
---------------------------------------------------------------------------
function S.Here()
  if not C_Map or not C_Map.GetBestMapForUnit or not C_Map.GetPlayerMapPosition then return nil end
  local m = C_Map.GetBestMapForUnit("player")
  if not Safe(m) or type(m) ~= "number" then return nil end
  local ok, p = pcall(C_Map.GetPlayerMapPosition, m, "player")
  if not ok or not p or not Safe(p) then return nil end
  local x, y = p:GetXY()
  if not Safe(x) or not Safe(y) or type(x) ~= "number" or type(y) ~= "number" or (x == 0 and y == 0) then return nil end
  local pos = { m = m, x = x, y = y }
  if C_Map.GetWorldPosFromMapPos and CreateVector2D then
    local ok2, c, wp = pcall(C_Map.GetWorldPosFromMapPos, m, CreateVector2D(x, y))
    if ok2 and type(c) == "number" and type(wp) == "table" and wp.GetXY then
      local wx, wy = wp:GetXY()
      if type(wx) == "number" and type(wy) == "number" then pos.c, pos.wx, pos.wy = c, wx, wy end
    end
  end
  return pos
end

-- Distance in yards from a to b, and b's offset (yards north, yards east).
-- nil when they're in different places.
function S.Distance(a, b)
  if type(a) ~= "table" or type(b) ~= "table" then return nil end
  if a.c and b.c and a.wx and b.wx then
    if a.c ~= b.c then return nil end
    local north, east = b.wx - a.wx, -(b.wy - a.wy)
    return math.sqrt(north * north + east * east), north, east
  end
  if a.m ~= b.m then return nil end
  local w, h = 1000, 1000
  if C_Map.GetMapWorldSize then
    local ok, mw, mh = pcall(C_Map.GetMapWorldSize, a.m)
    if ok and type(mw) == "number" and mw > 0 and type(mh) == "number" and mh > 0 then w, h = mw, mh end
  end
  local east, north = (b.x - a.x) * w, -(b.y - a.y) * h
  return math.sqrt(north * north + east * east), north, east
end

-- A position from someone else's message, checked.
local function ParsePos(msg)
  local m, x, y = Num(msg.m), Num(msg.x), Num(msg.y)
  if not m or m <= 0 or m > 1e7 or m ~= math.floor(m) or not x or not y or x < 0 or x > 1 or y < 0 or y > 1 then return nil end
  local pos = { m = m, x = x, y = y }
  local c, wx, wy = Num(msg.c), Num(msg.wx), Num(msg.wy)
  if c and wx and wy and math.abs(wx) < 1e6 and math.abs(wy) < 1e6 then pos.c, pos.wx, pos.wy = c, wx, wy end
  return pos
end

local function PosMsg(pos, msg)
  msg.m, msg.x, msg.y, msg.c, msg.wx, msg.wy = pos.m, pos.x, pos.y, pos.c, pos.wx, pos.wy
  return msg
end

local function Range(st) return st.hidden and HIDDEN or VISIBLE end

---------------------------------------------------------------------------
-- Your stashes
---------------------------------------------------------------------------
function S:Mine()
  local key = K:CharKey()
  local box = K.db.stashes[key]
  if type(box) ~= "table" then box = {}; K.db.stashes[key] = box end
  if type(box.list) ~= "table" then box.list = {} end
  return box.list
end

function S:Find(id)
  for i, st in ipairs(self:Mine()) do if st.id == id then return st, i end end
end

function S:CountIn(id, def)
  local st = self:Find(id)
  local n = 0
  for _, it in ipairs(st and st.items or {}) do if it.def == def then n = n + it.count end end
  return n
end

local function Reserved(st, def) return K.Trade and K.Trade:Reserved("stash:" .. st.id, def) or 0 end

function S:TakeOut(id, def, n)
  local st = self:Find(id)
  if not st or self:CountIn(id, def) < n then return false end
  for i = #st.items, 1, -1 do
    local it = st.items[i]
    if n > 0 and it.def == def then
      local k = math.min(n, it.count)
      it.count = it.count - k
      n = n - k
      if it.count <= 0 then table.remove(st.items, i) end
    end
  end
  K:Fire("STASHES")
  return true
end

function S:Total(st)
  local n = 0
  for _, it in ipairs(st.items) do n = n + it.count end
  return n
end

function S:Nearby(pos)
  local out = {}
  for _, st in ipairs(self:Mine()) do
    local d = S.Distance(pos, st.pos)
    if d and d <= 10 then out[#out + 1] = st end
  end
  return out
end

-- Leave n of the item in bag slot `slot` here. into = a stash id, or
-- { name, icon, hidden } for a new stash.
function S:Drop(slot, n, into)
  local pos = S.Here()
  if not pos then I.Error("You can't leave anything here.") return end
  local s = I:Slot(slot)
  local def = s and I:Get(s.def)
  if not def then return end
  n = math.floor(Num(n) or 1)
  if n < 1 or I:Available(s.def) < n then I.Error("That item is promised in a trade.") return end
  local st
  if type(into) == "string" then
    st = self:Find(into)
    local d = st and S.Distance(pos, st.pos)
    if not d or d > 10 then I.Error("That stash isn't here.") return end
  else
    if #self:Mine() >= MAX_STASHES then I.Error(("You can keep up to %d stashes. Empty one first."):format(MAX_STASHES)) return end
    local name = strtrim(Cut(into and into.name or "", 40))
    st = {
      id = ("%d%06d"):format(time(), math.random(0, 999999)),
      name = name ~= "" and name or "A stash", icon = I.ValidIcon(into and into.icon) or S.DEFAULT_ICON,
      hidden = into and into.hidden and true or nil, pos = pos, zone = (K:CurrentPlace()), t = time(), items = {},
    }
    table.insert(self:Mine(), 1, st)
  end
  local slotFor
  for _, it in ipairs(st.items) do if it.def == s.def then slotFor = it end end
  if not slotFor and #st.items >= MAX_ITEMS then I.Error("That stash is full.") return end
  if not I:Remove(s.def, n, slot) then return end
  if slotFor then slotFor.count = slotFor.count + n else st.items[#st.items + 1] = { def = def.id, count = n } end
  st.t = time()
  if SOUNDKIT and SOUNDKIT.IG_BACKPACK_CLOSE then PlaySound(SOUNDKIT.IG_BACKPACK_CLOSE) end
  K:Fire("STASHES")
  return st
end

-- Take a stack from your own stash back into your bags.
function S:Withdraw(st, index)
  local it = st.items[index]
  local def = it and I:Get(it.def)
  if not def then return end
  local n = it.count - Reserved(st, it.def)
  if n < 1 then I.Error("Someone is taking that right now.") return end
  if not I:Fits({ { id = it.def, n = n, stack = def.stack } }) then I.Error("There's no room in your bags.") return end
  self:TakeOut(st.id, it.def, n)
  I:Add(it.def, n)
end

function S:Empty(st)
  for i = #st.items, 1, -1 do self:Withdraw(st, i) end
  return #st.items == 0
end

function S:Remove(st)
  if #st.items > 0 and not self:Empty(st) then I.Error("Make room in your bags to empty it first.") return end
  local _, i = self:Find(st.id)
  if i then table.remove(self:Mine(), i) end
  K:Fire("STASHES")
  return true
end

function S:MarkOnMap(st)
  local p = st.pos
  local ok = false
  if C_Map.SetUserWaypoint and UiMapPoint and UiMapPoint.CreateFromCoordinates then
    ok = pcall(function()
      C_Map.SetUserWaypoint(UiMapPoint.CreateFromCoordinates(p.m, p.x, p.y))
      if C_SuperTrack and C_SuperTrack.SetSuperTrackedUserWaypoint then C_SuperTrack.SetSuperTrackedUserWaypoint(true) end
    end)
  end
  K:Print(("%s is in %s at %.1f, %.1f%s"):format(UI.Escape(st.name), st.zone or "?", p.x * 100, p.y * 100,
    ok and " (marked on your map)." or "."))
end

---------------------------------------------------------------------------
-- Searching
---------------------------------------------------------------------------
local function Summary(st)
  local items = {}
  for i = 1, math.min(MAX_ITEMS, #st.items) do
    local it = st.items[i]
    local n = it.count - Reserved(st, it.def)
    local def = I:Pack(it.def)
    if def and n > 0 then items[#items + 1] = { d = def, n = n } end
  end
  return items
end

function S:Search()
  local pos = S.Here()
  if not pos then I.Error("You can't search here.") return false end
  if GetTime() - (self.lastSearch or -99) < 4 then return false end
  self.lastSearch = GetTime()
  local sid = ("%d%06d"):format(time(), math.random(0, 999999))
  self.search = { sid = sid, at = GetTime(), pos = pos }
  self.results = {}
  for _, st in ipairs(self:Mine()) do
    local d, north, east = S.Distance(pos, st.pos)
    if d and d <= VISIBLE then
      local items = {}
      for _, it in ipairs(st.items) do
        local def = I:Get(it.def)
        if def then items[#items + 1] = { def = def, n = it.count } end
      end
      self.results[#self.results + 1] = { own = true, stash = st, owner = K:MyName(), id = st.id, name = st.name, icon = st.icon,
        hidden = st.hidden, dist = d, north = north, east = east, items = items, born = GetTime() }
    end
  end
  K.Net:Send("stashSearch", PosMsg(pos, { sid = sid }), "YELL")
  if SOUNDKIT and SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON then PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON) end
  C_Timer.After(SWEEP, function() K:Fire("STASHES") end)
  K:Fire("STASHES")
  return true
end

function S:Searching() return self.search and GetTime() - self.search.at < SWEEP end

-- Someone nearby is searching: answer with our stashes in range.
K.Net:On("stashSearch", function(msg, sender, channel)
  if channel ~= "YELL" or not K.db.settings.stashAnswer then return end
  if type(msg.sid) ~= "string" or #msg.sid > 30 then return end
  local key = K.NameKey(sender)
  local now = GetTime()
  if not key or (S.answered[key] and now - S.answered[key] < 3) then return end
  local pos = ParsePos(msg)
  if not pos then return end
  local list = {}
  for _, st in ipairs(S:Mine()) do
    local d, north, east = S.Distance(pos, st.pos)
    if d and d <= Range(st) and #list < 4 then
      list[#list + 1] = { id = st.id, name = st.name, icon = st.icon, hidden = st.hidden, d = math.floor(d + 0.5),
        n = math.floor(north + 0.5), e = math.floor(east + 0.5), items = Summary(st) }
    end
  end
  if #list == 0 then return end
  S.answered[key] = now
  K.Net:Send("stashFound", { sid = msg.sid, list = list }, "WHISPER", sender)
end)

K.Net:On("stashFound", function(msg, sender, channel)
  local s = S.search
  if channel ~= "WHISPER" or not s or msg.sid ~= s.sid or GetTime() - s.at > 30 then return end
  if type(msg.list) ~= "table" then return end
  for i = 1, 4 do
    local raw = msg.list[i]
    if type(raw) ~= "table" then break end
    local id = type(raw.id) == "string" and #raw.id <= 40 and raw.id
    local d = Num(raw.d)
    if id and d and d >= 0 and d <= VISIBLE + SLACK then
      local items = {}
      if type(raw.items) == "table" then
        for j = 1, MAX_ITEMS do
          local e = raw.items[j]
          if type(e) ~= "table" then break end
          local def = I.Sanitize(e.d)
          local n = math.floor(Num(e.n) or 0)
          if def and n >= 1 and n <= 999 then items[#items + 1] = { def = def, n = n } end
        end
      end
      local name = strtrim(Cut(raw.name, 40))
      local r = { owner = sender, id = id, name = name ~= "" and name or "A stash", icon = I.IconTexture(raw.icon),
        hidden = raw.hidden == true, dist = d, north = math.max(-60, math.min(60, Num(raw.n) or 0)),
        east = math.max(-60, math.min(60, Num(raw.e) or 0)), items = items, born = GetTime() }
      local replaced = false
      for k, old in ipairs(S.results) do
        if not old.own and old.id == id and K.NameKey(old.owner) == K.NameKey(sender) then S.results[k] = r; replaced = true end
      end
      if not replaced and #S.results < 12 then S.results[#S.results + 1] = r end
    end
  end
  K:Fire("STASHES")
end)

-- Ask for an item from a search result (or take it straight back from your own).
function S:Take(result, index)
  local it = result and result.items[index]
  if not it then return end
  if result.own then
    local st = self:Find(result.id)
    if not st then return end
    for i, x in ipairs(st.items) do
      if x.def == it.def.id then self:Withdraw(st, i) break end
    end
    it.n = self:CountIn(st.id, it.def.id)
    if it.n <= 0 then table.remove(result.items, index) end
    K:Fire("STASHES")
    return
  end
  if it.asking then return end
  if GetTime() - (self.lastTake or -99) < 1.5 then return end
  local pos = S.Here()
  if not pos then I.Error("You can't do that here.") return end
  local known = I:Get(it.def.id)
  if not I:Fits({ { id = it.def.id, n = it.n, stack = known and known.stack or it.def.stack } }) then
    I.Error("There's no room in your bags.") return
  end
  self.lastTake = GetTime()
  local req = ("%d%06d"):format(time(), math.random(0, 999999))
  local t = { owner = K.NameKey(result.owner), result = result, item = it, at = GetTime() }
  self.takes[req] = t
  it.asking = true
  K.Net:Send("stashTake", PosMsg(pos, { sid = result.id, d = it.def.id, n = it.n, req = req }), "WHISPER", result.owner)
  K:Fire("STASHES")
  C_Timer.After(25, function()
    if self.takes[req] == t then
      self.takes[req] = nil
      it.asking = nil
      I.Error("No answer from the stash. Its keeper may have moved on.")
      K:Fire("STASHES")
    end
  end)
end

function S:ExpectsTake(sender, req)
  local t = self.takes[req]
  return t ~= nil and t.owner == K.NameKey(sender) and GetTime() - t.at < 60
end

function S:Received(sender, req, r)
  local t = self.takes[req]
  if not t then return end
  self.takes[req] = nil
  t.item.asking = nil
  local e = r.entries[1]
  local got = 0
  for _, x in ipairs(r.entries) do got = got + x.n end
  t.item.n = t.item.n - got
  for i, x in ipairs(t.result.items) do
    if x == t.item and x.n <= 0 then table.remove(t.result.items, i) break end
  end
  local def = I:Get(e.def.id) or e.def
  UI.Toast({
    icon = I.IconTexture(def.icon), iconCoords = { 0.08, 0.92, 0.08, 0.92 },
    title = "Taken from " .. UI.Escape(t.result.name),
    text = I:Label(def, e.n) .. " is in your bags.", color = I.Quality(def.quality).color, duration = 5,
  })
  K:Fire("STASHES")
end

K.Net:On("stashNo", function(msg, sender)
  local t = type(msg.req) == "string" and S.takes[msg.req]
  if not t or t.owner ~= K.NameKey(sender) then return end
  S.takes[msg.req] = nil
  t.item.asking = nil
  local why = { far = "You're too far from that stash.", gone = "Someone got there first.",
                busy = "The stash's keeper is busy. Try again in a moment." }
  I.Error(why[msg.why] or why.gone)
  K:Fire("STASHES")
end)

-- Someone wants an item from one of our stashes.
K.Net:On("stashTake", function(msg, sender, channel)
  if channel ~= "WHISPER" or type(msg.req) ~= "string" or #msg.req > 40 then return end
  local key = K.NameKey(sender)
  local now = GetTime()
  if not key or (S.answered["take:" .. key] and now - S.answered["take:" .. key] < 1) then return end
  S.answered["take:" .. key] = now
  local function no(why) K.Net:Send("stashNo", { req = msg.req, why = why }, "WHISPER", sender) end
  local st = type(msg.sid) == "string" and S:Find(msg.sid)
  if not st or type(msg.d) ~= "string" then return no("gone") end
  local pos = ParsePos(msg)
  local d = pos and S.Distance(pos, st.pos)
  if not d or d > Range(st) + SLACK then return no("far") end
  local n = math.min(math.floor(Num(msg.n) or 0), S:CountIn(st.id, msg.d) - Reserved(st, msg.d))
  if n < 1 then return no("gone") end
  local o = K.Trade:Offer(sender, { { id = msg.d, n = n } }, { src = "stash:" .. st.id, req = msg.req, quiet = true })
  if not o then return no("busy") end
  o.stashName = st.name
end)

-- A trade from one of our stashes finished: tell the owner.
function S:Taken(id, o)
  local st = self:Find(id)
  local e = o.items[1]
  local def = e and I:Get(e.id)
  UI.Toast({
    icon = st and I.IconTexture(st.icon) or S.DEFAULT_ICON, iconCoords = { 0.08, 0.92, 0.08, 0.92 },
    title = Short(o.to) .. " found your stash",
    text = ("%s taken from %s."):format(I:Label(def, e and e.n), UI.Escape(st and st.name or o.stashName or "a stash")),
    color = BLIP.own, duration = 6,
  })
  K:Fire("STASHES")
end

function S:TakeFailed() K:Fire("STASHES") end

---------------------------------------------------------------------------
-- The radar: a scope with a sweeping arm, a pulse and blips for finds.
---------------------------------------------------------------------------
local function Radar(parent, size)
  local r = CreateFrame("Frame", nil, parent)
  r:SetSize(size, size)
  local R = size / 2
  r.R = R
  r.halo = UI.Circle(r, size + 6, "BACKGROUND", 0)
  r.halo:SetPoint("CENTER")
  r.halo:SetVertexColor(0.30, 0.20, 0.08, 0.30)
  r.disc = UI.Circle(r, size, "BACKGROUND", 1)
  r.disc:SetPoint("CENTER")
  r.disc:SetVertexColor(0.035, 0.12, 0.12, 1)
  local sub = 2
  for _, f in ipairs({ 0.66, 0.33 }) do
    local ring = UI.Circle(r, math.floor(size * f) + 2, "BACKGROUND", sub)
    ring:SetPoint("CENTER")
    ring:SetVertexColor(0.40, 0.92, 0.82, 0.22)
    local hole = UI.Circle(r, math.floor(size * f), "BACKGROUND", sub + 1)
    hole:SetPoint("CENTER")
    hole:SetVertexColor(0.035, 0.12, 0.12, 1)
    sub = sub + 2
  end
  for _, vertical in ipairs({ false, true }) do
    local l = r:CreateTexture(nil, "BORDER")
    l:SetTexture(WHITE)
    l:SetVertexColor(0.40, 0.92, 0.82, 0.12)
    l:SetSize(vertical and 1 or size - 8, vertical and size - 8 or 1)
    l:SetPoint("CENTER")
  end
  r.pulse = UI.Circle(r, size, "BORDER", 1)
  r.pulse:SetPoint("CENTER")
  r.pulse:SetVertexColor(0.40, 0.92, 0.82, 0)
  r.arms = {}
  for i = 1, 12 do
    local a = r:CreateTexture(nil, "ARTWORK", nil, 1)
    a:SetTexture(WHITE)
    a:SetSize(R - 4, i == 1 and 2 or 3)
    r.arms[i] = a
  end
  r.me = UI.Circle(r, 7, "OVERLAY", 2)
  r.me:SetPoint("CENTER")
  r.me:SetVertexColor(0.96, 0.84, 0.56, 1)
  r.north = r:CreateFontString(nil, "OVERLAY")
  r.north:SetFontObject(UI.FONTS.Label)
  r.north:SetPoint("TOP", 0, -5)
  r.north:SetText("N")
  r.north:SetTextColor(0.40, 0.92, 0.82, 0.55)
  r.blips = {}
  r.angle = math.pi / 2

  local function placeArms(alpha)
    for i, a in ipairs(r.arms) do
      local ang = r.angle + (i - 1) * 0.06
      local len = (R - 4) / 2
      a:ClearAllPoints()
      a:SetPoint("CENTER", r, "CENTER", math.cos(ang) * len, math.sin(ang) * len)
      a:SetRotation(ang)
      local fall = (1 - (i - 1) / #r.arms) ^ 2
      a:SetVertexColor(0.45, 0.95, 0.85, alpha * (i == 1 and 0.95 or 0.28 * fall))
    end
  end
  r.t = 0
  r:SetScript("OnUpdate", function(self, elapsed)
    self.t = self.t + elapsed
    if self.sweeping then
      self.angle = self.angle - elapsed * 3.4
      placeArms(1)
      local p = (self.t % 1.1) / 1.1
      local sz = size * (0.15 + 0.85 * p)
      self.pulse:SetSize(sz, sz)
      self.pulse:SetVertexColor(0.40, 0.92, 0.82, 0.22 * (1 - p))
    else
      self.angle = self.angle - elapsed * 0.5
      placeArms(0.35)
      self.pulse:SetVertexColor(0.40, 0.92, 0.82, 0)
    end
    for _, b in ipairs(self.blips) do
      if b:IsShown() then
        local glow = 0.55 + 0.45 * math.sin(self.t * 3 + (b.phase or 0))
        b.glow:SetAlpha(0.35 * glow)
      end
    end
  end)

  function r:SetBlips(list)
    for i, item in ipairs(list) do
      local b = self.blips[i]
      if not b then
        b = CreateFrame("Frame", nil, self)
        b:SetSize(14, 14)
        b.glow = UI.Circle(b, 14, "OVERLAY", 3)
        b.glow:SetPoint("CENTER")
        b.dot = UI.Circle(b, 7, "OVERLAY", 4)
        b.dot:SetPoint("CENTER")
        b.phase = i * 1.3
        self.blips[i] = b
      end
      local c = item.own and BLIP.own or (item.hidden and BLIP.hidden or BLIP.other)
      b.dot:SetVertexColor(c[1], c[2], c[3], 1)
      b.glow:SetVertexColor(c[1], c[2], c[3], 1)
      local d = math.max(0.01, item.dist or 0)
      local rad = math.min(R - 9, (d / VISIBLE) * (R - 9))
      local north, east = item.north or 0, item.east or 0
      local len = math.sqrt(north * north + east * east)
      local x, y = 0, 0
      if len > 0.01 then x, y = east / len * rad, north / len * rad end
      b:ClearAllPoints()
      b:SetPoint("CENTER", self, "CENTER", x, y)
      if not b:IsShown() or b.item ~= item then
        b.item = item
        b:Show()
        UI.SetProgress(b, 0)
        UI.Tween(b, 1, 0.35, function(p) b:SetScale(0.4 + 0.6 * p); b:SetAlpha(p) end, UI.Ease.outQuart)
      end
      b.selected = item.selected
      b:SetSize(item.selected and 18 or 14, item.selected and 18 or 14)
    end
    for i = #list + 1, #self.blips do self.blips[i]:Hide(); self.blips[i].item = nil end
  end
  return r
end

---------------------------------------------------------------------------
-- The stash panel: a pop-over card on the Inventory page.
---------------------------------------------------------------------------
local PW, PH = 640, 420
local RW = 424
local CELL, GAP = 46, 7

local function ItemGrid(parent, onClick)
  local g = { cells = {} }
  for i = 1, MAX_ITEMS do
    local s = I.NewSlot(parent, CELL)
    s:SetPoint("TOPLEFT", 200 + ((i - 1) % 8) * (CELL + GAP), -248 - math.floor((i - 1) / 8) * (CELL + GAP))
    s:SetScript("OnClick", function(self) if self.index then onClick(self.index) end end)
    s.asking = s:CreateFontString(nil, "OVERLAY", nil, 3)
    s.asking:SetFontObject(UI.FONTS.Label)
    s.asking:SetPoint("CENTER")
    s.asking:SetTextColor(1, 1, 1)
    s.asking:SetText("...")
    g.cells[i] = s
  end
  return g
end

function S:BuildPanel(page)
  if self.panel then return self.panel end
  local m = UI.Modal(page, PW, PH, function() self.panel:Hide() end)
  self.panel = m
  local card = m.card
  m.mode = "near"

  m.seg = UI.Segments(card, { { key = "near", label = "Search nearby" }, { key = "mine", label = "Your stashes" } }, 130,
    function(key) m.mode = key; m.selected = nil; S:RefreshPanel() end)
  m.seg:SetPoint("TOPLEFT", 16, -16)

  -- Left column: the radar ...
  local near = CreateFrame("Frame", nil, card)
  near:SetPoint("TOPLEFT", 16, -54)
  near:SetSize(168, PH - 70)
  m.near = near
  near.radar = Radar(near, 168)
  near.radar:SetPoint("TOP")
  near.status = UI.Text(near, "", "Body", "heading", 168)
  near.status:SetPoint("TOP", near.radar, "BOTTOM", 0, -12)
  near.status:SetJustifyH("CENTER")
  near.again = UI.Button(near, "Search the area", 168, 26)
  near.again:SetPoint("TOP", near.radar, "BOTTOM", 0, -40)
  near.again:SetScript("OnClick", function() S:Search() end)
  near.hint = UI.Text(near, "Stashes show from about 25 yards. Hidden ones only when you search right on top of them.",
    "Small", "subtle", 168)
  near.hint:SetPoint("TOP", near.again, "BOTTOM", 0, -12)
  near.hint:SetJustifyH("CENTER")
  near.hint:SetSpacing(2)

  -- ... or the chosen stash of yours
  local mine = CreateFrame("Frame", nil, card)
  mine:SetPoint("TOPLEFT", 16, -54)
  mine:SetSize(168, PH - 70)
  m.mine = mine
  mine.icon = mine:CreateTexture(nil, "ARTWORK")
  mine.icon:SetSize(52, 52)
  mine.icon:SetPoint("TOPLEFT", 0, -2)
  mine.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
  UI.Round(mine.icon)
  mine.name = UI.Text(mine, "", "Header", "heading", 108)
  mine.name:SetPoint("TOPLEFT", mine.icon, "TOPRIGHT", 8, -4)
  mine.name:SetMaxLines(2)
  mine.where = UI.Text(mine, "", "Small", "subtle", 168)
  mine.where:SetPoint("TOPLEFT", 0, -64)
  mine.where:SetSpacing(2)
  mine.vis = UI.Segments(mine, { { key = "shown", label = "Visible" }, { key = "hidden", label = "Hidden" } }, 84, function(key)
    local st = m.selected and S:Find(m.selected)
    if st then st.hidden = key == "hidden" or nil; K:Fire("STASHES") end
  end)
  mine.vis:SetPoint("TOPLEFT", 0, -114)
  mine.map = UI.Button(mine, "Mark on map", 168, 26)
  mine.map:SetPoint("TOPLEFT", 0, -150)
  mine.map:SetScript("OnClick", function() local st = S:Find(m.selected or ""); if st then S:MarkOnMap(st) end end)
  mine.empty = UI.Button(mine, "Empty into bags", 168, 26)
  mine.empty:SetPoint("TOPLEFT", 0, -182)
  mine.empty:SetScript("OnClick", function() local st = S:Find(m.selected or ""); if st then S:Empty(st) end end)
  mine.remove = UI.Button(mine, "Remove stash", 168, 26)
  mine.remove:SetPoint("TOPLEFT", 0, -214)
  mine.remove:SetScript("OnClick", function(self)
    local st = S:Find(m.selected or "")
    if not st then return end
    if not self.armed then
      self.armed = true
      self:SetText(#st.items > 0 and "Empty and remove?" or "Remove it?")
      C_Timer.After(3, function() self.armed = nil; self:SetText("Remove stash") end)
      return
    end
    self.armed = nil
    self:SetText("Remove stash")
    if S:Remove(st) then m.selected = nil end
  end)
  mine.none = UI.Text(mine, "Leave an item somewhere with Stash it on the Bags tab, and it will be listed here.",
    "Small", "subtle", 168)
  mine.none:SetPoint("TOPLEFT", 0, -4)
  mine.none:SetSpacing(2)

  -- Right column: the list and what the chosen stash holds
  m.list = UI.List(card, RW, 166, 52, "", function(row)
    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetSize(34, 34)
    row.icon:SetPoint("LEFT", 10, 0)
    row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    UI.Round(row.icon)
    row.name = UI.Text(row, "", "Header", "heading", 230)
    row.name:SetPoint("TOPLEFT", 54, -9)
    row.name:SetWordWrap(false)
    row.sub = UI.Text(row, "", "Small", "subtle", 230)
    row.sub:SetPoint("TOPLEFT", row.name, "BOTTOMLEFT", 0, -4)
    row.sub:SetWordWrap(false)
    row.count = UI.Chip(row)
    row.count:SetPoint("TOPRIGHT", -10, -9)
    row.flag = UI.Chip(row)
    row.flag:SetPoint("BOTTOMRIGHT", -10, 8)
    row:SetScript("OnClick", function(self)
      m.selected = m.mode == "mine" and self.item.id or self.item
      S:RefreshPanel()
    end)
  end, { emptyIcon = K.Art("IconPlace") })
  m.list:SetPoint("TOPLEFT", 200, -54)

  m.contents = UI.Section(card, "Contents")
  m.contents:SetPoint("TOPLEFT", 207, -230)
  m.grid = ItemGrid(card, function(index)
    if m.mode == "mine" then
      local st = S:Find(m.selected or "")
      if st then S:Withdraw(st, index) end
    elseif type(m.selected) == "table" then
      S:Take(m.selected, index)
    end
  end)
  m.foot = UI.Text(card, "", "Small", "subtle", RW)
  m.foot:SetPoint("TOPLEFT", 200, -360)
  m.foot:SetSpacing(2)

  K:On("STASHES", function() if m:IsShown() then S:RefreshPanel() end end)
  K:On("INVENTORY", function() if m:IsShown() then S:RefreshPanel() end end)
  return m
end

local function Where(st)
  return ("%s  ·  %.1f, %.1f"):format(UI.Escape(st.zone or "?"), st.pos.x * 100, st.pos.y * 100)
end

function S:RefreshPanel()
  local m = self.panel
  if not m then return end
  m.seg:Select(m.mode)
  local near = m.mode == "near"
  m.near:SetShown(near)
  m.mine:SetShown(not near)

  local items, sel = {}, nil
  if near then
    for _, r in ipairs(self.results) do items[#items + 1] = r end
    table.sort(items, function(a, b) return a.dist < b.dist end)
    if type(m.selected) == "table" then
      for _, r in ipairs(items) do if r == m.selected then sel = r end end
    end
    if not sel and items[1] and not self:Searching() then sel = items[1]; m.selected = sel end
    local sweeping = self:Searching()
    m.near.radar.sweeping = sweeping
    for _, r in ipairs(items) do r.selected = r == sel end
    m.near.radar:SetBlips(items)
    local s = self.search
    if sweeping then m.near.status:SetText("Searching the area...")
    elseif not s then m.near.status:SetText("Look around you")
    elseif #items == 0 then m.near.status:SetText("Nothing hidden here")
    else m.near.status:SetText(#items == 1 and "You found a stash" or (("You found %d stashes"):format(#items))) end
    m.near.again:SetEnabled(not sweeping)
    m.list.empty:SetText(sweeping and "Listening for answers..." or
      (s and "Nothing turned up. Stashes only answer while their keeper is online and nearby." or
        "Search the area to find stashes others have left nearby."))
  else
    for _, st in ipairs(self:Mine()) do items[#items + 1] = st end
    sel = self:Find(type(m.selected) == "string" and m.selected or "")
    if not sel and items[1] then sel = items[1]; m.selected = sel.id end
    m.list.empty:SetText("You haven't left any stashes yet.")
  end

  m.list:SetItems(items, function(row, it)
    local isSel = (near and it == sel) or (not near and sel and it.id == sel.id)
    row.icon:SetTexture(I.IconTexture(it.icon))
    row.name:SetText(UI.Escape(it.name))
    local count = 0
    for _, x in ipairs(it.items) do count = count + (x.n or x.count or 0) end
    if near then
      local who = it.own and "Yours" or Short(it.owner)
      row.sub:SetText(("%s  ·  %d yards"):format(who, math.floor(it.dist + 0.5)))
    else
      row.sub:SetText(Where(it))
    end
    row.count:Set(count == 0 and "Empty" or (count == 1 and "1 item" or (count .. " items")))
    if it.hidden then row.flag:Set("Hidden", BLIP.hidden) else row.flag:Set(nil) end
    row.sel:SetShown(isSel and true or false)
  end)

  -- Left column for your own stash
  if not near then
    local has = sel ~= nil
    for _, w in ipairs({ m.mine.icon, m.mine.name, m.mine.where, m.mine.vis, m.mine.map, m.mine.empty, m.mine.remove }) do w:SetShown(has) end
    m.mine.none:SetShown(not has)
    if has then
      m.mine.icon:SetTexture(I.IconTexture(sel.icon))
      m.mine.name:SetText(UI.Escape(sel.name))
      local here = S.Here()
      local d = here and S.Distance(here, sel.pos)
      m.mine.where:SetText(Where(sel) .. "\nLeft " .. UI.Ago(sel.t) .. (d and ("  ·  %d yards away"):format(math.floor(d + 0.5)) or ""))
      m.mine.vis:Select(sel.hidden and "hidden" or "shown")
      m.mine.empty:SetEnabled(#sel.items > 0)
    end
  end

  -- What the chosen stash holds
  local contents = {}
  if near and sel then
    for _, x in ipairs(sel.items) do contents[#contents + 1] = { def = x.def, n = x.n, asking = x.asking } end
  elseif sel then
    for _, x in ipairs(sel.items) do contents[#contents + 1] = { def = I:Get(x.def), n = x.count, unknown = true } end
  end
  m.contents:SetShown(sel ~= nil)
  m.contents.bg:SetShown(sel ~= nil)
  for i, cell in ipairs(m.grid.cells) do
    local c = contents[i]
    cell:SetShown(sel ~= nil and (c ~= nil or i <= 8))
    cell.index = c and i or nil
    if c then cell:SetItem(c.def, c.n, true) else cell:SetItem(nil) end
    cell:SetLocked(c and c.asking or false)
    cell.asking:SetShown(c and c.asking or false)
  end
  if not sel then
    m.foot:SetText("")
  elseif #contents == 0 then
    m.foot:SetText("It's empty.")
  elseif near and sel.own then
    m.foot:SetText("Your own stash. Click an item to take it back.")
  elseif near then
    m.foot:SetText("Click an item to take it. " .. Short(sel.owner) .. "'s client hands it over while you're close enough.")
  else
    m.foot:SetText("Click an item to take it back into your bags.")
  end
end

function S:OpenPanel(page, mode)
  local m = self:BuildPanel(page)
  m.mode = mode or m.mode or "near"
  if m.mode == "near" then m.selected = nil end
  m:Show()
  self:RefreshPanel()
  if m.mode == "near" and not self:Searching() then self:Search() end
end

---------------------------------------------------------------------------
-- The drop card: leave an item here
---------------------------------------------------------------------------
function S:BuildDrop(page)
  if self.drop then return self.drop end
  local m = UI.Modal(page, 440, 340, function() self.drop:Hide() end)
  self.drop = m
  local card = m.card
  local pill = UI.Section(card, "Leave it here")
  pill:SetPoint("TOPLEFT", 21, -15)

  m.slot = I.NewSlot(card, 44)
  m.slot:SetPoint("TOPLEFT", 16, -42)
  m.name = UI.Text(card, "", "Header", "heading", 220)
  m.name:SetPoint("TOPLEFT", m.slot, "TOPRIGHT", 10, -6)
  m.name:SetWordWrap(false)
  m.where = UI.Text(card, "", "Small", "subtle", 220)
  m.where:SetPoint("TOPLEFT", m.name, "BOTTOMLEFT", 0, -4)
  m.where:SetWordWrap(false)
  m.plus = UI.Button(card, "+", 24, 24)
  m.plus:SetPoint("TOPRIGHT", -16, -52)
  m.count = UI.Text(card, "1", "Header", "heading")
  m.count:SetPoint("RIGHT", m.plus, "LEFT", -10, 0)
  m.minus = UI.Button(card, "-", 24, 24)
  m.minus:SetPoint("RIGHT", m.plus, "LEFT", -40, 0)
  local function step(d)
    local s = I:Slot(m.slotIndex or 0)
    if not s then return end
    local max = math.max(1, I:Available(s.def))
    m.n = IsShiftKeyDown() and (d > 0 and max or 1) or math.max(1, math.min(max, (m.n or 1) + d))
    S:RefreshDrop()
  end
  m.plus:SetScript("OnClick", function() step(1) end)
  m.minus:SetScript("OnClick", function() step(-1) end)

  m.seg = UI.Segments(card, { { key = "new", label = "A new stash" }, { key = "old", label = "One of yours here" } }, 150,
    function(key) m.mode = key; S:RefreshDrop() end)
  m.seg:SetPoint("TOPLEFT", 16, -100)

  local new = CreateFrame("Frame", nil, card)
  new:SetPoint("TOPLEFT", 0, -134)
  new:SetSize(440, 150)
  m.new = new
  new.iconBtn = I.NewSlot(new, 40)
  new.iconBtn:SetPoint("TOPLEFT", 16, -14)
  new.iconBtn:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:SetText("Stash icon", 1, 0.82, 0)
    GameTooltip:AddLine("Click to choose how it looks to whoever finds it.", 1, 1, 1, true)
    GameTooltip:Show()
  end)
  new.iconBtn:SetScript("OnClick", function(self)
    I:ChooseIcon(self, m.icon, function(icon) m.icon = icon; S:RefreshDrop() end)
  end)
  new.name = UI.Field(new, "Name", 350, 40)
  new.name:SetPoint("TOPLEFT", 72, -14)
  new.hidden = UI.Toggle(new, "Hidden", "Only found by someone searching right where you stand.",
    function() return m.hidden end, function(v) m.hidden = v end, 408, true)
  new.hidden:SetPoint("TOPLEFT", 16, -66)

  m.old = UI.List(card, 408, 118, 38, "None of your stashes are within a few steps of here.", function(row)
    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetSize(26, 26)
    row.icon:SetPoint("LEFT", 8, 0)
    row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    UI.Round(row.icon)
    row.name = UI.Text(row, "", "Body", "heading", 240)
    row.name:SetPoint("LEFT", row.icon, "RIGHT", 10, 0)
    row.name:SetWordWrap(false)
    row.info = UI.Text(row, "", "Small", "subtle")
    row.info:SetPoint("RIGHT", -10, 0)
    row:SetScript("OnClick", function(self) m.into = self.item.id; S:RefreshDrop() end)
  end, { emptyIcon = K.Art("IconPlace") })
  m.old:SetPoint("TOPLEFT", 16, -140)

  m.go = UI.Button(card, "Leave it", 110, 26)
  m.go:SetPoint("BOTTOMRIGHT", -16, 14)
  m.go:SetScript("OnClick", function()
    local into
    if m.mode == "old" then into = m.into
    else into = { name = new.name.edit:GetText(), icon = m.icon, hidden = m.hidden } end
    if not into then I.Error("Choose a stash.") return end
    local st = S:Drop(m.slotIndex, m.n or 1, into)
    if st then
      m:Hide()
      UI.Toast({ icon = I.IconTexture(st.icon), iconCoords = { 0.08, 0.92, 0.08, 0.92 }, title = "Left in " .. UI.Escape(st.name),
        text = (st.hidden and "Hidden. " or "") .. "Others nearby can find it while you're online.", color = BLIP.own, duration = 5 })
    end
  end)
  m.cancel = UI.Button(card, "Cancel", 80, 26)
  m.cancel:SetPoint("RIGHT", m.go, "LEFT", -8, 0)
  m.cancel:SetScript("OnClick", function() m:Hide() end)
  K:On("INVENTORY", function() if m:IsShown() then S:RefreshDrop() end end)
  return m
end

function S:RefreshDrop()
  local m = self.drop
  if not m then return end
  local s = I:Slot(m.slotIndex or 0)
  local def = s and I:Get(s.def)
  if not def then m:Hide() return end
  local avail = math.max(1, I:Available(s.def))
  m.n = math.max(1, math.min(m.n or 1, avail))
  m.slot:SetItem(def, m.n)
  m.name:SetText(UI.Escape(def.name))
  m.name:SetTextColor(unpack(I.QualityColor(def.quality, true)))
  local here = S.Here()
  m.where:SetText(here and ("%s  ·  %.1f, %.1f"):format(UI.Escape((K:CurrentPlace())), here.x * 100, here.y * 100) or "You can't leave things here.")
  m.count:SetText(m.n)
  m.minus:SetEnabled(m.n > 1)
  m.plus:SetEnabled(m.n < avail)
  m.seg:Select(m.mode)
  m.new:SetShown(m.mode == "new")
  m.old:SetShown(m.mode == "old")
  m.new.iconBtn:SetItem({ icon = m.icon or S.DEFAULT_ICON, quality = 1 }, nil)
  m.new.hidden:Refresh()
  local list = here and self:Nearby(here) or {}
  m.old:SetItems(list, function(row, st)
    row.icon:SetTexture(I.IconTexture(st.icon))
    row.name:SetText(UI.Escape(st.name))
    local n = S:Total(st)
    row.info:SetText(n == 1 and "1 item" or (n .. " items"))
    row.sel:SetShown(st.id == m.into)
  end)
  m.go:SetEnabled(here ~= nil and (m.mode == "new" or m.into ~= nil))
end

-- Open the drop card for a bag slot.
function S:OpenDrop(page, slot)
  local m = self:BuildDrop(page)
  if self.panel then self.panel:Hide() end
  m.slotIndex, m.n, m.into = slot, 1, nil
  m.icon, m.hidden = S.DEFAULT_ICON, false
  local here = S.Here()
  local nearby = here and self:Nearby(here) or {}
  m.mode = #nearby > 0 and "old" or "new"
  if nearby[1] then m.into = nearby[1].id end
  m.new.name.edit:SetText("")
  m:Show()
  self:RefreshDrop()
end
