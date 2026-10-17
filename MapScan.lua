-- Kinship RP: find roleplayers on the world map. There's no broadcast channel
-- on this client, so a scan is a K.Net "scan" request on YELL (Kinship users
-- nearby in the zone); those who allow it whisper back where they are
-- ("scanr"), and they show as status-coloured dots on the map for a while.

local ADDON, ns = ...
local K = ns.K
local UI = K.UI
local Safe = K.Safe
local M = { found = {}, replied = {}, pins = {}, used = 0 }
K.MapScan = M

local PIN_LIFE = 180        -- seconds a dot stays on the map
local SCAN_TIME = 4         -- seconds the button pulses while answers come in
local SCAN_COOLDOWN = 8     -- between your own scans
local REPLY_GAP = 10        -- answer the same person at most this often
local SCAN_ICON = "Interface\\Icons\\INV_Misc_Spyglass_02"

local function S() return K.db.settings end
local function Short(n) return Ambiguate and Ambiguate(n, "none") or n end

---------------------------------------------------------------------------
-- Privacy and your position
---------------------------------------------------------------------------
-- Why you're hidden from scans right now ("off", "ooc", "pvp", "instance"), or nil.
function M:Hidden()
  local s = S()
  if not s.mapShare then return "off" end
  if s.mapHideOOC and (K:Profile().status or "ooc") == "ooc" then return "ooc" end
  if s.mapHidePvP then
    local pvp = UnitIsPVP("player")
    if Safe(pvp) and pvp then return "pvp" end
  end
  if IsInInstance() then return "instance" end
  return nil
end

local HIDDEN_TEXT = {
  off = "You're hidden: sharing your location is switched off.",
  ooc = "You're hidden while out of character.",
  pvp = "You're hidden while flagged for PvP.",
  instance = "You're hidden inside dungeons and raids.",
}

-- Your position on the asked-for map if you're on it, else on your own zone map.
local function MyPosition(wanted)
  if not (C_Map and C_Map.GetBestMapForUnit and C_Map.GetPlayerMapPosition) then return nil end
  local function at(map)
    if type(map) ~= "number" or map < 1 or map > 100000 then return nil end
    local ok, pos = pcall(C_Map.GetPlayerMapPosition, map, "player")
    if not ok or not pos then return nil end
    local x, y = pos.x, pos.y
    if not Safe(x) or not Safe(y) or type(x) ~= "number" or type(y) ~= "number" then return nil end
    if x < 0 or x > 1 or y < 0 or y > 1 or (x == 0 and y == 0) then return nil end
    return map, x, y
  end
  local m, x, y = at(tonumber(wanted))
  if m then return m, x, y end
  local ok, best = pcall(C_Map.GetBestMapForUnit, "player")
  if ok and Safe(best) then return at(best) end
end

---------------------------------------------------------------------------
-- Messages
---------------------------------------------------------------------------
K.Net:On("scan", function(msg, sender)
  if M:Hidden() then return end
  local key = K.NameKey(sender)
  local now = GetTime()
  if not key or (M.replied[key] and now - M.replied[key] < REPLY_GAP) then return end
  M.replied[key] = now
  -- A short random wait, so a crowd doesn't answer in the same instant
  C_Timer.After(0.2 + math.random() * 1.3, function()
    if M:Hidden() then return end
    local map, x, y = MyPosition(msg.m)
    if not map then return end
    local p = K:Profile()
    K.Net:Send("scanr", {
      m = map, x = math.floor(x * 10000 + 0.5), y = math.floor(y * 10000 + 0.5),
      s = K.STATUS[p.status or ""] and p.status or "ooc", n = K:DisplayName(p),
    }, "WHISPER", sender)
  end)
end)

