-- Kinship RP: Directory. Everyone whose roleplay profile has reached you,
-- from Kinship and from other RP addons (Total RP 3, MyRolePlay, XRP).

local ADDON, ns = ...
local K = ns.K
local UI = K.UI

local FILTERS = {
  { key = "all", label = "Everyone" }, { key = "nearby", label = "Nearby" }, { key = "ic", label = "IC" },
  { key = "lfrp", label = "LFRP" }, { key = "kin", label = "Your Kin" }, { key = "help", label = "RP help" },
}
local ADDONS = {
  totalrp3 = "Total RP 3", kinshiprp = "Kinship", myroleplay = "MyRolePlay", xrp = "XRP", gnomtec_badge = "Badge",
}
local LIST_W, CW, CH = 404, 696, 466
local NEARBY = 15 * 60

local function Short(n) return Ambiguate and Ambiguate(n, "none") or n end

local function AddonLabel(va)
  local first = type(va) == "string" and va:match("^([^/;]+)")
  if not first then return nil end
  return ADDONS[first:lower()] or first
end

local function DisplayName(e)
  local p = e.profile or {}
  local rp = strtrim(UI.Clean(p.rpName))
  if rp == "" then return Short(e.name) end
  local prefix = UI.Clean(p.prefix)
  return prefix ~= "" and (prefix .. " " .. rp) or rp
end

local function Matches(e, filter, search)
  local p = e.profile or {}
  if filter == "nearby" and time() - (e.t or 0) > NEARBY then return false end
  if filter == "ic" and p.status ~= "ic" then return false end
  if filter == "lfrp" and p.status ~= "lfrp" then return false end
  if filter == "kin" and not K:KinFor(e.name) then return false end
  -- New roleplayers, and those happy to help them
  if filter == "help" and p.rpExp ~= "new" and p.rpExp ~= "mentor" then return false end
  if search ~= "" then
    local hay = ((p.rpName or "") .. " " .. e.name .. " " .. (p.house or "") .. " " .. (p.epithet or "")):lower()
    if not hay:find(search, 1, true) then return false end
  end
  return true
end

local function RowMenu(owner, e)
  UI.Menu(owner, function(root)
    root:CreateTitle(DisplayName(e))
    root:CreateButton("View profile", function() K.Viewer:ShowName(e.name) end)
    root:CreateButton("Write a letter", function() K.Letters:Compose(e.name) end)
    if not K:KinFor(e.name) then
      root:CreateButton("Add to Kin", function() K:AddKinByName(e.name) end)
    end
    root:CreateButton("Whisper", function() K:Whisper(e.name) end)
    if K.Relations then K.Relations:FillMenu(root:CreateButton("Relationship"), e.name) end
    root:CreateDivider()
    if K.Safety then root:CreateButton("Ignore...", function() K.Safety:ConfirmIgnore(e.name) end) end
    root:CreateButton("|cffff6060Forget this profile|r", function()
      K.db.registry[K.NameKey(e.name) or ""] = nil
      K:Fire("REGISTRY")
    end)
  end)
end

