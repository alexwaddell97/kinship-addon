-- Kinship RP: roleplay names on unit frames. Your player frame shows your
-- roleplay name, and your target and focus frames show theirs once their
-- profile has arrived, where the frame shows the character name: the
-- roleplay name in roleplay gold, the character name kept after it in grey,
-- "Aldric Vane (Leeroy)", so you can always see who to whisper or invite.
--
-- Works with EllesmereUI's unit frames (it paints names into "text zones";
-- Kinship re-labels each zone right after it's painted) and with the game's
-- own frames. Only the name inside the text changes: level, health or any
-- other piece of the same line stays as the frame drew it. Nothing is written
-- into another addon's settings or files, and switching off repaints the
-- frames with the game's names.

local ADDON, ns = ...
local K = ns.K
local UI = K.UI
local Safe = K.Safe
local N = {}
K.UnitNames = N

local S = K.Settings

-- EllesmereUI's frames by unit, and the game's own name strings by unit.
local EUI_FRAMES = {
  player = "EllesmereUIUnitFrames_Player", target = "EllesmereUIUnitFrames_Target",
  focus = "EllesmereUIUnitFrames_Focus", targettarget = "EllesmereUIUnitFrames_TargetTarget",
  focustarget = "EllesmereUIUnitFrames_FocusTarget",
}
local function StockNames()
  return {
    player = _G.PlayerName or (_G.PlayerFrame and _G.PlayerFrame.name),
    target = (_G.TargetFrame and _G.TargetFrame.name) or _G.TargetFrameTextureFrameName,
    focus = (_G.FocusFrame and _G.FocusFrame.name) or _G.FocusFrameTextureFrameName,
  }
end

---------------------------------------------------------------------------
-- Which names to swap
---------------------------------------------------------------------------
-- Plain text: no colour codes or other escapes, so the frame keeps its look.
local Plain = K.Plain

-- The roleplay name for a unit, or nil to leave the frame alone.
local function RPName(unit)
  if not UnitExists(unit) then return nil end
  local isPlayer = UnitIsPlayer(unit)
  if not Safe(isPlayer) or not isPlayer then return nil end
  local me = UnitIsUnit(unit, "player")
  if Safe(me) and me then
    local p = K:Profile()
    if strtrim(p.rpName or "") == "" then return nil end
    return Plain(K:DisplayName(p))
  end
  if S().rpUnitNamesOthers == false then return nil end
  local name = GetUnitName(unit, true)
  if not Safe(name) or not name or K:IsIgnored(name) then return nil end
  local reg = K:ProfileOf(name)
  local p = reg and reg.profile
  local rp = p and Plain(UI.Clean(p.rpName or "")) or ""
  if rp == "" then return nil end
  local prefix = Plain(UI.Clean(p.prefix or ""))
  return prefix ~= "" and (prefix .. " " .. rp) or rp
end

