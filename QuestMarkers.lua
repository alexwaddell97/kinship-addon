-- Kinship RP: quest levels and world markers.
--
-- A quest can have a level (or a range, "18-22"), coloured the way the game
-- colours quests against your own level. It can also have a marker for where
-- it happens, and each objective one of its own: a spot on a map, optionally
-- an area around it. Markers travel with the quest when it's offered.
--
-- Tracked quests' markers show as pins on the world map (the quest's icon
-- for the quest, numbered dots for objectives, a ring for an area) and on
-- the minimap (at its edge when they're further away), and the objective
-- tracker shows how far away they are.
--
--   marker = { m = mapID, x = 0..1, y = 0..1, r = yards (optional), z = zone name }
--   K.QuestMarkers.Sanitize(v), .Here(), .Label(m), .Distance(m), :Pick(callback)
--   K.QuestMarkers.LevelText(q), .LevelHex(q)

local ADDON, ns = ...
local K = ns.K
local UI = K.UI
local Safe = K.Safe
local QM = {}
K.QuestMarkers = QM

QM.SIZES = { { r = 0, label = "Exact spot" }, { r = 30, label = "Small area" }, { r = 100, label = "Wide area" } }
QM.PIN_ICON = K.Art("IconPlace")

local function S() return K.db and K.db.settings or {} end

---------------------------------------------------------------------------
-- Levels
---------------------------------------------------------------------------
local function Level(v)
  v = tonumber(v)
  if not v or v ~= v then return nil end
  v = math.floor(v)
  if v < 1 or v > 100 then return nil end
  return v
end
QM.Level = Level

-- "18", "18-22" or nil.
function QM.LevelText(q)
  local lo, hi = q and Level(q.level), q and Level(q.levelMax)
  if not lo then return nil end
  if hi and hi > lo then return ("%d-%d"):format(lo, hi) end
  return tostring(lo)
end

-- The game's quest colour for that level against yours, as hex (for chrome or tooltips).
function QM.LevelColor(q)
  local lo = q and Level(q.level)
  if not lo then return nil end
  local c = GetQuestDifficultyColor and GetQuestDifficultyColor(lo)
  if type(c) == "table" and c.r then return { c.r, c.g, c.b } end
  local d = lo - (UnitLevel("player") or lo)
  if d >= 5 then return { 1, 0.1, 0.1 } elseif d >= 3 then return { 1, 0.5, 0.25 }
  elseif d >= -2 then return { 1, 1, 0 } elseif d >= -8 then return { 0.25, 0.75, 0.25 } end
  return { 0.5, 0.5, 0.5 }
end

function QM.LevelHex(q, onCard)
  local c = QM.LevelColor(q)
  if not c then return nil end
  return onCard and UI.CardHex(c) or UI.Hex(c)
end

---------------------------------------------------------------------------
-- Markers
---------------------------------------------------------------------------
local function Finite(v) return type(v) == "number" and v == v and v ~= math.huge and v ~= -math.huge end

function QM.Sanitize(v)
  if type(v) ~= "table" then return nil end
  local m, x, y = tonumber(v.m), tonumber(v.x), tonumber(v.y)
  if not (Finite(m) and Finite(x) and Finite(y)) then return nil end
  if m <= 0 or m > 1000000 or m ~= math.floor(m) then return nil end
  if x < 0 or x > 1 or y < 0 or y > 1 then return nil end
  local r = tonumber(v.r)
  r = (Finite(r) and r > 0) and math.min(500, math.floor(r)) or nil
  local z = type(v.z) == "string" and (v.z:gsub("[%c|]", "")):sub(1, 60) or nil
  if z == "" then z = nil end
  return { m = m, x = math.floor(x * 10000 + 0.5) / 10000, y = math.floor(y * 10000 + 0.5) / 10000, r = r, z = z }
end

local function MapName(m)
  local info = C_Map and C_Map.GetMapInfo and C_Map.GetMapInfo(m)
  return info and info.name or nil
end

-- "Elwynn Forest  42.1, 65.3"
function QM.Label(mk)
  if not mk then return nil end
  local z = mk.z or MapName(mk.m) or "Somewhere"
  return ("%s  %.1f, %.1f"):format(UI.Escape(z), mk.x * 100, mk.y * 100)
end

-- Your map and spot, or nil and why not.
local function PlayerPos()
  if not (C_Map and C_Map.GetBestMapForUnit and C_Map.GetPlayerMapPosition) then return nil end
  local map = C_Map.GetBestMapForUnit("player")
  if not map then return nil end
  local ok, pos = pcall(C_Map.GetPlayerMapPosition, map, "player")
  if not ok or not pos then return nil end
  local x, y = pos:GetXY()
  if not (Finite(x) and Finite(y)) or (x == 0 and y == 0) then return nil end
  return map, x, y
end

function QM.Here()
  local map, x, y = PlayerPos()
  if not map then return nil, "You can't mark a spot here (inside a dungeon, or the map doesn't know where you are)." end
  return QM.Sanitize({ m = map, x = x, y = y, z = MapName(map) })
end

-- Where a spot on one map falls on another (a zone's spot on its continent, a city's on its zone).
local function Project(map, x, y, onMap)
  if map == onMap then return x, y end
  if not (C_Map and C_Map.GetMapRectOnMap) then return nil end
  local ok, minX, maxX, minY, maxY = pcall(C_Map.GetMapRectOnMap, map, onMap)
  if ok and minX and maxX and minY and maxY and maxX > minX and maxY > minY then
    local px, py = minX + (maxX - minX) * x, minY + (maxY - minY) * y
    if px >= 0 and px <= 1 and py >= 0 and py <= 1 then return px, py end
  end
end
QM.Project = Project

local sizes = {}
local function MapSize(map)
  if sizes[map] == nil then
    local w, h
    if C_Map and C_Map.GetMapWorldSize then
      local ok, a, b = pcall(C_Map.GetMapWorldSize, map)
      if ok and Finite(a) and Finite(b) and a > 0 and b > 0 then w, h = a, b end
    end
    sizes[map] = w and { w, h } or false
  end
  local s = sizes[map]
  if s then return s[1], s[2] end
end
QM.MapSize = MapSize

-- Yards to a marker, and the offset east / north, or nil (another zone, or unknown).
function QM.Distance(mk)
  if not mk then return nil end
  local pm, px, py = PlayerPos()
  if not pm then return nil end
  local tx, ty = Project(mk.m, mk.x, mk.y, pm)
  local w, h = MapSize(pm)
  if not tx then
    local x2, y2 = Project(pm, px, py, mk.m)
    if not x2 then return nil end
    px, py, tx, ty = x2, y2, mk.x, mk.y
    w, h = MapSize(mk.m)
  end
  if not w then return nil end
  local east, south = (tx - px) * w, (ty - py) * h
  return math.sqrt(east * east + south * south), east, -south
end

-- "140 yds", "1.2 km"-free: yards all the way, rounded to tens.
function QM.DistText(d)
  if not d then return nil end
  if d < 15 then return "here" end
  return ("%d yds"):format(math.floor(d / 10 + 0.5) * 10)
end

---------------------------------------------------------------------------
-- Picking a spot on the world map
---------------------------------------------------------------------------
local picker
function QM:Pick(onPick)
  if InCombatLockdown() then K:Print("Not during combat.") return end
  local map = _G.WorldMapFrame
  if not map then K:Print("The world map isn't available.") return end
  local journal = K.Journal and K.Journal.frame
  local reopen = journal and journal:IsShown()
  if reopen then journal:Hide() end
  if not map:IsShown() and ToggleWorldMap then ToggleWorldMap() end
  local scroll = map.ScrollContainer or map
  if not picker then
    picker = CreateFrame("Button", nil, scroll)
    picker:SetAllPoints(scroll)
    picker:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    picker.banner = UI.Panel(picker)
    picker.banner:SetSize(360, 34)
    picker.banner:SetPoint("TOP", 0, -10)
    picker.banner.t = UI.Text(picker.banner, "Click where it happens. Right-click to cancel.", "Body", "heading")
    picker.banner.t:SetPoint("CENTER")
    picker:SetScript("OnHide", function(self) if self.done then self.done(nil) end end)
  end
  picker:SetFrameLevel(scroll:GetFrameLevel() + 500)
  local finished = false
  local function Done(mk)
    if finished then return end
    finished = true
    picker.done = nil
    picker:Hide()
    if mk then
      if map:IsShown() and HideUIPanel then pcall(HideUIPanel, map) end
      onPick(mk)
    end
    if reopen and journal then journal:Show() end
  end
  picker.done = Done
  picker:SetScript("OnClick", function(_, button)
    if button ~= "LeftButton" then Done(nil) return end
    local mapID = map.GetMapID and map:GetMapID()
    local x, y
    if scroll.GetNormalizedCursorPosition then x, y = scroll:GetNormalizedCursorPosition() end
    if not x and map.GetCanvas then
      local canvas = map:GetCanvas()
      local cx, cy = GetCursorPosition()
      local s = canvas:GetEffectiveScale()
      x = (cx / s - canvas:GetLeft()) / canvas:GetWidth()
      y = (canvas:GetTop() - cy / s) / canvas:GetHeight()
    end
    local mk = mapID and QM.Sanitize({ m = mapID, x = x, y = y, z = MapName(mapID) })
    if not mk then K:Print("That isn't a spot on the map.") return end
    Done(mk)
  end)
  picker:Show()
  UI.FadeIn(picker.banner, 0.15)
end

-- The menu behind a marker button: mark here, pick on map, area size, clear.
-- get() returns the marker; set(mk or nil) stores it.
function QM:Menu(owner, title, get, set)
  UI.Menu(owner, function(root)
    root:CreateTitle(title)
    root:CreateButton("Mark where I'm standing", function()
      local mk, err = QM.Here()
      if not mk then K:Print(err) return end
      local old = get()
      mk.r = old and old.r or nil
      set(mk)
    end)
    root:CreateButton("Pick on the world map", function()
      QM:Pick(function(mk)
        local old = get()
        mk.r = old and old.r or nil
        set(mk)
      end)
    end)
    local cur = get()
    if cur then
      root:CreateDivider()
      for _, sz in ipairs(QM.SIZES) do
        root:CreateRadio(sz.label, function() local m = get(); return m and (m.r or 0) == sz.r end, function()
          local m = get()
          if m then m.r = sz.r > 0 and sz.r or nil; set(m) end
        end)
      end
      root:CreateDivider()
      root:CreateButton("Clear", function() set(nil) end)
    end
  end)
end

---------------------------------------------------------------------------
-- Which markers to show: tracked, active quests
---------------------------------------------------------------------------
-- { { mk, quest, index (nil = the quest's own), icon }, ... }
local function Markers()
  local out = {}
  local Q = K.Quests
  if not (Q and K:ExtOn("campaigns")) then return out end
  for _, e in pairs(Q:Log()) do
    if type(e) == "table" and e.state == "active" and e.tracked then
      if e.marker then out[#out + 1] = { mk = e.marker, quest = e, icon = e.icon } end
      local QA = K.QuestAuto
      local mine = Q:IsMine(e)
      for i, o in ipairs(e.objectives or {}) do
        -- Players don't see pins for hidden objectives, or (in order) ones not yet open.
        local shows = not QA or mine or (QA.Visible(e, i) and QA.Open(e, i))
        if o.marker and not o.done and shows then out[#out + 1] = { mk = o.marker, quest = e, index = i } end
      end
    end
  end
  return out
end
QM.Markers = Markers

local function PinTooltip(owner, item)
  local e = item.quest
  GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
  GameTooltip:SetText(("|T%s:16:16:0:0:64:64:5:59:5:59|t  %s"):format(tostring(e.icon or K.Quests.DEFAULT_ICON), UI.Escape(e.title or "")), 1, 0.82, 0)
  if item.index then
    local o = e.objectives[item.index]
    GameTooltip:AddLine(("%d. %s"):format(item.index, UI.Escape(o and o.text or "")), 1, 1, 1, true)
  end
  GameTooltip:AddLine(QM.Label(item.mk), 0.75, 0.75, 0.75)
  local d = QM.Distance(item.mk)
  if d then GameTooltip:AddLine(QM.DistText(d) .. (item.mk.r and (", within " .. item.mk.r .. " yds") or ""), 0.55, 0.80, 1) end
  GameTooltip:AddLine("Click to open the quest.", 0.62, 0.62, 0.62)
  GameTooltip:Show()
end

-- One pin: the quest's icon in a ring, or a numbered dot for an objective.
local function NewPin(parent, size)
  local p = CreateFrame("Button", nil, parent)
  p:SetSize(size, size)
  p.area = UI.Circle(p, size, "BACKGROUND")
  p.area:SetPoint("CENTER")
  p.ring = UI.Circle(p, size, "ARTWORK", 0)
  p.ring:SetPoint("CENTER")
  p.icon = p:CreateTexture(nil, "ARTWORK", nil, 1)
  p.icon:SetSize(size - 4, size - 4)
  p.icon:SetPoint("CENTER")
  p.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
  UI.Round(p.icon)
  p.num = p:CreateFontString(nil, "OVERLAY")
  p.num:SetFontObject(UI.FONTS.Label)
  local face, fs = UI.FONTS.Label:GetFont()
  if face then p.num:SetFont(face, fs, "OUTLINE") end
  p.num:SetPoint("CENTER", 0, 0)
  p:SetScript("OnEnter", function(self) if self.item then PinTooltip(self, self.item) end end)
  p:SetScript("OnLeave", function() GameTooltip:Hide() end)
  p:SetScript("OnClick", function(self) if self.item then K.Quests:Open(self.item.quest.id) end end)
  function p:Set(item)
    self.item = item
    local u = K:Theme().ui
    if item.index then
      self.icon:SetTexture("Interface\\Buttons\\WHITE8X8")
      self.icon:SetVertexColor(0.10, 0.22, 0.22, 1)
      self.num:SetText(item.index)
      self.num:Show()
    else
      self.icon:SetTexture(item.icon or K.Quests.DEFAULT_ICON)
      self.icon:SetVertexColor(1, 1, 1, 1)
      self.num:Hide()
    end
    self.ring:SetVertexColor(u[1], u[2], u[3], 1)
  end
  return p
end

---------------------------------------------------------------------------
-- World map pins
---------------------------------------------------------------------------
local wm = { pins = {}, used = 0 }

function wm:Place()
  local owner = self.owner
  if not owner then return end
  local canvas = owner:GetCanvas()
  local scale = owner.GetCanvasScale and owner:GetCanvasScale() or 1
  if not scale or scale <= 0 then scale = 1 end
  local w, h = canvas:GetWidth(), canvas:GetHeight()
  local level = canvas:GetFrameLevel() + 1100
  for i = 1, self.used do
    local p = self.pins[i]
    p:SetScale(1 / scale)
    p:SetFrameLevel(level + (p.item.index and 0 or 1))
    p:ClearAllPoints()
    p:SetPoint("CENTER", canvas, "TOPLEFT", p.nx * w * scale, -p.ny * h * scale)
    -- An area: a soft disc sized to the ground it covers on this map
    local r, mw = p.item.mk.r, p.mapW
    if r and mw then
      local px = (r / mw) * w * scale * 2
      p.area:SetSize(math.max(p:GetWidth(), px), math.max(p:GetWidth(), px))
      p.area:Show()
    else
      p.area:Hide()
    end
  end
end

function wm:Layout()
  self.used = 0
  local owner = self.owner
  if owner and owner:IsShown() and S().questPins ~= false then
    local mapID = owner:GetMapID()
    for _, item in ipairs(Markers()) do
      local x, y = Project(item.mk.m, item.mk.x, item.mk.y, mapID)
      if x then
        self.used = self.used + 1
        local p = self.pins[self.used]
        if not p then p = NewPin(owner:GetCanvas(), 22); self.pins[self.used] = p end
        p.nx, p.ny = x, y
        p.mapW = MapSize(mapID)
        p:Set(item)
        p:SetSize(item.index and 18 or 24, item.index and 18 or 24)
        p.icon:SetSize(p:GetWidth() - 4, p:GetWidth() - 4)
        p.ring:SetSize(p:GetWidth(), p:GetWidth())
        local a = K:Theme().accent
        p.area:SetVertexColor(a[1], a[2], a[3], 0.18)
        p:Show()
      end
    end
  end
  for i = self.used + 1, #self.pins do self.pins[i]:Hide(); self.pins[i].item = nil end
  self:Place()
end

local function InstallWorldMap()
  if wm.provider then return true end
  local map = _G.WorldMapFrame
  if not (map and map.AddDataProvider and map.GetCanvas and map.GetMapID and MapCanvasDataProviderMixin and CreateFromMixins) then return false end
  wm.owner = map
  local pr = CreateFromMixins(MapCanvasDataProviderMixin)
  function pr:RemoveAllData() wm.used = 0; for _, p in ipairs(wm.pins) do p:Hide() end end
  function pr:RefreshAllData() wm:Layout() end
  function pr:OnMapChanged() wm:Layout() end
  function pr:OnCanvasScaleChanged() wm:Place() end
  function pr:OnCanvasSizeChanged() wm:Place() end
  map:AddDataProvider(pr)
  wm.provider = pr
  return true
end

---------------------------------------------------------------------------
-- Minimap pins
---------------------------------------------------------------------------
-- How many yards the minimap shows across, by zoom (outdoors / indoors).
local OUTDOOR = { [0] = 466 + 2 / 3, 400, 333 + 1 / 3, 266 + 2 / 3, 200, 133 + 1 / 3 }
local INDOOR = { [0] = 300, 240, 180, 120, 80, 50 }
local mm = { pins = {} }

local function Square()
  local shape = rawget(_G, "GetMinimapShape")
  if type(shape) == "function" then
    local ok, s = pcall(shape)
    return ok and s == "SQUARE"
  end
  return false
end

QM.cache = {}
function mm:Update()
  local minimap = _G.Minimap
  local list = (minimap and minimap:IsVisible() and S().questMinimap ~= false) and QM.cache or {}
  local used = 0
  if #list > 0 then
    local zoom = minimap:GetZoom() or 0
    local across = (IsIndoors() and INDOOR or OUTDOOR)[zoom] or 300
    local R = minimap:GetWidth() / 2
    local perYard = R / (across / 2)
    local getCVar = (C_CVar and C_CVar.GetCVar) or GetCVar
    local rotate = getCVar and getCVar("rotateMinimap") == "1"
    local facing = rotate and GetPlayerFacing and GetPlayerFacing() or nil
    local square = Square()
    for _, item in ipairs(list) do
      local d, east, north = QM.Distance(item.mk)
      if d then
        local x, y = east * perYard, north * perYard
        if facing then
          local c, s = math.cos(facing), math.sin(facing)
          x, y = x * c + y * s, -x * s + y * c
        end
        local edge = false
        local lim = R - 7
        if square then
          if math.abs(x) > lim or math.abs(y) > lim then
            local k = lim / math.max(math.abs(x), math.abs(y))
            x, y, edge = x * k, y * k, true
          end
        else
          local len = math.sqrt(x * x + y * y)
          if len > lim then x, y, edge = x / len * lim, y / len * lim, true end
        end
        used = used + 1
        local p = self.pins[used]
        if not p then
          p = NewPin(minimap, 14)
          p.area:Hide()
          self.pins[used] = p
        end
        p:SetFrameLevel(minimap:GetFrameLevel() + 8)
        p:Set(item)
        local size = item.index and 13 or 16
        p:SetSize(size, size)
        p.icon:SetSize(size - 3, size - 3)
        p.ring:SetSize(size, size)
        p.area:Hide()
        p:SetAlpha(edge and 0.6 or 1)
        p:ClearAllPoints()
        p:SetPoint("CENTER", minimap, "CENTER", x, y)
        p:Show()
      end
    end
  end
  for i = used + 1, #self.pins do self.pins[i]:Hide(); self.pins[i].item = nil end
end

---------------------------------------------------------------------------
-- Ticking: minimap pins often, tracker distances when they change
---------------------------------------------------------------------------
QM.dist = {}   -- [marker] = rounded yards, read by the tracker
local tick = CreateFrame("Frame")
tick.a, tick.b = 0, 0
tick:SetScript("OnUpdate", function(self, elapsed)
  self.a, self.b = self.a + elapsed, self.b + elapsed
  if self.a >= 0.1 then
    self.a = 0
    K.Try("minimap pins", mm.Update, mm)
  end
  if self.b >= 1 then
    self.b = 0
    local changed = false
    local seen = {}
    QM.cache = Markers()
    for _, item in ipairs(QM.cache) do
      local d = QM.Distance(item.mk)
      local r = d and math.floor(d / 10 + 0.5) or false
      seen[item.mk] = true
      if QM.dist[item.mk] ~= r then QM.dist[item.mk] = r; changed = true end
    end
    for mk in pairs(QM.dist) do if not seen[mk] then QM.dist[mk] = nil; changed = true end end
    if changed and K.QuestTracker then K.QuestTracker:Refresh() end
  end
end)

-- The tracker's text for a marker: "140 yds" (nil when unknown).
function QM.TrackerDistance(mk)
  local r = mk and QM.dist[mk]
  if not r then return nil end
  return QM.DistText(r * 10)
end

---------------------------------------------------------------------------
-- Forever World Map's explorer map: a layer of its own, when that addon
-- offers a public way in (ForeverWorldMapAPI.AddLayer / .Refresh, version 1;
-- see docs/ForeverWorldMap-API.md). Without it, nothing happens here: its
-- Blizzard-map mode already shows the pins above.
---------------------------------------------------------------------------
local FWM_KEY = "kinshipQuests"
local fwm
local function HookForeverMap()
  if fwm then return true end
  local api = rawget(_G, "ForeverWorldMapAPI")
  if type(api) ~= "table" or type(api.AddLayer) ~= "function" then return false end
  local ok, layer = pcall(api.AddLayer, {
    key = FWM_KEY, label = "Roleplay quests (Kinship)", level = 42, size = 22, icon = { texture = QM.PIN_ICON },
    perMap = function(uiMapID, marks)
      if S().questPins == false then return end
      for n, item in ipairs(QM.cache) do
        local mk = item.mk
        -- Each mark once: on its own map, or on the zone a city map sits in.
        local here = mk.m == uiMapID
        if not here and C_Map and C_Map.GetMapInfo then
          local info = C_Map.GetMapInfo(mk.m)
          here = info and info.parentMapID == uiMapID and info.mapType ~= nil and info.mapType >= 4
        end
        local x, y = mk.x, mk.y
        if here and mk.m ~= uiMapID then x, y = Project(mk.m, mk.x, mk.y, uiMapID) end
        if here and x then
          marks[#marks + 1] = {
            id = ("%s#%d"):format(item.quest.id or "?", item.index or 0), x = x, y = y,
            texture = item.index and QM.PIN_ICON or (item.icon or K.Quests.DEFAULT_ICON),
            size = item.index and 16 or 22,
            tooltip = function(tooltip)
              local e = item.quest
              tooltip:SetText(UI.Escape(e.title or "Roleplay quest"), 1, 0.82, 0)
              if item.index then
                local o = e.objectives[item.index]
                tooltip:AddLine(("%d. %s"):format(item.index, UI.Escape(o and o.text or "")), 1, 1, 1, true)
              end
              local d = QM.Distance(mk)
              if d then tooltip:AddLine(QM.DistText(d), 0.55, 0.80, 1) end
              tooltip:AddLine("Click to open the quest in Kinship.", 0.6, 0.6, 0.6)
            end,
            click = function() K.Quests:Open(item.quest.id) end,
          }
        end
      end
    end,
  })
  if ok and layer then fwm = api end
  return fwm ~= nil
end

local function RefreshForeverMap()
  if fwm and fwm.Refresh then pcall(fwm.Refresh, FWM_KEY) end
end
K:On("QUESTS", function() C_Timer.After(0, RefreshForeverMap) end)
K:On("LOGIN", function() C_Timer.After(1, HookForeverMap) end)

---------------------------------------------------------------------------
-- /kin markers: what Kinship can see, for when pins don't show
---------------------------------------------------------------------------
function QM:Report()
  local Q = K.Quests
  if not (Q and K:ExtOn("campaigns")) then K:Print("Quests are switched off (Settings > Extended features).") return end
  local tracked, stale = 0, 0
  for id, e in pairs(Q:Log()) do
    if type(e) == "table" and e.state == "active" and e.tracked then
      tracked = tracked + 1
      local hasOwn = e.marker ~= nil
      for _, o in ipairs(e.objectives or {}) do if o.marker then hasOwn = true end end
      local lib = Q:Library()[id]
      local libHas = lib and lib.marker ~= nil
      if lib then for _, o in ipairs(lib.objectives or {}) do if o.marker then libHas = true end end end
      if libHas and not hasOwn then stale = stale + 1 end
    end
  end
  local list = Markers()
  K:Print(("Tracked roleplay quests: %d  ·  markers on them: %d"):format(tracked, #list))
  if stale > 0 then
    K:Print(("%d of them got markers after you started them: open each in Quests > Write and press Save."):format(stale))
  end
  K:Print("World map pins: " .. (wm.provider and (S().questPins ~= false and "on" or "switched off in Settings") or "not hooked into the map"))
  K:Print("Minimap pins: " .. (S().questMinimap ~= false and "on" or "switched off in Settings"))
  if C_AddOns and C_AddOns.IsAddOnLoaded and C_AddOns.IsAddOnLoaded("ForeverWorldMap") then
    K:Print("Forever World Map's explorer map: " .. (fwm and "pins added"
      or "no way in yet (it needs ForeverWorldMapAPI; its Blizzard-map mode shows them)"))
  end
  local pm, px, py = PlayerPos()
  K:Print(pm and ("You are at %s  %.1f, %.1f"):format(MapName(pm) or tostring(pm), px * 100, py * 100)
    or "Your position isn't available here (inside a dungeon?).")
  for _, item in ipairs(list) do
    local d = QM.Distance(item.mk)
    K:Print(("  %s%s: %s  ·  %s"):format(item.quest.title or "?", item.index and (" #" .. item.index) or "",
      QM.Label(item.mk), d and QM.DistText(d) or "not on your map"))
  end
end

---------------------------------------------------------------------------
-- Start-up and settings
---------------------------------------------------------------------------
K:On("LOGIN", function()
  local s = K.db.settings
  if s.questPins == nil then s.questPins = true end
  if s.questMinimap == nil then s.questMinimap = true end
  if not K.Try("map pins", InstallWorldMap) or not wm.provider then
    local ev = CreateFrame("Frame")
    ev:RegisterEvent("ADDON_LOADED")
    ev:SetScript("OnEvent", function(self, _, name)
      if name == "Blizzard_WorldMap" and K.Try("map pins", InstallWorldMap) and wm.provider then self:UnregisterAllEvents() end
    end)
  end
end)
K:On("QUESTS", function() QM.cache = Markers(); K.Try("map pins", wm.Layout, wm) end)

K:RegisterSettings({ id = "questMarkers", title = "Quest markers", order = 35,
  shown = function() return K:ExtOn("campaigns") end, build = function(card)
  card:Toggle("On the world map", "Pins for your tracked roleplay quests: the quest's icon, numbered objectives, and a ring for an area.",
    { get = function() return S().questPins ~= false end, set = function(v) K.db.settings.questPins = v; K.Try("map pins", wm.Layout, wm) end })
  card:Toggle("On the minimap", "The same pins on your minimap, at its edge when they're further away.", "questMinimap")
end })
