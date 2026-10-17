-- Kinship RP: guided tours. The first time you open a journal page (or the
-- Roleplay pane, the target bar, the profile viewer), a short tour walks
-- through it: everything else dims, the part being explained is lit, and a
-- card says what it's for. Back, Next and Skip; Esc skips too. A "?" in the
-- journal's header replays the tour for the page you're on, and Settings >
-- Guides can switch them off or show them all again.
--
--   K:RegisterGuide({
--     id    = "profile",           -- remembered once seen (account-wide)
--     page  = "profile",           -- a journal page: starts on the first visit there
--     title = "Your character",    -- shown at the top of the card
--     steps = {
--       { title = "...", text = "...",
--         target = function(ctx) return someRegion end, -- nil = centred, no spotlight
--         side   = "right" | "left" | "top" | "bottom" | "auto" (default),
--         before = function(ctx) end,                   -- e.g. switch to a tab first
--         pad    = 4 },                                 -- extra space around the light
--     },
--     finish = function(skipped, ctx) end,               -- optional: tidy up after
--   })
--   K.Guide:Maybe(id, ctx)   start if not seen yet and guides are on
--   K.Guide:Start(id, ctx)   start now (the "?" button)
-- ctx is the page's content frame for journal pages, or whatever Maybe/Start
-- was given. A step whose target is missing or hidden shows centred instead.

local ADDON, ns = ...
local K = ns.K
local UI = K.UI
local G = { defs = {}, order = {}, queue = {} }
K.Guide = G

local WHITE = "Interface\\Buttons\\WHITE8X8"
local CARD_W = 310
local DIM = { 0, 0, 0, 0.62 }

