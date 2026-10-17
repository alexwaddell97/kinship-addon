-- Kinship RP: an entry in the game's Options > AddOns list, where players
-- look for an addon's settings. Kinship's settings live in its journal, so
-- the page is a short welcome with a button that opens them (closing the
-- game's Options on the way), and a few shortcuts.

local ADDON, ns = ...
local K = ns.K
local UI = K.UI
local O = {}
K.Options = O

-- Close the game's Options window (not back to the game menu), then open a journal page.
function O:OpenJournal(page)
  local sp = _G.SettingsPanel
  if sp and sp:IsShown() and not InCombatLockdown() then
    if sp.Close then pcall(sp.Close, sp, true) else pcall(HideUIPanel, sp) end
  end
  C_Timer.After(0, function() K.Journal:Open(page or "settings") end)
end

local function Build()
  if O.panel or not (Settings and Settings.RegisterCanvasLayoutCategory and Settings.RegisterAddOnCategory) then return end
  local f = CreateFrame("Frame")
  O.panel = f

  local logo = f:CreateTexture(nil, "ARTWORK")
  logo:SetTexture(K.ICON)
  logo:SetSize(56, 56)
  logo:SetPoint("TOPLEFT", 16, -18)
  local title = UI.Text(f, "Kinship RP", "Huge", "deskHeading")
  title:SetPoint("TOPLEFT", logo, "TOPRIGHT", 14, -6)
  local ver = UI.Text(f, "Version " .. tostring(K.VERSION or "?"), "Small", "deskSubtle")
  ver:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 1, -5)

  local blurb = UI.Text(f, "Your roleplay profile, the people you meet, your stories and the Warfront, all in one journal. "
    .. "Kinship keeps its settings there, with search, so everything is in one place.", "Body", "deskText", 520)
  blurb:SetPoint("TOPLEFT", logo, "BOTTOMLEFT", 2, -16)
  blurb:SetSpacing(3)

  local open = UI.Button(f, "Open Kinship settings", 220, 30)
  open:SetPoint("TOPLEFT", blurb, "BOTTOMLEFT", -2, -18)
  open:SetScript("OnClick", function() O:OpenJournal("settings") end)

  local row = {
    { "Open the journal", function() O:OpenJournal(nil) end },
    { "Edit your profile", function() O:OpenJournal("profile") end },
    { "Replay the welcome tour", function()
      O:OpenJournal(nil)
      C_Timer.After(0.4, function() if K.Guide then K.Guide:Start("journal", K.Journal, K.Journal.frame) end end)
    end },
  }
  local prev
  for _, r in ipairs(row) do
    local b = UI.Button(f, r[1], 170, 26)
    if prev then b:SetPoint("LEFT", prev, "RIGHT", 8, 0) else b:SetPoint("TOPLEFT", open, "BOTTOMLEFT", 0, -12) end
    b:SetScript("OnClick", r[2])
    prev = b
  end

  local tips = UI.Text(f, "/kin opens your journal  ·  /kin help lists every command  ·  "
    .. "Key Bindings > AddOns > Kinship RP has keys for the journal, the Parley wheel, dice and your status.", "Small", "deskSubtle", 540)
  tips:SetPoint("TOPLEFT", open, "BOTTOMLEFT", 0, -56)
  tips:SetSpacing(2)

  if K.Support then
    local kofi = K.Support.Link(f, true)
    kofi:SetPoint("TOPLEFT", tips, "BOTTOMLEFT", 0, -16)
  end

  local category = Settings.RegisterCanvasLayoutCategory(f, "Kinship RP")
  Settings.RegisterAddOnCategory(category)
  O.category = category
end

K:On("LOGIN", function() K.Try("options", Build) end)
