-- Kinship RP: moving over from Total RP 3 (and other roleplay addons).
--
-- Kinship is a replacement, not a companion: two addons writing one shared
-- profile fight each other. When another RP addon is running, Kinship offers
-- to bring your profiles across and switch the old addon off.
--
-- Total RP 3's saved data is only readable while it is loaded, so the import
-- happens first and the switch-off second. Every imported profile is also
-- kept account-wide, so your other characters pick up theirs the first time
-- they log in, even after Total RP 3 is gone. Total RP 3's own files are
-- never changed, so going back is always possible.

local ADDON, ns = ...
local K = ns.K
local UI = K.UI
local I = {}
K.Import = I

local LABELS = { totalRP3 = "Total RP 3", MyRolePlay = "MyRolePlay", xrp = "XRP" }
function I.Label(name) return LABELS[name] or name end

-- Total RP 3 personality presets, in its own order (for traits).
local TRAIT_PRESETS = {
  { "Chaotic", "Lawful" }, { "Chaste", "Lustful" }, { "Forgiving", "Vindictive" }, { "Altruistic", "Selfish" },
  { "Truthful", "Deceitful" }, { "Gentle", "Brutal" }, { "Superstitious", "Rational" }, { "Renegade", "Paragon" },
  { "Cautious", "Impulsive" }, { "Ascetic", "Bon vivant" }, { "Valorous", "Spineless" },
}
-- Misc. info types (Total RP 3's MiscInfoType)
local MISC = { [2] = "house", [3] = "nickname", [4] = "motto", [7] = "pronouns" }
-- RP-style ids to MSP consent fields
local STYLE = { ["2"] = "RI", ["3"] = "RD", ["4"] = "RR", ["7"] = "RM", ["8"] = "RO" }

---------------------------------------------------------------------------
-- Reading Total RP 3
---------------------------------------------------------------------------
-- Total RP 3 text carries its own markup: {h1}, {p:c}, {col:ffffff}, {icon:...}, {link*url*text}.
local function Strip(text)
  if type(text) ~= "string" then return "" end
  text = text:gsub("{link%*[^*]*%*(.-)}", "%1")
  text = text:gsub("{[^}]*}", "")
  text = text:gsub("|c%x%x%x%x%x%x%x%x", "")
  text = text:gsub("|r", "")
  text = text:gsub("|T.-|t", "")
  text = text:gsub("\n\n\n+", "\n\n")
  return strtrim(text)
end

-- Glance icons are stored as Total RP 3 media ids, not texture paths. Turn
-- them into something SetTexture understands while Total RP 3 is loaded.
function I.ResolveIcon(ic)
  if ic == nil then return nil end
  local lib = LibStub and LibStub("LibRPMedia-1.2", true)
  if lib and lib.ResolveIcon then
    local ok, a = pcall(lib.ResolveIcon, lib, ic)
    if ok and (type(a) == "number" or type(a) == "string") then return a end
  end
  local n = tonumber(ic)
  if n then return (bit and bit.band) and bit.band(n, 0x03ffffff) or n end
  if type(ic) == "string" and ic:find("^[%w_]+$") then return "Interface\\Icons\\" .. ic end
  return nil
end

-- Total RP 3's own key for a character: on this client that's the full name
-- with no realm ("Vax Orus"); elsewhere "Name-Realm". Kinship's MyName()
-- follows the same rule (both go through Chomp).
local function MyCharacterID()
  local api = rawget(_G, "TRP3_API")
  local id = type(api) == "table" and type(api.globals) == "table" and api.globals.player_id
  if type(id) == "string" and id ~= "" then return id end
  return K:MyName()
end

-- Find the profile bound to this character, comparing names loosely.
local function BoundTo(bound, id)
  if not id then return nil end
  if bound[id] then return bound[id] end
  local key = K.NameKey(id)
  for charID, name in pairs(bound) do
    if K.NameKey(charID) == key then return name end
  end
end
function I:TRP3Available() return type(rawget(_G, "TRP3_Profiles")) == "table" end

-- { { id, name, prof, chars = { "Name-Realm", ... }, mine = bool }, ... }
function I:TRP3Profiles()
  local profiles = rawget(_G, "TRP3_Profiles")
  if type(profiles) ~= "table" then return {} end
  local bound, chars = {}, rawget(_G, "TRP3_Characters")
  if type(chars) == "table" then
    for charID, c in pairs(chars) do
      if type(c) == "table" and c.profileID then
        bound[c.profileID] = bound[c.profileID] or {}
        table.insert(bound[c.profileID], charID)
      end
    end
  end
  local me, list = MyCharacterID(), {}
  for id, prof in pairs(profiles) do
    -- Skip Total RP 3's automatic default profile (its id ends in "*").
    if type(prof) == "table" and type(prof.player) == "table" and not (type(id) == "string" and id:sub(-1) == "*") then
      local entry = { id = id, name = Strip(prof.profileName) ~= "" and Strip(prof.profileName) or "Profile", prof = prof,
                      chars = bound[id] or {} }
      for _, c in ipairs(entry.chars) do if c == me or K.NameKey(c) == K.NameKey(me) then entry.mine = true end end
      list[#list + 1] = entry
    end
  end
  table.sort(list, function(a, b)
    if a.mine ~= b.mine then return a.mine and true or false end
    return a.name < b.name
  end)
  return list
end

-- Turn one Total RP 3 profile into a Kinship profile.
function I:Convert(prof)
  local pl = prof.player or {}
  local ch, ab, mi, cr = pl.characteristics or {}, pl.about or {}, pl.misc or {}, pl.character or {}
  local p = K.BlankProfile()

  local first, last = Strip(ch.FN), Strip(ch.LN)
  p.rpName = strtrim(first .. " " .. last)
  p.prefix = Strip(ch.TI)
  p.epithet = Strip(ch.FT)
  p.house = last   -- never the importing character's surname; a House misc entry can still set it
  -- Total RP 3 copies the game's race and class into every profile; only keep them if they were changed.
  local race, class = Strip(ch.RA), Strip(ch.CL)
  local gameRace, gameClass = UnitRace("player"), UnitClass("player")
  p.race = (race ~= gameRace) and race or ""
  p.class = (class ~= gameClass) and class or ""
  p.age, p.height, p.eyes = Strip(ch.AG), Strip(ch.HE), Strip(ch.EC)
  p.home, p.birthplace = Strip(ch.RE), Strip(ch.BP)
  if type(ch.MI) == "table" then
    for _, m in ipairs(ch.MI) do
      if type(m) == "table" then
        local field = MISC[tonumber(m.ID) or 0]
        if not field and type(m.NA) == "string" then
          local n = m.NA:lower()
          field = (n:find("pronoun") and "pronouns") or (n:find("motto") and "motto") or (n:find("nick") and "nickname")
            or (n:find("house") and "house") or nil
        end
        local v = Strip(m.VA)
        if field and v ~= "" then p[field] = v end
      end
    end
  end

  -- About: Total RP 3 has three layouts; Kinship keeps Appearance / Personality / History.
  local te = tonumber(ab.TE) or 1
  if te == 3 and type(ab.T3) == "table" then
    p.appearance = Strip(ab.T3.PH and ab.T3.PH.TX)
    p.personality = Strip(ab.T3.PS and ab.T3.PS.TX)
    p.history = Strip(ab.T3.HI and ab.T3.HI.TX)
  elseif te == 2 and type(ab.T2) == "table" then
    local parts = {}
    for _, frame in ipairs(ab.T2) do
      local t = type(frame) == "table" and Strip(frame.TX) or ""
      if t ~= "" then parts[#parts + 1] = t end
    end
    p.appearance = table.concat(parts, "\n\n")
  else
    p.appearance = Strip(type(ab.T1) == "table" and ab.T1.TX)
  end

  p.currently, p.ooc = Strip(cr.CU), Strip(cr.CO)
  p.status = (tonumber(cr.RP) == 1) and "ic" or "ooc"
  -- Roleplay experience: Total RP 3's beginner, experienced, volunteer.
  local xp = tonumber(cr.XP)
  if xp then p.rpExp = ({ "new", "experienced", "mentor" })[xp] end

  -- At first glance: kept whole for Kinship's glances, and summed up in the glance line.
  p.glances = {}
  if type(mi.PE) == "table" then
    local lines = {}
    for i = 1, 5 do
      local g = mi.PE[tostring(i)] or mi.PE[i]
      if type(g) == "table" and g.AC then
        local title, text = Strip(g.TI), Strip(g.TX)
        p.glances[#p.glances + 1] = { icon = I.ResolveIcon(g.IC), title = title, text = text }
        if title ~= "" then lines[#lines + 1] = title end
      end
    end
    p.glance = table.concat(lines, ". ")
  end

  -- Personality traits: kept for Kinship's trait sliders.
  p.traits = {}
  if type(ch.PS) == "table" then
    for _, t in ipairs(ch.PS) do
      if type(t) == "table" then
        local preset = TRAIT_PRESETS[tonumber(t.ID) or 0]
        local left = Strip(t.LT) ~= "" and Strip(t.LT) or (preset and preset[1])
        local right = Strip(t.RT) ~= "" and Strip(t.RT) or (preset and preset[2])
        -- V2 runs 0-20 (10 = centre); Total RP 3 shows a missing value at the centre.
        local value = math.max(0, math.min(20, tonumber(t.V2) or 10))
        if left and right then p.traits[#p.traits + 1] = { left = left, right = right, value = value } end
      end
    end
  end

  -- RP style becomes consent (same values on both sides).
  if type(mi.ST) == "table" then
    for id, field in pairs(STYLE) do
      local v = tostring(mi.ST[id] or mi.ST[tonumber(id)] or 0)
      if v == "1" or v == "2" or v == "3" then p.consent[field] = v end
    end
  end
  return p
end

---------------------------------------------------------------------------
-- Bringing profiles across
---------------------------------------------------------------------------
local function UniqueName(list, name)
  if not list[name] then return name end
  local n = 2
  while list[name .. " " .. n] do n = n + 1 end
  return name .. " " .. n
end

-- Profiles in a fresh Kinship start: all text empty.
local function IsBlank(p)
  if type(p) ~= "table" then return true end
  for k, v in pairs(K.BlankProfile()) do
    if type(v) == "string" and k ~= "house" and k ~= "status" and k ~= "stance" and strtrim(p[k] or "") ~= "" then return false end
  end
  return not (p.consent and next(p.consent))
end

-- A fingerprint of a profile's contents (not where it came from), to tell
-- whether it has been edited in Kinship since it was imported.
local function Signature(v)
  local t = type(v)
  if t ~= "table" then return t:sub(1, 1) .. tostring(v) end
  local keys = {}
  for k in pairs(v) do
    if k ~= "source" and k ~= "sourceSig" then keys[#keys + 1] = k end
  end
  table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
  local out = {}
  for _, k in ipairs(keys) do out[#out + 1] = tostring(k) .. "=" .. Signature(v[k]) end
  return "{" .. table.concat(out, ";") .. "}"
end

-- Put a converted profile into this character's list. The copy that came from
-- the same Total RP 3 profile is refreshed only if it hasn't been changed in
-- Kinship since; an edited one is left alone. Otherwise the profile is added.
-- Returns the name it lives under, and whether it was placed.
local function Place(list, name, prof)
  for existing, p in pairs(list) do
    if p.source and p.source == prof.source then
      if not p.sourceSig or Signature(p) ~= p.sourceSig then return existing, false end
      list[existing] = CopyTable(prof)
      list[existing].sourceSig = Signature(prof)
      return existing, true
    end
  end
  local final = UniqueName(list, name)
  list[final] = CopyTable(prof)
  list[final].sourceSig = Signature(prof)
  return final, true
end

-- Apply the account-wide library to this character, once per import.
-- all = this is the character doing the import (gets every profile);
-- otherwise a character only receives the profile Total RP 3 had bound to it.
function I:ApplyLibrary(all)
  local m = K.db.migration
  local lib = m.library
  if not lib or not lib.profiles then return 0 end
  m.applied = m.applied or {}
  local key = K:CharKey()
  if not key or (not all and m.applied[key] == lib.t) then return 0 end
  local mine, count = K:MyProfiles(), 0
  local boundName = BoundTo(lib.bound, MyCharacterID())
  local placedActive
  -- Clear away an untouched starter profile so it doesn't sit in front.
  if (all or boundName) and mine.list.Main and IsBlank(mine.list.Main) then
    local n = 0
    for _ in pairs(mine.list) do n = n + 1 end
    if n == 1 then mine.list.Main = nil end
  end
  for name, prof in pairs(lib.profiles) do
    if all or name == boundName then
      local final, placed = Place(mine.list, name, prof)
      if placed then count = count + 1 else self.kept = (self.kept or 0) + 1 end
      if name == boundName then placedActive = final end
    end
  end
  if placedActive then mine.active = placedActive end
  if not mine.list[mine.active or ""] then
    local first = lib.order and lib.order[1]
    mine.active = (first and mine.list[first] and first) or next(mine.list)
  end
  m.applied[key] = lib.t
  if count > 0 then K:Fire("PROFILE") end
  return count, placedActive
end

-- Read every Total RP 3 profile, keep them account-wide, apply to this character.
-- Safe to run again: profiles are matched by their Total RP 3 id and updated.
function I:ImportTRP3()
  local found = self:TRP3Profiles()
  if #found == 0 then return 0 end
  self.kept = 0
  local lib = { profiles = {}, bound = {}, order = {}, t = time() }
  for _, e in ipairs(found) do
    local name = UniqueName(lib.profiles, e.name)
    local p = self:Convert(e.prof)
    p.source = "trp3:" .. tostring(e.id)
    lib.profiles[name] = p
    lib.order[#lib.order + 1] = name
    for _, c in ipairs(e.chars) do lib.bound[c] = name end
  end
  K.db.migration.library = lib
  K.db.migration.imported = time()
  local count = self:ApplyLibrary(true)
  K:Fire("PROFILE")
  return count
end
-- Switch off the other addon (and its add-ons such as Total RP 3: Extended).
-- noSave: leave the list to be saved by the reload that follows, rather than
-- committing it here.
function I:DisableOther(other, noSave)
  local api = C_AddOns or {}
  local count = (api.GetNumAddOns or GetNumAddOns)()
  local getInfo = api.GetAddOnInfo or GetAddOnInfo
  local disable = api.DisableAddOn or DisableAddOn
  for i = 1, count do
    local name = getInfo(i)
    if name and (name == other or name:lower():find("^" .. other:lower() .. "_")) then pcall(disable, name) end
  end
  -- Commit it now, so cancelling the AddOns list later can't undo it.
  local save = not noSave and (api.SaveAddOns or SaveAddOns)
  if save then pcall(save) end
end

---------------------------------------------------------------------------
-- The "Move to Kinship" window
---------------------------------------------------------------------------
local W, H = 540, 440

function I:Build()
  if self.frame then return end
  local f = UI.Window("KinshipRPMove", "Move to Kinship", W, H)
  f:SetFrameStrata("DIALOG")
  self.frame = f
  local desk = UI.Desk(f)
  desk:SetPoint("TOPLEFT", 1, -35)
  desk:SetPoint("BOTTOMRIGHT", -1, 1)

  local mono = f:CreateTexture(nil, "ARTWORK")
  mono:SetTexture(K.MONOGRAM)
  mono:SetSize(72, 72)
  mono:SetPoint("TOPLEFT", 18, -46)
  f.title = UI.Text(f, "", "Huge", "deskHeading", W - 140)
  f.title:SetPoint("TOPLEFT", mono, "TOPRIGHT", 14, -10)
  f.sub = UI.Text(f, "", "Small", "deskSubtle", W - 140)
  f.sub:SetPoint("TOPLEFT", f.title, "BOTTOMLEFT", 0, -6)
  f.sub:SetSpacing(2)

  local card = UI.Panel(f)
  card:SetPoint("TOPLEFT", 18, -144)
  card:SetPoint("BOTTOMRIGHT", -18, 104)
  f.card = card
  f.what = UI.Section(card, "What comes across")
  f.what:SetPoint("TOPLEFT", 21, -15)
  f.body = UI.Text(card, "", "Small", "text", W - 76)
  f.body:SetPoint("TOPLEFT", 16, -40)
  f.body:SetSpacing(4)

  f.switch = UI.Toggle(f, "Switch it off afterwards",
    "Recommended. It takes effect after a reload. Its saved data stays untouched, so you can switch back.",
    function() return I.switchOff end, function(v) I.switchOff = v end, W - 36)
  f.switch:SetPoint("BOTTOMLEFT", 18, 52)

  f.go = UI.Button(f, "", 112, 28)
  f.go:SetPoint("BOTTOMRIGHT", -16, 14)
  f.later = UI.Button(f, "Not now", 100, 28)
  f.later:SetPoint("RIGHT", f.go, "LEFT", -8, 0)
end

function I:Show(fromSettings)
  local other = K.Comm:OtherRPAddon()
  if not other and not fromSettings then return end
  self:Build()
  local f = self.frame
  self.switchOff = true
  f.switch:Refresh()
  f.switch:Show()
  f.later:Show()
  f.later:SetText("Not now")
  f.later:SetScript("OnClick", function() K.db.migration.dismissed = time(); f:Hide() end)

  if not other then
    f.title:SetText("Kinship is in charge")
    f.sub:SetText("No other roleplay addon is running. Your profile, chat and tooltips are all Kinship's.")
    f.body:SetText("Nothing to move.")
    f.switch:Hide()
    f.later:Hide()
    f.go:SetText("Close")
    f.go:SetScript("OnClick", function() f:Hide() end)
    f:Show()
    return
  end

  local label = I.Label(other)
  f.title:SetText("Kinship replaces " .. label)
  if other == "totalRP3" and self:TRP3Available() then
    local found = self:TRP3Profiles()
    local names = {}
    for i, e in ipairs(found) do
      if i <= 4 then
        names[#names + 1] = "|cff" .. UI.Hex(K:Theme().heading) .. e.name .. "|r" .. (e.mine and "  (this character)" or "")
      end
    end
    if #found > 4 then names[#names + 1] = ("and %d more"):format(#found - 4) end
    if #found > 0 then
      f.sub:SetText(("Bring your %d %s across in one step. %s's own data stays untouched, so you can always go back.")
        :format(#found, #found == 1 and "profile" or "profiles", label))
    else
      f.sub:SetText(("%s has no profiles of yours to bring across. You can still switch it off so Kinship runs alone.")
        :format(label))
    end
    local t = K:Theme()
    local bullet = "|cff" .. UI.Hex(t.accent) .. "•|r  "
    f.body:SetText(table.concat({
      bullet .. "Names, titles, race, class, age, height, eyes, home and birthplace",
      bullet .. "Your About text, as Appearance, Personality and History",
      bullet .. "Currently, your out-of-character note, and your IC / OOC status",
      bullet .. "Glances, personality traits, pronouns, motto, house and RP style (as consent)",
      bullet .. "Your other characters pick up their own profile the first time they log in",
      "",
      (#names > 0 and ("Found: " .. table.concat(names, ", ")) or "No profiles found to bring across."),
    }, "\n"))
    f.what:SetText(#found > 0 and "What comes across" or "Why switch it off")
    if #found == 0 then
      f.body:SetText(("While %s runs, both addons write the profile other players see. Switching it off leaves Kinship in charge; "
        .. "its saved data stays untouched."):format(label))
    end
    f.go:SetText(#found > 0 and "Bring them across" or "Switch it off")
    f.go:SetWidth(#found > 0 and 150 or 120)
    f.go:SetScript("OnClick", function()
      local n = #found > 0 and I:ImportTRP3() or 0
      I:Finish(other, n)
    end)
  else
    f.what:SetText("Why switch it off")
    f.sub:SetText(("%s and Kinship both write the profile other players see, so only one should run."):format(label))
    f.body:SetText(("Kinship can't read %s's saved profile, so fill in your Profile page first, then switch %s off here. "
      .. "Its saved data stays untouched."):format(label, label))
    f.go:SetText("Switch it off")
    f.go:SetWidth(120)
    f.go:SetScript("OnClick", function() I:Finish(other, 0) end)
  end
  f:Show()
end

-- After importing: say what happened and offer the reload that completes the switch.
function I:Finish(other, count)
  local f = self.frame
  local label = I.Label(other)
  if self.switchOff then
    self:DisableOther(other)
    if other == "totalRP3" then K.db.settings.trp3Mode = "alone" end
  end
  f.title:SetText(count > 0 and "Welcome to Kinship" or "Almost done")
  local kept = self.kept or 0
  f.sub:SetText((count > 0 and ("%d %s brought across from %s."):format(count, count == 1 and "profile" or "profiles", label)
    or ("Nothing was imported from %s."):format(label))
    .. (kept > 0 and (" %d you'd already changed in Kinship %s kept as you left %s."):format(kept,
      kept == 1 and "was" or "were", kept == 1 and "it" or "them") or ""))
  f.body:SetText(self.switchOff
    and ("%s is switched off from your next reload. Reload now to finish moving, then open your journal with /kin."):format(label)
    or ("%s is still on. Both addons will write your profile until you switch it off in the AddOns list."):format(label))
  f.switch:Hide()
  f.later:SetText("Later")
  f.later:SetScript("OnClick", function() f:Hide() end)
  f.go:SetText(self.switchOff and "Reload now" or "Done")
  f.go:SetWidth(120)
  f.go:SetScript("OnClick", function()
    if I.switchOff then ReloadUI() else f:Hide(); K.Journal:Open("profile") end
  end)
  K:Print(f.sub:GetText())
end

---------------------------------------------------------------------------
-- Start-up: apply profiles imported on another character, then offer the move.
---------------------------------------------------------------------------
K:On("LOGIN", function()
  local n, active = I:ApplyLibrary()
  if n and n > 0 then
    K:Print(("Brought %d profile%s across from your Total RP 3 import%s."):format(n, n == 1 and "" or "s",
      active and (", and switched to \"" .. active .. "\"") or ""))
  end
  -- Only interrupt someone when there's actually something to bring across.
  -- (Settings > General > "Move to Kinship" is always there otherwise.)
  C_Timer.After(5, function()
    -- Already imported (perhaps on another character)? Don't ask again; Settings still offers it.
    if K:Compat() then return end   -- Compat.lua asks instead: alongside it, or on its own
    if K.db.migration.dismissed or K.db.migration.imported then return end
    if K.Comm:OtherRPAddon() == "totalRP3" and I:TRP3Available() and #I:TRP3Profiles() > 0 then I:Show() end
  end)
end)
