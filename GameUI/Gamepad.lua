-- Kinship RP: using Kinship's windows with a controller.
--
-- Forever's own controller interface only moves round the game's windows, so
-- while a Kinship window is open and a controller is on, Kinship borrows a few
-- of the controller's buttons:
--   D-pad              move the highlight (hold to keep moving)
--   A                  press what's highlighted (in a text box: start typing)
--   B                  stop typing, or close the window in front
--   LB / RB            previous / next tab (the journal's pages if it has none)
--   trigger + D-pad    scroll up and down (so does the right stick)
-- They go straight back to the game when the window closes, and when combat
-- starts. Two shortcuts work from the start, so nothing needs a mouse:
--   hold View + D-pad up      open or close your journal
--   hold View + D-pad down    your target's profile
-- They're only watched for, never bound, so both buttons keep their usual
-- jobs. Settings > Controller changes them or turns any of this off.

local ADDON, ns = ...
local K = ns.K
local UI = K.UI
local Pad = { bound = false, held = {} }
K.Pad = Pad

-- The controller's buttons we take, and what each does.
local KEYS = {
  PADDUP = "UP", PADDDOWN = "DOWN", PADDLEFT = "LEFT", PADDRIGHT = "RIGHT",
  PAD1 = "A", PAD2 = "B", PADLSHOULDER = "LB", PADRSHOULDER = "RB",
}
-- Scrolling: the D-pad with a trigger held (triggers are modifiers on the
-- controller), and the right stick where it sends button presses.
local SCROLL_KEYS = { PADRSTICKUP = "SUP", PADRSTICKDOWN = "SDOWN" }
local MODS = { "SHIFT-", "CTRL-", "ALT-", "CTRL-SHIFT-", "ALT-SHIFT-", "ALT-CTRL-", "ALT-CTRL-SHIFT-" }
local REPEATS = { UP = true, DOWN = true, LEFT = true, RIGHT = true, SUP = true, SDOWN = true }
local FIRST, AGAIN = 0.35, 0.08     -- held D-pad: first repeat, then every

local function S() return K.db and K.db.settings or {} end
local function InCombat() return InCombatLockdown and InCombatLockdown() end

-- A controller is turned on (Options > Controller) and plugged in.
function Pad.Connected()
  local G = C_GamePad
  if not (G and G.IsEnabled) then return false end
  local ok, on = pcall(G.IsEnabled)
  if not (ok and K.Safe(on) and on) then return false end
  if G.GetAllDeviceIDs then
    local ok2, ids = pcall(G.GetAllDeviceIDs)
    if ok2 and type(ids) == "table" then return #ids > 0 end
  end
  return true
end

function Pad.Wanted() return S().padNav ~= false and Pad.Connected() end

---------------------------------------------------------------------------
-- Finding things in the window in front
---------------------------------------------------------------------------
-- What the pad works on: a bar you've stepped into (the target bar, which
-- isn't a window), else the Kinship window in front. A window that opens
-- after you stepped in (pressing "View profile" on the bar) takes over.
Pad.overlays = {}

-- Something drawn over everything else that the pad should work on while it's
-- showing, such as the tour. It can set .padFirst (where the highlight
-- starts), .padBack (what B presses) and .padAnchor (what the button guide
-- sits under).
function Pad.Overlay(f) Pad.overlays[#Pad.overlays + 1] = f end

local function Front()
  for _, o in ipairs(Pad.overlays) do
    if o:IsVisible() then return o end
  end
  local e, win = Pad.entered, UI.FrontWindow()
  if e and not e:IsVisible() then Pad.entered, Pad.enteredOver, e = nil, nil, nil end
  if not e then return win end
  -- A window opened since you stepped in (the profile, from "View profile")
  -- goes on top; once it closes, you're back on the bar.
  if win and win ~= Pad.enteredOver then return win end
  return e
end
Pad.Front = Front

local function Walk(f, fn)
  for _, ch in ipairs({ f:GetChildren() }) do
    if ch:IsVisible() then
      fn(ch)
      Walk(ch, fn)
    end
  end
end

-- Its tabs: the bar highest up, so a page's own tabs win over smaller ones inside it.
function Pad.FrontTabs()
  local win, best = Front(), nil
  if not win then return nil end
  Walk(win, function(f)
    if type(f.tabs) == "table" and f.Step and (not best or (f:GetTop() or 0) > (best:GetTop() or 0)) then best = f end
  end)
  return best
end

-- Its main scrolling area: the biggest one with something to scroll.
function Pad.FrontScroll()
  local win, best, size = Front(), nil, 0
  if not win then return nil end
  Walk(win, function(f)
    if f:IsObjectType("ScrollFrame") and (f:GetVerticalScrollRange() or 0) > 0 then
      local s = (f:GetWidth() or 0) * (f:GetHeight() or 0)
      if s > size then best, size = f, s end
    end
  end)
  return best
end

-- Scroll as the mouse wheel would (dir 1 up, -1 down), by `px` when given.
function Pad.Scroll(sf, dir, px)
  if not sf then return end
  local wheel = not px and sf:IsMouseWheelEnabled() and sf:GetScript("OnMouseWheel")
  if wheel then
    wheel(sf, dir)
  else
    local r = sf:GetVerticalScrollRange() or 0
    sf:SetVerticalScroll(math.max(0, math.min(r, sf:GetVerticalScroll() - dir * (px or 48))))
  end
end

local function ScrollParent(f)
  local p = f:GetParent()
  while p do
    if p:IsObjectType("ScrollFrame") then return p end
    p = p:GetParent()
  end
end

---------------------------------------------------------------------------
-- What the highlight can stop on: buttons and text boxes that take clicks.
-- A frame can opt in with .padClick, or out with .padSkip.
---------------------------------------------------------------------------
local function Control(f)
  if f.padSkip then return false end
  if not (f:IsObjectType("Button") or f:IsObjectType("EditBox") or f.padClick) then return false end
  if f.IsEnabled and f:IsEnabled() == false then return false end
  if f.IsMouseEnabled and not f:IsMouseEnabled() then return false end
  local w, h = f:GetSize()
  return f:GetLeft() ~= nil and (w or 0) > 2 and (h or 0) > 2
end

local function Controls(root)
  local out = {}
  if root then Walk(root, function(f) if Control(f) then out[#out + 1] = f end end) end
  return out
end

-- Edges, in screen units.
local function Box(f)
  local s = f:GetEffectiveScale()
  return f:GetLeft() * s, f:GetRight() * s, f:GetBottom() * s, f:GetTop() * s
end

-- The distance between two spans (0 when they overlap).
local function Gap(a1, a2, b1, b2) return math.max(0, math.max(a1, b1) - math.min(a2, b2)) end

-- The control to go to from `from` in a direction. What's straight that way
-- (same row or column) comes first, then what's within 45 degrees, then the
-- rest; nearest first within each.
function Pad.Pick(from, list, dir)
  if not from:GetLeft() then return nil end
  local fl, fr, fb, ft = Box(from)
  local fx, fy = (fl + fr) / 2, (fb + ft) / 2
  local best, bestTier, bestScore
  for _, c in ipairs(list) do
    if c ~= from then
      local cl, cr, cb, ct = Box(c)
      local cx, cy = (cl + cr) / 2, (cb + ct) / 2
      local along, side, off
      if dir == "RIGHT" then along, side, off = cx - fx, Gap(fb, ft, cb, ct), cy - fy
      elseif dir == "LEFT" then along, side, off = fx - cx, Gap(fb, ft, cb, ct), cy - fy
      elseif dir == "UP" then along, side, off = cy - fy, Gap(fl, fr, cl, cr), cx - fx
      else along, side, off = fy - cy, Gap(fl, fr, cl, cr), cx - fx end
      if along > 2 then
        local tier = side < 1 and 2 or (side <= along and 1 or 0)
        local score = along + side * 3 + math.abs(off) * 0.05
        if not bestTier or tier > bestTier or (tier == bestTier and score < bestScore) then
          best, bestTier, bestScore = c, tier, score
        end
      end
    end
  end
  return best
end

-- Where the highlight starts: the control nearest the top left. In the
-- journal, on the page itself rather than the sidebar.
local function Root(win)
  local J = K.Journal
  if win and J and win == J.frame and J.current and J.content then
    local c = J.content[J.current]
    if c and c:IsVisible() and #Controls(c) > 0 then return c end
  end
  return win
end

local function First(list, root)
  local best, bestScore
  local s = root:GetEffectiveScale()
  local left, top = (root:GetLeft() or 0) * s, (root:GetTop() or 0) * s
  for _, c in ipairs(list) do
    local cl, _, _, ct = Box(c)
    local score = (cl - left) + (top - ct) * 2
    if not bestScore or score < bestScore then best, bestScore = c, score end
  end
  return best
end

---------------------------------------------------------------------------
-- The highlight: the control lights up as it does under the mouse (its own
-- OnEnter, tooltip included), with a frame round it in the theme's colour.
---------------------------------------------------------------------------
local ring
local function Ring()
  if ring then return ring end
  ring = CreateFrame("Frame", nil, UIParent)
  ring:SetFrameStrata("FULLSCREEN_DIALOG")
  ring:EnableMouse(false)
  ring.fill = ring:CreateTexture(nil, "BACKGROUND")
  ring.fill:SetAllPoints()
  ring.fill:SetColorTexture(1, 1, 1, 1)
  ring.edge = UI.Border(ring)
  ring:Hide()
  return ring
end

local function Paint()
  if not ring then return end
  local u = K:Theme().ui
  ring.fill:SetVertexColor(u[1], u[2], u[3], 0.10)
  ring.edge:SetColor(u[1], u[2], u[3], 0.95)
end

local function Leave()
  local c = Pad.focus
  if c and c:IsVisible() then
    local fn = c:GetScript("OnLeave")
    if fn then pcall(fn, c) end
  end
end

-- A control's place in what it's anchored to (a list row's place in the list).
local function Place(f)
  if f:GetNumPoints() < 1 then return nil end
  local _, rel, _, x, y = f:GetPoint(1)
  return rel, x, y
end

-- Keep the highlighted control in view inside its scrolling area. A list
-- only makes rows for what's on screen and hands them round as it scrolls,
-- so the item may now be in a different row: follow the item, not the row.
-- Returns the control to highlight.
local function IntoView(c)
  local sf = ScrollParent(c)
  if not sf then return c end
  local s, cs = sf:GetEffectiveScale(), c:GetEffectiveScale()
  local top, bottom = (sf:GetTop() or 0) * s, (sf:GetBottom() or 0) * s
  local ct, cb = (c:GetTop() or 0) * cs, (c:GetBottom() or 0) * cs
  local cur, r = sf:GetVerticalScroll(), sf:GetVerticalScrollRange() or 0
  local move = 0
  if ct > top then move = -(ct - top) - 6
  elseif cb < bottom then move = (bottom - cb) + 6 end
  if move == 0 then return c end
  local rel, x, y = Place(c)
  sf:SetVerticalScroll(math.max(0, math.min(r, cur + move / s)))
  if rel == nil or select(3, Place(c)) == y then return c end
  local parent = c:GetParent()
  for _, other in ipairs({ parent:GetChildren() }) do
    if other ~= c and other:IsShown() then
      local orel, ox, oy = Place(other)
      if orel == rel and ox == x and oy == y then return other end
    end
  end
  return c
end

-- Where the highlight was in each window or bar, to go back to it.
Pad.remember = setmetatable({}, { __mode = "k" })

function Pad.Focus(c)
  if Pad.focus ~= c then Leave() end
  if c then c = IntoView(c) end
  Pad.focus = c
  if c and Pad.win then Pad.remember[Pad.win] = c end
  local r = Ring()
  if not c then r:Hide() return end
  Paint()
  r:SetParent(c)
  r:SetFrameStrata("FULLSCREEN_DIALOG")
  r:ClearAllPoints()
  r:SetPoint("TOPLEFT", c, "TOPLEFT", -3, 3)
  r:SetPoint("BOTTOMRIGHT", c, "BOTTOMRIGHT", 3, -3)
  r:Show()
  local fn = c:GetScript("OnEnter")
  if fn then pcall(fn, c) end
end

-- After something changed in the window: keep the highlight if it's still
-- there, else start again at the top.
function Pad.Refresh()
  if not Pad.bound then return end
  local win = Front()
  if not win then return end
  local list = Controls(win)
  if Pad.focus and Pad.focus:IsVisible() and Pad.win == win then
    for _, c in ipairs(list) do if c == Pad.focus then return end end
  end
  Pad.win = win
  local last = Pad.remember[win]
  if last and last:IsVisible() then
    for _, c in ipairs(list) do if c == last then Pad.Focus(last) return end end
  end
  if win.padFirst and win.padFirst:IsVisible() then Pad.Focus(win.padFirst) return end
  local root = Root(win)
  Pad.Focus(First(root == win and list or Controls(root), root) or First(list, win))
end

---------------------------------------------------------------------------
-- The buttons
---------------------------------------------------------------------------
local function Press(c)
  if c:IsObjectType("EditBox") then c:SetFocus() return end
  if c:GetScript("OnClick") then c:Click("LeftButton") return end
  local down, up = c:GetScript("OnMouseDown"), c:GetScript("OnMouseUp")
  if down then down(c, "LeftButton") end
  if up then up(c, "LeftButton") end
end

local function Typing()
  local eb = GetCurrentKeyBoardFocus and GetCurrentKeyBoardFocus()
  local win = Front()
  if not (eb and win) then return nil end
  local p = eb
  while p do
    if p == win then return eb end
    p = p:GetParent()
  end
end

local function Sound() if SOUNDKIT then PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON) end end

function Pad.Press(name)
  local win = Front()
  if not win then return end
  if name == "A" then
    local c = Pad.focus
    if c and c:IsVisible() then
      local ok, err = pcall(Press, c)
      if not ok then K:CaughtError("controller", err) end
    end
  elseif name == "B" then
    local eb = Typing()
    if eb then eb:ClearFocus()
    elseif win.padBack and win.padBack:IsVisible() then win.padBack:Click("LeftButton")
    elseif win == Pad.entered then Pad.Leave()
    else win:Hide() end
  elseif name == "LB" or name == "RB" then
    local dir = name == "LB" and -1 or 1
    local bar = Pad.FrontTabs()
    if not (bar and bar:Step(dir)) and K.Journal.frame == win then K.Journal:Step(dir) end
  elseif name == "SUP" or name == "SDOWN" then
    local sf = (Pad.focus and Pad.focus:IsVisible() and ScrollParent(Pad.focus)) or Pad.FrontScroll()
    Pad.Scroll(sf, name == "SUP" and 1 or -1)
    return
  else
    local list = Controls(win)
    if not (Pad.focus and Pad.focus:IsVisible()) then Pad.win = nil; Pad.Refresh() return end
    local to = Pad.Pick(Pad.focus, list, name)
    if to then
      Pad.Focus(to)
      Sound()
    elseif name == "UP" or name == "DOWN" then
      -- Nothing further that way: scroll instead (a list only makes rows for
      -- what's on screen, so this brings the next ones in).
      local sf = ScrollParent(Pad.focus) or Pad.FrontScroll()
      Pad.Scroll(sf, name == "UP" and 1 or -1, math.max(24, Pad.focus:GetHeight() or 24))
    end
    return
  end
  -- Pressing may have changed the page: look again once it has.
  C_Timer.After(0, Pad.Refresh)
end

local owner = CreateFrame("Frame", "KinshipRPPadOwner", UIParent)
local function ButtonName(key) return "KinshipRPPad" .. key end
local function MakeButton(key, name)
  local b = CreateFrame("Button", ButtonName(key), UIParent)
  b:SetSize(1, 1)
  b:RegisterForClicks("AnyDown", "AnyUp")
  b:SetScript("OnClick", function(_, _, down)
    if down == false then
      if Pad.repeating == name then Pad.repeating = nil end
      return
    end
    if REPEATS[name] then Pad.repeating, Pad.repeatKey, Pad.repeatAt = name, key, GetTime() + FIRST end
    Pad.Press(name)
  end)
end
for key, name in pairs(KEYS) do MakeButton(key, name) end
for key, name in pairs(SCROLL_KEYS) do MakeButton(key, name) end
MakeButton("SUPMOD", "SUP")
MakeButton("SDOWNMOD", "SDOWN")

-- Each key and what it's bound to, so the binding and the check agree.
local function Wanted()
  local w = {}
  for key in pairs(KEYS) do
    w[key] = ButtonName(key)
    if key ~= "PADDUP" and key ~= "PADDDOWN" then
      for _, m in ipairs(MODS) do w[m .. key] = ButtonName(key) end
    end
  end
  for _, m in ipairs(MODS) do
    w[m .. "PADDUP"], w[m .. "PADDDOWN"] = ButtonName("SUPMOD"), ButtonName("SDOWNMOD")
  end
  for key in pairs(SCROLL_KEYS) do w[key] = ButtonName(key) end
  return w
end
local WANTED = Wanted()

-- The plain button a binding key ends in ("CTRL-PADDUP" -> "PADDUP").
local function Base(key) return key:match("([^%-]+)$") end

local function BindAll()
  ClearOverrideBindings(owner)
  for key, button in pairs(WANTED) do
    if not Pad.held[Base(key)] then SetOverrideBindingClick(owner, true, key, button, "LeftButton") end
  end
end

-- Every key still comes to us (the game can bind its own over ours later).
local function AllOurs()
  for key, button in pairs(WANTED) do
    if not Pad.held[Base(key)] then
      local action = GetBindingAction(key, true) or ""
      if not action:find(button, 1, true) then return false end
    end
  end
  return true
end

-- One of the game's own controller windows has the pad: leave it be.
local function GameHasPad()
  local m = GamepadMode and GamepadMode.FrameControlsManager
  local ok, other = false, nil
  if m and m.GetActiveFrame then ok, other = pcall(m.GetActiveFrame, m) end
  return ok and other ~= nil
end

local hints
function Pad.Bind()
  if InCombat() then return end
  -- A button still down (the one that opened the window) is taken once let go.
  wipe(Pad.held)
  for key in pairs(KEYS) do if IsKeyDown(key) then Pad.held[key] = true end end
  BindAll()
  Pad.bound, Pad.win, Pad.noCheck = true, nil, nil
  Pad.Refresh()
  if hints then hints:Place() end
end

-- Step into a bar that isn't a window (the target bar), and out again.
function Pad.Enter(frame)
  if not (frame and frame:IsVisible()) or InCombat() or not Pad.Wanted() then return false end
  Pad.entered, Pad.enteredOver = frame, UI.FrontWindow()
  Pad.remember[frame] = nil
  if Pad.bound then Pad.win = nil; Pad.Refresh() else Pad.Bind() end
  if hints then hints:Place() end
  return true
end

function Pad.Leave()
  if Pad.entered then Pad.remember[Pad.entered] = nil end
  Pad.entered, Pad.enteredOver = nil, nil
  Leave()
  Pad.focus, Pad.win = nil, nil
  if ring then ring:Hide() end
  if GameTooltip then GameTooltip:Hide() end
end

function Pad.Unbind()
  Pad.repeating = nil
  if Pad.bound and not InCombat() then ClearOverrideBindings(owner) end
  Pad.bound = false
  Leave()
  Pad.focus, Pad.win = nil, nil
  if ring then ring:Hide() end
  if hints then hints:Hide() end
end

---------------------------------------------------------------------------
-- A strip under the window saying what the buttons do.
---------------------------------------------------------------------------
local function Label(key, fallback)
  local t = GetBindingText and GetBindingText(key, "KEY_")
  return (t and t ~= "" and t ~= key) and t or fallback
end

local function MakeHints()
  local h = CreateFrame("Frame", nil, UIParent)
  h:SetFrameStrata("FULLSCREEN_DIALOG")
  h:SetClampedToScreen(true)
  h:SetHeight(24)
  h.bg = h:CreateTexture(nil, "BACKGROUND")
  h.bg:SetAllPoints()
  h.bg:SetColorTexture(0, 0, 0, 0.75)
  h.text = h:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  h.text:SetPoint("CENTER")
  function h:Place()
    local win = Front()
    if not (Pad.bound and win and S().padHints ~= false) then self:Hide() return end
    local u = K:Theme().ui
    local hex = ("|cff%02x%02x%02x"):format(math.floor(u[1] * 255 + 0.5), math.floor(u[2] * 255 + 0.5), math.floor(u[3] * 255 + 0.5))
    local function K2(key, fb) return hex .. Label(key, fb) .. "|r" end
    self.text:SetText(table.concat({
      K2("PAD1", "A") .. " Select", K2("PAD2", "B") .. " Back",
      K2("PADLSHOULDER", "LB") .. " / " .. K2("PADRSHOULDER", "RB") .. " Tabs",
      "Trigger + " .. K2("PADDUP", "D-pad") .. " Scroll",
    }, "     "))
    self:SetWidth(self.text:GetStringWidth() + 28)
    self:ClearAllPoints()
    self:SetPoint("TOP", win.padAnchor or win, "BOTTOM", 0, -6)
    self.win = win
    self:Show()
  end
  h:Hide()
  return h
end

---------------------------------------------------------------------------
-- Watching: a Kinship window opening or closing, the game taking the pad
-- back, held buttons, and the shortcut that opens the journal.
---------------------------------------------------------------------------
local tick = CreateFrame("Frame")
local nextLook, nextCheck, nextIntro = 0, 0, 0

-- The shortcuts: hold one button, press another. Each starts on a default
-- (false in settings when turned off) and can be changed in Settings.
local SHORTCUTS = {
  { key = "padShortcut", default = { hold = "PADBACK", press = "PADDUP" },
    does = "opens and closes your journal", run = function() K.Journal:Toggle() end },
  { key = "padProfileShortcut", default = { hold = "PADBACK", press = "PADDDOWN" },
    does = "takes you to your target's bar (or their profile)", run = function()
      local bar = rawget(_G, "KinshipRPTargetBar")
      if Pad.entered and Pad.entered == bar then Pad.Leave() return end
      if not Pad.Enter(bar) then K:ViewUnitProfile("target") end
    end },
}
Pad.SHORTCUTS = SHORTCUTS

function Pad.Shortcut(sc)
  local v = S()[sc.key]
  if v == false then return nil end
  return v or sc.default
end

-- "View + D-pad Up", in the game's own names for the buttons.
function Pad.ShortcutLabel(chord)
  if not chord then return nil end
  return Label(chord.hold, chord.hold) .. " + " .. Label(chord.press, chord.press)
end

tick:SetScript("OnUpdate", function()
  local now = GetTime()

  -- The shortcuts: both buttons down together (once each time).
  if not Pad.capturing then
    for _, sc in ipairs(SHORTCUTS) do
      local chord = Pad.Shortcut(sc)
      local down = chord and IsKeyDown(chord.hold) and IsKeyDown(chord.press) or false
      if down and not sc.down and Pad.Connected() then
        local ok, err = pcall(sc.run)
        if not ok then K:CaughtError("controller shortcut", err) end
      end
      sc.down = down
    end
  end

  -- The first time a controller is on, show how to use Kinship with it
  -- (looked for every couple of seconds until it has been seen once).
  if now >= nextIntro and Pad.ready and not S().padIntroSeen then
    nextIntro = now + 2
    if not InCombat() and Pad.Connected() then Pad.ShowIntro() end
  end

  -- A few times a second: should we have the pad?
  if now >= nextLook then
    nextLook = now + 0.2
    local want = Front() ~= nil and not InCombat() and Pad.Wanted()
    if want and not Pad.bound then Pad.Bind()
    elseif not want and Pad.bound then Pad.Unbind()
    elseif Pad.bound then
      if hints and hints.win ~= Front() then hints:Place() end
      if Pad.win ~= Front() then Pad.Refresh() end
    end
  end
  if not Pad.bound or InCombat() then return end

  -- Buttons that were down when we took the pad: theirs once let go.
  if next(Pad.held) then
    local any = false
    for key in pairs(Pad.held) do
      if IsKeyDown(key) then any = true else Pad.held[key] = nil end
    end
    if not any then BindAll() end
  end

  -- The game can bind its own over ours (letting go of a shoulder button puts
  -- its D-pad back, sometimes a moment later): take them back, unless one of
  -- its own windows has the pad.
  if not Pad.noCheck and now >= nextCheck and not next(Pad.held) then
    nextCheck = now + 0.25
    if not AllOurs() and not GameHasPad() then
      BindAll()
      -- Still not ours straight after: this client can't tell, so stop asking.
      if not AllOurs() then Pad.noCheck = true end
    end
  end

  -- A held D-pad keeps going.
  if Pad.repeating then
    if not IsKeyDown(Pad.repeatKey) and not Pad.repeatKey:find("MOD", 1, true) then
      Pad.repeating = nil
    elseif now >= Pad.repeatAt then
      Pad.repeatAt = now + AGAIN
      Pad.Press(Pad.repeating)
    end
  end
end)

-- The modifier scroll buttons have no key of their own to watch: the D-pad's.
for _, pair in ipairs({ { "SUPMOD", "PADDUP" }, { "SDOWNMOD", "PADDDOWN" } }) do
  _G[ButtonName(pair[1])]:HookScript("OnClick", function(_, _, down)
    if down ~= false then Pad.repeatKey = pair[2] end
  end)
end

owner:RegisterEvent("PLAYER_REGEN_DISABLED")
owner:RegisterEvent("GAME_PAD_DISCONNECTED")
owner:SetScript("OnEvent", function()
  -- Combat: give the buttons back while it's still allowed. The watcher takes
  -- them again once it's over, if a window is still open.
  if Pad.bound then Pad.Unbind() end
end)

-- One of the game's controller windows closing hands the pad round again:
-- take ours back if a Kinship window is still open.
K:On("LOGIN", function()
  Pad.ready = true
  hints = MakeHints()
  UI:OnTheme(function() Paint(); if hints:IsShown() then hints:Place() end end)
  if EventRegistry and EventRegistry.RegisterCallback then
    pcall(EventRegistry.RegisterCallback, EventRegistry, "Gamepad.RefreshFrameFocus", function()
      C_Timer.After(0, function()
        if Pad.bound and not InCombat() and not GameHasPad() then BindAll() end
      end)
    end, Pad)
  end
end)

---------------------------------------------------------------------------
-- Choosing a shortcut: hold one button and press another. B alone, or
-- 15 seconds, cancels.
---------------------------------------------------------------------------
local capture
function Pad.StopCapture(chord)
  if not (capture and capture:IsShown()) then return end
  capture:Hide()
  Pad.capturing = nil
  if not InCombat() and capture.EnableGamePadButton then capture:EnableGamePadButton(false) end
  local sc = capture.sc
  if chord and sc then
    for _, other in ipairs(SHORTCUTS) do
      local o = other ~= sc and Pad.Shortcut(other)
      if o and o.hold == chord.hold and o.press == chord.press then
        K:Print(("%s already %s. Pick another pair."):format(Pad.ShortcutLabel(chord), other.does))
        chord = nil
        break
      end
    end
  end
  if chord and sc then
    S()[sc.key] = chord
    sc.down = true    -- both still down: not a press yet
    K:Print(("%s now %s."):format(Pad.ShortcutLabel(chord), sc.does))
  end
  K.Journal:RefreshCurrent()
end

function Pad.Capture(sc)
  if InCombat() then K:Print("Not during combat.") return end
  if not capture then
    capture = CreateFrame("Frame", nil, UIParent)
    capture:SetSize(420, 64)
    capture:SetPoint("TOP", 0, -180)
    capture:SetFrameStrata("FULLSCREEN_DIALOG")
    capture.bg = capture:CreateTexture(nil, "BACKGROUND")
    capture.bg:SetAllPoints()
    capture.bg:SetColorTexture(0, 0, 0, 0.85)
    capture.edge = UI.Border(capture)
    capture.text = capture:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    capture.text:SetWidth(390)
    capture.text:SetText("Hold one controller button and press another, for example LB and D-pad down.\n"
      .. "Press B on its own to cancel.")
    capture.text:SetJustifyH("CENTER")
    capture.text:SetPoint("CENTER")
    capture:SetScript("OnGamePadButtonDown", function(self, button)
      if self.hold and self.hold ~= button and IsKeyDown(self.hold) then
        Pad.StopCapture({ hold = self.hold, press = button })
      else
        self.hold = button
      end
    end)
    capture:SetScript("OnGamePadButtonUp", function(self, button)
      if button == self.hold then
        if button == "PAD2" then Pad.StopCapture() else self.hold = nil end
      end
    end)
  end
  local u = K:Theme().ui
  capture.edge:SetColor(u[1], u[2], u[3], 0.9)
  capture.hold, capture.sc = nil, sc
  Pad.capturing = true
  if capture.EnableGamePadButton then capture:EnableGamePadButton(true) end
  if capture.SetPropagateGamePadButtonInput then capture:SetPropagateGamePadButtonInput(false) end
  capture:Show()
  local started = GetTime()
  capture.started = started
  C_Timer.After(15, function()
    if Pad.capturing and capture.started == started then Pad.StopCapture() end
  end)
end

---------------------------------------------------------------------------
-- The help window: shown the first time a controller is on, and from
-- Settings > Controller. It's a Kinship window, so the pad works it too.
---------------------------------------------------------------------------
local intro
local INTRO_W, INTRO_H, KEYS_W = 460, 360, 170

local function IntroRows()
  local rows = {}
  for _, sc in ipairs(SHORTCUTS) do
    local label = Pad.ShortcutLabel(Pad.Shortcut(sc))
    if label then rows[#rows + 1] = { (sc.does:gsub("^%l", string.upper)), label } end
  end
  rows[#rows + 1] = false
  rows[#rows + 1] = { "Move between buttons", Label("PADDUP", "D-pad") }
  rows[#rows + 1] = { "Press the highlighted button", Label("PAD1", "A") }
  rows[#rows + 1] = { "Go back or close", Label("PAD2", "B") }
  rows[#rows + 1] = { "Change tab", Label("PADLSHOULDER", "LB") .. " / " .. Label("PADRSHOULDER", "RB") }
  rows[#rows + 1] = { "Scroll", "Trigger + " .. Label("PADDUP", "D-pad") }
  return rows
end

function Pad.ShowIntro()
  S().padIntroSeen = true
  if not intro then
    intro = UI.Window("KinshipRPPadIntro", "Using Kinship with a controller", INTRO_W, INTRO_H)
    intro.lines = {}
    intro.foot = UI.Text(intro, "Change the shortcuts, or turn this off, in Settings > Controller. "
      .. "Tours work the same way: A for Next, B to skip.", "Small", "subtle", INTRO_W - 40)
    intro.foot:SetSpacing(2)
    intro.ok = UI.Button(intro, "Got it", 110, 26)
    intro.ok:SetPoint("BOTTOM", 0, 16)
    intro.ok:SetScript("OnClick", function() intro:Hide() end)
    intro.padFirst = intro.ok
  end
  for _, l in ipairs(intro.lines) do l[1]:Hide(); l[2]:Hide() end
  local y = -52
  for i, row in ipairs(IntroRows()) do
    if row then
      local l = intro.lines[i]
      if not l then
        l = { UI.Text(intro, "", "Body", "text", INTRO_W - KEYS_W - 50), UI.Text(intro, "", "Body", "heading", KEYS_W) }
        l[2]:SetJustifyH("RIGHT")
        intro.lines[i] = l
      end
      l[1]:SetText(row[1]); l[2]:SetText(row[2])
      l[1]:ClearAllPoints(); l[1]:SetPoint("TOPLEFT", 20, y)
      l[2]:ClearAllPoints(); l[2]:SetPoint("TOPRIGHT", -20, y)
      l[1]:Show(); l[2]:Show()
      y = y - math.max(22, l[1]:GetStringHeight() + 8)
    else
      y = y - 10
    end
  end
  intro.foot:ClearAllPoints()
  intro.foot:SetPoint("TOPLEFT", 20, y - 10)
  intro:Show()
end

---------------------------------------------------------------------------
-- Settings
---------------------------------------------------------------------------
K:RegisterSettings({ id = "controller", title = "Controller", order = 15,
  keywords = "gamepad controller handheld steam deck d-pad dpad xbox playstation buttons shortcut",
  build = function(card)
  card:Toggle("Use Kinship with a controller", "While a Kinship window is open, the D-pad moves between its buttons, "
    .. "A presses, B goes back, and LB and RB change tab.", {
    get = function() return S().padNav ~= false end,
    set = function(v) S().padNav = v and true or false end,
  })
  card:Toggle("Show the button guide", "A short line under the window saying what each button does.", {
    get = function() return S().padHints ~= false end,
    set = function(v) S().padHints = v and true or false; if hints then hints:Place() end end,
  })
  card:EndRow()
  for _, sc in ipairs(SHORTCUTS) do
    local note = card:Note("", 16)
    local choose = card:Button("Choose buttons", function() Pad.Capture(sc) end, 150)
    local other = UI.Button(card, "", 130, 26)
    other:SetPoint("LEFT", choose, "RIGHT", 8, 0)
    other:SetScript("OnClick", function()
      -- On (default or chosen): turn it off. Off: back to the default.
      if Pad.Shortcut(sc) then S()[sc.key] = false else S()[sc.key] = nil end
      K.Journal:RefreshCurrent()
    end)
    card:OnRefresh(function()
      local label = Pad.ShortcutLabel(Pad.Shortcut(sc))
      local what = sc.does:gsub("^%l", string.upper)
      note:SetText(label and (what .. " with " .. label .. ".") or (what .. ": off."))
      other:SetText(label and "Turn off" or "Use the default")
    end)
  end
  card:Button("Show the controller help", function() Pad.ShowIntro() end, 190)
  local foot = card:Note("", 16)
  card:OnRefresh(function()
    foot:SetText("Hold the first button, then press the second. Both keep their usual jobs in the game."
      .. (Pad.Connected() and "" or " Turn on your controller under Options > Controller first."))
  end)
end })
