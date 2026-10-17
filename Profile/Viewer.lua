-- Kinship RP: profile viewer (inspect-style).

local ADDON, ns = ...
local K = ns.K
local UI = K.UI
local V = {}
K.Viewer = V

-- Other players' profiles, as they arrive (Comm.lua fills this).
K.Registry = K.Registry or {}

-- Nature: personality and traits, kept off About so it stays short.
local TABS = { "About", "Nature", "Looks", "History", "Chronicle" }
local CHRONICLE = 5

-- Inline headings inside the reading text, in the theme's accent.
local function Head(text) return "|cff" .. UI.Hex(K:Theme().accent) .. text .. "|r" end

-- Profile writing, through Kinship's markup (headings, rules, icons) when it's there.
local function Rich(text, other)
  if not text or text == "" then return text end
  if K.Markup then return K.Markup:Render(text, { other = other, width = 330 }) end
  return text
end

-- Personality traits as two-coloured bars, one line each.
local BAR_W = 200
local function Bar(w, c)
  if w <= 0 then return "" end
  return ("|TInterface\\Buttons\\WHITE8X8:8:%d:0:0:8:8:0:8:0:8:%d:%d:%d|t"):format(w,
    math.floor(c[1] * 255), math.floor(c[2] * 255), math.floor(c[3] * 255))
end
local function TraitLines(p, other)
  local P = K.Persona
  if not P then return nil end
  local out = {}
  for _, t in ipairs(P.Traits(p)) do
    local v = P.TraitValue(t)
    local lw = math.floor(BAR_W * v / 20 + 0.5)
    local lc, rc = P.LeftColor(t), P.RightColor(t)
    local left = strtrim(other and UI.Clean(t.left) or t.left)
    local right = strtrim(other and UI.Clean(t.right) or t.right)
    -- The two traits on one line, each in its own side's colour, and the bar
    -- on the line under them (an image in a line of text sits above the
    -- words, so a bar beside its words never quite lines up with them).
    out[#out + 1] = ("|cff%s%s|r  |cff9a8f7a/|r  |cff%s%s|r\n%s%s"):format(UI.CardHex(lc), left, UI.CardHex(rc), right,
      Bar(lw, lc), Bar(BAR_W - lw, rc))
  end
  return #out > 0 and table.concat(out, "\n") or nil
end

---------------------------------------------------------------------------
-- The stage: the backdrop behind your character, an optional spotlight and
-- the floor they stand on. Chosen from the palette button on your own
-- profile, and shared with other Kinship users (field KS), so they see your
-- character the way you set them out. Other addons simply ignore it.
---------------------------------------------------------------------------
local SCENES = {
  { key = "theme", label = "Kinship" },   -- the theme's own stage colours
  { key = "night", label = "Night", top = { 0.11, 0.14, 0.27 }, bottom = { 0.02, 0.03, 0.07 }, light = { 0.72, 0.80, 1.00 } },
  { key = "dusk", label = "Dusk", top = { 0.46, 0.24, 0.36 }, bottom = { 0.11, 0.05, 0.10 }, light = { 1.00, 0.74, 0.55 } },
  { key = "forest", label = "Forest", top = { 0.15, 0.27, 0.16 }, bottom = { 0.03, 0.07, 0.04 }, light = { 0.86, 1.00, 0.72 } },
  { key = "ember", label = "Ember", top = { 0.47, 0.18, 0.07 }, bottom = { 0.10, 0.03, 0.02 }, light = { 1.00, 0.70, 0.40 } },
  { key = "frost", label = "Frost", top = { 0.42, 0.55, 0.66 }, bottom = { 0.08, 0.13, 0.21 }, light = { 0.85, 0.95, 1.00 } },
  { key = "parchment", label = "Parchment", top = { 0.60, 0.52, 0.38 }, bottom = { 0.25, 0.19, 0.12 }, light = { 1.00, 0.93, 0.76 } },
  { key = "void", label = "Void", top = { 0.08, 0.08, 0.09 }, bottom = { 0, 0, 0 }, light = { 0.90, 0.90, 0.95 } },
}
local SCENE = {}
for _, sc in ipairs(SCENES) do SCENE[sc.key] = sc end
local FLOORS = { { key = "shadow", label = "Shadow" }, { key = "glow", label = "Pool of light" }, { key = "none", label = "Nothing" } }
local FLOOR = { shadow = true, glow = true, none = true }

-- A profile's stage, with the defaults filled in.
local function StageOf(p)
  local st = p and type(p.stage) == "table" and p.stage or {}
  local c = st.c
  local custom = st.bg == "custom" and type(c) == "table" and type(c[1]) == "number" and type(c[2]) == "number" and type(c[3]) == "number"
  return {
    bg = (custom or SCENE[st.bg or ""]) and st.bg or "theme",
    c = custom and { math.max(0, math.min(1, c[1])), math.max(0, math.min(1, c[2])), math.max(0, math.min(1, c[3])) } or nil,
    spot = st.spot == true,
    floor = FLOOR[st.floor or ""] and st.floor or "shadow",
  }
end
V.StageOf = StageOf

local function Hex(c) return ("%02x%02x%02x"):format(math.floor(c[1] * 255 + 0.5), math.floor(c[2] * 255 + 0.5), math.floor(c[3] * 255 + 0.5)) end

-- "scene;rrggbb;spot;floor", e.g. "dusk;;1;glow" or "custom;3a5f8c;0;shadow".
function V.EncodeStage(p)
  if not (p and type(p.stage) == "table") then return nil end
  local st = StageOf(p)
  if st.bg == "theme" and not st.spot and st.floor == "shadow" then return nil end
  return ("%s;%s;%s;%s"):format(st.bg, st.c and Hex(st.c) or "", st.spot and "1" or "0", st.floor)
end

