-- Kinship RP: alongside Total RP 3. When both are loaded, Kinship asks once
-- whether to run on its own (bring Total RP 3's profiles across, then switch
-- it off: Import.lua) or alongside it. Alongside it (K:Compat()), Total RP 3
-- keeps profiles, tooltips, nameplates, chat names, its status toolbar, the
-- target bar and its map scan; Kinship hides its own versions of those and
-- keeps everything Total RP 3 doesn't have. Kinship never loads or needs
-- Total RP 3: it only notices it's there.
-- With Total RP 3: Extended loaded too, the same window asks who looks after
-- items, documents and effects: Kinship (and Extended can be switched off),
-- or Extended (and Kinship switches its own off, keeping quests and the rest).
-- Your details come from what Total RP 3 shares, into a Kinship profile of
-- their own ("Total RP 3: <its profile>") that follows Total RP 3's current
-- profile. Your Kinship profiles stay exactly as they were, and come back
-- when Kinship runs on its own again.

local ADDON, ns = ...
local K = ns.K
local UI = K.UI
local T = {}
K.TRP3 = T

-- What you gain by keeping Kinship alongside Total RP 3
T.GAINS = {
  { "Quests you write", "Offer them to the players around you, with objectives that tick themselves." },
  { "What you wear", "Roleplay items in a slot for every piece of gear, and outfits to change into." },
  { "Your stage", "A backdrop, light and floor behind your character when someone opens your profile." },
  { "Houses", "A crest, motto and shared history for the family name you carry." },
  { "Warfront", "Your war stance, the rivals you've met and the battles you've fought, and Parley across the line." },
  { "Items and letters", "Design items, write sealed letters, trade them and leave stashes in the world." },
  { "And more", "Effects, gatherings on the calendar, dice, the satchel and a Roleplay tab on your character sheet." },
}

-- What Total RP 3 looks after while it runs
T.KEEPS = "your profile, tooltips, nameplates, chat names, status and target bar"

---------------------------------------------------------------------------
-- Your details, from what Total RP 3 shares
---------------------------------------------------------------------------
local MIRROR = { "rpName", "prefix", "nickname", "race", "class", "eyes", "birthplace", "ooc", "epithet", "house",
                 "pronouns", "age", "height", "home", "motto", "currently", "appearance", "history", "personality", "status" }
local CONSENT_KEYS = { "RI", "RD", "RO", "RM", "RR" }

local function Plain(s)
  if type(s) ~= "string" then return s end
  return (s:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""))
end

-- The Kinship profile that follows Total RP 3's current one
function T:ProfileName()
  local api = rawget(_G, "TRP3_API")
  local ok, prof = pcall(function() return api.profile.getPlayerCurrentProfile() end)
  local n = ok and type(prof) == "table" and prof.profileName
  return "Total RP 3: " .. ((type(n) == "string" and n ~= "") and n or "Main")
end

function T:Mirror()
  local my = rawget(_G, "msp") and msp.my
  if T.moving or not (K:Compat() and K.db and my and my.VA and my.VA ~= "" and K.Comm and K.Comm.BuildProfile) then return end
  local mine = K:MyProfiles()
  local name = self:ProfileName()
  local cur = mine.list[mine.active]
  -- Remember the Kinship profile you were using, to come back to later.
  if cur and not cur.trp3 then
    K.db.trp3Before = K.db.trp3Before or {}
    K.db.trp3Before[K:CharKey()] = mine.active
  end
  local made = false
  if not mine.list[name] then
    -- Carries over Kinship's own extras (stance, stage, outfits' ties...) from the one in use.
    K:NewProfile(name, true)
    made = true
  end
  local p = mine.list[name]
  p.trp3 = true
  local fresh = K.Comm.BuildProfile(my)
  local changed = made
  for _, key in ipairs(MIRROR) do
    local v = fresh[key]
    if key == "rpName" or key == "class" or key == "eyes" then v = Plain(v) end
    if v == "" then v = nil end
    if p[key] ~= v then p[key] = v; changed = true end
  end
  local c = fresh.consent or {}
  p.consent = p.consent or {}
  for _, f in ipairs(CONSENT_KEYS) do
    if p.consent[f] ~= c[f] then p.consent[f] = c[f]; changed = true end
  end
  if mine.active ~= name then K:SwitchProfile(name)
  elseif changed then K:Fire("PROFILE") end
