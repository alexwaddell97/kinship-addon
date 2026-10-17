-- Kinship RP: Extended codecs. Import and export strings that Total RP 3:
-- Extended Tools reads and writes ("!" + LibDeflate's printable encoding of
-- deflated AceSerializer text), the older uncompressed strings, and the
-- message encoding Total RP 3 uses on its "TRP3.3" addon prefix (a 2-character
-- token, then deflated Chomp-serialised { modulePrefix, data } encoded for
-- chat channels). Nothing here registers a prefix or sends anything.
--   K.ExtCodec:Export(rootID [, obj])      -> string | nil, why
--   K.ExtCodec:Decode(text)                -> { version, id, object, display } | nil, why
--   K.ExtCodec:Import(text)                -> stored object, id, source | nil, why
--   K.ExtCodec:EncodeMessage(prefix, data [, token, logged]) -> payload | nil, why
--   K.ExtCodec:DecodeMessage(payload [, logged])             -> prefix, data, token | nil, why

local ADDON, ns = ...
local K = ns.K
local E = K.Ext
local C = {}
K.ExtCodec = C

local LibDeflate = LibStub and LibStub:GetLibrary("LibDeflate", true)
local AceSerializer = LibStub and LibStub:GetLibrary("AceSerializer-3.0", true)

C.MAX_INPUT = 600000     -- characters pasted (Tools refuses to export 500,000 or more)
C.MAX_EXPORT = 500000    -- Tools' own export limit
C.MAX_RAW = 4000000      -- characters once decompressed
C.MAX_MESSAGE = 2000000  -- characters of one TRP3.3 message, before decompressing

function C:Ready() return LibDeflate ~= nil and AceSerializer ~= nil end

---------------------------------------------------------------------------
-- Deflate: the game's own when it has it (what Total RP 3 uses), else
-- LibDeflate, which writes and reads the same raw DEFLATE stream.
---------------------------------------------------------------------------
local function Compress(s)
  if C_EncodingUtil and C_EncodingUtil.CompressString then
    local ok, out = pcall(C_EncodingUtil.CompressString, s)
    if ok and type(out) == "string" then return out end
  end
  if LibDeflate then
    local ok, out = pcall(LibDeflate.CompressDeflate, LibDeflate, s)
    if ok and type(out) == "string" then return out end
  end
end

local function Decompress(s)
  if C_EncodingUtil and C_EncodingUtil.DecompressString then
    local ok, out = pcall(C_EncodingUtil.DecompressString, s)
    if ok and type(out) == "string" then return out end
  end
  if LibDeflate then
    local ok, out = pcall(LibDeflate.DecompressDeflate, LibDeflate, s)
    if ok and type(out) == "string" then return out end
  end
end
C.Compress, C.Decompress = Compress, Decompress

