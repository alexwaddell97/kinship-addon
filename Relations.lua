-- Kinship RP: relationships with anyone you meet. Ten kinds come built in
-- (Friend, Family, Love, Ally, Mentor, Business, Neutral, Unfriendly, Rival,
-- Enemy) and you can make your own, each with a colour and an icon. Shown in
-- tooltips, set from the target bar, and kept in step with Kin bonds.
-- Fires "RELATIONS" whenever a relationship or a kind of relationship changes.
--
--   K:RelationOf(name)      -> def { key, label, color, icon, desc, custom } or nil
--   K:SetRelation(name, key) (key nil or "" clears it)
--   K:RelationDef(key), K:RelationTypes(), K.RELATION_TYPES (built-ins, in order)
--   K.Relations:Menu(owner, name), K.Relations:FillMenu(menuDescription, name)

local ADDON, ns = ...
local K = ns.K
local UI = K.UI
local Safe = K.Safe
local R = {}
K.Relations = R

local WHITE = "Interface\\Buttons\\WHITE8X8"
local CROP = ":0:0:64:64:5:59:5:59"
local function Icon(name) return "Interface\\Icons\\" .. name end
local OnCard = UI.OnCard or function(c) return c end

-- Icons checked against LibRPMediaData_Forever (they exist on this client).
K.RELATION_TYPES = {
  { key = "friend",     label = "Friend",     color = { 0.42, 0.82, 0.46 }, icon = Icon("achievement_reputation_06"),
    desc = "Someone you trust and are glad to see." },
  { key = "family",     label = "Family",     color = { 0.96, 0.70, 0.26 }, icon = Icon("achievement_reputation_07"),
    desc = "Kin by blood, by marriage or by choice." },
  { key = "love",       label = "Love",       color = { 0.96, 0.52, 0.68 }, icon = Icon("inv_valentinescandy"),
    desc = "A sweetheart, a spouse, or a quiet longing." },
  { key = "ally",       label = "Ally",       color = { 0.38, 0.64, 0.96 }, icon = Icon("inv_shield_06"),
    desc = "On the same side, for now or for good." },
  { key = "mentor",     label = "Mentor",     color = { 0.66, 0.56, 0.94 }, icon = Icon("inv_misc_book_09"),
    desc = "A teacher, or someone you are teaching." },
  { key = "business",   label = "Business",   color = { 0.92, 0.82, 0.36 }, icon = Icon("achievement_reputation_08"),
    desc = "Coin, contracts and favours owed." },
  { key = "neutral",    label = "Neutral",    color = { 0.64, 0.68, 0.76 }, icon = Icon("achievement_reputation_05"),
    desc = "Known to you, without strong feeling either way." },
  { key = "unfriendly", label = "Unfriendly", color = { 0.92, 0.56, 0.30 }, icon = Icon("spell_shadow_curseofmannoroth"),
    desc = "Bad blood, distrust or an old grudge." },
  { key = "rival",      label = "Rival",      color = { 0.90, 0.40, 0.32 }, icon = Icon("ability_warrior_challange"),
    desc = "A worthy opponent you measure yourself against." },
  { key = "enemy",      label = "Enemy",      color = { 0.82, 0.20, 0.24 }, icon = Icon("inv_misc_bone_humanskull_01"),
    desc = "Someone your character would gladly see fall." },
}
local BUILTIN = {}
for i, d in ipairs(K.RELATION_TYPES) do d.order = i; BUILTIN[d.key] = d end

