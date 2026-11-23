-- Kinship RP: Total RP 3: Extended cutscenes and documents, as campaigns
-- play them. A cutscene is a run of steps: who speaks (left, right or
-- nobody), their models, a background and an image, lines of text shown one
-- click at a time, and choices that lead to other steps. A step can run a
-- workflow as it begins; the cutscene runs others as it starts and ends.
-- Documents open in Kinship's own paper reader.
--   K.ExtCutscene:Play(fullID, args)  Quick(text, args)  Stop()
--   K.ExtCutscene:ShowDocument(fullID, args)  CloseDocument()

local _, ns = ...
local K = ns.K
local UI = K.UI
local E = K.Ext
local S = K.ExtScript
local C = {}
K.ExtCutscene = C

local EMPTY = {}
local W, H = 780, 380
local CHAT_H = 118
local CHOICES = 6

local function Step(class, i)
  local ds = type(class) == "table" and type(class.DS) == "table" and class.DS or EMPTY
  local s = ds[i]
  if s == nil and type(i) == "number" then s = ds[tostring(i)] end
  if s == nil and type(i) == "string" then s = ds[tonumber(i) or i] end
  return type(s) == "table" and s or nil
end

local function Parent(args) return type(args) == "table" and args.object or nil end

local function Run(f, scriptID)
  if scriptID == nil or not f.classID or type(f.class.SC) ~= "table" then return end
  S:Run(scriptID, f.class.SC, { object = Parent(f.args) }, f.classID)
end

---------------------------------------------------------------------------
-- The window
---------------------------------------------------------------------------
local function Model(parent, side)
  local m = CreateFrame("PlayerModel", nil, parent)
  m:SetSize(300, H - CHAT_H - 10)
  m:SetPoint(side == "LEFT" and "BOTTOMLEFT" or "BOTTOMRIGHT", parent, side == "LEFT" and "BOTTOMLEFT" or "BOTTOMRIGHT",
    side == "LEFT" and 20 or -20, CHAT_H - 6)
  m.side = side
  return m
end

local function SetModel(m, id)
  m:Hide()
  if type(id) ~= "string" or id == "" then return end
  if id == "target" and not UnitExists("target") then return end
  m:Show()
  if m.ClearModel then pcall(m.ClearModel, m) end
  if id == "player" or id == "target" then
    pcall(m.SetUnit, m, id)
  elseif id:sub(1, 3) == "DID" then
    pcall(m.SetDisplayInfo, m, tonumber(id:sub(4)) or 0)
  else
    pcall(m.SetCreature, m, tonumber(id) or 0)
  end
  pcall(m.SetFacing, m, m.side == "LEFT" and 0.7 or -0.7)
end

