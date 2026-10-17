-- Kinship RP: roleplay chat.
--   * Roleplay names in chat, for anyone whose profile has arrived: in
--     roleplay gold, with the character's name after it in grey. The name
--     stays a link to the character, so clicking it still whispers them.
--   * In emotes, "quoted speech" in the say colour
--   * In say, yell, party and the rest, *actions* and <actions> in the emote colour
--   * (( out-of-character asides )) dimmed
--   * NPC speech: an emote starting with "|| " becomes an NPC line, e.g.
--       /e || Town Guard says: Halt! Who goes there?
--       /e || The wind howls through the pass.
--   * Emotes starting with 's or , attach to your name ("Aldric's horse snorts.")

local ADDON, ns = ...
local K = ns.K
local UI = K.UI
local Safe = K.Safe
local Chat = {}
K.Chat = Chat

-- Roleplay chat only: never Trade, General or other numbered channels.
local CHANNELS = {
  "CHAT_MSG_SAY", "CHAT_MSG_YELL", "CHAT_MSG_EMOTE", "CHAT_MSG_PARTY", "CHAT_MSG_PARTY_LEADER",
  "CHAT_MSG_RAID", "CHAT_MSG_RAID_LEADER", "CHAT_MSG_RAID_WARNING", "CHAT_MSG_GUILD", "CHAT_MSG_OFFICER",
  "CHAT_MSG_WHISPER", "CHAT_MSG_WHISPER_INFORM",
}
local HANDLED = {}
for _, e in ipairs(CHANNELS) do HANDLED[e] = true end
local NPC_PREFIX = "|| "
local NPC_VERBS = { { "says:", "MONSTER_SAY" }, { "yells:", "MONSTER_YELL" }, { "whispers:", "MONSTER_WHISPER" },
                    { "asks:", "MONSTER_SAY" }, { "exclaims:", "MONSTER_SAY" } }

local function ColorOf(chatType, fallback)
  local info = ChatTypeInfo and ChatTypeInfo[chatType]
  if info and info.r then return UI.Hex({ info.r, info.g, info.b }) end
  return fallback
end

function Chat:Active() return K.db ~= nil end

---------------------------------------------------------------------------
-- Message text
---------------------------------------------------------------------------
local function Colorize(msg, isEmote)
  local s = K.db.settings
  if msg:find("|H", 1, true) or msg:find("|T", 1, true) then return msg end -- leave links and icons alone
  if s.chatEmotes then
    if isEmote then
      msg = msg:gsub('(".-")', "|cff" .. ColorOf("SAY", "ffffff") .. "%1|r")
    else
      local emote = "|cff" .. ColorOf("EMOTE", "ff8040")
      msg = msg:gsub("(%*.-%*)", emote .. "%1|r")
      msg = msg:gsub("(<.->)", emote .. "%1|r")
    end
  end
  if s.chatOOC then msg = msg:gsub("(%(%(.-%)%))", "|cff8c8c8c%1|r") end
  return msg
end