-- The forms the game's name can take on a frame: with surname first (Forever
-- characters have one), then the first name alone.
local function GameNames(unit)
  local n, surname = UnitName(unit)
  if not Safe(n) or type(n) ~= "string" or n == "" then return nil end
  local out = {}
  if Safe(surname) and type(surname) == "string" and surname ~= "" then out[#out + 1] = n .. " " .. surname end
  out[#out + 1] = n
  return out
end

-- Put the roleplay name in front of the first plain occurrence of any game
-- name in text, keeping that name after it. Returns the new text, the piece
-- put in and the game name it went around.
local function Swap(text, unit)
  if not Safe(text) or type(text) ~= "string" or text == "" then return nil end
  local rp = RPName(unit)
  if not rp then return nil end
  -- Already swapped (the frame asked twice): the first name would match
  -- inside the roleplay name itself ("Vax" in "Lord Vax Orius").
  if text:find(rp, 1, true) then return nil end
  for _, g in ipairs(GameNames(unit) or {}) do
    local i, j = text:find(g, 1, true)
    if i then
      local seg = K.BothNames(rp, g)
      return text:sub(1, i - 1) .. seg .. text:sub(j + 1), seg, g
    end
  end
end

---------------------------------------------------------------------------
-- Hooking name strings
---------------------------------------------------------------------------
local hooked = setmetatable({}, { __mode = "k" })

local function RelabelNow(fs)
  if fs.kinshipBusy then return end
  local unit = hooked[fs]
  if not unit or S().rpUnitNames == false then return end
  local ok, text = pcall(fs.GetText, fs)
  if not ok then return end
  local new, seg, game = Swap(text, unit)
  if new and new ~= text then
    fs.kinshipSeg, fs.kinshipGame = seg, game
    fs.kinshipBusy = true
    fs:SetText(new)
    fs.kinshipBusy = false
  end
end

-- The hooks run inside the frame addon's own repaint, which carries on to the
-- portrait, health and the rest afterwards: nothing here may ever raise an
-- error into it.
local function Relabel(fs)
  local ok = K.Try("unit names", RelabelNow, fs)
  if not ok then fs.kinshipBusy = false end
end

local function Hook(fs, unit)
  if not fs or hooked[fs] or not fs.SetText then return end
  hooked[fs] = unit
  hooksecurefunc(fs, "SetText", function(self) Relabel(self) end)
  if fs.SetFormattedText then hooksecurefunc(fs, "SetFormattedText", function(self) Relabel(self) end) end
  Relabel(fs)
end

-- Find every name string there is now (EllesmereUI rebuilds zones when its
-- settings change, so this runs again from time to time).
function N:Scan()
  for unit, global in pairs(EUI_FRAMES) do
    local f = _G[global]
    local zones = f and f._euiTextZones
    if type(zones) == "table" then
      for _, z in ipairs(zones) do
        if type(z) == "table" and z.fs then Hook(z.fs, unit) end
      end
    end
  end
  for unit, fs in pairs(StockNames()) do Hook(fs, unit) end
end

-- Repaint the frames: theirs redraw the game's names, and our hooks swap them.
function N:Refresh()
  self:Scan()
  local repaint = rawget(_G, "_EUF_RefreshUnitNames")
  if type(repaint) == "function" then pcall(repaint) end
  if S().rpUnitNames ~= false then
    for fs in pairs(hooked) do Relabel(fs) end
  elseif type(repaint) ~= "function" then
    -- The game's own frames: put their names back by hand.
    for fs in pairs(hooked) do
      local seg, game = fs.kinshipSeg, fs.kinshipGame
      if seg and game and not fs.kinshipBusy then
        local ok, text = pcall(fs.GetText, fs)
        if ok and type(text) == "string" then
          local i, j = text:find(seg, 1, true)
          if i then fs:SetText(text:sub(1, i - 1) .. game .. text:sub(j + 1)) end
        end
        fs.kinshipSeg, fs.kinshipGame = nil, nil
      end
    end
  end
end

local pending
local function Queue()
  if pending then return end
  pending = true
  C_Timer.After(0.1, function() pending = nil; K.Try("unit names", N.Refresh, N) end)
end

---------------------------------------------------------------------------
-- Start-up and events
---------------------------------------------------------------------------
local ev = CreateFrame("Frame")
ev:RegisterEvent("PLAYER_ENTERING_WORLD")
ev:RegisterEvent("PLAYER_TARGET_CHANGED")
ev:RegisterEvent("PLAYER_FOCUS_CHANGED")
ev:RegisterEvent("PORTRAITS_UPDATED")
-- One full repaint of EllesmereUI's frames once everything has loaded, so a
-- portrait painted blank during the loading screen gets its art.
local function RepaintFrames()
  local all = EllesmereUI and EllesmereUI._UFEngineForceAll
  if type(all) == "function" then pcall(all, "ForceUpdate") end
end

-- EllesmereUI draws a 2D portrait once per unit and only draws it again when
-- the unit changes. Art that wasn't ready at that moment (just after loading)
-- stays blank, and when the game says the art is ready it only redraws frames
-- that are showing, so a frame hidden until you have a target keeps the blank.
-- Redraw the 2D portraits when one of its frames appears and whenever portrait
-- art arrives, hidden frames included. (3D models and class icons look after
-- themselves, and redrawing a model is costly, so they're left alone.)
local function RedrawPortrait(f)
  local p = type(f) == "table" and rawget(f, "Portrait")
  if type(p) ~= "table" or type(p.ForceUpdate) ~= "function" or not p.IsObjectType then return end
  if p:IsObjectType("PlayerModel") or rawget(p, "isClass") then return end
  pcall(p.ForceUpdate, p)
end

local function RedrawPortraits()
  for _, global in pairs(EUI_FRAMES) do RedrawPortrait(_G[global]) end
end

local shownHooked = setmetatable({}, { __mode = "k" })
local function HookShows()
  for _, global in pairs(EUI_FRAMES) do
    local f = _G[global]
    if f and f.HookScript and not shownHooked[f] then
      shownHooked[f] = true
      f:HookScript("OnShow", function(self) C_Timer.After(0, function() RedrawPortrait(self) end) end)
    end
  end
end

ev:SetScript("OnEvent", function(_, event)
  if event == "PLAYER_ENTERING_WORLD" then
    -- Frames and their text zones are built a moment after login.
    for _, delay in ipairs({ 0.5, 2, 5 }) do C_Timer.After(delay, Queue) end
    C_Timer.After(2.5, RepaintFrames)
    C_Timer.After(2.5, HookShows)
  elseif event == "PORTRAITS_UPDATED" then
    C_Timer.After(0, RedrawPortraits)
  else
    Queue()
  end
end)

K:On("LOGIN", function()
  local s = K.db.settings
  if s.rpUnitNames == nil then s.rpUnitNames = true end
  if s.rpUnitNamesOthers == nil then s.rpUnitNamesOthers = true end
end)
K:On("PROFILE", Queue)
K:On("IGNORE", Queue)
K:On("REGISTRY", function(key)
  for _, unit in ipairs({ "target", "focus" }) do
    if UnitExists(unit) then
      local n = GetUnitName(unit, true)
      if Safe(n) and n and K.NameKey(n) == key then Queue() return end
    end
  end
end)

K:RegisterSettings({ id = "unitNames", title = "Unit frames", order = 41, build = function(card)
  card:Toggle("Roleplay names on unit frames", "Your player frame shows your roleplay name in roleplay gold, with your character's name after it.", {
    get = function() return S().rpUnitNames ~= false end,
    set = function(v) K.db.settings.rpUnitNames = v; N:Refresh() end,
  })
  card:Toggle("Include target and focus", "Your target and focus frames show their roleplay name, and their character's name, once their profile has arrived.", {
    get = function() return S().rpUnitNamesOthers ~= false end,
    set = function(v) K.db.settings.rpUnitNamesOthers = v; N:Refresh() end,
  })
  card:Note("Works with EllesmereUI's unit frames and the game's own. The character name always stays, so whispers and invites are never a guess; the rest of the line stays as your frames draw it.")
end })