end

-- Move to Kinship in one step: your Total RP 3 profiles come across, Total RP 3
-- and its add-ons (Extended too) are switched off, and the game reloads to finish.
-- Total RP 3's saved data is never touched, so switching it back on undoes it.
function T:MoveToKinship()
  T.moving = true   -- stop following Total RP 3, so nothing switches back before the reload
  local I = K.Import
  local n = 0
  if I and I:TRP3Available() and #I:TRP3Profiles() > 0 then n = I:ImportTRP3() or 0 end
  if I then I:DisableOther("totalRP3", true) end
  K.db.settings.trp3Mode = "alone"
  K.db.settings.trp3Ext = nil
  K.db.migration = K.db.migration or {}
  K.db.migration.moved = { n = n, t = time() }
  -- The game's own popup does the reload: a click of its button, which the game
  -- always allows, where a reload straight from here can be blocked.
  StaticPopup_Show("KINSHIPRP_TOGETHER_RELOAD", ((n > 0 and ("%d %s came across. "):format(n, n == 1 and "profile" or "profiles"))
    or "") .. "Total RP 3 and its add-ons switch off when you reload.\n\n(Or type /reload.)")
end

-- Back to your own Kinship profile when Total RP 3 isn't running.
local function ComeBack()
  if K:Compat() then return end
  local mine = K:MyProfiles()
  local cur = mine.list[mine.active]
  local before = K.db.trp3Before and K.db.trp3Before[K:CharKey()]
  if cur and cur.trp3 and before and mine.list[before] then K:SwitchProfile(before) end
  -- Moved to Kinship: the profiles that only followed Total RP 3 aren't needed now
  -- (the real ones came across), so they go, as long as one of your own is in use.
  if K.db.settings.trp3Mode == "alone" and not (mine.list[mine.active] or {}).trp3 then
    for _, name in ipairs(K:ProfileNames()) do
      if mine.list[name] and mine.list[name].trp3 then K:DeleteProfile(name) end
    end
  end
  local moved = K.db.migration and K.db.migration.moved
  if moved then
    K.db.migration.moved = nil
    C_Timer.After(3, function()
      K:Print(((moved.n or 0) > 0 and ("Welcome to Kinship. %d %s came across from Total RP 3, "):format(moved.n,
        moved.n == 1 and "profile" or "profiles") or "Welcome to Kinship. ")
        .. "Total RP 3 is off, with its saved data untouched: switch it back on in the AddOns list any time. Open your journal with /kin.")
    end)
  end
end

-- Where to write your profile: Kinship's Profile page, or alongside Total RP 3,
-- your character in Total RP 3's own window.
function K:OpenProfileEditor()
  if K:Compat() then
    local api = rawget(_G, "TRP3_API")
    local ok = pcall(function()
      api.navigation.openMainFrame()
      api.navigation.menu.selectMenu("main_12_player_character")
    end)
    if not ok then K:Print("Your profile is in Total RP 3: open it from its button or with /trp3.") end
  else
    K.Journal:Open("profile")
  end
end

-- Open someone's profile (yours with no name). Alongside Total RP 3 that's
-- its profile window, as theirs is the profile people wrote; Kinship's own
-- window is still a click away on Total RP 3's target bar, for what they
-- wear, their house and their stage. Falls back to Kinship's window for
-- anyone Total RP 3 doesn't know.
function K:ViewProfile(name, unit)
  local mine = not name or K.NameKey(name) == K.NameKey(K:MyName())
  if K:Compat() then
    local api = rawget(_G, "TRP3_API")
    local ok, shown = pcall(function()
      if mine then
        api.navigation.openMainFrame()
        api.navigation.menu.selectMenu("main_12_player_character")
        return true
      end
      local id = name
      if not id:find("-", 1, true) then id = id .. "-" .. (GetNormalizedRealmName() or "") end
      if not (api.register.isUnitIDKnown(id) and api.register.hasProfile(id)) then return false end
      api.navigation.openMainFrame()
      api.register.openPageByUnitID(id)
      return true
    end)
    if ok and shown then return end
  end
  if mine then K.Viewer:ShowSelf()
  elseif unit then K.Viewer:ShowName(name, unit)
  else K.Viewer:ShowName(name) end
