-- Kinship RP: the look and the shared widgets.
-- Flat, pixel-bordered chrome, comfortable reading type and gentle motion,
-- in Kinship's own colours: deep teal chrome, gold trim, and cream cards with
-- dark-brown text.

local ADDON, ns = ...
local K = ns.K
local UI = {}
K.UI = UI

local WHITE = "Interface\\Buttons\\WHITE8X8"

K.COLORS = {
  teal       = { 0.07, 0.28, 0.28 },
  tealBright = { 0.18, 0.52, 0.50 },
  gold       = { 0.94, 0.82, 0.54 },
  softGold   = { 0.80, 0.71, 0.51 },
  bronze     = { 0.55, 0.39, 0.18 },
}

---------------------------------------------------------------------------
-- Themes
---------------------------------------------------------------------------
local THEMES = {
  classic = {
    light = true, font = "classic", shadow = 0.85,
    chrome     = { 0.035, 0.078, 0.078, 0.98 },  -- window body
    chromeEdge = { 0.94, 0.82, 0.54, 0.30 },
    bar        = { 0, 0, 0, 0.26 },              -- title bar, sidebar
    deskBg     = { 0, 0, 0, 0.16 },              -- the work area under the page header
    line       = { 0.94, 0.82, 0.54, 0.14 },     -- dividers on the chrome
    ui         = { 0.94, 0.82, 0.54 },           -- chrome accent (gold)
    navText    = { 0.96, 0.92, 0.82 },
    stageTop   = { 0.08, 0.19, 0.19 }, stageBottom = { 0.015, 0.045, 0.045 },
    -- Cream cards and the dark-brown text written on them
    panel      = { 0.925, 0.890, 0.810, 1 },
    panelEdge  = { 0.30, 0.20, 0.08, 0.30 },
    text       = { 0.17, 0.15, 0.11 },
    subtle     = { 0.36, 0.29, 0.19 },
    heading    = { 0.27, 0.15, 0.04 },
    accent     = { 0.05, 0.36, 0.36 },           -- teal, on cream
    section    = { 0.26, 0.17, 0.06 },
    sectionBg  = { 0.30, 0.20, 0.08, 0.10 },
    field      = { 1, 1, 1, 0.55 },
    fieldEdge  = { 0.30, 0.20, 0.08, 0.28 },
    hover      = { 0.05, 0.36, 0.36, 0.07 },
    stripe     = { 0.30, 0.20, 0.08, 0.045 },
    select     = { 0.05, 0.36, 0.36, 0.16 },
    -- Text and fields sitting straight on the teal
    deskHeading = { 0.96, 0.84, 0.56 },
    deskText    = { 0.93, 0.90, 0.84 },
    deskSubtle  = { 0.78, 0.82, 0.79 },
    deskAccent  = { 0.62, 0.90, 0.84 },
    deskField     = { 0, 0, 0, 0.30 },
    deskFieldEdge = { 0.94, 0.82, 0.54, 0.22 },
    deskSectionBg = { 0, 0, 0, 0.25 },
    dim           = { 0.01, 0.03, 0.03, 0.72 },  -- behind pop-over cards
    -- Buttons: teal with gold lettering and a gold hairline
    btn          = { 0.06, 0.20, 0.20, 1 },    btnHover     = { 0.09, 0.28, 0.28, 1 },
    btnEdge      = { 0.94, 0.82, 0.54, 0.30 }, btnEdgeHover = { 0.94, 0.82, 0.54, 0.70 },
    btnText      = { 0.95, 0.89, 0.73 },       btnTextHover = { 1, 0.96, 0.86 },
    thumb = { 0.30, 0.20, 0.08, 0.40 }, track = { 0.30, 0.20, 0.08, 0.08 },
  },
  -- The game's own windows: a bronze metal rim, red buttons, gold headings
  -- and dark inset cards. skin = "blizzard" tells widgets to wear the
  -- client's frame art (copied from its templates, see the Skin section).
  blizzard = {
    light = false, font = "classic", shadow = 1, skin = "blizzard",
    chrome     = { 0.055, 0.052, 0.050, 0.97 },
    chromeEdge = { 0.62, 0.48, 0.27, 0.60 },     -- bronze
    bar        = { 0, 0, 0, 0.28 },
    deskBg     = { 0, 0, 0, 0.14 },
    line       = { 0.62, 0.48, 0.27, 0.32 },
    ui         = { 1, 0.82, 0 },
    navText    = { 0.95, 0.93, 0.88 },
    stageTop   = { 0.14, 0.13, 0.12 }, stageBottom = { 0.025, 0.024, 0.022 },
    -- Dark inset cards with light text
    panel      = { 0.025, 0.024, 0.022, 0.82 },
    panelEdge  = { 0.62, 0.48, 0.27, 0.42 },
    text       = { 0.93, 0.92, 0.89 },
    subtle     = { 0.68, 0.66, 0.62 },
    heading    = { 1, 0.82, 0 },
    accent     = { 1, 0.70, 0.22 },             -- amber, apart from the gold headings
    section    = { 1, 0.82, 0 },
    sectionBg  = { 1, 0.82, 0, 0.08 },
    field      = { 0, 0, 0, 0.50 },
    fieldEdge  = { 0.62, 0.48, 0.27, 0.42 },
    hover      = { 1, 0.82, 0, 0.07 },
    stripe     = { 1, 1, 1, 0.03 },
    select     = { 1, 0.82, 0, 0.14 },
    deskHeading = { 1, 0.82, 0 },
    deskText    = { 0.93, 0.92, 0.89 },
    deskSubtle  = { 0.70, 0.68, 0.64 },
    deskAccent  = { 1, 0.78, 0.38 },
    deskField     = { 0, 0, 0, 0.45 },
    deskFieldEdge = { 0.62, 0.48, 0.27, 0.40 },
    deskSectionBg = { 0, 0, 0, 0.32 },
    dim           = { 0, 0, 0, 0.70 },
    -- Flat stand-ins for the red buttons, used where the client's art is missing
    btn          = { 0.36, 0.05, 0.03, 1 },    btnHover     = { 0.48, 0.08, 0.05, 1 },
    btnEdge      = { 0.70, 0.55, 0.30, 0.65 }, btnEdgeHover = { 0.95, 0.80, 0.45, 0.90 },
    btnText      = { 1, 0.82, 0 },             btnTextHover = { 1, 1, 1 },
    segBg        = { 0, 0, 0, 0.45 },          -- segmented choices sit dark, not red
    thumb = { 0.62, 0.48, 0.27, 0.55 }, track = { 1, 1, 1, 0.05 },
  },
}

UI.THEMES = THEMES   -- read-only, for previews of each look

-- The chosen look (Settings > Look); Kinship's own until saved data has loaded.
-- Every widget reads its colours through K:Theme().
function K:Theme()
  local s = K.db and K.db.settings
  return s and THEMES[s.uiTheme] or THEMES.classic
end
function UI.Skinned() return K:Theme().skin == "blizzard" end

-- Fixed dark-on-cream colours (the "ink" style), for text that should not follow the look.
UI.INK = {
  ink        = { 0.19, 0.17, 0.13 },
  inkSubtle  = { 0.45, 0.36, 0.24 },
  inkHeading = { 0.30, 0.16, 0.04 },
  inkAccent  = { 0.05, 0.33, 0.33 },
}
local INK_FIELD, INK_EDGE = { 1, 1, 1, 0.38 }, { 0.40, 0.28, 0.12, 0.50 }
local INK_THUMB, INK_TRACK = { 0.40, 0.28, 0.12, 0.50 }, { 0.40, 0.28, 0.12, 0.12 }

-- Semantic colours (status, consent, stance, outcomes) are bright: right on
-- the dark chrome, unreadable as text on Classic's cream cards. OnCard inks
-- them down to a readable shade when the cards are light.
function UI.OnCard(c)
  if not K:Theme().light then return c end
  return { c[1] * 0.50, c[2] * 0.50, c[3] * 0.50, c[4] }
end
function UI.CardHex(c) return UI.Hex(UI.OnCard(c)) end

-- Colour code for inline |c text. Alpha is folded in, as if over a dark panel.
function UI.Hex(c)
  local a = c[4] or 1
  local function byte(v) return math.floor(v * a * 255 + 0.5) end
  return ("%02x%02x%02x"):format(byte(c[1]), byte(c[2]), byte(c[3]))
end

local function Mix(a, b, p)
  local aa, ba = a[4] or 1, b[4] or 1
  return a[1] + (b[1] - a[1]) * p, a[2] + (b[2] - a[2]) * p, a[3] + (b[3] - a[3]) * p, aa + (ba - aa) * p
end
UI.Mix = Mix

---------------------------------------------------------------------------
-- Fonts. Named font objects, re-pointed when the look changes, so every
-- string follows without being touched. "Shadow" variants are for text on
-- the window itself; text on cards never has a shadow.
---------------------------------------------------------------------------
local FONT_SIZES = { Huge = 20, Title = 16, Header = 14, Body = 13, Small = 12, Label = 11, Read = 14 }
local FONT_ALIAS = {
  GameFontNormalHuge = "Huge", GameFontNormalLarge = "Title", GameFontNormal = "Header",
  GameFontHighlight = "Body", GameFontNormalSmall = "Label", GameFontHighlightSmall = "Small", QuestFont = "Read",
}
UI.FONTS = {}
for name in pairs(FONT_SIZES) do
  UI.FONTS[name] = CreateFont("KinshipRPFont" .. name)
  UI.FONTS[name .. "Shadow"] = CreateFont("KinshipRPFont" .. name .. "Shadow")
end

function UI:ApplyFonts(t)
  for name, size in pairs(FONT_SIZES) do
    for _, suffix in ipairs({ "", "Shadow" }) do
      local f = self.FONTS[name .. suffix]
      f:SetFont(STANDARD_TEXT_FONT, size, "")
      f:SetTextColor(1, 1, 1)
      if suffix == "Shadow" then
        f:SetShadowColor(0, 0, 0, t.shadow); f:SetShadowOffset(1, -1)
      else
        f:SetShadowOffset(0, 0)
      end
    end
  end
end

function UI.Font(font, shadow)
  local key = FONT_ALIAS[font] or font
  if UI.FONTS[key] then return UI.FONTS[key .. (shadow and "Shadow" or "")] end
  return font
end

---------------------------------------------------------------------------
-- Theme registry
---------------------------------------------------------------------------
UI.themed = {}
local function Run(fn, t)
  local ok, err = pcall(fn, t)
  if not ok then K:CaughtError("theme", err) end
end
function UI:OnTheme(fn) table.insert(self.themed, fn); Run(fn, K:Theme()) end
function UI:ApplyTheme()
  local t = K:Theme()
  self:ApplyFonts(t)
  for _, fn in ipairs(self.themed) do Run(fn, t) end
end
UI:ApplyFonts(K:Theme())

K:On("LOGIN", function() UI:ApplyTheme() end)

---------------------------------------------------------------------------
-- Skin: the client's own frame art for the Blizzard look. Nothing is
-- shipped: a hidden button is made from each of the game's templates once,
-- and the art it wears (atlas, or file and texcoords) is copied onto ours,
-- so WoW Forever's own art shows wherever it differs from retail. Each piece
-- is made once and only shown or hidden when the look changes; anything the
-- client lacks falls back to the flat look.
---------------------------------------------------------------------------
local Skin = {}
UI.Skin = Skin

