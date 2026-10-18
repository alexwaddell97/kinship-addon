-- Kinship RP: profile links in chat.
-- Players can't send custom hyperlinks, so a link travels as plain text,
-- "[Kinship: Name]", and every Kinship user turns it into a clickable link
-- locally. Clicking opens that character's profile; hovering shows a short
-- card; shift-clicking puts the link into your own chat box.
-- The link type is "addon:KinshipRP:..." (|Haddon:KinshipRP:profile:Name|h),
-- named after the addon's folder: the client hands "addon" links to the
-- "SetItemRef" event, which is where clicks are caught (and through the
-- SetItemRef function too on clients that still call it).
-- This filter runs alongside Chat.lua's (it is added after it, and leaves
-- the rest of the message alone).

local ADDON, ns = ...
local K = ns.K
local UI = K.UI
local Safe = K.Safe
local L = {}
K.ChatLinks = L

local LINK = "addon:" .. ADDON .. ":profile:"
local OLD_LINK = "addon:kinship:profile:"   -- the older form, in chat lines from before
local FIND = "%[Kinship: ([^%]|\n]+)%]"
local LINK_HEX = "5fc4b8"

local CHANNELS = {
  "CHAT_MSG_SAY", "CHAT_MSG_YELL", "CHAT_MSG_EMOTE", "CHAT_MSG_PARTY", "CHAT_MSG_PARTY_LEADER",
  "CHAT_MSG_RAID", "CHAT_MSG_RAID_LEADER", "CHAT_MSG_RAID_WARNING", "CHAT_MSG_GUILD", "CHAT_MSG_OFFICER",
  "CHAT_MSG_WHISPER", "CHAT_MSG_WHISPER_INFORM", "CHAT_MSG_CHANNEL", "CHAT_MSG_INSTANCE_CHAT",
  "CHAT_MSG_INSTANCE_CHAT_LEADER", "CHAT_MSG_BN_WHISPER", "CHAT_MSG_BN_WHISPER_INFORM",
}

-- A character name from a token: no UI codes, a sensible length.
local function CleanName(n)
  n = strtrim((tostring(n or ""):gsub("|", ""):gsub("%c", "")))
  if #n < 2 or #n > 60 then return nil end
  return n
end

local Plain = K.Plain

function L.Token(name) return ("[Kinship: %s]"):format(name) end

-- What a link shows: their roleplay name if we have it.
local function Label(name)
  if K:IsMe(name) then return Plain(K:DisplayName()) end
  local reg = K:ProfileOf(name)
  local rp = reg and reg.profile and Plain(UI.Clean(reg.profile.rpName))
  if rp and rp ~= "" then return rp end
  return Ambiguate and Ambiguate(name, "none") or name
end

local function Format(raw)
  local name = CleanName(raw)
  if not name then return nil end
  return ("|T%s:0|t|cff%s|H%s%s|h[%s]|h|r"):format(K.ICON, LINK_HEX, LINK, name, Label(name))
end

local function Filter(_, _, msg, sender, ...)
  if not K.db or K.db.settings.chatLinks == false then return false end
  if not Safe(msg) or type(msg) ~= "string" or not msg:find("[Kinship:", 1, true) then return false end
  msg = msg:gsub(FIND, function(name) return Format(name) end)
  return false, msg, sender, ...
end

---------------------------------------------------------------------------
-- Putting a link in the chat box
---------------------------------------------------------------------------
local function ActiveEditBox()
  local get = (ChatFrameUtil and ChatFrameUtil.GetActiveWindow) or ChatEdit_GetActiveWindow
  if type(get) == "function" then
    local ok, eb = pcall(get)
    if ok and eb then return eb.chatFrame and eb.chatFrame.editBox or eb end
  end
end

L.ActiveEditBox = ActiveEditBox

function L:Insert(name)
  name = CleanName(name)
  if not name then return end
  local token = L.Token(name) .. " "
  local eb = ActiveEditBox()
  if eb and eb.Insert then eb:Insert(token) return end
  local open = (ChatFrameUtil and ChatFrameUtil.OpenChat) or ChatFrame_OpenChat
  if type(open) == "function" then pcall(open, token) end
end

-- Link your own profile.
function L:InsertMine() self:Insert(K:MyName()) end

