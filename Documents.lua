-- Kinship RP: documents. Multi-page books, notices and contracts that you
-- write at a desk on the Inventory page, read in a paper window with page
-- turns, and hand over attached to items (the document travels with the item).

local ADDON, ns = ...
local K = ns.K
local UI = K.UI
local I = K.Items
local Cut, Num = I.Cut, I.Num
local D = { MAX_PAGES = 10, MAX_PAGE = 1600, MAX_TITLE = 80 }
K.Documents = D

local WHITE = "Interface\\Buttons\\WHITE8X8"

-- Paper styles. Fixed colours: documents are paper whatever the page around them.
D.STYLES = {
  parchment = { label = "Parchment", paper = { 0.955, 0.925, 0.850 }, edge = { 0.30, 0.20, 0.08, 0.40 },
                rule = { 0.45, 0.32, 0.15, 0.16 }, grainA = 0, tint = { 1, 1, 1 },
                ink = { 0.19, 0.17, 0.13 }, sub = { 0.45, 0.36, 0.24 }, head = { 0.30, 0.16, 0.04 } },
  vellum    = { label = "Vellum", paper = { 0.975, 0.968, 0.940 }, edge = { 0.32, 0.30, 0.27, 0.35 },
                rule = { 0.36, 0.34, 0.30, 0.12 }, grainA = 0, tint = { 1, 1, 1 },
                ink = { 0.15, 0.15, 0.17 }, sub = { 0.42, 0.41, 0.40 }, head = { 0.12, 0.15, 0.26 } },
  dark      = { label = "Dark", paper = { 0.115, 0.100, 0.085 }, edge = { 0.94, 0.82, 0.54, 0.35 },
                rule = { 0.94, 0.82, 0.54, 0.16 }, grainA = 0, tint = { 0.55, 0.50, 0.45 },
                ink = { 0.90, 0.86, 0.78 }, sub = { 0.68, 0.62, 0.52 }, head = { 0.96, 0.84, 0.56 } },
  notice    = { label = "Notice", paper = { 0.880, 0.800, 0.610 }, edge = { 0.36, 0.24, 0.10, 0.55 },
                rule = { 0.36, 0.24, 0.10, 0.22 }, grainA = 0, tint = { 1, 0.90, 0.70 },
                ink = { 0.20, 0.14, 0.08 }, sub = { 0.42, 0.30, 0.16 }, head = { 0.40, 0.10, 0.06 }, pin = true },
}
D.STYLE_ORDER = { "parchment", "vellum", "dark", "notice" }

local function Style(key) return D.STYLES[key] or D.STYLES.parchment end

function D.SealLabel(key)
  for _, s in ipairs(UI.SEAL_COLORS) do if s.key == key then return s.label end end
  return "Crimson"
end

local function ValidSeal(key)
  if type(key) ~= "string" then return nil end
  for _, s in ipairs(UI.SEAL_COLORS) do if s.key == key then return key end end
  return nil
end

---------------------------------------------------------------------------
-- Data
---------------------------------------------------------------------------
function D:Get(id)
  if type(id) ~= "string" then return nil end
  return K.db.documents[id] or K.db.docCache[id]
end

function D:IsMine(id) return type(id) == "string" and K.db.documents[id] ~= nil end

function D.Sanitize(raw)
  if type(raw) ~= "table" or type(raw.id) ~= "string" or raw.id == "" or #raw.id > 100 then return nil end
  local pages = {}
  if type(raw.pages) == "table" then
    for i = 1, D.MAX_PAGES do
      local p = raw.pages[i]
      if type(p) ~= "string" then break end
      pages[i] = Cut(p, D.MAX_PAGE)
    end
  end
  if #pages == 0 then pages[1] = "" end
  return {
    id = raw.id, title = strtrim(Cut(raw.title, D.MAX_TITLE)), pages = pages,
    style = D.STYLES[raw.style] and raw.style or "parchment", seal = ValidSeal(raw.seal),
    author = Cut(raw.author, 60), created = Num(raw.created), edited = Num(raw.edited),
  }
end

function D:New(title)
  local now = time()
  local doc = {
    id = ("doc#%s#%d#%d"):format(K:MyName() or "?", now, math.random(100000, 999999)),
    title = title or "", pages = { "" }, style = "parchment", author = K:MyName(), created = now, edited = now,
  }
  K.db.documents[doc.id] = doc
  K:Fire("DOCUMENTS", doc)
  return doc
end

function D:Touched(doc)
  doc.edited = time()
  if self.reader and self.reader:IsShown() and self.reader.doc == doc then self:RenderReader(false) end
end

function D:Delete(id)
  if not K.db.documents[id] then return end
  K.db.documents[id] = nil
  K:Fire("DOCUMENTS")
end

-- Your own editable copy of someone else's document.
function D:Copy(id)
  local src = self:Get(id)
  if not src then return nil end
  local doc = self:New(src.title)
  for i, p in ipairs(src.pages) do doc.pages[i] = p end
  doc.style, doc.seal = src.style, src.seal
  K:Fire("DOCUMENTS", doc)
  return doc
end

-- Documents carried by items in your bags or stashes can't be forgotten.
function D:InUse(id)
  for _, s in pairs(I:Bag()) do
    local def = I:Get(s.def)
    if def and def.documentId == id then return true end
  end
  return false