-- What a texture is drawing right now, or nil.
local function Snap(tex)
  if not tex then return nil end
  local atlas = tex.GetAtlas and tex:GetAtlas()
  if atlas and atlas ~= "" then return { atlas = atlas, blend = tex:GetBlendMode() } end
  local file = tex:GetTexture()
  if not file then return nil end
  return { file = file, coords = { tex:GetTexCoord() }, blend = tex:GetBlendMode() }
end

-- Draw a snapped look on one of our textures (hidden when there is none).
function Skin.Paint(tex, s)
  if not s then tex:Hide() return end
  if s.atlas then
    tex:SetAtlas(s.atlas)
  else
    tex:SetTexture(s.file)
    tex:SetTexCoord(unpack(s.coords))
  end
  tex:SetBlendMode(s.blend or "BLEND")
  tex:Show()
end

local refs = {}
local function Ref(template, w, h)
  if refs[template] == nil then
    refs[template] = false
    local ok, b = pcall(CreateFrame, "Button", nil, UIParent, template)
    if ok and b then
      b:Hide()
      b:SetSize(w, h)
      refs[template] = b
    end
  end
  return refs[template] or nil
end

-- A state script on the reference, run safely (it swaps its own art).
local function Fire(b, script, ...)
  local fn = b:GetScript(script)
  if fn then pcall(fn, b, ...) end
end

-- The red panel button: { normal, pushed, disabled } each { L, M, R }, plus
-- the highlight and the end pieces' width. False when the client has none.
local buttonArt
function Skin.ButtonArt()
  if buttonArt == nil then
    buttonArt = false
    local b = Ref("UIPanelButtonTemplate", 110, 22)
    if b and b.Left and b.Middle and b.Right then
      local function take() return { Snap(b.Left), Snap(b.Middle), Snap(b.Right) } end
      local art = { capW = b.Left:GetWidth() }
      art.normal = take()
      Fire(b, "OnMouseDown", "LeftButton"); art.pushed = take(); Fire(b, "OnMouseUp", "LeftButton")
      b:Disable(); Fire(b, "OnDisable"); art.disabled = take()
      b:Enable(); Fire(b, "OnEnable")
      art.highlight = Snap(b:GetHighlightTexture())
      if not (art.capW and art.capW > 1) then art.capW = 12 end
      if art.normal[1] and art.normal[2] and art.normal[3] then buttonArt = art end
    end
  end
  return buttonArt or nil
end

-- The red X: { normal, pushed, disabled, highlight }, or false.
local closeArt
function Skin.CloseArt()
  if closeArt == nil then
    closeArt = false
    local b = Ref("UIPanelCloseButton", 24, 24)
    if b then
      local art = {
        normal = Snap(b:GetNormalTexture()), pushed = Snap(b:GetPushedTexture()),
        disabled = Snap(b:GetDisabledTexture()), highlight = Snap(b:GetHighlightTexture()),
      }
      if art.normal then closeArt = art end
    end
  end
  return closeArt or nil
end

-- The metal rim of the game's windows, on `f` (nil when the client can't
-- draw it). It's a frame above f's content, so the rim overlaps its edges;
-- the top carries a title band about 24 units deep.
-- One of the game's nine-slice layouts on a frame above `f`'s content, or
-- nil when the client lacks the layout or its art.
local function NineSlice(f, layout, lift)
  local NS = rawget(_G, "NineSliceUtil")
  if not (NS and NS.ApplyLayoutByName) then return nil end
  local ok, ns = pcall(CreateFrame, "Frame", nil, f, "NineSlicePanelTemplate")
  if not ok or not ns then return nil end
  ns:SetAllPoints()
  local piece = pcall(NS.ApplyLayoutByName, ns, layout) and (ns.TopLeftCorner or ns.TopEdge)
  if not (piece and ((piece.GetAtlas and piece:GetAtlas()) or piece:GetTexture())) then
    ns:Hide()
    return nil
  end
  ns:EnableMouse(false)
  ns:SetFrameLevel(f:GetFrameLevel() + lift)
  return ns
end

function Skin.Rim(f) return NineSlice(f, "ButtonFrameTemplateNoPortrait", 40) end

-- The thin inner border of the game's inset panes (the character sheet's
-- stats, for one), just above `f`'s content. Nil when the client has none.
function Skin.Inset(f) return NineSlice(f, "InsetFrameTemplate", 5) end

Skin.ROCK = "Interface\\FrameGeneral\\UI-Background-Rock"

-- The red button's art on a button of ours: three pieces and a highlight,
-- made once. Returns paint(state): state "normal", "pushed" or "disabled"
-- draws it, nil hides it; paint returns whether the art is showing.
function Skin.RedButton(b)
  local pieces = {}
  for i = 1, 3 do
    pieces[i] = b:CreateTexture(nil, "BACKGROUND", nil, 1)
    pieces[i]:Hide()
  end
  pieces[1]:SetPoint("TOPLEFT"); pieces[1]:SetPoint("BOTTOMLEFT")
  pieces[3]:SetPoint("TOPRIGHT"); pieces[3]:SetPoint("BOTTOMRIGHT")
  pieces[2]:SetPoint("TOPLEFT", pieces[1], "TOPRIGHT")
  pieces[2]:SetPoint("BOTTOMRIGHT", pieces[3], "BOTTOMLEFT")
  local hl = b:CreateTexture(nil, "HIGHLIGHT")
  hl:SetAllPoints()
  hl:Hide()
  return function(state)
    local art = state and Skin.ButtonArt()
    if not art then
      for i = 1, 3 do pieces[i]:Hide() end
      hl:Hide()
      return false
    end
    local set = art[state] or art.normal
    for i = 1, 3 do Skin.Paint(pieces[i], set[i] or art.normal[i]) end
    pieces[1]:SetWidth(art.capW); pieces[3]:SetWidth(art.capW)
    Skin.Paint(hl, art.highlight)
    return true
  end
end

-- The slim bronze box of the game's HUD (the action bars' and micro menu's
-- frame: a dark body inside a bronze line), cut from the client's own
-- "UI-HUD-ActionBar-Frame" art into nine pieces drawn on `parent` itself,
-- its corners `corner` units a side. Returns { SetShown = fn(on) }, or nil
-- when the client has no such art (the caller keeps its flat look).
-- The art is 55 units a side. Its corners (the chamfer and where the line
-- runs straight again) end 12 units in; drawn at their own size (corner 12)
-- the 2-unit line stays whole. Shrinking them thins it below a pixel, and
-- parts of the frame fade out as if cut off.
local HUD_ATLAS, HUD_CUT = "UI-HUD-ActionBar-Frame", 12 / 55
local hudInfo
local function HudInfo()
  if hudInfo == nil then
    hudInfo = false
    local info = C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(HUD_ATLAS)
    if info and info.file and info.leftTexCoord then hudInfo = info end
  end
  return hudInfo or nil
end
function Skin.Hud(parent, corner, sub)
  local info = HudInfo()
  if not info then return nil end
  corner = corner or 12
  local L, R, T, B = info.leftTexCoord, info.rightTexCoord, info.topTexCoord, info.bottomTexCoord
  local us = { L, L + (R - L) * HUD_CUT, R - (R - L) * HUD_CUT, R }
  local vs = { T, T + (B - T) * HUD_CUT, B - (B - T) * HUD_CUT, B }
  local p = {}
  for row = 1, 3 do
    for col = 1, 3 do
      local t = parent:CreateTexture(nil, "BACKGROUND", nil, sub or 2)
      if not pcall(t.SetTexture, t, info.file) then return nil end
      t:SetTexCoord(us[col], us[col + 1], vs[row], vs[row + 1])
      t:Hide()
      p[(row - 1) * 3 + col] = t
    end
  end
  -- 1 2 3 / 4 5 6 / 7 8 9
  for _, i in ipairs({ 1, 3, 7, 9 }) do p[i]:SetSize(corner, corner) end
  p[1]:SetPoint("TOPLEFT"); p[3]:SetPoint("TOPRIGHT"); p[7]:SetPoint("BOTTOMLEFT"); p[9]:SetPoint("BOTTOMRIGHT")
  p[2]:SetPoint("TOPLEFT", p[1], "TOPRIGHT"); p[2]:SetPoint("BOTTOMRIGHT", p[3], "BOTTOMLEFT")
  p[8]:SetPoint("TOPLEFT", p[7], "TOPRIGHT"); p[8]:SetPoint("BOTTOMRIGHT", p[9], "BOTTOMLEFT")
  p[4]:SetPoint("TOPLEFT", p[1], "BOTTOMLEFT"); p[4]:SetPoint("BOTTOMRIGHT", p[7], "TOPRIGHT")
  p[6]:SetPoint("TOPLEFT", p[3], "BOTTOMLEFT"); p[6]:SetPoint("BOTTOMRIGHT", p[9], "TOPRIGHT")
  p[5]:SetPoint("TOPLEFT", p[1], "BOTTOMRIGHT"); p[5]:SetPoint("BOTTOMRIGHT", p[9], "TOPLEFT")
  local box = { pieces = p }
  function box:SetShown(on) for i = 1, 9 do p[i]:SetShown(on and true or false) end end
  return box
end

---------------------------------------------------------------------------
-- Pixel-perfect lines and borders (four 1px strips, re-snapped on scale change)
---------------------------------------------------------------------------
local function PixelSize()
  local _, ph = GetPhysicalScreenSize()
  local es = UIParent:GetEffectiveScale()
  if not ph or ph <= 0 or not es or es <= 0 then return 1 end
  return 768 / ph / es
end

local function NoSnap(t)
  if t.SetSnapToPixelGrid then t:SetSnapToPixelGrid(false); t:SetTexelSnappingBias(0) end
end

local borders, lines = {}, {}

local function LayoutBorder(b)
  local e = PixelSize()
  b.T:SetHeight(e); b.B:SetHeight(e); b.L:SetWidth(e); b.R:SetWidth(e)
  b.L:ClearAllPoints(); b.L:SetPoint("TOPLEFT", 0, -e); b.L:SetPoint("BOTTOMLEFT", 0, e)
  b.R:ClearAllPoints(); b.R:SetPoint("TOPRIGHT", 0, -e); b.R:SetPoint("BOTTOMRIGHT", 0, e)
end

local function SizeLine(l) if l.vertical then l:SetWidth(PixelSize()) else l:SetHeight(PixelSize()) end end

