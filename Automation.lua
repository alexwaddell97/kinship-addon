-- Kinship RP: automation. Rules that change your status, profile or war
-- stance when something happens (entering a dungeon, mounting up, joining a
-- group...), and optionally switch it back when that moment passes, unless
-- you've changed it yourself in the meantime.
--
-- K.db.automation = {
--   rules = { { id, enabled, cond, action, value, restore }, ... }   -- account-wide
--   state = { [charGUID] = { [ruleId] = { prev = value } } }         -- which rules are in effect
-- }

local ADDON, ns = ...
local K = ns.K
local UI = K.UI
local A = {}
K.Automation = A

local ICONS = "Interface\\Icons\\"

-- Conditions, in the order the editor shows them.
A.CONDITIONS = {
  { key = "instance", short = "Dungeon or raid", long = "In a dungeon or raid",               icon = ICONS .. "INV_Misc_Key_03" },
  { key = "pvp",      short = "Battleground",    long = "In a battleground, arena or war zone", icon = ICONS .. "INV_BannerPVP_02" },
  { key = "hostile",  short = "Enemy land",      long = "In enemy territory",                 icon = ICONS .. "Ability_DualWield" },
  { key = "city",     short = "City or inn",     long = "Resting in a city or inn",           icon = ICONS .. "Spell_Nature_Sleep" },
  { key = "mounted",  short = "Mounted",         long = "While mounted",                      icon = ICONS .. "Ability_Mount_RidingHorse", quiet = true },
  { key = "combat",   short = "In combat",       long = "In combat",                          icon = ICONS .. "Ability_Warrior_OffensiveStance", quiet = true },
  { key = "group",    short = "In a group",      long = "In a group",                         icon = ICONS .. "INV_Misc_GroupNeedMore" },
  { key = "raid",     short = "In a raid",       long = "In a raid group",                    icon = ICONS .. "Spell_Holy_PrayerOfHealing" },
}
local COND = {}
for _, c in ipairs(A.CONDITIONS) do COND[c.key] = c end

A.ACTIONS = {
  { key = "status",  label = "Status",     verb = "Changes your status" },
  { key = "profile", label = "Profile",    verb = "Switches your profile" },
  { key = "stance",  label = "War stance", verb = "Changes your war stance" },
}
local ACTION = {}
for _, a in ipairs(A.ACTIONS) do ACTION[a.key] = a end

---------------------------------------------------------------------------
-- Reading the world
---------------------------------------------------------------------------
local inCombat = false

local function ZonePvP()
  if not GetZonePVPInfo then return nil end
  local ok, kind = pcall(GetZonePVPInfo)
  return ok and K.Safe(kind) and kind or nil
end

local TESTS = {
  instance = function()
    local inside, kind = IsInInstance()
    return inside and (kind == "party" or kind == "raid" or kind == "scenario") or false
  end,
  pvp = function()
    local inside, kind = IsInInstance()
    if inside and (kind == "pvp" or kind == "arena") then return true end
    local z = ZonePvP()
    return z == "combat" or z == "arena"
  end,
  hostile = function() return ZonePvP() == "hostile" end,
  city = function() return IsResting() and true or false end,
  mounted = function() return IsMounted() and true or false end,
  combat = function() return inCombat or (UnitAffectingCombat("player") and true or false) end,
  group = function() return IsInGroup() and true or false end,
  raid = function() return IsInRaid() and true or false end,
}

function A:Test(cond)
  local fn = TESTS[cond]
  if not fn then return false end
  local ok, v = K.Try("automation", fn)
  return ok and v and true or false
end

---------------------------------------------------------------------------
-- Doing things
---------------------------------------------------------------------------
local function Current(action)
  local p = K:Profile()
  if action == "status" then return p.status
  elseif action == "profile" then return K:MyProfiles().active
  elseif action == "stance" then return p.stance or "duel" end
end

local function Valid(action, value)
  if action == "status" then return K.STATUS[value or ""] ~= nil
  elseif action == "stance" then return K.STANCES[value or ""] ~= nil
  elseif action == "profile" then return value ~= nil and K:MyProfiles().list[value] ~= nil end
  return false
end

