-- Kinship RP: the language you speak in chat. A small pill sits on the top
-- edge of the chat edit box showing your language: click to cycle through the
-- ones you know, right-click to pick one. The game resets the language after
-- loading screens, so Kinship puts your choice back.

local ADDON, ns = ...
local K = ns.K
local UI = K.UI
local L = { pills = {} }
K.Language = L

local WHITE = "Interface\\Buttons\\WHITE8X8"

local function S() return K.db.settings end

-- Every chat edit box (one shared, or one per window in IM style).
local function EditBoxes()
  local out, seen = {}, {}
  local function add(eb) if eb and not seen[eb] then seen[eb] = true; out[#out + 1] = eb end end
  if DEFAULT_CHAT_FRAME and DEFAULT_CHAT_FRAME.editBox then add(DEFAULT_CHAT_FRAME.editBox) end
  for i = 1, (NUM_CHAT_WINDOWS or 10) do add(_G["ChatFrame" .. i .. "EditBox"]) end
  return out
end

-- { { name, id }, ... } for the languages this character can speak.
function L:Known()
  local out = {}
  if not GetNumLanguages then return out end
  for i = 1, GetNumLanguages() or 0 do
    local name, id = GetLanguageByIndex(i)
    if K.Safe(name) and name and id then out[#out + 1] = { name = name, id = id } end
  end
  return out
end

function L:Current()
  local eb = EditBoxes()[1]
  local id = eb and eb.languageID
  for _, lang in ipairs(self:Known()) do if lang.id == id then return lang end end
  local name, defID = GetDefaultLanguage and GetDefaultLanguage()
  return { name = name or "?", id = defID }
end

-- Changing languages mid-encounter risks locking chat; wait until it's over.
local function Blocked()
  local inside, kind = IsInInstance()
  return InCombatLockdown() and inside and (kind == "party" or kind == "raid")
end

function L:Set(id, remember)
  if Blocked() then return false end
  local lang
  for _, l in ipairs(self:Known()) do if l.id == id then lang = l end end
  if not lang then return false end
  for _, eb in ipairs(EditBoxes()) do
    eb.languageID = lang.id
    eb.language = lang.name
  end
  if remember ~= false then K.db.language[K:CharKey()] = lang.id end
  self:Update()
  return true
end

function L:Next()
  local known, cur = self:Known(), self:Current()
  if #known < 2 then return end
  for i, l in ipairs(known) do
    if l.id == cur.id then return self:Set(known[i % #known + 1].id) end
  end
  self:Set(known[1].id)
end

-- Put the saved language back (after a loading screen, or when the list changes).
function L:Restore()
  if not K.db or S().langRemember == false then return end
  local saved = K.db.language[K:CharKey()]
  if not saved then return end
  local cur = self:Current()
  if cur.id ~= saved then
    if not self:Set(saved, false) then
      -- No longer known (or blocked): fall back quietly to the default.
      self:Update()
    end
  end
end

---------------------------------------------------------------------------
-- The pill on the edit box
---------------------------------------------------------------------------
local function Pill(eb)
  local b = CreateFrame("Button", nil, eb)
  b:SetHeight(18)
  b:SetPoint("BOTTOMRIGHT", eb, "TOPRIGHT", -6, 2)
  b:SetFrameLevel(eb:GetFrameLevel() + 5)
  b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  b.bg = b:CreateTexture(nil, "BACKGROUND")
  b.bg:SetAllPoints()
  b.bg:SetTexture(WHITE)
  b.edge = UI.Border(b)
  b.bar = b:CreateTexture(nil, "ARTWORK")
  b.bar:SetTexture(WHITE)
  b.bar:SetWidth(2)
  b.bar:SetPoint("TOPLEFT")
  b.bar:SetPoint("BOTTOMLEFT")
  b.icon = b:CreateTexture(nil, "ARTWORK")
  b.icon:SetTexture(K.ICON)
  b.icon:SetSize(12, 12)
  b.icon:SetPoint("LEFT", 7, 0)
  b.text = UI.Text(b, "", "Label", "deskText")
  b.text:SetPoint("LEFT", b.icon, "RIGHT", 5, 0)
  local function paint(p)
    local t = K:Theme()
    b.bg:SetVertexColor(UI.Mix(t.chrome, t.btnHover, p))
    b.edge:SetColor(UI.Mix(t.chromeEdge, t.btnEdgeHover, p))
    b.bar:SetVertexColor(t.ui[1], t.ui[2], t.ui[3], 0.6 + 0.4 * p)
    b.text:SetAlpha(0.85 + 0.15 * p)
  end
  b:SetScript("OnEnter", function(self)
    UI.Tween(self, 1, 0.12, paint)
    local known, cur = L:Known(), L:Current()
    GameTooltip:SetOwner(self, "ANCHOR_TOPRIGHT")
    GameTooltip:SetText("Speaking " .. cur.name, 1, 0.82, 0)
    if #known > 1 then
      local nextName
      for i, l in ipairs(known) do if l.id == cur.id then nextName = known[i % #known + 1].name end end
      GameTooltip:AddLine("Click: switch to " .. (nextName or known[1].name), 0.85, 0.85, 0.85)
      GameTooltip:AddLine("Right-click: choose a language", 0.85, 0.85, 0.85)
    end
    GameTooltip:Show()
  end)
  b:SetScript("OnLeave", function(self) UI.Tween(self, 0, 0.15, paint); GameTooltip:Hide() end)
  b:SetScript("OnClick", function(self, button)
    if button == "RightButton" then
      UI.Menu(self, function(root)
        root:CreateTitle("Speak in")
        for _, l in ipairs(L:Known()) do
          root:CreateRadio(l.name, function() return L:Current().id == l.id end, function() L:Set(l.id) end)
        end
      end)
    else
      L:Next()
      if SOUNDKIT then PlaySound(SOUNDKIT.IG_CHARACTER_INFO_TAB) end
      if GameTooltip:IsOwned(self) then self:GetScript("OnEnter")(self) end
    end
  end)
  UI:OnTheme(function() paint(UI.Progress(b)) end)
  eb:HookScript("OnShow", function() L:Update() end)
  return b
end

function L:Update()
  if not K.db then return end
  local known = self:Known()
  local show = S().langSwitcher ~= false and #known > 1
  local cur = self:Current()
  for _, eb in ipairs(EditBoxes()) do
    local b = self.pills[eb]
    if show and not b then b = Pill(eb); self.pills[eb] = b end
    if b then
      b:SetShown(show)
      b.text:SetText(cur.name or "")
      b:SetWidth(math.ceil(b.text:GetStringWidth()) + 32)
    end
  end
end

---------------------------------------------------------------------------
-- Start-up and settings
---------------------------------------------------------------------------
K:On("LOGIN", function()
  K.db.language = K.db.language or {}
  if S().langSwitcher == nil then S().langSwitcher = true end
  if S().langRemember == nil then S().langRemember = true end
  local ev = CreateFrame("Frame")
  for _, e in ipairs({ "PLAYER_ENTERING_WORLD", "LOADING_SCREEN_DISABLED", "LANGUAGE_LIST_CHANGED", "PLAYER_REGEN_ENABLED" }) do
    pcall(ev.RegisterEvent, ev, e)
  end
  ev:SetScript("OnEvent", function(_, event)
    C_Timer.After(event == "PLAYER_REGEN_ENABLED" and 0.2 or 1, function() L:Restore(); L:Update() end)
  end)
  C_Timer.After(1, function() L:Restore(); L:Update() end)
end)

K:RegisterSettings({ id = "language", title = "Chat languages", order = 12, build = function(card)
  card:Toggle("Language switcher", "A small button on the chat box: click to change the language you speak.", {
    get = function() return S().langSwitcher ~= false end,
    set = function(v) S().langSwitcher = v; L:Update() end,
  })
  card:Toggle("Keep my language", "The game resets it after loading screens; Kinship puts your choice back.", {
    get = function() return S().langRemember ~= false end,
    set = function(v) S().langRemember = v; if v then L:Restore() end end,
  })
  local note = card:Note("", 14)
  card:OnRefresh(function()
    local known = L:Known()
    local names = {}
    for _, l in ipairs(known) do names[#names + 1] = l.name end
    note:SetText(#known > 1 and ("You speak " .. table.concat(names, ", ") .. ".")
      or "This character speaks only one language, so the switcher stays hidden.")
  end)
end })