function V.DecodeStage(text)
  if type(text) ~= "string" or #text > 40 then return nil end
  local bg, hex, spot, floor = text:match("^(%a+);(%x*);([01]);(%a+)$")
  if not bg then return nil end
  local st = { bg = bg, spot = spot == "1", floor = floor }
  if bg == "custom" and #hex == 6 then
    st.c = { tonumber(hex:sub(1, 2), 16) / 255, tonumber(hex:sub(3, 4), 16) / 255, tonumber(hex:sub(5, 6), 16) / 255 }
  end
  local clean = StageOf({ stage = st })
  if clean.bg == "custom" and not clean.c then clean.bg = "theme" end
  return clean
end

K:AddProfileField({
  full = { "KS" },
  publish = function(my, p) my.KS = V.EncodeStage(p) end,
  read = function(fields, out) out.stage = V.DecodeStage(fields.KS) end,
})

-- The colours a stage paints with: top and bottom of the backdrop, and its light.
local function StageColors(st)
  if st.bg == "custom" and st.c then
    local c = st.c
    return c, { c[1] * 0.22, c[2] * 0.22, c[3] * 0.22 }, { 0.55 + c[1] * 0.45, 0.55 + c[2] * 0.45, 0.55 + c[3] * 0.45 }
  end
  local sc = SCENE[st.bg]
  if sc and sc.top then return sc.top, sc.bottom, sc.light end
  local t = K:Theme()
  return t.stageTop, t.stageBottom, { 1.00, 0.94, 0.80 }
end

-- Open the game's colour picker. onChange(r, g, b) while choosing; onCancel() puts it back.
local function PickColor(r, g, b, onChange, onCancel)
  local cpf = ColorPickerFrame
  if not cpf then return end
  local function current() return cpf:GetColorRGB() end
  if cpf.SetupColorPickerAndShow then
    cpf:SetupColorPickerAndShow({ r = r, g = g, b = b, hasOpacity = false,
      swatchFunc = function() onChange(current()) end, cancelFunc = function() onCancel() end })
  else
    cpf.hasOpacity, cpf.opacityFunc = false, nil
    cpf.previousValues = { r, g, b }
    cpf.func = function() onChange(current()) end
    cpf.cancelFunc = function() onCancel() end
    cpf:SetColorRGB(r, g, b)
    cpf:Hide()
    cpf:Show()
  end
end