end

function D:Forget(id)
  if K.db.docCache[id] and not self:InUse(id) then K.db.docCache[id] = nil; K:Fire("DOCUMENTS") end
end

-- A document that arrived with an item. Your own always win; a cached copy is
-- only replaced by a newer edit from the same author.
function D:Learn(raw)
  local doc = D.Sanitize(raw)
  if not doc then return nil end
  if K.db.documents[doc.id] then return K.db.documents[doc.id] end
  local old = K.db.docCache[doc.id]
  if old and old.author ~= doc.author then return old end
  if old and (old.edited or 0) > (doc.edited or 0) then old.seen = time(); return old end
  doc.seen = time()
  K.db.docCache[doc.id] = doc
  K:Fire("DOCUMENTS", doc)
  return doc
end

function D:Pack(id)
  local doc = self:Get(id)
  return doc and D.Sanitize(doc) or nil
end

function D:List()
  local mine, theirs = {}, {}
  for _, d in pairs(K.db.documents) do mine[#mine + 1] = d end
  for _, d in pairs(K.db.docCache) do theirs[#theirs + 1] = d end
  table.sort(mine, function(a, b) return (a.edited or 0) > (b.edited or 0) end)
  table.sort(theirs, function(a, b) return (a.seen or 0) > (b.seen or 0) end)
  for _, d in ipairs(theirs) do mine[#mine + 1] = d end
  return mine
end

function D.Title(doc) return (doc and doc.title ~= "") and doc.title or "Untitled" end

---------------------------------------------------------------------------
-- Page text: plain text with a little structure.
--   # Heading     ## Subheading     --- a rule
---------------------------------------------------------------------------
local function Blocks(text)
  local out, para = {}, {}
  local function flush()
    if #para > 0 then out[#out + 1] = { kind = "p", text = table.concat(para, "\n") }; para = {} end
  end
  for line in ((text or "") .. "\n"):gmatch("(.-)\r?\n") do
    local h2 = line:match("^##%s+(.+)$")
    local h1 = not h2 and line:match("^#%s+(.+)$")
    if h2 then flush(); out[#out + 1] = { kind = "h2", text = h2 }
    elseif h1 then flush(); out[#out + 1] = { kind = "h1", text = h1 }
    elseif line:match("^%s*%-%-%-+%s*$") then flush(); out[#out + 1] = { kind = "rule" }
    else para[#para + 1] = line end
  end
  flush()
  -- Trim blank lines at the very start and end of the page
  while out[1] and out[1].kind == "p" and strtrim(out[1].text) == "" do table.remove(out, 1) end
  while out[#out] and out[#out].kind == "p" and strtrim(out[#out].text) == "" do table.remove(out) end
  return out
end

-- Lay the blocks out in a scroll child, reusing font strings and rules.
local function RenderBlocks(r, text, st, width)
  local y, nfs, nrule = 0, 0, 0
  for _, b in ipairs(Blocks(text)) do
    if b.kind == "rule" then
      nrule = nrule + 1
      local t = r.rules[nrule]
      if not t then
        t = r.child:CreateTexture(nil, "ARTWORK")
        t:SetTexture(WHITE)
        r.rules[nrule] = t
      end
      t:SetVertexColor(st.sub[1], st.sub[2], st.sub[3], 0.45)
      t:SetSize(math.floor(width * 0.4), 1)
      t:ClearAllPoints()
      t:SetPoint("TOP", r.child, "TOP", 0, -(y + 9))
      t:Show()
      y = y + 20
    else
      nfs = nfs + 1
      local f = r.pool[nfs]
      if not f then
        f = r.child:CreateFontString(nil, "OVERLAY")
        f:SetJustifyV("TOP")
        r.pool[nfs] = f
      end
      local head = b.kind ~= "p"
      f:SetFontObject(UI.Font(b.kind == "h1" and "Title" or (b.kind == "h2" and "Header" or "Read")))
      f:SetWidth(width)
      f:SetSpacing(head and 0 or 4)
      f:SetJustifyH(head and "CENTER" or "LEFT")
      local c = head and st.head or st.ink
      f:SetTextColor(c[1], c[2], c[3])
      f:SetText(UI.Escape(b.text))
      f:ClearAllPoints()
      f:SetPoint("TOPLEFT", r.child, "TOPLEFT", 0, -(y + (head and 4 or 0)))
      f:Show()
      y = y + f:GetStringHeight() + (head and 12 or 12)
    end
  end
  for i = nfs + 1, #r.pool do r.pool[i]:Hide() end
  for i = nrule + 1, #r.rules do r.rules[i]:Hide() end
  r.child:SetHeight(math.max(1, y))
end

---------------------------------------------------------------------------
-- Paper (the Letters look: soft shadow, ruled margin) in a document style
---------------------------------------------------------------------------
function D.Paper(parent)
  local p = CreateFrame("Frame", nil, parent)
  p.shadow = parent:CreateTexture(nil, "BACKGROUND", nil, 1)
  p.shadow:SetColorTexture(0, 0, 0, 0.35)
  p.shadow:SetPoint("TOPLEFT", p, "TOPLEFT", 3, -3)
  p.shadow:SetPoint("BOTTOMRIGHT", p, "BOTTOMRIGHT", 3, -3)
  p.bg = p:CreateTexture(nil, "BACKGROUND", nil, -2)
  p.bg:SetAllPoints()
  p.bg:SetTexture(WHITE)
  p.grain = p:CreateTexture(nil, "BACKGROUND", nil, -1)
  p.grain:SetAllPoints()
  p.edge = UI.Border(p)
  p.rule = CreateFrame("Frame", nil, p)
  p.rule:SetPoint("TOPLEFT", 9, -9)
  p.rule:SetPoint("BOTTOMRIGHT", -9, 9)
  p.rule.edge = UI.Border(p.rule)
  -- A nail for notices
  p.pinShadow = UI.Circle(p, 14, "OVERLAY", 0)
  p.pinShadow:SetPoint("TOP", 1, -8)
  p.pinShadow:SetVertexColor(0, 0, 0, 0.35)
  p.pin = UI.Circle(p, 12, "OVERLAY", 1)
  p.pin:SetPoint("TOP", 0, -7)
  p.pin:SetVertexColor(0.42, 0.12, 0.08, 1)
  p.pinShine = UI.Circle(p, 4, "OVERLAY", 2)
  p.pinShine:SetPoint("CENTER", p.pin, "CENTER", -2, 2)
  p.pinShine:SetVertexColor(1, 1, 1, 0.45)
  function p:SetStyle(key)
    local st = Style(key)
    self.bg:SetVertexColor(st.paper[1], st.paper[2], st.paper[3], 1)
    if st.grain and st.grainA > 0 then
      self.grain:SetTexture(K.MEDIA .. st.grain, "REPEAT", "REPEAT")
      if self.grain.SetHorizTile then self.grain:SetHorizTile(true); self.grain:SetVertTile(true) end
      self.grain:SetVertexColor(st.tint[1], st.tint[2], st.tint[3], st.grainA)
      self.grain:Show()
    else
      self.grain:Hide()
    end
    self.edge:SetColor(unpack(st.edge))
    self.rule.edge:SetColor(unpack(st.rule))
    for _, t in ipairs({ self.pin, self.pinShadow, self.pinShine }) do t:SetShown(st.pin and true or false) end
  end
  p:SetStyle("parchment")
  return p
end

---------------------------------------------------------------------------
-- The reader window
---------------------------------------------------------------------------
local RW, RH = 480, 620

function D:BuildReader()
  if self.reader then return self.reader end
  local f = UI.Window("KinshipRPDocument", "Document", RW, RH)
  f:SetFrameStrata("DIALOG")
  self.reader = f

  local paper = D.Paper(f)
  paper:SetPoint("TOPLEFT", 16, -50)
  paper:SetPoint("BOTTOMRIGHT", -16, 16)
  f.paper = paper
  local PW = RW - 32
  local IW = PW - 72
  f.IW = IW

  -- Everything that turns with the page lives on the leaf.
  local leaf = CreateFrame("Frame", nil, paper)
  leaf:SetSize(PW, RH - 66)
  leaf:SetPoint("TOPLEFT")
  f.leaf = leaf

  leaf.title = leaf:CreateFontString(nil, "OVERLAY")
  leaf.title:SetFontObject(UI.FONTS.Huge)
  leaf.title:SetWidth(IW)
  leaf.title:SetJustifyH("CENTER")
  leaf.title:SetPoint("TOP", 0, -36)
  leaf.ornament = leaf:CreateTexture(nil, "ARTWORK")
  leaf.ornament:SetTexture(WHITE)
  leaf.ornament:SetSize(120, 1)
  leaf.diamond = leaf:CreateTexture(nil, "ARTWORK", nil, 1)
  leaf.diamond:SetTexture(WHITE)
  leaf.diamond:SetSize(6, 6)
  leaf.diamond:SetRotation(math.rad(45))
  leaf.running = leaf:CreateFontString(nil, "OVERLAY")
  leaf.running:SetFontObject(UI.FONTS.Label)
  leaf.running:SetWidth(IW)
  leaf.running:SetJustifyH("CENTER")
  leaf.running:SetPoint("TOP", 0, -28)
  leaf.runLine = leaf:CreateTexture(nil, "ARTWORK")
  leaf.runLine:SetTexture(WHITE)
  leaf.runLine:SetSize(IW, 1)
  leaf.runLine:SetPoint("TOP", 0, -46)

  local sf = CreateFrame("ScrollFrame", nil, leaf)
  local child = CreateFrame("Frame", nil, sf)
  child:SetSize(IW, 1)
  sf:SetScrollChild(child)
  f.body = { sf = sf, child = child, pool = {}, rules = {} }
  f.scroll = UI.ScrollBar(sf, true, 40)

  leaf.seal = UI.Seal(leaf, 54)
  leaf.seal:SetPoint("BOTTOMRIGHT", -38, 58)

  f.counter = paper:CreateFontString(nil, "OVERLAY")
  f.counter:SetFontObject(UI.FONTS.Small)
  f.counter:SetPoint("BOTTOM", 0, 26)
  f.prev = UI.Button(paper, "Previous", 86, 24)
  f.prev:SetPoint("BOTTOMLEFT", 22, 20)
  f.prev:SetScript("OnClick", function() D:Turn(-1) end)
  f.next = UI.Button(paper, "Next", 86, 24)
  f.next:SetPoint("BOTTOMRIGHT", -22, 20)
  f.next:SetScript("OnClick", function() D:Turn(1) end)

  f.turnKey = {}
  f:HookScript("OnHide", function() f.doc = nil end)
  return f
end

-- Draw the current page. Called with the leaf at rest or mid-turn.
function D:RenderReader(resetScroll)
  local f = self.reader
  local doc = f and f.doc
  if not doc then return end
  local st = Style(doc.style)
  local n = #doc.pages
  f.page = math.max(1, math.min(f.page or 1, n))
  f.paper:SetStyle(doc.style)
  f:SetTitle(UI.Escape(D.Title(doc)))
  local leaf, first, last = f.leaf, f.page == 1, f.page == n

  leaf.title:SetShown(first)
  leaf.ornament:SetShown(first)
  leaf.diamond:SetShown(first)
  leaf.running:SetShown(not first)
  leaf.runLine:SetShown(not first)
  local top
  if first then
    leaf.title:SetText(UI.Escape(D.Title(doc)))
    leaf.title:SetTextColor(st.head[1], st.head[2], st.head[3])
    local th = leaf.title:GetStringHeight()
    leaf.ornament:ClearAllPoints()
    leaf.ornament:SetPoint("TOP", 0, -(36 + th + 12))
    leaf.ornament:SetVertexColor(st.sub[1], st.sub[2], st.sub[3], 0.6)
    leaf.diamond:ClearAllPoints()
    leaf.diamond:SetPoint("CENTER", leaf.ornament, "CENTER")
    leaf.diamond:SetVertexColor(st.head[1], st.head[2], st.head[3], 0.85)
    top = 36 + th + 28
  else
    leaf.running:SetText(UI.Escape(D.Title(doc)):upper())
    leaf.running:SetTextColor(st.sub[1], st.sub[2], st.sub[3])
    leaf.runLine:SetVertexColor(st.sub[1], st.sub[2], st.sub[3], 0.35)
    top = 58
  end
  local sealed = last and doc.seal ~= nil
  leaf.seal:SetShown(sealed)
  if sealed then
    local h = K:House()
    leaf.seal:SetSeal(doc.seal, (D:IsMine(doc.id) and h and h.crest) or K.ICON)
  end
  local bottom = sealed and 122 or 62
  local sf = f.body.sf
  sf:ClearAllPoints()
  sf:SetPoint("TOPLEFT", 36, -top)
  sf:SetPoint("BOTTOMRIGHT", leaf, "BOTTOMRIGHT", -36, bottom)
  RenderBlocks(f.body, doc.pages[f.page], st, f.IW)
  if resetScroll ~= false then sf:SetVerticalScroll(0) end
  f.scroll.Update()

  f.counter:SetText(n > 1 and ("Page %d of %d"):format(f.page, n) or "")
  f.counter:SetTextColor(st.sub[1], st.sub[2], st.sub[3])
  f.prev:SetShown(n > 1)
  f.next:SetShown(n > 1)
  f.prev:SetEnabled(f.page > 1)
  f.next:SetEnabled(f.page < n)
end

-- A page turn: the leaf slides away and fades, the new page slides in.
function D:Turn(dir)
  local f = self.reader
  if not f or not f.doc then return end
  local target = (f.page or 1) + dir
  if target < 1 or target > #f.doc.pages then return end
  if SOUNDKIT and SOUNDKIT.IG_QUEST_LIST_OPEN then PlaySound(SOUNDKIT.IG_QUEST_LIST_OPEN) end
  f.page = target
  local swapped = false
  UI.SetProgress(f.turnKey, 0)
  UI.Tween(f.turnKey, 1, 0.42, function(p)
    local x, a
    if p < 0.35 then
      local q = p / 0.35
      x, a = -dir * 26 * q, 1 - q
    else
      if not swapped then swapped = true; D:RenderReader(true) end
      local q = UI.Ease.outQuart((p - 0.35) / 0.65)
      x, a = dir * 26 * (1 - q), q
    end
    f.leaf:SetPoint("TOPLEFT", x, 0)
    f.leaf:SetAlpha(a)
    f.prev:SetEnabled(f.page > 1)
    f.next:SetEnabled(f.page < #f.doc.pages)
  end)
end

function D:Open(id, page)
  if not K:ExtOn("documents") then return end
  local doc = self:Get(id)
  if not doc then I.Error("The pages of this document never reached you.") return end
  local f = self:BuildReader()
  f.doc, f.page = doc, page or 1
  f.leaf:SetPoint("TOPLEFT", 0, 0)
  f.leaf:SetAlpha(1)
  f:Show()
  f:Raise()
  self:RenderReader(true)
end

---------------------------------------------------------------------------
-- The Documents tab of the Inventory page: a list, and a writing desk.
---------------------------------------------------------------------------
local LIST_W = 230
local CARD_W, CARD_H = 696 - LIST_W - 10, 426
local IW = CARD_W - 32

-- A button that asks twice before doing something it can't undo.
local function Confirming(b, label, ask, fn)
  b:SetText(label)
  b:SetScript("OnClick", function(self)
    if self.armed then
      self.armed = nil
      self:SetText(label)
      fn()
    else
      self.armed = true
      self:SetText(ask)
      C_Timer.After(3, function() if self.armed then self.armed = nil; self:SetText(label) end end)
    end
  end)
  b:HookScript("OnHide", function(self) self.armed = nil; self:SetText(label) end)
end

local function PageTab(parent)
  local b = CreateFrame("Button", nil, parent)
  b:SetSize(26, 24)
  b.bg = b:CreateTexture(nil, "BACKGROUND")
  b.bg:SetAllPoints()
  b.bg:SetTexture(WHITE)
  b.edge = UI.Border(b)
  b.text = UI.Text(b, "", "Small", "plain")
  b.text:SetPoint("CENTER", 0, 0)
  function b:Paint()
    local t = K:Theme()
    if self.selected then
      self.bg:SetVertexColor(t.accent[1], t.accent[2], t.accent[3], 0.90)
      self.edge:SetColor(t.accent[1], t.accent[2], t.accent[3], 1)
      self.text:SetTextColor(t.panel[1], t.panel[2], t.panel[3])
    else
      local f = self.hover and t.select or t.field
      self.bg:SetVertexColor(unpack(f))
      self.edge:SetColor(unpack(self.hover and { t.accent[1], t.accent[2], t.accent[3], 0.6 } or t.fieldEdge))
      self.text:SetTextColor(unpack(t.text))
    end
  end
  b:SetScript("OnEnter", function(self) self.hover = true; self:Paint() end)
  b:SetScript("OnLeave", function(self) self.hover = false; self:Paint() end)
  UI:OnTheme(function() b:Paint() end)
  return b
end

function D:BuildTab(tab, opts)
  opts = opts or {}
  tab.page = 1

  local new = UI.Button(tab, "New document", LIST_W, 26)
  new:SetPoint("TOPLEFT", 0, 0)
  new:SetScript("OnClick", function()
    local doc = D:New()
    tab.selected, tab.page = doc.id, 1
    K.Journal:RefreshCurrent()
    tab.ed.title.edit:SetFocus()
  end)

  tab.list = UI.List(tab, LIST_W, CARD_H - 34, 50,
    "No documents yet. Write a book, a notice or a contract, then attach it to an item.",
    function(row)
      row.sheet = row:CreateTexture(nil, "ARTWORK")
      row.sheet:SetTexture(WHITE)
      row.sheet:SetSize(24, 30)
      row.sheet:SetPoint("LEFT", 12, 0)
      row.sheetEdge = CreateFrame("Frame", nil, row)
      row.sheetEdge:SetAllPoints(row.sheet)
      row.sheetEdge.b = UI.Border(row.sheetEdge)
      row.lines = {}
      for i = 1, 3 do
        local l = row:CreateTexture(nil, "ARTWORK", nil, 1)
        l:SetTexture(WHITE)
        l:SetSize(i == 1 and 14 or 16, 1)
        l:SetPoint("TOPLEFT", row.sheet, "TOPLEFT", 4, -7 - (i - 1) * 5)
        row.lines[i] = l
      end
      row.seal = UI.Circle(row, 10, "OVERLAY")
      row.seal:SetPoint("CENTER", row.sheet, "BOTTOMRIGHT", -2, 3)
      row.name = UI.Text(row, "", "Header", "heading", LIST_W - 70)
      row.name:SetPoint("TOPLEFT", 48, -9)
      row.name:SetWordWrap(false)
      row.sub = UI.Text(row, "", "Small", "subtle", LIST_W - 70)
      row.sub:SetPoint("TOPLEFT", row.name, "BOTTOMLEFT", 0, -4)
      row.sub:SetWordWrap(false)
      row:SetScript("OnClick", function(self)
        tab.selected, tab.page = self.item.id, 1
        K.Journal:RefreshCurrent()
      end)
    end, { emptyIcon = K.Art("IconNote") })
  tab.list:SetPoint("TOPLEFT", 0, -34)

  local card = UI.Panel(tab)
  card:SetPoint("TOPLEFT", LIST_W + 10, 0)
  card:SetSize(CARD_W, CARD_H)
  tab.card = card

  -- Writing desk (your own documents) -----------------------------------------
  local ed = CreateFrame("Frame", nil, card)
  ed:SetAllPoints()
  tab.ed = ed
  local pill = UI.Section(ed, "Writing desk")
  pill:SetPoint("TOPLEFT", 21, -15)

  ed.del = UI.Button(ed, "Delete", 70, 22)
  ed.del:SetPoint("TOPRIGHT", -16, -10)
  Confirming(ed.del, "Delete", "Sure?", function()
    if tab.selected then D:Delete(tab.selected); tab.selected = nil; K.Journal:RefreshCurrent() end
  end)
  UI.Tooltip(ed.del, "Delete document", "Items already given away keep their own copy.")
  ed.make = UI.Button(ed, "Make an item", 106, 22)
  ed.make:SetPoint("RIGHT", ed.del, "LEFT", -6, 0)
  ed.make:SetScript("OnClick", function()
    local doc = D:Get(tab.selected)
    if doc and opts.onMakeItem then opts.onMakeItem(doc) end
  end)
  UI.Tooltip(ed.make, "Make an item", "Design an item that carries this document. Whoever holds it can read it.")
  ed.read = UI.Button(ed, "Read", 64, 22)
  ed.read:SetPoint("RIGHT", ed.make, "LEFT", -6, 0)
  ed.read:SetScript("OnClick", function() if tab.selected then D:Open(tab.selected, tab.page) end end)

  ed.title = UI.Field(ed, "Title", IW, D.MAX_TITLE, function(text)
    local doc = K.db.documents[tab.selected or ""]
    if doc then doc.title = strtrim(text); D:Touched(doc); D:RefreshList(tab) end
  end)
  ed.title:SetPoint("TOPLEFT", 16, -40)

  local sl = UI.Text(ed, "Style", "Label", "subtle")
  sl:SetPoint("TOPLEFT", 17, -88)
  local sitems = {}
  for _, key in ipairs(D.STYLE_ORDER) do sitems[#sitems + 1] = { key = key, label = D.STYLES[key].label } end
  ed.style = UI.Segments(ed, sitems, 66, function(key)
    local doc = K.db.documents[tab.selected or ""]
    if doc then doc.style = key; D:Touched(doc); D:RefreshList(tab) end
  end)
  ed.style:SetPoint("TOPLEFT", 16, -102)

  local sealX = 16 + 4 * 66 + 18
  local wl = UI.Text(ed, "Seal", "Label", "subtle")
  wl:SetPoint("TOPLEFT", sealX + 1, -88)
  ed.swatches = {}
  local choices = { { key = false, label = "No seal" } }
  for _, s in ipairs(UI.SEAL_COLORS) do choices[#choices + 1] = s end
  for i, s in ipairs(choices) do
    local b = CreateFrame("Button", nil, ed)
    b:SetSize(18, 18)
    b:SetPoint("TOPLEFT", sealX + (i - 1) * 18, -105)
    b.ring = UI.Circle(b, 18, "ARTWORK", 0)
    b.ring:SetPoint("CENTER")
    b.dot = UI.Circle(b, 14, "ARTWORK", 1)
    b.dot:SetPoint("CENTER")
    if s.color then
      b.dot:SetVertexColor(s.color[1], s.color[2], s.color[3], 1)
    else
      b.dot:SetVertexColor(1, 1, 1, 0.55)
      b.slash = b:CreateTexture(nil, "ARTWORK", nil, 2)
      b.slash:SetTexture(WHITE)
      b.slash:SetSize(11, 1.5)
      b.slash:SetPoint("CENTER")
      b.slash:SetRotation(math.rad(-45))
      b.slash:SetVertexColor(0.45, 0.30, 0.15, 0.9)
    end
    b.key = s.key or nil
    b:SetScript("OnClick", function()
      local doc = K.db.documents[tab.selected or ""]
      if doc then doc.seal = b.key; D:Touched(doc); D:RefreshTab(tab) end
    end)
    UI.Tooltip(b, s.key and (s.label .. " wax") or "No seal", s.key and "Pressed at the foot of the last page." or nil)
    ed.swatches[i] = b
  end

  local pl = UI.Text(ed, "Pages", "Label", "subtle")
  pl:SetPoint("TOPLEFT", 17, -136)
  ed.tabs = {}
  for i = 1, D.MAX_PAGES do
    local b = PageTab(ed)
    b:SetPoint("TOPLEFT", 16 + (i - 1) * 30, -150)
    b.text:SetText(i)
    b:SetScript("OnClick", function()
      ed.body.edit:ClearFocus()
      tab.page = i
      D:RefreshTab(tab)
    end)
    ed.tabs[i] = b
  end
  ed.add = PageTab(ed)
  ed.add.text:SetText("+")
  ed.add:SetScript("OnClick", function()
    local doc = K.db.documents[tab.selected or ""]
    if not doc or #doc.pages >= D.MAX_PAGES then return end
    table.insert(doc.pages, tab.page + 1, "")
    tab.page = tab.page + 1
    D:Touched(doc)
    D:RefreshTab(tab)
    ed.body.edit:SetFocus()
  end)
  UI.Tooltip(ed.add, "Add a page", "A blank page after this one.")

  ed.body = UI.TextArea(ed, IW, 172, D.MAX_PAGE, function(text)
    local doc = K.db.documents[tab.selected or ""]
    if doc and doc.pages[tab.page] then doc.pages[tab.page] = text; D:Touched(doc) end
  end)
  ed.body:SetPoint("TOPLEFT", 16, -182)
  ed.count = UI.Text(ed, "", "Label", "subtle")
  ed.count:SetPoint("TOPLEFT", 17, -366)
  ed.body.edit:HookScript("OnTextChanged", function(self)
    ed.count:SetText(("%d / %d"):format(self:GetNumLetters(), D.MAX_PAGE))
  end)

  ed.remove = UI.Button(ed, "Remove page", 100, 22)
  ed.remove:SetPoint("TOPRIGHT", -16, -362)
  Confirming(ed.remove, "Remove page", "Sure?", function()
    local doc = K.db.documents[tab.selected or ""]
    if not doc or #doc.pages <= 1 then return end
    table.remove(doc.pages, tab.page)
    tab.page = math.max(1, tab.page - 1)
    D:Touched(doc)
    D:RefreshTab(tab, true)
  end)
  local function Swap(d)
    local doc = K.db.documents[tab.selected or ""]
    local j = tab.page + d
    if not doc or not doc.pages[j] then return end
    ed.body.edit:ClearFocus()
    doc.pages[tab.page], doc.pages[j] = doc.pages[j], doc.pages[tab.page]
    tab.page = j
    D:Touched(doc)
    D:RefreshTab(tab, true)
  end
  ed.later = UI.Button(ed, "Later", 62, 22)
  ed.later:SetPoint("RIGHT", ed.remove, "LEFT", -6, 0)
  ed.later:SetScript("OnClick", function() Swap(1) end)
  UI.Tooltip(ed.later, "Move this page later")
  ed.earlier = UI.Button(ed, "Earlier", 66, 22)
  ed.earlier:SetPoint("RIGHT", ed.later, "LEFT", -6, 0)
  ed.earlier:SetScript("OnClick", function() Swap(-1) end)
  UI.Tooltip(ed.earlier, "Move this page earlier")

  local hint = UI.Text(ed, "Start a line with # for a heading, ## for a subheading, or --- for a rule.", "Label", "subtle", IW)
  hint:SetPoint("TOPLEFT", 17, -396)

  -- Someone else's document ------------------------------------------------------
  local ro = CreateFrame("Frame", nil, card)
  ro:SetAllPoints()
  tab.ro = ro
  local rp = UI.Section(ro, "From another hand")
  rp:SetPoint("TOPLEFT", 21, -15)
  ro.sheet = D.Paper(ro)
  ro.sheet:SetSize(120, 156)
  ro.sheet:SetPoint("TOPLEFT", 18, -46)
  ro.sheetTitle = ro.sheet:CreateFontString(nil, "OVERLAY")
  ro.sheetTitle:SetFontObject(UI.FONTS.Small)
  ro.sheetTitle:SetWidth(96)
  ro.sheetTitle:SetPoint("TOP", 0, -24)
  ro.sheetTitle:SetJustifyH("CENTER")
  ro.sheetSeal = UI.Seal(ro.sheet, 30)
  ro.sheetSeal:SetPoint("BOTTOM", 0, 16)
  ro.title = UI.Text(ro, "", "Title", "heading", IW - 136)
  ro.title:SetPoint("TOPLEFT", 156, -48)
  ro.by = UI.Text(ro, "", "Small", "subtle", IW - 136)
  ro.by:SetPoint("TOPLEFT", ro.title, "BOTTOMLEFT", 0, -6)
  ro.info = UI.Text(ro, "", "Small", "text", IW - 136)
  ro.info:SetPoint("TOPLEFT", ro.by, "BOTTOMLEFT", 0, -10)
  ro.info:SetSpacing(3)
  ro.readBtn = UI.Button(ro, "Read", 120, 26)
  ro.readBtn:SetPoint("TOPLEFT", 156, -150)
  ro.readBtn:SetScript("OnClick", function() if tab.selected then D:Open(tab.selected) end end)
  ro.copy = UI.Button(ro, "Make a copy", 120, 26)
  ro.copy:SetPoint("LEFT", ro.readBtn, "RIGHT", 8, 0)
  ro.copy:SetScript("OnClick", function()
    local doc = D:Copy(tab.selected)
    if doc then tab.selected, tab.page = doc.id, 1; K.Journal:RefreshCurrent() end
  end)
  UI.Tooltip(ro.copy, "Make a copy", "An editable copy of your own.")
  local el = UI.Text(ro, "First page", "Label", "subtle")
  el:SetPoint("TOPLEFT", 17, -218)
  ro.excerpt = UI.ReadArea(ro, IW, CARD_H - 232 - 56, "Read", "text")
  ro.excerpt:SetPoint("TOPLEFT", 16, -234)
  ro.forget = UI.Button(ro, "Forget", 80, 24)
  ro.forget:SetPoint("BOTTOMRIGHT", -16, 14)
  Confirming(ro.forget, "Forget", "Sure?", function()
    if tab.selected then D:Forget(tab.selected); tab.selected = nil; K.Journal:RefreshCurrent() end
  end)
  ro.note = UI.Text(ro, "", "Small", "subtle", IW - 100)
  ro.note:SetPoint("BOTTOMLEFT", 17, 20)

  -- Nothing chosen ---------------------------------------------------------------
  local blank = CreateFrame("Frame", nil, card)
  blank:SetAllPoints()
  tab.blank = blank
  local bi = blank:CreateTexture(nil, "ARTWORK")
  bi:SetTexture(K.Art("IconNote"))
  bi:SetSize(64, 64)
  bi:SetPoint("CENTER", 0, 44)
  bi:SetAlpha(0.8)
  local bt = UI.Text(blank, "Books, notices and contracts, up to ten pages each. Attach one to an item and whoever holds it can read it.",
    "Read", "subtle", IW - 60)
  bt:SetPoint("TOP", bi, "BOTTOM", 0, -12)
  bt:SetJustifyH("CENTER")
  bt:SetSpacing(3)
  local bb = UI.Button(blank, "Write a document", 150, 26)
  bb:SetPoint("TOP", bt, "BOTTOM", 0, -16)
  bb:SetScript("OnClick", function() new:Click() end)
end

function D:RefreshList(tab)
  local me = K.NameKey(K:MyName())
  tab.list:SetItems(D:List(), function(row, doc)
    local st = Style(doc.style)
    row.sheet:SetVertexColor(st.paper[1], st.paper[2], st.paper[3], 1)
    row.sheetEdge.b:SetColor(st.edge[1], st.edge[2], st.edge[3], 0.8)
    for _, l in ipairs(row.lines) do l:SetVertexColor(st.sub[1], st.sub[2], st.sub[3], 0.6) end
    if doc.seal then
      local c = UI.SealColor(doc.seal)
      row.seal:SetVertexColor(c[1], c[2], c[3], 1)
      row.seal:Show()
    else
      row.seal:Hide()
    end
    row.name:SetText(UI.Escape(D.Title(doc)))
    local pages = #doc.pages == 1 and "1 page" or (#doc.pages .. " pages")
    if D:IsMine(doc.id) then
      row.sub:SetText(pages .. "  ·  " .. st.label)
    else
      local from = doc.author ~= "" and K.NameKey(doc.author) ~= me and ("From " .. UI.Escape(I.Short(doc.author))) or "Received"
      row.sub:SetText(from .. "  ·  " .. pages)
    end
    row.sel:SetShown(doc.id == tab.selected)
  end)
end

function D:RefreshTab(tab, forceText)
  self:RefreshList(tab)
  local doc = self:Get(tab.selected)
  if not doc then tab.selected = nil end
  local mine = doc and self:IsMine(doc.id)
  tab.ed:SetShown(mine and true or false)
  tab.ro:SetShown(doc ~= nil and not mine)
  tab.blank:SetShown(doc == nil)
  if not doc then return end
  tab.page = math.max(1, math.min(tab.page or 1, #doc.pages))
  local key = doc.id .. "#" .. tab.page
  local changed = tab.shownKey ~= key
  if tab.shownDoc ~= doc.id then UI.FadeIn(tab.card, 0.2) end
  tab.shownDoc, tab.shownKey = doc.id, key

  if not mine then
    local r = tab.ro
    r.sheet:SetStyle(doc.style)
    local st = Style(doc.style)
    r.sheetTitle:SetText(UI.Escape(D.Title(doc)))
    r.sheetTitle:SetTextColor(st.head[1], st.head[2], st.head[3])
    r.sheetSeal:SetShown(doc.seal ~= nil)
    if doc.seal then r.sheetSeal:SetSeal(doc.seal, K.ICON) end
    r.title:SetText(UI.Escape(D.Title(doc)))
    r.by:SetText(doc.author ~= "" and ("Written by " .. UI.Escape(I.Short(doc.author))) or "Author unknown")
    local info = { (#doc.pages == 1 and "One page" or (#doc.pages .. " pages")) .. " of " .. st.label:lower() }
    if doc.seal then info[#info + 1] = "Sealed in " .. D.SealLabel(doc.seal):lower() .. " wax" end
    if doc.seen then info[#info + 1] = "Received " .. UI.Ago(doc.seen) end
    r.info:SetText(table.concat(info, "\n"))
    if changed then r.excerpt:SetText(UI.Escape(doc.pages[1] or "")) end
    local used = self:InUse(doc.id)
    r.forget:SetEnabled(not used)
    r.note:SetText(used and "An item in your bags carries it." or "")
    return
  end

  local ed = tab.ed
  if changed or forceText or not ed.title.edit:HasFocus() then ed.title.edit:SetText(doc.title or "") end
  if changed or forceText or not ed.body.edit:HasFocus() then
    ed.body.edit:SetText(doc.pages[tab.page] or "")
    ed.body.edit:SetCursorPosition(0)
  end
  ed.count:SetText(("%d / %d"):format(ed.body.edit:GetNumLetters(), D.MAX_PAGE))
  ed.style:Select(doc.style)
  for _, b in ipairs(ed.swatches) do
    local on = b.key == doc.seal
    b.ring:SetVertexColor(0.30, 0.20, 0.08, on and 0.9 or 0)
    b.dot:SetSize(on and 12 or 14, on and 12 or 14)
  end
  local n = #doc.pages
  for i, b in ipairs(ed.tabs) do
    b:SetShown(i <= n)
    b.selected = i == tab.page
    b:Paint()
  end
  ed.add:ClearAllPoints()
  ed.add:SetPoint("TOPLEFT", 16 + n * 30, -150)
  ed.add:SetShown(n < D.MAX_PAGES)
  ed.remove:SetEnabled(n > 1)
  ed.earlier:SetEnabled(tab.page > 1)
  ed.later:SetEnabled(tab.page < n)
end

---------------------------------------------------------------------------
-- Saved data
---------------------------------------------------------------------------
K:On("LOGIN", function()
  K.db.documents = K.db.documents or {}
  K.db.docCache = K.db.docCache or {}
  -- Forget received documents that no item carries any more.
  local used = {}
  for _, def in pairs(K.db.itemDefs or {}) do if def.documentId then used[def.documentId] = true end end
  for _, def in pairs(K.db.itemCache or {}) do if def.documentId then used[def.documentId] = true end end
  local cutoff = time() - 90 * 86400
  for id, doc in pairs(K.db.docCache) do
    if not used[id] and (type(doc) ~= "table" or (doc.seen or 0) < cutoff) then K.db.docCache[id] = nil end
  end
end)
