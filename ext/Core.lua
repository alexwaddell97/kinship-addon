-- Kinship RP: Extended objects. The object store (K.db.ext = { my, exchange,
-- security }), type codes, IDs and full-ID paths, a flat registry of inner
-- objects, the sanitiser every imported or received object passes through,
-- and security levels worked out here (never taken from the data).
-- Objects keep Total RP 3: Extended's own shapes (TY, MD, BA, IN, SC, LI ...),
-- described in docs/EXTENDED_FORMAT.md, so they go back out as they came in.
-- Read loose fields through the E.Bool / E.Num / E.Str helpers, and change
-- them with E.Write, which keeps the shape a field already has.

local ADDON, ns = ...
local K = ns.K
local E = { registry = {}, source = {} }
K.Ext = E

E.VERSION = 1062               -- Extended's data version (extended_version)
E.DISPLAY_VERSION = "2.3.6"    -- the Extended release that format matches
E.SEP = " "                    -- full IDs: "root inner inner"

-- Type codes, their labels and the module that plays them.
E.TYPES = {
  IT = { label = "Item",      plural = "Items",      module = "inventory", icon = "INV_Misc_Bag_08" },
  DO = { label = "Document",  plural = "Documents",  module = "documents", icon = "INV_Misc_Book_09" },
  CA = { label = "Campaign",  plural = "Campaigns",  module = "campaigns", icon = "INV_Scroll_03" },
  QU = { label = "Quest",     plural = "Quests",     module = "campaigns", icon = "INV_Scroll_03" },
  ST = { label = "Step",      plural = "Steps",      module = "campaigns", icon = "INV_Scroll_03" },
  DI = { label = "Cutscene",  plural = "Cutscenes",  module = "dialogues", icon = "INV_Misc_Note_01" },
  AU = { label = "Aura",      plural = "Auras",      module = "auras",     icon = "Spell_Holy_MagicalSentry" },
}
E.TYPE_ORDER = { "IT", "DO", "CA", "DI", "AU", "QU", "ST" }
E.MODES = { QU = "Quick", NO = "Normal", EX = "Expert" }
E.ELEMENTS = { list = true, branch = true, delay = true }

-- Containers of inner objects that Extended registers by full ID.
local CHILD_KEYS = { "IN", "QE", "ST" }

local EMPTY = {}

---------------------------------------------------------------------------
-- The store
---------------------------------------------------------------------------
function E:DB()
  local db = K.db and K.db.ext
  if type(db) ~= "table" then return nil end
  return db
end

local function EnsureDB()
  K.db.ext = type(K.db.ext) == "table" and K.db.ext or {}
  local db = K.db.ext
  db.my = type(db.my) == "table" and db.my or {}
  db.exchange = type(db.exchange) == "table" and db.exchange or {}
  local sec = type(db.security) == "table" and db.security or {}
  db.security = sec
  -- Per-creation and per-sender trust, plus the levels worked out here.
  for _, k in ipairs({ "global", "specific", "sender", "whitelist", "levels" }) do
    sec[k] = type(sec[k]) == "table" and sec[k] or {}
  end
  return db
end

---------------------------------------------------------------------------
-- IDs and full-ID paths
---------------------------------------------------------------------------
local ID_CHARS = "0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ"