local function Build()
  if C.frame then return C.frame end
  local f = CreateFrame("Frame", "KinshipRPCutscene", UIParent)
  f:SetSize(W, H)
  f:SetPoint("BOTTOM", 0, 150)
  f:SetFrameStrata("DIALOG")
  f:SetToplevel(true)
  f:SetClampedToScreen(true)
  f:SetMovable(true)
  f:EnableMouse(true)
  f:RegisterForDrag("LeftButton")
  f:SetScript("OnDragStart", f.StartMoving)
  f:SetScript("OnDragStop", f.StopMovingOrSizing)
  table.insert(UISpecialFrames, "KinshipRPCutscene")

  f.shade = f:CreateTexture(nil, "BACKGROUND", nil, -8)
  f.shade:SetAllPoints()
  f.shade:SetColorTexture(0, 0, 0, 0.72)
  f.bg = f:CreateTexture(nil, "BACKGROUND", nil, -7)
  f.bg:SetAllPoints()
  f.bg:SetAlpha(0.55)
  f.edge = UI.Border(f)

  f.image = f:CreateTexture(nil, "ARTWORK")
  f.image:SetPoint("TOP", 0, -16)

  f.left, f.right = Model(f, "LEFT"), Model(f, "RIGHT")

  local chat = CreateFrame("Frame", nil, f)
  chat:SetPoint("BOTTOMLEFT", 10, 10)
  chat:SetPoint("BOTTOMRIGHT", -10, 10)
  chat:SetHeight(CHAT_H)
  chat.bg = chat:CreateTexture(nil, "BACKGROUND")
  chat.bg:SetAllPoints()
  chat.bg:SetColorTexture(0.05, 0.04, 0.03, 0.9)
  chat.edge = UI.Border(chat)
  f.chat = chat

  f.name = UI.Text(chat, "", "Header", "heading")
  f.name:SetTextColor(1, 0.82, 0)
  f.text = UI.Text(chat, "", "Read", "text", W - 60)
  f.text:SetTextColor(1, 1, 1)
  f.text:SetPoint("TOPLEFT", 16, -30)
  f.text:SetJustifyV("TOP")
  f.text:SetSpacing(3)

  f.next = UI.Button(chat, "Next", 96, 24)
  f.next:SetPoint("BOTTOMRIGHT", -10, 8)
  f.hint = UI.Text(chat, "", "Small", "subtle")
  f.hint:SetPoint("RIGHT", f.next, "LEFT", -10, 0)

  f.choices = {}
  for i = 1, CHOICES do
    local b = UI.Button(f, "", 380, 26)
    b:SetPoint("BOTTOM", chat, "TOP", 0, 6 + (CHOICES - i) * 30)
    b:Hide()
    f.choices[i] = b
  end

  f.close = UI.CloseButton(f, nil, 20)
  f.close:SetPoint("TOPRIGHT", -6, -6)
  f.close:SetScript("OnClick", function() C:Finish() end)

  -- Walking away ends a cutscene that asks you to stay close.
  f.elapsed = 0
  f:SetScript("OnUpdate", function(self, dt)
    self.elapsed = self.elapsed + dt
    if self.elapsed < 0.5 then return end
    self.elapsed = 0
    if (self.limit or 0) > 0 and self.startX then
      local y, x = UnitPosition("player")
      if K.Safe(x) and K.Safe(y) and math.sqrt((x - self.startX) ^ 2 + (y - self.startY) ^ 2) > self.limit then C:Finish() end
    end
  end)
  f:SetScript("OnHide", function(self)
    if self.playing then C:Finish(true) end
  end)
  UI:OnTheme(function(t)
    f.edge:SetColor(t.ui[1], t.ui[2], t.ui[3], 0.8)
    chat.edge:SetColor(t.ui[1], t.ui[2], t.ui[3], 0.5)
  end)
  C.frame = f
  return f
end

---------------------------------------------------------------------------
-- Playing
---------------------------------------------------------------------------
local ShowLine