K.Net:On("scanr", function(msg, sender)
  if not M.scanAt or GetTime() - M.scanAt > 30 then return end   -- only answers to our own scan
  if K:IsIgnored(sender) then return end
  local map, x, y = tonumber(msg.m), tonumber(msg.x), tonumber(msg.y)
  if not map or not x or not y or x < 0 or x > 10000 or y < 0 or y > 10000 then return end
  local key = K.NameKey(sender)
  if not key then return end
  local rp = type(msg.n) == "string" and strtrim((UI.Clean(msg.n):gsub("[\r\n]", " "))) or ""
  M.found[key] = {
    name = sender, map = map, x = x / 10000, y = y / 10000, t = time(),
    status = K.STATUS[msg.s or ""] and msg.s or "ooc",
    rp = (rp ~= "" and #rp <= 60) and rp or nil,
  }
  M:Layout()
end)

---------------------------------------------------------------------------
-- Pins: small frames on the map canvas, counter-scaled so they keep their
-- size when you zoom. A data provider tells us when the map, its size or
-- its zoom changes.
---------------------------------------------------------------------------
local owner, provider

-- A found player's position on the map being viewed (0-1), or nil.
local function Project(e, mapID)
  if not mapID then return nil end
  if e.map == mapID then return e.x, e.y end
  if C_Map.GetMapRectOnMap then
    local ok, minX, maxX, minY, maxY = pcall(C_Map.GetMapRectOnMap, e.map, mapID)
    if ok and minX and maxX and minY and maxY and maxX > minX and maxY > minY then
      local x, y = minX + (maxX - minX) * e.x, minY + (maxY - minY) * e.y
      if x >= 0 and x <= 1 and y >= 0 and y <= 1 then return x, y end
    end
  end
end

local function DisplayName(e)
  local reg = K:ProfileOf(e.name)
  local p = reg and reg.profile
  if p then
    local rp = strtrim(UI.Clean(p.rpName or ""))
    if rp ~= "" then
      local prefix = strtrim(UI.Clean(p.prefix or ""))
      return prefix ~= "" and (prefix .. " " .. rp) or rp, p
    end
  end
  return e.rp or Short(e.name), p
end

local function PinEnter(pin)
  UI.Tween(pin, 1, 0.12, pin.paintHover, UI.Ease.outQuart)
  local e = pin.entry
  if not e then return end
  local name, p = DisplayName(e)
  local s = K.STATUS[e.status] or K.STATUS.ooc
  GameTooltip:SetOwner(pin, "ANCHOR_RIGHT")
  GameTooltip:SetText(name, 1, 0.86, 0.55)
  if p and p.epithet and p.epithet ~= "" then GameTooltip:AddLine(UI.Clean(p.epithet), 0.30, 0.72, 0.68) end
  GameTooltip:AddLine(("|T%s:12:12|t %s"):format(K.ICON, s.label), s.color[1], s.color[2], s.color[3])
  local char = Short(e.name)
  if char ~= name then GameTooltip:AddLine(char, 0.7, 0.7, 0.7) end
  if p and p.currently and p.currently ~= "" then
    GameTooltip:AddLine("\"" .. UI.Clean(p.currently) .. "\"", 0.85, 0.85, 0.85, true)
  end
  GameTooltip:AddLine("Seen " .. UI.Ago(e.t), 0.6, 0.6, 0.6)
  GameTooltip:AddLine("Click to view their profile", 0.45, 0.8, 0.75)
  GameTooltip:Show()
  if K.Comm and K.Comm.Request then K.Comm:Request(e.name) end
end

local function PinLeave(pin)
  UI.Tween(pin, 0, 0.15, pin.paintHover, UI.Ease.outQuart)
  GameTooltip:Hide()
end

local function PinClick(pin, button)
  local e = pin.entry
  if button ~= "LeftButton" or not e then return end
  GameTooltip:Hide()
  if WorldMapFrame and WorldMapFrame:IsShown() and not InCombatLockdown() then pcall(HideUIPanel, WorldMapFrame) end
  K.Viewer:ShowName(e.name)
end

local function NewPin(i)
  local canvas = owner:GetCanvas()
  local p = CreateFrame("Button", nil, canvas)
  p:SetSize(30, 30)
  p:RegisterForClicks("LeftButtonUp")
  p.halo = UI.Circle(p, 26, "BACKGROUND")
  p.halo:SetPoint("CENTER")
  p.shadow = UI.Circle(p, 19, "ARTWORK", 0)
  p.shadow:SetPoint("CENTER", 0, -1)
  p.shadow:SetVertexColor(0, 0, 0, 0.55)
  p.ring = UI.Circle(p, 17, "ARTWORK", 1)
  p.ring:SetPoint("CENTER")
  p.dot = UI.Circle(p, 13, "ARTWORK", 2)
  p.dot:SetPoint("CENTER")
  p.shine = UI.Circle(p, 5, "ARTWORK", 3)
  p.shine:SetPoint("CENTER", -2, 2)
  p.shine:SetVertexColor(1, 1, 1, 0.45)
  p.phase = i * 0.7
  function p.paintHover(v)
    local grow = 4 * v
    p.ring:SetSize(17 + grow, 17 + grow)
    p.shadow:SetSize(19 + grow, 19 + grow)
    p.dot:SetSize(13 + grow, 13 + grow)
    local g = K:Theme().ui
    p.ring:SetVertexColor(1 + (g[1] - 1) * v, 1 + (g[2] - 1) * v, 1 + (g[3] - 1) * v, 0.95)
  end
  p.paintHover(0)
  p:SetScript("OnEnter", PinEnter)
  p:SetScript("OnLeave", PinLeave)
  p:SetScript("OnClick", PinClick)
  return p
end

local function HideFrom(i)
  for n = i, #M.pins do M.pins[n]:Hide(); M.pins[n].entry = nil end
end

-- Put the shown pins where they belong at the canvas's current size and zoom.
function M:Place()
  if not owner then return end
  local canvas = owner:GetCanvas()
  local scale = owner.GetCanvasScale and owner:GetCanvasScale() or 1
  if not scale or scale <= 0 then scale = 1 end
  local w, h = canvas:GetWidth(), canvas:GetHeight()
  local level = canvas:GetFrameLevel() + 1200
  for i = 1, self.used do
    local p = self.pins[i]
    p:SetScale(1 / scale)
    p:SetFrameLevel(level)
    p:ClearAllPoints()
    p:SetPoint("CENTER", canvas, "TOPLEFT", p.nx * w * scale, -p.ny * h * scale)
  end
end

-- Drop expired or ignored people, then lay out a pin for everyone on this map.
function M:Layout()
  self.used = 0
  local now = time()
  for key, e in pairs(self.found) do
    if now - e.t > PIN_LIFE or K:IsIgnored(e.name) then self.found[key] = nil end
  end
  if owner and owner:IsShown() then
    local mapID = owner:GetMapID()
    for _, e in pairs(self.found) do
      local x, y = Project(e, mapID)
      if x then
        self.used = self.used + 1
        local p = self.pins[self.used]
        if not p then p = NewPin(self.used); self.pins[self.used] = p end
        p.nx, p.ny, p.entry = x, y, e
        local c = (K.STATUS[e.status] or K.STATUS.ooc).color
        p.dot:SetVertexColor(c[1], c[2], c[3], 1)
        p.halo:SetVertexColor(c[1], c[2], c[3], 0.25)
        p:Show()
      end
    end
    self:Place()
  end
  HideFrom(self.used + 1)
  self:UpdateButton()
end

---------------------------------------------------------------------------
-- The "Find roleplayers" button on the map
---------------------------------------------------------------------------
function M:BuildButton()
  if self.button then return end
  local host = owner.ScrollContainer or owner
  local b = CreateFrame("Button", nil, owner)
  b:SetHeight(28)
  b:SetPoint("TOPRIGHT", host, "TOPRIGHT", -10, -10)
  b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  b.bg = b:CreateTexture(nil, "BACKGROUND")
  b.bg:SetAllPoints()
  b.bg:SetTexture("Interface\\Buttons\\WHITE8X8")
  b.edge = UI.Border(b)
  b.bar = b:CreateTexture(nil, "ARTWORK")
  b.bar:SetTexture("Interface\\Buttons\\WHITE8X8")
  b.bar:SetWidth(2)
  b.bar:SetPoint("TOPLEFT")
  b.bar:SetPoint("BOTTOMLEFT")
  b.pulse = UI.Circle(b, 18, "ARTWORK", 0)
  b.pulse:Hide()
  b.icon = b:CreateTexture(nil, "ARTWORK", nil, 1)
  b.icon:SetSize(18, 18)
  b.icon:SetPoint("LEFT", 9, 0)
  b.icon:SetTexture(SCAN_ICON)
  b.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
  UI.Round(b.icon)
  b.pulse:SetPoint("CENTER", b.icon)
  b.label = UI.Text(b, "Find roleplayers", "Small", "deskText")
  b.label:SetPoint("LEFT", b.icon, "RIGHT", 7, 0)
  b.label:SetWordWrap(false)
  b.count = UI.Chip(b, "Label", true)
  b.count:SetPoint("RIGHT", -8, 0)

  local function paint(p)
    local t = K:Theme()
    b.bg:SetVertexColor(UI.Mix(t.chrome, t.btnHover, p * 0.8))
    b.edge:SetColor(UI.Mix(t.chromeEdge, t.btnEdgeHover, p))
    b.bar:SetVertexColor(t.ui[1], t.ui[2], t.ui[3], 0.35 + 0.65 * math.max(p, b.scanning and 1 or 0))
    b.icon:SetAlpha(0.85 + 0.15 * p)
  end
  b.paint = paint
  UI:OnTheme(function() paint(UI.Progress(b)) end)

  b:SetScript("OnEnter", function(self)
    UI.Tween(self, 1, 0.12, paint)
    GameTooltip:SetOwner(self, "ANCHOR_BOTTOMLEFT")
    GameTooltip:SetText("Find roleplayers", 1, 0.86, 0.55)
    GameTooltip:AddLine("Asks Kinship users nearby in this zone where they are. They show as dots on the map for a few minutes.", 1, 1, 1, true)
    local why = M:Hidden()
    GameTooltip:AddLine(" ")
    if why then GameTooltip:AddLine(HIDDEN_TEXT[why], 0.95, 0.70, 0.40, true)
    else GameTooltip:AddLine("You're visible to other people's scans.", 0.45, 0.85, 0.55, true) end
    GameTooltip:AddLine("Right-click: privacy settings", 0.7, 0.7, 0.7)
    GameTooltip:Show()
  end)
  b:SetScript("OnLeave", function(self) UI.Tween(self, 0, 0.15, paint); GameTooltip:Hide() end)
  b:SetScript("OnClick", function(_, button)
    if button == "RightButton" then
      if WorldMapFrame and WorldMapFrame:IsShown() and not InCombatLockdown() then pcall(HideUIPanel, WorldMapFrame) end
      K.Journal:Open("settings")
    else
      M:Scan()
    end
  end)

  -- Pulse while scanning; breathe the dots' halos; expire old dots.
  local t, tick = 0, 0
  b:SetScript("OnUpdate", function(self, elapsed)
    t, tick = t + elapsed, tick + elapsed
    if self.scanning then
      local p = (t % 1.1) / 1.1
      local size = 18 + 22 * UI.Ease.outQuart(p)
      self.pulse:SetSize(size, size)
      local u = K:Theme().ui
      self.pulse:SetVertexColor(u[1], u[2], u[3], 0.7 * (1 - p))
      self.icon:SetRotation(math.sin(t * 6) * 0.25)
    end
    for i = 1, M.used do
      local pin = M.pins[i]
      local s = 0.5 + 0.5 * math.sin(t * 2.4 + pin.phase)
      local hs = 22 + 8 * s
      pin.halo:SetSize(hs, hs)
      pin.halo:SetAlpha(0.55 + 0.45 * (1 - s))
    end
    if tick > 5 then
      tick = 0
      if next(M.found) then
        local now = time()
        for _, e in pairs(M.found) do
          if now - e.t > PIN_LIFE then M:Layout() break end
        end
      end
    end
  end)
  b:SetScript("OnShow", function() M:Layout() end)
  self.button = b
  self:UpdateButton()
end

function M:UpdateButton()
  local b = self.button
  if not b then return end
  if owner then b:SetFrameLevel(math.min(9000, owner:GetCanvas():GetFrameLevel() + 1300)) end
  local text = self.flash or (b.scanning and "Looking for roleplayers..." or "Find roleplayers")
  b.label:SetText(text)
  b.count:Set(self.used > 0 and tostring(self.used) or nil, K:Theme().ui)
  local w = 9 + 18 + 7 + math.ceil(b.label:GetStringWidth()) + 12 + (b.count:IsShown() and (b.count:GetWidth() + 6) or 0)
  b:SetWidth(math.max(120, w))
  b.paint(UI.Progress(b))
end

-- A short message on the button ("3 found", "No one answered").
function M:Flash(text, secs)
  self.flash = text
  self:UpdateButton()
  local token = {}
  self.flashToken = token
  C_Timer.After(secs or 3, function()
    if M.flashToken == token then M.flash = nil; M:UpdateButton() end
  end)
end

function M:Scan()
  local b = self.button
  if not b or b.scanning then return end
  local now = GetTime()
  if self.scanAt and now - self.scanAt < SCAN_COOLDOWN then
    self:Flash("Just a moment...", 1.5)
    return
  end
  if IsInInstance() then self:Flash("Not inside instances") return end
  local map = owner and owner:GetMapID()
  if not map then
    local ok, best = pcall(C_Map.GetBestMapForUnit, "player")
    map = ok and Safe(best) and best or nil
  end
  if not K.Net:Send("scan", { m = map }, "YELL") then
    self:Flash("Can't scan right now")
    return
  end
  wipe(self.found)
  self.scanMap, self.scanAt, self.flash = map, now, nil
  b.scanning = true
  b.pulse:Show()
  if SOUNDKIT and SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON then PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON) end
  self:Layout()
  C_Timer.After(SCAN_TIME, function()
    b.scanning = false
    b.pulse:Hide()
    b.icon:SetRotation(0)
    M:Layout()
    local n = 0
    for _ in pairs(M.found) do n = n + 1 end
    if n == 0 then M:Flash("No one answered nearby", 4)
    elseif M.used == 0 then M:Flash(n .. " found, not on this map", 4)
    else M:Flash(M.used == 1 and "1 roleplayer found" or (M.used .. " roleplayers found"), 4) end
  end)
