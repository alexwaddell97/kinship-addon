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

local Short = K.Short

local page   -- the Letters page, once built
local function SetKey(text)
  if not page then return end
  local key = L.CleanKey(text)
  page.key = key ~= "" and key or nil
  page:PaintOptions()
end
StaticPopupDialogs["KINSHIPRP_LETTER_KEY"] = {
  text = "Write this letter in cipher.\n\nChoose a key word, and tell it to them in character: without it, the letter reads as nonsense.",
  button1 = OKAY or "OK", button2 = CANCEL or "Cancel",
  hasEditBox = true, maxLetters = 24,
  OnShow = function(self)
    local eb = self.editBox or self.EditBox or (self.GetEditBox and self:GetEditBox())
    if eb then eb:SetText(page and page.key or ""); eb:HighlightText() end
  end,
  OnAccept = function(self)
    local eb = self.editBox or self.EditBox or (self.GetEditBox and self:GetEditBox())
    if eb then SetKey(eb:GetText()) end
  end,
  EditBoxOnEnterPressed = function(self) SetKey(self:GetText()); self:GetParent():Hide() end,
  EditBoxOnEscapePressed = function(self) self:GetParent():Hide() end,
  timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
}

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
    page = c
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
    read.body = UI.ReadArea(read, IW + 6, PAPER_H - 82 - 162, "QuestFont", "ink")
    read.body:SetPoint("TOPLEFT", 28, -82)
    read.sign = UI.Text(read, "", "QuestFont", "inkAccent", IW - 90)
    read.sign:SetPoint("BOTTOMRIGHT", -28, 86)
    read.sign:SetJustifyH("RIGHT")
    read.seal = UI.Seal(read, 56)
    read.seal:SetPoint("BOTTOMLEFT", 26, 22)
    read.encl = CreateFrame("Frame", nil, read)
    read.encl:SetSize(IW, 26)
    read.encl:SetPoint("BOTTOMLEFT", 28, 130)
    read.encl.label = UI.Text(read.encl, "Enclosed", "Small", "inkSubtle")
    read.encl.label:SetPoint("LEFT", 0, 0)
    read.enclSlots = {}
    for i = 1, L.MAX_ENCLOSED do
      local s = K.Items.NewSlot(read.encl, 26)
      s:SetPoint("LEFT", read.encl.label, "RIGHT", 8 + (i - 1) * 30, 0)
      s.tooltipAnchor = "ANCHOR_TOP"
      read.enclSlots[i] = s
    end
    read.take = UI.Button(read.encl, "Take them", 90, 24)
    read.take:SetScript("OnClick", function() if c.selected then L:TakeEnclosed(c.selected) end end)
    read.encl.extra = UI.Text(read.encl, "", "Small", "ink", IW - 130)
    read.encl.extra:SetWordWrap(false)
    read.key = UI.Edit(read, 150, 24, "ink", 24)
    read.key:SetPoint("BOTTOMLEFT", 28, 100)
    read.key.hint = UI.Text(read.key, "Key word", "Small", "inkSubtle")
    read.key.hint:SetPoint("LEFT", 8, 0)
    read.key:HookScript("OnTextChanged", function(self) self.hint:SetShown((self:GetText() or "") == "") end)
    read.decipher = UI.Button(read, "Decipher", 90, 24)
    read.decipher:SetPoint("LEFT", read.key, "RIGHT", 6, 0)
    local function Decipher()
      local l = c.selected
      if not l then return end
      if L:TryKey(l, read.key:GetText()) then
        if SOUNDKIT then PlaySound(SOUNDKIT.IG_QUEST_LIST_OPEN) end
        read.key:SetText("")
        read.key:ClearFocus()
        UI.FadeIn(read, 0.35)
      else
        K:Print("That key word doesn't make sense of it.")
      end
    end
    read.decipher:SetScript("OnClick", Decipher)
    read.key:SetScript("OnEnterPressed", Decipher)
    UI.Tooltip(read.decipher, "Decipher", "Type the key word you were given in character.")
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
    read.burn:SetScript("OnClick", function() if c.selected and L:Delete(c.selected) then c.selected = nil end end)
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
    -- How it's written: the hand, the state of the paper, and a cipher
    local function Option(x, title, body, menu)
      local b = UI.Button(w, "", 110, 22)
      b:SetPoint("TOPLEFT", x, -22)
      b:SetScript("OnClick", function(self) UI.Menu(self, menu) end)
      UI.Tooltip(b, title, body)
      return b
    end
    w.hand = Option(28, "Your hand", "How your character writes. They see it in the same hand.", function(root)
      root:CreateTitle("Your hand")
      for _, h in ipairs(L.HANDS) do
        root:CreateRadio(h.label, function() return c.hand == h.key end, function()
          c.hand = h.key
          K.db.settings.letterHand = h.key   -- remembered for your next letter
          c:PaintOptions()
        end)
      end
    end)
    w.cond = Option(144, "The paper", "The state your letter arrives in.", function(root)
      root:CreateTitle("The paper")
      for _, cd in ipairs(L.CONDITIONS) do
        root:CreateRadio(cd.label, function() return c.cond == cd.key end, function() c.cond = cd.key; c:PaintOptions() end)
      end
    end)
    w.cipher = Option(260, "Cipher", "Scramble the letter with a key word. Without the key, it reads as nonsense, "
      .. "to them and to anyone who gets hold of it.", function(root)
      root:CreateTitle("Cipher")
      root:CreateRadio("No cipher", function() return c.key == nil end, function() c.key = nil; c:PaintOptions() end)
      root:CreateRadio(c.key and ("Key word: " .. c.key) or "Write in cipher...", function() return c.key ~= nil end,
        function() StaticPopup_Show("KINSHIPRP_LETTER_KEY") end)
    end)
    w.to = UI.Field(w, "To", 170, 60, nil, "ink")
    w.to:SetPoint("TOPLEFT", 28, -54)
    -- Your characters, Kin, correspondents and the Directory, as you type
    K.Suggest(w.to.edit, function() w.title.edit:SetFocus() end)
    w.title = UI.Field(w, "Title (optional)", IW - 182, L.MAX_TITLE, nil, "ink")
    w.title:SetPoint("TOPLEFT", 210, -54)
    w.body = UI.TextArea(w, IW, PAPER_H - 102 - 154, L.MAX_BODY, nil, "ink")
    w.body:SetPoint("TOPLEFT", 28, -102)
    w.count = UI.Text(w, "", "Label", "inkSubtle")
    w.count:SetPoint("TOPLEFT", w.body, "BOTTOMLEFT", 2, -4)
    w.body.edit:HookScript("OnTextChanged", function(self) w.count:SetText(("%d / %d"):format(self:GetNumLetters(), L.MAX_BODY)) end)
    -- Enclosures: Kinship items from your bags, up to three kinds
    w.encl = CreateFrame("Frame", nil, w)
    w.encl:SetSize(IW, 26)
    w.encl:SetPoint("BOTTOMLEFT", 28, 108)
    w.enclose = UI.Button(w.encl, "Enclose...", 96, 24)
    w.enclose:SetPoint("LEFT", 0, 0)
    UI.Tooltip(w.enclose, "Enclose", "Tuck Kinship items from your bags into the letter. They leave your bags when you seal it, "
      .. "and go into theirs when they break the seal. Right-click one to take it out again.")
    w.enclSlots = {}
    for i = 1, L.MAX_ENCLOSED do
      local s = K.Items.NewSlot(w.encl, 26)
      s:SetPoint("LEFT", w.enclose, "RIGHT", 8 + (i - 1) * 30, 0)
      s:RegisterForClicks("LeftButtonUp", "RightButtonUp")
      s:SetScript("OnClick", function(_, button)
        if button == "RightButton" and c.enclosed[i] then
          local e = c.enclosed[i]
          e.n = e.n - 1
          if e.n <= 0 then table.remove(c.enclosed, i) end
          c:PaintEnclosed()
        end
      end)
      s.tooltipAnchor = "ANCHOR_TOP"
      w.enclSlots[i] = s
    end
    w.enclose:SetScript("OnClick", function(self)
      local I = K.Items
      local have, order = {}, {}
      for _, s in ipairs(I:Bag()) do
        if s and not have[s.def] and I:Get(s.def) then have[s.def] = true; order[#order + 1] = s.def end
      end
      UI.Menu(self, function(root)
        root:CreateTitle("Enclose from your bags")
        if #order == 0 then root:CreateTitle("|cff9a9a9aNothing in your bags|r") return end
        for _, id in ipairs(order) do
          local def = I:Get(id)
          local inLetter = 0
          for _, e in ipairs(c.enclosed) do if e.id == id then inLetter = e.n end end
          local left = I:Available(id) - inLetter
          if def.documentId then
            root:CreateButton("|cff9a9a9a" .. UI.Escape(def.name) .. " (carries writing: use Give)|r", function() end)
          elseif left > 0 then
            root:CreateButton(("%s (%d)"):format(UI.Escape(def.name), left), function()
              for _, e in ipairs(c.enclosed) do
                if e.id == id then e.n = e.n + 1; c:PaintEnclosed() return end
              end
              if #c.enclosed >= L.MAX_ENCLOSED then
                K:Print(("A letter holds up to %d kinds of item."):format(L.MAX_ENCLOSED))
                return
              end
              c.enclosed[#c.enclosed + 1] = { id = id, n = 1 }
              c:PaintEnclosed()
            end)
          end
        end
      end)
    end)
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
      GameTooltip:SetText("Seal it", 1, 0.82, 0)
      GameTooltip:AddLine("It waits in your Sent letters until you post it at a mailbox (postage applies). "
        .. "It goes as game mail, so it reaches them even if they're offline.", 1, 1, 1, true)
      GameTooltip:Show()
    end)
    w.send:HookScript("OnLeave", function() GameTooltip:Hide() end)
    w.cancel = UI.Button(w, "Cancel", 80, 26)
    w.cancel:SetPoint("RIGHT", w.send, "LEFT", -6, 0)
    w.cancel:SetScript("OnClick", function() c.mode = "read"; K.Journal:RefreshCurrent() end)
    w.send:SetScript("OnClick", function()
      local letter, err = L:Send(w.to.edit:GetText(), w.title.edit:GetText(), w.body.edit:GetText(),
        w.sign.edit:GetText(), c.seal, c.crest, { hand = c.hand, cond = c.cond, key = c.key, enclosed = c.enclosed })
      if not letter then K:Print(err) return end
      if SOUNDKIT then PlaySound(SOUNDKIT.IG_QUEST_LOG_CLOSE) end
      c.box, c.selected, c.mode = "out", letter, "read"
      K.Journal:RefreshCurrent()
      -- It waits to be posted: only Post them, at a mailbox, spends postage
      K:Print((K.Post and K.Post.open)
        and "Sealed. Press Post them beside the mail window to send it (postage applies)."
        or "Sealed. It's in your Sent letters, to post next time you're at a mailbox.")
    end)

    function c:PaintSeal()
      self.write.seal:SetSeal(self.seal, L.CrestTexture(self.crest))
      for _, b in ipairs(self.write.swatches) do
        local on = b.key == self.seal
        b.ring:SetVertexColor(0.30, 0.20, 0.08, on and 0.9 or 0)
        b.dot:SetSize(on and 12 or 14, on and 12 or 14)   -- the chosen wax sits inside a visible ring
      end
    end

    function c:PaintEnclosed()
      for i, s in ipairs(w.enclSlots) do
        local e = self.enclosed[i]
        s:SetItem(e and K.Items:Get(e.id), e and e.n)
        s:SetShown(e ~= nil)
      end
    end

    function c:PaintOptions()
      w.hand:SetText(L.HandLabel(self.hand))
      w.cond:SetText(L.CondLabel(self.cond))
      w.cipher:SetText(self.key and "In cipher" or "No cipher")
      w.body.edit:SetFontObject(L.HandFont(self.hand))
      L.Stain(self.paper, self.cond, "draft")
    end

    function c:Compose(to, title)
      self.mode = "write"
      self.hand = L.ValidHand(K.db.settings.letterHand)
      self.cond, self.key = "pristine", nil
      self.enclosed = {}
      self:PaintEnclosed()
      self.seal = self.seal or "crimson"
      self.crest = DefaultCrest()
      K.Journal:RefreshCurrent()
      w.to.edit:SetText(to or "")
      w.title.edit:SetText(title or "")
      w.body.edit:SetText("")
      w.sign.edit:SetText(DefaultSign())
      self:PaintSeal()
      self:PaintOptions()
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
          if l.enclosed and not l.taken then L:TakeEnclosed(l) end
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
    -- The paper's condition, for the letter on show (or the one being written)
    if writing then L.Stain(c.paper, c.cond, "draft")
    else L.Stain(c.paper, l and l.cond, l and l.id) end
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
    -- In the writer's hand; a letter in cipher reads as nonsense until its key is found
    r.body.text:SetFontObject(L.HandFont(l.hand))
    r.body:SetText(UI.Escape(l.body))
    r.sign:SetFontObject(L.HandFont(l.hand))
    r.sign:SetTextColor(unpack(UI.INK.inkAccent))
    r.sign:SetText(l.sign ~= "" and ("— " .. UI.Escape(l.sign)) or "")
    -- What's enclosed: Kinship items (to take), and real gold or items (from the mail)
    local items = l.enclosed or {}
    local real = (l.purse or 0) > 0 or (type(l.goods) == "table" and #l.goods > 0) or (type(l.goods) == "number" and l.goods > 0)
    r.encl:SetShown(#items > 0 or real)
    local lastSlot
    for i, s in ipairs(r.enclSlots) do
      local e = items[i]
      s:SetItem(e and (K.Items:Get(e.d.id) or e.d), e and e.n)
      s:SetShown(e ~= nil)
      if e then lastSlot = s end
    end
    local anchor = lastSlot or r.encl.label
    local canTake = l.dir == "in" and #items > 0 and not l.taken and l.read
    r.take:SetShown(canTake and true or false)
    r.take:ClearAllPoints()
    r.take:SetPoint("LEFT", anchor, "RIGHT", 10, 0)
    r.encl.extra:ClearAllPoints()
    r.encl.extra:SetPoint("LEFT", canTake and r.take or anchor, "RIGHT", 10, 0)
    local extra = real and L.EnclosedLine({ purse = l.purse, goods = l.goods }) or nil
    r.encl.extra:SetText(extra and ((#items > 0 and "and " or "") .. extra .. (l.dir == "in" and " (take it from the mail)" or "")) or "")
    local locked = l.dir == "in" and l.cipher and not l.solved
    r.key:SetShown(locked and true or false)
    r.decipher:SetShown(locked and true or false)
    if l.cipher or l.key then
      meta[#meta + 1] = locked and "In cipher" or (l.key and ("In cipher, key: " .. UI.Escape(l.key)) or "Deciphered")
      r.meta:SetText(table.concat(meta, "  ·  "))
    end
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