-- Choices for your own kinds of relationship.
local SWATCHES = {
  { 0.42, 0.82, 0.46 }, { 0.30, 0.76, 0.70 }, { 0.38, 0.64, 0.96 }, { 0.66, 0.56, 0.94 },
  { 0.82, 0.48, 0.88 }, { 0.96, 0.52, 0.68 }, { 0.90, 0.40, 0.32 }, { 0.92, 0.56, 0.30 },
  { 0.96, 0.70, 0.26 }, { 0.92, 0.82, 0.36 }, { 0.64, 0.68, 0.76 }, { 0.66, 0.50, 0.36 },
}
local ICONS = {
  "achievement_reputation_06", "achievement_reputation_07", "inv_valentinescandy", "inv_valentinescard01",
  "inv_shield_06", "inv_misc_book_09", "achievement_reputation_08", "achievement_reputation_05",
  "spell_shadow_curseofmannoroth", "ability_warrior_challange", "inv_misc_bone_humanskull_01", "inv_misc_groupneedmore",
  "inv_crown_01", "inv_misc_flower_02", "inv_misc_key_03", "inv_misc_coin_01",
  "spell_holy_holybolt", "inv_sword_04", "spell_shadow_deathpact", "ability_eyeoftheowl",
  "inv_misc_rune_01", "inv_scroll_03", "inv_jewelry_ring_03", "inv_drink_05",
}
for i, n in ipairs(ICONS) do ICONS[i] = Icon(n) end

local BUTTON_ICON = Icon("achievement_guildperk_everybodysfriend")
local MAX_LABEL = 24

---------------------------------------------------------------------------
-- Data
---------------------------------------------------------------------------
-- Your relationships, per character: K.db.relations[charGUID][nameKey] = relKey
local function Store()
  local db = K.db
  if not db or type(db.relations) ~= "table" then return {} end
  local char = K:CharKey()
  if not Safe(char) or not char then return {} end
  db.relations[char] = db.relations[char] or {}
  return db.relations[char]
end

-- The Kin bond we last saw for each Kin entry, so a change made on the Kin
-- page can be told apart from a Kin entry that simply never had one.
local function Seen()
  local db = K.db
  if not db or type(db.relationKin) ~= "table" then return {} end
  local char = K:CharKey()
  if not Safe(char) or not char then return {} end
  db.relationKin[char] = db.relationKin[char] or {}
  return db.relationKin[char]
end

local function Customs()
  local t = K.db and K.db.relationTypes
  return (t and t.list) or {}
end

local function ValidName(name)
  return Safe(name) and type(name) == "string" and name ~= ""
end