---------------------------------------------------------------------------
-- Clicks and hovers
---------------------------------------------------------------------------
-- The name in one of our links, or nil when it's someone else's link.
local function LinkName(link)
  if type(link) ~= "string" or not Safe(link) then return nil end
  for _, prefix in ipairs({ LINK, OLD_LINK }) do
    if link:sub(1, #prefix) == prefix then return CleanName(link:sub(#prefix + 1)) end
  end
end

local lastLink, lastAt
local function OnLink(link)
  local name = LinkName(link)
  if not name then return end
  -- The same click can arrive by both routes: act on it once.
  if lastLink == link and lastAt and GetTime() - lastAt < 0.3 then return end
  lastLink, lastAt = link, GetTime()
  if IsShiftKeyDown() then
    -- Shift-click: share it on. The game may have dropped the raw hyperlink
    -- into the chat box; swap it for the plain token others can read.
    C_Timer.After(0, function()
      local eb = ActiveEditBox()
      if not eb then return L:Insert(name) end
      local text = eb:GetText() or ""
      local fixed, n = text:gsub("|T[^|]*|t", ""):gsub("|c%x%x%x%x%x%x%x%x|Haddon:[^|]*:profile:[^|]*|h.-|h|r", L.Token(name))
      if n > 0 then eb:SetText(fixed) else L:Insert(name) end
    end)
    return
  end
  if K:IsIgnored(name) then return end
  K:ViewProfile(name)
end

local function Hover(frame, link)
  local name = LinkName(link)
  if not name or K:IsIgnored(name) then return end
  GameTooltip:SetOwner(frame, "ANCHOR_CURSOR")
  GameTooltip:SetText(("|T%s:16|t %s"):format(K.ICON, Label(name)), 1, 0.82, 0)
  local isMe = K:IsMe(name)
  local reg = not isMe and K:ProfileOf(name)
  local p = isMe and K:Profile() or (reg and reg.profile)
  if p then
    local ep = Plain(UI.Clean(p.epithet))
    if ep ~= "" then GameTooltip:AddLine(ep, 0.37, 0.77, 0.72) end
    local who = strtrim(Plain(UI.Clean(p.race)) .. " " .. Plain(UI.Clean(p.class)))
    if who ~= "" then GameTooltip:AddLine(who, 0.8, 0.8, 0.8) end
    local s = K.STATUS[p.status or ""]
    if s then GameTooltip:AddLine(s.label, unpack(s.color)) end
    local cur = Plain(UI.Clean(p.currently))
    if cur ~= "" then GameTooltip:AddLine("\"" .. cur .. "\"", 0.85, 0.85, 0.85, true) end
  else
    GameTooltip:AddLine("Their profile hasn't arrived yet.", 0.7, 0.7, 0.7)
  end
  GameTooltip:AddLine(" ")
  GameTooltip:AddLine("Click to open the profile", 0.6, 0.6, 0.6)
  GameTooltip:Show()
  L.hovering = true
end

local function HookFrames()
  for i = 1, (NUM_CHAT_WINDOWS or 10) do
    local f = _G["ChatFrame" .. i]
    if f and not L.hooked[f] then
      L.hooked[f] = true
      f:HookScript("OnHyperlinkEnter", function(self, link) K.Try("chat links", Hover, self, link) end)
      f:HookScript("OnHyperlinkLeave", function() if L.hovering then L.hovering = false; GameTooltip:Hide() end end)
    end
  end
end

---------------------------------------------------------------------------
-- Start-up
---------------------------------------------------------------------------
L.hooked = {}
K:On("LOGIN", function()
  if K.db.settings.chatLinks == nil then K.db.settings.chatLinks = true end
  local util = type(ChatFrameUtil) == "table" and ChatFrameUtil or nil
  local add = (util and util.AddMessageEventFilter) or ChatFrame_AddMessageEventFilter
  if type(add) == "function" then
    for _, e in ipairs(CHANNELS) do pcall(add, e, Filter) end
  end
  -- Both routes a click can take (the same click arriving twice is ignored).
  if EventRegistry and EventRegistry.RegisterCallback then
    EventRegistry:RegisterCallback("SetItemRef", function(_, link) K.Try("chat links", OnLink, link) end, L)
  end
  if type(SetItemRef) == "function" then
    hooksecurefunc("SetItemRef", function(link) K.Try("chat links", OnLink, link) end)
  end
  K.Try("chat links", HookFrames)
end)

K:RegisterTargetButton({
  id = "chatlink", order = 60,
  icon = "Interface\\Icons\\INV_Misc_Note_02",
  label = "Link profile in chat",
  shown = function(unit, name) return name ~= nil or (unit and UnitIsPlayer(unit)) end,
  onClick = function(unit, name)
    if not name and unit and UnitExists(unit) then
      local n = GetUnitName(unit, true)
      if Safe(n) then name = n end
    end
    if name then L:Insert(name) end
  end,
})

K:RegisterSettings({ id = "chatlinks", title = "Profile links", order = 11, build = function(card)
  card:Toggle("Clickable profile and item links", "[Kinship: Name] and [Kinship item: Name] in chat become links.", "chatLinks")
  card:Note("Share a profile from the target bar, or shift-click a Kinship item while typing to link it. Everyone with "
    .. "Kinship sees a link; everyone else reads the plain text.")
  local b = card:Button("Link my profile in chat", function() L:InsertMine() end, 180)
  UI.Tooltip(b, "Link my profile", "Puts a link to your own profile in the chat box.")
end })
