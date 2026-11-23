-- Kinship RP: Extended scripts. Runs Total RP 3: Extended workflows (effect
-- lists, branches and delays), conditions and operands with a small
-- interpreter of its own: nothing is ever compiled, raw scripts and macros
-- never run, and effects that need permission go through K.Ext:Allowed, so a
-- campaign someone sent you can't speak or emote for you unless you let it.
--   S:Run(scriptID, scripts, args, fullID)  run the workflow SC[scriptID]
--   S:Check(cond, args)                     a condition, true or false
--   S.Parse(text, args)                     text with its ${...} filled in
--   S.Text(text)                            Total RP 3 tags as game text
--   S.effects[id] = fn(a, args, allowed)    S.operands[id] = fn(a, args)
-- args as Extended: { object = campaign log, event = payload, custom = {},
-- scripts = SC, classID = full ID, LAST = what the last effect returned }.

local _, ns = ...
local K = ns.K
local E = K.Ext
local S = { effects = {}, operands = {}, notes = {} }
K.ExtScript = S

local EMPTY = {}
local MAX_STEPS = 500    -- elements one run may pass through (workflows can loop)
local MAX_DEPTH = 16     -- workflows starting workflows
local depth = 0

local function P() return K.ExtCampaign end
local function ActiveLog() return P() and P():ActiveLog() end

local function Safe(v) return K.Safe(v) and v or nil end

-- Say something once per creation and session: what it uses that Kinship
-- can't do yet, or what it tried that Kinship won't do.
function S.Note(fullID, key, text)
  local root = E.RootID(fullID or "?")
  local k = root .. "\001" .. key
  if S.notes[k] then return end
  S.notes[k] = true
  local obj = E:Get(root)
  local name = obj and E.Info(obj).name or root
  K:Print(("%s: %s"):format(K.UI.Escape(K.Plain(name)), text))
end

---------------------------------------------------------------------------
-- Text
---------------------------------------------------------------------------
-- Total RP 3's formatting tags as plain game text: colours kept, the rest
-- (headings, alignment, icons, images) reduced to their words.
function S.Text(text)
  if type(text) ~= "string" then return "" end
  text = text:gsub("{col:(%x%x%x%x%x%x)}", "|cff%1"):gsub("{/col}", "|r")
  text = text:gsub("{link%*[^*]*%*([^}]*)}", "%1")
  text = text:gsub("{twitter%*[^*]*%*([^}]*)}", "%1")
  text = text:gsub("{icon:[^}]*}", ""):gsub("{img:[^}]*}", "")
  text = text:gsub("{/?[hp]%d?[^}]*}", ""):gsub("{/?[ib]}", "")
  return text
end

-- A number as Extended shows it: at most `decimals` places, no trailing zeros.
local function Short(v, decimals)
  local n = tonumber(v)
  if type(v) ~= "number" or not n or n == math.floor(n) then return tostring(v) end
  local s = ("%." .. (decimals or 2) .. "f"):format(n)
  s = s:gsub("0+$", ""):gsub("%.$", "")
  return s
end

local function NoTarget() return rawget(_G, "SPELL_FAILED_BAD_IMPLICIT_TARGETS") or "No target" end
local function Unknown() return rawget(_G, "UNKNOWN") or "Unknown" end

-- "Name-Realm", as Total RP 3 names players. Forever names may hold a "-" of
-- their own, so the realm is only added, never looked for.
local function UnitID(unit)
  if not UnitExists(unit) then return nil end
  local name, realm = UnitName(unit)
  name, realm = Safe(name), Safe(realm)
  if not name then return nil end
  if not realm or realm == "" then realm = GetNormalizedRealmName and Safe(GetNormalizedRealmName()) end
  return realm and realm ~= "" and (name .. "-" .. realm) or name
end
S.UnitID = UnitID

local function ProfileOfUnit(unit)
  if not (UnitExists(unit) and UnitIsPlayer(unit)) then return nil end
  if UnitIsUnit(unit, "player") then return K:Profile() end
  local name = Safe(GetUnitName(unit, true))
  return name and K.ProfileOf and K:ProfileOf(name) or nil
end

-- The name a unit goes by: a campaign's name for an NPC, a roleplay name for
-- a player, else the game's.
local function FullName(unit)
  if UnitIsUnit(unit, "player") then return K.Plain(K:DisplayName()) end
  if not UnitExists(unit) then return nil end
  local npc = P() and P():NPC(unit)
  if npc and npc.name then return npc.name end
  local p = ProfileOfUnit(unit)
  local shown = p and K:ShownName(p, Safe(GetUnitName(unit, false)))
  return shown or Safe(GetUnitName(unit, false))
end

