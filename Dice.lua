-- Kinship RP: roleplay dice. Rolls "NdM+K" expressions (1d20, 2d6+3, d100,
-- "1d20 1d4-1"), shows them in a dice tray with a short spin, and shares them
-- with your group, your target or everyone nearby (K.Net kind "dice").

local ADDON, ns = ...
local K = ns.K
local UI = K.UI
local Safe = K.Safe
local D = { history = {}, recent = {}, mod = 0 }
K.Dice = D

local DICE_ICON = "Interface\\Icons\\INV_Misc_Dice_01"
local DICE_COLOR = { 0.95, 0.76, 0.36 }
local CRIT_COLOR = { 0.40, 0.85, 0.48 }     -- a natural 20
local FUMBLE_COLOR = { 0.90, 0.36, 0.30 }   -- a natural 1
local QUICK = { 4, 6, 8, 10, 12, 20, 100 }
local MAX_TERMS, MAX_COUNT, MAX_SIDES, MAX_MOD = 6, 20, 1000, 999
local HISTORY_MAX = 40
local SPAM_LIMIT, SPAM_WINDOW = 4, 6        -- incoming rolls per sender per window (seconds)

D.SHARES = {
  { key = "group",  label = "Group" },
  { key = "target", label = "Target" },
  { key = "nearby", label = "Nearby" },
  { key = "self",   label = "Just me" },
}

local function S() return K.db.settings end

