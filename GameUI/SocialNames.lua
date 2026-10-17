-- Kinship RP: roleplay names in the game's people lists.
-- Friends, the guild roster and /who show a character's roleplay name next
-- to theirs once their profile has arrived, in Kinship's teal:
--   Friends   the line under the name: "Aldric Vane · Elwynn Forest"
--   Guild     after the name: "Leeroy  Aldric Vane"
--   Who       after the name, the same way
-- Only text is changed, after the game (and EllesmereUI) have drawn the row;
-- rows are never moved or resized, and the lists' scroll boxes are left
-- alone. Friends and guildmates who are online and haven't been met yet are
-- asked for their profile, a few at a time.

local ADDON, ns = ...
local K = ns.K
local UI = K.UI
local Safe = K.Safe
local SN = { asked = {}, budget = 0, budgetAt = 0 }
K.SocialNames = SN

local HEX = "5fc4b8"
local SUFFIX = "  |cff" .. HEX
local ASK_PER_MINUTE = 12

local function On() return K.db and K.db.settings.listNames ~= false end

local function Plain(s)
  return strtrim((tostring(s or ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("|", "")))
end

-- Ask once a session for the profile of someone online we haven't met.
local function Ask(name)
  if SN.asked[name] or not (K.Comm and K.Comm.Request) then return end
  local now = GetTime()
  if now - SN.budgetAt > 60 then SN.budget, SN.budgetAt = 0, now end
  if SN.budget >= ASK_PER_MINUTE then return end
  SN.budget = SN.budget + 1
  SN.asked[name] = true
  K.Comm:Request(name)
end

-- Their roleplay name when it says more than the character name does.
function SN.RPName(name, online)
  if not Safe(name) or type(name) ~= "string" or name == "" or K:IsIgnored(name) then return nil end
  if K:IsMe(name) then
    local p = K:Profile()
    local rp = strtrim(p.rpName or "") ~= "" and Plain(K:DisplayName(p)) or ""
    return rp ~= "" and rp or nil
  end
  local reg = K:ProfileOf(name)
  local p = reg and reg.profile
  if not p then
    if online then Ask(name) end
    return nil
  end
  local rp = Plain(UI.Clean(p.rpName or ""))
  if rp == "" then return nil end
  local short = (Ambiguate and Ambiguate(name, "none") or name):lower()
  if rp:lower() == short then return nil end
  return rp
end

-- Text with any earlier roleplay name taken off.
local function Bare(text)
  text = tostring(text or "")
  local cut = text:find(SUFFIX, 1, true)
  if cut then text = text:sub(1, cut - 1) end
  return (text:gsub("^|cff" .. HEX .. "[^|]*|r  ·  ", ""))
end

local function Suffix(fs, rp)
  if not (fs and fs.GetText and fs.SetText) then return end
  local text = fs:GetText()
  if not Safe(text) or type(text) ~= "string" then return end
  local bare = Bare(text)
  local want = rp and (bare .. SUFFIX .. UI.Escape(rp) .. "|r") or bare
  if want ~= text then fs:SetText(want) end
end

local function Prefix(fs, rp)
  if not (fs and fs.GetText and fs.SetText) then return end
  local text = fs:GetText()
  if not Safe(text) or type(text) ~= "string" then return end
  local bare = Bare(text)
  local want = bare
  if rp then want = ("|cff%s%s|r%s"):format(HEX, UI.Escape(rp), bare ~= "" and ("  ·  " .. bare) or "") end
  if want ~= text then fs:SetText(want) end
end

---------------------------------------------------------------------------
-- Friends
---------------------------------------------------------------------------
local function FriendName(button)
  local id = button.id
  if not id then return nil end
  if button.buttonType == FRIENDS_BUTTON_TYPE_WOW and C_FriendList and C_FriendList.GetFriendInfoByIndex then
    local info = C_FriendList.GetFriendInfoByIndex(id)
    return info and info.name, info and info.connected
  elseif button.buttonType == FRIENDS_BUTTON_TYPE_BNET and C_BattleNet and C_BattleNet.GetFriendAccountInfo then
    local info = C_BattleNet.GetFriendAccountInfo(id)
    local g = info and info.gameAccountInfo
    if g and g.characterName and g.clientProgram == (BNET_CLIENT_WOW or "WoW") then
      local n = g.characterName
      if g.realmName and g.realmName ~= "" and g.realmName ~= GetRealmName() then n = n .. "-" .. g.realmName end
      return n, g.isOnline
    end
  end
end

local function FriendButton(button)
  local info = button.info or button.Info
  if not info then return end
  local name, online = FriendName(button)
  Prefix(info, On() and name and SN.RPName(name, online) or nil)
end

---------------------------------------------------------------------------
-- Guild roster (Communities window)
---------------------------------------------------------------------------
local function GuildRow(row)
  local nf = row.NameFrame
  local fs = nf and nf.Name
  local info = row.memberInfo or (row.GetMemberInfo and row:GetMemberInfo())
  if not fs or type(info) ~= "table" then return end
  local p = info.presence   -- online, away or busy (not offline or on the app)
  local online = p == 1 or p == 4 or p == 5
  Suffix(fs, On() and info.name and SN.RPName(info.name, online) or nil)
end

local function GuildList()
  local cf = rawget(_G, "CommunitiesFrame")
  local box = cf and cf.MemberList and cf.MemberList.ScrollBox
  if box and box.ForEachFrame then box:ForEachFrame(function(row) K.Try("guild names", GuildRow, row) end) end
end

---------------------------------------------------------------------------
-- Who
---------------------------------------------------------------------------
local function WhoInfo(row)
  local data = row.GetElementData and row:GetElementData()
  local index = type(data) == "number" and data or (type(data) == "table" and (data.index or data.whoIndex)) or row.index
  if type(data) == "table" and data.fullName then return data end
  if type(index) == "number" and C_FriendList and C_FriendList.GetWhoInfo then return C_FriendList.GetWhoInfo(index) end
end

-- The font string on a row showing this name (its fields differ between clients).
local function NameString(row, full)
  local short = Ambiguate and Ambiguate(full, "none") or full
  for _, key in ipairs({ "Name", "name", "NameText" }) do
    local fs = row[key]
    if type(fs) == "table" and fs.GetText then return fs end
  end
  for _, r in ipairs({ row:GetRegions() }) do
    if r.GetObjectType and r:GetObjectType() == "FontString" then
      local t = Bare(r:GetText())
      if Safe(t) and (t == full or t == short) then return r end
    end
  end
end

local function WhoRow(row)
  local info = WhoInfo(row)
  local full = info and info.fullName
  if type(full) ~= "string" then return end
  local fs = NameString(row, full)
  Suffix(fs, On() and SN.RPName(full, false) or nil)
end

local function WhoList()
  local wf = rawget(_G, "LFGWhoListFrame") or rawget(_G, "WhoFrame")
  local box = wf and (wf.ScrollBox or (wf.ListInset and wf.ListInset.ScrollBox))
  if box and box.ForEachFrame then box:ForEachFrame(function(row) K.Try("who names", WhoRow, row) end) end
  return box
end

---------------------------------------------------------------------------
-- Hooks
---------------------------------------------------------------------------
local function HookGuild()
  if SN.guildHooked then return end
  local cf = rawget(_G, "CommunitiesFrame")
  local ml = cf and cf.MemberList
  if not ml then return end
  SN.guildHooked = true
  if ml.RefreshListDisplay then
    hooksecurefunc(ml, "RefreshListDisplay", function() K.Try("guild names", GuildList) end)
  end
  if ml.ScrollBox and ml.ScrollBox.RegisterCallback and ScrollBoxListMixin then
    ml.ScrollBox:RegisterCallback(ScrollBoxListMixin.Event.OnDataRangeChanged,
      function() K.Try("guild names", GuildList) end, SN)
  end
end

local function HookWho()
  if SN.whoHooked then return end
  local box = WhoList()
  if not box then return end
  SN.whoHooked = true
  if box.RegisterCallback and ScrollBoxListMixin then
    box:RegisterCallback(ScrollBoxListMixin.Event.OnDataRangeChanged, function() K.Try("who names", WhoList) end, SN)
  end
  if box.Update then hooksecurefunc(box, "Update", function() K.Try("who names", WhoList) end) end
end

function SN:Refresh()
  -- Friends: re-label the rows showing (reading the list, never moving it)
  local fl = rawget(_G, "FriendsListFrame")
  local box = fl and fl:IsVisible() and fl.ScrollBox
  if box and box.ForEachFrame then box:ForEachFrame(function(b) K.Try("friend names", FriendButton, b) end) end
  K.Try("guild names", GuildList)
  K.Try("who names", WhoList)
end

local ev = CreateFrame("Frame")
ev:SetScript("OnEvent", function(_, event, name)
  if event == "ADDON_LOADED" and name == "Blizzard_Communities" then K.Try("guild names", HookGuild)
  elseif event == "WHO_LIST_UPDATE" then
    C_Timer.After(0, function() K.Try("who names", HookWho); K.Try("who names", WhoList) end)
  end
end)

K:On("LOGIN", function()
  if K.db.settings.listNames == nil then K.db.settings.listNames = true end
  if type(FriendsFrame_UpdateFriendButton) == "function" then
    hooksecurefunc("FriendsFrame_UpdateFriendButton", function(button) K.Try("friend names", FriendButton, button) end)
  end
  K.Try("guild names", HookGuild)
  K.Try("who names", HookWho)
  ev:RegisterEvent("ADDON_LOADED")
  pcall(ev.RegisterEvent, ev, "WHO_LIST_UPDATE")
  -- A profile arriving fills in the rows already showing
  local pending
  K:On("REGISTRY", function()
    if pending or not On() then return end
    pending = true
    C_Timer.After(1, function() pending = nil; SN:Refresh() end)
  end)
end)

K:RegisterSettings({ id = "listNames", title = "People lists", order = 42, build = function(card)
  card:Toggle("Roleplay names in friends, guild and who", "Their roleplay name shows beside their character's name once their profile has arrived.", {
    get = function() return On() end,
    set = function(v) K.db.settings.listNames = v; SN:Refresh() end,
  })
  card:Note("Friends and guildmates who are online are asked for their profile a few at a time, the same as hovering them would.")
end })
