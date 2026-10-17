-- Kinship RP: item links in chat.
-- Like a real item link: shift-click a Kinship item (in your bags, the
-- satchel or the Workshop) while typing and "[Kinship item: Silver Locket]"
-- goes into the chat box. Everyone with Kinship sees it as a link in the
-- item's quality colour; hovering shows the item, clicking pins it like the
-- game's own item links, shift-clicking passes it on. Everyone else reads the
-- plain words.
-- The words carry no details, so the first time you hover someone's link your
-- client asks them for it by addon whisper (itemAsk / itemTell) and keeps the
-- answer, exactly as a design arrives with a traded item.

local ADDON, ns = ...
local K = ns.K
local UI = K.UI
local Safe = K.Safe
local I = K.Items
local IL = { asked = {}, hooked = {} }
K.ItemLinks = IL
K.Net:Gate({ "itemAsk", "itemTell" }, "inventory")

local LINK = "addon:" .. ADDON .. ":item:"
local FIND = "%[Kinship item: ([^%]|\n]+)%]"
local UNKNOWN_HEX = "5fc4b8"
local ASK_AGAIN = 30          -- seconds before asking the same person again
local KEEP_LINKED = 40        -- your most recent links remembered by name

local CHANNELS = {
  "CHAT_MSG_SAY", "CHAT_MSG_YELL", "CHAT_MSG_EMOTE", "CHAT_MSG_PARTY", "CHAT_MSG_PARTY_LEADER",
  "CHAT_MSG_RAID", "CHAT_MSG_RAID_LEADER", "CHAT_MSG_RAID_WARNING", "CHAT_MSG_GUILD", "CHAT_MSG_OFFICER",
  "CHAT_MSG_WHISPER", "CHAT_MSG_WHISPER_INFORM", "CHAT_MSG_CHANNEL", "CHAT_MSG_INSTANCE_CHAT",
  "CHAT_MSG_INSTANCE_CHAT_LEADER",
}

local function On() return K.db and K.db.settings.chatLinks ~= false and K:ExtOn("inventory") end

-- An item name as it can travel in a token: no brackets, codes or line breaks.
local function CleanName(n)
  n = strtrim((tostring(n or ""):gsub("|", ""):gsub("[%[%]:]", ""):gsub("%c", "")))
  if n == "" or #n > 60 then return nil end
  return n
end

local function Key(name) return (CleanName(name) or ""):lower() end

function IL.Token(name) return ("[Kinship item: %s]"):format(CleanName(name) or "?") end

---------------------------------------------------------------------------
-- Knowing which item a link means
---------------------------------------------------------------------------
-- Your recent links by name, so a question about one is answered with the
-- very item you linked even when two of yours share a name.
local function Linked()
  local key = K:CharKey()
  K.db.itemLinksOut = K.db.itemLinksOut or {}
  local box = K.db.itemLinksOut[key]
  if type(box) ~= "table" then box = {}; K.db.itemLinksOut[key] = box end
  return box
end

-- What others' links turned out to be: "sender\001name" -> item id.
local function Seen()
  K.db.itemLinksSeen = K.db.itemLinksSeen or {}
  return K.db.itemLinksSeen
end

local function ByName(list, key)
  for _, def in pairs(list or {}) do
    if type(def) == "table" and Key(def.name) == key then return def end
  end
end

-- One of yours by name: a link you made, a design, something in your bags,
-- then anything you've come to know (passing on someone else's link).
function IL:Mine(name)
  local key = Key(name)
  if key == "" then return nil end
  local id = Linked()[key]
  local def = id and I:Get(id.id)
  if def then return def end
  def = ByName(K.db.itemDefs, key)
  if def then return def end
  for _, slot in pairs(I:Bag()) do
    local d = slot and I:Get(slot.def)
    if d and Key(d.name) == key then return d end
  end
  return ByName(K.db.itemCache, key)
end

function IL:Resolve(sender, name)
  if not sender or K:IsMe(sender) then return self:Mine(name) end
  local id = Seen()[sender .. "\001" .. Key(name)]
  return id and I:Get(id) or nil
end