local function Apply(action, value)
  if not Valid(action, value) or Current(action) == value then return false end
  if action == "status" then K:SetStatus(value)
  elseif action == "profile" then K:SwitchProfile(value)
  elseif action == "stance" then K:SetStance(value) end
  return true
end

-- The value a rule sets, as a label and colour.
function A:ValueLabel(action, value)
  if action == "status" then
    local s = K.STATUS[value or ""]
    return s and s.label or "?", s and s.color
  elseif action == "stance" then
    local s = K.STANCES[value or ""]
    return s and s.label or "?", s and s.color
  end
  return value and ("\"" .. value .. "\"") or "No profile chosen", K:Theme().accent
end

local function Notify(rule, value, back)
  local c = COND[rule.cond]
  if not c or c.quiet or K.db.settings.autoNotify == false then return end
  local label = A:ValueLabel(rule.action, value)
  UI.Toast({ icon = c.icon, round = true, duration = 3,
    title = back and "Back to how it was" or c.long,
    text = ("%s: %s"):format(ACTION[rule.action] and ACTION[rule.action].label or "", label) })
end

function A:Rules() return K.db.automation.rules end

function A:State()
  local key = K:CharKey()
  local st = K.db.automation.state
  st[key] = st[key] or {}
  return st[key]
end

function A:IsActive(rule) return K.db and K.db.automation and self:State()[rule.id] ~= nil end

function A:Evaluate()
  if not K.db or not K.db.automation then return end
  local state = self:State()
  local known = {}
  for _, rule in ipairs(self:Rules()) do
    known[rule.id] = true
    local on = rule.enabled and self:Test(rule.cond)
    local st = state[rule.id]
    if on and not st then
      state[rule.id] = { prev = Current(rule.action) }
      if Apply(rule.action, rule.value) then Notify(rule, rule.value) end
    elseif not on and st then
      state[rule.id] = nil
      -- Only switch back if nobody changed it since the rule did.
      if rule.restore and st.prev and Current(rule.action) == rule.value then
        if Apply(rule.action, st.prev) then Notify(rule, st.prev, true) end
      end
    end
  end
  for id in pairs(state) do if not known[id] then state[id] = nil end end
  if self.list and self.list:IsVisible() then self:RefreshList() end
end

local queued
function A:Queue(delay)
  if queued then return end
  queued = true
  C_Timer.After(delay or 0.2, function() queued = false; A:Evaluate() end)
end

function A:Save(rule)
  for i, r in ipairs(self:Rules()) do
    if r.id == rule.id then self:Rules()[i] = rule; self:Evaluate(); self:RefreshList(); return end
  end
  table.insert(self:Rules(), rule)
  self:Evaluate()
  self:RefreshList()
end

function A:Delete(rule)
  for i, r in ipairs(self:Rules()) do
    if r.id == rule.id then table.remove(self:Rules(), i) break end
  end
  self:State()[rule.id] = nil
  self:RefreshList()
end

---------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------
K:On("LOGIN", function()
  K.db.automation = K.db.automation or {}
  K.db.automation.rules = K.db.automation.rules or {}
  K.db.automation.state = K.db.automation.state or {}
  if K.db.settings.autoNotify == nil then K.db.settings.autoNotify = true end

  local ev = CreateFrame("Frame")
  for _, e in ipairs({ "PLAYER_ENTERING_WORLD", "ZONE_CHANGED_NEW_AREA", "ZONE_CHANGED", "ZONE_CHANGED_INDOORS",
                       "PLAYER_UPDATE_RESTING", "GROUP_ROSTER_UPDATE", "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED" }) do
    pcall(ev.RegisterEvent, ev, e)
  end
  -- Mounting: the modern event, or the player's auras on older builds.
  if not pcall(ev.RegisterEvent, ev, "PLAYER_MOUNT_DISPLAY_CHANGED") then
    pcall(ev.RegisterUnitEvent, ev, "UNIT_AURA", "player")
  end
  ev:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_REGEN_DISABLED" then
      inCombat = true
      A:Evaluate()
    elseif event == "PLAYER_REGEN_ENABLED" then
      inCombat = false
      A:Queue(0.5)
    elseif event == "PLAYER_ENTERING_WORLD" then
      A:Queue(1.5)
    else
      A:Queue(0.2)
    end
  end)
  A:Queue(2)
