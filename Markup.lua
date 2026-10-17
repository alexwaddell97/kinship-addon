-- Kinship RP: rich text for profile writing. K.Markup:Render(text, ctx) turns
-- profile text into a string ready for a FontString. FontStrings can't change
-- size inline, so headings are set apart by colour and a short accent rule:
--   # Heading   ## Subheading   ### Minor heading      (one per line)
--   ---                                                 a divider line
--   *emphasis*                                          in the accent colour
--   {col:rrggbb}text{/col}                              coloured text
--   {icon:IconName:size} or {icon:fileID:size}          an icon that exists
-- Total RP 3's tags ({h1}..{/h1}, {h2}, {h3}, {p:c}, {col:r}, {icon:..},
-- {link*url*text}) are understood too, for imported or received text.
--
-- ctx (all optional): { other = true   -- another player's text: cleaned first
--                       style = nil | "desk" | "ink"   -- what it's printed on
--                       width = n }    -- divider width in pixels
-- Colours are kept readable on the surface they sit on: bright colours meant
-- for dark tooltips are deepened on cream cards, and very dark ones lifted
-- on dark panels.

local ADDON, ns = ...
local K = ns.K
local UI = K.UI
local M = {}
K.Markup = M

local WHITE = "Interface\\Buttons\\WHITE8X8"
local ICON_MIN, ICON_MAX, ICON_SIZE = 8, 64, 16
local CROP = ":0:0:64:64:5:59:5:59"

-- Total RP 3's one-letter colours ({col:r} and friends).
local LETTERS = { r = "ff0000", g = "00ff00", b = "0000ff", y = "ffff00", p = "ff00ff",
                  c = "00ffff", w = "ffffff", ["0"] = "000000", o = "ffaa00" }

-- Toolbar palette: mid tones that read well on cream and on dark panels.
M.PALETTE = {
  { label = "Crimson", hex = "b8323a" },
  { label = "Ember",   hex = "d2742c" },
  { label = "Gold",    hex = "c99a2e" },
  { label = "Forest",  hex = "3f8f4f" },
  { label = "Teal",    hex = "1f8c88" },
  { label = "Sky",     hex = "3f7fc4" },
  { label = "Violet",  hex = "8a54b8" },
  { label = "Rose",    hex = "c4588a" },
  { label = "Stone",   hex = "7d7d7d" },
}

---------------------------------------------------------------------------
-- Colour helpers
---------------------------------------------------------------------------
local function Byte(v) return math.max(0, math.min(255, math.floor(v * 255 + 0.5))) end
local function HexOf(r, g, b) return ("%02x%02x%02x"):format(Byte(r), Byte(g), Byte(b)) end
M.HexOf = HexOf

local function Fold(c) local a = c[4] or 1; return c[1] * a, c[2] * a, c[3] * a end

-- "light" (cream cards, paper) or "dark" (Enhanced panels, the window itself).
local function Surface(ctx)
  if ctx.style == "ink" then return "light" end
  if ctx.style == "desk" then return "dark" end
  return K:Theme().light and "light" or "dark"
end

-- Nudge a colour so it stays readable on the given surface.
local function Readable(hex, surface)
  local r, g, b = tonumber(hex:sub(1, 2), 16), tonumber(hex:sub(3, 4), 16), tonumber(hex:sub(5, 6), 16)
  if not (r and g and b) then return nil end
  r, g, b = r / 255, g / 255, b / 255
  local l = 0.299 * r + 0.587 * g + 0.114 * b
  if surface == "light" and l > 0.62 then
    local f = 0.50 / l
    r, g, b = r * f, g * f, b * f
  elseif surface == "dark" and l < 0.30 then
    local k = (0.42 - l) / (1 - l)
    r, g, b = r + (1 - r) * k, g + (1 - g) * k, b + (1 - b) * k
  end
  return HexOf(r, g, b)
end
M.Readable = Readable

-- Heading, accent and subtle colours for the surface.
local function Roles(ctx)
  local t = K:Theme()
  if ctx.style == "ink" then return UI.INK.inkHeading, UI.INK.inkAccent, UI.INK.inkSubtle end
  if ctx.style == "desk" then return t.deskHeading, t.deskAccent, t.deskSubtle end
  return t.heading, t.accent, t.subtle
end

-- A quiet line colour: the subtle colour, softened toward the surface.
local function DividerColor(ctx, surface)
  local _, _, subtle = Roles(ctx)
  local base = surface == "light" and { 0.93, 0.89, 0.81 } or { 0.07, 0.06, 0.05 }
  local p = 0.55 * (subtle[4] or 1)
  return base[1] + (subtle[1] - base[1]) * p, base[2] + (subtle[2] - base[2]) * p, base[3] + (subtle[3] - base[3]) * p
