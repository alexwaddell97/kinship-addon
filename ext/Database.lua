-- Kinship RP: the Database tab of the Inventory page. Every Total RP 3:
-- Extended object you hold (your own, and those received or imported), what's
-- inside each one and whether it needs your permission to run, with import
-- from and export to Total RP 3: Extended Tools strings.
--   K.ExtDB:BuildTab(frame, page), K.ExtDB:RefreshTab(frame)

local ADDON, ns = ...
local K = ns.K
local UI = K.UI
local E = K.Ext
local C = K.ExtCodec
local DB = {}
K.ExtDB = DB

local CW, BODY_H = 696, 426
local LIST_W = 260
local ED_W = CW - LIST_W - 10      -- 426
local IW = ED_W - 32
local MODAL_W, MODAL_IW = 560, 528

local FILTERS = {
  { key = "all", label = "All" }, { key = "my", label = "Yours" }, { key = "exchange", label = "Received" },
}

-- What a permission group lets a creation do, in plain words.
local GROUP_LABEL = {
  SEC_REASON_TALK = "speak in chat for you", SEC_REASON_EMOTE = "perform emotes",
  SEC_REASON_SOUND = "play sounds others hear", SEC_REASON_DISMOUNT = "summon or dismiss your mount",
  SEC_REASON_SCRIPT = "run raw scripts", SEC_REASON_MACRO = "run macros",
}

local function Refresh() K.Journal:RefreshCurrent() end

local function Sub() return UI.Hex(K:Theme().subtle) end

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

local function EmptyState(parent, text, w, button)
  local f = CreateFrame("Frame", nil, parent)
  f:SetAllPoints()
  f.art = f:CreateTexture(nil, "ARTWORK")
  f.art:SetTexture(K.Art("IconNote"))
  f.art:SetSize(64, 64)
  f.art:SetPoint("CENTER", 0, 44)
  f.art:SetAlpha(0.8)
  f.text = UI.Text(f, text, "Read", "subtle", w)
  f.text:SetPoint("TOP", f.art, "BOTTOM", 0, -12)
  f.text:SetJustifyH("CENTER")
  f.text:SetSpacing(3)
  if button then
    f.button = UI.Button(f, button, 150, 26)
    f.button:SetPoint("TOP", f.text, "BOTTOM", 0, -16)
  end
  return f
end

local function NameColor(info)
  if info.type == "IT" and K.Items and K.Items.QualityColor then return K.Items.QualityColor(info.quality, true) end
  return K:Theme().heading
end

local function TypeLabel(ty) return E.TYPES[ty] and E.TYPES[ty].label or ("Unknown (" .. tostring(ty) .. ")") end

local function Plain(s) return UI.Clean(s or "") end

---------------------------------------------------------------------------
-- Import pop-over
---------------------------------------------------------------------------
local function BuildImport(page, tab)
  local m = UI.Modal(page, MODAL_W, 372, function() tab.importer:Hide() end)
  local card = m.card
  local pill = UI.Section(card, "Import from Total RP 3: Extended")
  pill:SetPoint("TOPLEFT", 21, -15)
  local help = UI.Text(card, "In Total RP 3: Extended Tools, right-click an object in the database and choose Export, "
    .. "copy the text, then paste it here with Ctrl+V.", "Small", "subtle", MODAL_IW)
  help:SetPoint("TOPLEFT", 16, -42)
  help:SetSpacing(2)
  m.area = UI.TextArea(card, MODAL_IW, 170, C.MAX_INPUT, function() m.decoded = nil; m:Status() end)
  m.area:SetPoint("TOPLEFT", 16, -82)
  m.status = UI.Text(card, "", "Small", "subtle", MODAL_IW)
  m.status:SetPoint("TOPLEFT", 16, -264)
  m.status:SetSpacing(2)

  m.go = UI.Button(card, "Import", 120, 26)
  m.go:SetPoint("BOTTOMRIGHT", -16, 14)
  m.clear = UI.Button(card, "Clear", 80, 26)
  m.clear:SetPoint("RIGHT", m.go, "LEFT", -8, 0)
  m.clear:SetScript("OnClick", function()
    m.area.edit:SetText("")
    m.decoded = nil
    m:Status()
    m.area.edit:SetFocus()
  end)

  function m:Status(text, bad)
    local c = bad and UI.CardHex({ 0.90, 0.36, 0.30 }) or Sub()
    self.status:SetText(text and ("|cff%s%s|r"):format(c, text) or "")
    self.go:SetText(self.decoded and "Import anyway" or "Import")
  end

  local function Finish(decoded)
    local obj, src = E:Store(decoded.id, decoded.object)
    if not obj then m:Status("It couldn't be stored: " .. tostring(src) .. ".", true) return end
    local info = E.Info(obj)
    tab.importer:Hide()
    tab.filter = "all"
    tab.selected = decoded.id
    if SOUNDKIT and SOUNDKIT.IG_BACKPACK_OPEN then PlaySound(SOUNDKIT.IG_BACKPACK_OPEN) end
    UI.Toast({ icon = E.IconTexture(info.icon), iconCoords = { 0.08, 0.92, 0.08, 0.92 },
      title = Plain(info.name), text = TypeLabel(info.type) .. (src == "my" and " (yours) imported." or " imported."),
      duration = 4 })
    Refresh()
  end

  m.go:SetScript("OnClick", function()
    if m.decoded then Finish(m.decoded) return end
    local decoded, why = C:Decode(m.area.edit:GetText())
    if not decoded then m:Status(why, true) return end
    local warn = C:Warnings(decoded)
    if #warn == 0 then Finish(decoded) return end
    m.decoded = decoded
    local info = E.Info(decoded.object)
    m:Status(("%s \"%s\" by %s.\n%s"):format(TypeLabel(info.type), Plain(info.name), Plain(info.author or "someone"),
      table.concat(warn, "\n")))
  end)

  function m:Open()
    self.decoded = nil
    self.area.edit:SetText("")
    self:Status()
    self:Show()
    self.area.edit:SetFocus()
  end
  return m