-- A new root ID: month, day and time, then five random characters (15 in all).
function E:NewID()
  for _ = 1, 50 do
    local tail = {}
    for i = 1, 5 do
      local n = math.random(1, #ID_CHARS)
      tail[i] = ID_CHARS:sub(n, n)
    end
    local id = date("%m%d%H%M%S") .. table.concat(tail)
    if not self.registry[id] then return id end
  end
end

-- Child IDs (inner objects, quests, steps): lowercase, anything but letters,
-- digits and _ becomes _.
function E.ChildID(id)
  return (tostring(id or ""):lower():gsub("[^%w_]", "_"))
end

function E.FullID(...)
  local parts = {}
  for i = 1, select("#", ...) do
    local p = select(i, ...)
    if p ~= nil and p ~= "" then parts[#parts + 1] = tostring(p) end
  end
  return strtrim(table.concat(parts, E.SEP))
end

function E.Split(fullID)
  local out = {}
  for part in tostring(fullID or ""):gmatch("[^" .. E.SEP .. "]+") do out[#out + 1] = part end
  return out
end

function E.RootID(fullID)
  fullID = tostring(fullID or "")
  local at = fullID:find(E.SEP, 1, true)
  return at and fullID:sub(1, at - 1) or fullID
end

function E.Related(a, b) return E.RootID(a) == E.RootID(b) end

-- A root ID we'll store under: printable, no separator, sensibly short.
function E.ValidRootID(id)
  return type(id) == "string" and #id >= 1 and #id <= 64 and not id:find("[%s%c|]")
end

---------------------------------------------------------------------------
-- The flat registry: every root and inner object by full ID
---------------------------------------------------------------------------
local function Register(fullID, obj, source, depth)
  if type(obj) ~= "table" or depth > 16 then return 0 end
  E.registry[fullID] = obj
  E.source[fullID] = source
  local n = 1
  for _, key in ipairs(CHILD_KEYS) do
    local kids = obj[key]
    if type(kids) == "table" then
      for childID, child in pairs(kids) do
        -- Quests' ST are steps (objects); a workflow's ST lives under SC, never here.
        if type(child) == "table" and type(child.TY) == "string" then
          n = n + Register(E.FullID(fullID, childID), child, source, depth + 1)
        end
      end
    end
  end
  return n
end

local function Unregister(rootID)
  local prefix = rootID .. E.SEP
  for id in pairs(E.registry) do
    if id == rootID or id:sub(1, #prefix) == prefix then
      E.registry[id], E.source[id] = nil, nil
    end
  end
end

function E:Rebuild()
  wipe(self.registry)
  wipe(self.source)
  local db = self:DB()
  if not db then return end
  -- Received copies first, so your own creation wins when both exist.
  for _, src in ipairs({ "exchange", "my" }) do
    for id, obj in pairs(db[src]) do
      if E.ValidRootID(id) then Register(id, obj, src, 0) end
    end
  end
end

-- An object by full ID, or nil. Where it came from: "my" or "exchange".
function E:Get(fullID) return self.registry[fullID], self.source[fullID] end
function E:Exists(fullID) return self.registry[fullID] ~= nil end

-- Calls fn(fullID, obj) for a root and everything inside it.
function E.Walk(rootID, obj, fn, depth)
  depth = depth or 0
  if type(obj) ~= "table" or depth > 16 then return end
  fn(rootID, obj)
  for _, key in ipairs(CHILD_KEYS) do
    if type(obj[key]) == "table" then
      for childID, child in pairs(obj[key]) do
        if type(child) == "table" and type(child.TY) == "string" then
          E.Walk(E.FullID(rootID, childID), child, fn, depth + 1)
        end
      end
    end
  end
end

---------------------------------------------------------------------------
-- Normalise on read: Extended's fields are loosely typed (false for absent,
-- numbers as strings, booleans as 1/0). Read through these; never reshape.
---------------------------------------------------------------------------
function E.Bool(v) return v == true or v == 1 or v == "1" or v == "true" end

function E.Num(v, default)
  if type(v) == "number" then return v == v and v or default end   -- NaN is no number
  if type(v) == "string" then return tonumber(v) or default end
  return default
end

function E.Str(v, default)
  if type(v) == "string" then return v end
  if type(v) == "number" then return tostring(v) end
  return default
end

-- obj.a.b.c without tripping on missing tables: E.Path(obj, "BA", "NA").
function E.Path(t, ...)
  for i = 1, select("#", ...) do
    if type(t) ~= "table" then return nil end
    t = t[select(i, ...)]
  end
  return t
end

-- Write back the same shape: a field that held a string number stays a
-- string, one that held false goes back to false rather than nil, and so on.
function E.Write(t, key, value)
  local old = t[key]
  if value == nil and old == false then
    value = false
  elseif type(old) == "string" and type(value) == "number" then
    value = tostring(value)
  elseif type(old) == "number" and type(value) == "string" and tonumber(value) then
    value = tonumber(value)
  elseif type(old) == "boolean" and value == nil then
    value = false
  end
  t[key] = value
  return value
end

-- What the database view and tooltips show, read safely from any object.
function E.Info(obj)
  local ba = type(obj) == "table" and type(obj.BA) == "table" and obj.BA or EMPTY
  local md = type(obj) == "table" and type(obj.MD) == "table" and obj.MD or EMPTY
  local ty = type(obj) == "table" and E.Str(obj.TY) or nil
  local name = E.Str(ba.NA)
  if (not name or name == "") and ty == "ST" then name = "Step" end
  if (not name or name == "") and ty == "DO" and type(obj.PA) == "table" then name = "Untitled document" end
  local icon = E.Str(ba.IC) or (E.TYPES[ty] and E.TYPES[ty].icon) or "INV_Misc_QuestionMark"
  return {
    type = ty, known = E.TYPES[ty] ~= nil, name = name or "Unnamed",
    icon = icon, desc = E.Str(ba.DE) or E.Str(ba.TX) or "",
    quality = E.Num(ba.QA, 1), mode = E.Str(md.MO) or "NO",
    version = E.Num(md.V, 0), author = E.Str(md.CB), created = E.Str(md.CD),
    savedBy = E.Str(md.SB), saved = E.Str(md.SD), language = E.Str(md.LO),
    dataVersion = E.Num(md.tV),
  }
end

-- An icon from the data as a texture: a name ("INV_Letter_04"), a file ID
-- (number or digits) or a full path.
function E.IconTexture(icon)
  if type(icon) == "number" then return icon end
  if type(icon) ~= "string" or icon == "" then return "Interface\\Icons\\INV_Misc_QuestionMark" end
  if icon:match("^%d+$") then return tonumber(icon) end
  if icon:find("[\\/]") then return icon end
  return "Interface\\Icons\\" .. icon
end

-- Rows and columns of a container, from "5x4" or the SR / SC strings.
function E.ContainerSize(obj)
  local co = type(obj) == "table" and type(obj.CO) == "table" and obj.CO or EMPTY
  local r, c = E.Num(co.SR), E.Num(co.SC)
  if not (r and c) and type(co.SI) == "string" then
    local a, b = co.SI:match("^(%d+)x(%d+)$")
    r, c = tonumber(a), tonumber(b)
  end
  return r or 5, c or 4
end

---------------------------------------------------------------------------
-- The sanitiser. Everything imported or received is copied through here:
-- only tables, strings, finite numbers and booleans, with limits on depth,
-- count and size. Returns the clean copy, or nil and a reason.
---------------------------------------------------------------------------
E.LIMITS = {
  depth = 40,          -- nested tables
  nodes = 60000,       -- values in all
  stringLen = 65536,   -- characters in one string
  keyLen = 200,        -- characters in one string key
  bytes = 3000000,     -- characters in all strings together
}

local function Copy(v, depth, budget)
  local tv = type(v)
  if tv == "string" then
    if #v > E.LIMITS.stringLen then return nil, "a text is too long" end
    budget.bytes = budget.bytes + #v
    if budget.bytes > E.LIMITS.bytes then return nil, "it holds too much text" end
    return v
  elseif tv == "number" then
    if v ~= v or v == math.huge or v == -math.huge then return nil, "it holds a number that isn't one" end
    return v
  elseif tv == "boolean" then
    return v
  elseif tv ~= "table" then
    return nil, "it holds a " .. tv
  end
  if depth > E.LIMITS.depth then return nil, "it is nested too deeply" end
  local out = {}
  for k, val in pairs(v) do
    budget.nodes = budget.nodes + 1
    if budget.nodes > E.LIMITS.nodes then return nil, "it is too large" end
    local tk = type(k)
    if tk == "string" then
      if #k > E.LIMITS.keyLen then return nil, "a field name is too long" end
      budget.bytes = budget.bytes + #k
    elseif tk == "number" then
      if k ~= k or k == math.huge or k == -math.huge then return nil, "a field name isn't one" end
    else
      return nil, "a field name is a " .. tk
    end
    local copy, why = Copy(val, depth + 1, budget)
    if copy == nil then return nil, why end
    out[k] = copy
  end
  return out
end

-- Copy any value within the limits (for message payloads too).
function E.SanitizeValue(v)
  local copy, why = Copy(v, 0, { nodes = 0, bytes = 0 })
  if copy == nil then return nil, why or "it is empty" end
  return copy
end

-- A whole object: within the limits, a known type at the root, and with
-- Extended's internal flags removed. Security fields are recomputed by
-- E:Store, never kept from the data.
function E.Sanitize(obj)
  if type(obj) ~= "table" then return nil, "it isn't an Extended object" end
  local copy, why = E.SanitizeValue(obj)
  if not copy then return nil, why end
  if type(copy.TY) ~= "string" or not E.TYPES[copy.TY] then return nil, "it isn't an Extended object (no known type)" end
  if copy.MD ~= nil and type(copy.MD) ~= "table" then return nil, "its details are damaged" end
  copy.MD = copy.MD or {}
  copy.missing = nil
  return copy
end

---------------------------------------------------------------------------
-- Security, worked out here. Levels as Extended: 1 low (dangerous),
-- 2 medium, 3 high (safe). Unknown effects count as low, as in Extended.
-- Kinship refuses script and secure_macro outright, whoever made them.
---------------------------------------------------------------------------
E.SECURITY = { LOW = 1, MEDIUM = 2, HIGH = 3 }
E.REFUSED = { script = true, secure_macro = true }

-- Effects that need permission, and the group a permission covers.
E.SECURITY_GROUP = {
  script = "SEC_REASON_SCRIPT", secure_macro = "SEC_REASON_MACRO",
  speech_env = "SEC_REASON_TALK", speech_npc = "SEC_REASON_TALK", speech_player = "SEC_REASON_TALK",
  do_emote = "SEC_REASON_EMOTE",
  sound_id_local = "SEC_REASON_SOUND", sound_music_local = "SEC_REASON_SOUND",
  companion_dismiss_mount = "SEC_REASON_DISMOUNT", companion_summon_mount = "SEC_REASON_DISMOUNT",
}

E.EFFECT_LEVEL = {
  script = 1, secure_macro = 1, speech_env = 1, speech_npc = 1, speech_player = 1,
  do_emote = 2, sound_id_local = 2, sound_music_local = 2,
  companion_dismiss_mount = 2, companion_summon_mount = 2,
}
-- Every other effect Extended ships is safe.
for _, id in ipairs({
  "text", "var_object", "var_operand", "var_prompt", "signal_send", "run_workflow", "run_item_workflow",
  "sound_id_self", "sound_id_stop", "sound_music_self", "sound_music_stop",
  "sound_id_local_stop", "sound_music_local_stop", "companion_dismiss_critter", "companion_random_critter",
  "cam_zoom_in", "cam_zoom_out", "cam_save", "cam_load",
  "item_add", "item_remove", "item_consume", "item_cooldown", "item_bag_durability", "item_sheath",
  "item_use", "item_roll_dice", "item_loot", "document_show", "document_close", "dialog_start", "dialog_quick",
  "quest_start", "quest_goToStep", "quest_revealObjective", "quest_markObjDone",
  "aura_apply", "aura_remove", "aura_duration", "aura_var_set", "aura_run_workflow", "MISSING",
}) do E.EFFECT_LEVEL[id] = 3 end

-- Modules adding effects later (Phase 1 onward) declare their level here.
function E:SetEffectLevel(id, level) self.EFFECT_LEVEL[id] = level end
function E.EffectLevel(id) return E.EFFECT_LEVEL[id] or E.SECURITY.LOW end

-- Scan every workflow in a root and its inner objects. Returns the lowest
-- level, details = { group or effectID = { fullID, ... } } (Extended's
-- shape) and refused = { effectID = { fullID, ... } }.
function E.ComputeSecurity(rootID, obj)
  local level, details, refused = E.SECURITY.HIGH, {}, {}
  E.Walk(rootID, obj, function(fullID, o)
    if type(o.SC) ~= "table" then return end
    for _, wf in pairs(o.SC) do
      local steps = type(wf) == "table" and wf.ST
      if type(steps) == "table" then
        for _, step in pairs(steps) do
          if type(step) == "table" and step.t == "list" and type(step.e) == "table" then
            for _, eff in pairs(step.e) do
              local id = type(eff) == "table" and E.Str(eff.id) or "MISSING"
              local l = E.EffectLevel(id)
              if l < level then level = l end
              if l < E.SECURITY.HIGH then
                local key = E.SECURITY_GROUP[id] or id
                details[key] = details[key] or {}
                table.insert(details[key], fullID)
              end
              if E.REFUSED[id] then
                refused[id] = refused[id] or {}
                table.insert(refused[id], fullID)
              end
            end
          end
        end
      end
    end
  end)
  return level, details, refused
end

-- Recompute and record a root's security. The object carries the result in
-- Extended's own fields (items and campaigns, or wherever they already were),
-- so an export tells Total RP 3 users the truth.
function E:Secure(rootID, obj)
  local level, details, refused = E.ComputeSecurity(rootID, obj)
  local db = self:DB()
  if db then db.security.levels[rootID] = { level = level, refused = refused, t = time() } end
  if obj.TY == "IT" or obj.TY == "CA" or obj.securityLevel ~= nil or obj.details ~= nil then
    obj.securityLevel, obj.details = level, details
  end
  return level, details, refused
end

function E:Security(rootID)
  local db = self:DB()
  local rec = db and db.security.levels[E.RootID(rootID)]
  if rec then return rec.level, rec.refused end
  local obj = self.registry[E.RootID(rootID)]
  if obj then
    local level, _, refused = E.ComputeSecurity(E.RootID(rootID), obj)
    return level, refused
  end
  return E.SECURITY.LOW, {}
end

-- May this object run an effect that needs permission? Your own creations
-- may; refused effects never may; otherwise the sender must be trusted or
-- the group allowed (for everything, or for this object).
function E:Allowed(fullID, effectID)
  if self.REFUSED[effectID] then return false end
  if self.EffectLevel(effectID) >= self.SECURITY.HIGH then return true end
  local root = E.RootID(fullID)
  local db = self:DB()
  if not db then return false end
  if db.my[root] then return true end
  local sec = db.security
  local sender = sec.sender[root]
  if sender and sec.whitelist[sender] then return true end
  local group = self.SECURITY_GROUP[effectID] or effectID
  if sec.global[group] then return true end
  return type(sec.specific[root]) == "table" and sec.specific[root][group] == true
end

---------------------------------------------------------------------------
-- Storing and removing roots
---------------------------------------------------------------------------
local function IsMine(obj)
  local by = E.Path(obj, "MD", "CB")
  return type(by) == "string" and K.NameKey(by) ~= nil and K.NameKey(by) == K.NameKey(K:MyName())
end
E.IsMine = IsMine

-- Store a root: sanitised, filed under "my" when you made it (MD.CB is you)
-- or "exchange" otherwise, security recomputed, the sender remembered.
-- received = it came from another player (trade, link, stash): always
-- "exchange", whatever its MD.CB claims, so it can't pass as your own.
-- Returns the stored object and where it went, or nil and a reason.
function E:Store(rootID, obj, sender, received)
  if not E.ValidRootID(rootID) then return nil, "its ID is damaged" end
  local db = self:DB()
  if not db then return nil, "Kinship isn't ready yet" end
  local clean, why = E.Sanitize(obj)
  if not clean then return nil, why end
  local src = (not received and IsMine(clean)) and "my" or "exchange"
  self:Remove(rootID, true)
  db[src][rootID] = clean
  self:Secure(rootID, clean)
  local from = type(sender) == "string" and sender ~= "" and sender or E.Str(clean.MD.CB)
  if src == "exchange" and from then db.security.sender[rootID] = from end
  Register(rootID, clean, src, 0)
  K:Fire("EXT_DB", rootID)
  return clean, src
end

function E:Remove(rootID, quiet)
  local db = self:DB()
  if not db then return end
  local had = db.my[rootID] ~= nil or db.exchange[rootID] ~= nil
  db.my[rootID], db.exchange[rootID] = nil, nil
  db.security.levels[rootID] = nil
  db.security.sender[rootID] = nil
  db.security.specific[rootID] = nil
  Unregister(rootID)
  if had and not quiet then K:Fire("EXT_DB", rootID) end
  return had
end

-- Roots for a list: { id, obj, source, info, count } sorted by name.
-- source: "my", "exchange" or nil for both.
function E:List(source)
  local db, out = self:DB(), {}
  if not db then return out end
  for _, src in ipairs({ "my", "exchange" }) do
    if source == nil or source == src then
      for id, obj in pairs(db[src]) do
        if type(obj) == "table" and E.ValidRootID(id) then
          local n = 0
          E.Walk(id, obj, function() n = n + 1 end)
          out[#out + 1] = { id = id, obj = obj, source = src, info = E.Info(obj), count = n - 1 }
        end
      end
    end
  end
  table.sort(out, function(a, b)
    local an, bn = a.info.name:lower(), b.info.name:lower()
    if an ~= bn then return an < bn end
    return a.id < b.id
  end)
  return out
end

-- Inner objects of a root, for the detail view: { { id = fullID, info, depth } }.
function E:Children(rootID)
  local root = self.registry[rootID]
  local out = {}
  if not root then return out end
  E.Walk(rootID, root, function(fullID, obj)
    if fullID ~= rootID then
      local _, depth = fullID:gsub(E.SEP, "")
      out[#out + 1] = { id = fullID, info = E.Info(obj), depth = depth }
    end
  end)
  table.sort(out, function(a, b) return a.id < b.id end)
  return out
end

-- Extended's "missing" placeholder, for IDs that resolve to nothing.
E.MISSING = { missing = true, TY = "IT", BA = { IC = "INV_Misc_QuestionMark", NA = "Missing object",
  DE = "Its details never reached you, or it was removed." } }
function E:GetOrMissing(fullID) return self.registry[fullID] or self.MISSING end

K:On("LOGIN", function()
  EnsureDB()
  E:Rebuild()
end)