---------------------------------------------------------------------------
-- Import and export strings
---------------------------------------------------------------------------
-- The string for one root, exactly as Tools writes it.
function C:Export(rootID, obj)
  if not self:Ready() then return nil, "The import and export libraries didn't load." end
  obj = obj or E:Get(rootID)
  if type(obj) ~= "table" then return nil, "There's nothing by that ID to export." end
  local ok, serial = pcall(AceSerializer.Serialize, AceSerializer, { E.VERSION, rootID, obj, E.DISPLAY_VERSION })
  if not ok or type(serial) ~= "string" then return nil, "It couldn't be written out." end
  serial = serial:gsub("|", "||")
  local packed = Compress(serial)
  if not packed then return nil, "It couldn't be compressed." end
  local out = "!" .. LibDeflate:EncodeForPrint(packed)
  if #out >= C.MAX_EXPORT then
    return nil, ("It's too large to export (%d KB; Total RP 3 stops at %d KB)."):format(math.floor(#out / 1024), C.MAX_EXPORT / 1000)
  end
  return out
end

-- Read a pasted string. Returns { version, id, object, display, compressed }
-- with the object already sanitised, or nil and a reason to show.
function C:Decode(text)
  if not self:Ready() then return nil, "The import and export libraries didn't load." end
  if type(text) ~= "string" then return nil, "Paste an export string first." end
  if #text > C.MAX_INPUT * 2 then return nil, "That's far too long to be an export string." end
  -- Neither encoding ever contains whitespace (AceSerializer escapes it),
  -- so line breaks from pasting are dropped.
  text = text:gsub("%s+", "")
  if text == "" then return nil, "Paste an export string first." end
  if #text > C.MAX_INPUT then return nil, "That's too long to be an export string." end

  local body, compressed = text:gsub("^!", "")
  local serial
  if compressed == 1 then
    local packed = LibDeflate:DecodeForPrint(body)
    if not packed then return nil, "That isn't a Total RP 3: Extended export string." end
    serial = Decompress(packed)
    if not serial then return nil, "That string is damaged (it wouldn't decompress)." end
  else
    serial = body
    if serial:sub(1, 2) ~= "^1" then return nil, "That isn't a Total RP 3: Extended export string." end
  end
  if #serial > C.MAX_RAW then return nil, "That object is too large to import." end
  serial = serial:gsub("||", "|")

  local ok, data = AceSerializer:Deserialize(serial)
  if not ok or type(data) ~= "table" or (#data ~= 3 and #data ~= 4) then
    return nil, "That string is damaged (it couldn't be read)."
  end
  local id, version, display = data[2], data[1], data[4]
  if type(id) == "number" then id = tostring(id) end
  if not E.ValidRootID(id) then
    return nil, type(id) == "string" and id:find(E.SEP, 1, true) and "That's part of another object, not a whole one."
      or "That string has no usable ID."
  end
  local obj, why = E.Sanitize(data[3])
  if not obj then return nil, "It can't be imported: " .. why .. "." end
  return {
    version = tonumber(version), id = id, object = obj,
    display = type(display) == "string" and display:sub(1, 20) or nil, compressed = compressed == 1,
  }
end

-- Warnings worth showing before an import goes ahead (none means none).
function C:Warnings(decoded)
  local out = {}
  if decoded.version and decoded.version ~= E.VERSION then
    out[#out + 1] = ("It was made with Extended %s; Kinship reads %s."):format(
      decoded.display or tostring(decoded.version), E.DISPLAY_VERSION)
  end
  local have = E:Get(decoded.id)
  local theirs = E.Num(E.Path(decoded.object, "MD", "V"), 0)
  if have then
    local mine = E.Num(E.Path(have, "MD", "V"), 0)
    if mine > theirs then
      out[#out + 1] = ("You already have a newer version (%d) than this one (%d)."):format(mine, theirs)
    else
      out[#out + 1] = "It replaces the copy you already have."
    end
  end
  local _, _, refused = E.ComputeSecurity(decoded.id, decoded.object)
  if next(refused) then
    out[#out + 1] = "It uses raw scripts or macros. Kinship keeps them but will never run them."
  end
  return out
end

-- Decode and store in one go.
function C:Import(text)
  local decoded, why = self:Decode(text)
  if not decoded then return nil, why end
  local obj, src = E:Store(decoded.id, decoded.object)
  if not obj then return nil, src end
  return obj, decoded.id, src
end

---------------------------------------------------------------------------
-- TRP3.3 messages (Phase 3 registers the prefix and routes module prefixes)
---------------------------------------------------------------------------
-- Tokens: two characters, base 74 from "0" (ASCII 48), 1 to 74*74-1.
local TOKEN_MOD, TOKEN_START = 74, 48
local nextToken = 1

function C.Token(n)
  n = math.floor(tonumber(n) or 1) % (TOKEN_MOD * TOKEN_MOD)
  return string.char(TOKEN_START + math.floor(n / TOKEN_MOD)) .. string.char(TOKEN_START + n % TOKEN_MOD)
end

function C.TokenNumber(token)
  if type(token) ~= "string" or #token ~= 2 then return nil end
  local a, b = token:byte(1) - TOKEN_START, token:byte(2) - TOKEN_START
  if a < 0 or a >= TOKEN_MOD or b < 0 or b >= TOKEN_MOD then return nil end
  return a * TOKEN_MOD + b
end

function C.NewToken()
  local t = C.Token(nextToken)
  nextToken = nextToken + 1
  if nextToken >= TOKEN_MOD * TOKEN_MOD then nextToken = 1 end
  return t
end

-- logged = sent on a "logged" channel (BNet relays): left uncompressed.
function C:EncodeMessage(modulePrefix, data, token, logged)
  local Chomp = AddOn_Chomp
  if not (Chomp and Chomp.Serialize and LibDeflate) then return nil, "Chomp or LibDeflate is missing." end
  if type(modulePrefix) ~= "string" then return nil, "No module prefix." end
  local ok, serial = pcall(Chomp.Serialize, { modulePrefix = modulePrefix, data = data })
  if not ok or type(serial) ~= "string" then return nil, "The message couldn't be written out." end
  if not logged then
    local packed = Compress(serial)
    if not packed then return nil, "The message couldn't be compressed." end
    serial = LibDeflate:EncodeForWoWChatChannel(packed)
  end
  return (token or C.NewToken()) .. serial
end

-- Returns modulePrefix, data (sanitised) and the token, or nil and a reason.
function C:DecodeMessage(payload, logged)
  local Chomp = AddOn_Chomp
  if not (Chomp and Chomp.Deserialize and LibDeflate) then return nil, "Chomp or LibDeflate is missing." end
  if type(payload) ~= "string" or #payload < 3 then return nil, "Empty message." end
  if #payload > C.MAX_MESSAGE then return nil, "Message too large." end
  local token, body = payload:sub(1, 2), payload:sub(3)
  if not logged then
    -- Total RP 3 falls back to the raw text when it isn't channel-encoded.
    local packed = LibDeflate:DecodeForWoWChatChannel(body) or body
    body = Decompress(packed)
    if not body then return nil, "Message wouldn't decompress." end
  end
  if #body > C.MAX_RAW then return nil, "Message too large." end
  local ok, msg = pcall(Chomp.Deserialize, body)
  if not ok or type(msg) ~= "table" or type(msg.modulePrefix) ~= "string" then return nil, "Message couldn't be read." end
  local data = msg.data
  if data ~= nil then
    local why
    data, why = E.SanitizeValue(data)
    if data == nil then return nil, "Message refused: " .. tostring(why) .. "." end
  end
  return msg.modulePrefix, data, token
end