end

-- An inline rule: a tinted white texture (|T height:width ... r:g:b|t).
local function Rule(r, g, b, width, height)
  return ("|T%s:%d:%d:0:0:8:8:0:8:0:8:%d:%d:%d|t"):format(WHITE, height, width, Byte(r), Byte(g), Byte(b))
end
M.Swatch = function(hex, size)
  local r, g, b = tonumber(hex:sub(1, 2), 16) or 0, tonumber(hex:sub(3, 4), 16) or 0, tonumber(hex:sub(5, 6), 16) or 0
  return Rule(r / 255, g / 255, b / 255, size or 10, size or 10)
end

---------------------------------------------------------------------------
-- Icons: only ones that exist on this client
---------------------------------------------------------------------------
local macroSet, macroList

-- Every icon the macro picker offers (file IDs, sometimes names), in order.
function M:IconList()
  if macroList then return macroList end
  macroList, macroSet = {}, {}
  for _, fname in ipairs({ "GetMacroIcons", "GetMacroItemIcons" }) do
    local fn = rawget(_G, fname)
    if type(fn) == "function" then
      local t = {}
      local ok, r = pcall(fn, t)
      if ok and type(r) == "table" then t = r end
      for _, icon in ipairs(t) do
        if (type(icon) == "number" or type(icon) == "string") and not macroSet[icon] then
          macroSet[icon] = true
          if type(icon) == "string" then macroSet[icon:lower()] = true end
          macroList[#macroList + 1] = icon
        end
      end
    end
  end
  return macroList
end

local checked, probe = {}, nil

-- Icon name or file ID -> something SetTexture/|T accepts, or nil if it
-- doesn't exist on this client.
function M.IconTexture(spec)
  if type(spec) ~= "string" and type(spec) ~= "number" then return nil end
  spec = strtrim(tostring(spec))
  if spec == "" then return nil end
  if checked[spec] ~= nil then return checked[spec] or nil end
  local result = false
  local n = tonumber(spec)
  if n then
    M:IconList()
    if macroSet[n] then result = n end
  elseif #spec <= 80 and spec:find("^[%w_%-]+$") then
    local path = "Interface\\Icons\\" .. spec
    M:IconList()
    local getID = rawget(_G, "GetFileIDFromPath")
    if macroSet[spec:lower()] then
      result = path
    elseif type(getID) == "function" then
      local ok, id = pcall(getID, path)
      if ok and id then result = path end
    else
      probe = probe or UIParent:CreateTexture(nil, "BACKGROUND")
      probe:SetTexture(path)
      if probe.GetTextureFileID then
        if probe:GetTextureFileID() then result = path end
      else
        result = path
      end
    end
  end
  checked[spec] = result
  return result or nil
end

---------------------------------------------------------------------------
-- Rendering
---------------------------------------------------------------------------
-- Other players' text: drop links, textures and UI codes (UI.Clean), keep
-- colours, and show any other "|" literally.
local function Sanitise(text, other)
  text = tostring(text or ""):gsub("\r\n?", "\n"):gsub("[\001\002\003]", "")
  -- UI.Clean leaves only colours and |r as codes; every other pipe is escaped.
  if other then text = UI.Clean(text) end
  return text
end

-- Total RP 3 structure tags become Kinship lines.
local function Structure(s)
  s = s:gsub("{h(%d)[^}]*}(.-){/h%d}", function(n, inner)
    n = math.max(1, math.min(3, tonumber(n) or 1))
    return "\n" .. ("#"):rep(n) .. " " .. (inner:gsub("\n", " ")) .. "\n"
  end)
  s = s:gsub("{p:?%a?}", ""):gsub("{/p}", "\n")
  s = s:gsub("{img[^}]*}", "")
  s = s:gsub("{link%*[^*]*%*({icon:[^}]+})}", "%1")
  s = s:gsub("{link%*[^*]*%*([^}]*)}", "%1")
  s = s:gsub("{twitter%*[^*]*%*([^}]*)}", "%1"):gsub("{bsky%*[^*]*%*([^}]*)}", "%1")
  return s
end

local function Inline(s, accentHex, surface)
  -- Colour codes already in the text (other addons, pasted), made readable.
  s = s:gsub("|c%x%x(%x%x%x%x%x%x)", function(hex) return "|cff" .. (Readable(hex, surface) or hex) end)
  s = s:gsub("{col:(%x%x%x%x%x%x)}", function(hex) return "|cff" .. Readable(hex, surface) end)
  s = s:gsub("{col:(%w)}", function(l)
    local hex = LETTERS[l:lower()]
    return hex and ("|cff" .. Readable(hex, surface)) or ""
  end)
  s = s:gsub("{/col}", "|r")
  s = s:gsub("{icon:([^:}]+):?(%d*)}", function(spec, size)
    local tex = M.IconTexture(spec)
    if not tex then return "" end
    size = math.max(ICON_MIN, math.min(ICON_MAX, tonumber(size) or ICON_SIZE))
    return ("|T%s:%d:%d%s|t"):format(tostring(tex), size, size, CROP)
  end)
  s = s:gsub("%*%*([^%*\n]+)%*%*", "|cff" .. accentHex .. "%1|r")
  s = s:gsub("%*([^%*\n]+)%*", "|cff" .. accentHex .. "%1|r")
  return s
end

function M:Render(text, ctx)
  if ctx == true then ctx = { other = true } end
  ctx = type(ctx) == "table" and ctx or {}
  if type(text) ~= "string" or text == "" then return "" end
  local s = Sanitise(text, ctx.other)
  s = s:gsub("||", "\003")   -- escaped pipes stay out of the way until the end
  s = Structure(s)

  local surface = Surface(ctx)
  local head, accent, subtle = Roles(ctx)
  local headHex, accentHex, subHex = UI.Hex(head), UI.Hex(accent), UI.Hex(subtle)
  local ar, ag, ab = Fold(accent)
  local dr, dg, db = DividerColor(ctx, surface)
  local width = math.max(40, math.floor(ctx.width or 300))

  local out = {}
  local function Gap() if #out > 0 and out[#out] ~= "" then out[#out + 1] = "" end end
  for line in (s .. "\n"):gmatch("(.-)\n") do
    local hashes, title = line:match("^%s*(#+)%s*(%S.-)%s*$")
    if hashes then
      local level = math.min(3, #hashes)
      title = Inline(title, accentHex, surface)
      Gap()
      if level == 1 then
        out[#out + 1] = "|cff" .. headHex .. title .. "|r"
        out[#out + 1] = Rule(ar, ag, ab, 36, 2)
      elseif level == 2 then
        out[#out + 1] = "|cff" .. accentHex .. title .. "|r"
      else
        out[#out + 1] = "|cff" .. subHex .. title .. "|r"
      end
    elseif line:find("^%s*%-%-%-+%s*$") or line:find("^%s*___+%s*$") or line:find("^%s*%*%*%*+%s*$") then
      Gap()
      out[#out + 1] = Rule(dr, dg, db, width, 1)
      out[#out + 1] = ""
    else
      out[#out + 1] = Inline(line, accentHex, surface)
    end
  end
  s = table.concat(out, "\n")
  s = s:gsub("\n\n\n+", "\n\n"):gsub("^\n+", ""):gsub("\n+$", "")
  s = s:gsub("\003", "||")
  return s
end

-- Plain words without any markup (for one-line summaries).
function M:Strip(text)
  local s = Structure(tostring(text or ""))
  s = s:gsub("{/?col[^}]*}", ""):gsub("{icon:[^}]*}", "")
  s = s:gsub("^%s*#+%s*", ""):gsub("\n%s*#+%s*", "\n"):gsub("\n%s*%-%-%-+%s*", "\n")
  s = s:gsub("%*([^%*\n]+)%*", "%1")
  return s
end

-- A short guide to the syntax. accentHex: colour for the examples (a tooltip
-- teal by default, since this usually shows in a game tooltip).
function M:Help(accentHex)
  local a = "|cff" .. (accentHex or "5fc4b8")
  return table.concat({
    a .. "# Heading|r   a title for a section",
    a .. "## Subheading|r   a smaller title",
    a .. "---|r   a divider line across the page",
    a .. "*words*|r   emphasis, in the accent colour",
    a .. "{col:c94f4f}words{/col}|r   coloured words",
    a .. "{icon:INV_Misc_Note_01:18}|r   an icon, 8 to 64 pixels",
    " ",
    "Total RP 3 tags such as {h1}, {p:c} and {col:r} work too.",
  }, "\n")
end

---------------------------------------------------------------------------
-- Inserting into an edit box
---------------------------------------------------------------------------
-- Code-made changes don't count as typing, so tell the box's own handler,
-- which is what saves the text.
local function Commit(eb)
  local fn = eb:GetScript("OnTextChanged")
  if fn then K.Try("markup", fn, eb, true) end
end

local function Focus(eb) if not eb:HasFocus() then eb:SetFocus() end end

local function AtLineStart(eb)
  local pos = eb:GetCursorPosition() or 0
  if pos <= 0 then return true end
  return (eb:GetText() or ""):sub(pos, pos) == "\n"
end

local function Wrap(eb, before, after)
  Focus(eb)
  local pos = eb:GetCursorPosition() or 0
  eb:Insert(before .. after)
  eb:SetCursorPosition(pos + #before)
  Commit(eb)
end

local function InsertLine(eb, prefix)
  Focus(eb)
  eb:Insert((AtLineStart(eb) and "" or "\n") .. prefix)
  Commit(eb)
end

local function InsertBlock(eb, block)
  Focus(eb)
  eb:Insert((AtLineStart(eb) and "" or "\n") .. block .. "\n")
  Commit(eb)
end

local function InsertText(eb, text)
  Focus(eb)
  eb:Insert(text)
  Commit(eb)
end

-- The game's colour picker, for a colour outside the palette.
local pick, pickHooked
local function CustomColour(eb)
  local CPF = rawget(_G, "ColorPickerFrame")
  if not CPF or type(CPF.SetupColorPickerAndShow) ~= "function" then return end
  pick = { eb = eb, r = 0.72, g = 0.30, b = 0.30 }
  if not pickHooked then
    pickHooked = true
    CPF:HookScript("OnHide", function()
      local p = pick
      pick = nil
      if p and not p.cancelled then Wrap(p.eb, ("{col:%s}"):format(HexOf(p.r, p.g, p.b)), "{/col}") end
    end)
  end
  pcall(CPF.SetupColorPickerAndShow, CPF, {
    r = pick.r, g = pick.g, b = pick.b, hasOpacity = false,
    swatchFunc = function() if pick then pick.r, pick.g, pick.b = CPF:GetColorRGB() end end,
    cancelFunc = function() if pick then pick.cancelled = true end end,
  })
end

local function ColourMenu(owner, eb)
  UI.Menu(owner, function(root)
    root:CreateTitle("Colour the next words")
    for _, c in ipairs(M.PALETTE) do
      root:CreateButton(M.Swatch(c.hex, 10) .. "  " .. c.label, function() Wrap(eb, ("{col:%s}"):format(c.hex), "{/col}") end)
    end
    local CPF = rawget(_G, "ColorPickerFrame")
    if CPF and type(CPF.SetupColorPickerAndShow) == "function" then
      root:CreateDivider()
      root:CreateButton("Any colour...", function() CustomColour(eb) end)
    end
  end)
end

---------------------------------------------------------------------------
-- Icon picker: the macro icons (always valid), or an icon typed by name.
---------------------------------------------------------------------------
local PICK_W, PICK_H, COLS, CELL = 372, 432, 8, 41

function M:BuildPicker()
  if self.picker then return self.picker end
  -- Its own global name: IconPicker.lua's window is KinshipRPIconPicker.
  local f = UI.Window("KinshipRPMarkupIconPicker", "Choose an icon", PICK_W, PICK_H)
  f:SetFrameStrata("DIALOG")
  self.picker = f
  local desk = UI.Desk(f)
  desk:SetPoint("TOPLEFT", 1, -35)
  desk:SetPoint("BOTTOMRIGHT", -1, 1)

  f.size = 18
  f.sizes = UI.Segments(f, { { key = 14, label = "Small" }, { key = 18, label = "Med" },
    { key = 24, label = "Large" }, { key = 32, label = "Huge" } }, 48, function(k) f.size = k end)
  f.sizes:SetPoint("TOPLEFT", 16, -46)
  f.sizes:Select(18)
  UI.Tooltip(f.sizes, "Icon size", "How large the icon sits in your text.")

  f.name = UI.Edit(f, 136, 24, "desk", 80)
  f.name:SetPoint("TOPRIGHT", -16, -46)
  f.name.hint = UI.Text(f.name, "Icon name, then Enter", "Small", "deskSubtle")
  f.name.hint:SetPoint("LEFT", 8, 0)
  f.name:SetScript("OnTextChanged", function(self)
    self.hint:SetShown((self:GetText() or "") == "")
    f.status:SetText("")
  end)
  f.name:SetScript("OnEnterPressed", function(self)
    local spec = strtrim(self:GetText() or "")
    if M.IconTexture(spec) then
      f.Choose(spec)
    else
      f.status:SetText("|cffe6705aThere's no icon called \"" .. UI.Escape(spec) .. "\" on this client.|r")
    end
  end)
  f.status = UI.Text(f, "", "Small", "deskSubtle", PICK_W - 32)
  f.status:SetPoint("TOPLEFT", 17, -78)

  function f.Choose(spec)
    local fn = f.onPick
    f:Hide()
    if fn then K.Try("icon picker", fn, tostring(spec), f.size) end
  end

  f.list = UI.List(f, PICK_W - 32, PICK_H - 112, CELL, "No icons are available on this client.", function(row)
    row:EnableMouse(false)
    row.cells = {}
    for i = 1, COLS do
      local b = CreateFrame("Button", nil, row)
      b:SetSize(CELL - 4, CELL - 4)
      b:SetPoint("LEFT", (i - 1) * CELL, 0)
      b.icon = b:CreateTexture(nil, "ARTWORK")
      b.icon:SetPoint("TOPLEFT", 1, -1)
      b.icon:SetPoint("BOTTOMRIGHT", -1, 1)
      b.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
      b.edge = UI.Border(b)
      local function paint(p)
        local t = K:Theme()
        b.edge:SetColor(UI.Mix(t.deskFieldEdge, { t.ui[1], t.ui[2], t.ui[3], 1 }, p))
        b.icon:SetAlpha(0.85 + 0.15 * p)
      end
      b:SetScript("OnEnter", function(self) UI.Tween(self, 1, 0.1, paint) end)
      b:SetScript("OnLeave", function(self) UI.Tween(self, 0, 0.12, paint) end)
      b:SetScript("OnClick", function(self) if self.spec then f.Choose(self.spec) end end)
      UI:OnTheme(function() paint(UI.Progress(b)) end)
      row.cells[i] = b
    end
  end, { bare = true, emptyIcon = K.Art("IconNote") })
  f.list:SetPoint("TOPLEFT", 16, -96)
  return f
end

-- onPick(spec, size): spec is a file ID or an icon name, as a string.
function M:PickIcon(onPick)
  local f = self:BuildPicker()
  f.onPick = onPick
  f.status:SetText("")
  f.name:SetText("")
  if not f.loaded then
    f.loaded = true
    local rows, row = {}, nil
    for i, icon in ipairs(self:IconList()) do
      if (i - 1) % COLS == 0 then row = {}; rows[#rows + 1] = row end
      row[#row + 1] = icon
    end
    f.list:SetItems(rows, function(r, item)
      for i, b in ipairs(r.cells) do
        local icon = item[i]
        b.spec = icon
        b:SetShown(icon ~= nil)
        if icon then
          b.icon:SetTexture(type(icon) == "string" and ("Interface\\Icons\\" .. icon) or icon)
        end
      end
    end)
  end
  f:Show()
end

---------------------------------------------------------------------------
-- Formatting toolbar for any multi-line edit box (the Profile page attaches
-- one under its writing area).
---------------------------------------------------------------------------
function M:Toolbar(parent, editBox)
  local bar = CreateFrame("Frame", nil, parent)
  bar:SetHeight(22)
  local x = 0
  local function Add(label, w, title, body, fn)
    local b = UI.Button(bar, label, w, 22)
    b:SetPoint("LEFT", x, 0)
    x = x + w + 4
    b:SetScript("OnClick", function(self) fn(self) end)
    UI.Tooltip(b, title, body)
    return b
  end
  Add("H1", 30, "Heading", "Starts a line as a section title:\n# A title", function() InsertLine(editBox, "# ") end)
  Add("H2", 30, "Subheading", "A smaller title:\n## A subtitle", function() InsertLine(editBox, "## ") end)
  Add("Em", 32, "Emphasis", "Words between *stars* show in the accent colour.", function() Wrap(editBox, "*", "*") end)

  local col = Add("", 30, "Colour", "Colour the words you type next.", function(self) ColourMenu(self, editBox) end)
  for i, hex in ipairs({ "b8323a", "c99a2e", "1f8c88" }) do
    local s = col:CreateTexture(nil, "ARTWORK")
    s:SetTexture(WHITE)
    s:SetSize(4, 12)
    s:SetPoint("CENTER", (i - 2) * 5, 0)
    s:SetVertexColor(tonumber(hex:sub(1, 2), 16) / 255, tonumber(hex:sub(3, 4), 16) / 255, tonumber(hex:sub(5, 6), 16) / 255, 1)
  end

  Add("Icon", 40, "Icon", "Pick an icon to place in your text.", function()
    M:PickIcon(function(spec, size) InsertText(editBox, ("{icon:%s:%d}"):format(spec, size)) end)
  end)
  Add("Line", 38, "Divider", "A line across the page:\n---", function() InsertBlock(editBox, "---") end)
  Add("?", 22, "Formatting", M:Help(), function() end)
  bar:SetWidth(math.max(1, x - 4))
  return bar
end