---------------------------------------------------------------------------
-- Parsing and rolling
---------------------------------------------------------------------------
-- "2d6+3" -> { groups = { { n = 2, d = 6, s = 1 } }, mod = 3 }.
-- Dice keep their sign (s = 1 or -1); plain numbers fold into mod.
function D.Parse(expr)
  if type(expr) ~= "string" then return nil, "Nothing to roll." end
  local s = strtrim(expr:lower())
  if s == "" then return nil, "Nothing to roll." end
  if s:find("[^%dd%+%-%s]") then return nil, "Use dice like 1d20, 2d6+3 or d100." end
  local groups, mod, pos, len = {}, 0, 1, #s
  while pos <= len do
    local _, stop, sign, count, isDie, num = s:find("^%s*([%+%-]?)%s*(%d*)(d?)(%d+)%s*", pos)
    if not stop then return nil, "Couldn't read \"" .. expr .. "\". Try 1d20 or 2d6+3." end
    local neg = sign == "-" and -1 or 1
    if isDie == "d" then
      local n, d = count == "" and 1 or tonumber(count), tonumber(num)
      if not n or n < 1 or n > MAX_COUNT then return nil, ("Roll between 1 and %d dice at a time."):format(MAX_COUNT) end
      if not d or d < 2 or d > MAX_SIDES then return nil, ("Dice need between 2 and %d sides."):format(MAX_SIDES) end
      groups[#groups + 1] = { n = n, d = d, s = neg }
      if #groups > MAX_TERMS then return nil, ("Up to %d kinds of dice in one roll."):format(MAX_TERMS) end
    else
      mod = mod + neg * (tonumber(count .. num) or 0)
    end
    pos = stop + 1
  end
  if #groups == 0 then return nil, "Add at least one die, like 1d20." end
  if math.abs(mod) > MAX_MOD then return nil, "That modifier is too large." end
  return { groups = groups, mod = mod }
end

-- Compact text for a parsed expression or a result: "1d20+1d4-1".
function D.Format(r)
  local out = {}
  for i, g in ipairs(r.groups) do
    local sign = g.s < 0 and "-" or (i > 1 and "+" or "")
    out[#out + 1] = sign .. g.n .. "d" .. g.d
  end
  local m = r.mod or 0
  if m > 0 then out[#out + 1] = "+" .. m elseif m < 0 then out[#out + 1] = tostring(m) end
  return table.concat(out)
end

function D.Evaluate(parsed, extra)
  local res = { groups = {}, mod = (parsed.mod or 0) + (tonumber(extra) or 0), total = 0 }
  res.mod = math.max(-MAX_MOD, math.min(MAX_MOD, res.mod))
  for _, g in ipairs(parsed.groups) do
    local r, sum = {}, 0
    for i = 1, g.n do r[i] = math.random(1, g.d); sum = sum + r[i] end
    res.groups[#res.groups + 1] = { n = g.n, d = g.d, s = g.s, r = r }
    res.total = res.total + g.s * sum
  end
  res.total = res.total + res.mod
  res.expr = D.Format(res)
  return res
end

-- The lowest and highest totals an expression can give (for the spin).
local function Range(r)
  local lo, hi = r.mod or 0, r.mod or 0
  for _, g in ipairs(r.groups) do
    if g.s > 0 then lo, hi = lo + g.n, hi + g.n * g.d else lo, hi = lo - g.n * g.d, hi - g.n end
  end
  return lo, hi
end

-- "crit" / "fumble" for a single d20, otherwise nil.
local function Natural(r)
  local g = #r.groups == 1 and r.groups[1]
  if not g or g.n ~= 1 or g.d ~= 20 or g.s ~= 1 or not g.r then return nil end
  if g.r[1] == 20 then return "crit" elseif g.r[1] == 1 then return "fumble" end
end
D.Natural = Natural

local function NaturalColor(r)
  local n = Natural(r)
  return n == "crit" and CRIT_COLOR or (n == "fumble" and FUMBLE_COLOR) or nil
end

-- "1d20 (17) + 1d4 (3) + 2"
function D.Breakdown(r)
  local parts = {}
  for i, g in ipairs(r.groups) do
    local shown = {}
    for j, v in ipairs(g.r or {}) do
      if j > 10 then shown[#shown + 1] = "..." break end
      shown[#shown + 1] = tostring(v)
    end
    local piece = g.n .. "d" .. g.d .. " (" .. table.concat(shown, ", ") .. ")"
    if i > 1 or g.s < 0 then piece = (g.s < 0 and "- " or "+ ") .. piece end
    parts[#parts + 1] = piece
  end
  local m = r.mod or 0
  if m > 0 then parts[#parts + 1] = "+ " .. m elseif m < 0 then parts[#parts + 1] = "- " .. (-m) end
  return table.concat(parts, " ")
end

---------------------------------------------------------------------------
-- Sharing
---------------------------------------------------------------------------
local function TargetName()
  if not UnitExists("target") or not UnitIsPlayer("target") or UnitIsUnit("target", "player") then return nil end
  local n = GetUnitName("target", true)
  if Safe(n) and type(n) == "string" and n ~= "" then return n end
end

local function Short(n) return Ambiguate and Ambiguate(n, "none") or n end

function D:Share()
  local s = K.db and S().diceShare
  for _, x in ipairs(self.SHARES) do if x.key == s then return s end end
  return "group"
end

-- channel, target  or  nil, reason (the roll then stays with you)
local function Channel(share, target)
  if share == "group" then
    if not IsInGroup() then return nil, "You're not in a group, so only you saw it." end
    return IsInRaid() and "RAID" or "PARTY"
  elseif share == "target" then
    local name = target or TargetName()
    if not name then return nil, "No player targeted, so only you saw it." end
    return "WHISPER", name
  elseif share == "nearby" then
    return "YELL"
  end
end

-- Who a roll went to, for the history and chat ("your group", "Anduin").
local function ShareLabel(channel, to)
  if channel == "RAID" then return "your raid"
  elseif channel == "PARTY" then return "your party"
  elseif channel == "WHISPER" then return Short(to)
  elseif channel == "YELL" then return "everyone nearby" end
  return nil
end

-- Roll an expression and share it. share: "group" | "target" | "nearby" | "self"
-- (defaults to the tray's choice). Returns the result, or nil and a reason.
function D:Roll(expr, share, mod, target, quiet)
  local parsed, err = D.Parse(expr)
  if not parsed then
    if not quiet then K:Print(err) end
    return nil, err
  end
  local res = D.Evaluate(parsed, mod)
  res.who, res.me, res.t = K:DisplayName(), true, time()
  share = share or self:Share()
  if share ~= "self" then
    local channel, to = Channel(share, target)
    if channel then
      if K.Net:Send("dice", {
        g = res.groups, m = res.mod, t = res.total, n = K:DisplayName(),
      }, channel, to) then
        res.to = ShareLabel(channel, to)
      else
        res.note = "Couldn't send it right now, so only you saw it."
      end
    else
      res.note = to
    end
  end
  self:Record(res)
  if not quiet then self:ChatLine(res) end
  return res
end

function D:Record(res)
  table.insert(self.history, 1, res)
  while #self.history > HISTORY_MAX do table.remove(self.history) end
  K:Fire("DICE", res)
end

function D:ChatLine(res)
  local frame = DEFAULT_CHAT_FRAME
  if not frame then return end
  local dice = UI.Hex(DICE_COLOR)
  local nat = NaturalColor(res)
  local total = ("|cff%s%d|r"):format(nat and UI.Hex(nat) or "ffffff", res.total)
  local who = res.me and "You roll" or ("|cff%s%s|r rolls"):format(dice, res.who)
  local tail = ""
  if res.me then
    if res.to then tail = (" |cff8c8c8c(shared with %s)|r"):format(res.to)
    elseif res.note then tail = " |cff8c8c8c(only you)|r" end
  end
  frame:AddMessage(("|T%s:14:14:0:0:64:64:5:59:5:59|t %s |cff%s%s|r: %s = %s%s"):format(
    DICE_ICON, who, dice, res.expr, D.Breakdown(res), total, tail), 0.92, 0.88, 0.78)
end

function D:Toast(res)
  local nat = Natural(res)
  UI.Toast({
    icon = DICE_ICON, round = true,
    title = res.who .. " rolls " .. res.expr,
    text = (nat == "crit" and "Natural 20!  " or (nat == "fumble" and "Natural 1.  " or "")) .. D.Breakdown(res),
    big = tostring(res.total), color = NaturalColor(res) or DICE_COLOR, duration = 6,
    onClick = function() D:Open() end,
  })
end

---------------------------------------------------------------------------
-- Receiving
---------------------------------------------------------------------------
-- Rebuild a received roll from scratch, trusting nothing but the numbers.
local function Validate(msg)
  if type(msg.g) ~= "table" or #msg.g == 0 or #msg.g > MAX_TERMS then return nil end
  local m = tonumber(msg.m) or 0
  if m ~= m or math.abs(m) > MAX_MOD then return nil end
  local res = { groups = {}, mod = math.floor(m), total = 0 }
  for i, g in ipairs(msg.g) do
    if type(g) ~= "table" or type(g.r) ~= "table" then return nil end
    local n, d = tonumber(g.n), tonumber(g.d)
    if not n or not d or n < 1 or n > MAX_COUNT or d < 2 or d > MAX_SIDES then return nil end
    n, d = math.floor(n), math.floor(d)
    if #g.r ~= n then return nil end
    local s = tonumber(g.s) == -1 and -1 or 1
    local r, sum = {}, 0
    for j = 1, n do
      local v = tonumber(g.r[j])
      if not v or v < 1 or v > d then return nil end
      r[j] = math.floor(v)
      sum = sum + r[j]
    end
    res.groups[i] = { n = n, d = d, s = s, r = r }
    res.total = res.total + s * sum
  end
  res.total = res.total + res.mod
  res.expr = D.Format(res)
  return res
end

local function WhoName(sender, claimed)
  local reg = K:ProfileOf(sender)
  local p = reg and reg.profile
  if p then
    local rp = strtrim(UI.Clean(p.rpName or ""))
    if rp ~= "" then
      local prefix = strtrim(UI.Clean(p.prefix or ""))
      return prefix ~= "" and (prefix .. " " .. rp) or rp
    end
  end
  if type(claimed) == "string" then
    local c = strtrim((UI.Clean(claimed):gsub("[\r\n]", " ")))
    if c ~= "" and #c <= 60 then return c end
  end
  return Short(sender)
end

local CHANNEL_LABEL = { PARTY = "your party", RAID = "your raid", WHISPER = "you", YELL = "everyone nearby" }

K.Net:On("dice", function(msg, sender, channel)
  local key = K.NameKey(sender)
  if not key then return end
  local now = GetTime()
  local r = D.recent[key]
  if not r or now - r.start > SPAM_WINDOW then r = { start = now, n = 0 }; D.recent[key] = r end
  r.n = r.n + 1
  if r.n > SPAM_LIMIT then return end

  local res = Validate(msg)
  if not res then return end
  res.who, res.sender, res.t = WhoName(sender, msg.n), sender, time()
  res.via = CHANNEL_LABEL[channel or ""]
  D:Record(res)
  if S().diceChat then D:ChatLine(res) end
  if S().diceToasts then D:Toast(res) end
end)

---------------------------------------------------------------------------
-- The dice tray
---------------------------------------------------------------------------
local W, H, PAD = 380, 578, 16
local INNER = W - 2 * PAD

-- A big number in the reading face, re-applied when fonts change.
local function BigNumber(parent, size)
  local fs = parent:CreateFontString(nil, "OVERLAY")
  fs:SetFontObject(UI.FONTS.Huge)
  UI:OnTheme(function()
    local face = UI.FONTS.Huge:GetFont()
    if face then fs:SetFont(face, size, "") end
  end)
  fs:SetJustifyH("LEFT")
  return fs
end

function D:Build()
  if self.frame then return end
  local f = UI.Window("KinshipRPDiceTray", "Dice", W, H)
  f:ClearAllPoints()
  f:SetPoint("CENTER", 320, 20)
  f.icon:SetTexture(DICE_ICON)
  f.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
  UI.Round(f.icon)
  self.frame = f

  -- Result card -------------------------------------------------------------
  local card = UI.Panel(f)
  card:SetPoint("TOPLEFT", PAD, -46)
  card:SetSize(INNER, 118)
  f.card = card
  card.ring = UI.Circle(card, 76, "ARTWORK", 0)
  card.ring:SetPoint("LEFT", 18, 0)
  card.disc = UI.Circle(card, 70, "ARTWORK", 1)
  card.disc:SetPoint("CENTER", card.ring)
  card.die = card:CreateTexture(nil, "ARTWORK", nil, 2)
  card.die:SetSize(60, 60)
  card.die:SetPoint("CENTER", card.ring)
  card.die:SetTexture(DICE_ICON)
  card.die:SetTexCoord(0.08, 0.92, 0.08, 0.92)
  UI.Round(card.die)
  card.expr = UI.Text(card, "", "Small", "subtle", INNER - 140)
  card.expr:SetPoint("TOPLEFT", card.ring, "TOPRIGHT", 18, 2)
  card.expr:SetWordWrap(false)
  card.total = BigNumber(card, 40)
  card.total:SetPoint("TOPLEFT", card.expr, "BOTTOMLEFT", -1, -4)
  card.breakdown = UI.Text(card, "", "Small", "text", INNER - 120)
  card.breakdown:SetPoint("TOPLEFT", card.total, "BOTTOMLEFT", 1, -4)
  card.breakdown:SetWordWrap(false)
  card.chip = UI.Chip(card, "Label")
  card.chip:SetPoint("TOPRIGHT", -12, -12)

  local function paintRing(p)
    local t = K:Theme()
    local c = card.flashColor or t.accent
    card.ring:SetVertexColor(UI.Mix({ t.accent[1], t.accent[2], t.accent[3], 0.55 }, { c[1], c[2], c[3], 1 }, p))
  end
  card.paintRing = paintRing
  UI:OnTheme(function(t)
    card.disc:SetVertexColor(unpack(t.panel))
    paintRing(UI.Progress(card.ring))
    D:PaintTotal()
  end)

  -- Quick dice --------------------------------------------------------------
  local y = -46 - 118 - 12
  local ql = UI.Text(f, "Quick dice", "Label", "deskSubtle")
  ql:SetPoint("TOPLEFT", PAD + 1, y)
  local qhint = UI.Text(f, "Shift-click to roll at once", "Label", "deskSubtle")
  qhint:SetPoint("TOPRIGHT", -PAD - 1, y)
  qhint:SetAlpha(0.8)
  local gap = 4
  local qw = math.floor((INNER - gap * (#QUICK - 1)) / #QUICK)
  for i, sides in ipairs(QUICK) do
    local b = UI.Button(f, "d" .. sides, qw, 30)
    b.label:SetFontObject(UI.FONTS.Body)
    b.label:SetPoint("LEFT", 2, 0)
    b.label:SetPoint("RIGHT", -2, 0)
    b:Paint()
    b:SetPoint("TOPLEFT", PAD + (i - 1) * (qw + gap), y - 15)
    b:SetScript("OnClick", function() D:QuickDie(sides) end)
    UI.Tooltip(b, "d" .. sides, "Click to set it in the expression (click again for another die).\nShift-click to roll one right away.")
  end

  -- Expression and modifier -------------------------------------------------
  y = y - 15 - 30 - 12
  local el = UI.Text(f, "Expression", "Label", "deskSubtle")
  el:SetPoint("TOPLEFT", PAD + 1, y)
  local EW = INNER - 126
  f.expr = UI.Edit(f, EW, 26, "desk", 60)
  f.expr:SetPoint("TOPLEFT", PAD, y - 14)
  f.expr:SetText("1d20")
  f.expr:SetScript("OnEnterPressed", function(self) self:ClearFocus(); D:TrayRoll() end)
  f.expr:SetScript("OnTextChanged", function(self, user) if user then D:SetError(nil) end end)

  local ml = UI.Text(f, "Modifier", "Label", "deskSubtle")
  ml:SetPoint("TOPLEFT", PAD + EW + 10 + 1, y)
  local minus = UI.Button(f, "-", 26, 26)
  minus:SetPoint("TOPLEFT", PAD + EW + 10, y - 14)
  f.modEdit = UI.Edit(f, 56, 26, "desk", 4)
  f.modEdit:SetPoint("LEFT", minus, "RIGHT", 4, 0)
  f.modEdit:SetJustifyH("CENTER")
  f.modEdit:SetTextInsets(2, 2, 0, 0)
  local plus = UI.Button(f, "+", 26, 26)
  plus:SetPoint("LEFT", f.modEdit, "RIGHT", 4, 0)
  local function ShowMod() f.modEdit:SetText(D.mod > 0 and ("+" .. D.mod) or tostring(D.mod)) end
  f.ShowMod = ShowMod
  local function Step(v)
    D.mod = math.max(-99, math.min(99, D.mod + v))
    ShowMod()
  end
  minus:SetScript("OnClick", function() Step(IsShiftKeyDown() and -5 or -1) end)
  plus:SetScript("OnClick", function() Step(IsShiftKeyDown() and 5 or 1) end)
  f.modEdit:SetScript("OnTextChanged", function(self, user)
    if not user then return end
    local v = tonumber((self:GetText() or ""):match("^%s*([%+%-]?%d+)%s*$") or "")
    if v then D.mod = math.max(-99, math.min(99, v)) end
  end)
  f.modEdit:SetScript("OnEditFocusLost", function() ShowMod() end)
  f.modEdit:EnableMouseWheel(true)
  f.modEdit:SetScript("OnMouseWheel", function(_, delta) Step(delta > 0 and 1 or -1) end)
  UI.Tooltip(f.modEdit, "Modifier", "Added to every roll from the tray. Scroll or use - and + (Shift for 5).")
  ShowMod()

  -- Share -------------------------------------------------------------------
  y = y - 14 - 26 - 12
  local sl = UI.Text(f, "Share with", "Label", "deskSubtle")
  sl:SetPoint("TOPLEFT", PAD + 1, y)
  f.share = UI.Segments(f, D.SHARES, INNER / #D.SHARES, function(key)
    S().diceShare = key
    if key ~= "target" then D.targetName = nil end
    D:UpdateHint()
  end)
  f.share:SetPoint("TOPLEFT", PAD, y - 14)
  f.hint = UI.Text(f, "", "Small", "deskSubtle", INNER)
  f.hint:SetPoint("TOPLEFT", PAD + 1, y - 14 - 24 - 8)
  f.hint:SetWordWrap(false)

  -- Roll --------------------------------------------------------------------
  y = y - 14 - 24 - 8 - 16 - 10
  f.roll = UI.Button(f, ("|T%s:16:16:0:0:64:64:5:59:5:59|t  Roll"):format(DICE_ICON), INNER, 32)
  f.roll.label:SetFontObject(UI.FONTS.Header)
  f.roll:Paint()
  f.roll:SetPoint("TOPLEFT", PAD, y)
  f.roll:SetScript("OnClick", function() D:TrayRoll() end)

  -- History -----------------------------------------------------------------
  y = y - 32 - 14
  local hl = UI.Text(f, "History", "Label", "deskSubtle")
  hl:SetPoint("TOPLEFT", PAD + 1, y)
  local clear = UI.Button(f, "Clear", 54, 18)
  clear:SetPoint("TOPRIGHT", -PAD, y + 3)
  clear:SetScript("OnClick", function() wipe(D.history); D:RefreshHistory() end)
  local listH = H + y - 14 - PAD
  f.list = UI.List(f, INNER, listH, 38, "No rolls yet. Yours, and the ones shared with you, gather here.",
    function(row)
      row.icon = row:CreateTexture(nil, "ARTWORK")
      row.icon:SetSize(24, 24)
      row.icon:SetPoint("LEFT", 6, 0)
      row.icon:SetTexture(DICE_ICON)
      row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
      UI.Round(row.icon)
      row.title = UI.Text(row, "", "Small", "heading", INNER - 120)
      row.title:SetPoint("TOPLEFT", row.icon, "TOPRIGHT", 8, 2)
      row.title:SetWordWrap(false)
      row.sub = UI.Text(row, "", "Label", "subtle", INNER - 120)
      row.sub:SetPoint("TOPLEFT", row.title, "BOTTOMLEFT", 0, -3)
      row.sub:SetWordWrap(false)
      row.total = UI.Text(row, "", "Title", "plain")
      row.total:SetPoint("RIGHT", -8, 0)
      row:SetScript("OnClick", function(self)
        local res = self.item
        if res and res.expr then f.expr:SetText(res.expr); D:SetError(nil) end
      end)
      row.onEnter = function(self)
        local res = self.item
        if not res then return end
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:SetText((res.me and "You" or res.who) .. " rolled " .. res.expr, 1, 0.82, 0)
        GameTooltip:AddLine(D.Breakdown(res) .. " = " .. res.total, 1, 1, 1, true)
        GameTooltip:AddLine(UI.Ago(res.t), 0.7, 0.7, 0.7)
        GameTooltip:AddLine("Click to use this expression again.", 0.45, 0.8, 0.75)
        GameTooltip:Show()
      end
    end, { emptyIcon = K.Art("IconNote") })
  f.list:SetPoint("TOPLEFT", PAD, y - 14)

  f:HookScript("OnShow", function() D:Refresh() end)
  f:HookScript("OnHide", function()
    D.targetName = nil
    if D.spinning then
      card:SetScript("OnUpdate", nil)
      D.spinning = false
      if D.pending then D:ShowResult(D.pending); D:ChatLine(D.pending); D.pending = nil end
    end
  end)
  f:RegisterEvent("PLAYER_TARGET_CHANGED")
  f:RegisterEvent("GROUP_ROSTER_UPDATE")
  f:SetScript("OnEvent", function() if f:IsShown() then D:UpdateHint() end end)

  self:ShowResult(nil)
end

-- Quick die: set "1dN", or add another of the same die.
function D:QuickDie(sides)
  if IsShiftKeyDown() then return self:TrayRoll("1d" .. sides) end
  local f = self.frame
  local parsed = D.Parse(f.expr:GetText() or "")
  local g = parsed and #parsed.groups == 1 and parsed.groups[1]
  local text
  if g and g.d == sides and g.s == 1 and g.n < MAX_COUNT then
    g.n = g.n + 1
    text = D.Format(parsed)
  else
    text = "1d" .. sides
  end
  f.expr:SetText(text)
  self:SetError(nil)
  if SOUNDKIT then PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON) end
end

function D:UpdateHint()
  local f = self.frame
  if not f then return end
  local share = self:Share()
  f.share:Select(share)
  local text
  if share == "group" then
    if IsInRaid() then text = "Kinship users in your raid see the roll."
    elseif IsInGroup() then text = "Kinship users in your party see the roll."
    else text = "You're not in a group, so only you will see it." end
  elseif share == "target" then
    local name = self.targetName or TargetName()
    text = name and ("Whispered to " .. Short(name) .. ", if they use Kinship.") or "Target a player to whisper them your roll."
  elseif share == "nearby" then
    text = "Kinship users nearby in this zone see the roll."
  else
    text = "Only you see the roll."
  end
  f.hint:SetText(text)
end

function D:SetError(err)
  local f = self.frame
  if not f then return end
  if err then
    f.card.breakdown:SetText(("|cff%s%s|r"):format(UI.CardHex(FUMBLE_COLOR), err))
  elseif self.shown then
    f.card.breakdown:SetText(D.Breakdown(self.shown))
  else
    f.card.breakdown:SetText("Pick a die, or type an expression.")
  end
end

function D:PaintTotal()
  local f = self.frame
  if not f then return end
  local nat = self.shown and not self.spinning and NaturalColor(self.shown)
  local c = nat and UI.OnCard(nat) or K:Theme().heading
  f.card.total:SetTextColor(c[1], c[2], c[3])
end

-- Show a result in the card (nil = the ready state).
function D:ShowResult(res)
  local card = self.frame.card
  self.shown = res
  if not res then
    card.expr:SetText("READY TO ROLL")
    card.total:SetText("-")
    card.chip:Set(nil)
    self:SetError(nil)
    self:PaintTotal()
    return
  end
  local who = res.me and "You rolled " or (res.who .. " rolled ")
  card.expr:SetText(who .. res.expr)
  card.total:SetText(res.total)
  local nat = Natural(res)
  if nat == "crit" then card.chip:Set("Natural 20", CRIT_COLOR)
  elseif nat == "fumble" then card.chip:Set("Natural 1", FUMBLE_COLOR)
  elseif res.me and res.to then card.chip:Set("To " .. res.to, K:Theme().accent)
  elseif res.me and res.note then card.chip:Set("Only you", K:Theme().subtle)
  else card.chip:Set(nil) end
  card.breakdown:SetText(res.note and ("|cff%s%s|r"):format(UI.CardHex(FUMBLE_COLOR), res.note) or D.Breakdown(res))
  self:PaintTotal()
  -- A flash of colour around the die as it lands
  card.flashColor = NaturalColor(res) or DICE_COLOR
  UI.SetProgress(card.ring, 1)
  card.paintRing(1)
  UI.Tween(card.ring, 0, 0.8, card.paintRing, UI.Ease.outSine)
end

-- Spin the number and the die for a moment, then land on the result.
function D:Animate(res)
  local card = self.frame.card
  local lo, hi = Range(res)
  local t, nextTick, dur = 0, 0, 0.75
  self.spinning, self.pending = true, res
  card.chip:Set(nil)
  card.expr:SetText("Rolling " .. res.expr .. "...")
  card.breakdown:SetText("")
  self:PaintTotal()
  if SOUNDKIT and SOUNDKIT.UI_BAG_SORTING_01 then PlaySound(SOUNDKIT.UI_BAG_SORTING_01) end
  card:SetScript("OnUpdate", function(frame, elapsed)
    t = t + elapsed
    if t < dur then
      local p = t / dur
      if card.die.SetRotation then card.die:SetRotation(UI.Ease.outQuart(p) * math.pi * 4) end
      if t >= nextTick then
        nextTick = t + 0.035 + 0.13 * p * p   -- slows as it settles
        card.total:SetText(math.random(lo, hi))
      end
    else
      frame:SetScript("OnUpdate", nil)
      if card.die.SetRotation then card.die:SetRotation(0) end
      D.spinning, D.pending = false, nil
      D:ShowResult(res)
      D:ChatLine(res)
      D:RefreshHistory()
      if SOUNDKIT then PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON) end
    end
  end)
end

function D:TrayRoll(expr)
  local f = self.frame
  if not f or self.spinning then return end
  f.expr:ClearFocus()
  f.modEdit:ClearFocus()
  local res, err = self:Roll(expr or f.expr:GetText(), self:Share(), self.mod, self.targetName, true)
  if not res then
    self:SetError(err)
    return
  end
  self:Animate(res)
end

local function FillHistory(row, res)
  local t = K:Theme()
  local sub = UI.Hex(t.subtle)
  local where
  if res.me then where = res.to and ("to " .. res.to) or "just you"
  else where = res.via and ("to " .. res.via) or nil end
  row.title:SetText((res.me and "You" or res.who) .. "  |cff" .. sub .. res.expr .. (where and ("  ·  " .. where) or "") .. "|r")
  row.sub:SetText(D.Breakdown(res))
  local nat = NaturalColor(res)
  local c = nat and UI.OnCard(nat) or t.heading
  row.total:SetText(res.total)
  row.total:SetTextColor(c[1], c[2], c[3])
  row.sel:SetShown(false)
end

function D:RefreshHistory()
  if not self.frame then return end
  self.frame.list:SetItems(self.history, FillHistory)
end

function D:Refresh()
  if not self.frame then return end
  self:UpdateHint()
  self.frame.ShowMod()
  if not self.spinning then self:RefreshHistory() end
end

-- Open the tray. targetName: roll for that player (the target bar's button).
function D:Open(targetName)
  self:Build()
  if targetName then
    self.targetName = targetName
    S().diceShare = "target"
  end
  if self.frame:IsShown() then self:Refresh() else self.frame:Show() end
end

function D:Toggle()
  if self.frame and self.frame:IsShown() then self.frame:Hide() else self:Open() end
end

K:On("DICE", function()
  if D.frame and D.frame:IsShown() and not D.spinning then D:RefreshHistory() end
end)

---------------------------------------------------------------------------
-- Settings, target bar and start-up
---------------------------------------------------------------------------
K:On("LOGIN", function()
  local s = K.db.settings
  if s.diceToasts == nil then s.diceToasts = true end
  if s.diceChat == nil then s.diceChat = true end
  if s.diceShare == nil then s.diceShare = "group" end
end)

K:RegisterSettings({ id = "dice", title = "Dice", order = 40, build = function(card)
  card:Toggle("Shared rolls as toasts", "A card at the top of the screen when someone shares a roll with you.", "diceToasts")
  card:Toggle("Shared rolls in chat", "A coloured line in your chat window for every roll shared with you.", "diceChat")
  card:Note("Roll from the dice tray, the target bar, or with /kin roll 2d6+3. Only Kinship users receive shared rolls, "
    .. "and anyone rolling too often is quietly ignored for a few seconds.")
  card:Button("Open the dice tray", function() D:Open() end, 160)
end })

K:RegisterTargetButton({
  id = "dice", icon = DICE_ICON, label = "Roll dice", order = 35,
  onClick = function(unit, name)
    local n = name
    if not n and unit and UnitExists(unit) then
      local g = GetUnitName(unit, true)
      if Safe(g) then n = g end
    end
    D:Open(n)
  end,
})
