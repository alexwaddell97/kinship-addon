-- Kinship RP: name suggestions. As you type a name into a box (a letter's To,
-- Give an item, Add to Kin), a short list drops down with the people it could
-- be: your own characters first, then your Kin, the people you've written to
-- or heard from, and everyone in your Directory, most recently seen first.
-- It matches the start of any word of a character's name or roleplay name,
-- so "mel" finds Marian Melody (Forever characters have two names), and
-- picking one fills in the character's name, which is what the game needs.
--   K.Suggest(editBox, onPick, up)   onPick(name) after a pick, optional;
--                                    up: open above the box (for one near the bottom)
-- Up / Down move through the list; Enter or Tab picks; Esc closes it.

local ADDON, ns = ...
local K = ns.K
local UI = K.UI

local ROWS, ROW_H = 6, 30

local function Short(n) return K.Short(n, "") end
local function Clean(s) return strtrim(UI.Clean and UI.Clean(tostring(s or "")) or tostring(s or "")) end

-- Everyone worth suggesting: { name, rp, tag }, best first, each once.
function K:People()
  local out, seen = {}, {}
  local me = K.NameKey(K:MyName())
  local function Add(name, rp, tag)
    name = type(name) == "string" and strtrim(name) or ""
    local key = name ~= "" and K.NameKey(name)
    if not key or key == me or seen[key] or K:IsIgnored(name) then return end
    seen[key] = true
    out[#out + 1] = { name = Short(name), rp = Clean(rp), tag = tag }
  end
  local function RP(name)
    local e = K.Registry and K.Registry[K.NameKey(name) or ""]
    return e and e.profile and e.profile.rpName
  end
  -- Your own characters, by their whole name (each remembers it at login;
  -- the plain name is only the first of a Forever character's two)
  for _, p in pairs(K.db.profiles or {}) do
    if type(p) == "table" and p.full then
      local prof = p.list and p.list[p.active]
      Add(p.full, prof and prof.rpName, "Your character")
    end
  end
  -- Your Kin, by bond
  for _, e in pairs(K:KinList()) do
    if type(e) == "table" then Add(e.name, RP(e.name), (e.rel or "") ~= "" and K.RelationLabel(e.rel) or "Kin") end
  end
  -- Letters, newest first
  for _, l in ipairs(K:LetterBox()) do
    local who = l.dir == "in" and l.from or l.to
    Add(who, RP(who), "Letters")
  end
  -- The Directory, most recently seen first
  local reg = {}
  for _, e in pairs(K.Registry or {}) do
    if type(e) == "table" and e.name then reg[#reg + 1] = e end
  end
  table.sort(reg, function(a, b) return (a.t or 0) > (b.t or 0) end)
  for _, e in ipairs(reg) do Add(e.name, e.profile and e.profile.rpName, "Directory") end
  return out
end

-- Does a name match what's typed? The start of the whole name, or of any word in it.
local function Matches(text, q)
  text = text:lower()
  if text:sub(1, #q) == q then return true end
  for word in text:gmatch("[^%s%-]+") do
    if word:sub(1, #q) == q then return true end
  end
  return false
end

function K.Suggest(edit, onPick, up)
  local list = CreateFrame("Frame", nil, edit)
  list:SetFrameStrata("DIALOG")
  list:SetFrameLevel(edit:GetFrameLevel() + 50)
  if up then list:SetPoint("BOTTOMLEFT", edit, "TOPLEFT", 0, 2) else list:SetPoint("TOPLEFT", edit, "BOTTOMLEFT", 0, -2) end
  list:SetWidth(math.max(220, edit:GetWidth()))
  list:Hide()
  local bg = UI.Panel(list)
  bg:SetAllPoints()
  list.rows = {}
  for i = 1, ROWS do
    local row = CreateFrame("Button", nil, list)
    row:SetHeight(ROW_H)
    row:SetPoint("TOPLEFT", 4, -4 - (i - 1) * ROW_H)
    row:SetPoint("RIGHT", -4, 0)
    row.hi = row:CreateTexture(nil, "BACKGROUND")
    row.hi:SetAllPoints()
    row.name = UI.Text(row, "", "Body", "text")
    row.name:SetPoint("TOPLEFT", 8, -3)
    row.name:SetPoint("RIGHT", -8, 0)
    row.name:SetWordWrap(false)
    row.sub = UI.Text(row, "", "Small", "subtle")
    row.sub:SetPoint("TOPLEFT", row.name, "BOTTOMLEFT", 0, -1)
    row.sub:SetPoint("RIGHT", -8, 0)
    row.sub:SetWordWrap(false)
    row:SetScript("OnEnter", function(self) list:Select(self.index) end)
    row:SetScript("OnClick", function(self) list:Pick(self.index) end)
    list.rows[i] = row
  end

  function list:Paint()
    local t = K:Theme()
    for i, row in ipairs(self.rows) do
      local h = t.hover or { 1, 1, 1, 0.08 }
      row.hi:SetColorTexture(h[1], h[2], h[3], i == self.sel and (h[4] or 0.08) * 2 or 0)
    end
  end
  UI:OnTheme(function() list:Paint() end)

  function list:Select(i)
    self.sel = i
    self:Paint()
  end

  function list:Pick(i)
    local p = self.found and self.found[i or self.sel]
    if not p then return false end
    self.picking = true
    edit:SetText(p.name)
    edit:SetCursorPosition(#p.name)
    self.picking = false
    self:Hide()
    if onPick then onPick(p.name) end
    return true
  end

  function list:Update()
    if self.picking then return end
    local q = strtrim(edit:GetText() or ""):lower()
    if q == "" or not edit:HasFocus() then self:Hide() return end
    local found = {}
    for _, p in ipairs(K:People()) do
      if Matches(p.name, q) or (p.rp ~= "" and Matches(p.rp, q)) then
        found[#found + 1] = p
        if #found >= ROWS then break end
      end
    end
    -- Nothing to add when the only match is exactly what's typed
    if #found == 0 or (#found == 1 and found[1].name:lower() == q) then self:Hide() return end
    self.found = found
    for i, row in ipairs(self.rows) do
      local p = found[i]
      row.index = i
      if p then
        local rp = p.rp ~= "" and p.rp:lower() ~= p.name:lower() and p.rp or nil
        row.name:SetText(rp and (rp .. "  |cff" .. UI.Hex(K:Theme().subtle) .. p.name .. "|r") or p.name)
        row.sub:SetText(p.tag)
        row:Show()
      else
        row:Hide()
      end
    end
    self:SetHeight(#found * ROW_H + 8)
    self:Select(1)
    self:Show()
  end

  edit:HookScript("OnTextChanged", function(_, user) if user then list:Update() end end)
  edit:HookScript("OnEditFocusLost", function() C_Timer.After(0.15, function() list:Hide() end) end)
  edit:HookScript("OnArrowPressed", function(_, key)
    if not (list:IsShown() and list.found) then return end
    local n = #list.found
    if key == "DOWN" then list:Select((list.sel or 0) % n + 1)
    elseif key == "UP" then list:Select(((list.sel or 2) - 2) % n + 1) end
  end)
  edit:HookScript("OnTabPressed", function() if list:IsShown() then list:Pick() end end)
  -- Enter picks the highlighted name, before the box does whatever Enter does
  local enter = edit:GetScript("OnEnterPressed")
  edit:SetScript("OnEnterPressed", function(self, ...)
    if list:IsShown() and list:Pick() then return end
    if enter then return enter(self, ...) end
  end)
  local escape = edit:GetScript("OnEscapePressed")
  edit:SetScript("OnEscapePressed", function(self, ...)
    if list:IsShown() then list:Hide() return end
    if escape then return escape(self, ...) end
  end)
  return list
end
