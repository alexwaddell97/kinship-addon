-- Kinship RP: roleplay items. The designs you create (an account-wide
-- library), designs received from other players (a cache, so their items
-- always show correctly), each character's bags, the item tooltip, using an
-- item, and the item slot widget shared by the bags, trading and stashes.

local ADDON, ns = ...
local K = ns.K
local UI = K.UI
local I = { SLOTS = 30, MAX_STACK = 99 }
K.Items = I

local WHITE = "Interface\\Buttons\\WHITE8X8"
local ICON_DIR = "Interface\\Icons\\"
local CACHE_DAYS = 90

I.MAX = { id = 100, name = 60, description = 600, flavor = 200, useText = 200, creator = 60 }
I.DEFAULT_ICON = "Interface\\Icons\\INV_Misc_QuestionMark"

-- Where an item can be worn (see Wardrobe.lua). Roleplay slots, not the
-- game's gear: a design says which one it goes in, or none. They're laid out
-- as the character screen lays out its gear: side = "left", "right" or
-- "bottom", in order down (or along) each.
I.WEAR = {
  { key = "head", label = "Head", side = "left" }, { key = "neck", label = "Neck", side = "left" },
  { key = "shoulder", label = "Shoulders", side = "left" }, { key = "back", label = "Back", side = "left" },
  { key = "chest", label = "Chest", side = "left" }, { key = "shirt", label = "Shirt", side = "left" },
  { key = "tabard", label = "Tabard", side = "left" }, { key = "wrist", label = "Wrists", side = "left" },
  { key = "hands", label = "Hands", side = "right" }, { key = "waist", label = "Waist", side = "right" },
  { key = "legs", label = "Legs", side = "right" }, { key = "feet", label = "Feet", side = "right" },
  { key = "finger", label = "Ring", side = "right" }, { key = "finger2", label = "Second ring", side = "right" },
  { key = "keepsake", label = "Keepsake", side = "right" }, { key = "charm", label = "Charm", side = "right" },
  { key = "main", label = "Main hand", side = "bottom" }, { key = "off", label = "Off hand", side = "bottom" },
  { key = "carried", label = "Carried", side = "bottom" },
}
-- Where each slot sits in its column (or row): [key] = { side, position from 0 }
I.WEAR_PLACE = {}
do
  local n = {}
  for _, w in ipairs(I.WEAR) do
    n[w.side] = (n[w.side] or -1) + 1
    I.WEAR_PLACE[w.key] = { side = w.side, at = n[w.side] }
  end
end
I.WEAR_LABEL = {}
for _, w in ipairs(I.WEAR) do I.WEAR_LABEL[w.key] = w.label end