local function NamePart(unit, which)
  local full
  if UnitIsUnit(unit, "player") then
    local p = K:Profile()
    full = K.Plain(p.rpName or "") ~= "" and K.Plain(p.rpName) or K:CharacterName()
  else
    local p = ProfileOfUnit(unit)
    full = p and K.Plain(p.rpName or "") ~= "" and K.Plain(p.rpName) or Safe(GetUnitName(unit, false))
  end
  if not full then return nil end
  local first, last = K.SplitName(full)
  if which == "first" then return first end
  return last or first
end

local function Field(unit, field, fallback)
  local p = ProfileOfUnit(unit)
  local v = p and K.Plain(p[field] or "")
  if v and v ~= "" then return v end
  return fallback
end

local REPLACE = {
  ["wow:player"] = function() return Safe(UnitName("player")) or Unknown() end,
  ["wow:target"] = function() return Safe(GetUnitName("target", false)) or NoTarget() end,
  ["wow:player:id"] = function() return UnitID("player") or "" end,
  ["wow:target:id"] = function() return UnitID("target") or NoTarget() end,
  ["wow:player:race"] = function() return Safe(UnitRace("player")) or Unknown() end,
  ["wow:target:race"] = function() return Safe(UnitRace("target")) or NoTarget() end,
  ["wow:player:class"] = function() return Safe(UnitClass("player")) or Unknown() end,
  ["wow:target:class"] = function() return Safe(UnitClass("target")) or NoTarget() end,
  ["trp:player:full"] = function() return FullName("player") or "" end,
  ["trp:target:full"] = function() return FullName("target") or NoTarget() end,
  ["trp:player:first"] = function() return NamePart("player", "first") or "" end,
  ["trp:player:last"] = function() return NamePart("player", "last") or "" end,
  ["trp:target:first"] = function() return NamePart("target", "first") or NoTarget() end,
  ["trp:target:last"] = function() return NamePart("target", "last") or NoTarget() end,
  ["trp:player:class"] = function() return Field("player", "class", Safe(UnitClass("player")) or Unknown()) end,
  ["trp:player:race"] = function() return Field("player", "race", Safe(UnitRace("player")) or Unknown()) end,
  ["trp:target:class"] = function() return Field("target", "class", Safe(UnitClass("target")) or NoTarget()) end,
  ["trp:target:race"] = function() return Field("target", "race", Safe(UnitRace("target")) or NoTarget()) end,
  ["last.return"] = function(args) return args and args.LAST ~= nil and tostring(args.LAST) or "" end,
}