local function Process(f, isNew)
  wipe(f.lines)
  local ds = Step(f.class, f.index) or EMPTY
  local args = f.args
  -- Who speaks, where, and what's on screen carry on until a step changes them.
  f.ND = ds.ND or f.ND or "NONE"
  f.NA = ds.NA or f.NA or "${trp:player:full}"
  f.BG = ds.BG or f.BG
  if type(ds.IM) == "table" then f.IM = ds.IM end
  f.LU = ds.LU or f.LU
  f.RU = ds.RU or f.RU

  f.name:ClearAllPoints()
  if f.ND == "LEFT" then
    f.name:SetPoint("TOPLEFT", 16, -9)
    f.name:SetText(K.Plain(S.Text(S.Parse(f.NA, args))))
  elseif f.ND == "RIGHT" then
    f.name:SetPoint("TOPRIGHT", -16, -9)
    f.name:SetText(K.Plain(S.Text(S.Parse(f.NA, args))))
  else
    f.name:SetText("")
  end

  if type(f.BG) == "string" and f.BG ~= "" then f.bg:SetTexture(f.BG); f.bg:Show() else f.bg:Hide() end
  local im = f.IM
  if type(im) == "table" and E.Str(im.UR) then
    f.image:SetTexture(E.Str(im.UR))
    f.image:SetTexCoord(E.Num(im.LE, 0), E.Num(im.RI, 1), E.Num(im.TO, 0), E.Num(im.BO, 1))
    f.image:SetSize(math.min(E.Num(im.WI, 256), W - 40), math.min(E.Num(im.HE, 256), H - CHAT_H - 30))
    f.image:Show()
  else
    f.image:Hide()
  end
  SetModel(f.left, f.LU)
  SetModel(f.right, f.RU)

  local text = E.Str(ds.TX)
  if text then
    text = text:gsub("\r\n", "\n")
    for line in (text .. "\n"):gmatch("(.-)\n") do f.lines[#f.lines + 1] = line end
    while #f.lines > 0 and f.lines[#f.lines] == "" do f.lines[#f.lines] = nil end
  end
  f.line = 1
  f.step = ds

  -- A step's workflow may start another cutscene; then this step stops here.
  local gen = f.gen
  if ds.WO ~= nil then Run(f, ds.WO) end
  if isNew or f.gen == gen then ShowLine(f) end
end

local function Choose(f, ch)
  local n = tonumber(ch.N) or ch.N
  if n and n ~= 0 and Step(f.class, n) then
    f.index = n
    Process(f)
  else
    C:Finish()
  end
end

function ShowLine(f)
  if not f.playing then return end
  local ds, args = f.step or EMPTY, f.args
  local text = S.Parse(f.lines[f.line] or "", args)
  -- Lines in <angle brackets> or *stars* are told, not said.
  local b = text:byte()
  if b == 60 or b == 42 then
    text = text:gsub("^<", "|cffff8040"):gsub(">$", "|r"):gsub("^%*", "|cffff8040"):gsub("%*$", "|r")
  end
  f.text:SetText(K.UI.Clean(S.Text(text)))
  for _, c in ipairs(f.choices) do c:Hide() end
  f.next:Enable()
  f.hint:SetText("")

  if f.lines[f.line + 1] then
    f.next:SetText("Next")
    f.next:SetScript("OnClick", function() f.line = f.line + 1; ShowLine(f) end)
  elseif type(ds.CH) == "table" then
    local i = 0
    for _, ch in ipairs(ds.CH) do
      if type(ch) == "table" and i < CHOICES and S:Check(ch.C, args) then
        i = i + 1
        local btn = f.choices[i]
        btn:SetText(K.Plain(S.Text(S.Parse(E.Str(ch.TX) or "", args))))
        btn:SetScript("OnClick", function() Choose(f, ch) end)
        btn:Show()
      end
    end
    -- Reposition the shown choices to sit just above the text.
    for j = 1, i do
      f.choices[j]:ClearAllPoints()
      f.choices[j]:SetPoint("BOTTOM", f.chat, "TOP", 0, 6 + (i - j) * 30)
    end
    if i > 0 then
      f.next:Disable()
      f.hint:SetText("Choose an answer.")
    else
      f.next:SetText("Close")
      f.next:SetScript("OnClick", function() C:Finish() end)
    end
  elseif E.Bool(ds.EP) then
    f.next:SetText("Close")
    f.next:SetScript("OnClick", function() C:Finish() end)
  else
    local n = tonumber(ds.N) or ds.N or ((tonumber(f.index) or 0) + 1)
    if Step(f.class, n) then
      f.next:SetText("Next")
      f.next:SetScript("OnClick", function() f.index = n; Process(f) end)
    else
      f.next:SetText("Close")
      f.next:SetScript("OnClick", function() C:Finish() end)
    end
  end
end

local function Start(class, classID, args)
  if not K:ExtOn("campaigns") then K:Print("Campaigns are switched off (Settings > Extended features).") return end
  local f = Build()
  if f.playing then C:Finish(true) end
  f.gen = (f.gen or 0) + 1
  f.class, f.classID, f.args = class, classID, args or {}
  f.index = E.Num(E.Path(class, "BA", "FS"), 1)
  f.limit = E.Num(E.Path(class, "BA", "DI"), 0)
  local y, x = UnitPosition("player")
  f.startX, f.startY = K.Safe(x) and x or nil, K.Safe(y) and y or nil
  f.ND, f.NA, f.BG, f.IM, f.LU, f.RU = nil, nil, nil, nil, nil, nil
  f.lines = f.lines or {}
  f.playing = true
  f:Show()
  f:Raise()
  if classID then Run(f, E.Path(class, "LI", "OS")) end
  if not f.playing then return end
  Process(f, true)
end

function C:Play(fullID, args)
  local class = E:Get(fullID)
  if not class or class.TY ~= "DI" then
    S.Note(args and args.classID or fullID, "nodialog:" .. tostring(fullID), ("it plays a cutscene that isn't in it (%s)."):format(tostring(fullID)))
    return
  end
  Start(class, fullID, args)
end

-- A single line: you and your target, the target speaking.
function C:Quick(text, args)
  Start({ TY = "DI", BA = {}, DS = { { TX = text, ND = "RIGHT", NA = "${trp:target:full}", LU = "player", RU = "target" } } }, nil, args)
end

function C:Finish(hidden)
  local f = self.frame
  if not f or not f.playing then return end
  f.playing = false
  if not hidden then f:Hide() end
  f.left:Hide()
  f.right:Hide()
  Run(f, E.Path(f.class, "LI", "OE"))
end

-- Stop without running anything (the campaign was paused).
function C:Stop()
  local f = self.frame
  if not f then return end
  f.playing = false
  f:Hide()
end

---------------------------------------------------------------------------
-- Documents: an Extended document's pages in Kinship's reader. Its "on
-- close" workflow runs when you put it down.
---------------------------------------------------------------------------
local open
function C:ShowDocument(fullID, args)
  local obj = E:Get(fullID)
  if not obj or obj.TY ~= "DO" then
    S.Note(args and args.classID or fullID, "nodoc:" .. tostring(fullID), ("it opens a document that isn't in it (%s)."):format(tostring(fullID)))
    return
  end
  local D = K.Documents
  if not (D and K:ExtOn("documents")) then K:Print("Documents are switched off (Settings > Extended features).") return end
  local pages = {}
  for _, p in ipairs(type(obj.PA) == "table" and obj.PA or EMPTY) do
    local text = type(p) == "table" and E.Str(p.TX) or nil
    if text then
      text = K.Plain(S.Text(S.Parse(text, args)))
      if #text > D.MAX_PAGE then text = text:sub(1, D.MAX_PAGE) end
      pages[#pages + 1] = text
    end
    if #pages >= D.MAX_PAGES then break end
  end
  if #pages == 0 then pages[1] = "" end
  local id = "ext#" .. fullID
  local doc = { id = id, title = E.Info(obj).name, pages = pages, style = "parchment",
                author = E.Str(E.Path(obj, "MD", "CB")) or "" }
  -- Lent to the reader only: it isn't kept among the documents you've read.
  K.db.docCache[id] = doc
  D:Open(id)
  K.db.docCache[id] = nil
  local reader = D.reader
  if not reader then return end
  open = { id = id, obj = obj, fullID = fullID, args = args }
  if not reader.kinshipExtHooked then
    reader.kinshipExtHooked = true
    reader:HookScript("OnHide", function(self)
      local o = open
      if not (o and self.doc and self.doc.id == o.id) then return end
      open = nil
      local oc = E.Path(o.obj, "LI", "OC")
      if oc ~= nil and type(o.obj.SC) == "table" then
        S:Run(oc, o.obj.SC, { object = Parent(o.args) }, o.fullID)
      end
    end)
  end
end

function C:CloseDocument()
  local reader = K.Documents and K.Documents.reader
  if reader and open and reader:IsShown() then reader:Hide() end
end