function K:RelationTypes()
  local out = {}
  for _, d in ipairs(K.RELATION_TYPES) do out[#out + 1] = d end
  for _, d in ipairs(Customs()) do out[#out + 1] = d end
  return out
end

function K:RelationDef(key)
  if type(key) ~= "string" or key == "" then return nil end
  if BUILTIN[key] then return BUILTIN[key] end
  for _, d in ipairs(Customs()) do if d.key == key then return d end end
end

-- Kin entries are keyed by the name as it was seen (often without a realm);
-- relations use K.NameKey. Find the Kin entry for any form of the name.
local function KinEntry(name)
  if not K.db or not ValidName(name) then return nil end
  local list = K:KinList()
  local low = name:lower()
  if list[low] then return list[low], low end
  local short = Ambiguate and Ambiguate(name, "none")
  if type(short) == "string" and list[short:lower()] then return list[short:lower()], short:lower() end
  local nk = K.NameKey and K.NameKey(name)
  if nk and list[nk] then return list[nk], nk end
end

function K:RelationKey(name)
  if not ValidName(name) then return nil end
  local key = K.NameKey(name)
  return key and Store()[key] or nil
end

function K:RelationOf(name)
  if not self.db or not ValidName(name) then return nil end
  local def = self:RelationDef(self:RelationKey(name))
  if def then return def end
  local e = KinEntry(name)
  if e and e.rel and e.rel ~= "" then return self:RelationDef(e.rel) end
end

-- The Kin page lists K.RELATIONS as bonds; give it every kind of relationship
-- so a bond chosen there and a relationship chosen here are the same thing.
local function RebuildKinBonds()
  local list = K.RELATIONS
  if type(list) ~= "table" then return end
  wipe(list)
  list[1] = { key = "", label = "Companion" }
  for _, d in ipairs(K:RelationTypes()) do list[#list + 1] = { key = d.key, label = d.label } end
end
RebuildKinBonds()

function K:SetRelation(name, relKey)
  if not self.db or not ValidName(name) then return false end
  local key = K.NameKey(name)
  if not key then return false end
  if relKey == "" or relKey == "none" then relKey = nil end
  if relKey and not self:RelationDef(relKey) then return false end
  Store()[key] = relKey
  local e, kinKey = KinEntry(name)
  if e then
    e.rel = relKey or ""
    Seen()[kinKey] = e.rel
    self:Fire("KIN")
  end
  self:Fire("RELATIONS", key, relKey)
  return true
end

-- Bring relationships and Kin bonds into line after the Kin list changes.
local function SyncFromKin()
  if not K.db or type(K.db.relations) ~= "table" then return end
  local store, seen, list = Store(), Seen(), K:KinList()
  local changed = false
  for kinKey, e in pairs(list) do
    local nk = type(e.name) == "string" and K.NameKey(e.name)
    if nk then
      local rel, prev = e.rel or "", seen[kinKey]
      if prev == nil then
        if rel == "" and store[nk] then
          e.rel = store[nk]                       -- a relationship set before they joined your Kin
        elseif rel ~= "" and store[nk] ~= rel and K:RelationDef(rel) then
          store[nk] = rel; changed = true
        end
      elseif prev ~= rel then                     -- changed on the Kin page
        store[nk] = (rel ~= "" and K:RelationDef(rel)) and rel or nil
        changed = true
      end
      seen[kinKey] = e.rel or ""
    end
  end
  for kinKey in pairs(seen) do if not list[kinKey] then seen[kinKey] = nil end end
  if changed then K:Fire("RELATIONS") end
end

-- Run before the pages redraw, so the Kin page shows the synced bond.
local function OnFirst(event, fn)
  K.listeners[event] = K.listeners[event] or {}
  table.insert(K.listeners[event], 1, fn)
end
OnFirst("KIN", function() SyncFromKin() end)

-- How many of your relationships use a kind (for the Settings list).
local function Uses(key)
  local n = 0
  for _, v in pairs(Store()) do if v == key then n = n + 1 end end
  return n
end

local function Plain(s)
  local text = tostring(s or ""):gsub("|", "")
  return strtrim(text)
end

local function LabelTaken(label, except)
  local low = label:lower()
  for _, d in ipairs(K:RelationTypes()) do
    if d ~= except and d.label:lower() == low then return true end
  end
  return false
end

function R:SaveCustom(def, label, color, icon)
  local db = K.db and K.db.relationTypes
  if not db then return nil end
  label = Plain(label):sub(1, MAX_LABEL)
  if label == "" then return nil end
  if def then
    def.label, def.color, def.icon = label, { color[1], color[2], color[3] }, icon
  else
    db.n = (db.n or 0) + 1
    local key = "c" .. db.n
    while K:RelationDef(key) do db.n = db.n + 1; key = "c" .. db.n end
    def = { key = key, label = label, color = { color[1], color[2], color[3] }, icon = icon, custom = true }
    table.insert(db.list, def)
  end
  RebuildKinBonds()
  K:Fire("RELATIONS")
  K:Fire("KIN")
  return def
end

function R:DeleteCustom(def)
  local db = K.db and K.db.relationTypes
  if not db or not def or not def.custom then return end
  for i, d in ipairs(db.list) do if d == def then table.remove(db.list, i) break end end
  -- Forget it everywhere, on every character.
  for _, store in pairs(K.db.relations or {}) do
    for name, v in pairs(store) do if v == def.key then store[name] = nil end end
  end
  for _, kin in pairs(K.db.kin or {}) do
    for _, e in pairs(kin) do if e.rel == def.key then e.rel = "" end end
  end
  for _, seen in pairs(K.db.relationKin or {}) do
    for k, v in pairs(seen) do if v == def.key then seen[k] = "" end end
  end
  RebuildKinBonds()
  K:Fire("RELATIONS")
  K:Fire("KIN")
end

---------------------------------------------------------------------------
-- Menus (target bar, and for other pages to reuse)
---------------------------------------------------------------------------
local function MenuLabel(d)
  return ("|T%s:16:16%s|t  |cff%s%s|r"):format(d.icon, CROP, UI.Hex(d.color), d.label)
end

-- Fill a menu (or a submenu description) with the relationship choices.
function R:FillMenu(root, name)
  local function current() local d = K:RelationOf(name); return d and d.key or nil end
  root:CreateRadio("No relationship", function() return current() == nil end, function() K:SetRelation(name, nil) end)
  for _, d in ipairs(K:RelationTypes()) do
    local key = d.key
    root:CreateRadio(MenuLabel(d), function() return current() == key end, function() K:SetRelation(name, key) end)
  end
  root:CreateDivider()
  root:CreateButton("Manage relationships...", function() if K.Journal then K.Journal:Open("settings") end end)
end

local function MouseOwner()
  if GetMouseFoci then
    local ok, foci = pcall(GetMouseFoci)
    if ok and type(foci) == "table" and foci[1] then return foci[1] end
  end
  if GetMouseFocus then
    local ok, f = pcall(GetMouseFocus)
    if ok and f then return f end
  end
  return UIParent
end

function R:Menu(owner, name)
  if not ValidName(name) then return end
  local short = Ambiguate and Ambiguate(name, "none") or name
  UI.Menu(owner or MouseOwner(), function(root)
    root:CreateTitle(short)
    R:FillMenu(root, name)
  end)
end

---------------------------------------------------------------------------
-- Tooltip line and target bar button
---------------------------------------------------------------------------
K:AddTooltipLines(function(tooltip, unit, name, profile, isMe)
  if isMe or not K.db or not K.db.settings.relTooltip then return end
  local d = K:RelationOf(name)
  if not d then return end
  tooltip:AddLine(("|T%s:14:14%s|t %s"):format(d.icon, CROP, d.label), d.color[1], d.color[2], d.color[3])
end)

local function IsOther(unit, name)
  if not ValidName(name) then return false end
  if unit and Safe(unit) then
    local ok, me = pcall(UnitIsUnit, unit, "player")
    if ok and Safe(me) and me then return false end
  end
  return K.NameKey(name) ~= K.NameKey(K:MyName())
end

K:RegisterTargetButton({
  id = "relation", order = 25, label = "Relationship", icon = BUTTON_ICON,
  shown = function(unit, name) return IsOther(unit, name) end,
  onClick = function(unit, name, owner) R:Menu(owner, name) end,
})

---------------------------------------------------------------------------
-- Editor for your own kinds of relationship (a modal over the journal)
---------------------------------------------------------------------------
local Editor = {}
local EW = 368   -- inner width of the editor card

local function Swatch(parent, color, onClick)
  local b = CreateFrame("Button", nil, parent)
  b:SetSize(22, 22)
  b.ring = UI.Circle(b, 22, "ARTWORK", 0)
  b.ring:SetPoint("CENTER")
  b.fill = UI.Circle(b, 16, "ARTWORK", 1)
  b.fill:SetPoint("CENTER")
  b.fill:SetVertexColor(color[1], color[2], color[3], 1)
  b.color = color
  local function paint(p)
    local t = K:Theme().text
    b.ring:SetVertexColor(t[1], t[2], t[3], b.selected and 0.9 or 0.35 * p)
  end
  function b:Paint() paint(UI.Progress(self)) end
  b:SetScript("OnEnter", function(self) UI.Tween(self, 1, 0.12, paint) end)
  b:SetScript("OnLeave", function(self) UI.Tween(self, 0, 0.12, paint) end)
  b:SetScript("OnClick", function(self)
    if SOUNDKIT then PlaySound(SOUNDKIT.IG_CHARACTER_INFO_TAB) end
    onClick(self.color)
  end)
  return b
end

local function IconChoice(parent, path, onClick)
  local b = CreateFrame("Button", nil, parent)
  b:SetSize(26, 26)
  b.icon = b:CreateTexture(nil, "ARTWORK")
  b.icon:SetPoint("TOPLEFT", 2, -2)
  b.icon:SetPoint("BOTTOMRIGHT", -2, 2)
  b.icon:SetTexture(path)
  b.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
  b.edge = UI.Border(b)
  b.path = path
  local function paint(p)
    local t = K:Theme()
    if b.selected then
      b.edge:SetColor(t.accent[1], t.accent[2], t.accent[3], 1)
      b.icon:SetAlpha(1)
      b.icon:SetDesaturated(false)
    else
      b.edge:SetColor(UI.Mix(t.panelEdge, { t.accent[1], t.accent[2], t.accent[3], 0.6 }, p))
      b.icon:SetAlpha(0.7 + 0.3 * p)
      b.icon:SetDesaturated(p < 0.5)
    end
  end
  function b:Paint() paint(UI.Progress(self)) end
  b:SetScript("OnEnter", function(self) UI.Tween(self, 1, 0.12, paint) end)
  b:SetScript("OnLeave", function(self) UI.Tween(self, 0, 0.12, paint) end)
  b:SetScript("OnClick", function(self)
    if SOUNDKIT then PlaySound(SOUNDKIT.IG_CHARACTER_INFO_TAB) end
    onClick(self.path)
  end)
  return b
end

function Editor:Build()
  if self.ov then return true end
  local host = K.Journal and K.Journal.frame
  if not host then return false end
  local ov = UI.Modal(host, EW + 32, 356, function() Editor:Close() end)
  self.ov = ov
  local card = ov.card
  host:HookScript("OnHide", function() Editor:Close() end)

  self.heading = UI.Section(card, "New relationship")
  self.heading:SetPoint("TOPLEFT", 21, -18)

  -- Preview: how it will read in tooltips and menus
  local pv = CreateFrame("Frame", nil, card)
  pv:SetSize(EW, 54)
  pv:SetPoint("TOPLEFT", 16, -42)
  pv.bg = pv:CreateTexture(nil, "BACKGROUND")
  pv.bg:SetAllPoints()
  UI:OnTheme(function(t) pv.bg:SetColorTexture(unpack(t.sectionBg)) end)
  pv.bar = pv:CreateTexture(nil, "ARTWORK")
  pv.bar:SetTexture(WHITE)
  pv.bar:SetWidth(3)
  pv.bar:SetPoint("TOPLEFT"); pv.bar:SetPoint("BOTTOMLEFT")
  pv.ring = UI.Circle(pv, 38, "ARTWORK", 0)
  pv.ring:SetPoint("LEFT", 14, 0)
  pv.icon = pv:CreateTexture(nil, "ARTWORK", nil, 1)
  pv.icon:SetSize(32, 32)
  pv.icon:SetPoint("CENTER", pv.ring)
  pv.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
  UI.Round(pv.icon)
  pv.name = UI.Text(pv, "", "Title", "plain", EW - 80)
  pv.name:SetPoint("TOPLEFT", pv.ring, "TOPRIGHT", 12, -2)
  pv.name:SetWordWrap(false)
  pv.hint = UI.Text(pv, "How it reads in tooltips, menus and on your Kin page.", "Small", "subtle", EW - 80)
  pv.hint:SetPoint("TOPLEFT", pv.name, "BOTTOMLEFT", 0, -4)
  pv.hint:SetWordWrap(false)
  self.preview = pv

  self.field = UI.Field(card, "Name", EW, MAX_LABEL, function() Editor:Paint() end)
  self.field:SetPoint("TOPLEFT", 16, -108)
  self.field.edit:SetScript("OnEnterPressed", function() Editor:Save() end)
  self.error = UI.Text(card, "", "Small", "plain", 220)
  self.error:SetPoint("TOPRIGHT", -16, -108)
  self.error:SetJustifyH("RIGHT")
  local ec = OnCard({ 0.90, 0.36, 0.30 })
  self.error:SetTextColor(ec[1], ec[2], ec[3])

  local cl = UI.Text(card, "Colour", "Label", "subtle")
  cl:SetPoint("TOPLEFT", 17, -160)
  self.swatches = {}
  local gap = math.floor((EW - #SWATCHES * 22) / (#SWATCHES - 1))
  for i, c in ipairs(SWATCHES) do
    local s = Swatch(card, c, function(color) Editor.draft.color = color; Editor:Paint() end)
    s:SetPoint("TOPLEFT", 16 + (i - 1) * (22 + gap), -176)
    self.swatches[i] = s
  end

  local il = UI.Text(card, "Icon", "Label", "subtle")
  il:SetPoint("TOPLEFT", 17, -212)
  self.icons = {}
  local per = 12
  local igap = math.floor((EW - per * 26) / (per - 1))
  for i, path in ipairs(ICONS) do
    local col, row = (i - 1) % per, math.floor((i - 1) / per)
    local b = IconChoice(card, path, function(p) Editor.draft.icon = p; Editor:Paint() end)
    b:SetPoint("TOPLEFT", 16 + col * (26 + igap), -228 - row * (26 + igap))
    self.icons[i] = b
  end

  self.save = UI.Button(card, "Save", 110, 26)
  self.save:SetPoint("BOTTOMRIGHT", -16, 16)
  self.save:SetScript("OnClick", function() Editor:Save() end)
  self.cancel = UI.Button(card, "Cancel", 90, 26)
  self.cancel:SetPoint("RIGHT", self.save, "LEFT", -8, 0)
  self.cancel:SetScript("OnClick", function() Editor:Close() end)
  self.delete = UI.Button(card, "", 120, 26)
  self.delete:SetPoint("BOTTOMLEFT", 16, 16)
  self.delete:SetScript("OnClick", function() Editor:Delete() end)

  UI:OnTheme(function() if ov:IsShown() then Editor:Paint() end end)
  return true
end

function Editor:Paint()
  local d = self.draft
  if not d then return end
  local label = Plain(self.field.edit:GetText())
  local pv = self.preview
  local c = d.color
  pv.bar:SetVertexColor(c[1], c[2], c[3], 1)
  pv.ring:SetVertexColor(c[1], c[2], c[3], 1)
  pv.icon:SetTexture(d.icon)
  local tc = OnCard(c)
  pv.name:SetText(label ~= "" and label or "Your relationship")
  pv.name:SetTextColor(tc[1], tc[2], tc[3], label ~= "" and 1 or 0.55)
  for _, s in ipairs(self.swatches) do
    s.selected = s.color[1] == c[1] and s.color[2] == c[2] and s.color[3] == c[3]
    s:Paint()
  end
  for _, b in ipairs(self.icons) do
    b.selected = b.path == d.icon
    b:Paint()
  end
  self.save:SetEnabled(label ~= "")
  if label ~= "" and LabelTaken(label, self.editing) then
    self.error:SetText("You already have one called that.")
  else
    self.error:SetText("")
  end
end

function Editor:Open(def)
  if not self:Build() then return end
  self.editing = def
  local c = def and def.color or SWATCHES[2]
  self.draft = { color = { c[1], c[2], c[3] }, icon = def and def.icon or ICONS[12] }
  self.heading:SetText(def and "Edit relationship" or "New relationship")
  self.field.edit:SetText(def and def.label or "")
  self.delete:SetShown(def ~= nil)
  self.delete:SetText("|cffd85a50Delete|r")
  self.armed = false
  self.ov:Show()
  self:Paint()
  self.field.edit:SetFocus()
end

function Editor:Close()
  if not self.ov then return end
  self.field.edit:ClearFocus()
  self.ov:Hide()
  self.editing, self.draft = nil, nil
end

function Editor:Save()
  if not self.draft then return end
  local label = Plain(self.field.edit:GetText())
  if label == "" then self.error:SetText("Give it a name first."); return end
  if LabelTaken(label, self.editing) then self.error:SetText("You already have one called that."); return end
  R:SaveCustom(self.editing, label, self.draft.color, self.draft.icon)
  if SOUNDKIT then PlaySound(SOUNDKIT.IG_CHARACTER_INFO_TAB) end
  self:Close()
  R:RefreshSettings()
end

-- Delete asks twice: the first click arms the button for a few seconds.
function Editor:Delete()
  local def = self.editing
  if not def then return end
  if not self.armed then
    self.armed = true
    local n = Uses(def.key)
    self.delete:SetText(n > 0 and ("|cffd85a50Remove from %d?|r"):format(n) or "|cffd85a50Sure?|r")
    C_Timer.After(3, function()
      if Editor.editing == def and Editor.armed then
        Editor.armed = false
        Editor.delete:SetText("|cffd85a50Delete|r")
      end
    end)
    return
  end
  R:DeleteCustom(def)
  self:Close()
  R:RefreshSettings()
end

---------------------------------------------------------------------------
-- Settings
---------------------------------------------------------------------------
-- A small tile showing one built-in kind, with its description on hover.
local function Tile(parent, d, w, h)
  local b = CreateFrame("Button", nil, parent)
  b:SetSize(w, h)
  b.bg = b:CreateTexture(nil, "BACKGROUND")
  b.bg:SetAllPoints()
  b.bg:SetTexture(WHITE)
  b.bar = b:CreateTexture(nil, "ARTWORK")
  b.bar:SetTexture(WHITE)
  b.bar:SetWidth(2)
  b.bar:SetPoint("TOPLEFT"); b.bar:SetPoint("BOTTOMLEFT")
  b.bar:SetVertexColor(d.color[1], d.color[2], d.color[3], 1)
  b.icon = b:CreateTexture(nil, "ARTWORK")
  b.icon:SetSize(20, 20)
  b.icon:SetPoint("LEFT", 10, 0)
  b.icon:SetTexture(d.icon)
  b.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
  UI.Round(b.icon)
  b.label = UI.Text(b, d.label, "Body", "plain", w - 44)
  b.label:SetPoint("LEFT", b.icon, "RIGHT", 8, 0)
  b.label:SetWordWrap(false)
  local function paint(p)
    local t = K:Theme()
    b.bg:SetVertexColor(UI.Mix(t.sectionBg, { d.color[1], d.color[2], d.color[3], 0.18 }, p))
    local c = OnCard(d.color)
    b.label:SetTextColor(c[1], c[2], c[3])
    b.bar:SetAlpha(0.6 + 0.4 * p)
  end
  b:SetScript("OnEnter", function(self)
    UI.Tween(self, 1, 0.12, paint)
    GameTooltip:SetOwner(self, "ANCHOR_TOP")
    GameTooltip:SetText(("|T%s:16:16%s|t %s"):format(d.icon, CROP, d.label), d.color[1], d.color[2], d.color[3])
    GameTooltip:AddLine(d.desc, 1, 1, 1, true)
    local n = Uses(d.key)
    GameTooltip:AddLine(n > 0 and (n == 1 and "You have 1 of these." or ("You have " .. n .. " of these.")) or "Set it from the target bar or your Kin.",
      0.7, 0.7, 0.7, true)
    GameTooltip:Show()
  end)
  b:SetScript("OnLeave", function(self) UI.Tween(self, 0, 0.15, paint); GameTooltip:Hide() end)
  UI:OnTheme(function() paint(UI.Progress(b)) end)
  return b
end

function R:RefreshSettings()
  local list = self.customList
  if not list or not list:IsVisible() then return end
  local items = {}
  for _, d in ipairs(Customs()) do items[#items + 1] = d end
  list:SetItems(items, function(row, d)
    row.icon:SetTexture(d.icon)
    row.ring:SetVertexColor(d.color[1], d.color[2], d.color[3], 1)
    local c = OnCard(d.color)
    row.name:SetText(d.label)
    row.name:SetTextColor(c[1], c[2], c[3])
    local n = Uses(d.key)
    row.sub:SetText(n == 0 and "Not given to anyone yet" or (n == 1 and "Given to 1 person" or ("Given to " .. n .. " people")))
  end)
  if self.customCount then
    local n = #items
    self.customCount:SetText(n == 0 and "" or (n == 1 and "1 of your own" or (n .. " of your own")))
  end
end

K:RegisterSettings({ id = "relations", title = "Relationships", order = 32, build = function(card)
  local W = card:GetWidth() - 32
  card:Toggle("Relationship in tooltips", "Your relationship with someone, in its colour, when you mouse over them.", "relTooltip")
  card:Space(2)

  local y = card.y
  local l1 = UI.Text(card, "Built in", "Label", "subtle")
  l1:SetPoint("TOPLEFT", 17, y)
  y = y - 18
  local cols, gap, th = 5, 8, 34
  local tw = math.floor((W - (cols - 1) * gap) / cols)
  for i, d in ipairs(K.RELATION_TYPES) do
    local col, row = (i - 1) % cols, math.floor((i - 1) / cols)
    Tile(card, d, tw, th):SetPoint("TOPLEFT", 16 + col * (tw + gap), y - row * (th + gap))
  end
  y = y - 2 * th - gap - 20

  local l2 = UI.Text(card, "Your own", "Label", "subtle")
  l2:SetPoint("TOPLEFT", 17, y)
  R.customCount = UI.Text(card, "", "Label", "subtle")
  R.customCount:SetPoint("LEFT", l2, "RIGHT", 10, 0)
  R.customCount:SetAlpha(0.8)
  local new = UI.Button(card, "New relationship", 150, 24)
  new:SetPoint("TOPRIGHT", -16, y + 7)
  new:SetScript("OnClick", function() Editor:Open(nil) end)
  y = y - 24

  R.customList = UI.List(card, W, 150, 40,
    "None of your own yet. Make one for the bonds the built-in ones don't cover: sworn sister, debtor, old flame.",
    function(row)
      row.ring = UI.Circle(row, 26, "ARTWORK", 0)
      row.ring:SetPoint("LEFT", 10, 0)
      row.icon = row:CreateTexture(nil, "ARTWORK", nil, 1)
      row.icon:SetSize(22, 22)
      row.icon:SetPoint("CENTER", row.ring)
      row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
      UI.Round(row.icon)
      row.name = UI.Text(row, "", "Body", "plain", 300)
      row.name:SetPoint("TOPLEFT", row.ring, "TOPRIGHT", 10, 1)
      row.name:SetWordWrap(false)
      row.sub = UI.Text(row, "", "Small", "subtle", 300)
      row.sub:SetPoint("TOPLEFT", row.name, "BOTTOMLEFT", 0, -3)
      row.edit = UI.Button(row, "Edit", 72, 22)
      row.edit:SetPoint("RIGHT", -8, 0)
      row.edit:SetScript("OnClick", function() Editor:Open(row.item) end)
      row:SetScript("OnClick", function(self) Editor:Open(self.item) end)
    end, { emptyIcon = K.Art("IconKin") })
  R.customList:SetPoint("TOPLEFT", 16, y)
  y = y - 150

  card:Space(card.y - y + 10)
  card:OnRefresh(function() R:RefreshSettings() end)
end })

---------------------------------------------------------------------------
-- Start-up and events
---------------------------------------------------------------------------
K:On("LOGIN", function()
  K.db.relations = K.db.relations or {}
  K.db.relationKin = K.db.relationKin or {}
  K.db.relationTypes = K.db.relationTypes or { list = {}, n = 0 }
  K.db.relationTypes.list = K.db.relationTypes.list or {}
  if K.db.settings.relTooltip == nil then K.db.settings.relTooltip = true end
  RebuildKinBonds()
  SyncFromKin()
end)

K:On("RELATIONS", function()
  R:RefreshSettings()
  if K.Journal and (K.Journal:IsShowing("directory") or K.Journal:IsShowing("kin")) then K.Journal:RefreshCurrent() end
end)