local function Paragraphs(parts)
  local out = {}
  for _, p in ipairs(parts) do
    if p[2] and strtrim(p[2]) ~= "" then out[#out + 1] = Head(p[1]) .. "\n" .. p[2] end
  end
  return table.concat(out, "\n\n")
end

function V:Build()
  if self.frame then return end
  local f = UI.Window("KinshipRPViewer", "Roleplay profile", 640, 484)
  self.frame = f
  local desk = UI.Desk(f)
  desk:SetPoint("TOPLEFT", 1, -35)
  desk:SetPoint("BOTTOMRIGHT", -1, 1)

  -- Model --------------------------------------------------------------------
  -- A softly lit stage: a vertical gradient (the theme's colours, or the
  -- profile's chosen scene), an optional spotlight, something on the floor
  -- under their feet, a gold (or accent) line along the floor, and a 1px edge.
  local stage = CreateFrame("Frame", nil, f)
  stage:SetSize(226, 422)
  stage:SetPoint("TOPLEFT", 14, -48)
  local backdrop = stage:CreateTexture(nil, "BACKGROUND")
  backdrop:SetAllPoints()
  backdrop:SetColorTexture(1, 1, 1, 1)
  local shade = stage:CreateTexture(nil, "BACKGROUND", nil, 1)
  shade:SetPoint("BOTTOMLEFT"); shade:SetPoint("BOTTOMRIGHT"); shade:SetHeight(70)
  shade:SetColorTexture(1, 1, 1, 1)
  local spot = stage:CreateTexture(nil, "BACKGROUND", nil, 2)
  spot:SetTexture(K.MEDIA .. "StageSpot")
  spot:SetPoint("TOP", 0, 0)
  spot:SetSize(226, 400)
  spot:SetBlendMode("ADD")
  local pool = stage:CreateTexture(nil, "BACKGROUND", nil, 3)
  pool:SetTexture(K.MEDIA .. "StageFloor")
  -- Wide enough to read as a patch of floor, not a footprint: the game centres
  -- a model by its whole outline (an outstretched arm included), so the feet
  -- can sit a little to one side, and they still land well inside it.
  pool:SetPoint("BOTTOM", 0, 82)
  pool:SetSize(214, 46)
  local floor = stage:CreateTexture(nil, "ARTWORK")
  floor:SetTexture("Interface\\Buttons\\WHITE8X8")
  floor:SetHeight(2)
  floor:SetPoint("BOTTOMLEFT", 0, 0)
  floor:SetPoint("BOTTOMRIGHT", 0, 0)
  local edge = CreateFrame("Frame", nil, stage)
  edge:SetAllPoints()
  edge:SetFrameLevel(stage:GetFrameLevel() + 5)
  edge.border = UI.Border(edge)
  self.stageParts = { backdrop = backdrop, shade = shade, spot = spot, pool = pool, floor = floor, edge = edge }
  UI:OnTheme(function() V:PaintStage() end)
  local model = CreateFrame("PlayerModel", nil, stage)
  model:SetPoint("TOPLEFT", 6, -6)
  model:SetPoint("BOTTOMRIGHT", -6, 30)
  model.facing = 0
  model:EnableMouse(true)
  model:SetScript("OnMouseDown", function(self) self.dragX = GetCursorPosition() end)
  model:SetScript("OnMouseUp", function(self) self.dragX = nil end)
  model:SetScript("OnUpdate", function(self)
    if self.dragX then
      local x = GetCursorPosition()
      self.facing = self.facing + (x - self.dragX) * 0.012
      self.dragX = x
      self:SetFacing(self.facing)
    end
  end)
  self.model = model
  self.stageEmpty = stage:CreateTexture(nil, "ARTWORK")
  self.stageEmpty:SetTexture(K.MONOGRAM)
  self.stageEmpty:SetSize(96, 96)
  self.stageEmpty:SetPoint("CENTER", 0, 20)
  self.stageEmpty:SetAlpha(0.25)
  self.stageNote = UI.Text(stage, "", "GameFontHighlightSmall", "fixed", 190)
  self.stageNote:SetTextColor(0.95, 0.9, 0.8)
  self.stageNote:SetPoint("BOTTOM", 0, 14)
  self.stageNote:SetJustifyH("CENTER")

  -- Your own profile: a palette button to set the stage out.
  local pal = CreateFrame("Button", nil, stage)
  pal:SetSize(24, 24)
  pal:SetPoint("TOPRIGHT", -7, -7)
  pal:SetFrameLevel(model:GetFrameLevel() + 3)
  pal.ring = UI.Circle(pal, 24, "ARTWORK", 0)
  pal.ring:SetPoint("CENTER")
  pal.hole = UI.Circle(pal, 21, "ARTWORK", 1)
  pal.hole:SetPoint("CENTER")
  pal.icon = pal:CreateTexture(nil, "ARTWORK", nil, 2)
  pal.icon:SetTexture(K.Art("IconPalette"))
  pal.icon:SetSize(19, 19)
  pal.icon:SetPoint("CENTER")
  pal.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
  UI.Round(pal.icon)
  local function palPaint(pr)
    local t = K:Theme()
    pal.ring:SetVertexColor(t.ui[1], t.ui[2], t.ui[3], 0.5 + 0.5 * pr)
    pal.hole:SetVertexColor(0, 0, 0, 0.6)
    pal.icon:SetAlpha(0.8 + 0.2 * pr)
  end
  pal:SetScript("OnEnter", function(b)
    UI.Tween(b, 1, 0.1, palPaint)
    GameTooltip:SetOwner(b, "ANCHOR_RIGHT")
    GameTooltip:SetText("Set the stage", 1, 0.82, 0)
    GameTooltip:AddLine("The backdrop, light and floor behind your character. Other Kinship users see it too.", 1, 1, 1, true)
    GameTooltip:Show()
  end)
  pal:SetScript("OnLeave", function(b) UI.Tween(b, 0, 0.12, palPaint); GameTooltip:Hide() end)
  pal:SetScript("OnClick", function(b) GameTooltip:Hide(); V:StageMenu(b) end)
  UI:OnTheme(function() palPaint(UI.Progress(pal)) end)
  pal:Hide()
  self.palette = pal

  -- What they're wearing: round tokens like the glances, ringed in each
  -- item's quality colour, packed down the side in head-to-toe order (see
  -- V:PlaceWorn). Hover for the item.
  self.wornSlots = {}
  if K.Worn then
    local I = K.Items
    for i = 1, #I.WEAR do
      local b = CreateFrame("Button", nil, stage)
      b:SetFrameLevel(model:GetFrameLevel() + 3)
      b.ring = UI.Circle(b, 30, "ARTWORK", 0)
      b.ring:SetPoint("CENTER")
      b.hole = UI.Circle(b, 27, "ARTWORK", 1)
      b.hole:SetPoint("CENTER")
      b.icon = b:CreateTexture(nil, "ARTWORK", nil, 2)
      b.icon:SetPoint("CENTER")
      b.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
      UI.Round(b.icon)
      local function paint(pr)
        local c = b.color or K:Theme().ui
        local sz = b.size or 30
        b.ring:SetSize(sz, sz)
        b.hole:SetSize(sz - 3, sz - 3)
        b.ring:SetVertexColor(c[1], c[2], c[3], 0.65 + 0.35 * pr)
        b.hole:SetVertexColor(0, 0, 0, 0.6)
        b.icon:SetSize(sz - 6 + 2 * pr, sz - 6 + 2 * pr)
      end
      b.paint = paint
      b:SetScript("OnEnter", function(self)
        UI.Tween(self, 1, 0.1, paint)
        if not self.def then return end
        I:ShowTooltip(self, self.def, nil, "ANCHOR_RIGHT")
        GameTooltip:AddLine("Worn: " .. (I.WEAR_LABEL[self.slot] or ""), 0.55, 0.80, 1)
        GameTooltip:Show()
      end)
      b:SetScript("OnLeave", function(self) UI.Tween(self, 0, 0.12, paint); GameTooltip:Hide() end)
      UI:OnTheme(function() paint(UI.Progress(b)) end)
      b:Hide()
      self.wornSlots[i] = b
    end
  end

  -- Glances, in a row along the foot of the stage
  self.glances = {}
  for i = 1, 5 do
    local b = CreateFrame("Button", nil, stage)
    b:SetSize(34, 34)
    b:SetFrameLevel(model:GetFrameLevel() + 2)
    b.ring = UI.Circle(b, 34, "ARTWORK", 0)
    b.ring:SetPoint("CENTER")
    b.icon = b:CreateTexture(nil, "ARTWORK", nil, 1)
    b.icon:SetSize(30, 30)
    b.icon:SetPoint("CENTER")
    UI.Round(b.icon)
    local function paint(p)
      local u = K:Theme().ui
      b.ring:SetVertexColor(u[1], u[2], u[3], 0.5 + 0.5 * p)
      b.icon:SetSize(30 + 2 * p, 30 + 2 * p)
    end
    b:SetScript("OnEnter", function(self)
      UI.Tween(self, 1, 0.1, paint)
      if K.Persona and self.glance then K.Persona.GlanceTooltip(self, self.glance, self.other, "ANCHOR_RIGHT") end
    end)
    b:SetScript("OnLeave", function(self)
      UI.Tween(self, 0, 0.12, paint)
      if K.Persona then K.Persona.HideTooltip() else GameTooltip:Hide() end
    end)
    UI:OnTheme(function() paint(UI.Progress(b)) end)
    b:Hide()
    self.glances[i] = b
  end
  self.stage = stage

  -- Header -------------------------------------------------------------------
  local info = UI.Panel(f)
  info:SetPoint("TOPLEFT", f, "TOPLEFT", 250, -48)
  info:SetPoint("BOTTOMRIGHT", -14, 14)
  self.info = info

  self.name = UI.Text(info, "", "GameFontNormalHuge", "heading", 330)
  self.name:SetPoint("TOPLEFT", 18, -16)
  self.epithet = UI.Text(info, "", "GameFontHighlight", "accent", 330)
  self.epithet:SetPoint("TOPLEFT", self.name, "BOTTOMLEFT", 0, -3)

  self.crest = info:CreateTexture(nil, "ARTWORK")
  self.crest:SetSize(16, 16)
  self.crest:SetPoint("TOPLEFT", self.epithet, "BOTTOMLEFT", 0, -6)
  self.house = UI.Text(info, "", "GameFontHighlightSmall", "text", 300)
  self.house:SetPoint("LEFT", self.crest, "RIGHT", 5, 0)
  -- "of House X" opens the house's own card
  local hb = CreateFrame("Button", nil, info)
  hb:SetPoint("LEFT", self.crest, "LEFT", -2, 0)
  hb:SetHeight(20)
  hb:SetScript("OnEnter", function(b)
    local u = K:Theme().accent
    V.house:SetTextColor(u[1], u[2], u[3])
    GameTooltip:SetOwner(b, "ANCHOR_RIGHT")
    GameTooltip:SetText(V.house:GetText() or "", 1, 0.82, 0)
    GameTooltip:AddLine("Click to see the house: its motto, history and members.", 1, 1, 1, true)
    GameTooltip:Show()
  end)
  hb:SetScript("OnLeave", function()
    V.house:SetTextColor(unpack(K:Theme().text))
    GameTooltip:Hide()
  end)
  hb:SetScript("OnClick", function()
    local d = V.data
    local p = d and d.profile
    if p and p.house then V:ShowHouse(p.house, not d.mine and p or nil) end
  end)
  hb:Hide()
  self.houseBtn = hb

  self.gem = UI.Gem(info, 16)
  self.gem:SetPoint("TOPLEFT", 16, -78)
  self.status = UI.Text(info, "", "GameFontHighlightSmall", "text")
  self.status:SetPoint("LEFT", self.gem, "RIGHT", 4, 0)
  self.stance = UI.Chip(info)
  self.stance:SetPoint("LEFT", self.status, "RIGHT", 10, 0)
  self.exp = UI.Chip(info)
  self.exp:SetPoint("LEFT", self.stance, "RIGHT", 6, 0)

  -- Quick facts in two columns
  self.facts = {}
  local labels = { "Pronouns", "Age", "Height", "Home" }
  for i, label in ipairs(labels) do
    local col, row = (i - 1) % 2, math.floor((i - 1) / 2)
    local l = UI.Text(info, label, "GameFontNormalSmall", "subtle")
    l:SetPoint("TOPLEFT", 18 + col * 180, -102 - row * 18)
    local v = UI.Text(info, "", "GameFontHighlightSmall", "text", 110)
    v:SetPoint("TOPLEFT", 80 + col * 180, -102 - row * 18)
    v:SetWordWrap(false)
    self.facts[label] = v
  end

  self.currently = UI.Text(info, "", "QuestFont", "subtle", 334)
  self.currently:SetPoint("TOPLEFT", 18, -142)
  if self.currently.SetMaxLines then self.currently:SetMaxLines(2) end

  -- Tabs with an accent underline, sitting on a hairline
  self.tabs = UI.TabBar(info, TABS, function(i) V:ShowTab(i) end)
  self.tabs:SetPoint("TOPLEFT", 10, -178)
  self.tabs.maxWidth = 300   -- inside the panel and clear of its scrollbar: the gaps close up to fit
  local div = UI.Divider(info, 330)
  div:SetPoint("TOPLEFT", 18, -204)
  self.body = UI.ReadArea(info, 340, 196, "QuestFont")
  self.body:SetPoint("TOPLEFT", 18, -214)

  -- Mature-content cover over the profile (Safety module)
  if K.Safety then self.cover = K.Safety:Cover(info) end

  -- Inline colours are baked into the text, so rebuild it when the look changes.
  UI:OnTheme(function() if V.data and V.tab then V:ShowTab(V.tab) end end)
end

function V:ShowTab(i)
  if self.tab ~= i and self.frame:IsShown() then UI.FadeIn(self.body, 0.2) end
  self.tab = i
  self.tabs:Select(i)
  local d = self.data
  local text
  if not d.profile then
    if i == CHRONICLE and d.mine then text = self:ChronicleText() else text = d.missing end
  elseif i == 1 then
    local bounds = {}
    for _, f in ipairs(K.CONSENT) do
      local v = d.profile.consent and d.profile.consent[f.key]
      for _, cv in ipairs(K.CONSENT_VALUES) do
        if cv.key == v then bounds[#bounds + 1] = ("%s |cff%s%s|r"):format(f.label, UI.CardHex(cv.color), cv.key == "3" and "ask first" or cv.label:lower()) end
      end
    end
    local pr = d.profile
    -- Who they are, on one line: "Human  ·  Paladin  ·  Storm grey eyes  ·  Born in Moonbrook"
    local who = {}
    for _, f in ipairs({ { "", "race" }, { "", "class" }, { "", "eyes", " eyes" }, { "Born in ", "birthplace" },
                         { "Known as ", "nickname" } }) do
      local v = pr[f[2]] and strtrim(pr[f[2]]) or ""
      if v ~= "" then who[#who + 1] = f[1] .. v .. (f[3] or "") end
    end
    local other = not d.mine
    local effects
    if K.Auras then
      local lines = {}
      for _, e in ipairs(K.Auras:Of(d.raw, d.mine)) do
        local c = UI.CardHex(K.Auras.Color(e.kind))
        local nm = other and UI.Clean(e.name) or UI.Escape(e.name)
        local left = e.expires and (", " .. K.Auras.Left(e.expires) .. " left") or ""
        local note = e.note and ("  \"" .. (other and UI.Clean(e.note) or UI.Escape(e.note)) .. "\"") or ""
        lines[#lines + 1] = ("|T%s:16:16:0:0:64:64:5:59:5:59|t |cff%s%s|r%s%s"):format(tostring(e.icon), c, nm, left, note)
      end
      effects = #lines > 0 and table.concat(lines, "\n") or nil
    end
    -- Their house: its motto and history (yours from your house page)
    local houseName, houseText = strtrim(pr.house or ""), nil
    if houseName ~= "" then
      local h = d.mine and K:House() or nil
      local motto = strtrim((d.mine and h and h.motto or pr.houseMotto) or "")
      local hist = strtrim((d.mine and h and h.desc or pr.houseHistory) or "")
      local bits = {}
      if motto ~= "" then bits[#bits + 1] = "\"" .. (other and motto or UI.Escape(motto)) .. "\"" end
      -- The history lives on the house's own card, a click away
      if hist ~= "" then
        bits[#bits + 1] = "|cff" .. UI.Hex(K:Theme().subtle) .. "Click the house name above for its history and members.|r"
      end
      if #bits > 0 then houseText = table.concat(bits, "\n") end
    end
    text = Paragraphs({ { "Right now", effects }, { "At a glance", pr.glance }, { "Identity", table.concat(who, "  \194\183  ") },
      { "Motto", pr.motto }, { "House " .. (other and houseName or UI.Escape(houseName)), houseText },
      { "Boundaries", table.concat(bounds, "  \194\183  ") }, { "Out of character", pr.ooc } })
  elseif i == 2 then
    local other = not d.mine
    text = Paragraphs({ { "Personality", Rich(d.profile.personality, other) }, { "Traits", TraitLines(d.profile, other) } })
  elseif i == 3 then
    text = Rich(d.profile.appearance, not d.mine)
  elseif i == 4 then
    text = Rich(d.profile.history, not d.mine)
  else
    text = d.mine and self:ChronicleText() or "Shared Chronicle highlights will appear here once profile sharing arrives."
  end
  if not text or strtrim(text) == "" then text = "|cff" .. UI.Hex(K:Theme().subtle) .. "Nothing written here yet.|r" end
  self.body:SetText(text)
end

function V:ChronicleText()
  local entries, out = K:Chronicle().entries, {}
  for i = #entries, math.max(1, #entries - 9), -1 do
    local e = entries[i]
    out[#out + 1] = ("%s  %s\n%s"):format(Head(K.FormatDate(e.t)), e.place or "", e.title)
  end
  return #out > 0 and table.concat(out, "\n\n") or "No Chronicle entries yet."
end

function V:Present(data, unit, keepTab)
  self:Build()
  -- Another player's text keeps its colours but loses links, textures and other codes.
  if data.profile and not data.mine then
    local clean = {}
    for k, v in pairs(data.profile) do clean[k] = type(v) == "string" and UI.Clean(v) or v end
    data.profile = clean
  end
  self.data = data
  local f = self.frame
  local p = data.profile
  self.name:SetWordWrap(false)

  -- A roleplay name always has the character's own name after it, in grey.
  local rp = p and not data.mine and strtrim(UI.Clean(p.rpName)) or ""
  local char = data.mine and K:CharacterName() or (data.name or "")
  local text = data.name
  if rp ~= "" then
    local prefix = UI.Clean(p.prefix)
    text = prefix ~= "" and (prefix .. " " .. rp) or rp
  end
  local hasRP = rp ~= "" or (data.mine and p and strtrim(p.rpName or "") ~= "")
  if hasRP and char ~= "" and char:lower() ~= (text or ""):lower() then
    text = text .. " |cff" .. K.CHAR_NAME_HEX .. "(" .. char .. ")|r"
  end
  self.name:SetText(text)
  self.epithet:SetText(p and p.epithet ~= "" and p.epithet or " ")

  local houseName = p and strtrim(p.house or "") or ""
  if houseName ~= "" then
    local h = K.db.houses[houseName:lower()]
    local crest = (not data.mine and p.crest) or (h and h.crest) or "Interface\\Icons\\INV_Shield_05"
    self.crest:SetTexture(crest)
    self.crest:Show()
    self.house:SetText("of House " .. houseName)
    self.houseBtn:SetWidth(math.ceil(self.house:GetStringWidth()) + 26)
    self.houseBtn:Show()
  else
    self.crest:Hide()
    self.house:SetText("")
    self.houseBtn:Hide()
  end

  local status = p and p.status or nil
  self.gem:SetShown(status ~= nil)
  self.status:SetText(status and K.STATUS[status].label or "")
  if status then self.gem:SetStatus(status) end
  local stance = p and K.STANCES[p.stance or (data.mine and "duel" or "")]
  self.stance:Set(stance and stance.label or nil, stance and stance.color)
  local lv = K.Experience and K.Experience.Of(p)
  self.exp:Set(lv and lv.label or nil, lv and lv.color)
  -- The experience chip sits on the status line when there's room, and on the
  -- house line when there isn't, so it never runs off the edge of the card.
  self.exp:ClearAllPoints()
  local after = self.stance:IsShown() and self.stance or self.status
  local room = self.info:GetWidth() - 36
  local used = 20 + self.status:GetStringWidth() + (self.stance:IsShown() and (10 + self.stance:GetWidth()) or 0)
    + 8 + self.exp:GetWidth()
  if used <= room then
    self.exp:SetPoint("LEFT", after, "RIGHT", self.stance:IsShown() and 6 or 10, 0)
  elseif houseName ~= "" then
    self.exp:SetPoint("LEFT", self.house, "LEFT", math.ceil(self.house:GetStringWidth()) + 10, 0)
  else
    self.exp:SetPoint("LEFT", self.crest, "LEFT", 0, 0)
  end

  for label, key in pairs({ Pronouns = "pronouns", Age = "age", Height = "height", Home = "home" }) do
    local v = p and p[key] or ""
    self.facts[label]:SetText(v ~= "" and v or "|cff888888-|r")
  end

  local cur = p and p.currently or ""
  if cur ~= "" then self.currently:SetText("\"" .. cur .. "\"")
  elseif data.kinLine then self.currently:SetText(data.kinLine)
  else self.currently:SetText("") end

  -- The stage they've set out, and the palette to change yours
  self.stageLook = StageOf(p)
  self:PaintStage()
  self.palette:SetShown(data.mine and true or false)
  -- Their worn items around the stage
  local worn = K.Worn and K:ExtOn("inventory") and p and K.Worn.Of(p, data.mine) or {}
  self:PlaceWorn(worn, data.mine)

  -- Model (left alone on live refreshes so it doesn't jump while you type)
  if keepTab and f:IsShown() then
    -- keep current model
  elseif unit and UnitExists(unit) then
    self.model:Show(); self.stageEmpty:Hide()
    self.model:SetUnit(unit)
    self.model.facing = 0; self.model:SetFacing(0)
    self.stageNote:SetText("Drag to turn")
  else
    self.model:Hide(); self.stageEmpty:Show()
    self.stageNote:SetText("Stand near them to see their appearance.")
  end

  -- Glances along the foot of the stage, centred
  local list = (K.Persona and p) and K.Persona.Glances(p) or {}
  local n = #list
  for i, b in ipairs(self.glances) do
    local g = list[i]
    b.glance, b.other = g, not data.mine
    if g then
      K.Persona.SetIcon(b.icon, g.icon)
      b:ClearAllPoints()
      b:SetPoint("BOTTOM", self.stage, "BOTTOM", (i - (n + 1) / 2) * 38, 34)
      b:Show()
    else
      b:Hide()
    end
  end

  if self.cover then self.cover:Check(not data.mine and data.raw or nil) end

  f:Show()
  -- Opened on purpose (Preview, a link, a portrait): to the front, even if it was
  -- already open behind the journal. Live refreshes while you type leave it where it is.
  if not keepTab then f:Raise() end
  self.tabs:SetTabShown(CHRONICLE, data.mine and true or false)
  local tab = keepTab and self.tab or 1
  if tab == CHRONICLE and not data.mine then tab = 1 end
  self:ShowTab(tab)
  if K.Guide then C_Timer.After(0.3, function() if f:IsShown() then K.Guide:Maybe("viewer", V, f) end end) end
end

-- Worn items down the stage's left edge, head to toe with no gaps; past nine
-- they share out between both edges (the right one starts below the palette)
-- and get a little smaller to fit.
local TOKEN_TOP, TOKEN_FLOOR = 10, 112   -- clear of the stage top, and of the floor and glances
function V:PlaceWorn(worn, mine)
  local I = K.Items
  local list = {}
  for _, w in ipairs(I.WEAR) do
    if worn[w.key] then list[#list + 1] = { slot = w.key, def = worn[w.key] } end
  end
  local n = #list
  local h = self.stage:GetHeight()
  local left = n <= 9 and n or math.ceil(n / 2)
  local rightTop = TOKEN_TOP + (mine and 30 or 0)
  local rows = math.max(left, n - left, 1)
  local step = math.min(36, math.floor((h - rightTop - TOKEN_FLOOR) / rows))
  local size = math.min(30, step - 4)
  for i, b in ipairs(self.wornSlots) do
    local e = list[i]
    if e then
      b.slot, b.def, b.size = e.slot, e.def, size
      local q = e.def.quality or 1
      b.color = q ~= 1 and I.QualityColor(q) or nil
      b.icon:SetTexture(I.IconTexture(e.def.icon))
      b:SetSize(size, size)
      b:ClearAllPoints()
      if i <= left then b:SetPoint("TOPLEFT", 8, -TOKEN_TOP - (i - 1) * step)
      else b:SetPoint("TOPRIGHT", -8, -rightTop - (i - left - 1) * step) end
      b.paint(UI.Progress(b))
      b:Show()
    else
      b.def = nil
      b:Hide()
    end
  end
end

-- Paint the stage for the profile on show (the theme's look when there's none).
function V:PaintStage()
  local parts = self.stageParts
  if not parts then return end
  local t = K:Theme()
  local st = self.stageLook or StageOf(nil)
  local top, bottom, light = StageColors(st)
  if parts.backdrop.SetGradient and CreateColor then
    parts.backdrop:SetGradient("VERTICAL", CreateColor(bottom[1], bottom[2], bottom[3], 1), CreateColor(top[1], top[2], top[3], 1))
    parts.shade:SetGradient("VERTICAL", CreateColor(0, 0, 0, 0.5), CreateColor(0, 0, 0, 0))
  else
    parts.backdrop:SetVertexColor(top[1], top[2], top[3], 1)
    parts.shade:SetVertexColor(0, 0, 0, 0.35)
  end
  parts.spot:SetShown(st.spot)
  parts.spot:SetVertexColor(light[1], light[2], light[3], 0.42)
  if st.floor == "glow" then
    parts.pool:SetBlendMode("ADD")
    parts.pool:SetVertexColor(light[1], light[2], light[3], st.spot and 0.75 or 0.55)
    parts.pool:Show()
  elseif st.floor == "shadow" then
    parts.pool:SetBlendMode("BLEND")
    parts.pool:SetVertexColor(0, 0, 0, 0.6)
    parts.pool:Show()
  else
    parts.pool:Hide()
  end
  parts.floor:SetVertexColor(t.ui[1], t.ui[2], t.ui[3], 0.8)
  parts.edge.border:SetColor(unpack(t.chromeEdge))
end

-- Change your own stage: saved to your profile, shared, and shown at once.
local function SetStage(change)
  local p = K:Profile()
  local st = StageOf(p)
  change(st)
  p.stage = { bg = st.bg, c = st.c, spot = st.spot or nil, floor = st.floor }
  if V.data and V.data.mine then
    V.stageLook = StageOf(p)
    V:PaintStage()
  end
  K:Fire("PROFILE")
end

function V:StageMenu(owner)
  local st = StageOf(K:Profile())
  UI.Menu(owner, function(root)
    root:CreateTitle("Backdrop")
    for _, sc in ipairs(SCENES) do
      root:CreateRadio(sc.label, function() return StageOf(K:Profile()).bg == sc.key end,
        function() SetStage(function(x) x.bg, x.c = sc.key, nil end) end)
    end
    root:CreateRadio("Your own colour...", function() return StageOf(K:Profile()).bg == "custom" end, function()
      local before = K:Profile().stage and CopyTable(K:Profile().stage) or nil
      local c = st.c or StageColors(st)
      PickColor(c[1], c[2], c[3], function(r, g, b)
        SetStage(function(x) x.bg, x.c = "custom", { r, g, b } end)
      end, function()
        K:Profile().stage = before
        if V.data and V.data.mine then V.stageLook = StageOf(K:Profile()); V:PaintStage() end
        K:Fire("PROFILE")
      end)
    end)
    root:CreateDivider()
    root:CreateTitle("Light")
    root:CreateCheckbox("Spotlight", function() return StageOf(K:Profile()).spot end,
      function() SetStage(function(x) x.spot = not x.spot end) end)
    root:CreateDivider()
    root:CreateTitle("Floor")
    for _, fl in ipairs(FLOORS) do
      root:CreateRadio(fl.label, function() return StageOf(K:Profile()).floor == fl.key end,
        function() SetStage(function(x) x.floor = fl.key end) end)
    end
  end)
end

---------------------------------------------------------------------------
-- A house's own card: its crest, motto and history, and the members you
-- know of (each opens their profile). Opened from "of House X" on a profile.
-- Another house's details come from its members' shared profiles; your own
-- from your House page.
---------------------------------------------------------------------------
local HW, HH = 420, 540

-- The members of a house you know of: yours with your own recognition, any
-- other from the profiles you've seen.
local function HouseMembersOf(key)
  local out = {}
  if key == K:HouseKey() and K.HouseMembers then
    local recognised, claims = K:HouseMembers()
    for _, m in ipairs(recognised) do out[#out + 1] = m end
    for _, m in ipairs(claims) do m.claim = true; out[#out + 1] = m end
    return out
  end
  for _, reg in pairs(K.Registry) do
    local p = reg.profile
    if p and strtrim(p.house or ""):lower() == key and not K:IsIgnored(reg.name) then
      out[#out + 1] = { name = Ambiguate and Ambiguate(reg.name, "none") or reg.name, raw = reg.name, profile = p }
    end
  end
  table.sort(out, function(a, b) return a.name < b.name end)
  return out
end

-- The crest, motto and history to show: the profile you came from first,
-- then any member who has shared them.
local function HouseDetails(key, from, members)
  if key == K:HouseKey() then
    local h = K:House() or {}
    return h.crest, h.motto, h.desc, false
  end
  local crest, motto, hist
  local function take(p)
    if not p then return end
    crest = crest or p.crest
    if (not motto or motto == "") and p.houseMotto and p.houseMotto ~= "" then motto = p.houseMotto end
    if (not hist or hist == "") and p.houseHistory and p.houseHistory ~= "" then hist = p.houseHistory end
  end
  take(from)
  for _, m in ipairs(members) do take(m.profile) end
  return crest, motto and UI.Clean(motto), hist, true
end

function V:BuildHouse()
  if self.houseFrame then return self.houseFrame end
  local f = UI.Window("KinshipRPHouseCard", "House", HW, HH)
  self.houseFrame = f
  local desk = UI.Desk(f)
  desk:SetPoint("TOPLEFT", 1, -35)
  desk:SetPoint("BOTTOMRIGHT", -1, 1)
  local card = UI.Panel(f)
  card:SetPoint("TOPLEFT", 14, -48)
  card:SetPoint("BOTTOMRIGHT", -14, 14)
  local IW = HW - 28 - 36   -- the card's width, less 18 either side

  f.ring = UI.Circle(card, 66, "ARTWORK", 0)
  f.ring:SetPoint("TOPLEFT", 18, -18)
  f.crest = card:CreateTexture(nil, "ARTWORK", nil, 1)
  f.crest:SetSize(58, 58)
  f.crest:SetPoint("CENTER", f.ring)
  f.crest:SetTexCoord(0.08, 0.92, 0.08, 0.92)
  UI.Round(f.crest)
  UI:OnTheme(function(t) f.ring:SetVertexColor(t.ui[1], t.ui[2], t.ui[3], 1) end)
  f.title = UI.Text(card, "", "GameFontNormalLarge", "heading", IW - 82)
  f.title:SetPoint("TOPLEFT", f.ring, "TOPRIGHT", 14, -10)
  f.title:SetWordWrap(false)
  f.motto = UI.Text(card, "", "QuestFont", "accent", IW - 82)
  f.motto:SetPoint("TOPLEFT", f.title, "BOTTOMLEFT", 0, -6)
  f.motto:SetMaxLines(2)

  local div = UI.Divider(card, IW)
  div:SetPoint("TOPLEFT", 18, -98)
  local hs = UI.Section(card, "History")
  hs:SetPoint("TOPLEFT", 25, -112)
  f.history = UI.ReadArea(card, IW, 140, "QuestFont", "text")
  f.history:SetPoint("TOPLEFT", 18, -132)

  local ms = UI.Section(card, "Members you know of")
  ms:SetPoint("TOPLEFT", 25, -286)
  f.members = UI.List(card, IW, 120, 26, "Nobody yet. Members appear as you meet them.", function(row)
    row.name = UI.Text(row, "", "Body", "heading", 200)
    row.name:SetPoint("LEFT", 10, 0)
    row.name:SetWordWrap(false)
    row.sub = UI.Text(row, "", "Small", "subtle", 130)
    row.sub:SetPoint("RIGHT", -10, 0)
    row.sub:SetJustifyH("RIGHT")
    row.sub:SetWordWrap(false)
    row:SetScript("OnClick", function(self)
      local m = self.item
      if not m then return end
      if m.raw then V:ShowName(m.raw) elseif m.mine then V:ShowSelf() end
    end)
  end, { emptyIcon = K.Art("IconKin") })
  f.members:SetPoint("TOPLEFT", 18, -306)
  f.note = UI.Text(card, "", "Small", "subtle", IW)
  f.note:SetPoint("TOPLEFT", f.members, "BOTTOMLEFT", 2, -6)
  f.note:SetSpacing(2)
  return f
end

function V:ShowHouse(name, from)
  name = strtrim(name or "")
  if name == "" then return end
  local key = name:lower()
  local f = self:BuildHouse()
  local members = HouseMembersOf(key)
  local crest, motto, hist, other = HouseDetails(key, from, members)
  f:SetTitle("House " .. name)
  f.title:SetText("House " .. name)
  f.crest:SetTexture(crest or "Interface\\Icons\\INV_Shield_05")
  motto = strtrim(motto or "")
  f.motto:SetText(motto ~= "" and ("\"" .. (other and motto or UI.Escape(motto)) .. "\"") or "")
  hist = strtrim(hist or "")
  f.history:SetText(hist ~= "" and Rich(hist, other)
    or ("|cff" .. UI.Hex(K:Theme().subtle) .. "No history written yet.|r"))
  f.members:SetItems(members, function(row, m)
    local rp = m.profile and strtrim(UI.Clean(m.profile.rpName or "")) or ""
    -- On the light card: the roleplay name in the row's own ink (the gold of
    -- K.BothNames is for dark backgrounds), the character's name softer beside it.
    if rp ~= "" and m.name:lower() ~= rp:lower() then
      row.name:SetText(rp .. " |cff" .. UI.Hex(K:Theme().subtle) .. "(" .. m.name .. ")|r")
    else
      row.name:SetText(rp ~= "" and rp or m.name)
    end
    local sub = m.role or (m.claim and "Claims the name") or ""
    row.sub:SetText(sub)
    row.name:SetWidth(sub ~= "" and 200 or 320)   -- the whole row when there's nothing beside it
  end)
  f.note:SetText(other and "Anyone can write a house name into their profile, so these are the people who say they belong."
    or "Recognise who truly belongs on your House page.")
  f:Show()
  f:Raise()
end

function V:ShowSelf(keepTab)
  local p = K:Profile()
  self:Present({ name = K:DisplayName(p), profile = p, mine = true }, "player", keepTab)
end

local function KinLine(name)
  local e = K:KinFor(name)
  if not e then return nil end
  local m = e.met or {}
  return ("%s. You met in %s, at level %d."):format(K.RelationLabel(e.rel), m.place or "?", m.level or 0)
end

function V:ShowName(name, unit, keepTab)
  if not name then return end
  -- A unit token is only a hint: by the time a profile arrives it may point
  -- at someone else, or at you. Keep it only while it's still this player.
  if unit then
    local n = UnitExists(unit) and GetUnitName(unit, true)
    if not (n and K.Safe(n) and K.NameKey(n) == K.NameKey(name)) then unit = nil end
  end
  if K:IsMe(name) then return self:ShowSelf() end
  if not unit then
    for _, u in ipairs({ "target", "mouseover", "focus" }) do
      local n = UnitExists(u) and GetUnitName(u, true)
      if n and K.Safe(n) and n == name then unit = u break end
    end
  end
  local reg = K:ProfileOf(name)
  if not keepTab then K.Comm:Request(name, true) end
  local short = Ambiguate and Ambiguate(name, "none") or name
  self:Present({
    name = short, raw = name, unit = unit, key = K.NameKey(name),
    profile = reg and reg.profile,
    kinLine = KinLine(name),
    missing = "No roleplay profile has arrived from this player yet.\n\n" ..
      "If they use Kinship or another RP addon (such as Total RP 3, MyRolePlay or XRP), " ..
      "their profile appears here as soon as it arrives. Profiles can't travel inside dungeons and raids.",
  }, unit, keepTab)
end

function V:ShowUnit(unit)
  if not UnitExists(unit) or not UnitIsPlayer(unit) then return end
  if UnitIsUnit(unit, "player") then return self:ShowSelf() end
  local name = GetUnitName(unit, true)
  if K.Safe(name) then self:ShowName(name, unit) end
end

K:On("REGISTRY", function(key)
  local d = V.data
  if V.frame and V.frame:IsShown() and d and not d.mine and d.key == key then
    V:ShowName(d.raw, d.unit, true)
  end
end)

K:On("PROFILE", function()
  if V.frame and V.frame:IsShown() and V.data and V.data.mine then V:ShowSelf(true) end
end)

K:On("AURAS", function()
  if V.frame and V.frame:IsShown() and V.data and V.data.mine then V:ShowSelf(true) end
end)

K:On("WORN", function()
  if V.frame and V.frame:IsShown() and V.data and V.data.mine then V:ShowSelf(true) end
end)