function K:RegisterGuide(def)
  if type(def) ~= "table" or type(def.id) ~= "string" or type(def.steps) ~= "table" then return end
  if not G.defs[def.id] then G.order[#G.order + 1] = def.id end
  G.defs[def.id] = def
end

local function DB() return K.db and K.db.guides end
function G:Seen(id) local d = DB(); return d and d.seen[id] and true or false end
function G:MarkSeen(id) local d = DB(); if d then d.seen[id] = time() end end
function G:Reset() local d = DB(); if d then wipe(d.seen) end end
function G:AutoOn() return K.db and K.db.settings.guidesAuto ~= false end

---------------------------------------------------------------------------
-- The overlay: four dimmed panes around a lit rectangle, a glowing edge,
-- and the card.
---------------------------------------------------------------------------
local function Build()
  if G.frame then return G.frame end
  local o = CreateFrame("Frame", "KinshipRPGuide", UIParent)
  o:SetAllPoints(UIParent)
  o:SetFrameStrata("FULLSCREEN_DIALOG")
  o:SetToplevel(true)
  o:Hide()
  G.frame = o

  o.panes = {}
  for i = 1, 4 do
    local p = CreateFrame("Frame", nil, o)
    p:EnableMouse(true)          -- the rest of the screen waits until the tour is done
    p.t = p:CreateTexture(nil, "BACKGROUND")
    p.t:SetAllPoints()
    p.t:SetColorTexture(unpack(DIM))
    o.panes[i] = p
  end

  o.edge = CreateFrame("Frame", nil, o)
  o.edge:SetFrameLevel(o:GetFrameLevel() + 2)
  o.edge.b = UI.Border(o.edge)
  o.edge.glow = CreateFrame("Frame", nil, o.edge)
  o.edge.glow:SetPoint("TOPLEFT", -3, 3)
  o.edge.glow:SetPoint("BOTTOMRIGHT", 3, -3)
  o.edge.glow.b = UI.Border(o.edge.glow)

  -- The card
  local c = UI.Panel(o)
  c:SetSize(CARD_W, 160)
  c:SetFrameLevel(o:GetFrameLevel() + 5)
  c:SetClampedToScreen(true)
  c:EnableMouse(true)
  o.card = c
  c.accent = c:CreateTexture(nil, "ARTWORK")
  c.accent:SetTexture(WHITE)
  c.accent:SetHeight(3)
  c.accent:SetPoint("TOPLEFT"); c.accent:SetPoint("TOPRIGHT")
  c.icon = c:CreateTexture(nil, "ARTWORK")
  c.icon:SetTexture(K.ICON)
  c.icon:SetSize(16, 16)
  c.icon:SetPoint("TOPLEFT", 16, -14)
  c.kicker = UI.Text(c, "", "Label", "subtle", CARD_W - 110)
  c.kicker:SetPoint("LEFT", c.icon, "RIGHT", 6, 0)
  c.kicker:SetWordWrap(false)
  c.count = UI.Text(c, "", "Label", "subtle")
  c.count:SetPoint("TOPRIGHT", -16, -16)
  c.title = UI.Text(c, "", "Header", "heading", CARD_W - 32)
  c.title:SetPoint("TOPLEFT", 16, -38)
  c.text = UI.Text(c, "", "Body", "text", CARD_W - 32)
  c.text:SetPoint("TOPLEFT", c.title, "BOTTOMLEFT", 0, -8)
  c.text:SetSpacing(3)
  c.dots = {}
  for i = 1, 12 do
    local d = UI.Circle(c, 6, "ARTWORK")
    d:Hide()
    c.dots[i] = d
  end
  c.next = UI.Button(c, "Next", 76, 24)
  c.next:SetPoint("BOTTOMRIGHT", -14, 12)
  c.next:SetScript("OnClick", function() G:Step(1) end)
  c.back = UI.Button(c, "Back", 64, 24)
  c.back:SetPoint("RIGHT", c.next, "LEFT", -6, 0)
  c.back:SetScript("OnClick", function() G:Step(-1) end)
  c.skip = UI.Button(c, "Skip tour", 84, 24)
  c.skip:SetPoint("BOTTOMLEFT", 14, 12)
  c.skip:SetScript("OnClick", function() G:Finish(true) end)
  UI.Tooltip(c.skip, "Skip this tour", "Replay it any time with the ? at the top of the journal. Esc skips every tour waiting; Settings > Guides turns them off.")
  UI:OnTheme(function(t)
    c.accent:SetVertexColor(unpack(t.accent))
    o.edge.b:SetColor(t.ui[1], t.ui[2], t.ui[3], 1)
    for _, d in ipairs(c.dots) do d:SetVertexColor(t.accent[1], t.accent[2], t.accent[3], 1) end
  end)

  -- Follow the target if its window moves, and breathe the glow.
  o.t = 0
  o:SetScript("OnUpdate", function(self, elapsed)
    self.t = self.t + elapsed
    local a = 0.35 + 0.30 * math.sin(self.t * 3)
    local u = K:Theme().ui
    self.edge.glow.b:SetColor(u[1], u[2], u[3], a)
    if G.host and not G.host:IsVisible() then G:Finish(true, true) return end
    if not G.tweening and self.t - (self.lastFollow or 0) > 0.1 then
      self.lastFollow = self.t
      G:Place(false)
    end
  end)
  o:SetScript("OnHide", function() if G.active then G:Finish(true, true) end end)
  tinsert(UISpecialFrames, "KinshipRPGuide")   -- Esc skips this tour and any waiting after it
  return o
end

-- The lit rectangle, in UIParent's coordinates, for a region (or nil).
local function RectOf(region, pad)
  if not region or not region.GetLeft or not region:IsVisible() then return nil end
  local l, r, t, b = region:GetLeft(), region:GetRight(), region:GetTop(), region:GetBottom()
  if not (l and r and t and b) then return nil end
  local s = region:GetEffectiveScale() / UIParent:GetEffectiveScale()
  pad = pad or 4
  return { l = l * s - pad, r = r * s + pad, t = t * s + pad, b = b * s - pad }
end

local function Lerp(a, b, p) return a + (b - a) * p end

-- Lay out the dim panes, the edge and the card for a rectangle.
local function Draw(o, rect, side)
  local W, H = UIParent:GetWidth(), UIParent:GetHeight()
  local P = o.panes
  for _, p in ipairs(P) do p:ClearAllPoints() end
  local c = o.card
  c:ClearAllPoints()
  if not rect then
    P[1]:SetAllPoints(UIParent)
    for i = 2, 4 do P[i]:Hide() end
    P[1]:Show()
    o.edge:Hide()
    local host = G.host
    if host and host:IsVisible() then c:SetPoint("CENTER", host, "CENTER") else c:SetPoint("CENTER", UIParent, "CENTER", 0, 60) end
    return
  end
  for _, p in ipairs(P) do p:Show() end
  -- top, bottom, left, right
  P[1]:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 0, 0)
  P[1]:SetPoint("BOTTOMRIGHT", UIParent, "TOPRIGHT", 0, -(H - rect.t))
  P[2]:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", 0, rect.b)
  P[2]:SetPoint("BOTTOMRIGHT", UIParent, "BOTTOMRIGHT", 0, 0)
  P[3]:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", 0, rect.t)
  P[3]:SetPoint("BOTTOMRIGHT", UIParent, "BOTTOMLEFT", rect.l, rect.b)
  P[4]:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", rect.r, rect.t)
  P[4]:SetPoint("BOTTOMRIGHT", UIParent, "BOTTOMRIGHT", 0, rect.b)
  o.edge:Show()
  o.edge:ClearAllPoints()
  o.edge:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", rect.l, rect.t)
  o.edge:SetPoint("BOTTOMRIGHT", UIParent, "BOTTOMLEFT", rect.r, rect.b)

  -- The card goes beside the light, on the requested side or wherever there's room.
  local cw, ch, gap = c:GetWidth(), c:GetHeight(), 14
  local room = { right = W - rect.r, left = rect.l, top = H - rect.t, bottom = rect.b }
  if room[side or ""] == nil then
    side = nil
  elseif room[side] < ((side == "left" or side == "right") and (cw + gap) or (ch + gap)) then
    side = nil   -- no room on the side asked for
  end
  if not side then
    if room.right >= cw + gap then side = "right"
    elseif room.left >= cw + gap then side = "left"
    elseif room.bottom >= ch + gap then side = "bottom"
    else side = "top" end
  end
  local cx, cy = (rect.l + rect.r) / 2, (rect.t + rect.b) / 2
  if side == "right" then c:SetPoint("LEFT", UIParent, "BOTTOMLEFT", rect.r + gap, cy)
  elseif side == "left" then c:SetPoint("RIGHT", UIParent, "BOTTOMLEFT", rect.l - gap, cy)
  elseif side == "bottom" then c:SetPoint("TOP", UIParent, "BOTTOMLEFT", cx, rect.b - gap)
  else c:SetPoint("BOTTOM", UIParent, "BOTTOMLEFT", cx, rect.t + gap) end