---------------------------------------------------------------------------
-- Making a link
---------------------------------------------------------------------------
local function ActiveEditBox()
  return K.ChatLinks and K.ChatLinks.ActiveEditBox and K.ChatLinks.ActiveEditBox()
end

-- Shift-click on an item: if you're typing, link it and return true (the
-- click is then used up, as with the game's own items).
function IL:TryLink(item)
  if not On() or not IsShiftKeyDown() then return false end
  local def = type(item) == "table" and item or I:Get(item)
  local eb = ActiveEditBox()
  if not (def and eb and eb.Insert) then return false end
  local name = CleanName(def.name)
  if not name then return false end
  local box = Linked()
  box[name:lower()] = { id = def.id, t = time() }
  -- Keep only the most recent few
  local n, oldest, oldKey = 0, math.huge, nil
  for k, v in pairs(box) do
    n = n + 1
    if (v.t or 0) < oldest then oldest, oldKey = v.t or 0, k end
  end
  if n > KEEP_LINKED and oldKey then box[oldKey] = nil end
  eb:Insert(IL.Token(name))
  return true
end

---------------------------------------------------------------------------
-- Asking for an item you haven't seen
---------------------------------------------------------------------------
function IL:Ask(sender, name)
  local k = sender .. "\001" .. Key(name)
  local at = self.asked[k]
  if at and GetTime() - at < ASK_AGAIN then return at end
  self.asked[k] = GetTime()
  K.Net:Send("itemAsk", { name = CleanName(name) }, "WHISPER", sender)
  return self.asked[k]
end

K.Net:On("itemAsk", function(msg, sender)
  if not On() or type(msg.name) ~= "string" then return end
  local def = IL:Mine(msg.name)
  K.Net:Send("itemTell", { name = CleanName(msg.name), d = def and I:Pack(def.id) or nil }, "WHISPER", sender)
end)

K.Net:On("itemTell", function(msg, sender)
  if not On() or type(msg.name) ~= "string" then return end
  local k = sender .. "\001" .. Key(msg.name)
  IL.asked[k] = nil
  local def = msg.d and I:Learn(msg.d)
  if def then Seen()[k] = def.id else IL.missing = IL.missing or {}; IL.missing[k] = true end
  IL:Repaint(sender, msg.name)
end)

---------------------------------------------------------------------------
-- In chat
---------------------------------------------------------------------------
local function Format(name, sender)
  name = CleanName(name)
  if not name or not sender then return nil end
  local def = IL:Resolve(sender, name)
  local hex = def and UI.Hex(I.Quality(def.quality).color) or UNKNOWN_HEX
  return ("|cff%s|H%s%s:%s|h[%s]|h|r"):format(hex, LINK, sender, name, name)
end

local function Filter(_, event, msg, sender, ...)
  if not On() then return false end
  if not Safe(msg) or type(msg) ~= "string" or not msg:find("[Kinship item:", 1, true) then return false end
  if not Safe(sender) or type(sender) ~= "string" then return false end
  -- A whisper you sent names who it went to; the item is yours
  local owner = event == "CHAT_MSG_WHISPER_INFORM" and K:MyName() or sender
  msg = msg:gsub(FIND, function(name) return Format(name, owner) end)
  return false, msg, sender, ...
end