end

function K:ViewUnitProfile(unit)
  if not (UnitExists(unit) and UnitIsPlayer(unit)) then return K:ViewProfile() end
  if UnitIsUnit(unit, "player") then return K:ViewProfile() end
  if K:Compat() then return K:ViewProfile(GetUnitName(unit, true), unit) end
  K.Viewer:ShowUnit(unit)
end

---------------------------------------------------------------------------
-- A Kinship button on Total RP 3's target bar: what they wear, their house
-- and stage, in Kinship's own window. Registered while Total RP 3 loads,
-- the only time it takes new buttons.
---------------------------------------------------------------------------
local function HookTargetBar()
  local api, addon = rawget(_G, "TRP3_API"), rawget(_G, "TRP3_Addon")
  if not (api and api.RegisterCallback and addon and addon.Events and addon.Events.WORKFLOW_ON_LOADED) then return end
  api.RegisterCallback(addon, addon.Events.WORKFLOW_ON_LOADED, function()
    if not (api.target and api.target.registerButton) then return end   -- its target bar is switched off
    local enums = rawget(_G, "AddOn_TotalRP3") and AddOn_TotalRP3.Enums
    pcall(api.target.registerButton, {
      id = "zz_kinship",
      configText = "Kinship: what they wear, their house and their stage",
      onlyForType = enums and enums.UNIT_TYPE and enums.UNIT_TYPE.CHARACTER or nil,
      condition = function() return K:Compat() end,
      onClick = function(unitID)
        if UnitExists("target") and UnitIsPlayer("target") then K.Viewer:ShowUnit("target") else K.Viewer:ShowName(unitID) end
      end,
      tooltip = "Kinship",
      tooltipSub = "Click to see what they wear, their house and their stage.",
      icon = "INV_Misc_Lantern_01",
    })
  end)
end

local ev = CreateFrame("Frame")
ev:RegisterEvent("ADDON_LOADED")
ev:SetScript("OnEvent", function(self, _, name)
  if name == "totalRP3" then
    self:UnregisterEvent("ADDON_LOADED")
    K.Try("trp3 target bar", HookTargetBar)
  end
end)

---------------------------------------------------------------------------
-- Total RP 3: Extended: whose items, documents and effects
---------------------------------------------------------------------------
-- Kinship's modules that Extended has its own of
T.EXT_SHARED = { "inventory", "documents", "auras" }

function K:ExtendedLoaded()
  local loaded = (C_AddOns and C_AddOns.IsAddOnLoaded) or rawget(_G, "IsAddOnLoaded")
  if not loaded then return false end
  local ok, v = pcall(loaded, "totalRP3_Extended")
  return ok and v and true or false
end

StaticPopupDialogs["KINSHIPRP_TOGETHER_RELOAD"] = {
  text = "%s",
  showAlert = true,
  button1 = "Reload now", button2 = "Later",
  OnAccept = function() ReloadUI() end,
  timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
}