end

-- Measure the current step's target and draw; animate = glide from the last spot.
function G:Place(animate)
  local o, step = self.frame, self.steps and self.steps[self.index]
  if not o or not step then return end
  local region
  if step.target then
    local ok, r = K.Try("guide", step.target, self.ctx)
    if ok then region = r end
  end
  local rect = RectOf(region, step.pad)
  local from = self.rect
  self.rect = rect
  if animate and from and rect then
    self.tweening = true
    UI.SetProgress(self, 0)
    UI.Tween(self, 1, 0.28, function(p)
      Draw(o, { l = Lerp(from.l, rect.l, p), r = Lerp(from.r, rect.r, p), t = Lerp(from.t, rect.t, p), b = Lerp(from.b, rect.b, p) }, step.side)
      if p >= 1 then self.tweening = false end
    end, UI.Ease.outQuart)
  else
    self.tweening = false
    Draw(o, rect, step.side)
  end
end

---------------------------------------------------------------------------
-- Running a tour
---------------------------------------------------------------------------
function G:Show()
  local o, def = self.frame, self.def
  local step = self.steps[self.index]
  if not step then return self:Finish(false) end
  if step.before then K.Try("guide", step.before, self.ctx) end
  local c = o.card
  local n = #self.steps
  c.kicker:SetText("Guide  ·  " .. (def.title or def.id))
  c.count:SetText(("%d / %d"):format(self.index, n))
  c.title:SetText(step.title or "")
  c.text:SetText(step.text or "")
  local h = 38 + c.title:GetStringHeight() + 8 + c.text:GetStringHeight() + 24 + 46
  c:SetHeight(math.ceil(h))
  -- Progress dots, centred above the buttons
  local shown = math.min(n, #c.dots)
  for i, d in ipairs(c.dots) do
    d:SetShown(i <= shown)
    if i <= shown then
      d:ClearAllPoints()
      d:SetPoint("BOTTOM", c, "BOTTOM", (i - (shown + 1) / 2) * 11, 44)
      d:SetAlpha(i == self.index and 1 or 0.3)
    end
  end
  c.back:SetEnabled(self.index > 1)
  c.next:SetText(self.index == n and "Done" or "Next")
  c.skip:SetShown(self.index < n)
  UI.FadeIn(c, 0.15)
  -- Let a tab switch in `before` settle before measuring.
  C_Timer.After(0, function() if G.active and G.steps[G.index] == step then G:Place(true) end end)
end

function G:Step(d)
  if not self.active then return end
  local i = self.index + d
  if i < 1 then return end
  if i > #self.steps then return self:Finish(false) end
  self.index = i
  if SOUNDKIT and SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON then PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON) end
  self:Show()