-- Fill in ${name}, ${name::default} and ${name#decimals}: unit names, event
-- values, then workflow, object and campaign variables.
function S.Parse(text, args)
  if text == nil then return nil end
  args = args or EMPTY
  text = tostring(text)
  return (text:gsub("%$%{(.-)%}", function(capture)
    local default
    local at = capture:find("::", 1, true)
    if at then default = capture:sub(at + 2); capture = capture:sub(1, at - 1) end
    local decimals = 2
    local hash = capture:find("#", 1, true)
    if hash then decimals = tonumber(capture:sub(hash + 1)) or 2; capture = capture:sub(1, hash - 1) end
    if REPLACE[capture] then
      local ok, v = pcall(REPLACE[capture], args)
      return ok and tostring(v or "") or ""
    end
    local unit, male, female = capture:match("^gender:(%w+):([^:]+):([^:]+)$")
    if unit then
      local sex = UnitExists(unit) and Safe(UnitSex(unit))
      if sex == 2 then return male elseif sex == 3 then return female end
      return Unknown()
    end
    local index = capture:match("^event%.(%d+)$")
    if index then
      local v = (args.event or EMPTY)[tonumber(index)]
      if v == nil then return capture end
      return Short(v, decimals)
    end
    local v = (args.custom or EMPTY)[capture]
    if v == nil then v = (type(args.object) == "table" and args.object.vars or EMPTY)[capture] end
    if v == nil then v = ((ActiveLog() or EMPTY).vars or EMPTY)[capture] end
    if v ~= nil then return Short(v, decimals) end
    local obj = E:Get(capture)
    if obj then return "[" .. E.Info(obj).name .. "]" end
    return default or capture
  end))
end

---------------------------------------------------------------------------
-- Variables: w = this run, o = the object (the campaign log for campaigns),
-- c = the campaign that's playing.
---------------------------------------------------------------------------
local function Storage(args, source)
  if source == "w" then
    args.custom = args.custom or {}
    return args.custom
  elseif source == "o" and type(args.object) == "table" then
    args.object.vars = type(args.object.vars) == "table" and args.object.vars or {}
    return args.object.vars
  elseif source == "c" then
    local log = ActiveLog()
    if not log then return nil end
    log.vars = type(log.vars) == "table" and log.vars or {}
    return log.vars
  end
end

function S.SetVar(args, source, op, name, value)
  if type(name) ~= "string" or name == "" then return end
  local store = Storage(args, source)
  if not store then return end
  if op == "=" or (op == "[=]" and store[name] == nil) then
    store[name] = value
    return
  end
  local a, b = tonumber(store[name] or 0) or 0, tonumber(value or 0) or 0
  if op == "+" then store[name] = a + b
  elseif op == "-" then store[name] = a - b
  elseif op == "x" then store[name] = a * b
  elseif op == "/" then store[name] = b ~= 0 and a / b or a end
end

function S.GetVar(args, source, name)
  local store = Storage(args, source)
  if not store then return nil end
  return store[name]
end

---------------------------------------------------------------------------
-- Conditions. A test is { left, comparator, right }; each side is a value
-- { v = ... } or an operand { i = id, a = args }. Tests join with "+" (and)
-- and "*" (or), the ors binding first, as Extended reads them.
---------------------------------------------------------------------------
local NUMERIC = { ["<"] = true, [">"] = true, ["<="] = true, [">="] = true }

local function Side(s, numeric, args)
  if type(s) ~= "table" then error("a condition is damaged") end
  if s.v ~= nil then
    if numeric then
      local n = tonumber(s.v)
      if not n then error("a condition compares a word as a number") end
      return n
    end
    return S.Parse(tostring(s.v), args)
  end
  local fn = S.operands[s.i]
  if not fn then error("a condition uses something Kinship doesn't know (" .. tostring(s.i) .. ")") end
  local v = fn(type(s.a) == "table" and s.a or EMPTY, args)
  if numeric then return tonumber(v) or -1 end
  return tostring(v)
end

local function Test(t, args)
  local cmp = t[2]
  local numeric = NUMERIC[cmp]
  if not numeric and cmp ~= "==" and cmp ~= "~=" then error("a condition is damaged") end
  local l, r = Side(t[1], numeric, args), Side(t[3], numeric, args)
  if cmp == "==" then return l == r
  elseif cmp == "~=" then return l ~= r
  elseif cmp == "<" then return l < r
  elseif cmp == ">" then return l > r
  elseif cmp == "<=" then return l <= r
  else return l >= r end
end

local function Evaluate(cond, args)
  local result, group = true, nil
  for i = 1, #cond do
    local el = cond[i]
    if type(el) == "table" then
      local v = Test(el, args)
      if group == nil then group = v else group = group or v end
    elseif el == "+" then
      if group ~= nil then result = result and group end
      group = nil
    elseif el ~= "*" then
      error("a condition is damaged")
    end
  end
  if group ~= nil then result = result and group end
  return result and true or false
end

function S:Check(cond, args)
  if type(cond) ~= "table" or #cond == 0 then return true end
  local ok, res = pcall(Evaluate, cond, args or EMPTY)
  if not ok then
    S.Note(args and args.classID, "cond:" .. tostring(res), "a condition couldn't be read, so it counts as false (" .. tostring(res):gsub("^.-:%d+: ", "") .. ").")
    return false
  end
  return res
end

---------------------------------------------------------------------------
-- Workflows
---------------------------------------------------------------------------
local function RunEffect(eff, args)
  if type(eff) ~= "table" then return end
  local id = E.Str(eff.id) or "MISSING"
  if type(eff.cond) == "table" and #eff.cond > 0 and not S:Check(eff.cond, args) then return end
  if E.REFUSED[id] then
    S.Note(args.classID, "refused", "it tried to run a raw script or macro. Kinship never runs those, so that part was skipped.")
    return
  end
  local fn = S.effects[id]
  if not fn then
    S.Note(args.classID, "effect:" .. id, ("it uses an effect Kinship can't play yet (%s), so that part was skipped."):format(id))
    return
  end
  fn(type(eff.args) == "table" and eff.args or EMPTY, args, E:Allowed(args.classID, id))
end

local Element
function Element(structure, id, args, budget)
  while id ~= nil do
    budget.n = budget.n + 1
    if budget.n > MAX_STEPS then error("it ran too long (a workflow loops on itself)") end
    local el = structure[id]
    if el == nil and type(id) == "number" then el = structure[tostring(id)] end
    if el == nil and type(id) == "string" then el = structure[tonumber(id) or id] end
    if type(el) ~= "table" then return end
    if el.t == "list" then
      for _, eff in ipairs(type(el.e) == "table" and el.e or EMPTY) do RunEffect(eff, args) end
      id = el.n
    elseif el.t == "branch" then
      -- Every branch whose condition holds runs, in order, as in Extended.
      for _, b in ipairs(type(el.b) == "table" and el.b or EMPTY) do
        if type(b) == "table" then
          local has = type(b.cond) == "table" and #b.cond > 0
          if not has or S:Check(b.cond, args) then
            if b.n then Element(structure, b.n, args, budget) end
          elseif has then
            if type(b.failMessage) == "string" and b.failMessage ~= "" then S.Message(S.Parse(b.failMessage, args), 4) end
            if type(b.failWorkflow) == "string" and b.failWorkflow ~= "" then
              S:Run(b.failWorkflow, args.scripts, args, args.classID)
            end
          end
        end
      end
      return
    elseif el.t == "delay" then
      local d = math.max(0, math.min(E.Num(el.d, 0), 3600))
      local nextID = el.n
      -- An interruptible cast doesn't start while you move, and stops if you do.
      local cast = E.Num(el.i, 1) == 2
      if cast and (GetUnitSpeed("player") or 0) > 0 then return end
      if nextID ~= nil then
        C_Timer.After(d, function()
          if cast and (GetUnitSpeed("player") or 0) > 0 then return end
          S.Resume(structure, nextID, args)
        end)
      end
      return
    else
      return
    end
  end
end

local function Fail(args, err)
  err = tostring(err):gsub("^.-:%d+: ", "")
  S.Note(args and args.classID, "error:" .. err, "a script stopped: " .. err)
end

function S.Resume(structure, id, args)
  depth = depth + 1
  local ok, err = pcall(Element, structure, id, args, { n = 0 })
  depth = depth - 1
  if not ok then Fail(args, err) end
end

-- Run SC[scriptID] of an object. fullID is the object's full ID: it decides
-- what the workflow may do (K.Ext:Allowed).
function S:Run(scriptID, scripts, args, fullID)
  if type(scripts) ~= "table" or scriptID == nil then return end
  local wf = scripts[scriptID]
  if type(wf) ~= "table" or type(wf.ST) ~= "table" then
    S.Note(fullID, "missing:" .. tostring(scriptID), ("it calls a workflow that isn't there (%s)."):format(tostring(scriptID)))
    return
  end
  if depth >= MAX_DEPTH then Fail(args, "workflows started each other too many times") return end
  args = args or {}
  args.custom = args.custom or {}
  args.scripts, args.classID = scripts, fullID
  local first = wf.ST["1"] ~= nil and "1" or 1
  S.Resume(wf.ST, first, args)
end

---------------------------------------------------------------------------
-- Messages, as Extended's: 1 chat, 2 a box to close, 3 across the screen,
-- 4 the alert line at the top.
---------------------------------------------------------------------------
StaticPopupDialogs["KINSHIPRP_EXT_MESSAGE"] = {
  text = "%s", button1 = OKAY or "OK",
  timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
}

function S.Message(text, kind)
  text = S.Text(tostring(text or ""))
  if text == "" then return end
  kind = tonumber(kind) or 1
  if kind == 2 then
    StaticPopup_Show("KINSHIPRP_EXT_MESSAGE", K.UI.Clean(text))
  elseif kind == 3 and RaidNotice_AddMessage and RaidWarningFrame then
    RaidNotice_AddMessage(RaidWarningFrame, K.UI.Clean(text), ChatTypeInfo and ChatTypeInfo.RAID_WARNING or { r = 1, g = 0.82, b = 0 })
  elseif kind == 4 and UIErrorsFrame then
    UIErrorsFrame:AddMessage(K.UI.Clean(text), 1, 0.82, 0)
  else
    DEFAULT_CHAT_FRAME:AddMessage(K.UI.Clean(text), 1, 0.82, 0)
  end
end

---------------------------------------------------------------------------
-- Effects
---------------------------------------------------------------------------
local FX = S.effects
local function Str(v, default) return E.Str(v, default) or default end

local function Chat(text, channel)
  text = K.UI.Clean(S.Text(text)):gsub("\n", " ")
  if text == "" then return end
  if #text > 255 then text = text:sub(1, 255) end
  local send = C_ChatInfo and C_ChatInfo.SendChatMessage or SendChatMessage
  if send then pcall(send, text, channel) end
end

local SPEECH = { ["/s"] = "says:", ["/y"] = "yells:", ["/w"] = "whispers:" }
local CHANNEL = { ["/s"] = "SAY", ["/y"] = "YELL", ["/e"] = "EMOTE" }

FX.MISSING = function(_, args) S.Note(args.classID, "missing", "it uses an effect that's missing from it, so that part was skipped.") end

FX.text = function(a, args)
  local text = S.Parse(Str(a[1], ""), args)
  S.Message(text, a[2])
  args.LAST = 0
end

FX.speech_env = function(a, args, allowed)
  local text = S.Parse(Str(a[1], ""), args)
  if allowed then Chat("|| " .. text, "EMOTE") else S.Message(text, 1) end
  args.LAST = 0
end

FX.speech_npc = function(a, args, allowed)
  local name, how, text = Str(a[1], ""), Str(a[2], "/s"), Str(a[3], "")
  local line
  if how == "/e" then line = ("%s %s"):format(name, text)
  else line = ("%s %s %s"):format(name, SPEECH[how] or SPEECH["/s"], text) end
  line = S.Parse(line, args)
  if allowed then Chat("|| " .. line, "EMOTE") else S.Message(line, 1) end
  args.LAST = 0
end

FX.speech_player = function(a, args, allowed)
  local how, text = Str(a[1], "/s"), S.Parse(Str(a[2], ""), args)
  if allowed then Chat(text, CHANNEL[how] or "SAY") else S.Message(("%s: %s"):format(K.Plain(K:DisplayName()), text), 1) end
  args.LAST = 0
end

FX.do_emote = function(a, args, allowed)
  local token = Str(a[1], ""):upper()
  if token == "" then return end
  local faction = UnitFactionGroup("player")
  if token == "FORTHEALLIANCE" and faction == "Horde" then token = "FORTHEHORDE"
  elseif token == "FORTHEHORDE" and faction == "Alliance" then token = "FORTHEALLIANCE" end
  if allowed then
    local fn = (C_ChatInfo and C_ChatInfo.PerformEmote) or rawget(_G, "DoEmote")
    if fn then pcall(fn, token) end
  else
    S.Message("/" .. token:lower(), 1)
  end
  args.LAST = 0
end

FX.var_object = function(a, args)
  S.SetVar(args, Str(a[1], "w"), Str(a[2], "i"), Str(a[3], "var"), S.Parse(Str(a[4], "0"), args))
  args.LAST = 0
end

FX.var_operand = function(a, args)
  local fn = S.operands[Str(a[3], "random")]
  if not fn then S.Note(args.classID, "operand:" .. tostring(a[3]), ("it reads something Kinship doesn't know (%s)."):format(tostring(a[3]))) return end
  S.SetVar(args, Str(a[2], "w"), "=", Str(a[1], "var"), fn(type(a[4]) == "table" and a[4] or EMPTY, args))
  args.LAST = 0
end

-- Ask for a word, keep it in a variable, then carry on with a workflow.
local prompt
StaticPopupDialogs["KINSHIPRP_EXT_PROMPT"] = {
  text = "%s", button1 = OKAY or "OK", button2 = CANCEL or "Cancel",
  hasEditBox = true, maxLetters = 200,
  OnShow = function(self)
    local eb = self.editBox or self.EditBox or (self.GetEditBox and self:GetEditBox())
    if eb then eb:SetText(""); eb:SetFocus() end
  end,
  OnAccept = function(self)
    local eb = self.editBox or self.EditBox or (self.GetEditBox and self:GetEditBox())
    if prompt and eb then S.SetVar(prompt.args, prompt.source, "=", prompt.var, eb:GetText()) end
  end,
  OnHide = function()
    local p = prompt
    prompt = nil
    if p and p.after then
      C_Timer.After(0, function() FX.run_workflow({ p.afterSource, p.after }, p.args) end)
    end
  end,
  EditBoxOnEnterPressed = function(self) self:GetParent().button1:Click() end,
  EditBoxOnEscapePressed = function(self) self:GetParent():Hide() end,
  timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
}

FX.var_prompt = function(a, args)
  C_Timer.After(0.1, function()
    prompt = { args = args, var = Str(a[2], "var"), source = Str(a[3], "o"),
               after = E.Str(a[4]), afterSource = Str(a[5], "o") }
    if prompt.after == "" then prompt.after = nil end
    StaticPopup_Show("KINSHIPRP_EXT_PROMPT", K.UI.Clean(S.Text(S.Parse(Str(a[1], ""), args))))
  end)
  args.LAST = 0
end

FX.signal_send = function(a, args)
  if UnitExists("target") and UnitIsUnit("target", "player") then
    if P() then P():Custom("TRP3_SIGNAL", Str(a[1], ""), S.Parse(Str(a[2], ""), args), UnitID("player")) end
  else
    S.Note(args.classID, "signal", "it sends signals to other players, which Kinship can't do yet.")
  end
  args.LAST = 0
end

FX.run_workflow = function(a, args)
  local source, id = Str(a[1], "o"), E.Str(a[2])
  if not id then return end
  if source == "o" then
    S:Run(id, args.scripts, args, args.classID)
  elseif source == "c" then
    local c = P() and P():Current()
    local obj = c and E:Get(c)
    if obj and type(obj.SC) == "table" then S:Run(id, obj.SC, args, c) end
  else
    S.Note(args.classID, "itemwf", "it runs workflows on Total RP 3: Extended items, which Kinship can't hold yet.")
  end
end

-- Sounds and music, for you alone (sounds "nearby" play only for you too:
-- they'd need Total RP 3 to reach other players).
local playing = {}
local function PlaySound_(channel, id, isFile)
  local num = tonumber(id)
  local ok, willPlay, handle
  if isFile or not num then
    ok, willPlay, handle = pcall(PlaySoundFile, num or id, channel or "SFX")
  else
    ok, willPlay, handle = pcall(PlaySound, num, channel or "SFX", false)
  end
  if ok and willPlay and handle then
    playing[tostring(id)] = playing[tostring(id)] or {}
    table.insert(playing[tostring(id)], handle)
  end
end

local function StopSounds(id, fade)
  local list = playing[tostring(id)]
  if not list then return end
  for _, h in ipairs(list) do pcall(StopSound, h, (tonumber(fade) or 0) * 1000) end
  playing[tostring(id)] = nil
end

FX.sound_id_self = function(a, args) PlaySound_(Str(a[1], "SFX"), a[2], E.Bool(a[3])); args.LAST = 0 end
FX.sound_id_local = function(a, args) PlaySound_(Str(a[1], "SFX"), a[2], E.Bool(a[4])); args.LAST = 0 end
FX.sound_id_stop = function(a, args)
  if a[2] == nil or a[2] == "" then for id in pairs(playing) do StopSounds(id, a[3]) end else StopSounds(a[2], a[3]) end
  args.LAST = 0
end
FX.sound_id_local_stop = FX.sound_id_stop
FX.sound_music_self = function(a, args)
  local id = a[1]
  if id ~= nil and id ~= "" then pcall(PlayMusic, tonumber(id) or id) end
  args.LAST = 0
end
FX.sound_music_local = FX.sound_music_self
FX.sound_music_stop = function(_, args) pcall(StopMusic); args.LAST = 0 end
FX.sound_music_local_stop = FX.sound_music_stop

FX.companion_dismiss_mount = function(_, args, allowed)
  if allowed and IsMounted() then pcall(Dismount) end
  args.LAST = 0
end
FX.companion_summon_mount = function(a, args, allowed)
  local id = tonumber(a[1])
  if allowed and id and C_MountJournal and C_MountJournal.SummonByID then pcall(C_MountJournal.SummonByID, id) end
  args.LAST = 0
end
FX.companion_dismiss_critter = function(_, args)
  local pj = rawget(_G, "C_PetJournal")
  if pj and pj.GetSummonedPetGUID and pj.SummonPetByGUID then
    local guid = pj.GetSummonedPetGUID()
    if guid then pcall(pj.SummonPetByGUID, guid) end
  end
  args.LAST = 0
end
FX.companion_random_critter = function(a, args)
  local pj = rawget(_G, "C_PetJournal")
  if pj and pj.SummonRandomPet then pcall(pj.SummonRandomPet, E.Bool(a[1])) end
  args.LAST = 0
end

FX.cam_zoom_in = function(a, args) pcall(CameraZoomIn, tonumber(S.Parse(Str(a[1], "0"), args)) or 0); args.LAST = 0 end
FX.cam_zoom_out = function(a, args) pcall(CameraZoomOut, tonumber(S.Parse(Str(a[1], "0"), args)) or 0); args.LAST = 0 end
FX.cam_save = function(a, args) pcall(SaveView, tonumber(a[1]) or 1); args.LAST = 0 end
FX.cam_load = function(a, args) pcall(SetView, tonumber(a[1]) or 1); args.LAST = 0 end

-- Quests: "campaign quest" in the first argument, as Extended writes them.
local function QuestIDs(v)
  local parts = E.Split(E.Str(v) or "")
  return parts[1], parts[2], parts[3]
end

FX.quest_start = function(a, args)
  local c, q = QuestIDs(a[1])
  args.LAST = (c and q and P()) and P():StartQuest(c, q) or 2
end
FX.quest_goToStep = function(a, args)
  local c, q, s = QuestIDs(a[1])
  args.LAST = (c and q and s and P()) and P():GoToStep(c, q, s) or 2
end
FX.quest_revealObjective = function(a, args)
  local c, q = QuestIDs(a[1])
  local o = E.Str(a[2])
  args.LAST = (c and q and o and P()) and P():Reveal(c, q, o) or 2
end
FX.quest_markObjDone = function(a, args)
  local c, q = QuestIDs(a[1])
  local o = E.Str(a[2])
  args.LAST = (c and q and o and P()) and P():MarkDone(c, q, o) or 2
end

FX.document_show = function(a, args)
  local id = E.Str(a[1])
  if id and K.ExtCutscene then K.ExtCutscene:ShowDocument(id, args) end
  args.LAST = 0
end
FX.document_close = function(_, args)
  if K.ExtCutscene then K.ExtCutscene:CloseDocument() end
  args.LAST = 0
end
FX.dialog_start = function(a, args)
  local id = E.Str(a[1])
  if id and K.ExtCutscene then K.ExtCutscene:Play(id, args) end
  args.LAST = 0
end
FX.dialog_quick = function(a, args)
  if K.ExtCutscene then K.ExtCutscene:Quick(Str(a[1], ""), args) end
  args.LAST = 0
end

-- Dice: "1d20 2d6+1", each part filled in first. The total is the result.
FX.item_roll_dice = function(a, args)
  local total, parts = 0, {}
  for part in Str(a[1], "1d20"):gmatch("%S+") do
    part = S.Parse(part, args)
    local n, sides, mod = part:match("^(%d*)[dD](%d+)([%+%-]?%d*)$")
    n, sides = tonumber(n) or 1, tonumber(sides)
    if sides and n >= 1 and n <= 100 and sides >= 1 and sides <= 10000 then
      local sum = 0
      for _ = 1, n do sum = sum + math.random(1, sides) end
      sum = sum + (tonumber(mod) or 0)
      total = total + sum
      parts[#parts + 1] = ("%dd%d%s"):format(n, sides, mod or "")
    end
  end
  if #parts > 0 then
    S.Message(("%s rolls %s: %d"):format(K.Plain(K:DisplayName()), table.concat(parts, " "), total), 1)
    if P() then P():Custom("TRP3_ROLL", table.concat(parts, " "), total) end
  end
  local var = E.Str(a[2])
  if var and var ~= "" then S.SetVar(args, Str(a[3], "w"), "=", var, total) end
  args.LAST = total
end

FX.item_sheath = function(_, args) pcall(ToggleSheath); args.LAST = 0 end

-- What a campaign may use that Kinship can't hold: Extended's own items and auras.
for _, id in ipairs({ "item_add", "item_remove", "item_consume", "item_cooldown", "item_bag_durability",
                      "item_use", "item_loot", "run_item_workflow" }) do
  FX[id] = function(_, args)
    S.Note(args.classID, "items", "it uses Total RP 3: Extended items, which Kinship can't hold yet, so those parts were skipped.")
    args.LAST = 2
  end
end
for _, id in ipairs({ "aura_apply", "aura_remove", "aura_duration", "aura_var_set", "aura_run_workflow" }) do
  FX[id] = function(_, args)
    S.Note(args.classID, "auras", "it uses Total RP 3: Extended auras, which Kinship can't play yet, so those parts were skipped.")
    args.LAST = 2
  end
end

---------------------------------------------------------------------------
-- Operands: what conditions and variables can read.
---------------------------------------------------------------------------
local OP = S.operands
local function U(a) local u = E.Str(a[1]); return (u and u ~= "") and u or "target" end
local function Call(fn, ...) local ok, a, b, c = pcall(fn, ...); if ok then return a, b, c end end

local function NPCID(unit)
  local guid = UnitExists(unit) and Safe(UnitGUID(unit))
  if not guid then return nil end
  local kind, _, _, _, _, id = strsplit("-", guid)
  if kind == "Creature" or kind == "Vehicle" or kind == "Pet" then return id end
end
S.NPCID = NPCID

local function Position(unit)
  local y, x = Call(UnitPosition, unit)
  return Safe(x), Safe(y)
end

OP.unit_name = function(a) return FullName(U(a)) or "nil" end
OP.unit_id = function(a) return UnitID(U(a)) or "nil" end
OP.unit_npc_id = function(a) return NPCID(U(a)) or "nil" end
OP.unit_guid = function(a) return Safe(UnitGUID(U(a))) or "nil" end
OP.unit_guild = function(a) return Safe((Call(GetGuildInfo, U(a)))) or "nil" end
OP.unit_guild_rank = function(a) local _, rank = Call(GetGuildInfo, U(a)); return Safe(rank) or "nil" end
OP.unit_class = function(a) local _, c = UnitClass(U(a)); c = Safe(c); return c and c:lower() or "nil" end
OP.unit_race = function(a) local _, r = UnitRace(U(a)); r = Safe(r); return r and r:lower() or "nil" end
OP.unit_faction = function(a) local f = Safe(UnitFactionGroup(U(a))); return f and f:lower() or "nil" end
OP.unit_sex = function(a) return Safe(UnitSex(U(a))) or 1 end
OP.unit_creature_type = function(a) return Safe(UnitCreatureType(U(a))) or "nil" end
OP.unit_creature_family = function(a) return Safe(UnitCreatureFamily(U(a))) or "nil" end
OP.unit_classification = function(a) return Safe(UnitClassification(U(a))) or "nil" end
OP.unit_exists = function(a) return UnitExists(U(a)) and true or false end
OP.unit_is_player = function(a) return Safe(UnitIsPlayer(U(a))) and true or false end
OP.unit_is_dead = function(a) return Safe(UnitIsDeadOrGhost(U(a))) and true or false end
OP.unit_distance_trade = function(a) return Safe((Call(CheckInteractDistance, U(a), 2))) and true or false end
OP.unit_distance_inspect = function(a) return Safe((Call(CheckInteractDistance, U(a), 1))) and true or false end
OP.unit_health = function(a) return Safe(UnitHealth(U(a))) or 0 end
OP.unit_level = function(a) return Safe(UnitLevel(U(a))) or 0 end
OP.unit_speed = function(a) return Safe((GetUnitSpeed(U(a)))) or 0 end
OP.unit_position_x = function(a) local x = Position(U(a)); return x or 0 end
OP.unit_position_y = function(a) local _, y = Position(U(a)); return y or 0 end
OP.unit_distance_point = function(a, args)
  local x, y = Position(U(a))
  local px, py = tonumber(S.Parse(E.Str(a[3]) or "0", args)) or 0, tonumber(S.Parse(E.Str(a[2]) or "0", args)) or 0
  if not (x and y) then return 0 end
  return math.sqrt((x - px) ^ 2 + (y - py) ^ 2)
end
OP.unit_distance_me = function(a)
  local x, y = Position(U(a))
  local mx, my = Position("player")
  if not (x and y and mx and my) then return 0 end
  return math.sqrt((x - mx) ^ 2 + (y - my) ^ 2)
end

OP.char_facing = function() return Safe(Call(GetPlayerFacing)) or 0 end
OP.char_cam_distance = function() return Safe(Call(GetCameraZoom)) or 0 end
OP.char_falling = function() return IsFalling() and true or false end
OP.char_stealth = function() return IsStealthed() and true or false end
OP.char_flying = function() return IsFlying() and true or false end
OP.char_mounted = function() return IsMounted() and true or false end
OP.char_resting = function() return IsResting() and true or false end
OP.char_swimming = function() return IsSwimming() and true or false end
OP.char_indoors = function() return IsIndoors() and true or false end
OP.char_zone = function() return GetZoneText() or "" end
OP.char_subzone = function() return GetSubZoneText() or "" end
OP.char_minimap = function() return GetMinimapZoneText() or "" end
OP.char_achievement = function(a)
  local id = tonumber(a[2])
  if not (id and GetAchievementInfo) then return false end
  local r = { Call(GetAchievementInfo, id) }
  if a[1] == "account" then return r[4] and true or false end
  return r[13] and true or false
end

OP.var_check = function(a, args) local v = S.GetVar(args, E.Str(a[1]) or "w", E.Str(a[2]) or ""); return v == nil and "nil" or tostring(v) end
OP.var_check_n = function(a, args) return tonumber(S.GetVar(args, E.Str(a[1]) or "w", E.Str(a[2]) or "") or 0) or 0 end
OP.check_event_var = function(a, args) local v = (args.event or EMPTY)[tonumber(a[1]) or 1]; return v == nil and "nil" or tostring(v) end
OP.check_event_var_n = function(a, args) return tonumber((args.event or EMPTY)[tonumber(a[1]) or 1] or 0) or 0 end
OP.random = function(a, args)
  local from = math.floor(tonumber(S.Parse(E.Str(a[1]) or "1", args)) or 1)
  local to = math.floor(tonumber(S.Parse(E.Str(a[2]) or "100", args)) or 100)
  if to < from then from, to = to, from end
  return math.random(from, to)
end

OP.quest_is_step = function(a) local c, q = QuestIDs(a[1]); return (c and q and P() and P():CurrentStep(c, q)) or "nil" end
OP.quest_obj = function(a) local c, q = QuestIDs(a[1]); return (c and q and P() and P():ObjectiveDone(c, q, E.Str(a[2]))) and true or false end
OP.quest_obj_current = function(a) local c, q = QuestIDs(a[1]); return (c and q and P() and P():AllDone(c, q, false)) and true or false end
OP.quest_obj_all = function(a) local c, q = QuestIDs(a[1]); return (c and q and P() and P():AllDone(c, q, true)) and true or false end
OP.quest_is_npc = function(a) return (P() and P():NPC(U(a))) and true or false end
OP.quest_active_campaign = function() return (P() and P():Current()) or "nil" end

OP.time_hour = function() local h = GetGameTime(); return h or 0 end
OP.time_minute = function() local _, m = GetGameTime(); return m or 0 end
OP.date_day = function() return date("*t").day end
OP.date_month = function() return date("*t").month end
OP.date_year = function() return date("*t").year end
OP.date_day_of_week = function() return date("*t").wday end

-- Extended's items and auras aren't held here: they read as absent.
for _, id in ipairs({ "inv_item_quality", "inv_item_id_weight", "inv_item_value", "inv_item_count", "inv_item_weight" }) do
  OP[id] = function(_, args)
    S.Note(args.classID, "items", "it uses Total RP 3: Extended items, which Kinship can't hold yet, so those parts were skipped.")
    return 0
  end
end
for _, id in ipairs({ "inv_item_name", "inv_item_icon", "inv_container_slot_id" }) do
  OP[id] = function(_, args)
    S.Note(args.classID, "items", "it uses Total RP 3: Extended items, which Kinship can't hold yet, so those parts were skipped.")
    return "nil"
  end
end
for _, id in ipairs({ "aura_active", "aura_helpful", "aura_cancellable" }) do OP[id] = function() return false end end
for _, id in ipairs({ "aura_duration", "aura_count", "aura_var_check_n" }) do OP[id] = function() return 0 end end
for _, id in ipairs({ "aura_name", "aura_category", "aura_icon", "aura_color", "aura_var_check", "aura_id" }) do
  OP[id] = function() return "nil" end
end