-- Apply who looks after them. Returns what needs a reload, as a sentence, or nil.
function T:ApplyExtended(who, switchOff)
  local was = K.db.settings.trp3Ext
  K.db.settings.trp3Ext = who
  if who == "extended" then
    for _, m in ipairs(T.EXT_SHARED) do K:SetExt(m, false) end
    return nil
  end
  local reload = {}
  if was == "extended" then
    for _, m in ipairs(T.EXT_SHARED) do K:SetExt(m, true) end
    reload[#reload + 1] = "Kinship's items, documents and effects come back"
  end
  if switchOff and K:ExtendedLoaded() and K.Import then
    K.Import:DisableOther("totalRP3_Extended")
    reload[#reload + 1] = "Total RP 3: Extended switches off (its saved data stays)"
  end
  return #reload > 0 and (table.concat(reload, ", and ") .. " when you reload.") or nil
end

-- Extended switched off since you chose it: Kinship's own come back.
local function ExtendedGone()
  if K.db.settings.trp3Ext ~= "extended" or K:ExtendedLoaded() then return end
  for _, m in ipairs(T.EXT_SHARED) do K:SetExt(m, true) end
  K.db.settings.trp3Ext = nil
  K:Print("Total RP 3: Extended isn't running, so Kinship's items, documents and effects are back on from your next reload.")
end

---------------------------------------------------------------------------
-- The choice: Kinship on its own, or alongside Total RP 3
---------------------------------------------------------------------------
local W, H, EXT_H = 560, 516, 206

function T:Build()
  if self.frame then return self.frame end
  local f = UI.Window("KinshipRPTogether", "Kinship and Total RP 3", W, H)
  f:SetFrameStrata("DIALOG")
  self.frame = f
  local desk = UI.Desk(f)
  desk:SetPoint("TOPLEFT", 1, -35)
  desk:SetPoint("BOTTOMRIGHT", -1, 1)

  local mono = f:CreateTexture(nil, "ARTWORK")
  mono:SetTexture(K.MONOGRAM)
  mono:SetSize(64, 64)
  mono:SetPoint("TOPLEFT", 18, -48)
  f.title = UI.Text(f, "Total RP 3 is running too", "Huge", "deskHeading", W - 130)
  f.title:SetPoint("TOPLEFT", mono, "TOPRIGHT", 14, -8)
  f.sub = UI.Text(f, "Kinship can work alongside it, or take over from it. You can change your mind later in Settings > General.",
    "Small", "deskSubtle", W - 130)
  f.sub:SetPoint("TOPLEFT", f.title, "BOTTOMLEFT", 0, -6)
  f.sub:SetSpacing(2)

  local card = UI.Panel(f)
  card:SetPoint("TOPLEFT", 18, -132)
  card:SetPoint("BOTTOMRIGHT", -18, 60)
  f.card = card
  local head = UI.Section(card, "Keeping both")
  head:SetPoint("TOPLEFT", 21, -15)
  f.intro = UI.Text(card, ("Total RP 3 looks after %s. Kinship hides its own and adds what Total RP 3 doesn't have:"):format(T.KEEPS),
    "Small", "text", W - 76)
  f.intro:SetPoint("TOPLEFT", 16, -40)
  f.intro:SetSpacing(3)
  f.gains = UI.Text(card, "", "Small", "text", W - 76)
  f.gains:SetPoint("TOPLEFT", f.intro, "BOTTOMLEFT", 0, -10)
  f.gains:SetSpacing(4)
  f.alone = UI.Text(card, "Or move to Kinship: it brings your Total RP 3 profiles across, switches Total RP 3 and its add-ons "
    .. "(Extended too) off, and reloads. Their saved data stays untouched, so you can always go back.", "Small", "subtle", W - 76)
  f.alone:SetPoint("BOTTOMLEFT", 16, 14)
  f.alone:SetSpacing(2)

  -- With Extended loaded too: whose items, documents and effects
  local ext = UI.Panel(f)
  ext:SetPoint("BOTTOMLEFT", 18, 60)
  ext:SetPoint("BOTTOMRIGHT", -18, 60)
  ext:SetHeight(EXT_H - 12)
  f.ext = ext
  local eh = UI.Section(ext, "Total RP 3: Extended is running too")
  eh:SetPoint("TOPLEFT", 21, -15)
  local ask = UI.Text(ext, "Who looks after items, documents and effects?", "Small", "text", W - 76)
  ask:SetPoint("TOPLEFT", 16, -40)
  f.extPick = UI.Segments(ext, { { key = "kinship", label = "Kinship" }, { key = "extended", label = "Total RP 3: Extended" } },
    120, function(key) f.extWho = key; T:PaintExtended() end)
  f.extPick:Fit(110)
  f.extPick:SetPoint("TOPLEFT", 16, -60)
  f.extWhy = UI.Text(ext, "", "Small", "subtle", W - 76)
  f.extWhy:SetPoint("TOPLEFT", 16, -92)
  f.extWhy:SetSpacing(2)
  f.extOff = UI.Toggle(ext, "Switch Total RP 3: Extended off",
    "After a reload. Its saved data stays, so you can switch it back on.",
    function() return f.extSwitchOff end, function(v) f.extSwitchOff = v end, W - 76, true)
  f.extOff:SetPoint("BOTTOMLEFT", 16, 10)

  f.keep = UI.Button(f, "Keep both", 120, 28)
  f.keep:SetPoint("BOTTOMRIGHT", -18, 18)
  f.keep:SetScript("OnClick", function()
    K.db.settings.trp3Mode = "together"
    local reload = f.ext:IsShown() and T:ApplyExtended(f.extWho, f.extWho == "kinship" and f.extSwitchOff) or nil
    f:Hide()
    K:Print(("Kinship is working alongside Total RP 3. Total RP 3 keeps %s; the rest is in your journal (/kin)."):format(T.KEEPS))
    if f.ext:IsShown() and f.extWho == "extended" then
      K:Print("Total RP 3: Extended looks after items, documents and effects. Kinship's are off; quests, houses, Warfront and the rest stay.")
    end
    if reload then StaticPopup_Show("KINSHIPRP_TOGETHER_RELOAD", reload) end
  end)
  f.move = UI.Button(f, "Move to Kinship", 140, 28)
  f.move:SetPoint("RIGHT", f.keep, "LEFT", -8, 0)
  f.move:SetScript("OnClick", function()
    f:Hide()
    T:MoveToKinship()
  end)
  UI.Tooltip(f.move, "Move to Kinship", "Brings your Total RP 3 profiles across, switches Total RP 3 and its add-ons off, "
    .. "and reloads the game.")
  f.later = UI.Button(f, "Decide later", 110, 28)
  f.later:SetPoint("BOTTOMLEFT", 18, 18)
  f.later:SetScript("OnClick", function() f:Hide() end)
  return f
end

-- The line under the choice, and the switch-off only when Kinship keeps them
function T:PaintExtended()
  local f = self.frame
  f.extPick:Select(f.extWho)
  if f.extWho == "extended" then
    f.extWhy:SetText("Kinship switches off its items, documents and effects. Worn items and outfits go with them, since they're "
      .. "built on Kinship's items. Quests, houses, Warfront and the rest stay.")
    f.extOff:Hide()
  else
    f.extWhy:SetText("Worn items, outfits, quest rewards and stashes are built on Kinship's items. Extended's own items and "
      .. "documents can still come across through Inventory > Database.")
    f.extOff:Show()
    f.extOff:Refresh()
  end
end

function T:Show()
  local f = self:Build()
  -- The Extended question, when it's loaded
  local ext = K:ExtendedLoaded()
  f.ext:SetShown(ext)
  f:SetHeight(ext and (H + EXT_H) or H)
  f.card:ClearAllPoints()
  f.card:SetPoint("TOPLEFT", 18, -132)
  f.card:SetPoint("BOTTOMRIGHT", -18, ext and (60 + EXT_H) or 60)
  if ext then
    f.extWho = K.db.settings.trp3Ext or "kinship"
    if f.extSwitchOff == nil then f.extSwitchOff = true end
    self:PaintExtended()
  end
  local t = K:Theme()
  local gold, bullet = UI.Hex(t.heading), "|cff" .. UI.Hex(t.accent) .. "•|r  "
  local lines = {}
  for _, g in ipairs(T.GAINS) do lines[#lines + 1] = bullet .. "|cff" .. gold .. g[1] .. "|r  " .. g[2] end
  f.gains:SetText(table.concat(lines, "\n"))
  f:Show()
  f:Raise()
end

---------------------------------------------------------------------------
-- Start-up
---------------------------------------------------------------------------
K:On("LOGIN", function()
  ExtendedGone()
  if not K:Compat() then
    ComeBack()
    return
  end
  -- Follow Total RP 3 whenever it updates what it shares (it calls msp:Update).
  local lib = rawget(_G, "msp")
  if lib and type(lib.Update) == "function" then
    hooksecurefunc(lib, "Update", function()
      if T.mirroring then return end
      T.mirroring = true
      K.Try("trp3 mirror", T.Mirror, T)
      T.mirroring = false
    end)
  end
  for _, delay in ipairs({ 2, 8 }) do C_Timer.After(delay, function() K.Try("trp3 mirror", T.Mirror, T) end) end
  -- Ask once (again if you said "Decide later").
  C_Timer.After(6, function()
    -- Also once Extended turns up after you'd chosen
    local extUnasked = K:ExtendedLoaded() and K.db.settings.trp3Ext == nil
    if (K.db.settings.trp3Mode ~= "together" or extUnasked) and not InCombatLockdown() then T:Show() end
  end)
end)