end

-- skipped: Skip or Esc; all: drop any tours waiting their turn too.
function G:Finish(skipped, all)
  if not self.active then return end
  self:MarkSeen(self.def.id)
  local after, ctx = self.def.finish, self.ctx
  self.active, self.def, self.steps, self.ctx, self.host, self.rect = nil, nil, nil, nil, nil, nil
  self.tweening = false
  if self.frame:IsShown() then self.frame:Hide() end
  if after then K.Try("guide", after, skipped, ctx) end
  -- Anything that was waiting its turn (the page tour after the welcome tour)
  if all then wipe(self.queue) return end
  local nxt = table.remove(self.queue, 1)
  if nxt then C_Timer.After(0.25, function() G:Maybe(nxt.id, nxt.ctx, nxt.host) end) end
end

-- host: a frame whose hiding ends the tour (the journal, the character window...).
function G:Start(id, ctx, host)
  local def = self.defs[id]
  if not def or #def.steps == 0 then return false end
  if self.active then self:Finish(true) end
  wipe(self.queue)
  local o = Build()
  self.active, self.def, self.steps, self.ctx, self.index = true, def, def.steps, ctx, 1
  self.host = host
  self.rect = nil
  o:Show()
  o:Raise()
  self:Show()
  return true
end

function G:Maybe(id, ctx, host)
  if not K.db or not self:AutoOn() or self:Seen(id) or not self.defs[id] then return end
  if InCombatLockdown() then return end
  if self.active then
    if self.def.id ~= id then self.queue[#self.queue + 1] = { id = id, ctx = ctx, host = host } end
    return
  end
  self:Start(id, ctx, host)
end

-- The guide for a journal page, if there is one.
local function PageGuide(pageId)
  for _, gid in ipairs(G.order) do
    if G.defs[gid].page == pageId then return gid end
  end
end
G.PageGuide = PageGuide

---------------------------------------------------------------------------
-- The journal: a welcome tour on first open, a tour per page on first
-- visit, and a "?" in the header to replay the one for the page you're on.
---------------------------------------------------------------------------
local J = K.Journal

local function CurrentPage()
  if not (J.frame and J.frame:IsShown() and J.current) then return nil end
  return J.pages[J.current], J.content[J.current]
end

function G:ReplayCurrent()
  local page, content = CurrentPage()
  local gid = page and ((page.guide and content and page.guide(content)) or PageGuide(page.id))
  if gid and content and content.ok then self:Start(gid, content, J.frame)
  elseif self.defs.journal then self:Start("journal", J, J.frame) end
end

local function AddHelpButton()
  local f = J.frame
  if not f or J.helpButton then return end
  local b = CreateFrame("Button", nil, f)
  b:SetSize(22, 22)
  b:SetPoint("TOPRIGHT", -38, -7)
  b:SetFrameLevel(f:GetFrameLevel() + 10)
  b.ring = UI.Circle(b, 22, "ARTWORK", 0)
  b.ring:SetPoint("CENTER")
  b.hole = UI.Circle(b, 19, "ARTWORK", 1)
  b.hole:SetPoint("CENTER")
  b.q = UI.Text(b, "?", "Header", "plain")
  b.q:SetPoint("CENTER", 0, 0)
  local function paint(p)
    local t = K:Theme()
    b.ring:SetVertexColor(t.ui[1], t.ui[2], t.ui[3], 0.45 + 0.55 * p)
    b.hole:SetVertexColor(t.chrome[1], t.chrome[2], t.chrome[3], 1)
    b.q:SetTextColor(t.ui[1], t.ui[2], t.ui[3], 0.75 + 0.25 * p)
  end
  b:SetScript("OnEnter", function(self)
    UI.Tween(self, 1, 0.1, paint)
    GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
    GameTooltip:SetText("Guide", 1, 0.82, 0)
    GameTooltip:AddLine("A short tour of this page.", 1, 1, 1, true)
    GameTooltip:Show()
  end)
  b:SetScript("OnLeave", function(self) UI.Tween(self, 0, 0.12, paint); GameTooltip:Hide() end)
  b:SetScript("OnClick", function() G:ReplayCurrent() end)
  UI:OnTheme(function() paint(UI.Progress(b)) end)
  J.helpButton = b
end

hooksecurefunc(J, "Build", function() AddHelpButton() end)

hooksecurefunc(J, "Show", function(self)
  if not K.db then return end
  local page, content = CurrentPage()
  if not page or not content or not content.ok then return end
  local id = page.id
  local function Go()
    if not G:AutoOn() or not J:IsShowing(id) then return end
    if G.defs.journal and not G:Seen("journal") then
      G:Maybe("journal", J, J.frame)
      local gid = PageGuide(id)
      if gid and not G:Seen(gid) then G.queue[#G.queue + 1] = { id = gid, ctx = content, host = J.frame } end
      return
    end
    local gid = PageGuide(id)
    if gid then G:Maybe(gid, content, J.frame) end
  end
  C_Timer.After(0.35, function()
    if not J:IsShowing(id) then return end
    -- One question first (RPExperience.lua), then the tours.
    local X = K.Experience
    if X and X:NeedsAsking() then X:Ask(J.frame, Go) else Go() end
  end)
end)

---------------------------------------------------------------------------
-- Saved data and settings
---------------------------------------------------------------------------
K:On("LOGIN", function()
  K.db.guides = K.db.guides or {}
  K.db.guides.seen = K.db.guides.seen or {}
  if K.db.settings.guidesAuto == nil then K.db.settings.guidesAuto = true end
end)

K:RegisterSettings({ id = "guides", title = "Guides", order = 2, build = function(card)
  card:Toggle("Guide me through new pages", "The first time you open a page, a short tour shows what everything does. Skip any tour with Esc.",
    { get = function() return G:AutoOn() end, set = function(v) K.db.settings.guidesAuto = v end })
  card:Button("Show every guide again", function()
    G:Reset()
    K:Print("Guides reset: each page shows its tour again the next time you open it.")
  end, 200)
  card:Note("The ? at the top of the journal replays the tour for the page you're on.")
end })
