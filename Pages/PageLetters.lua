-- Kinship RP: Letters page. Received and sent letters on the left; on the
-- right a sheet of paper that is either a sealed letter waiting to be
-- opened, an open letter, or a fresh page being written.

local ADDON, ns = ...
local K = ns.K
local UI = K.UI
local L = K.Letters

local CW, CH, TOP = 696, 466, 34
local LIST_W = 276
local PAPER_W, PAPER_H = CW - LIST_W - 12, CH - TOP
-- Letters are paper in either look.
local PAPER, PAPER_EDGE, PAPER_RULE = { 0.955, 0.925, 0.850 }, { 0.30, 0.20, 0.08, 0.40 }, { 0.45, 0.32, 0.15, 0.16 }
local STATES = {
  outbox      = { label = "To post",     color = { 0.95, 0.76, 0.36 } },
  posted      = { label = "Posted",      color = { 0.42, 0.82, 0.50 } },
  -- Letters sent by courier, before letters went by post
  sending     = { label = "Sending",     color = { 0.95, 0.76, 0.36 } },
  delivered   = { label = "Delivered",   color = { 0.42, 0.82, 0.50 } },
  unconfirmed = { label = "No reply",    color = { 0.95, 0.60, 0.30 } },
  failed      = { label = "Not sent",    color = { 0.90, 0.36, 0.30 } },
}

local function Short(n) return Ambiguate and Ambiguate(n or "?", "none") or (n or "?") end

-- A sheet of paper with a soft shadow and a faint ruled margin.
local function Paper(parent, w, h)
  local p = CreateFrame("Frame", nil, parent)
  p:SetSize(w, h)
  local shadow = parent:CreateTexture(nil, "BACKGROUND")
  shadow:SetColorTexture(0, 0, 0, 0.35)
  shadow:SetPoint("TOPLEFT", p, "TOPLEFT", 3, -3)
  shadow:SetPoint("BOTTOMRIGHT", p, "BOTTOMRIGHT", 3, -3)
  p.bg = p:CreateTexture(nil, "BACKGROUND")
  p.bg:SetAllPoints()
  p.bg:SetColorTexture(PAPER[1], PAPER[2], PAPER[3], 1)
  p.edge = UI.Border(p, PAPER_EDGE)
  local rule = CreateFrame("Frame", nil, p)
  rule:SetPoint("TOPLEFT", 9, -9)
  rule:SetPoint("BOTTOMRIGHT", -9, 9)
  UI.Border(rule, PAPER_RULE)
  return p
end

local function DefaultCrest()
  local h = K:House()
  return h and h.crest or "monogram"
end

local function DefaultSign()
  local house = K:HouseName()
  return K:PlayerName() .. (house ~= "" and (", of House " .. house) or "")
end