end)

---------------------------------------------------------------------------
-- Rule editor (a pop-over card on the journal)
---------------------------------------------------------------------------
local MW, MH = 440, 404
local IW = MW - 32
local TILE_W, TILE_H = 96, 52

local function Tile(parent, c, onClick)
  local b = CreateFrame("Button", nil, parent)
  b:SetSize(TILE_W, TILE_H)
  b.key = c.key
  b.bg = b:CreateTexture(nil, "BACKGROUND")
  b.bg:SetAllPoints()
  b.bg:SetTexture("Interface\\Buttons\\WHITE8X8")
  b.edge = UI.Border(b)
  b.icon = b:CreateTexture(nil, "ARTWORK")
  b.icon:SetSize(22, 22)
  b.icon:SetPoint("TOP", 0, -7)
  b.icon:SetTexture(c.icon)
  b.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
  UI.Round(b.icon)
  b.label = UI.Text(b, c.short, "Small", "text", TILE_W - 8)
  b.label:SetPoint("BOTTOM", 0, 7)
  b.label:SetJustifyH("CENTER")
  b.label:SetWordWrap(false)
  local function paint(p)
    local t = K:Theme()
    local a = t.accent
    if b.selected then
      b.bg:SetVertexColor(a[1], a[2], a[3], 0.16)
      b.edge:SetColor(a[1], a[2], a[3], 0.9)
    else
      local h = t.hover
      b.bg:SetVertexColor(h[1], h[2], h[3], (h[4] or 1) * 1.6 * p)
      b.edge:SetColor(UI.Mix(t.panelEdge, { a[1], a[2], a[3], 0.6 }, p))
    end
    b.icon:SetDesaturated(not b.selected and p < 0.5)
    b.label:SetTextColor(unpack((b.selected or p > 0.5) and t.heading or t.text))
  end
  function b:Paint() paint(UI.Progress(self)) end
  b:SetScript("OnEnter", function(self) UI.Tween(self, 1, 0.12, paint) end)
  b:SetScript("OnLeave", function(self) UI.Tween(self, 0, 0.15, paint) end)
  b:SetScript("OnClick", function(self)
    if SOUNDKIT then PlaySound(SOUNDKIT.IG_CHARACTER_INFO_TAB) end
    onClick(self.key)
  end)
  UI:OnTheme(function() b:Paint() end)
  return b
end