end

---------------------------------------------------------------------------
-- Hooking into the world map
---------------------------------------------------------------------------
local function Install()
  if provider then return true end
  local map = WorldMapFrame
  if not (map and map.AddDataProvider and map.GetCanvas and map.GetMapID and MapCanvasDataProviderMixin and CreateFromMixins) then
    return false
  end
  owner = map
  provider = CreateFromMixins(MapCanvasDataProviderMixin)
  function provider:RemoveAllData() HideFrom(1); M.used = 0 end
  function provider:RefreshAllData() M:Layout() end
  function provider:OnMapChanged()
    -- Results belong to the map you scanned: a different map starts clean.
    local id = owner:GetMapID()
    if M.scanMap and id ~= M.scanMap and next(M.found) then wipe(M.found); M.scanMap = nil end
    M:Layout()
  end
  function provider:OnCanvasScaleChanged() M:Place() end
  function provider:OnCanvasSizeChanged() M:Place() end
  map:AddDataProvider(provider)
  M:BuildButton()
  return true
end

K:On("LOGIN", function()
  local s = K.db.settings
  if s.mapShare == nil then s.mapShare = true end
  if s.mapHideOOC == nil then s.mapHideOOC = false end
  if s.mapHidePvP == nil then s.mapHidePvP = true end
  if K:Compat() then return end   -- Total RP 3 has its own map scan
  if K.Try("map scan", Install) and provider then return end
  local ev = CreateFrame("Frame")
  ev:RegisterEvent("ADDON_LOADED")
  ev:SetScript("OnEvent", function(self, _, name)
    if name == "Blizzard_WorldMap" then
      local ok = K.Try("map scan", Install)
      if ok and provider then self:UnregisterAllEvents() end
    end
  end)
end)

K:On("REGISTRY", function()
  if M.used > 0 and owner and owner:IsShown() then M:UpdateButton() end
end)

---------------------------------------------------------------------------
-- Settings
---------------------------------------------------------------------------
K:RegisterSettings({ id = "mapscan", trp3 = "hide", title = "Find roleplayers on the map", order = 45, build = function(card)
  card:Toggle("Share my location", "Answer when a Kinship user nearby looks for roleplayers on their world map.", "mapShare")
  card:Toggle("Not while out of character", "Stay hidden from scans while your status is OOC.", "mapHideOOC")
  card:Toggle("Not while flagged for PvP", "Stay hidden from scans while you're PvP-flagged.", "mapHidePvP")
  card:EndRow()
  local note = card:Note("", 16)
  card:OnRefresh(function()
    local why = M:Hidden()
    note:SetText(why and HIDDEN_TEXT[why]
      or "You're visible right now. Use \"Find roleplayers\" at the top right of the world map to see who's around.")
  end)
end })