K:RegisterPage({
  id = "letters", title = "Letters", heading = "Letters",
  subtitle = "Write, seal and post letters to other characters.",

  build = function(c)
    c.box, c.mode = "in", "read"

    c.boxes = UI.Segments(c, { { key = "in", label = "Received" }, { key = "out", label = "Sent" } }, 90,
      function(key) c.box = key; c.selected = nil; K.Journal:RefreshCurrent() end)
    c.boxes:SetPoint("TOPLEFT", 0, 0)
    local write = UI.Button(c, "Write a letter", 130, 24)
    write:SetPoint("TOPRIGHT", 0, 0)
    write:SetScript("OnClick", function() c:Compose("") end)

    -- The pile ------------------------------------------------------------------
    c.list = UI.List(c, LIST_W, CH - TOP, 56,
      "No letters yet. Write to someone, post it at a mailbox, and they'll find a sealed letter waiting for them.",
      function(row)
        row.seal = UI.Seal(row, 30)
        row.seal:SetPoint("LEFT", 10, 0)
        row.name = UI.Text(row, "", "Header", "heading", 150)
        row.name:SetPoint("TOPLEFT", 50, -11)
        row.name:SetWordWrap(false)
        row.title = UI.Text(row, "", "Small", "subtle", 132)
        row.title:SetPoint("TOPLEFT", row.name, "BOTTOMLEFT", 0, -4)
        row.title:SetWordWrap(false)
        row.when = UI.Text(row, "", "Small", "subtle")
        row.when:SetPoint("TOPRIGHT", -10, -12)
        row.chip = UI.Chip(row)
        row.chip:SetPoint("BOTTOMRIGHT", -10, 9)
        row:SetScript("OnClick", function(self) c.selected = self.item; c.mode = "read"; K.Journal:RefreshCurrent() end)
      end, { emptyIcon = K.Art("IconNote") })
    c.list:SetPoint("TOPLEFT", 0, -TOP)

    -- The paper ---------------------------------------------------------------------
    local paper = Paper(c, PAPER_W, PAPER_H)
    paper:SetPoint("TOPRIGHT", -2, -TOP)
    c.paper = paper
    local IW = PAPER_W - 56

    -- Sealed: an envelope with the seal, waiting to be broken
    local sealed = CreateFrame("Frame", nil, paper)
    sealed:SetAllPoints()
    c.sealed = sealed
    sealed.from = UI.Text(sealed, "A letter from", "Small", "inkSubtle")
    sealed.from:SetPoint("TOP", 0, -96)
    sealed.name = UI.Text(sealed, "", "Huge", "inkHeading")
    sealed.name:SetPoint("TOP", sealed.from, "BOTTOM", 0, -6)
    sealed.title = UI.Text(sealed, "", "QuestFont", "inkSubtle", IW)
    sealed.title:SetPoint("TOP", sealed.name, "BOTTOM", 0, -8)
    sealed.title:SetJustifyH("CENTER")
    sealed.seal = UI.Seal(sealed, 86)
    sealed.seal:SetPoint("CENTER", 0, -30)
    sealed.open = UI.Button(sealed, "Break the seal", 150, 28)
    sealed.open:SetPoint("BOTTOM", 0, 56)
    sealed.open:SetScript("OnClick", function() c:BreakSeal() end)

    -- Open letter
    local read = CreateFrame("Frame", nil, paper)
    read:SetAllPoints()
    c.read = read
    read.meta = UI.Text(read, "", "Small", "inkSubtle", IW)
    read.meta:SetPoint("TOPRIGHT", -28, -26)
    read.meta:SetJustifyH("RIGHT")
    read.title = UI.Text(read, "", "GameFontNormalLarge", "inkHeading", IW)
    read.title:SetPoint("TOPLEFT", 28, -46)
    read.title:SetWordWrap(false)
    local rdiv = UI.Divider(read, IW, true)
    rdiv:SetPoint("TOPLEFT", 28, -72)
    read.body = UI.ReadArea(read, IW + 6, PAPER_H - 82 - 128, "QuestFont", "ink")
    read.body:SetPoint("TOPLEFT", 28, -82)
    read.sign = UI.Text(read, "", "QuestFont", "inkAccent", IW - 90)
    read.sign:SetPoint("BOTTOMRIGHT", -28, 86)
    read.sign:SetJustifyH("RIGHT")
    read.seal = UI.Seal(read, 56)
    read.seal:SetPoint("BOTTOMLEFT", 26, 22)
    read.state = UI.Chip(read)
    read.state:SetPoint("LEFT", read.seal, "RIGHT", 12, 0)
    read.reply = UI.Button(read, "Reply", 84, 24)
    read.reply:SetPoint("BOTTOMRIGHT", -26, 24)
    read.reply:SetScript("OnClick", function()
      if c.selected and c.selected.dir == "out" and c.selected.state == "failed" and K.Post then
        K.Post:Retry(c.selected)
        return
      end
      local l = c.selected
      if l then c:Compose(l.dir == "in" and l.from or l.to, l.title ~= "" and ("Re: " .. l.title:gsub("^Re: ", "")) or "") end
    end)
    read.burn = UI.Button(read, "Burn", 70, 24)
    read.burn:SetPoint("RIGHT", read.reply, "LEFT", -6, 0)
    read.burn:SetScript("OnClick", function() if c.selected then L:Delete(c.selected); c.selected = nil end end)
    UI.Tooltip(read.burn, "Burn this letter", "Delete it from your letters for good.")

    -- Nothing chosen
    local blank = CreateFrame("Frame", nil, paper)
    blank:SetAllPoints()
    c.blank = blank
    local bi = blank:CreateTexture(nil, "ARTWORK")
    bi:SetTexture(K.Art("IconNote"))
    bi:SetSize(64, 64)
    bi:SetPoint("CENTER", 0, 28)
    bi:SetAlpha(0.8)
    local bt = UI.Text(blank, "Choose a letter to read, or write one of your own.", "QuestFont", "inkSubtle", IW - 40)
    bt:SetPoint("TOP", bi, "BOTTOM", 0, -12)
    bt:SetJustifyH("CENTER")

    -- Writing ----------------------------------------------------------------------
    local w = CreateFrame("Frame", nil, paper)
    w:SetAllPoints()
    c.write = w
    w.heading = UI.Text(w, "A new letter", "GameFontNormalLarge", "inkHeading")
    w.heading:SetPoint("TOPLEFT", 28, -26)
    w.to = UI.Field(w, "To", 170, 60, nil, "ink")
    w.to:SetPoint("TOPLEFT", 28, -54)
    w.title = UI.Field(w, "Title (optional)", IW - 182, L.MAX_TITLE, nil, "ink")
    w.title:SetPoint("TOPLEFT", 210, -54)
    w.body = UI.TextArea(w, IW, PAPER_H - 102 - 120, L.MAX_BODY, nil, "ink")
    w.body:SetPoint("TOPLEFT", 28, -102)
    w.count = UI.Text(w, "", "Label", "inkSubtle")
    w.count:SetPoint("TOPLEFT", w.body, "BOTTOMLEFT", 2, -4)
    w.body.edit:HookScript("OnTextChanged", function(self) w.count:SetText(("%d / %d"):format(self:GetNumLetters(), L.MAX_BODY)) end)
    w.sign = UI.Field(w, "Signed", IW - 96, L.MAX_SIGN, nil, "ink")
    w.sign:SetPoint("BOTTOMLEFT", 28, 64)

    -- Seal: colour swatches and the crest pressed into it (click the seal to change)
    w.seal = UI.Seal(w, 52)
    w.seal:SetPoint("BOTTOMRIGHT", -28, 66)
    w.sealBtn = CreateFrame("Button", nil, w.seal)
    w.sealBtn:SetAllPoints()
    w.sealBtn:SetScript("OnClick", function()
      c.crest = (c.crest == "monogram") and (K:House() and K:House().crest or "monogram") or "monogram"
      c:PaintSeal()
    end)
    UI.Tooltip(w.sealBtn, "Your seal", "Click to switch between your house crest and the Kinship monogram.")
    w.swatches = {}
    for i, s in ipairs(UI.SEAL_COLORS) do
      local b = CreateFrame("Button", nil, w)
      b:SetSize(18, 18)
      b:SetPoint("BOTTOMLEFT", 28 + (i - 1) * 22, 28)
      b.ring = UI.Circle(b, 18, "ARTWORK", 0)
      b.ring:SetPoint("CENTER")
      b.dot = UI.Circle(b, 14, "ARTWORK", 1)
      b.dot:SetPoint("CENTER")
      b.dot:SetVertexColor(s.color[1], s.color[2], s.color[3], 1)
      b.key = s.key
      b:SetScript("OnClick", function() c.seal = s.key; c:PaintSeal() end)
      UI.Tooltip(b, s.label .. " wax")
      w.swatches[i] = b
    end
    w.send = UI.Button(w, "Seal it", 110, 26)
    w.send:SetPoint("BOTTOMRIGHT", -28, 24)
    w.send:HookScript("OnEnter", function(self)
      GameTooltip:SetOwner(self, "ANCHOR_TOP")
      if K.Post and K.Post.open then
        GameTooltip:SetText("Seal & post", 1, 0.82, 0)
        GameTooltip:AddLine("It goes by mail now, so it reaches them even if they're offline.", 1, 1, 1, true)
      else
        GameTooltip:SetText("Seal it", 1, 0.82, 0)
        GameTooltip:AddLine("It waits in your Sent letters until you next open a mailbox, then goes by mail, "
          .. "so it reaches them even if they're offline.", 1, 1, 1, true)
      end
      GameTooltip:Show()
    end)
    w.send:HookScript("OnLeave", function() GameTooltip:Hide() end)
    w.cancel = UI.Button(w, "Cancel", 80, 26)
    w.cancel:SetPoint("RIGHT", w.send, "LEFT", -6, 0)
    w.cancel:SetScript("OnClick", function() c.mode = "read"; K.Journal:RefreshCurrent() end)
    w.send:SetScript("OnClick", function()
      local letter, err = L:Send(w.to.edit:GetText(), w.title.edit:GetText(), w.body.edit:GetText(),
        w.sign.edit:GetText(), c.seal, c.crest)
      if not letter then K:Print(err) return end
      if SOUNDKIT then PlaySound(SOUNDKIT.IG_QUEST_LOG_CLOSE) end
      c.box, c.selected, c.mode = "out", letter, "read"
      K.Journal:RefreshCurrent()
      -- At a mailbox it goes straight away; otherwise it waits for one
      if K.Post and K.Post.open then K.Post:PostAll()
      else K:Print("Sealed. It's in your Sent letters, to be posted next time you open a mailbox.") end
    end)

    function c:PaintSeal()
      self.write.seal:SetSeal(self.seal, L.CrestTexture(self.crest))
      for _, b in ipairs(self.write.swatches) do
        local on = b.key == self.seal
        b.ring:SetVertexColor(0.30, 0.20, 0.08, on and 0.9 or 0)
        b.dot:SetSize(on and 12 or 14, on and 12 or 14)   -- the chosen wax sits inside a visible ring
      end
    end

    function c:Compose(to, title)
      self.mode = "write"
      w.send:SetText((K.Post and K.Post.open) and "Seal & post" or "Seal it")
      self.seal = self.seal or "crimson"
      self.crest = DefaultCrest()
      K.Journal:RefreshCurrent()
      w.to.edit:SetText(to or "")
      w.title.edit:SetText(title or "")
      w.body.edit:SetText("")
      w.sign.edit:SetText(DefaultSign())
      self:PaintSeal()
      UI.FadeIn(w, 0.2)
      if (to or "") == "" then w.to.edit:SetFocus() else w.body.edit:SetFocus() end
    end

    -- Breaking the seal: it swells and fades, then the letter appears.
    function c:BreakSeal()
      local l = self.selected
      if not l then return end
      if SOUNDKIT then PlaySound(SOUNDKIT.IG_QUEST_LIST_OPEN) end
      local s = sealed.seal
      UI.SetProgress(s, 0)
      UI.Tween(s, 1, 0.35, function(p)
        local sc = 1 + 0.45 * p
        s:SetScale(sc)
        s:SetPoint("CENTER", 0, -30 / sc)   -- offsets scale with the frame; keep it in place
        s:SetAlpha(1 - p)
        if p >= 1 then
          s:SetScale(1); s:SetAlpha(1); s:SetPoint("CENTER", 0, -30)
          l.read = true
          K:Fire("LETTERS")
          UI.FadeIn(c.read, 0.35)
        end
      end, UI.Ease.outQuart)
    end
  end,

  refresh = function(c)
    if L.focus then
      c.box, c.selected, c.mode = L.focus.dir, L.focus, "read"
      L.focus = nil
    end
    if L.composeTo then
      local to = L.composeTo
      L.composeTo = nil
      c:Compose(to)
      return
    end
    c.boxes:Select(c.box)

    local items = {}
    for _, l in ipairs(K:LetterBox()) do
      -- Letters from someone you've ignored stay hidden (and come back if you stop).
      if l.dir == c.box and not (l.dir == "in" and K:IsIgnored(l.from)) then items[#items + 1] = l end
    end
    c.list:SetItems(items, function(row, l)
      local who = l.dir == "in" and l.from or l.to
      row.seal:SetSeal(l.seal, L.CrestTexture(l.crest))
      row.seal:SetAlpha((l.dir == "in" and not l.read) and 1 or 0.55)
      row.name:SetText((l.dir == "out" and "To " or "") .. Short(who))
      row.title:SetText(l.title ~= "" and UI.Escape(l.title) or UI.Escape(l.body:sub(1, 60):gsub("\n", " ")))
      row.when:SetText(date("%d %b", l.t))
      if l.dir == "in" and not l.read then row.chip:Set("Sealed", UI.SealColor(l.seal))
      elseif l.dir == "out" and STATES[l.state] and l.state ~= "delivered" then row.chip:Set(STATES[l.state].label, STATES[l.state].color)
      else row.chip:Set(nil) end
      row.sel:SetShown(l == c.selected)
    end)

    local l = c.selected
    if l and not L:Find(l.id) then l, c.selected = nil, nil end
    local writing = c.mode == "write"
    local isSealed = not writing and l and l.dir == "in" and not l.read
    c.write:SetShown(writing)
    c.sealed:SetShown(isSealed and true or false)
    c.read:SetShown(not writing and l ~= nil and not isSealed)
    c.blank:SetShown(not writing and l == nil)
    if writing or not l then return end

    if c.shown ~= l then c.shown = l; UI.FadeIn(c.paper, 0.2) end
    if isSealed then
      c.sealed.name:SetText(Short(l.from))
      c.sealed.title:SetText(l.title ~= "" and ("\"" .. UI.Escape(l.title) .. "\"") or "")
      c.sealed.seal:SetSeal(l.seal, L.CrestTexture(l.crest))
      return
    end
    local r = c.read
    local meta = { date("%d %B %Y", l.sent or l.t) }
    if l.place and l.place ~= "" then meta[#meta + 1] = UI.Escape(l.place) end
    r.meta:SetText(table.concat(meta, "  ·  "))
    r.title:SetText(l.title ~= "" and UI.Escape(l.title) or (l.dir == "in" and ("From " .. Short(l.from)) or ("To " .. Short(l.to))))
    r.body:SetText(UI.Escape(l.body))
    r.sign:SetText(l.sign ~= "" and ("— " .. UI.Escape(l.sign)) or "")
    r.seal:SetSeal(l.seal, L.CrestTexture(l.crest))
    local st = l.dir == "out" and STATES[l.state]
    r.state:Set(st and st.label or nil, st and st.color)
    local retry = l.dir == "out" and l.state == "failed"
    r.reply:SetText(l.dir == "in" and "Reply" or (retry and "Try again" or "Write again"))
    r.reply:SetWidth(l.dir == "in" and 84 or 110)
  end,
})

K:On("LETTERS", function()
  local J = K.Journal
  if J.frame and J.frame:IsShown() and J.current and J.pages[J.current].id == "letters" then J:RefreshCurrent() end
end)