function A:BuildEditor()
  if self.editor then return self.editor end
  local parent = (K.Journal and K.Journal.frame) or UIParent
  local ov = UI.Modal(parent, MW, MH, function() A.editor:Hide() end)
  self.editor = ov
  local card = ov.card

  card.title = UI.Section(card, "New rule")
  card.title:SetPoint("TOPLEFT", 21, -15)

  local when = UI.Text(card, "When", "Label", "subtle")
  when:SetPoint("TOPLEFT", 17, -44)
  card.tiles = {}
  for i, c in ipairs(A.CONDITIONS) do
    local col, row = (i - 1) % 4, math.floor((i - 1) / 4)
    local t = Tile(card, c, function(key) A.draft.cond = key; A:PaintEditor() end)
    t:SetPoint("TOPLEFT", 16 + col * (TILE_W + 8), -60 - row * (TILE_H + 8))
    card.tiles[i] = t
  end

  local doThis = UI.Text(card, "Do this", "Label", "subtle")
  doThis:SetPoint("TOPLEFT", 17, -184)
  card.action = UI.Segments(card, A.ACTIONS, IW / 3, function(key)
    A.draft.action = key
    if not Valid(key, A.draft.value) then
      A.draft.value = (key == "status" and "ooc") or (key == "stance" and "none") or nil
    end
    A:PaintEditor()
  end)
  card.action:SetPoint("TOPLEFT", 16, -200)

  card.valueLabel = UI.Text(card, "", "Label", "subtle")
  card.valueLabel:SetPoint("TOPLEFT", 17, -236)

  local sitems = {}
  for _, k in ipairs(K.STATUS_ORDER) do sitems[#sitems + 1] = { key = k, label = K.STATUS[k].label, color = K.STATUS[k].color } end
  card.status = UI.Segments(card, sitems, IW / 3, function(key) A.draft.value = key; A:PaintEditor() end)
  card.status:SetPoint("TOPLEFT", 16, -252)
  local witems = {}
  for _, k in ipairs(K.STANCE_ORDER) do witems[#witems + 1] = { key = k, label = K.STANCES[k].label, color = K.STANCES[k].color } end
  card.stance = UI.Segments(card, witems, IW / 3, function(key) A.draft.value = key; A:PaintEditor() end)
  card.stance:SetPoint("TOPLEFT", 16, -252)
  card.profile = UI.Button(card, "", 220, 24)
  card.profile:SetPoint("TOPLEFT", 16, -252)
  card.profile:SetScript("OnClick", function(self)
    UI.Menu(self, function(root)
      root:CreateTitle("Switch to")
      for _, name in ipairs(K:ProfileNames()) do
        root:CreateRadio(name, function() return A.draft.value == name end, function() A.draft.value = name; A:PaintEditor() end)
      end
    end)
  end)
  card.profileNote = UI.Text(card, "Profiles belong to this character.", "Small", "subtle", IW - 232)
  card.profileNote:SetPoint("LEFT", card.profile, "RIGHT", 12, 0)

  card.restore = UI.Toggle(card, "Switch back afterwards",
    "When the moment passes, return to what you had before, unless you've changed it yourself.",
    function() return A.draft and A.draft.restore end, function(v) A.draft.restore = v end, IW, true)
  card.restore:SetPoint("TOPLEFT", 16, -292)

  card.save = UI.Button(card, "Save rule", 120, 28)
  card.save:SetPoint("BOTTOMRIGHT", -16, 14)
  card.save:SetScript("OnClick", function()
    local d = A.draft
    if not d or not Valid(d.action, d.value) then return end
    ov:Hide()
    A:Save(d)
  end)
  card.cancel = UI.Button(card, "Cancel", 96, 28)
  card.cancel:SetPoint("RIGHT", card.save, "LEFT", -8, 0)
  card.cancel:SetScript("OnClick", function() ov:Hide() end)
  return ov
end

function A:PaintEditor()
  local card, d = self.editor.card, self.draft
  for _, t in ipairs(card.tiles) do t.selected = t.key == d.cond; t:Paint() end
  card.action:Select(d.action)
  card.status:SetShown(d.action == "status")
  card.stance:SetShown(d.action == "stance")
  card.profile:SetShown(d.action == "profile")
  card.profileNote:SetShown(d.action == "profile")
  if d.action == "status" then card.status:Select(d.value)
  elseif d.action == "stance" then card.stance:Select(d.value) end
  card.valueLabel:SetText(d.action == "status" and "Set my status to" or d.action == "stance" and "Set my war stance to"
    or "Switch to the profile")
  card.profile:SetText(d.action == "profile" and d.value and Valid("profile", d.value) and d.value or "Choose a profile...")
  card.restore:Refresh()
  card.save:SetEnabled(Valid(d.action, d.value))
end

-- rule: an existing rule to edit, or nil for a new one.
function A:Edit(rule)
  local ov = self:BuildEditor()
  if rule then
    self.draft = { id = rule.id, enabled = rule.enabled, cond = rule.cond, action = rule.action, value = rule.value, restore = rule.restore }
  else
    self.draft = { id = ("%d-%d"):format(time(), math.random(1000, 9999)), enabled = true,
                   cond = "instance", action = "status", value = "ooc", restore = true }
  end
  ov.card.title:SetText(rule and "Edit rule" or "New rule")
  self:PaintEditor()
  ov:Show()
end

---------------------------------------------------------------------------
-- Settings: the list of rules
---------------------------------------------------------------------------
local ROW_H, ROWS = 46, 4

local function BuildRow(row)
  row.ring = UI.Circle(row, 32, "ARTWORK", 0)
  row.ring:SetPoint("LEFT", 10, 0)
  row.icon = row:CreateTexture(nil, "ARTWORK", nil, 1)
  row.icon:SetSize(28, 28)
  row.icon:SetPoint("CENTER", row.ring)
  row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
  UI.Round(row.icon)
  UI:OnTheme(function(t) row.ring:SetVertexColor(t.panelEdge[1], t.panelEdge[2], t.panelEdge[3], 0.5) end)
  row.title = UI.Text(row, "", "Body", "heading", 300)
  row.title:SetPoint("TOPLEFT", 52, -8)
  row.title:SetWordWrap(false)
  row.sub = UI.Text(row, "", "Small", "subtle", 340)
  row.sub:SetPoint("TOPLEFT", row.title, "BOTTOMLEFT", 0, -3)
  row.sub:SetWordWrap(false)
  row.del = UI.CloseButton(row, true, 20)
  row.del:SetPoint("RIGHT", -10, 0)
  row.del:SetScript("OnClick", function() if row.item then A:Delete(row.item) end end)
  UI.Tooltip(row.del, "Delete rule")
  row.toggle = UI.Toggle(row, "", nil, function() return row.item and row.item.enabled end, function(v)
    if row.item then row.item.enabled = v; A:Evaluate(); A:RefreshList() end
  end, 50, true)
  row.toggle:SetPoint("RIGHT", row.del, "LEFT", -12, 0)
  row.chip = UI.Chip(row)
  row.chip:SetPoint("RIGHT", row.toggle, "LEFT", -12, 0)
  row:SetScript("OnClick", function(self) if self.item then A:Edit(self.item) end end)
  row.onEnter = function(self)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:SetText("Click to edit this rule", 1, 0.82, 0)
    GameTooltip:Show()
  end
end

local function FillRow(row, rule)
  local c = COND[rule.cond] or A.CONDITIONS[1]
  row.icon:SetTexture(c.icon)
  row.title:SetText(c.long)
  local active = A:IsActive(rule)
  local sub = (ACTION[rule.action] and ACTION[rule.action].verb or "") ..
    (rule.restore and ", then switches back" or ", and leaves it")
  if active and rule.enabled then sub = sub .. ("  ·  |cff%sactive now|r"):format(UI.Hex(K:Theme().accent)) end
  row.sub:SetText(sub)
  local label, color = A:ValueLabel(rule.action, rule.value)
  if rule.action == "status" then label = K.STATUS[rule.value] and K.STATUS[rule.value].short or label end
  row.chip:Set(label, color)
  row.toggle:Refresh()
  local a = rule.enabled and 1 or 0.45
  row.icon:SetAlpha(a); row.title:SetAlpha(a); row.sub:SetAlpha(a); row.chip:SetAlpha(a)
  row.icon:SetDesaturated(not rule.enabled)
end

function A:RefreshList()
  if not self.list or not K.db then return end
  self.list:SetItems(self:Rules(), FillRow)
  if self.count then
    local n = #self:Rules()
    self.count:SetText(n == 0 and "" or (n == 1 and "1 rule" or (n .. " rules")))
  end
end

K:RegisterSettings({ id = "automation", title = "Automation", order = 15, build = function(card)
  card:Note("Let Kinship change your status, profile or war stance for you when something happens. "
    .. "A rule can switch things back once the moment passes. Click a rule to edit it.")
  card:EndRow()
  local w = card:GetWidth() - 32
  local h = ROW_H * ROWS
  local holder = CreateFrame("Frame", nil, card)
  holder:SetSize(w, h)
  holder:SetPoint("TOPLEFT", 16, card.y)
  holder.bg = holder:CreateTexture(nil, "BACKGROUND")
  holder.bg:SetAllPoints()
  holder.edge = UI.Border(holder)
  UI:OnTheme(function(t)
    holder.bg:SetColorTexture(unpack(t.sectionBg))
    holder.edge:SetColor(unpack(t.panelEdge))
  end)
  local list = UI.List(holder, w, h, ROW_H,
    "No rules yet. Try one: in a dungeon or raid, go Out of Character, and switch back when you leave.",
    BuildRow, { bare = true, emptyIcon = K.Art("IconMilestone") })
  list:SetPoint("TOPLEFT")
  A.list = list
  card:Space(h + 12)

  local add = card:Button("Add a rule", function() A:Edit(nil) end, 140)
  A.count = UI.Text(card, "", "Small", "subtle")
  A.count:SetPoint("LEFT", add, "RIGHT", 12, 0)
  card:Toggle("Tell me when a rule switches", "A short notice when a rule changes something (not for combat or mounting).", "autoNotify")
  card:OnRefresh(function() A:RefreshList() end)
end })
