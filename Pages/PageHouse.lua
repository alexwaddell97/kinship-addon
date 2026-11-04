-- Kinship RP: House page (families built on shared surnames).

local ADDON, ns = ...
local K = ns.K
local UI = K.UI

-- Crests to choose from, by theme (names in the game's icon folder). Any
-- that this client doesn't have are left out when the chooser is built.
local CREST_SETS = {
  { key = "arms", label = "Arms", icons = {
    "INV_Shield_05", "INV_Shield_01", "INV_Shield_02", "INV_Shield_03", "INV_Shield_04", "INV_Shield_06", "INV_Shield_07", "INV_Shield_08",
    "INV_Shield_09", "INV_Shield_10", "INV_Crown_01", "INV_Crown_02", "INV_Jewelry_Ring_03", "INV_Jewelry_Ring_01", "INV_Misc_Gem_Pearl_05", "INV_Misc_Gem_01",
    "INV_BannerPVP_01", "INV_BannerPVP_02", "INV_Misc_Key_03", "INV_Misc_Coin_01", "INV_Misc_Book_09", "INV_Misc_Rune_01", "INV_Scroll_03", "INV_Letter_15",
    "Spell_Holy_SealOfMight", "Spell_Holy_SealOfWisdom", "Spell_Holy_SealOfRighteousness", "Spell_Holy_SealOfSalvation", "Ability_Warrior_BattleShout",
    "Ability_Warrior_DefensiveStance", "Ability_Warrior_ShieldWall", "Spell_Holy_DevotionAura",
  } },
  { key = "beasts", label = "Beasts", icons = {
    "Ability_Hunter_Pet_Wolf", "Ability_Hunter_Pet_Bear", "Ability_Hunter_Pet_Boar", "Ability_Hunter_Pet_Cat", "Ability_Hunter_Pet_Owl",
    "Ability_Hunter_Pet_Raptor", "Ability_Hunter_Pet_Spider", "Ability_Hunter_Pet_Scorpid", "Ability_Hunter_Pet_Crab", "Ability_Hunter_Pet_Crocolisk",
    "Ability_Hunter_Pet_Gorilla", "Ability_Hunter_Pet_Hyena", "Ability_Hunter_Pet_Turtle", "Ability_Hunter_Pet_Vulture", "Ability_Hunter_Pet_WindSerpent",
    "Ability_Hunter_Pet_Bat", "Ability_Hunter_Pet_Tallstrider", "Ability_Mount_WhiteTiger", "Ability_Mount_BlackPanther", "Ability_Mount_JungleTiger",
    "Ability_Mount_RidingHorse", "Ability_Mount_WhiteDireWolf", "Ability_Mount_MountainRam", "Ability_Mount_Raptor", "Ability_Druid_CatForm",
    "Ability_Racial_BearForm", "Ability_Druid_TravelForm", "Ability_Druid_AquaticForm", "Ability_Hunter_EagleEye", "Spell_Nature_RavenForm",
    "INV_Misc_Head_Dragon_01", "INV_Misc_MonsterClaw_04",
  } },
  { key = "war", label = "Blades", icons = {
    "INV_Sword_04", "INV_Sword_01", "INV_Sword_02", "INV_Sword_03", "INV_Sword_05", "INV_Sword_06", "INV_Sword_07", "INV_Sword_08",
    "INV_Axe_01", "INV_Axe_02", "INV_Axe_03", "INV_Axe_04", "INV_Hammer_09", "INV_Hammer_01", "INV_Hammer_02", "INV_Mace_01",
    "INV_Spear_01", "INV_Staff_01", "INV_Staff_02", "INV_Weapon_ShortBlade_01", "INV_Weapon_ShortBlade_02", "INV_Weapon_ShortBlade_05",
    "Ability_Rogue_Eviscerate", "Ability_DualWield", "Ability_BackStab", "Ability_Parry", "Ability_MeleeDamage", "Ability_ThunderClap",
    "INV_Misc_Bone_HumanSkull_01", "Ability_Warrior_Charge", "Ability_Warrior_Disarm", "Ability_Warrior_Cleave",
  } },
  { key = "nature", label = "Nature", icons = {
    "Spell_Nature_Tranquility", "Spell_Nature_StarFall", "Spell_Nature_ProtectionformNature", "Spell_Nature_HealingTouch",
    "Spell_Nature_Regeneration", "Spell_Nature_ResistNature", "Spell_Nature_Thorns", "Spell_Nature_LightningShield", "Spell_Nature_Lightning",
    "Spell_Nature_EarthBind", "Spell_Nature_Sleep", "Spell_Nature_Cyclone", "Spell_Nature_Polymorph", "Spell_Frost_SummonWaterElemental",
    "INV_Misc_Herb_19", "INV_Misc_Flower_02", "INV_Misc_Herb_10", "INV_Misc_Branch_01", "INV_Misc_Pelt_Wolf_01", "INV_Misc_Food_15",
    "INV_Drink_05", "INV_Misc_Herb_07", "INV_Misc_Herb_11", "Spell_Nature_NullifyDisease",
  } },
  { key = "magic", label = "Magic", icons = {
    "Spell_Holy_HolyBolt", "Spell_Holy_PowerWordShield", "Spell_Holy_MindVision", "Spell_Holy_GreaterBlessingofKings", "Spell_Holy_Renew",
    "Spell_Holy_MagicalSentry", "Spell_Holy_PrayerOfSpirit", "Spell_Fire_FlameBolt", "Spell_Fire_Fireball02", "Spell_Fire_Fire",
    "Spell_Frost_FrostBolt02", "Spell_Frost_IceStorm", "Spell_Arcane_Blink", "Spell_Arcane_StarFire", "Spell_Arcane_PortalStormWind",
    "Spell_Shadow_ShadowWordPain", "Spell_Shadow_DeathCoil", "Spell_Shadow_RaiseDead", "Spell_Shadow_Charm", "Spell_Shadow_Possession",
    "Spell_Shadow_AntiShadow", "Spell_Shadow_LifeDrain", "Spell_Shadow_PsychicScream", "Spell_Shadow_MindSteal",
  } },
}
local ICON_DIR = "Interface\\Icons\\"

-- A crest as a medallion: a gold ring, a dark well, a fine inner ring, and the
-- icon set inside it, trimmed of its square border and kept small enough to
-- stay sharp. onCard: on a card (the well takes the card's colour).
-- Returns a frame (a Button when button) with :SetCrest(path) and :SetLit(v).
local function Medallion(parent, size, button, onCard)
  local f = CreateFrame(button and "Button" or "Frame", nil, parent)
  f:SetSize(size, size)
  local inner = math.floor(size * 0.82)
  f.ring = UI.Circle(f, size, "BACKGROUND", 0)
  f.ring:SetPoint("CENTER")
  f.well = UI.Circle(f, size - 6, "BACKGROUND", 1)
  f.well:SetPoint("CENTER")
  f.inner = UI.Circle(f, inner, "BORDER", 0)
  f.inner:SetPoint("CENTER")
  f.hole = UI.Circle(f, inner - 3, "BORDER", 1)
  f.hole:SetPoint("CENTER")
  f.icon = f:CreateTexture(nil, "ARTWORK")
  f.icon:SetSize(inner - 9, inner - 9)
  f.icon:SetPoint("CENTER")
  f.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
  UI.Round(f.icon)
  f.shine = UI.Circle(f, inner - 9, "OVERLAY", 0)
  f.shine:SetPoint("CENTER")
  f.shine:SetBlendMode("ADD")
  f.shine:SetVertexColor(1, 1, 1, 0)
  function f:SetCrest(path) self.icon:SetTexture(path or "Interface\\Icons\\INV_Shield_05") end
  function f:SetLit(v)
    local t = K:Theme()
    self.ring:SetVertexColor(t.ui[1], t.ui[2], t.ui[3], v and 1 or 0.9)
    self.shine:SetVertexColor(1, 1, 1, v and 0.08 or 0)
  end
  UI:OnTheme(function(t)
    f.well:SetVertexColor(unpack(onCard and t.panel or t.chrome))
    f.inner:SetVertexColor(t.ui[1], t.ui[2], t.ui[3], 0.5)
    f.hole:SetVertexColor(0.04, 0.03, 0.02, 0.92)
    f:SetLit(false)
  end)
  return f
end

---------------------------------------------------------------------------
-- The crest chooser: a pop-over on the journal. Your arms large in their
-- ring, with the house name and motto beneath, and as they'll be pressed
-- into a letter's seal; themed sets of round crests, or any icon by name.
---------------------------------------------------------------------------
local CW, CH = 580, 440
local COLS, ROWS, CELL = 8, 6, 43
local chooser

local function CrestName(path)
  local n = tostring(path or ""):match("([^\\]+)$") or ""
  return (n:gsub("^INV_", ""):gsub("^Ability_", ""):gsub("^Spell_", ""):gsub("_", " "))
end

local function BuildChooser()
  local m = UI.Modal((K.Journal and K.Journal.frame) or UIParent, CW, CH, function() chooser:Hide() end)
  chooser = m
  local card = m.card

  -- Left: the preview
  m.head = UI.Section(card, "Your arms")
  m.head:SetPoint("TOPLEFT", 21, -15)
  local cx = 105
  m.medal = Medallion(card, 112, false, true)
  m.medal:SetPoint("CENTER", card, "TOPLEFT", cx, -110)
  m.big = m.medal.icon
  m.house = UI.Text(card, "", "Header", "text", 170)
  m.house:SetPoint("TOP", card, "TOPLEFT", cx, -176)
  m.house:SetJustifyH("CENTER")
  m.house:SetWordWrap(false)
  m.motto = UI.Text(card, "", "Small", "subtle", 170)
  m.motto:SetPoint("TOP", m.house, "BOTTOM", 0, -5)
  m.motto:SetJustifyH("CENTER")
  m.motto:SetSpacing(2)
  m.name = UI.Text(card, "", "Small", "subtle", 170)
  m.name:SetPoint("TOP", card, "TOPLEFT", cx, -232)
  m.name:SetJustifyH("CENTER")
  m.name:SetWordWrap(false)

  -- The seal it makes (click to try another wax)
  m.sealKey = 1
  m.seal = UI.Seal(card, 58)
  m.seal:SetPoint("CENTER", card, "TOPLEFT", cx, -300)
  m.sealBtn = CreateFrame("Button", nil, card)
  m.sealBtn:SetAllPoints(m.seal)
  m.sealBtn:SetScript("OnClick", function()
    m.sealKey = m.sealKey % #UI.SEAL_COLORS + 1
    m:Paint()
  end)
  UI.Tooltip(m.sealBtn, "On your letters", "Your crest is pressed into the wax of every letter you seal. Click to try another colour of wax.")
  m.sealNote = UI.Text(card, "Pressed into your letters' seals", "Small", "subtle", 170)
  m.sealNote:SetPoint("TOP", m.seal, "BOTTOM", 0, -8)
  m.sealNote:SetJustifyH("CENTER")

  -- Right: the sets
  local RX = 210
  local sets = {}
  for _, set in ipairs(CREST_SETS) do sets[#sets + 1] = { key = set.key, label = set.label } end
  m.tabs = UI.Segments(card, sets, 68, function(key) m.set = key; m:Paint() end)
  m.tabs:SetPoint("TOPLEFT", RX, -44)

  m.cells = {}
  for i = 1, COLS * ROWS do
    local b = CreateFrame("Button", nil, card)
    b:SetSize(CELL - 3, CELL - 3)
    b:SetPoint("TOPLEFT", RX + ((i - 1) % COLS) * CELL, -78 - math.floor((i - 1) / COLS) * CELL)
    b.ring = UI.Circle(b, CELL - 3, "ARTWORK", 0)
    b.ring:SetPoint("CENTER")
    b.icon = b:CreateTexture(nil, "ARTWORK", nil, 1)
    b.icon:SetSize(CELL - 9, CELL - 9)
    b.icon:SetPoint("CENTER")
    b.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    UI.Round(b.icon)
    b:SetScript("OnEnter", function(self)
      self.hover = true
      m:PaintCell(self)
      GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
      GameTooltip:SetText(CrestName(self.path), 1, 1, 1)
      GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function(self) self.hover = false; m:PaintCell(self); GameTooltip:Hide() end)
    b:SetScript("OnClick", function(self)
      if SOUNDKIT then PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON) end
      m.choice = self.path
      m:Paint()
      UI.FadeIn(m.big, 0.15)
    end)
    m.cells[i] = b
  end

  -- Any icon, by name
  m.field = UI.Field(card, "Or any icon, by name (e.g. INV_Misc_Head_Dragon_01)", 236, 80, nil)
  m.field:SetPoint("TOPLEFT", RX, -350)
  m.field.edit:SetScript("OnEnterPressed", function(self)
    local name = strtrim(self:GetText() or ""):gsub("^[Ii]nterface\\[Ii]cons\\", "")
    self:ClearFocus()
    if not name:find("^[%w_]+$") then m.note:SetText("Only letters, numbers and _ in an icon's name.") return end
    local probe = m.probe or card:CreateTexture(nil, "BACKGROUND")
    m.probe = probe
    probe:Hide()
    if probe:SetTexture(ICON_DIR .. name) == false then m.note:SetText("Your game has no icon by that name.") return end
    m.choice = ICON_DIR .. name
    m.note:SetText("")
    m:Paint()
  end)
  m.note = UI.Text(card, "", "Small", "subtle", 236)
  m.note:SetPoint("TOPLEFT", m.field, "BOTTOMLEFT", 1, -4)

  m.use = UI.Button(card, "Use this crest", 130, 26)
  m.use:SetPoint("BOTTOMRIGHT", -16, 14)
  m.use:SetScript("OnClick", function()
    if m.choice and m.onPick then m.onPick(m.choice) end
    m:Hide()
  end)
  m.cancel = UI.Button(card, "Cancel", 80, 26)
  m.cancel:SetPoint("RIGHT", m.use, "LEFT", -8, 0)
  m.cancel:SetScript("OnClick", function() m:Hide() end)

  -- Leave out crests this client doesn't have.
  local probe = card:CreateTexture(nil, "BACKGROUND")
  probe:Hide()
  for _, set in ipairs(CREST_SETS) do
    local kept = {}
    for _, name in ipairs(set.icons) do
      if probe:SetTexture(ICON_DIR .. name) ~= false and #kept < COLS * ROWS then kept[#kept + 1] = ICON_DIR .. name end
    end
    set.paths = kept
  end

  function m:PaintCell(b)
    local t = K:Theme()
    local sel = b.path ~= nil and b.path == self.choice
    local c = sel and t.accent or t.ui
    b.ring:SetVertexColor(c[1], c[2], c[3], sel and 1 or (b.hover and 0.55 or 0))
    b.icon:SetAlpha((sel or b.hover) and 1 or 0.85)
  end

  function m:Paint()
    local t = K:Theme()
    self.tabs:Select(self.set)
    local list
    for _, set in ipairs(CREST_SETS) do if set.key == self.set then list = set.paths end end
    for i, b in ipairs(self.cells) do
      b.path = list and list[i]
      b:SetShown(b.path ~= nil)
      if b.path then b.icon:SetTexture(b.path); self:PaintCell(b) end
    end
    self.medal:SetCrest(self.choice)
    local kind = self.kind
    local h = kind.Record()
    self.head:SetText(kind.arms)
    self.house:SetText(kind.Title(kind.Name()))
    local motto = h and strtrim(h.motto or "") or ""
    self.motto:SetText(motto ~= "" and ("\"" .. UI.Escape(motto) .. "\"") or "")
    self.name:SetText(CrestName(self.choice))
    -- Only a house's crest goes on your seal
    for _, w in ipairs({ self.seal, self.sealBtn, self.sealNote }) do w:SetShown(kind.seal) end
    self.seal:SetSeal(UI.SEAL_COLORS[self.sealKey].key, self.choice)
    self.use:SetEnabled(self.choice ~= nil)
  end
  UI:OnTheme(function() if m:IsShown() then m:Paint() end end)
  return m
end

-- current: the crest now; onPick(path) when one is chosen; kind: whose
-- crest it is (HOUSE or GROUP, below).
local function ShowPicker(current, onPick, kind)
  local m = chooser or BuildChooser()
  m.onPick, m.kind = onPick, kind
  m.choice = current
  m.note:SetText("")
  m.field.edit:SetText("")
  -- Open on the set the current crest is in.
  m.set = CREST_SETS[1].key
  for _, set in ipairs(CREST_SETS) do
    for _, path in ipairs(set.paths or {}) do if path == current then m.set = set.key end end
  end
  m:Paint()
  m:Show()
end

-- Recognition: [nameKey] = { name, state = "recognised" | "ignored" }
function K:SetHouseMember(key, name, state)
  local h = self:House()
  if not h or not key then return end
  h.members = h.members or {}
  h.members[key] = state and { name = name, state = state } or nil
  if state == "recognised" then self:Print(name .. " is now recognised as family.")
  elseif state == "ignored" then self:Print(name .. "'s claim will no longer be shown.") end
  self:Fire("HOUSE")
  K.Journal:RefreshCurrent()
end

function K:HouseState(name)
  local h = self:House()
  local key = K.NameKey(name)
  local m = h and h.members and key and h.members[key]
  return m and m.state or nil
end

-- Returns recognised members and unconfirmed claims for your house.
function K:HouseMembers()
  local key = self:HouseKey()
  local house = self:House()
  local recognised, claims, seen = {}, {}, {}
  if not key or not house then return recognised, claims end
  house.members = house.members or {}

  for guid, p in pairs(self.db.profiles) do
    local prof = p.list and p.list[p.active]
    if prof and self:HouseKey(strtrim(prof.house or "")) == key and p.name then
      local k = K.NameKey(p.name) or p.name:lower()
      if not seen[k] then
        seen[k] = true
        recognised[#recognised + 1] = { name = p.name, key = k, mine = true, state = "recognised",
          role = guid == self:CharKey() and "You" or "Your character" }
      end
    end
  end

  local recent = time() - 600
  local function add(name, raw, role)
    local k = K.NameKey(raw or name) or name:lower()
    if seen[k] then return end
    seen[k] = true
    local state = house.members[k] and house.members[k].state
    if state == "ignored" then return end
    local m = { name = name, raw = raw, key = k, state = state, role = role }
    if state == "recognised" then recognised[#recognised + 1] = m else claims[#claims + 1] = m end
  end

  -- People whose shared profile names this house
  for _, reg in pairs(self.Registry) do
    local house = reg.profile and strtrim(reg.profile.house or "") or ""
    if house:lower() == key then
      add(Ambiguate and Ambiguate(reg.name, "none") or reg.name, reg.name,
        (reg.t or 0) > recent and "|cff5fd35fNearby|r" or nil)
    end
  end
  -- Kin who share the surname
  for _, e in pairs(self:KinList()) do
    local _, surname = K.SplitName(e.name)
    if surname and surname:lower() == key then add(e.name, nil, K.RelationLabel(e.rel)) end
  end
  -- Anyone recognised earlier who isn't nearby right now
  for k, m in pairs(house.members) do
    if m.state == "recognised" and not seen[k] then
      seen[k] = true
      recognised[#recognised + 1] = { name = Ambiguate and Ambiguate(m.name, "none") or m.name, raw = m.name, key = k, state = "recognised" }
    end
  end

  local byName = function(a, b)
    if a.mine ~= b.mine then return a.mine and true or false end
    return a.name < b.name
  end
  table.sort(recognised, byName); table.sort(claims, byName)
  return recognised, claims
end


---------------------------------------------------------------------------
-- The page: two tabs built the same way, your house (a family, on a shared
-- surname) and your group (a company, an order, an RP guild).
---------------------------------------------------------------------------
local TOP, PANE_H = 40, 466 - 40

local HOUSE = {
  arms = "Your arms", seal = true, event = "HOUSE",
  Name = function() return K:HouseName() end,
  Record = function() return K:House() end,
  Title = function(name) return "House " .. name end,
  Members = function() return K:HouseMembers() end,
  SetMember = function(key, name, state) K:SetHouseMember(key, name, state) end,
  crestTip = "Click to choose your house's crest.",
  mottoTip = "A few words your house lives by.",
  story = "The house's story",
  recognise = "Recognise as family",
  claims = "Claims to be of this house",
  membersNote = "Anyone can write a house name into their profile. Recognise the people who truly belong; only you see these choices.",
}

local GROUP = {
  arms = "Your banner", seal = false, event = "HOUSE",
  Name = function() return K:GroupName() end,
  Record = function() return K:Group() end,
  Title = function(name) return name end,
  Members = function() return K:GroupMembers() end,
  SetMember = function(key, name, state) K:SetGroupMember(key, name, state) end,
  crestTip = "Click to choose your group's banner.",
  mottoTip = "A few words your group stands for.",
  story = "The group's story",
  recognise = "Recognise as a member",
  claims = "Claims to belong",
  membersNote = "Anyone can write a group name into their profile. Recognise the people who truly belong; only you see these choices.",
}

-- Shared by both tabs: crest, name, motto, story and members.
local function BuildPane(c, kind)
  local pane = CreateFrame("Frame", nil, c)
  pane:SetPoint("TOPLEFT", 0, -TOP)
  pane:SetSize(696, PANE_H)
  pane.kind = kind

  -- Hero: the crest in a gold ring, the name and its motto ----------------------
  local hero = CreateFrame("Frame", nil, pane)
  hero:SetPoint("TOPLEFT")
  hero:SetPoint("TOPRIGHT")
  hero:SetHeight(104)
  pane.hero = hero
  pane.crest = Medallion(hero, 100, true)
  pane.crest:SetPoint("LEFT", 2, 0)
  local ring = pane.crest
  pane.crest:HookScript("OnEnter", function(self) self:SetLit(true) end)
  pane.crest:HookScript("OnLeave", function(self) self:SetLit(false) end)
  pane.crest:SetScript("OnClick", function()
    local r = kind.Record()
    ShowPicker(r and r.crest, function(path)
      local rec = kind.Record()
      if rec then rec.crest = path; K:Fire(kind.event); K.Journal:RefreshCurrent() end
    end, kind)
  end)
  UI.Tooltip(pane.crest, kind.arms, kind.crestTip)

  pane.title = UI.Text(hero, "", "GameFontNormalHuge", "deskHeading", kind.seal and 560 or 440)
  pane.title:SetPoint("TOPLEFT", ring, "TOPRIGHT", 22, -6)
  pane.title:SetWordWrap(false)
  pane.summary = UI.Text(hero, "", "GameFontHighlightSmall", "deskSubtle")
  pane.summary:SetPoint("TOPLEFT", pane.title, "BOTTOMLEFT", 1, -5)
  pane.motto = UI.Field(hero, "Motto", kind.seal and 400 or 380, 90, function(text)
    local r = kind.Record(); if r then r.motto = text; K:Fire(kind.event) end
  end, "desk")
  pane.motto:SetPoint("TOPLEFT", ring, "TOPRIGHT", 22, -54)
  UI.Tooltip(pane.motto.edit, "Motto", kind.mottoTip)

  local rule = UI.Line(hero)
  rule:SetPoint("TOPLEFT", hero, "BOTTOMLEFT", 0, -10)
  rule:SetPoint("TOPRIGHT", hero, "BOTTOMRIGHT", 0, -10)
  UI:OnTheme(function(t) rule:SetVertexColor(unpack(t.line)) end)

  -- Not in one yet: an empty crest ring, waiting for a name ----------------------
  pane.none = CreateFrame("Frame", nil, pane)
  pane.none:SetAllPoints()
  local nring = Medallion(pane.none, 100)
  nring:SetPoint("TOP", 0, -50)
  nring:SetCrest("Interface\\Icons\\INV_Misc_QuestionMark")
  nring.icon:SetDesaturated(true)
  nring.icon:SetAlpha(0.45)
  nring:SetAlpha(0.7)
  pane.noneTitle = UI.Text(pane.none, "", "GameFontNormalLarge", "deskHeading")
  pane.noneTitle:SetPoint("TOP", nring, "BOTTOM", 0, -20)
  pane.noneText = UI.Text(pane.none, "", "QuestFont", "deskText", 420)
  pane.noneText:SetPoint("TOP", pane.noneTitle, "BOTTOM", 0, -10)
  pane.noneText:SetJustifyH("CENTER")
  pane.noneText:SetSpacing(3)

  -- Details --------------------------------------------------------------
  local bodyTop = 124
  pane.body = CreateFrame("Frame", nil, pane)
  pane.body:SetPoint("TOPLEFT", 0, -bodyTop)
  pane.body:SetPoint("BOTTOMRIGHT", 0, 0)
  local bodyH = PANE_H - bodyTop

  local about = UI.Panel(pane.body)
  about:SetPoint("TOPLEFT", 0, 0)
  about:SetSize(380, bodyH)
  local ah = UI.Section(about, kind.story)
  ah:SetPoint("TOPLEFT", 21, -13)
  pane.desc = UI.TextArea(about, 348, bodyH - 54, 2000, function(text)
    local r = kind.Record(); if r then r.desc = text; K:Fire(kind.event) end
  end)
  pane.desc:SetPoint("TOPLEFT", 16, -38)

  pane.members = UI.List(pane.body, 306, bodyH - 62, 28, "", function(row)
    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetSize(18, 18)
    row.icon:SetPoint("LEFT", 6, 0)
    row.btn = UI.Button(row, "", 82, 18)
    row.btn:SetPoint("RIGHT", -2, 0)
    row.role = UI.Text(row, "", "GameFontHighlightSmall", "subtle")
    row.role:SetPoint("RIGHT", row.btn, "LEFT", -6, 0)
    row.name = UI.Text(row, "", "GameFontHighlight", "text")
    row.name:SetPoint("LEFT", 30, 0)
    row.name:SetPoint("RIGHT", row.role, "LEFT", -4, 0)
    row.name:SetWordWrap(false)
    row.header = UI.Text(row, "", "GameFontNormalSmall", "section")
    row.header:SetPoint("LEFT", 8, -2)
    row:SetScript("OnClick", function(self, button)
      local m = self.item
      if not m or m.header then return end
      if button == "RightButton" and not m.mine then
        UI.Menu(self, function(root)
          root:CreateTitle(m.name)
          root:CreateButton("View profile", function() K:ViewProfile(m.raw or m.name) end)
          if m.state == "recognised" then
            root:CreateButton("Stop recognising", function() kind.SetMember(m.key, m.name, nil) end)
          else
            root:CreateButton(kind.recognise, function() kind.SetMember(m.key, m.name, "recognised") end)
          end
          root:CreateButton("|cffff6060Ignore this claim|r", function() kind.SetMember(m.key, m.name, "ignored") end)
        end)
      else
        K:ViewProfile(m.raw or m.name)
      end
    end)
    row.btn:SetScript("OnClick", function()
      local m = row.item
      kind.SetMember(m.key, m.name, m.state == "recognised" and nil or "recognised")
    end)
  end)
  pane.members:SetPoint("TOPRIGHT", 0, -24)
  local mh = UI.Section(pane.body, "Members", true)
  mh:SetPoint("BOTTOMLEFT", pane.members, "TOPLEFT", 7, 7)
  pane.membersNote = UI.Text(pane.body, kind.membersNote, "GameFontHighlightSmall", "deskSubtle", 300)
  pane.membersNote:SetPoint("TOPLEFT", pane.members, "BOTTOMLEFT", 2, -6)
  return pane
end

local function RefreshPane(pane)
  local kind = pane.kind
  local name, rec = kind.Name(), kind.Record()
  pane.none:SetShown(rec == nil)
  for _, w in ipairs({ pane.body, pane.hero }) do w:SetShown(rec ~= nil) end
  if not rec then return end
  pane.title:SetText(kind.Title(name))
  pane.crest:SetCrest(rec.crest)
  if not pane.motto.edit:HasFocus() then pane.motto.edit:SetText(rec.motto or "") end
  if not pane.desc.edit:HasFocus() then pane.desc.edit:SetText(rec.desc or "") end

  -- Your own characters always belong. Everyone else is a claim until you
  -- recognise them: anyone can type a name into their profile.
  local recognised, claims = kind.Members()
  local summary = #recognised == 1 and "1 member" or (#recognised .. " members")
  if #claims > 0 then summary = summary .. ("  ·  %d %s"):format(#claims, #claims == 1 and "claim" or "claims") end
  pane.summary:SetText(summary)
  local items = {}
  items[#items + 1] = { header = "Recognised" }
  for _, m in ipairs(recognised) do items[#items + 1] = m end
  if #claims > 0 then
    items[#items + 1] = { header = kind.claims }
    for _, m in ipairs(claims) do items[#items + 1] = m end
  end
  pane.members:SetItems(items, function(row, m)
    local isHeader = m.header ~= nil
    row.header:SetShown(isHeader)
    row.icon:SetShown(not isHeader); row.name:SetShown(not isHeader); row.role:SetShown(not isHeader)
    row.btn:SetShown(not isHeader and not m.mine)
    if isHeader then row.header:SetText(m.header) return end
    row.icon:SetTexture(m.mine and K.ICON or (K.Art("IconKin")))
    row.icon:SetDesaturated(m.state ~= "recognised" and not m.mine)
    row.name:SetText(m.name)
    row.role:SetText(m.role or "")
    row.btn:SetText(m.state == "recognised" and "Remove" or "Recognise")
  end)
end

K:RegisterPage({
  id = "house", title = "House", heading = "House & group",
  subtitle = "Your family, and any company or order you belong to.",

  build = function(c)
    c.tab = 1
    c.tabs = UI.TabBar(c, { "House", "Group" }, function(i) c.tab = i; K.Journal:RefreshCurrent() end, true)
    c.tabs:SetPoint("TOPLEFT", -10, 2)

    -- House: its name comes from your profile (your surname, to start with)
    local h = BuildPane(c, HOUSE)
    h.noneTitle:SetText("No house yet")
    h.noneText:SetText(K:Compat()
      and "In Total RP 3, edit your Characteristics and add a House name under Additional Information to found a house. Other characters who share that name can join it."
      or ("Set a house name on your Profile page to found a house. " ..
      "Other characters who share that name can join it."))
    local go = UI.Button(h.none, K:Compat() and "Open Total RP 3" or "Go to Profile", 140, 24)
    go:SetPoint("TOP", h.noneText, "BOTTOM", 0, -18)
    go:SetScript("OnClick", function() K:OpenProfileEditor() end)

    -- Group: named right here, with your place in it
    local g = BuildPane(c, GROUP)
    g.noneTitle:SetText("No group yet")
    g.noneText:SetText("A company, an order, an RP guild: anything you belong to that isn't a family. "
      .. "Name one to found it, or use the same name as others to join them.")
    g.join = UI.Field(g.none, "Group name", 240, K.MAX_GROUP_NAME, nil, "desk")
    g.join:SetPoint("TOP", g.noneText, "BOTTOM", -59, -18)
    g.joinBtn = UI.Button(g.none, "Found or join", 110, 23)
    g.joinBtn:SetPoint("BOTTOMLEFT", g.join.edit, "BOTTOMRIGHT", 8, 0)
    local function join()
      local name = strtrim(g.join.edit:GetText() or "")
      if name == "" then return end
      g.join.edit:ClearFocus()
      g.join.edit:SetText("")
      K:SetGroup(name)
      K.Journal:RefreshCurrent()
    end
    g.joinBtn:SetScript("OnClick", join)
    g.join.edit:SetScript("OnEnterPressed", join)

    g.role = UI.Field(g.hero, "Your place in it", 150, K.MAX_GROUP_ROLE, function(text) K:SetGroupRole(text) end, "desk")
    g.role:SetPoint("TOPRIGHT", 0, -54)
    g.role:Info("Your place in it", "What you are in the group, like \"Sergeant\", \"Founder\" or \"Recruit\". "
      .. "It shows beside your name in the members list, and on your tooltip.")
    g.leave = UI.Button(g.hero, "Leave", 70, 22)
    g.leave:SetPoint("TOPRIGHT", 0, -4)
    g.leave:SetScript("OnClick", function()
      K:SetGroup("")
      K.Journal:RefreshCurrent()
    end)
    UI.Tooltip(g.leave, "Leave the group", "Takes it off your profile. Its crest and story stay saved here, "
      .. "so naming it again brings them back.")

    c.panes = { h, g }
    -- The house tour lights these
    c.hero, c.none, c.crest, c.motto, c.desc, c.members = h.hero, h.none, h.crest, h.motto, h.desc, h.members
    c.group = g
  end,

  refresh = function(c)
    c.tabs:Select(c.tab)
    for i, pane in ipairs(c.panes) do pane:SetShown(i == c.tab) end
    if c.shownTab ~= c.tab then
      if c.shownTab then UI.FadeIn(c.panes[c.tab], 0.2) end
      c.shownTab = c.tab
    end
    local pane = c.panes[c.tab]
    RefreshPane(pane)
    if pane == c.group and not c.group.role.edit:HasFocus() then c.group.role.edit:SetText(K:GroupRole()) end
  end,
})