-- sender, name from one of our links, or nil when it's someone else's link.
local function Parse(link)
  if type(link) ~= "string" or not Safe(link) or link:sub(1, #LINK) ~= LINK then return nil end
  local sender, name = link:sub(#LINK + 1):match("^([^:]+):(.+)$")
  if sender and CleanName(name) then return sender, CleanName(name) end
end

local function Fill(tt, sender, name)
  local def = IL:Resolve(sender, name)
  if def then
    I:FillTooltip(tt, def)
    return
  end
  tt:SetText(name, 0.37, 0.77, 0.72)
  local k = sender .. "\001" .. Key(name)
  if IL.missing and IL.missing[k] then
    tt:AddLine(I.Short(sender) .. " no longer has this item.", 0.62, 0.62, 0.62, true)
  elseif not K.Net:Ready() then
    tt:AddLine("Its details haven't reached you.", 0.62, 0.62, 0.62, true)
  else
    local at = IL:Ask(sender, name)
    tt:AddLine(GetTime() - at < 8 and ("Asking " .. I.Short(sender) .. " about it…")
      or (I.Short(sender) .. " hasn't answered. They may be away."), 0.62, 0.62, 0.62, true)
  end
end

-- An answer arrived: redraw whichever tooltip is showing that link.
function IL:Repaint(sender, name)
  local k = sender .. "\001" .. Key(name)
  if self.hover and self.hover.k == k and GameTooltip:IsOwned(self.hover.frame) then
    GameTooltip:ClearLines()
    Fill(GameTooltip, sender, name)
    GameTooltip:Show()
  end
  if self.pinned == k and ItemRefTooltip and ItemRefTooltip:IsShown() then
    ItemRefTooltip:ClearLines()
    Fill(ItemRefTooltip, sender, name)
    ItemRefTooltip:Show()
  end
end

local function Hover(frame, link)
  local sender, name = Parse(link)
  if not sender or K:IsIgnored(sender) then return end
  GameTooltip:SetOwner(frame, "ANCHOR_CURSOR")
  Fill(GameTooltip, sender, name)
  GameTooltip:Show()
  IL.hover = { k = sender .. "\001" .. Key(name), frame = frame }
end

local lastLink, lastAt
local function OnLink(link)
  local sender, name = Parse(link)
  if not sender then return end
  if lastLink == link and lastAt and GetTime() - lastAt < 0.3 then return end
  lastLink, lastAt = link, GetTime()
  if IsShiftKeyDown() then
    -- Pass it on: swap any raw hyperlink the game dropped in for the plain words.
    C_Timer.After(0, function()
      local eb = ActiveEditBox()
      if not eb then return end
      local text = eb:GetText() or ""
      local fixed, n = text:gsub("|c%x%x%x%x%x%x%x%x|Haddon:[^|]*:item:[^|]*|h.-|h|r", IL.Token(name))
      if n > 0 then eb:SetText(fixed) else eb:Insert(IL.Token(name)) end
      local def = IL:Resolve(sender, name)
      if def then Linked()[Key(name)] = { id = def.id, t = time() } end
    end)
    return
  end
  if K:IsIgnored(sender) or not ItemRefTooltip then return end
  local k = sender .. "\001" .. Key(name)
  if IL.pinned == k and ItemRefTooltip:IsShown() then ItemRefTooltip:Hide() return end
  ShowUIPanel(ItemRefTooltip)
  if not ItemRefTooltip:IsShown() then ItemRefTooltip:SetOwner(UIParent, "ANCHOR_PRESERVE") end
  ItemRefTooltip:ClearLines()
  Fill(ItemRefTooltip, sender, name)
  ItemRefTooltip:Show()
  IL.pinned = k
end

local function HookFrames()
  for i = 1, (NUM_CHAT_WINDOWS or 10) do
    local f = _G["ChatFrame" .. i]
    if f and not IL.hooked[f] then
      IL.hooked[f] = true
      f:HookScript("OnHyperlinkEnter", function(self, link) K.Try("item links", Hover, self, link) end)
      f:HookScript("OnHyperlinkLeave", function()
        if IL.hover then IL.hover = nil; GameTooltip:Hide() end
      end)
    end
  end
end

K:On("LOGIN", function()
  -- Others' links are only remembered to save asking again; let a big pile go
  local n = 0
  for _ in pairs(Seen()) do n = n + 1 end
  if n > 400 then K.db.itemLinksSeen = {} end
  local util = type(ChatFrameUtil) == "table" and ChatFrameUtil or nil
  local add = (util and util.AddMessageEventFilter) or ChatFrame_AddMessageEventFilter
  if type(add) == "function" then
    for _, e in ipairs(CHANNELS) do pcall(add, e, Filter) end
  end
  if EventRegistry and EventRegistry.RegisterCallback then
    EventRegistry:RegisterCallback("SetItemRef", function(_, link) K.Try("item links", OnLink, link) end, IL)
  end
  if type(SetItemRef) == "function" then
    hooksecurefunc("SetItemRef", function(link) K.Try("item links", OnLink, link) end)
  end
  K.Try("item links", HookFrames)
end)