-- Per-line notes passed from the message filter to the name filter.
local npcName, attach, order = {}, {}, {}
local function Remember(map, id, value)
  map[id] = value
  order[#order + 1] = id
  if #order > 60 then
    local old = table.remove(order, 1)
    npcName[old], attach[old] = nil, nil
  end
end

local function HandleNPC(body, lineID)
  for _, v in ipairs(NPC_VERBS) do
    local who, rest = body:match("^(.-) " .. v[1]:gsub("%p", "%%%0") .. "%s*(.*)$")
    if who and who ~= "" then
      local hex = ColorOf(v[2], "fffa9f")
      Remember(npcName, lineID, ("|cff%s%s %s|r"):format(hex, who, v[1]))
      return ("|cff%s%s|r"):format(hex, rest)
    end
  end
  -- No speaker: pure narration, shown without anyone's name.
  Remember(npcName, lineID, "|cff" .. ColorOf("EMOTE", "ff8040") .. body .. "|r")
  return " "
end

local function MessageFilter(frame, event, msg, sender, ...)
  if not Chat:Active() or not Safe(msg) or type(msg) ~= "string" then return false end
  local lineID = select(9, ...)
  local s = K.db.settings
  local isEmote = event == "CHAT_MSG_EMOTE"
  -- NPC lines and 's / , need the name filter to rewrite the sender too.
  if isEmote and Chat.names and Safe(lineID) and lineID then
    if s.chatNPC and msg:sub(1, 3) == NPC_PREFIX then
      return false, HandleNPC(msg:sub(4), lineID), sender, ...
    elseif msg:sub(1, 3) == "'s " then
      Remember(attach, lineID, "'s"); msg = msg:sub(4)
    elseif msg:sub(1, 2) == ", " then
      Remember(attach, lineID, ","); msg = msg:sub(3)
    end
  end
  return false, Colorize(msg, isEmote), sender, ...
end

---------------------------------------------------------------------------
-- Names
---------------------------------------------------------------------------
-- A name as plain text: colours, links, textures and other UI codes are
-- removed whole (dropping only the "|" used to leave "cffff0000Name" behind).
-- A profile's own name colour is dropped: roleplay names are all roleplay gold.
local function CleanName(n)
  n = tostring(n or "")
  n = n:gsub("||", "")                               -- literal pipes
  n = n:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|cn[^:|]*:", ""):gsub("|r", "")
  n = n:gsub("|H.-|h(.-)|h", "%1"):gsub("|[TtAaKk].-|[tTaAkK]", ""):gsub("|n", " ")
  n = n:gsub("|", ""):gsub("%c", "")
  n = strtrim(n)
  if #n > 48 then n = n:sub(1, 48):gsub("[\192-\255][\128-\191]*$", "") end -- never half a letter
  return n
end

-- Returns the text to show for the sender, or nil for the game's default.
local function NameFilter(event, _, _, sender, _, _, _, _, _, _, _, _, lineID, guid)
  if not Chat:Active() or not HANDLED[event] then return nil end
  if Safe(lineID) and lineID and npcName[lineID] then return npcName[lineID] end
  local tail = Safe(lineID) and lineID and attach[lineID]
  if not K.db.settings.chatNames and not tail then return nil end
  if not Safe(sender) or type(sender) ~= "string" or sender == "" then return nil end

  local name
  if K.db.settings.chatNames then
    -- Your own lines use your own profile (it isn't among the ones received).
    local rp
    if K:IsMe(sender) then
      rp = K:Profile().rpName
    else
      local reg = K:ProfileOf(sender)
      rp = reg and reg.profile and reg.profile.rpName
      -- Someone talking whose profile hasn't come yet: ask for it (the same
      -- slow, one-at-a-time queue the nameplates use), so the next line has it.
      if not (reg and reg.profile) and K.Plates and not K:IsIgnored(sender) then K.Plates:Ask(sender) end
    end
    if type(rp) == "string" and rp ~= "" then
      rp = CleanName(rp)
      if rp ~= "" then name = K.BothNames(rp, Ambiguate and Ambiguate(sender, "none") or sender) end
    end
  end
  if name then return name .. (tail or "") end
  if not tail then return nil end
  name = Ambiguate and Ambiguate(sender, "short") or sender

  local class
  if Safe(guid) and type(guid) == "string" and guid ~= "" and GetPlayerInfoByGUID then
    local ok, _, c = pcall(GetPlayerInfoByGUID, guid)
    if ok and Safe(c) then class = c end
  end
  if class then name = "|cff" .. UI.Hex({ UI.ClassColor(class) }) .. name .. "|r" end
  return name .. (tail or "")
end

---------------------------------------------------------------------------
-- Start-up
---------------------------------------------------------------------------
K:On("LOGIN", function()
  if K:Compat() then return end   -- Total RP 3 styles chat while it runs
  local util = type(ChatFrameUtil) == "table" and ChatFrameUtil or nil
  local add = (util and util.AddMessageEventFilter) or ChatFrame_AddMessageEventFilter
  if type(add) == "function" then
    for _, e in ipairs(CHANNELS) do pcall(add, e, MessageFilter) end
  end
  if util and type(util.AddSenderNameFilter) == "function" then
    pcall(util.AddSenderNameFilter, NameFilter)
    Chat.names = true
  end
end)