K:RegisterPage({
  id = "directory", trp3 = "hide", title = "Directory", heading = "Directory",
  subtitle = "Everyone whose roleplay profile has reached you.",

  build = function(c)
    c.filter, c.search = "all", ""
    function c:Selected() return self.selKey and K.Registry[self.selKey] or nil end
    c.filters = UI.Segments(c, FILTERS, 78, function(key) c.filter = key; K.Journal:RefreshCurrent() end)
    c.filters:SetPoint("TOPLEFT", 0, 0)
    local search = UI.Search(c, 176, "Names and houses", function(t) c.search = t; K.Journal:RefreshCurrent() end)
    search:SetPoint("TOPRIGHT", 0, 0)
    c.searchBox = search

    c.list = UI.List(c, LIST_W, CH - 34 - 26, 54,
      "No profiles yet. Mouse over players who use Kinship, Total RP 3, MyRolePlay or XRP and their profiles will gather here.",
      function(row)
        row.dot = UI.Gem(row, 15)
        row.dot:SetPoint("LEFT", 14, 7)
        row.name = UI.Text(row, "", "Header", "heading", 230)
        row.name:SetPoint("TOPLEFT", 32, -10)
        row.name:SetWordWrap(false)
        row.sub = UI.Text(row, "", "Small", "subtle", 240)
        row.sub:SetPoint("TOPLEFT", row.name, "BOTTOMLEFT", 0, -4)
        row.sub:SetWordWrap(false)
        row.addon = UI.Chip(row)
        row.addon:SetPoint("TOPRIGHT", -10, -10)
        row.ago = UI.Text(row, "", "Small", "subtle")
        row.ago:SetPoint("BOTTOMRIGHT", -10, 10)
        row:SetScript("OnClick", function(self, button)
          if button == "RightButton" then RowMenu(self, self.item) else c.selKey = K.NameKey(self.item.name); K.Journal:RefreshCurrent() end
        end)
        row:SetScript("OnDoubleClick", function(self) K.Viewer:ShowName(self.item.name) end)
      end, { emptyIcon = K.Art("IconPlace") })
    c.list:SetPoint("TOPLEFT", 0, -34)
    c.count = UI.Text(c, "", "Small", "deskSubtle", LIST_W)
    c.count:SetPoint("BOTTOMLEFT", 2, 4)

    -- Preview card ---------------------------------------------------------------
    local card = UI.Panel(c)
    card:SetPoint("TOPLEFT", LIST_W + 10, -34)
    card:SetPoint("BOTTOMRIGHT")
    local PW = CW - LIST_W - 10 - 32
    local d = CreateFrame("Frame", nil, card)
    d:SetPoint("TOPLEFT", 16, -16)
    d:SetPoint("BOTTOMRIGHT", -16, 14)
    c.detail = d
    if K.Safety then c.cover = K.Safety:Cover(card) end

    d.ring = UI.Circle(d, 54, "ARTWORK", 0)
    d.ring:SetPoint("TOPLEFT")
    d.crest = d:CreateTexture(nil, "ARTWORK", nil, 1)
    d.crest:SetSize(48, 48)
    d.crest:SetPoint("CENTER", d.ring)
    d.crest:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    UI.Round(d.crest)
    d.name = UI.Text(d, "", "Title", "heading", PW - 66)
    d.name:SetPoint("TOPLEFT", d.ring, "TOPRIGHT", 12, -2)
    d.name:SetMaxLines(2)
    d.epithet = UI.Text(d, "", "Small", "accent", PW - 66)
    d.epithet:SetPoint("TOPLEFT", d.name, "BOTTOMLEFT", 0, -3)
    d.epithet:SetWordWrap(false)

    d.status = UI.Chip(d)
    d.status:SetPoint("TOPLEFT", 0, -66)
    d.stance = UI.Chip(d)
    d.house = UI.Text(d, "", "Small", "text", PW)
    d.house:SetPoint("TOPLEFT", 0, -92)
    d.house:SetWordWrap(false)

    d.facts = {}
    for i, label in ipairs({ "Pronouns", "Age", "Height", "Home" }) do
      local col, rowN = (i - 1) % 2, math.floor((i - 1) / 2)
      local l = UI.Text(d, label, "Label", "subtle")
      l:SetPoint("TOPLEFT", col * (PW / 2), -114 - rowN * 30)
      local v = UI.Text(d, "", "Small", "text", PW / 2 - 8)
      v:SetPoint("TOPLEFT", l, "BOTTOMLEFT", 0, -2)
      v:SetWordWrap(false)
      d.facts[label] = v
    end

    d.currently = UI.Text(d, "", "QuestFont", "subtle", PW)
    d.currently:SetPoint("TOPLEFT", 0, -178)
    d.currently:SetMaxLines(3)
    d.currently:SetSpacing(2)
    d.consent = UI.Text(d, "", "Small", "text", PW)
    d.consent:SetPoint("TOPLEFT", 0, -236)
    d.consent:SetSpacing(2)

    local nl = UI.Text(d, "Your private note", "Label", "subtle")
    nl:SetPoint("BOTTOMLEFT", 1, 104)
    d.note = UI.TextArea(d, PW, 62, 400, function(text)
      local key = c.selKey
      if key then K.db.notes[key] = text ~= "" and text or nil end
    end)
    d.note:SetPoint("BOTTOMLEFT", 0, 36)

    local bw = math.floor((PW - 12) / 3)
    d.open = UI.Button(d, "Profile", bw, 26)
    d.open:SetPoint("BOTTOMLEFT", 0, 0)
    d.open:SetScript("OnClick", function() local e = c:Selected(); if e then K.Viewer:ShowName(e.name) end end)
    d.letter = UI.Button(d, "Letter", bw, 26)
    d.letter:SetPoint("LEFT", d.open, "RIGHT", 6, 0)
    d.letter:SetScript("OnClick", function() local e = c:Selected(); if e then K.Letters:Compose(e.name) end end)
    d.kin = UI.Button(d, "Add to Kin", bw, 26)
    d.kin:SetPoint("LEFT", d.letter, "RIGHT", 6, 0)
    d.kin:SetScript("OnClick", function() local e = c:Selected(); if e then K:AddKinByName(e.name); K.Journal:RefreshCurrent() end end)

    c.empty = CreateFrame("Frame", nil, card)
    c.empty:SetAllPoints()
    local ei = c.empty:CreateTexture(nil, "ARTWORK")
    ei:SetTexture(K.Art("IconPlace"))
    ei:SetSize(64, 64)
    ei:SetPoint("CENTER", 0, 24)
    ei:SetAlpha(0.75)
    local et = UI.Text(c.empty, "Choose someone to see their profile at a glance. Double-click to open it in full.", "QuestFont", "subtle", 220)
    et:SetPoint("TOP", ei, "BOTTOM", 0, -12)
    et:SetJustifyH("CENTER")
    et:SetSpacing(2)
  end,

  refresh = function(c)
    c.filters:Select(c.filter)
    local items, total = {}, 0
    for _, e in pairs(K.Registry or {}) do
      if e.profile then
        total = total + 1
        if Matches(e, c.filter, c.search) then items[#items + 1] = e end
      end
    end
    table.sort(items, function(a, b) return (a.t or 0) > (b.t or 0) end)
    c.count:SetText(total == 1 and "1 profile" or (total .. " profiles"))

    c.list:SetItems(items, function(row, e)
      local p = e.profile
      row.dot:SetStatus(p.status)
      row.name:SetText(DisplayName(e))
      local sub = (p.epithet ~= "" and UI.Escape(p.epithet)) or (p.house ~= "" and ("of House " .. UI.Escape(p.house))) or Short(e.name)
      row.sub:SetText(sub)
      row.addon:Set(AddonLabel(p.addon), K:Theme().accent)
      row.ago:SetText(UI.Ago(e.t))
      row.sel:SetShown(c.selKey ~= nil and K.NameKey(e.name) == c.selKey)
    end)

    local e, d = c:Selected(), c.detail
    d:SetShown(e ~= nil)
    c.empty:SetShown(e == nil)
    if c.cover then c.cover:Check(e and e.name or nil) end
    if not e then return end
    if c.shown ~= c.selKey then
      c.shown = c.selKey
      d.note.edit:ClearFocus()   -- so a half-typed note can't follow you to someone else
      d.note.edit:SetText(K.db.notes[c.selKey] or "")
      UI.FadeIn(d, 0.2)
    end
    local p = e.profile
    local t = K:Theme()
    d.ring:SetVertexColor(t.ui[1], t.ui[2], t.ui[3], 1)
    local h = p.house ~= "" and K.db.houses[p.house:lower()]
    d.crest:SetTexture(p.crest or (h and h.crest) or "Interface\\Icons\\INV_Shield_05")
    d.name:SetText(DisplayName(e))
    d.epithet:SetText(p.epithet ~= "" and UI.Escape(p.epithet) or "")
    local st = K.STATUS[p.status] or K.STATUS.ooc
    d.status:Set(st.label, st.color)
    local stance = p.stance and K.STANCES[p.stance]
    d.stance:ClearAllPoints()
    d.stance:SetPoint("LEFT", d.status, "RIGHT", 6, 0)
    d.stance:Set(stance and stance.label or nil, stance and stance.color)
    d.house:SetText(p.house ~= "" and ("of House " .. UI.Escape(p.house)) or Short(e.name))
    for label, key in pairs({ Pronouns = "pronouns", Age = "age", Height = "height", Home = "home" }) do
      local v = p[key] or ""
      d.facts[label]:SetText(v ~= "" and UI.Escape(v) or "-")
    end
    d.currently:SetText(p.currently ~= "" and ("\"" .. UI.Escape(p.currently) .. "\"") or "")

    local parts = {}
    for _, f in ipairs(K.CONSENT) do
      local v = p.consent and p.consent[f.key]
      for _, cv in ipairs(K.CONSENT_VALUES) do
        if cv.key == v then parts[#parts + 1] = ("%s |cff%s%s|r"):format(f.label, UI.CardHex(cv.color), cv.label) end
      end
    end
    d.consent:SetText(table.concat(parts, "   "))
    if not d.note.edit:HasFocus() then d.note.edit:SetText(K.db.notes[c.selKey] or "") end
    local isKin = K:KinFor(e.name) ~= nil
    d.kin:SetText(isKin and "In your Kin" or "Add to Kin")
    d.kin:SetEnabled(not isKin)
  end,
})

K:On("REGISTRY", function()
  local J = K.Journal
  if J.frame and J.frame:IsShown() and J.current and J.pages[J.current].id == "directory" then J:RefreshCurrent() end
end)