-- Item quality, as the game colours it. "ink" is the same colour darkened
-- for cream cards (Common falls back to the card's text colour).
I.QUALITY = {
  [0] = { label = "Poor",      color = { 0.62, 0.62, 0.62 }, ink = { 0.42, 0.42, 0.42 } },
  [1] = { label = "Common",    color = { 1, 1, 1 } },
  [2] = { label = "Uncommon",  color = { 0.12, 1, 0 },       ink = { 0.10, 0.48, 0.04 } },
  [3] = { label = "Rare",      color = { 0, 0.44, 0.87 },    ink = { 0.00, 0.33, 0.68 } },
  [4] = { label = "Epic",      color = { 0.64, 0.21, 0.93 }, ink = { 0.46, 0.14, 0.70 } },
  [5] = { label = "Legendary", color = { 1, 0.50, 0 },       ink = { 0.76, 0.36, 0.00 } },
}

-- A few hand-picked icons for when no icon picker is installed.
I.ICON_PRESETS = {
  "INV_Misc_Bag_08", "INV_Misc_Book_09", "INV_Misc_Note_01", "INV_Scroll_03", "INV_Letter_15", "INV_Box_01",
  "INV_Misc_Gem_01", "INV_Misc_Coin_01", "INV_Drink_05", "INV_Misc_Food_15", "INV_Potion_51", "INV_Misc_Key_03",
  "INV_Misc_Gift_01", "INV_Feather_05", "INV_Misc_Map_01", "INV_Misc_Spyglass_02", "INV_Misc_Toy_04", "INV_Misc_OrnateBox",
}

---------------------------------------------------------------------------
-- Small helpers (shared by Documents, Trade and Stashes)
---------------------------------------------------------------------------
-- Cut a string to at most max bytes without leaving half a UTF-8 character.
function I.Cut(s, max)
  if type(s) ~= "string" then return "" end
  if #s <= max then return s end
  s = s:sub(1, max)
  local i = #s
  while i > 0 do
    local b = s:byte(i)
    if b < 0x80 then return s end
    if b >= 0xC0 then return s:sub(1, i - 1) end
    i = i - 1
  end
  return s
end
local Cut = I.Cut

-- A finite number, or nil.
function I.Num(v)
  if type(v) == "number" and v == v and v ~= math.huge and v ~= -math.huge then return v end
end
local Num = I.Num

function I.Short(name) return K.Short(name, "someone") end

function I.Error(msg)
  if UIErrorsFrame and UIErrorsFrame.AddMessage then UIErrorsFrame:AddMessage(msg, 1, 0.25, 0.2) else K:Print(msg) end
end

-- An icon is a file ID (from the game's icon lists) or a path in Interface\Icons.
function I.ValidIcon(v)
  if type(v) == "number" then
    if v > 0 and v < 2147483647 and v == math.floor(v) then return v end
    return nil
  end
  if type(v) ~= "string" or #v > 120 then return nil end
  if v:find("^[%w_%-]+$") then return ICON_DIR .. v end
  if v:lower():find("^interface\\icons\\[%w_%-]+$") then return v end
  return nil
end

function I.IconTexture(v) return I.ValidIcon(v) or I.DEFAULT_ICON end

function I.Quality(q) return I.QUALITY[q] or I.QUALITY[1] end

-- The colour for a quality: as the game shows it (tooltips, the chrome), or
-- inked down for text on a cream card (Common uses the card's own text colour).
function I.QualityColor(q, onCard)
  local Q = I.Quality(q)
  if not onCard then return Q.color end
  if (q or 1) == 1 then return K:Theme().text end
  return UI.OnCard and UI.OnCard(Q.color) or (Q.ink or Q.color)
end

local function PixelSize()
  local _, ph = GetPhysicalScreenSize()
  local es = UIParent:GetEffectiveScale()
  if not ph or ph <= 0 or not es or es <= 0 then return 1 end
  return 768 / ph / es
end

---------------------------------------------------------------------------
-- Designs
---------------------------------------------------------------------------
function I:NewId()
  return ("%s#%d#%d"):format(K:MyName() or "?", time(), math.random(100000, 999999))
end

-- Check and copy a definition (yours, or one that arrived from someone else).
function I.Sanitize(raw)
  if type(raw) ~= "table" then return nil end
  local id = raw.id
  if type(id) ~= "string" or id == "" or #id > I.MAX.id then return nil end
  local name = strtrim(Cut(raw.name, I.MAX.name))
  if name == "" then return nil end
  local q = Num(raw.quality) or 1
  q = math.floor(q)
  if q < 0 or q > 5 then q = 1 end
  local stack = math.floor(Num(raw.stack) or 1)
  stack = math.max(1, math.min(I.MAX_STACK, stack))
  local doc = raw.documentId
  if type(doc) ~= "string" or doc == "" or #doc > 100 then doc = nil end
  return {
    id = id, name = name, icon = I.IconTexture(raw.icon), quality = q,
    description = Cut(raw.description, I.MAX.description),
    flavor = Cut(raw.flavor, I.MAX.flavor),
    useText = strtrim(Cut(raw.useText, I.MAX.useText)),
    stack = stack, consume = raw.consume == true or nil, documentId = doc,
    wear = I.WEAR_LABEL[raw.wear or ""] and raw.wear or nil,
    creator = Cut(raw.creator, I.MAX.creator), created = Num(raw.created), edited = Num(raw.edited),
  }
end

function I:Get(id)
  if type(id) ~= "string" then return nil end
  return K.db.itemDefs[id] or K.db.itemCache[id]
end

function I:IsMine(id) return type(id) == "string" and K.db.itemDefs[id] ~= nil end

-- A definition that arrived with an item. Your own designs always win; a
-- cached design is only replaced by a newer edit from the same creator.
function I:Learn(raw)
  local def = I.Sanitize(raw)
  if not def then return nil end
  if K.db.itemDefs[def.id] then return K.db.itemDefs[def.id] end
  local old = K.db.itemCache[def.id]
  if old and old.creator ~= def.creator then return old end
  if old and (old.edited or 0) > (def.edited or 0) then old.seen = time(); return old end
  def.seen = time()
  K.db.itemCache[def.id] = def
  K:Fire("ITEMDEFS", def)
  return def
end

-- A copy of a definition to send to someone.
function I:Pack(id)
  local def = self:Get(id)
  return def and I.Sanitize(def) or nil
end

-- Save a design from the Workshop. fields = { name, icon, quality, ... }.
function I:SaveDesign(fields, id)
  local now = time()
  local old = id and K.db.itemDefs[id]
  local raw = {}
  for k, v in pairs(fields) do raw[k] = v end
  raw.id = old and old.id or self:NewId()
  raw.creator = old and old.creator or K:MyName()
  raw.created = old and old.created or now
  raw.edited = now
  local def = I.Sanitize(raw)
  if not def then return nil, "Give the item a name first." end
  K.db.itemDefs[def.id] = def
  K:Fire("ITEMDEFS", def)
  return def
end

-- Deleting a design keeps the copies already made: they move to the cache.
function I:DeleteDesign(id)
  local def = K.db.itemDefs[id]
  if not def then return end
  K.db.itemDefs[id] = nil
  def.seen = time()
  K.db.itemCache[id] = def
  K:Fire("ITEMDEFS")
end

function I:Designs()
  local out = {}
  for _, def in pairs(K.db.itemDefs) do out[#out + 1] = def end
  table.sort(out, function(a, b) return (a.edited or 0) > (b.edited or 0) end)
  return out
end

---------------------------------------------------------------------------
-- Bags
---------------------------------------------------------------------------
function I:Bag()
  local key = K:CharKey()
  local inv = K.db.inventory[key]
  if type(inv) ~= "table" then inv = {}; K.db.inventory[key] = inv end
  if type(inv.slots) ~= "table" then inv.slots = {} end
  return inv.slots
end

function I:Slot(i) return self:Bag()[i] end

function I:CountOf(id)
  local n, bag = 0, self:Bag()
  for i = 1, self.SLOTS do
    local s = bag[i]
    if s and s.def == id then n = n + s.count end
  end
  return n
end

-- In your bags or on you (what you're wearing counts as carried).
function I:Has(id)
  local n = self:CountOf(id)
  if K.Worn then
    for _, e in pairs(K.Worn:Table()) do if e.def == id then n = n + 1 end end
  end
  return n
end

-- Copies promised to someone in a trade that hasn't finished yet.
function I:Reserved(id)
  return K.Trade and K.Trade.Reserved and K.Trade:Reserved("bag", id) or 0
end

function I:Available(id) return self:CountOf(id) - self:Reserved(id) end

function I:FreeSlots()
  local n, bag = 0, self:Bag()
  for i = 1, self.SLOTS do if not bag[i] then n = n + 1 end end
  return n
end

-- Put n of an item into a bag table (top up stacks, then empty slots).
-- Returns how many didn't fit.
local function Fill(bag, id, n, stack, slots)
  for i = 1, slots do
    if n <= 0 then return 0 end
    local s = bag[i]
    if s and s.def == id and s.count < stack then
      local k = math.min(n, stack - s.count)
      s.count = s.count + k
      n = n - k
    end
  end
  for i = 1, slots do
    if n <= 0 then return 0 end
    if not bag[i] then
      local k = math.min(n, stack)
      bag[i] = { def = id, count = k }
      n = n - k
    end
  end
  return math.max(0, n)
end

I.Fill = Fill   -- the vault fills its slots the same way

-- Would all of these fit? entries = { { id, n, stack }, ... }
function I:Fits(entries)
  local copy = {}
  for i = 1, self.SLOTS do
    local s = self:Bag()[i]
    if s then copy[i] = { def = s.def, count = s.count } end
  end
  for _, e in ipairs(entries) do
    if Fill(copy, e.id, e.n, e.stack or 1, self.SLOTS) > 0 then return false end
  end
  return true
end

-- Add n of an item you know the design of. Returns how many didn't fit.
function I:Add(id, n)
  local def = self:Get(id)
  if not def or type(n) ~= "number" or n <= 0 then return n or 0 end
  local left = Fill(self:Bag(), id, math.floor(n), def.stack, self.SLOTS)
  K:Fire("INVENTORY")
  return left
end

-- Remove n of an item, starting with slot `prefer`. All or nothing.
function I:Remove(id, n, prefer)
  if self:CountOf(id) < n then return false end
  local bag = self:Bag()
  local function take(i)
    local s = bag[i]
    if n > 0 and s and s.def == id then
      local k = math.min(n, s.count)
      s.count = s.count - k
      n = n - k
      if s.count <= 0 then bag[i] = nil end
    end
  end
  if prefer then take(prefer) end
  for i = self.SLOTS, 1, -1 do take(i) end
  K:Fire("INVENTORY")
  return true
end

-- Drag and drop: merge onto a matching stack, otherwise swap.
function I:Move(from, to)
  if from == to or not from or not to or to < 1 or to > self.SLOTS then return end
  local bag = self:Bag()
  local a, b = bag[from], bag[to]
  if not a then return end
  if b and b.def == a.def then
    local def = self:Get(a.def)
    local k = math.min(a.count, (def and def.stack or 1) - b.count)
    if k > 0 then
      b.count = b.count + k
      a.count = a.count - k
      if a.count <= 0 then bag[from] = nil end
    else
      bag[from], bag[to] = b, a
    end
  else
    bag[from], bag[to] = b, a
  end
  K:Fire("INVENTORY")
  return true
end

-- Split n off a stack into the first empty slot. Returns the new slot.
function I:Split(slot, n)
  local bag = self:Bag()
  local s = bag[slot]
  if not s or n <= 0 or n >= s.count then return nil end
  for i = 1, self.SLOTS do
    if not bag[i] then
      bag[i] = { def = s.def, count = n }
      s.count = s.count - n
      K:Fire("INVENTORY")
      return i
    end
  end
  I.Error("There's no empty slot to split the stack into.")
end

function I:Destroy(slot)
  local s = self:Bag()[slot]
  if not s then return end
  if self:Reserved(s.def) > 0 then I.Error("That item is promised in a trade.") return end
  self:Bag()[slot] = nil
  if SOUNDKIT and SOUNDKIT.IG_BACKPACK_CLOSE then PlaySound(SOUNDKIT.IG_BACKPACK_CLOSE) end
  K:Fire("INVENTORY")
end

---------------------------------------------------------------------------
-- Using and reading
---------------------------------------------------------------------------
-- Performs the item's emote (only ever call this from a click) and/or opens
-- its document. Consumable items are used up.
function I:Use(slot)
  local s = self:Bag()[slot]
  local def = s and self:Get(s.def)
  if not def then return end
  local did = false
  if def.useText ~= "" then
    if GetTime() - (self.lastUse or 0) < 1.5 then return end
    if def.consume and self:Available(def.id) < 1 then I.Error("That item is promised in a trade.") return end
    self.lastUse = GetTime()
    local line = strtrim((def.useText:gsub("[|\r\n]", " ")))
    line = Cut(line, 255)
    local send = C_ChatInfo and C_ChatInfo.SendChatMessage or SendChatMessage
    if send and line ~= "" then pcall(send, line, "EMOTE") end
    did = true
    if def.consume then self:Remove(def.id, 1, slot) end
  end
  if def.documentId then
    self:Read(def)
    did = true
  end
  -- Something to wear and nothing else to do: put it on.
  if not did and def.wear and K.Worn then K.Worn:Wear(slot) return end
  if not did then I.Error(UI.Escape(def.name) .. " has no use.") end
end

function I:Read(def)
  if type(def) == "string" then def = self:Get(def) end
  if not def or not def.documentId then return end
  if not K:ExtOn("documents") then I.Error("Documents are switched off (Settings > Extended features).") return end
  if K.Documents and K.Documents.Open then K.Documents:Open(def.documentId) end
end

---------------------------------------------------------------------------
-- Tooltip
---------------------------------------------------------------------------
-- Fill a game tooltip for an item. item = a definition or its id.
function I:FillTooltip(tt, item, count)
  local def = type(item) == "table" and item or self:Get(item)
  if not def then
    tt:SetText("Unknown item", 0.62, 0.62, 0.62)
    tt:AddLine("Its description never reached you.", 1, 1, 1, true)
    return
  end
  local c = I.Quality(def.quality).color
  tt:SetText(UI.Escape(def.name), c[1], c[2], c[3], 1, true)
  local right = ""
  if def.stack > 1 then right = count and ("%d / %d"):format(count, def.stack) or ("Stacks to %d"):format(def.stack) end
  tt:AddDoubleLine(I.Quality(def.quality).label .. " item", right, 0.62, 0.62, 0.62, 0.62, 0.62, 0.62)
  if def.description ~= "" then tt:AddLine(UI.Clean(def.description), 1, 1, 1, true) end
  if def.useText ~= "" then
    tt:AddLine("Use: " .. UI.Escape(def.useText) .. (def.consume and " (used up)" or ""), 0.12, 1, 0, true)
  end
  if def.documentId then
    local doc = K.Documents and K.Documents:Get(def.documentId)
    tt:AddLine(doc and ("Read: " .. UI.Escape(doc.title ~= "" and doc.title or "Untitled")) or "Its writing never reached you.",
      0.55, 0.80, 1, true)
  end
  if def.wear and I.WEAR_LABEL[def.wear] then tt:AddLine("Worn on: " .. I.WEAR_LABEL[def.wear], 0.55, 0.80, 1) end
  if def.flavor ~= "" then tt:AddLine("\"" .. UI.Clean(def.flavor) .. "\"", 1, 0.82, 0, true) end
  if def.creator ~= "" then tt:AddLine("Made by " .. UI.Escape(I.Short(def.creator)), 0.55, 0.55, 0.55) end
end

function I:ShowTooltip(owner, item, count, anchor)
  GameTooltip:SetOwner(owner, anchor or "ANCHOR_RIGHT")
  self:FillTooltip(GameTooltip, item, count)
  GameTooltip:Show()
end

-- "[Name] x3" in quality colour, for chat lines and toasts (dark backgrounds).
function I:Label(def, count)
  if not def then return "an unknown item" end
  local c = I.Quality(def.quality).color
  return ("|cff%s[%s]|r%s"):format(UI.Hex(c), UI.Escape(def.name), (count and count > 1) and (" x" .. count) or "")
end

---------------------------------------------------------------------------
-- Item slot widget: a rounded well with the icon, a quality-coloured edge,
-- a count, a hover glow and a little lift. Used by the bags, the give
-- window and stashes. slot:SetItem(def, count), slot:SetSelected(v),
-- slot:SetLocked(v), slot:Pop(). Hook OnEnter/OnLeave/OnClick freely.
---------------------------------------------------------------------------
function I.NewSlot(parent, size)
  local b = CreateFrame("Button", nil, parent)
  b:SetSize(size, size)
  local e = PixelSize()
  local inner = size - 8
  b.inner = inner

  b.well = b:CreateTexture(nil, "BACKGROUND")
  b.well:SetTexture(WHITE)
  b.well:SetPoint("TOPLEFT", e, -e)
  b.well:SetPoint("BOTTOMRIGHT", -e, e)
  b.icon = b:CreateTexture(nil, "ARTWORK")
  b.icon:SetSize(inner, inner)
  b.icon:SetPoint("CENTER")
  b.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
  b.glow = b:CreateTexture(nil, "ARTWORK", nil, 2)
  b.glow:SetTexture(WHITE)
  b.glow:SetPoint("BOTTOMLEFT", 2, 2)
  b.glow:SetPoint("BOTTOMRIGHT", -2, 2)
  b.glow:SetHeight(math.floor(size * 0.65))
  b.shine = b:CreateTexture(nil, "ARTWORK", nil, 3)
  b.shine:SetAllPoints(b.icon)
  b.shine:SetColorTexture(1, 1, 1, 1)
  b.shine:SetBlendMode("ADD")
  b.shine:SetAlpha(0)
  b.lock = b:CreateTexture(nil, "ARTWORK", nil, 4)
  b.lock:SetAllPoints(b.icon)
  b.lock:SetColorTexture(0, 0, 0, 0.45)
  b.lock:Hide()

  -- Rounded edge: four strips stopping short of the corners, and a pixel in each corner.
  b.edges = {}
  local function strip()
    local t = b:CreateTexture(nil, "OVERLAY", nil, 1)
    t:SetTexture(WHITE)
    b.edges[#b.edges + 1] = t
    return t
  end
  local top = strip(); top:SetHeight(e); top:SetPoint("TOPLEFT", 2 * e, 0); top:SetPoint("TOPRIGHT", -2 * e, 0)
  local bot = strip(); bot:SetHeight(e); bot:SetPoint("BOTTOMLEFT", 2 * e, 0); bot:SetPoint("BOTTOMRIGHT", -2 * e, 0)
  local lft = strip(); lft:SetWidth(e); lft:SetPoint("TOPLEFT", 0, -2 * e); lft:SetPoint("BOTTOMLEFT", 0, 2 * e)
  local rgt = strip(); rgt:SetWidth(e); rgt:SetPoint("TOPRIGHT", 0, -2 * e); rgt:SetPoint("BOTTOMRIGHT", 0, 2 * e)
  for _, p in ipairs({ { "TOPLEFT", e, -e }, { "TOPRIGHT", -e, -e }, { "BOTTOMLEFT", e, e }, { "BOTTOMRIGHT", -e, e } }) do
    local t = strip()
    t:SetSize(e, e)
    t:SetPoint(p[1], p[2], p[3])
  end

  -- Selection ring, just outside the edge
  b.ring = CreateFrame("Frame", nil, b)
  b.ring:SetPoint("TOPLEFT", -3, 3)
  b.ring:SetPoint("BOTTOMRIGHT", 3, -3)
  b.ring.edge = UI.Border(b.ring)
  b.ring:Hide()

  b.count = b:CreateFontString(nil, "OVERLAY", nil, 2)
  b.count:SetFontObject(UI.FONTS.Small)
  b.count:SetPoint("BOTTOMRIGHT", -4, 4)
  b.count:SetJustifyH("RIGHT")
  b.count:SetTextColor(1, 1, 1)

  b.popKey = {}

  function b:Paint()
    local t = K:Theme()
    local p = UI.Progress(self)
    local has = self.def ~= nil or self.unknown
    if t.light then
      self.well:SetVertexColor(0.30, 0.20, 0.08, has and 0.16 or 0.08)
    else
      self.well:SetVertexColor(0, 0, 0, has and 0.45 or 0.28)
    end
    local q = self.quality
    local qc = q and I.Quality(q).color
    local er, eg, eb, ea
    if has and q and q >= 2 then
      er, eg, eb, ea = qc[1], qc[2], qc[3], 0.75 + 0.25 * p
    else
      local base = t.panelEdge
      local acc = t.accent
      er, eg, eb, ea = UI.Mix(base, { acc[1], acc[2], acc[3], has and 0.85 or 0.45 }, p)
      if has then ea = math.max(ea, t.light and 0.45 or 0.22) end
    end
    for _, s in ipairs(self.edges) do s:SetVertexColor(er, eg, eb, ea) end
    local gc = (has and qc and q >= 1) and qc or t.accent
    local ga = has and (0.10 + 0.26 * p) or 0.10 * p
    if q and q >= 2 and has then ga = ga + 0.06 end
    if self.glow.SetGradient and CreateColor then
      self.glow:SetGradient("VERTICAL", CreateColor(gc[1], gc[2], gc[3], ga), CreateColor(gc[1], gc[2], gc[3], 0))
    else
      self.glow:SetVertexColor(gc[1], gc[2], gc[3], ga * 0.5)
    end
    self.shine:SetAlpha(has and 0.10 * p or 0)
    local a = t.accent
    self.ring.edge:SetColor(a[1], a[2], a[3], 1)
    local pop = UI.Progress(self.popKey)
    local grow = (pop > 0 and pop < 1) and (1 - pop) * 0.18 or 0
    local sz = self.inner * (1 + grow) + 2 * p
    self.icon:SetSize(sz, sz)
  end

  function b:SetItem(def, count, unknown)
    self.def, self.n, self.unknown = def, count, (not def and unknown) and true or nil
    if def then
      self.icon:SetTexture(I.IconTexture(def.icon))
      self.icon:Show()
      self.quality = def.quality
    elseif self.unknown then
      self.icon:SetTexture(I.DEFAULT_ICON)
      self.icon:Show()
      self.quality = 0
    else
      self.icon:Hide()
      self.quality = nil
    end
    self.count:SetText((count and count > 1) and tostring(count) or "")
    self:Paint()
  end

  function b:SetSelected(v) self.ring:SetShown(v and true or false) end
  function b:SetLocked(v)
    self.lock:SetShown(v and true or false)
    self.icon:SetDesaturated(v and true or false)
  end
  -- A little bounce when something lands in the slot.
  function b:Pop()
    UI.SetProgress(self.popKey, 0)
    UI.Tween(self.popKey, 1, 0.28, function() self:Paint() end, UI.Ease.outQuart)
  end

  local function paint() b:Paint() end
  b:SetScript("OnEnter", function(self)
    UI.Tween(self, 1, 0.12, paint)
    if self.def or self.unknown then I:ShowTooltip(self, self.def, self.n, self.tooltipAnchor) end
  end)
  b:SetScript("OnLeave", function(self)
    UI.Tween(self, 0, 0.15, paint)
    GameTooltip:Hide()
  end)
  UI:OnTheme(function()
    local face, fsize = UI.FONTS.Small:GetFont()
    if face then b.count:SetFont(face, fsize, "OUTLINE") end
    b:Paint()
  end)
  b:SetItem(nil)
  return b
end

---------------------------------------------------------------------------
-- Choosing an icon: Kinship's icon picker when it's there, otherwise a
-- small chooser with hand-picked icons and a field for any icon name.
---------------------------------------------------------------------------
local chooser
local function BuildChooser()
  local f = CreateFrame("Frame", "KinshipRPItemIconChooser", UIParent)
  f:SetSize(292, 214)
  f:SetFrameStrata("FULLSCREEN_DIALOG")
  f:SetClampedToScreen(true)
  f:EnableMouse(true)
  f.bg = f:CreateTexture(nil, "BACKGROUND")
  f.bg:SetAllPoints()
  f.edge = UI.Border(f)
  UI:OnTheme(function(t)
    f.bg:SetColorTexture(unpack(t.chrome))
    f.edge:SetColor(unpack(t.chromeEdge))
  end)
  local title = UI.Text(f, "Choose an icon", "Header", "deskHeading")
  title:SetPoint("TOPLEFT", 14, -12)
  local close = UI.CloseButton(f, false, 20)
  close:SetPoint("TOPRIGHT", -6, -6)
  f.buttons = {}
  for i, name in ipairs(I.ICON_PRESETS) do
    local b = CreateFrame("Button", nil, f)
    b:SetSize(38, 38)
    b:SetPoint("TOPLEFT", 14 + ((i - 1) % 6) * 44, -38 - math.floor((i - 1) / 6) * 44)
    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetAllPoints()
    b.icon:SetTexture(ICON_DIR .. name)
    b.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    b.edge = UI.Border(b, { 1, 1, 1, 0.15 })
    b:SetScript("OnEnter", function(self) self.edge:SetColor(1, 1, 1, 0.7) end)
    b:SetScript("OnLeave", function(self) self.edge:SetColor(1, 1, 1, 0.15) end)
    b:SetScript("OnClick", function()
      f:Hide()
      if f.onPick then f.onPick(ICON_DIR .. name) end
    end)
    f.buttons[i] = b
  end
  f.field = UI.Edit(f, 184, 24, "desk", 80)
  f.field:SetPoint("BOTTOMLEFT", 14, 14)
  f.hint = UI.Text(f.field, "or type an icon name", "Small", "deskSubtle")
  f.hint:SetPoint("LEFT", 8, 0)
  f.field:HookScript("OnTextChanged", function(self) f.hint:SetShown(self:GetText() == "") end)
  f.ok = UI.Button(f, "Use", 70, 24)
  f.ok:SetPoint("BOTTOMRIGHT", -14, 14)
  local function accept()
    local v = I.ValidIcon(strtrim(f.field:GetText() or ""))
    if not v then I.Error("That isn't an icon name (try INV_Misc_Bag_08).") return end
    f:Hide()
    if f.onPick then f.onPick(v) end
  end
  f.ok:SetScript("OnClick", accept)
  f.field:SetScript("OnEnterPressed", accept)
  tinsert(UISpecialFrames, "KinshipRPItemIconChooser")
  f:SetScript("OnShow", function(self) UI.FadeIn(self, 0.15) end)
  f:Hide()
  return f
end

function I:ChooseIcon(anchor, current, onPick)
  if K.IconPicker and type(K.IconPicker.Open) == "function" then
    local ok = K.Try("icon picker", K.IconPicker.Open, K.IconPicker, anchor, current, function(icon)
      local v = I.ValidIcon(icon)
      if v then onPick(v) end
    end)
    if ok then return end
  end
  chooser = chooser or BuildChooser()
  chooser.onPick = onPick
  chooser.field:SetText("")
  chooser:ClearAllPoints()
  chooser:SetPoint("TOPLEFT", anchor, "TOPRIGHT", 8, 0)
  chooser:Show()
  chooser:Raise()
end

---------------------------------------------------------------------------
-- Saved data
---------------------------------------------------------------------------
-- Forget received designs nobody carries any more.
local function PruneCache()
  local used = {}
  for _, inv in pairs(K.db.inventory) do
    if type(inv) == "table" and type(inv.slots) == "table" then
      for _, s in pairs(inv.slots) do if type(s) == "table" and s.def then used[s.def] = true end end
    end
  end
  for _, box in pairs(K.db.stashes or {}) do
    for _, st in ipairs(type(box) == "table" and box.list or {}) do
      for _, it in ipairs(st.items or {}) do used[it.def] = true end
    end
  end
  local cutoff = time() - CACHE_DAYS * 86400
  for id, def in pairs(K.db.itemCache) do
    if not used[id] and (type(def) ~= "table" or (def.seen or 0) < cutoff) then K.db.itemCache[id] = nil end
  end
end

K:On("LOGIN", function()
  K.db.itemDefs = K.db.itemDefs or {}
  K.db.itemCache = K.db.itemCache or {}
  K.db.inventory = K.db.inventory or {}
  K.db.stashes = K.db.stashes or {}
  local s = K.db.settings
  if s.itemOffers == nil then s.itemOffers = true end
  if s.stashAnswer == nil then s.stashAnswer = true end
  I:Bag()
  K.Try("items", PruneCache)
end)

K:RegisterSettings({ id = "items", title = "Items & stashes", order = 40,
  shown = function() return K:ExtOn("inventory") end, build = function(card)
  card:Toggle("Accept item offers", "Other players can offer you items. Turn off to turn every offer away.", "itemOffers")
  card:Toggle("Answer area searches", "Players searching nearby can find your stashes.", "stashAnswer")
  card:Toggle("Kinship items in the trade window", "A card beside the trade window when you trade with another Kinship player, to swap Kinship items as part of the trade. Off, your trades are ordinary game trades.", {
    get = function() return K.db.settings.tradeCard ~= false end,
    set = function(v) K.db.settings.tradeCard = v end,
  })
  card:Toggle("Kinship vault at the bank", "Thirty more slots that open beside the bank when you talk to a banker.", {
    get = function() return K.db.settings.vault ~= false end,
    set = function(v) K.db.settings.vault = v; if not v and K.Vault then K.Vault:Hide() end end,
  })
  card:Toggle("Satchel button by your bags", "A small bag beside your bag bar that opens your roleplay satchel.", {
    get = function() return K.db.settings.satchelButton ~= false end,
    set = function(v) K.db.settings.satchelButton = v; if K.Satchel then K.Satchel:PlaceButton() end end,
  })
  card:Toggle("Open the satchel with your bags", "Your roleplay satchel opens and closes with your game bags, docked beside them.", {
    get = function() return K.db.settings.satchelWithBags ~= false end,
    set = function(v) K.db.settings.satchelWithBags = v end,
  })
  card:Toggle("Keep the satchel minimised", "It still comes up with your bags, but as a thin strip beside them, until you click it. Handy when you're not roleplaying.", {
    get = function() return K.db.settings.satchelMin and true or false end,
    set = function(v) if K.Satchel then K.Satchel:SetCollapsed(v) else K.db.settings.satchelMin = v or nil end end,
  })
end })