function UI.Border(frame, color)
  local b = {}
  for _, k in ipairs({ "T", "B", "L", "R" }) do
    local t = frame:CreateTexture(nil, "BORDER", nil, 7)
    t:SetTexture(WHITE)
    NoSnap(t)
    b[k] = t
  end
  b.T:SetPoint("TOPLEFT"); b.T:SetPoint("TOPRIGHT")
  b.B:SetPoint("BOTTOMLEFT"); b.B:SetPoint("BOTTOMRIGHT")
  function b:SetColor(r, g, bl, a) for _, k in ipairs({ "T", "B", "L", "R" }) do self[k]:SetVertexColor(r, g, bl, a or 1) end end
  function b:SetShown(v) for _, k in ipairs({ "T", "B", "L", "R" }) do self[k]:SetShown(v) end end
  LayoutBorder(b)
  if color then b:SetColor(unpack(color)) end
  borders[#borders + 1] = b
  return b
end

function UI.Line(parent, vertical, layer)
  local l = parent:CreateTexture(nil, layer or "BORDER")
  l:SetTexture(WHITE)
  NoSnap(l)
  l.vertical = vertical
  SizeLine(l)
  lines[#lines + 1] = l
  return l
end

local scaleWatch = CreateFrame("Frame")
scaleWatch:RegisterEvent("UI_SCALE_CHANGED")
scaleWatch:RegisterEvent("DISPLAY_SIZE_CHANGED")
scaleWatch:RegisterEvent("PLAYER_ENTERING_WORLD")
scaleWatch:SetScript("OnEvent", function()
  C_Timer.After(0, function()
    for _, b in ipairs(borders) do LayoutBorder(b) end
    for _, l in ipairs(lines) do SizeLine(l) end
  end)
end)

---------------------------------------------------------------------------
-- Motion. One driver frame runs every tween: progress p moves toward its
-- target at 1/dur per second and apply() receives the eased value.
---------------------------------------------------------------------------
local tweens, progress = {}, setmetatable({}, { __mode = "k" })
local driver = CreateFrame("Frame")
driver:Hide()
driver:SetScript("OnUpdate", function(self, elapsed)
  for key, tw in pairs(tweens) do
    local step = elapsed / tw.dur
    if tw.p < tw.target then tw.p = math.min(tw.target, tw.p + step) else tw.p = math.max(tw.target, tw.p - step) end
    progress[key] = tw.p
    K.Try("animation", tw.apply, tw.ease and tw.ease(tw.p) or tw.p)
    if tw.p == tw.target then tweens[key] = nil end
  end
  if not next(tweens) then self:Hide() end
end)

UI.Ease = {
  outQuart = function(p) return 1 - (1 - p) ^ 4 end,
  outSine  = function(p) return math.sin(p * math.pi / 2) end,
}

function UI.Tween(key, target, dur, apply, ease)
  tweens[key] = { p = progress[key] or 0, target = target, dur = dur, apply = apply, ease = ease }
  driver:Show()
end

function UI.Progress(key) return progress[key] or 0 end

-- Fade a frame in from nothing (window opens, page changes).
function UI.FadeIn(frame, dur)
  progress[frame] = 0
  frame:SetAlpha(0)
  UI.Tween(frame, 1, dur or 0.2, function(p) frame:SetAlpha(p) end)
end

---------------------------------------------------------------------------
-- Text
---------------------------------------------------------------------------
-- role: a theme colour ("text", "subtle", "heading", "accent", "section",
-- "deskHeading", ...), an ink colour ("ink", "inkSubtle", ...) or "fixed"
-- (white; the caller colours it). Desk and fixed text get a soft shadow.
function UI.Text(parent, text, font, role, width)
  role = role or "text"
  local shadow = role == "fixed" or role:find("^desk") ~= nil
  local fs = parent:CreateFontString(nil, "OVERLAY")
  fs:SetFontObject(UI.Font(font or "Body", shadow))
  fs:SetJustifyH("LEFT")
  fs:SetText(text or "")
  if width then fs:SetWidth(width) end
  if UI.INK[role] then
    fs:SetTextColor(unpack(UI.INK[role]))
  elseif role == "fixed" or role == "plain" then  -- plain: like fixed, without the shadow
    fs:SetTextColor(1, 1, 1)
  else
    UI:OnTheme(function(t) fs:SetTextColor(unpack(t[role] or t.text)) end)
  end
  return fs
end

-- Small section label on a soft pill (DialogueUI's "Rewards" headers).
function UI.Section(parent, text, desk)
  local fs = UI.Text(parent, text, "Label", desk and "deskHeading" or "section")
  local bg = parent:CreateTexture(nil, "BORDER")
  bg:SetPoint("TOPLEFT", fs, "TOPLEFT", -7, 4)
  bg:SetPoint("BOTTOMRIGHT", fs, "BOTTOMRIGHT", 7, -4)
  UI:OnTheme(function(t) bg:SetColorTexture(unpack(desk and t.deskSectionBg or t.sectionBg)) end)
  fs.bg = bg
  return fs
end

-- A 1px divider. ink = drawn on painted parchment.
function UI.Divider(parent, width, ink)
  local d = UI.Line(parent, false, "ARTWORK")
  d:SetWidth(width)
  if ink then d:SetVertexColor(0.40, 0.28, 0.12, 0.35)
  else UI:OnTheme(function(t) d:SetVertexColor(unpack(t.panelEdge)) end) end
  return d
end

function UI.Tooltip(widget, title, body)
  widget:HookScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:SetText(title, 1, 0.82, 0)
    if body then GameTooltip:AddLine(body, 1, 1, 1, true) end
    GameTooltip:Show()
  end)
  widget:HookScript("OnLeave", function() GameTooltip:Hide() end)
end

-- A small (i) that explains something when you hover it. It sits just to
-- the right of `beside` (usually a label) unless you place it yourself.
-- role is the theme colour for the dot ("subtle" unless given).
function UI.Info(parent, beside, title, body, role)
  local b = CreateFrame("Button", nil, parent)
  b:SetSize(13, 13)
  if beside then b:SetPoint("LEFT", beside, "RIGHT", 4, 0) end
  local dot = UI.Circle(b, 13)
  dot:SetPoint("CENTER")
  local i = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  i:SetPoint("CENTER", 0.5, 0)
  i:SetText("i")
  i:SetTextColor(1, 1, 1)
  if UI.INK[role] then dot:SetVertexColor(unpack(UI.INK[role]))
  else UI:OnTheme(function(t) dot:SetVertexColor(unpack(t[role] or t.subtle)) end) end
  dot:SetAlpha(0.7)
  b:SetScript("OnEnter", function() dot:SetAlpha(1) end)
  b:SetScript("OnLeave", function() dot:SetAlpha(0.7) end)
  UI.Tooltip(b, title, body)
  return b
end

---------------------------------------------------------------------------
-- Buttons
---------------------------------------------------------------------------
function UI.Button(parent, text, w, h)
  local b = CreateFrame("Button", nil, parent)
  b:SetSize(w or 110, h or 24)
  b.bg = b:CreateTexture(nil, "BACKGROUND")
  b.bg:SetAllPoints()
  b.bg:SetTexture(WHITE)
  b.edge = UI.Border(b)
  b.label = b:CreateFontString(nil, "OVERLAY")
  b.label:SetFontObject(UI.FONTS.Small)
  b.label:SetPoint("LEFT", 6, 0)
  b.label:SetPoint("RIGHT", -6, 0)
  b.label:SetWordWrap(false)
  b:SetFontString(b.label)
  b:SetPushedTextOffset(0, -1)
  b:SetText(text or "")

  -- The Blizzard look's red button art, made once.
  local red = Skin.RedButton(b)

  local function paint(p)
    local t = K:Theme()
    local state = t.skin == "blizzard" and (not b:IsEnabled() and "disabled" or (b.down and "pushed") or "normal") or nil
    local art = red(state)
    b.bg:SetShown(not art); b.edge:SetShown(not art)
    if art then
      local c = b:IsEnabled() and (p > 0.5 and { 1, 1, 1 } or { 1, 0.82, 0 }) or { 0.5, 0.5, 0.5 }
      b.label:SetTextColor(c[1], c[2], c[3], 1)
      return
    end
    b.bg:SetVertexColor(Mix(t.btn, t.btnHover, p))
    b.edge:SetColor(Mix(t.btnEdge, t.btnEdgeHover, p))
    local r, g, bl, a = Mix(t.btnText, t.btnTextHover, p)
    b.label:SetTextColor(r, g, bl, b:IsEnabled() and a or a * 0.4)
  end
  function b:Paint() paint(UI.Progress(self)) end
  b:HookScript("OnEnter", function(self) if self:IsEnabled() then UI.Tween(self, 1, 0.12, paint) end end)
  b:HookScript("OnLeave", function(self) self.down = nil; UI.Tween(self, 0, 0.12, paint) end)
  b:HookScript("OnMouseDown", function(self) if self:IsEnabled() then self.down = true; self:Paint() end end)
  b:HookScript("OnMouseUp", function(self) self.down = nil; self:Paint() end)
  b:SetScript("OnEnable", function(self) self:Paint() end)
  b:SetScript("OnDisable", function(self) self.down = nil; UI.Tween(self, 0, 0.01, paint) end)
  UI:OnTheme(function() b:Paint() end)
  return b
end

-- A drawn "x". onPanel = sits on a card, so it uses the card's text colour.
function UI.CloseButton(parent, onPanel, size)
  size = size or 24
  local b = CreateFrame("Button", nil, parent)
  b:SetSize(size, size)
  b.bg = b:CreateTexture(nil, "BACKGROUND")
  b.bg:SetAllPoints()
  b.bg:SetTexture(WHITE)
  b.cross = {}
  for i, angle in ipairs({ 45, -45 }) do
    local l = b:CreateTexture(nil, "ARTWORK")
    l:SetTexture(WHITE)
    l:SetSize(size * 0.5, math.max(1.2, size / 16))
    l:SetPoint("CENTER")
    l:SetRotation(math.rad(angle))
    b.cross[i] = l
  end
  -- The Blizzard look's red X, made once.
  b.art = b:CreateTexture(nil, "ARTWORK", nil, 1)
  b.art:SetAllPoints()
  b.art:Hide()
  b.artHL = b:CreateTexture(nil, "HIGHLIGHT")
  b.artHL:SetAllPoints()
  b.artHL:Hide()
  local function paint(p)
    local art = UI.Skinned() and Skin.CloseArt()
    b.bg:SetShown(not art)
    for _, l in ipairs(b.cross) do l:SetShown(not art) end
    if art then
      Skin.Paint(b.art, not b:IsEnabled() and art.disabled or (b.down and art.pushed) or art.normal)
      Skin.Paint(b.artHL, art.highlight)
      return
    end
    b.art:Hide(); b.artHL:Hide()
    local c = onPanel and K:Theme().text or K:Theme().navText
    b.bg:SetVertexColor(c[1], c[2], c[3], 0.10 * p)
    for _, l in ipairs(b.cross) do l:SetVertexColor(c[1], c[2], c[3], 0.55 + 0.45 * p) end
  end
  b:SetScript("OnEnter", function(self) UI.Tween(self, 1, 0.1, paint) end)
  b:SetScript("OnLeave", function(self) self.down = nil; UI.Tween(self, 0, 0.1, paint) end)
  b:SetScript("OnMouseDown", function(self)
    for _, l in ipairs(b.cross) do l:SetPoint("CENTER", 0, -1) end
    self.down = true; paint(UI.Progress(self))
  end)
  b:SetScript("OnMouseUp", function(self)
    for _, l in ipairs(b.cross) do l:SetPoint("CENTER", 0, 0) end
    self.down = nil; paint(UI.Progress(self))
  end)
  b:SetScript("OnClick", function() parent:Hide() end)
  UI:OnTheme(function() paint(UI.Progress(b)) end)
  return b
end

-- A row of joined buttons where one is selected (segmented control).
function UI.Segments(parent, items, width, onSelect)
  width = width or 84
  local h = 24
  local holder = CreateFrame("Frame", nil, parent)
  holder.bg = holder:CreateTexture(nil, "BACKGROUND")
  holder.bg:SetAllPoints()
  holder.bg:SetTexture(WHITE)
  holder.edge = UI.Border(holder)
  holder.buttons = {}
  for i, item in ipairs(items) do
    local b = CreateFrame("Button", nil, holder)
    b:SetSize(width, h)
    b:SetPoint("LEFT", (i - 1) * width, 0)
    b.key = item.key
    b.fill = b:CreateTexture(nil, "BACKGROUND", nil, 1)
    b.fill:SetAllPoints()
    b.fill:SetTexture(WHITE)
    b.bar = b:CreateTexture(nil, "ARTWORK")
    b.bar:SetTexture(WHITE)
    b.bar:SetHeight(2)
    b.bar:SetPoint("BOTTOMLEFT", 1, 1)
    b.bar:SetPoint("BOTTOMRIGHT", -1, 1)
    b.text = b:CreateFontString(nil, "OVERLAY")
    b.text:SetFontObject(UI.FONTS.Small)
    b.text:SetPoint("LEFT", 4, 0)
    b.text:SetPoint("RIGHT", -4, 0)
    b.text:SetWordWrap(false)
    b.text:SetText(item.label)
    if i > 1 then
      b.div = UI.Line(b, true)
      b.div:SetPoint("TOPLEFT", 0, -4)
      b.div:SetPoint("BOTTOMLEFT", 0, 4)
    end
    b:SetScript("OnEnter", function(self) self.hover = true; holder:Paint() end)
    b:SetScript("OnLeave", function(self) self.hover = false; holder:Paint() end)
    b:SetScript("OnClick", function()
      if SOUNDKIT then PlaySound(SOUNDKIT.IG_CHARACTER_INFO_TAB) end
      holder:Select(item.key)
      onSelect(item.key)
    end)
    holder.buttons[i] = b
  end
  holder:SetSize(#items * width, h)

  function holder:Paint()
    local t = K:Theme()
    self.bg:SetVertexColor(unpack(t.segBg or t.btn))
    self.edge:SetColor(unpack(t.btnEdge))
    for i, b in ipairs(self.buttons) do
      local sel = b.key == self.selected
      local u = items[i].color or t.ui   -- an item can bring its own colour (e.g. Yes / Ask / No)
      b.fill:SetVertexColor(u[1], u[2], u[3], sel and (items[i].color and 0.28 or 0.16) or (b.hover and 0.07 or 0))
      b.bar:SetVertexColor(u[1], u[2], u[3], sel and 1 or 0)
      b.text:SetTextColor(unpack((sel or b.hover) and t.btnTextHover or t.btnText))
      if b.div then b.div:SetVertexColor(unpack(t.btnEdge)) end
    end
  end
  function holder:Select(key) self.selected = key; self:Paint() end
  -- Size each segment to its own label (but at least `min` wide) instead of
  -- all to one width, so a long label ("Out of Character") isn't cut short.
  function holder:Fit(min)
    local x = 0
    for _, b in ipairs(self.buttons) do
      local tw = b.text.GetUnboundedStringWidth and b.text:GetUnboundedStringWidth() or b.text:GetStringWidth()
      local bw = math.max(min or 0, math.ceil(tw or 0) + 12)
      b:SetWidth(bw)
      b:ClearAllPoints()
      b:SetPoint("LEFT", x, 0)
      x = x + bw
    end
    self:SetSize(x, h)
  end
  -- Exactly `total` wide, each segment as wide as its words plus an even
  -- share of what's left. If the words don't fit, the smaller label font is
  -- tried, and failing that the segments split it evenly (and trim).
  function holder:FitTo(total)
    local n = #self.buttons
    local function measure()
      local tw, sum = {}, 0
      for i, b in ipairs(self.buttons) do
        tw[i] = math.ceil((b.text.GetUnboundedStringWidth and b.text:GetUnboundedStringWidth() or b.text:GetStringWidth()) or 0)
        sum = sum + tw[i]
      end
      return tw, sum
    end
    local tw, sum = measure()
    if sum + 10 * n > total then
      for _, b in ipairs(self.buttons) do b.text:SetFontObject(UI.FONTS.Label) end
      tw, sum = measure()
    end
    local share = (total - sum) / n
    local x = 0
    for i, b in ipairs(self.buttons) do
      local bw = share >= 8 and (tw[i] + share) or (total / n)
      if i == n then bw = total - x end
      b:SetWidth(bw)
      b:ClearAllPoints()
      b:SetPoint("LEFT", x, 0)
      x = x + bw
    end
    self:SetSize(total, h)
  end
  UI:OnTheme(function() holder:Paint() end)
  return holder
end

-- Text tabs with an accent underline (EllesmereUI's tab bar).
-- desk = drawn straight on the window rather than on a card.
function UI.TabBar(parent, names, onSelect, desk)
  local bar = CreateFrame("Frame", nil, parent)
  bar:SetHeight(26)
  bar.tabs = {}
  for i, label in ipairs(names) do
    local b = CreateFrame("Button", nil, bar)
    b.text = b:CreateFontString(nil, "OVERLAY")
    b.text:SetFontObject(desk and UI.FONTS.HeaderShadow or UI.FONTS.Header)
    b.text:SetPoint("CENTER", 0, 1)
    b.text:SetText(label)
    b.line = b:CreateTexture(nil, "ARTWORK")
    b.line:SetTexture(WHITE)
    b.line:SetHeight(2)
    b.line:SetPoint("BOTTOM")
    b:SetScript("OnEnter", function(self) self.hover = true; bar:Paint() end)
    b:SetScript("OnLeave", function(self) self.hover = false; bar:Paint() end)
    b:SetScript("OnClick", function()
      if SOUNDKIT then PlaySound(SOUNDKIT.IG_CHARACTER_INFO_TAB) end
      bar:Select(i)
      onSelect(i)
    end)
    bar.tabs[i] = b
  end
  function bar:Paint()
    local t, x = K:Theme(), 0
    -- The gap between tabs closes up when they'd run wider than maxWidth.
    local gap, sum, n = 24, 0, 0
    -- bar.order (optional): the order the tabs show in, by index
    local order = self.order
    if not order then
      order = {}
      for i = 1, #self.tabs do order[i] = i end
    end
    for _, i in ipairs(order) do
      local b = self.tabs[i]
      if b and not b.off then sum = sum + math.ceil(b.text:GetStringWidth()); n = n + 1 end
    end
    if self.maxWidth and n > 1 and sum + gap * (n - 1) > self.maxWidth then
      gap = math.max(10, math.floor((self.maxWidth - sum) / (n - 1)))
    end
    for _, i in ipairs(order) do
      local b = self.tabs[i]
      if b and not b.off then
        local w = math.ceil(b.text:GetStringWidth())
        b:SetSize(w + math.min(20, gap - 4), 26)
        b:ClearAllPoints()
        b:SetPoint("LEFT", x, 0)
        x = x + w + gap
        b.line:SetWidth(w + 6)
        local sel = i == self.selected
        local on, mid, off, a = t.heading, t.text, t.subtle, t.accent
        if desk then on, mid, off, a = t.deskHeading, t.deskText, t.deskSubtle, t.ui end
        b.text:SetTextColor(unpack(sel and on or (b.hover and mid or off)))
        b.text:SetAlpha((b.faint and not sel and not b.hover) and 0.45 or 1)
        b.line:SetVertexColor(a[1], a[2], a[3], sel and 1 or (b.hover and 0.3 or 0))
      end
    end
    self:SetWidth(math.max(1, x))
  end
  function bar:Select(i) self.selected = i; self:Paint() end
  -- Dim a tab with nothing in it (it can still be opened).
  function bar:SetTabFaint(i, faint)
    local b = self.tabs[i]
    if not b then return end
    b.faint = faint or nil
    self:Paint()
  end
  -- Hide a tab (a switched-off feature); the others close up.
  function bar:SetTabShown(i, shown)
    local b = self.tabs[i]
    if not b then return end
    b.off = not shown or nil
    b:SetShown(shown and true or false)
    self:Paint()
  end
  UI:OnTheme(function() bar:Paint() end)
  return bar
end

-- Sidebar navigation row: accent bar, fading glow, and a small nudge to the
-- right on hover.
function UI.NavButton(parent, label, icon, w, onClick)
  local b = CreateFrame("Button", nil, parent)
  b:SetSize(w, 36)
  b.glow = b:CreateTexture(nil, "BACKGROUND")
  b.glow:SetAllPoints()
  b.glow:SetColorTexture(1, 1, 1, 1)
  b.bar = b:CreateTexture(nil, "ARTWORK")
  b.bar:SetTexture(WHITE)
  b.bar:SetWidth(3)
  b.bar:SetPoint("TOPLEFT")
  b.bar:SetPoint("BOTTOMLEFT")
  b.content = CreateFrame("Frame", nil, b)
  b.content:SetSize(w - 10, 36)
  b.content:SetPoint("LEFT")
  b.icon = b.content:CreateTexture(nil, "ARTWORK")
  b.icon:SetSize(20, 20)
  b.icon:SetPoint("LEFT", 18, 0)
  -- icon: a texture path, "portrait" (your character's face), or { path, round = true }
  if icon == "portrait" then
    UI.Round(b.icon)
    function b:RefreshIcon() SetPortraitTexture(self.icon, "player") end
    b:RefreshIcon()
  elseif type(icon) == "table" then
    b.icon:SetTexture(icon[1])
    b.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    if icon.round then UI.Round(b.icon) end
  else
    b.icon:SetTexture(icon)
  end
  b.text = b.content:CreateFontString(nil, "OVERLAY")
  b.text:SetFontObject(UI.FONTS.Header)
  b.text:SetPoint("LEFT", b.icon, "RIGHT", 10, 0)
  b.text:SetText(label)

  function b:Paint()
    local t, u = K:Theme(), K:Theme().ui
    local a = self.selected and 0.20 or (self.hover and 0.06 or 0)
    if self.glow.SetGradient and CreateColor then
      self.glow:SetGradient("HORIZONTAL", CreateColor(u[1], u[2], u[3], a), CreateColor(u[1], u[2], u[3], 0))
    else
      self.glow:SetVertexColor(u[1], u[2], u[3], a * 0.5)
    end
    self.bar:SetVertexColor(u[1], u[2], u[3], self.selected and 1 or (self.hover and 0.3 or 0))
    local alpha = self.selected and 1 or (self.hover and 0.86 or 0.6)
    local c = t.navText
    self.text:SetTextColor(c[1], c[2], c[3], alpha)
    self.icon:SetAlpha(alpha)
  end
  local function slide(p) b.content:SetPoint("LEFT", 5 * p, 0) end
  b:SetScript("OnEnter", function(self) self.hover = true; self:Paint(); UI.Tween(self, 1, 0.25, slide, UI.Ease.outQuart) end)
  b:SetScript("OnLeave", function(self) self.hover = false; self:Paint(); UI.Tween(self, 0, 0.25, slide, UI.Ease.outQuart) end)
  b:SetScript("OnClick", function()
    if SOUNDKIT then PlaySound(SOUNDKIT.IG_CHARACTER_INFO_TAB) end
    onClick()
  end)
  function b:SetSelected(v) self.selected = v; self:Paint() end
  UI:OnTheme(function() b:Paint() end)
  return b
end

---------------------------------------------------------------------------
-- Windows: flat chrome, 1px edge, drawn close button, quick fade on open.
-- opts.bare skips the title bar (the journal draws its own sidebar header).
---------------------------------------------------------------------------
function UI.Window(name, title, w, h, opts)
  opts = opts or {}
  local f = CreateFrame("Frame", name, UIParent)
  f:SetSize(w, h)
  f:SetPoint("CENTER")
  f:SetFrameStrata("HIGH")
  f:SetToplevel(true)
  f:SetClampedToScreen(true)
  f:SetMovable(true)
  f:EnableMouse(true)
  f:RegisterForDrag("LeftButton")
  f:SetScript("OnDragStart", f.StartMoving)
  f:SetScript("OnDragStop", f.StopMovingOrSizing)

  f.bg = f:CreateTexture(nil, "BACKGROUND", nil, -8)
  f.bg:SetAllPoints()
  f.bg:SetTexture(WHITE)
  f.edge = UI.Border(f)

  -- The Blizzard look: the game's rock backdrop under the content and its
  -- metal rim over the edges, both made once and shown with that look.
  f.rock = f:CreateTexture(nil, "BACKGROUND", nil, -7)
  f.rock:SetAllPoints()
  f.rock:SetTexture(Skin.ROCK, "REPEAT", "REPEAT")
  f.rock:SetHorizTile(true); f.rock:SetVertTile(true)
  f.rock:Hide()
  f.rim = Skin.Rim(f)
  -- The title and close button ride above the rim.
  f.top = CreateFrame("Frame", nil, f)
  f.top:SetAllPoints()
  f.top:EnableMouse(false)
  if f.rim then f.top:SetFrameLevel(f.rim:GetFrameLevel() + 1) end

  f.close = UI.CloseButton(f)
  f.close:SetFrameLevel(f.top:GetFrameLevel() + 1)
  f.close:SetPoint("TOPRIGHT", -6, -5)

  -- A bare window still gets its title in the rim's band.
  if opts.bare then
    f.TitleText = UI.Text(f.top, title, "Header", "deskHeading")
    f.TitleText:Hide()
  end

  if not opts.bare then
    f.titleBar = f:CreateTexture(nil, "BACKGROUND", nil, -6)
    f.titleBar:SetPoint("TOPLEFT")
    f.titleBar:SetPoint("TOPRIGHT")
    f.titleBar:SetHeight(34)
    f.titleBar:SetTexture(WHITE)
    f.titleLine = UI.Line(f)
    f.titleLine:SetPoint("TOPLEFT", 0, -34)
    f.titleLine:SetPoint("TOPRIGHT", 0, -34)
    f.icon = f:CreateTexture(nil, "ARTWORK")
    f.icon:SetSize(18, 18)
    f.icon:SetPoint("TOPLEFT", 12, -8)
    f.icon:SetTexture(K.ICON)
    f.TitleText = UI.Text(f.top, title, "Header", "deskHeading")
    f.TitleText:SetPoint("LEFT", f.icon, "RIGHT", 8, 0)
  end
  function f:SetTitle(text) if self.TitleText then self.TitleText:SetText(text) end end

  UI:OnTheme(function(t)
    local rim = t.skin == "blizzard" and f.rim and true or false
    f.bg:SetVertexColor(unpack(t.chrome))
    f.edge:SetColor(unpack(t.chromeEdge))
    f.edge:SetShown(not rim)
    if f.rim then f.rim:SetShown(rim) end
    f.rock:SetShown(rim)
    f.rock:SetVertexColor(0.5, 0.5, 0.5, 0.85)
    f.close:ClearAllPoints()
    -- On the rim, the X sits in its corner over the title band.
    if rim then f.close:SetPoint("TOPRIGHT", -3, -2) else f.close:SetPoint("TOPRIGHT", -6, -5) end
    if f.titleBar then
      f.titleBar:SetShown(not rim); f.titleLine:SetShown(not rim); f.icon:SetShown(not rim)
      f.titleBar:SetVertexColor(unpack(t.bar))
      f.titleLine:SetVertexColor(unpack(t.line))
    end
    local tt = f.TitleText
    if tt then
      tt:ClearAllPoints()
      if rim then
        -- Centred in the rim's band, as the game's own windows have it.
        tt:SetPoint("TOPLEFT", f, "TOPLEFT", 40, -6)
        tt:SetPoint("TOPRIGHT", f, "TOPRIGHT", -40, -6)
        tt:SetJustifyH("CENTER")
        tt:SetWordWrap(false)
        tt:Show()
      elseif f.icon then
        tt:SetWidth(0)
        tt:SetJustifyH("LEFT")
        tt:SetPoint("LEFT", f.icon, "RIGHT", 8, 0)
      else
        tt:Hide()   -- a bare window draws its own header
      end
    end
  end)

  tinsert(UISpecialFrames, name)
  f:SetScript("OnShow", function(self)
    if SOUNDKIT then PlaySound(SOUNDKIT.IG_CHARACTER_INFO_OPEN) end
    UI.FadeIn(self, 0.18)
  end)
  f:SetScript("OnHide", function() if SOUNDKIT then PlaySound(SOUNDKIT.IG_CHARACTER_INFO_CLOSE) end end)
  f:Hide()
  return f
end

---------------------------------------------------------------------------
-- Content pieces
---------------------------------------------------------------------------
-- A small round button in a window's top-right corner (help, Ko-fi): x, y
-- from the corner under Kinship's look; in the metal rim's title band, left
-- of the X, under the Blizzard look.
function UI.SeatCornerButton(f, b, x, y)
  UI:OnTheme(function(t)
    local rim = t.skin == "blizzard" and f.rim
    b:ClearAllPoints()
    if rim then
      b:SetPoint("TOPRIGHT", x + 6, -1)
      b:SetFrameLevel(f.top:GetFrameLevel() + 1)
    else
      b:SetPoint("TOPRIGHT", x, y)
      b:SetFrameLevel(f:GetFrameLevel() + 10)
    end
  end)
end

-- A content card: cream, with a fine brown edge.
function UI.Panel(parent)
  local p = CreateFrame("Frame", nil, parent)
  p.bg = p:CreateTexture(nil, "BACKGROUND")
  p.bg:SetAllPoints()
  p.edge = UI.Border(p)
  UI:OnTheme(function(t)
    p.bg:SetColorTexture(unpack(t.panel))
    p.edge:SetColor(unpack(t.panelEdge))
  end)
  return p
end

-- The flat work area under a window's header.
function UI.Desk(parent)
  local d = parent:CreateTexture(nil, "BACKGROUND", nil, -2)
  UI:OnTheme(function(t)
    if t.deskBg then d:SetColorTexture(unpack(t.deskBg)); d:Show() else d:Hide() end
  end)
  return d
end

-- A filled circle (masked square), e.g. a crest ring or a status dot.
local CIRCLE_MASK = "Interface\\CHARACTERFRAME\\TempPortraitAlphaMask"
function UI.Circle(parent, size, layer, sub)
  local c = parent:CreateTexture(nil, layer or "ARTWORK", nil, sub)
  c:SetTexture(WHITE)
  c:SetSize(size, size)
  UI.Round(c)
  return c
end

-- A card that pops over its parent on a dimmed backdrop. Clicking the
-- backdrop or the close button calls onClose.
function UI.Modal(parent, w, h, onClose)
  local ov = CreateFrame("Frame", nil, parent)
  ov:SetAllPoints()
  ov:SetFrameLevel(parent:GetFrameLevel() + 30)
  ov:EnableMouse(true)
  ov.dim = ov:CreateTexture(nil, "BACKGROUND")
  ov.dim:SetAllPoints()
  UI:OnTheme(function(t) ov.dim:SetColorTexture(unpack(t.dim)) end)
  ov:SetScript("OnMouseDown", function() onClose() end)
  local card = UI.Panel(ov)
  card:SetSize(w, h)
  card:SetPoint("CENTER")
  card:EnableMouse(true)
  card.accent = card:CreateTexture(nil, "ARTWORK")
  card.accent:SetTexture(WHITE)
  card.accent:SetHeight(3)
  card.accent:SetPoint("TOPLEFT"); card.accent:SetPoint("TOPRIGHT")
  UI:OnTheme(function(t) card.accent:SetVertexColor(unpack(t.accent)) end)
  card.close = UI.CloseButton(card, true)
  card.close:SetPoint("TOPRIGHT", -8, -10)
  card.close:SetScript("OnClick", function() onClose() end)
  ov.card = card
  ov:SetScript("OnShow", function(self) UI.FadeIn(self, 0.15) end)
  ov:Hide()
  return ov
end

---------------------------------------------------------------------------
-- Thin scrollbar with smooth wheel scrolling. Sits just
-- to the right of the scroll frame and hides when nothing overflows.
---------------------------------------------------------------------------
function UI.ScrollBar(sf, ink, step)
  local bar = CreateFrame("Frame", nil, sf:GetParent())
  bar:SetPoint("TOPLEFT", sf, "TOPRIGHT", 3, 0)
  bar:SetPoint("BOTTOMLEFT", sf, "BOTTOMRIGHT", 3, 0)
  bar:SetWidth(8)
  bar.track = bar:CreateTexture(nil, "BACKGROUND")
  bar.track:SetTexture(WHITE)
  bar.track:SetPoint("TOP")
  bar.track:SetPoint("BOTTOM")
  bar.track:SetWidth(3)
  local thumb = CreateFrame("Button", nil, bar)
  thumb:SetWidth(8)
  thumb.tex = thumb:CreateTexture(nil, "ARTWORK")
  thumb.tex:SetTexture(WHITE)
  thumb.tex:SetPoint("TOP")
  thumb.tex:SetPoint("BOTTOM")
  thumb.tex:SetWidth(3)
  bar.thumb = thumb

  local function Range()
    local child = sf:GetScrollChild()
    return math.max(0, (child and child:GetHeight() or 0) - sf:GetHeight())
  end
  local function Update()
    local r, h = Range(), sf:GetHeight()
    if r < 1 or h <= 0 then bar:Hide() return end
    bar:Show()
    local th = math.max(24, h * h / (h + r))
    thumb:SetHeight(th)
    thumb:ClearAllPoints()
    thumb:SetPoint("TOP", bar, "TOP", 0, -(h - th) * math.min(1, sf:GetVerticalScroll() / r))
  end
  bar.Update = Update

  local anim = CreateFrame("Frame", nil, sf)
  local target
  local function Smooth(self, elapsed)
    local cur = sf:GetVerticalScroll()
    local diff = target - cur
    if math.abs(diff) < 0.5 then
      sf:SetVerticalScroll(target); target = nil; self:SetScript("OnUpdate", nil)
    else
      sf:SetVerticalScroll(cur + diff * math.min(1, 12 * elapsed))
    end
  end
  -- A list inside a scrolling page hands the wheel on once it can't go any
  -- further (or has nothing to scroll), so the page keeps scrolling past it.
  local function PassUp(delta)
    local p = sf:GetParent()
    while p do
      if p:IsObjectType("ScrollFrame") and p:IsMouseWheelEnabled() then
        local fn = p:GetScript("OnMouseWheel")
        if fn then fn(p, delta) return end
      end
      p = p:GetParent()
    end
  end
  sf:EnableMouseWheel(true)
  sf:SetScript("OnMouseWheel", function(_, delta)
    local r = Range()
    local at = target or sf:GetVerticalScroll()
    if r <= 0 or (delta > 0 and at <= 0) or (delta < 0 and at >= r - 0.5) then PassUp(delta) return end
    target = math.max(0, math.min(r, at - delta * (step or 48)))
    anim:SetScript("OnUpdate", Smooth)
  end)

  thumb:SetScript("OnMouseDown", function(self)
    local _, y = GetCursorPosition()
    self.dragY, self.from = y / self:GetEffectiveScale(), sf:GetVerticalScroll()
    target = nil; anim:SetScript("OnUpdate", nil)
    self:SetScript("OnUpdate", function()
      local _, cy = GetCursorPosition()
      cy = cy / self:GetEffectiveScale()
      local free, r = sf:GetHeight() - self:GetHeight(), Range()
      if free > 0 then sf:SetVerticalScroll(math.max(0, math.min(r, self.from + (self.dragY - cy) / free * r))) end
    end)
  end)
  thumb:SetScript("OnMouseUp", function(self) self:SetScript("OnUpdate", nil) end)

  -- ink: dark on parchment; "desk": straight on the window, in the gold of its chrome.
  local function paint(p)
    local tc, kc
    if ink == "desk" then
      local u = K:Theme().ui
      tc, kc = { u[1], u[2], u[3], 0.12 }, { u[1], u[2], u[3], 0.55 }
    elseif ink then tc, kc = INK_TRACK, INK_THUMB else local t = K:Theme(); tc, kc = t.track, t.thumb end
    bar.track:SetVertexColor(unpack(tc))
    local r, g, b, a = unpack(kc)
    thumb.tex:SetVertexColor(r, g, b, math.min(1, a + 0.3 * p))
    thumb.tex:SetWidth(3 + 2 * p)
  end
  thumb:SetScript("OnEnter", function(self) UI.Tween(self, 1, 0.12, paint) end)
  thumb:SetScript("OnLeave", function(self) UI.Tween(self, 0, 0.12, paint) end)
  if ink and ink ~= "desk" then paint(0) else UI:OnTheme(function() paint(UI.Progress(thumb)) end) end

  sf:HookScript("OnVerticalScroll", Update)
  sf:HookScript("OnScrollRangeChanged", Update)
  sf:HookScript("OnSizeChanged", Update)
  local child = sf:GetScrollChild()
  if child then child:HookScript("OnSizeChanged", Update) end
  bar:Hide()
  return bar
end

---------------------------------------------------------------------------
-- Inputs
---------------------------------------------------------------------------
-- style: nil (on a card), "desk" (straight on the window), "ink" (fixed dark-on-cream)
local function FieldColors(style, t)
  if style == "ink" then return INK_FIELD, INK_EDGE, UI.INK.ink, UI.INK.inkAccent end
  if style == "desk" then return t.deskField, t.deskFieldEdge, t.deskText, t.ui end
  return t.field, t.fieldEdge, t.text, t.accent
end

-- Flat background + 1px edge that lights up in the accent colour on focus.
local function StyleInput(box, edit, style)
  box.bg = box:CreateTexture(nil, "BACKGROUND")
  box.bg:SetAllPoints()
  box.bg:SetTexture(WHITE)
  box.edge = UI.Border(box)
  local function paint()
    local bg, edge, text, focus = FieldColors(style, K:Theme())
    box.bg:SetVertexColor(unpack(bg))
    if edit:HasFocus() then box.edge:SetColor(focus[1], focus[2], focus[3], 0.85)
    else box.edge:SetColor(unpack(edge)) end
    edit:SetTextColor(unpack(text))
  end
  edit:HookScript("OnEditFocusGained", paint)
  edit:HookScript("OnEditFocusLost", paint)
  if style == "ink" then paint() else UI:OnTheme(paint) end
end

function UI.Edit(parent, w, h, style, maxLetters)
  local eb = CreateFrame("EditBox", nil, parent)
  eb:SetSize(w, h or 24)
  eb:SetAutoFocus(false)
  eb:SetFontObject(UI.FONTS.Body)
  eb:SetTextInsets(8, 8, 0, 0)
  eb:SetMaxLetters(maxLetters or 60)
  eb:SetScript("OnEscapePressed", eb.ClearFocus)
  eb:SetScript("OnEnterPressed", eb.ClearFocus)
  StyleInput(eb, eb, style)
  return eb
end

-- Labelled single-line field. onChange(text) fires on user edits.
function UI.Field(parent, label, width, maxLetters, onChange, style)
  local holder = CreateFrame("Frame", nil, parent)
  holder:SetSize(width, 40)
  local role = (style == "desk" and "deskSubtle") or (style == "ink" and "inkSubtle") or "subtle"
  holder.label = UI.Text(holder, label, "Label", role)
  holder.label:SetPoint("TOPLEFT", 1, 0)
  local eb = UI.Edit(holder, width, 23, style, maxLetters)
  eb:SetPoint("TOPLEFT", 0, -14)
  eb:SetScript("OnTextChanged", function(self, user) if user and onChange then onChange(self:GetText()) end end)
  holder.edit = eb
  -- A label too long for the field (with room for its (i)) is cut short with
  -- "..." rather than running into the next field. Re-fitted when fonts change.
  holder.label:SetWordWrap(false)
  local function fit()
    local l = holder.label
    l:SetWidth(0)
    local room = width - 2 - (holder.info and 18 or 0)
    local w = l.GetUnboundedStringWidth and l:GetUnboundedStringWidth() or l:GetStringWidth()
    if w and w > room then l:SetWidth(room) end
  end
  fit()
  UI:OnTheme(fit)
  -- holder:Info(title, body) puts a small (i) after the label.
  function holder:Info(title, body) self.info = UI.Info(self, self.label, title, body, role); fit(); return self end
  return holder
end

-- Multi-line text area with scrolling. style as for UI.Edit (true = "ink").
function UI.TextArea(parent, w, h, maxLetters, onChange, style)
  if style == true then style = "ink" end
  local box = CreateFrame("Frame", nil, parent)
  box:SetSize(w, h)
  local sf = CreateFrame("ScrollFrame", nil, box)
  sf:SetPoint("TOPLEFT", 9, -7)
  sf:SetPoint("BOTTOMRIGHT", -16, 7)
  local eb = CreateFrame("EditBox", nil, sf)
  eb:SetMultiLine(true)
  eb:SetAutoFocus(false)
  eb:SetFontObject(UI.FONTS.Body)
  eb:SetSpacing(2)
  eb:SetWidth(w - 26)
  eb:SetMaxLetters(maxLetters or 4000)
  eb:SetScript("OnEscapePressed", eb.ClearFocus)
  eb:SetScript("OnTextChanged", function(self, user)
    if ScrollingEdit_OnTextChanged then pcall(ScrollingEdit_OnTextChanged, self, sf) end
    if user and onChange then onChange(self:GetText()) end
  end)
  if ScrollingEdit_OnCursorChanged then eb:SetScript("OnCursorChanged", ScrollingEdit_OnCursorChanged) end
  if ScrollingEdit_OnUpdate then eb:SetScript("OnUpdate", function(self, e) pcall(ScrollingEdit_OnUpdate, self, e, sf) end) end
  sf:SetScrollChild(eb)
  UI.ScrollBar(sf, style == "ink", 36)
  box:EnableMouse(true)
  box:SetScript("OnMouseDown", function() eb:SetFocus() end)
  StyleInput(box, eb, style)
  box.edit = eb
  return box
end

-- Scrolling read-only text (profile and Chronicle pages), set with DialogueUI's
-- generous line spacing.
function UI.ReadArea(parent, w, h, font, role)
  local sf = CreateFrame("ScrollFrame", nil, parent)
  sf:SetSize(w - 10, h)
  local child = CreateFrame("Frame", nil, sf)
  child:SetSize(w - 12, 1)
  sf:SetScrollChild(child)
  local fs = UI.Text(child, "", font or "Read", role or "text", w - 16)
  fs:SetPoint("TOPLEFT", 2, -2)
  fs:SetJustifyV("TOP")
  fs:SetSpacing(4)
  UI.ScrollBar(sf, role and role:find("^ink") ~= nil)
  sf.text = fs
  function sf:SetText(text)
    fs:SetText(text or "")
    child:SetHeight(math.max(1, fs:GetStringHeight() + 8))
    self:SetVerticalScroll(0)
  end
  return sf
end

-- Search box with a magnifier, placeholder and clear button.
function UI.Search(parent, width, placeholder, onChange)
  local eb = UI.Edit(parent, width, 24, "desk", 40)
  eb:SetTextInsets(24, 22, 0, 0)
  eb.icon = eb:CreateTexture(nil, "OVERLAY")
  eb.icon:SetTexture("Interface\\Common\\UI-Searchbox-Icon")
  eb.icon:SetSize(13, 13)
  eb.icon:SetPoint("LEFT", 7, -1)
  eb.icon:SetAlpha(0.6)
  eb.hint = UI.Text(eb, placeholder or SEARCH or "Search", "Small", "deskSubtle")
  eb.hint:SetPoint("LEFT", 24, 0)
  eb.hint:SetPoint("RIGHT", -8, 0)   -- a long hint ends in "..." inside the box
  eb.hint:SetWordWrap(false)
  eb.clear = UI.CloseButton(eb, false, 18)
  eb.clear:SetPoint("RIGHT", -3, 0)
  eb.clear:Hide()
  eb.clear:SetScript("OnClick", function() eb:SetText(""); eb:ClearFocus() end)
  eb:SetScript("OnTextChanged", function(self)
    local text = self:GetText() or ""
    self.hint:SetShown(text == "")
    self.clear:SetShown(text ~= "")
    onChange(strtrim(text):lower())
  end)
  return eb
end

---------------------------------------------------------------------------
-- Virtualised list (only builds frames for visible rows)
---------------------------------------------------------------------------
function UI.List(parent, w, h, rowH, emptyText, buildRow, opts)
  rowH, opts = rowH or 22, opts or {}
  local box = opts.bare and CreateFrame("Frame", nil, parent) or UI.Panel(parent)
  box:SetSize(w, h)
  local pad, barW = opts.bare and 0 or 6, 12
  local sf = CreateFrame("ScrollFrame", nil, box)
  sf:SetPoint("TOPLEFT", pad, -pad)
  sf:SetPoint("BOTTOMRIGHT", -(pad + barW), pad)
  local cw = w - 2 * pad - barW
  local content = CreateFrame("Frame", nil, sf)
  content:SetSize(cw, 1)
  sf:SetScrollChild(content)
  box.items, box.rows = {}, {}

  -- Empty state: the page's medallion, softly faded, over a short line of text
  box.emptyArt = box:CreateTexture(nil, "ARTWORK")
  box.emptyArt:SetTexture(opts.emptyIcon or K.ICON)
  local artSize = math.min(64, h * 0.3)
  box.emptyArt:SetSize(artSize, artSize)
  box.emptyArt:SetPoint("CENTER", 0, artSize * 0.5)
  box.emptyArt:SetAlpha(0.75)
  box.empty = UI.Text(box, emptyText or "Nothing here yet.", "Body", opts.ink and "inkSubtle" or "subtle", math.min(w - 40, 320))
  box.empty:SetPoint("TOP", box.emptyArt, "BOTTOM", 0, -12)
  box.empty:SetJustifyH("CENTER")
  box.empty:SetSpacing(3)

  local visible = math.ceil(h / rowH) + 1
  for i = 1, visible do
    local row = CreateFrame("Button", nil, content)
    row:SetSize(cw, rowH)
    row.stripe = row:CreateTexture(nil, "BACKGROUND")
    row.stripe:SetAllPoints(); row.stripe:Hide()
    row.hover = row:CreateTexture(nil, "BACKGROUND", nil, 1)
    row.hover:SetAllPoints(); row.hover:Hide()
    row.sel = row:CreateTexture(nil, "BACKGROUND", nil, 2)
    row.sel:SetAllPoints(); row.sel:SetColorTexture(1, 1, 1, 1); row.sel:Hide()
    row.selBar = row:CreateTexture(nil, "BORDER")
    row.selBar:SetTexture(WHITE)
    row.selBar:SetWidth(2)
    row.selBar:SetPoint("TOPLEFT"); row.selBar:SetPoint("BOTTOMLEFT")
    row.selBar:Hide()
    -- Pages toggle row.sel; the accent bar follows it.
    local selTex, selBar = row.sel, row.selBar
    function selTex:SetShown(v) if v then self:Show(); selBar:Show() else self:Hide(); selBar:Hide() end end

    local function paint(t)
      local hover, stripe, sel, bar
      if opts.ink then
        hover, stripe, sel, bar = { 0.40, 0.28, 0.12, 0.12 }, { 0.40, 0.28, 0.12, 0.05 }, { 0.07, 0.36, 0.36, 0.20 }, UI.INK.inkAccent
      else
        hover, stripe, sel, bar = t.hover, t.stripe, t.select, t.accent
      end
      row.hover:SetColorTexture(unpack(hover))
      row.stripe:SetColorTexture(unpack(stripe))
      if row.sel.SetGradient and CreateColor then
        row.sel:SetGradient("HORIZONTAL", CreateColor(sel[1], sel[2], sel[3], sel[4]), CreateColor(sel[1], sel[2], sel[3], sel[4] * 0.3))
      else
        row.sel:SetVertexColor(unpack(sel))
      end
      row.selBar:SetVertexColor(bar[1], bar[2], bar[3], 1)
    end
    if opts.ink then paint() else UI:OnTheme(paint) end

    row:SetScript("OnEnter", function(self) self.hover:Show(); if self.onEnter then self.onEnter(self) end end)
    row:SetScript("OnLeave", function(self) self.hover:Hide(); GameTooltip:Hide() end)
    row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    buildRow(row)
    row:Hide()
    box.rows[i] = row
  end

  function box:Render()
    local offset = math.floor(sf:GetVerticalScroll() / rowH)
    for i, row in ipairs(self.rows) do
      local idx = offset + i
      local item = self.items[idx]
      if item then
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", 0, -(idx - 1) * rowH)
        row.item = item
        row.stripe:SetShown(not opts.bare and idx % 2 == 0)
        self.fill(row, item, idx)
        row:Show()
      else
        row:Hide()
      end
    end
  end

  function box:SetItems(items, fill)
    self.items, self.fill = items, fill or self.fill
    local total = #items * rowH
    content:SetHeight(math.max(1, total))
    local maxScroll = math.max(0, total - sf:GetHeight())
    if sf:GetVerticalScroll() > maxScroll then sf:SetVerticalScroll(maxScroll) end
    self.empty:SetShown(#items == 0)
    self.emptyArt:SetShown(#items == 0)
    self:Render()
    self.scrollBar.Update()
  end

  box.scrollBar = UI.ScrollBar(sf, opts.ink, rowH * 2)
  sf:HookScript("OnVerticalScroll", function() box:Render() end)
  return box
end

-- Context menu using the game's modern menu system.
function UI.Menu(owner, build)
  if MenuUtil and MenuUtil.CreateContextMenu then
    MenuUtil.CreateContextMenu(owner, function(_, root) build(root) end)
  end
end

-- Copy box: for Discord text and anything else players need to copy.
function UI:Copy(title, text)
  if not self.copyFrame then
    local f = UI.Window("KinshipRPCopyFrame", "Copy text", 460, 304)
    f:SetFrameStrata("DIALOG")
    f.hint = UI.Text(f, "Press Ctrl+C to copy, then paste it wherever you like.", "Small", "deskSubtle", 420)
    f.hint:SetPoint("TOPLEFT", 16, -46)
    f.area = UI.TextArea(f, 430, 220, 8000, nil, "desk")
    f.area:SetPoint("TOPLEFT", 15, -68)
    self.copyFrame = f
  end
  local f = self.copyFrame
  f:SetTitle(title)
  f:Show()
  f.area.edit:SetText(text)
  f.area.edit:SetFocus()
  f.area.edit:HighlightText()
end

-- Status dot: a flat circle in the status colour.
function UI.Gem(parent, size)
  local g = UI.Circle(parent, math.floor((size or 14) * 0.7 + 0.5))
  function g:SetStatus(status)
    local s = K.STATUS[status] or K.STATUS.ooc
    self:SetVertexColor(s.color[1], s.color[2], s.color[3], 1)
  end
  g:SetStatus("ooc")
  return g
end

-- Round-mask a texture (crests, rings, dots).
function UI.Round(tex)
  if not tex.AddMaskTexture then return end
  local parent = tex:GetParent()
  local mask = parent:CreateMaskTexture()
  mask:SetTexture(CIRCLE_MASK, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
  mask:SetAllPoints(tex)
  tex:AddMaskTexture(mask)
end

---------------------------------------------------------------------------
-- Small helpers
---------------------------------------------------------------------------
function UI.SetProgress(key, p) progress[key] = p end

-- "just now", "12m ago", "3h ago", "yesterday", "4 days ago"
function UI.Ago(t)
  if not t then return "never" end
  local s = time() - t
  if s < 90 then return "just now" end
  if s < 3600 then return math.floor(s / 60) .. "m ago" end
  if s < 86400 then return math.floor(s / 3600) .. "h ago" end
  local d = math.floor(s / 86400)
  return d == 1 and "yesterday" or (d .. " days ago")
end

-- Text that came from another player: show it as typed, never as UI codes.
function UI.Escape(text) return (tostring(text or ""):gsub("|", "||")) end

-- Profile text from other addons may carry colours (fine) but must not carry
-- links, textures or other UI codes: keep the colours, drop the rest.
-- Escape-first: every pipe is made literal, then only colours, |r and |n
-- are let back in, so removing one code can never assemble another.
function UI.Clean(text)
  if type(text) ~= "string" then return "" end
  text = text:gsub("[\001\002]", "")
  text = text:gsub("||", "\001")                         -- pipes already shown literally
  text = text:gsub("|H.-|h(.-)|h", "%1")                 -- links: keep their label
  text = text:gsub("|[TtAaKk].-|[tTaAkK]", "")           -- textures, atlases, protected names
  text = text:gsub("|", "||")                            -- everything else becomes plain text...
  text = text:gsub("||(c%x%x%x%x%x%x%x%x)", "|%1")       -- ...except colours,
  text = text:gsub("||r", "|r")                          -- colour ends,
  text = text:gsub("||n", "\n")                          -- and line breaks
  text = text:gsub("\001", "||")
  return text
end

function UI.ClassColor(class)
  local c = class and ((C_ClassColor and C_ClassColor.GetClassColor(class)) or (RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]))
  if c then return c.r, c.g, c.b end
  return 0.8, 0.8, 0.8
end

-- Class crest from the shared class sheet.
function UI.ClassIcon(tex, class)
  local c = class and CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[class]
  if c then
    tex:SetTexture("Interface\\WorldStateFrame\\ICONS-CLASSES")
    tex:SetTexCoord(c[1] + 0.015, c[2] - 0.015, c[3] + 0.015, c[4] - 0.015)
  else
    tex:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
    tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
  end
end

-- A small coloured pill label ("Honour first", "Nemesis", "Unread").
-- desk = sits straight on the window; otherwise it's on a card and its text
-- is inked down on Classic's cream so it stays readable.
function UI.Chip(parent, font, desk)
  local c = CreateFrame("Frame", nil, parent)
  c:SetSize(40, 18)
  c.bg = c:CreateTexture(nil, "BACKGROUND")
  c.bg:SetAllPoints()
  c.bg:SetTexture(WHITE)
  c.edge = UI.Border(c)
  c.text = c:CreateFontString(nil, "OVERLAY")
  c.text:SetFontObject(UI.FONTS[font or "Label"])
  c.text:SetPoint("CENTER", 0, 0)
  function c:Set(text, color)
    color = color or K:Theme().accent
    self.text:SetText(text or "")
    local tc = desk and color or UI.OnCard(color)
    self.text:SetTextColor(tc[1], tc[2], tc[3])
    self.bg:SetVertexColor(color[1], color[2], color[3], 0.14)
    self.edge:SetColor(color[1], color[2], color[3], 0.55)
    self:SetWidth(math.ceil(self.text:GetStringWidth()) + 14)
    self:SetShown(text ~= nil and text ~= "")
  end
  return c
end

---------------------------------------------------------------------------
-- Toggle switch: a track with a sliding knob, with a
-- label and an optional line of explanation. onPanel = sits on a card.
---------------------------------------------------------------------------
function UI.Toggle(parent, label, desc, get, set, width, onPanel)
  width = width or 300
  local row = CreateFrame("Button", nil, parent)
  row:SetSize(width, 24)
  local sw = CreateFrame("Frame", nil, row)
  sw:SetSize(34, 18)
  sw:SetPoint("TOPRIGHT", 0, -1)
  sw.bg = sw:CreateTexture(nil, "BACKGROUND")
  sw.bg:SetAllPoints()
  sw.bg:SetTexture(WHITE)
  sw.edge = UI.Border(sw)
  sw.knob = sw:CreateTexture(nil, "ARTWORK")
  sw.knob:SetTexture(WHITE)
  sw.knob:SetSize(12, 12)
  row.switch = sw
  row.label = UI.Text(row, label, "Body", onPanel and "text" or "deskText", width - 48)
  row.label:SetPoint("TOPLEFT", 0, -2)
  if desc then
    row.desc = UI.Text(row, desc, "Small", onPanel and "subtle" or "deskSubtle", width - 48)
    row.desc:SetPoint("TOPLEFT", row.label, "BOTTOMLEFT", 0, -3)
    row.desc:SetSpacing(2)
  end

  local function paint(p)
    local t = K:Theme()
    local on = onPanel and t.accent or t.ui
    local off = t.light and onPanel and { 0.30, 0.20, 0.08, 0.22 } or { 1, 1, 1, 0.14 }
    sw.bg:SetVertexColor(UI.Mix(off, { on[1], on[2], on[3], 0.85 }, p))
    sw.edge:SetColor(UI.Mix(off, { on[1], on[2], on[3], 1 }, p))
    sw.knob:ClearAllPoints()
    sw.knob:SetPoint("LEFT", 3 + p * 16, 0)
    sw.knob:SetVertexColor(1, 1, 1, 0.75 + 0.25 * p)
  end
  function row:Refresh()
    local p = get() and 1 or 0
    UI.SetProgress(self, p)
    paint(p)
    local h = 4 + self.label:GetStringHeight() + (self.desc and (self.desc:GetStringHeight() + 3) or 0)
    self:SetHeight(math.max(22, math.ceil(h)))
  end
  row:SetScript("OnClick", function(self)
    local v = not get()
    set(v)
    if SOUNDKIT then PlaySound(v and SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON or SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_OFF) end
    UI.Tween(self, v and 1 or 0, 0.12, paint, UI.Ease.outQuart)
  end)
  row:SetScript("OnEnter", function(self) self.label:SetAlpha(1); sw:SetAlpha(1) end)
  row:SetScript("OnLeave", function(self) self.label:SetAlpha(0.92); sw:SetAlpha(0.92) end)
  row.label:SetAlpha(0.92); sw:SetAlpha(0.92)
  UI:OnTheme(function() row:Refresh() end)
  return row
end

---------------------------------------------------------------------------
-- Wax seal: a disc of coloured wax with the crest pressed into it.
---------------------------------------------------------------------------
UI.SEAL_COLORS = {
  { key = "crimson", label = "Crimson", color = { 0.60, 0.10, 0.12 } },
  { key = "royal",   label = "Royal",   color = { 0.17, 0.25, 0.58 } },
  { key = "forest",  label = "Forest",  color = { 0.14, 0.40, 0.22 } },
  { key = "teal",    label = "Teal",    color = { 0.05, 0.38, 0.38 } },
  { key = "gold",    label = "Gold",    color = { 0.78, 0.58, 0.18 } },
  { key = "violet",  label = "Violet",  color = { 0.40, 0.18, 0.52 } },
  { key = "night",   label = "Night",   color = { 0.13, 0.12, 0.12 } },
}
function UI.SealColor(key)
  for _, s in ipairs(UI.SEAL_COLORS) do if s.key == key then return s.color end end
  return UI.SEAL_COLORS[1].color
end

function UI.Seal(parent, size)
  local s = CreateFrame("Frame", nil, parent)
  s:SetSize(size, size)
  s.shadow = UI.Circle(s, size + 3, "BACKGROUND")
  s.shadow:SetPoint("CENTER", 1, -2)
  s.shadow:SetVertexColor(0, 0, 0, 0.35)
  s.wax = UI.Circle(s, size, "ARTWORK", 0)
  s.wax:SetPoint("CENTER")
  s.rim = UI.Circle(s, math.floor(size * 0.80), "ARTWORK", 1)
  s.rim:SetPoint("CENTER")
  s.crest = s:CreateTexture(nil, "ARTWORK", nil, 2)
  s.crest:SetSize(math.floor(size * 0.56), math.floor(size * 0.56))
  s.crest:SetPoint("CENTER")
  s.crest:SetTexCoord(0.08, 0.92, 0.08, 0.92)
  UI.Round(s.crest)
  s.crest:SetDesaturated(true)
  s.shine = UI.Circle(s, math.floor(size * 0.42), "ARTWORK", 3)
  s.shine:SetPoint("CENTER", -size * 0.16, size * 0.16)
  s.shine:SetVertexColor(1, 1, 1, 0.10)
  function s:SetSeal(colorKey, crest)
    local c = UI.SealColor(colorKey)
    self.wax:SetVertexColor(c[1], c[2], c[3], 1)
    self.rim:SetVertexColor(c[1] * 0.78, c[2] * 0.78, c[3] * 0.78, 1)
    self.crest:SetTexture(crest or "Interface\\Icons\\INV_Shield_05")
    self.crest:SetVertexColor(math.min(1, c[1] * 1.6 + 0.1), math.min(1, c[2] * 1.6 + 0.1), math.min(1, c[3] * 1.6 + 0.1), 0.85)
  end
  s:SetSeal("crimson")
  return s
end

---------------------------------------------------------------------------
-- Toasts: small cards that slide in at the top of the screen, stack, pause
-- while hovered and fade away. o = { icon, round, title, text, big, color,
-- duration, sound, onClick, actions = { { label, fn }, ... } }
---------------------------------------------------------------------------
local toastPool, toastActive = {}, {}
local TOAST_W, TOAST_TOP = 360, 120

local function LayoutToasts()
  local y = -TOAST_TOP
  for _, f in ipairs(toastActive) do
    f.baseY = y
    f:ClearAllPoints()
    f:SetPoint("TOP", UIParent, "TOP", 0, y + (f.slide or 0))
    y = y - f:GetHeight() - 8
  end
end

-- Safe to call twice (an action that raises a toast can push this one out
-- first): only a toast that's still showing goes back to the pool.
local function ReleaseToast(f)
  local found
  for i, a in ipairs(toastActive) do if a == f then table.remove(toastActive, i); found = true break end end
  if not found then return end
  f:Hide()
  f:SetScript("OnUpdate", nil)
  toastPool[#toastPool + 1] = f
  LayoutToasts()
end

local function NewToast()
  local f = CreateFrame("Button", nil, UIParent)
  f:SetSize(TOAST_W, 64)
  f:SetFrameStrata("DIALOG")
  f:SetClampedToScreen(true)
  f.bg = f:CreateTexture(nil, "BACKGROUND")
  f.bg:SetAllPoints()
  f.edge = UI.Border(f)
  f.bar = f:CreateTexture(nil, "ARTWORK")
  f.bar:SetTexture(WHITE)
  f.bar:SetWidth(3)
  f.bar:SetPoint("TOPLEFT")
  f.bar:SetPoint("BOTTOMLEFT")
  f.glow = f:CreateTexture(nil, "BACKGROUND", nil, 1)
  f.glow:SetPoint("TOPLEFT"); f.glow:SetPoint("BOTTOMLEFT"); f.glow:SetWidth(140)
  f.glow:SetColorTexture(1, 1, 1, 1)
  f.icon = f:CreateTexture(nil, "ARTWORK")
  f.icon:SetSize(40, 40)
  f.icon:SetPoint("TOPLEFT", 14, -12)
  f.iconMask = f:CreateMaskTexture()
  f.iconMask:SetTexture(CIRCLE_MASK, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
  f.iconMask:SetAllPoints(f.icon)
  f.title = UI.Text(f, "", "Header", "deskHeading", TOAST_W - 150)
  f.title:SetPoint("TOPLEFT", f.icon, "TOPRIGHT", 12, -2)
  f.title:SetWordWrap(false)
  f.text = UI.Text(f, "", "Small", "deskText", TOAST_W - 150)
  f.text:SetPoint("TOPLEFT", f.title, "BOTTOMLEFT", 0, -4)
  f.big = UI.Text(f, "", "Huge", "deskHeading")
  f.big:SetPoint("RIGHT", -16, 0)
  f.big:SetJustifyH("RIGHT")
  f.actions = {}
  for i = 1, 2 do
    local b = UI.Button(f, "", 96, 22)
    b:SetPoint("BOTTOMRIGHT", -12 - (2 - i) * 102, 10)
    f.actions[i] = b
  end
  UI:OnTheme(function(t)
    f.bg:SetColorTexture(unpack(t.chrome))
    f.edge:SetColor(unpack(t.chromeEdge))
  end)
  f:SetScript("OnEnter", function(self) self.hovered = true end)
  f:SetScript("OnLeave", function(self) self.hovered = false end)
  f:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  return f
end

function UI.Toast(o)
  local f = table.remove(toastPool) or NewToast()
  -- Each showing gets its own number, so a click meant for an earlier toast
  -- never closes a later one that reuses this frame.
  f.gen = (f.gen or 0) + 1
  local gen = f.gen
  local function Done() if f.gen == gen then ReleaseToast(f) end end
  local color = o.color or K:Theme().ui
  f.bar:SetVertexColor(color[1], color[2], color[3], 1)
  if f.glow.SetGradient and CreateColor then
    f.glow:SetGradient("HORIZONTAL", CreateColor(color[1], color[2], color[3], 0.16), CreateColor(color[1], color[2], color[3], 0))
  else
    f.glow:SetVertexColor(color[1], color[2], color[3], 0.08)
  end
  f.icon:SetTexture(o.icon or K.ICON)
  if o.round and not f.masked then f.icon:AddMaskTexture(f.iconMask); f.masked = true
  elseif not o.round and f.masked then f.icon:RemoveMaskTexture(f.iconMask); f.masked = false end
  f.icon:SetTexCoord(unpack(o.round and { 0.08, 0.92, 0.08, 0.92 } or { 0, 1, 0, 1 }))
  if o.iconCoords then f.icon:SetTexCoord(unpack(o.iconCoords)) end
  f.title:SetText(o.title or "")
  f.text:SetText(o.text or "")
  f.big:SetText(o.big or "")
  local bigW = o.big and (f.big:GetStringWidth() + 24) or 0
  f.title:SetWidth(TOAST_W - 80 - bigW)
  f.text:SetWidth(TOAST_W - 80 - bigW)
  local n = o.actions and #o.actions or 0
  for i, b in ipairs(f.actions) do
    local a = o.actions and o.actions[n - 2 + i]
    b:SetShown(a ~= nil)
    if a then
      b:SetText(a.label)
      b:SetScript("OnClick", function() K.Try("toast", a.fn); Done() end)
    end
  end
  local textH = f.title:GetStringHeight() + f.text:GetStringHeight() + 30
  f:SetHeight(math.max(64, math.ceil(textH)) + (n > 0 and 30 or 0))
  f:SetScript("OnClick", function(_, button)
    if button == "LeftButton" and o.onClick then K.Try("toast", o.onClick) end
    Done()
  end)

  table.insert(toastActive, 1, f)
  while #toastActive > 4 do ReleaseToast(toastActive[#toastActive]) end
  f.slide, f.hovered = 12, false
  f:SetAlpha(0)
  f:Show()
  LayoutToasts()
  if o.sound and SOUNDKIT and SOUNDKIT[o.sound] then PlaySound(SOUNDKIT[o.sound]) end

  local life, hold, t = 0.35, o.duration or (n > 0 and 20 or 6), 0
  f:SetScript("OnUpdate", function(self, elapsed)
    if self.hovered and t > life then return end
    t = t + elapsed
    if t < life then
      local p = UI.Ease.outQuart(t / life)
      self:SetAlpha(p)
      self.slide = 12 * (1 - p)
      self:SetPoint("TOP", UIParent, "TOP", 0, self.baseY + self.slide)
    elseif t < life + hold then
      if self.slide ~= 0 then self.slide = 0; self:SetAlpha(1); self:SetPoint("TOP", UIParent, "TOP", 0, self.baseY) end
    elseif t < life + hold + 0.4 then
      self:SetAlpha(1 - (t - life - hold) / 0.4)
    else
      ReleaseToast(self)
    end
  end)
  return f
end