end

---------------------------------------------------------------------------
-- Export pop-over
---------------------------------------------------------------------------
local function BuildExport(page, tab)
  local m = UI.Modal(page, MODAL_W, 340, function() tab.exporter:Hide() end)
  local card = m.card
  m.pill = UI.Section(card, "Export")
  m.pill:SetPoint("TOPLEFT", 21, -15)
  local help = UI.Text(card, "Press Ctrl+C to copy. In Total RP 3: Extended Tools, open the database, choose Import "
    .. "and paste it there, or share it with anyone using Kinship or Total RP 3.", "Small", "subtle", MODAL_IW)
  help:SetPoint("TOPLEFT", 16, -42)
  help:SetSpacing(2)
  -- Read-only: any typing puts the string back.
  m.area = UI.TextArea(card, MODAL_IW, 190, C.MAX_EXPORT, function()
    m.area.edit:SetText(m.text or "")
    m.area.edit:HighlightText()
  end)
  m.area:SetPoint("TOPLEFT", 16, -82)
  m.size = UI.Text(card, "", "Small", "subtle", 300)
  m.size:SetPoint("BOTTOMLEFT", 17, 21)
  m.select = UI.Button(card, "Select all", 110, 26)
  m.select:SetPoint("BOTTOMRIGHT", -16, 14)
  m.select:SetScript("OnClick", function()
    m.area.edit:SetFocus()
    m.area.edit:HighlightText()
  end)

  function m:Open(id, text, info)
    self.text = text
    self.pill:SetText("Export: " .. Plain(info.name))
    self.area.edit:SetText(text)
    self.size:SetText(("%s KB, Total RP 3: Extended %s format"):format(
      ("%.1f"):format(#text / 1024), E.DISPLAY_VERSION))
    self:Show()
    self.area.edit:SetFocus()
    self.area.edit:HighlightText()
  end
  return m
end

---------------------------------------------------------------------------
-- The tab
---------------------------------------------------------------------------
function DB:BuildTab(tab, page)
  tab.filter = "all"
  tab.page = page

  tab.filters = UI.Segments(tab, FILTERS, 62, function(key) tab.filter = key; Refresh() end)
  tab.filters:SetPoint("TOPLEFT", 0, -1)
  tab.import = UI.Button(tab, "Import", LIST_W - 3 * 62 - 8, 26)
  tab.import:SetPoint("TOPLEFT", 3 * 62 + 8, 0)
  tab.import:SetScript("OnClick", function() DB:OpenImport(tab) end)
  UI.Tooltip(tab.import, "Import", "Paste an export string from Total RP 3: Extended Tools.")

  tab.list = UI.List(tab, LIST_W, BODY_H - 34, 50,
    "Nothing here yet. Import a creation from Total RP 3: Extended to keep it here.",
    function(row)
      row.icon = row:CreateTexture(nil, "ARTWORK")
      row.icon:SetSize(34, 34)
      row.icon:SetPoint("LEFT", 10, 0)
      row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
      UI.Round(row.icon)
      row.name = UI.Text(row, "", "Header", "heading", LIST_W - 74)
      row.name:SetPoint("TOPLEFT", 54, -9)
      row.name:SetWordWrap(false)
      row.sub = UI.Text(row, "", "Small", "subtle", LIST_W - 74)
      row.sub:SetPoint("TOPLEFT", row.name, "BOTTOMLEFT", 0, -4)
      row.sub:SetWordWrap(false)
      row:SetScript("OnClick", function(self)
        tab.selected = self.item.id
        Refresh()
      end)
      row.onEnter = function(self)
        local info = self.item.info
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(Plain(info.name), 1, 0.82, 0)
        if info.desc ~= "" then GameTooltip:AddLine(Plain(info.desc), 1, 1, 1, true) end
        GameTooltip:Show()
      end
    end, { emptyIcon = K.Art("IconNote") })
  tab.list:SetPoint("TOPLEFT", 0, -34)

  local card = UI.Panel(tab)
  card:SetPoint("TOPLEFT", LIST_W + 10, 0)
  card:SetSize(ED_W, BODY_H)
  tab.card = card

  local d = CreateFrame("Frame", nil, card)
  d:SetAllPoints()
  tab.detail = d
  local pill = UI.Section(d, "Extended object")
  pill:SetPoint("TOPLEFT", 21, -15)
  d.source = UI.Chip(d)
  d.source:SetPoint("TOPRIGHT", -16, -12)

  d.icon = d:CreateTexture(nil, "ARTWORK")
  d.icon:SetSize(44, 44)
  d.icon:SetPoint("TOPLEFT", 16, -42)
  d.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
  UI.Round(d.icon)
  d.name = UI.Text(d, "", "Title", "heading", IW - 60)
  d.name:SetPoint("TOPLEFT", d.icon, "TOPRIGHT", 12, -2)
  d.name:SetWordWrap(false)
  d.kind = UI.Text(d, "", "Small", "subtle", IW - 60)
  d.kind:SetPoint("TOPLEFT", d.name, "BOTTOMLEFT", 0, -5)
  d.kind:SetWordWrap(false)
  d.safety = UI.Chip(d)
  d.safety:SetPoint("TOPLEFT", 16, -96)

  d.body = UI.ReadArea(d, IW + 6, BODY_H - 128 - 52, "Read", "text")
  d.body:SetPoint("TOPLEFT", 16, -124)

  d.export = UI.Button(d, "Export", 110, 26)
  d.export:SetPoint("BOTTOMLEFT", 16, 14)
  d.export:SetScript("OnClick", function() if tab.selected then DB:OpenExport(tab, tab.selected) end end)
  UI.Tooltip(d.export, "Export", "A string Total RP 3: Extended Tools can import, or anyone using Kinship.")
  d.remove = UI.Button(d, "Remove", 110, 26)
  d.remove:SetPoint("BOTTOMRIGHT", -16, 14)
  Confirming(d.remove, "Remove", "Sure?", function()
    if tab.selected then E:Remove(tab.selected); tab.selected = nil; Refresh() end
  end)
  UI.Tooltip(d.remove, "Remove", "Forget this object and everything inside it. You can import it again later.")

  tab.none = EmptyState(card, "", IW - 60, "Import a creation")
  tab.none.button:SetScript("OnClick", function() DB:OpenImport(tab) end)
end

function DB:OpenImport(tab)
  tab.importer = tab.importer or BuildImport(tab.page, tab)
  tab.importer:Open()
end

function DB:OpenExport(tab, id)
  local obj = E:Get(id)
  if not obj then return end
  local text, why = C:Export(id, obj)
  if not text then UI.Toast({ title = "Couldn't export", text = why, duration = 4 }) return end
  tab.exporter = tab.exporter or BuildExport(tab.page, tab)
  tab.exporter:Open(id, text, E.Info(obj))
end

-- The detail text for one root.
local function DetailText(id, obj, source)
  local info = E.Info(obj)
  local sub, out = Sub(), {}
  if info.desc ~= "" then out[#out + 1] = Plain(info.desc) end

  local facts = { ("|cff%sID|r  %s"):format(sub, UI.Escape(id)) }
  if info.author then
    facts[#facts + 1] = ("|cff%sMade by|r  %s%s"):format(sub, Plain(info.author), info.created and ("  ·  " .. UI.Escape(info.created)) or "")
  end
  if info.savedBy or info.saved then
    facts[#facts + 1] = ("|cff%sLast saved|r  %s%s"):format(sub, Plain(info.savedBy or ""),
      info.saved and ("  ·  " .. UI.Escape(info.saved)) or "")
  end
  facts[#facts + 1] = ("|cff%sVersion|r  %d  ·  %s mode%s"):format(sub, info.version, E.MODES[info.mode] or "Normal",
    info.dataVersion and ("  ·  data %d"):format(info.dataVersion) or "")
  out[#out + 1] = table.concat(facts, "\n")

  local kids = E:Children(id)
  if #kids > 0 then
    local lines = { ("|cff%sInside (%d)|r"):format(sub, #kids) }
    for i, k in ipairs(kids) do
      if i > 40 then lines[#lines + 1] = ("|cff%s...and %d more|r"):format(sub, #kids - 40) break end
      local tail = k.id:match("([^ ]+)$") or k.id
      lines[#lines + 1] = ("%s%s  |cff%s%s · %s|r"):format(string.rep("    ", math.max(0, k.depth - 1)),
        Plain(k.info.name), sub, TypeLabel(k.info.type), UI.Escape(tail))
    end
    out[#out + 1] = table.concat(lines, "\n")
  end

  local level, details, refused = E.ComputeSecurity(id, obj)
  local sec = {}
  if level >= E.SECURITY.HIGH then
    sec[1] = "Nothing in it needs your permission to run."
  else
    local asks = {}
    for key in pairs(details) do
      if GROUP_LABEL[key] then asks[#asks + 1] = GROUP_LABEL[key]
      else asks[#asks + 1] = ("use an effect Kinship doesn't know (%s)"):format(UI.Escape(key)) end
    end
    table.sort(asks)
    sec[1] = (source == "my" and "Yours, so it may " or "It would ask before it may ") .. table.concat(asks, ", ") .. "."
  end
  if next(refused) then
    sec[#sec + 1] = ("|cff%sIt contains raw scripts or macros. Kinship keeps them, and exports them unchanged, but never runs them.|r")
      :format(UI.CardHex({ 0.90, 0.36, 0.30 }))
  end
  out[#out + 1] = table.concat(sec, "\n")

  local T = E.TYPES[info.type]
  if T and not K:ExtOn(T.module) then
    out[#out + 1] = ("|cff%s%s are switched off in Settings > Extended features.|r"):format(sub, T.plural)
  else
    out[#out + 1] = ("|cff%sKinship keeps it ready to share and export. Playing Extended creations arrives in a later update.|r"):format(sub)
  end
  return table.concat(out, "\n\n")
end

function DB:RefreshTab(tab)
  tab.filters:Select(tab.filter)
  local items = E:List(tab.filter ~= "all" and tab.filter or nil)
  tab.list:SetItems(items, function(row, it)
    row.icon:SetTexture(E.IconTexture(it.info.icon))
    row.name:SetText(Plain(it.info.name))
    row.name:SetTextColor(unpack(NameColor(it.info)))
    local sub = TypeLabel(it.info.type)
    if it.source == "my" then sub = sub .. "  ·  yours"
    elseif it.info.author then sub = sub .. "  ·  " .. Plain(Ambiguate(it.info.author, "none")) end
    if it.count > 0 then sub = sub .. ("  ·  %d inside"):format(it.count) end
    row.sub:SetText(sub)
    row.sel:SetShown(it.id == tab.selected)
  end)

  local obj, source = nil, nil
  if tab.selected then obj, source = E:Get(tab.selected) end
  if not obj or E.RootID(tab.selected) ~= tab.selected then tab.selected, obj = nil, nil end
  tab.detail:SetShown(obj ~= nil)
  tab.none:SetShown(obj == nil)
  if not obj then
    local any = #E:List() > 0
    tab.none.text:SetText(any and "Choose an object to see what's inside it, export it or remove it."
      or "Bring in creations from Total RP 3: Extended. Export one in its Tools, then paste the string here.")
    tab.none.button:SetShown(not any)
    return
  end
  local d, id = tab.detail, tab.selected
  if tab.shown ~= id then
    tab.shown = id
    UI.FadeIn(d, 0.2)
  end
  local info = E.Info(obj)
  d.icon:SetTexture(E.IconTexture(info.icon))
  d.name:SetText(Plain(info.name))
  d.name:SetTextColor(unpack(NameColor(info)))
  local kind = TypeLabel(info.type)
  if info.type == "IT" and K.Items then kind = K.Items.Quality(info.quality).label .. " item" end
  d.kind:SetText(kind .. (info.language and ("  ·  " .. UI.Escape(info.language):upper()) or ""))
  d.source:Set(source == "my" and "Yours" or "Received", source == "my" and K:Theme().accent or { 0.55, 0.40, 0.85 })

  local level, refused = E:Security(id)
  if next(refused or {}) then d.safety:Set("Has scripts Kinship won't run", { 0.90, 0.36, 0.30 })
  elseif level >= E.SECURITY.HIGH then d.safety:Set("Safe", { 0.30, 0.70, 0.40 })
  else d.safety:Set("Asks permission", { 0.95, 0.70, 0.30 }) end
  d.body:SetText(DetailText(id, obj, source))
end
