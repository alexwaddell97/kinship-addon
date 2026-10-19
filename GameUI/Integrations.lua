-- Kinship RP: tooltips, right-click menus and the status button.

local ADDON, ns = ...
local K = ns.K
local UI = K.UI
local Safe = K.Safe

---------------------------------------------------------------------------
-- Tooltips
---------------------------------------------------------------------------
-- The roleplay name (with its short title) on the tooltip's first line, in
-- roleplay gold, and the character's own name on the right of it in grey.
local function SetNameLine(tooltip, text, char)
  local base = tooltip.GetName and tooltip:GetName() or ""
  local fs = _G[base .. "TextLeft1"]
  if not (fs and text and text ~= "") then return end
  fs:SetText(text)
  fs:SetTextColor(unpack(K.RP_NAME_COLOR))
  if not char or char == "" or char:lower() == text:lower() then return end
  local right = _G[base .. "TextRight1"]
  if right then
    right:SetText(char)
    right:SetTextColor(unpack(K.CHAR_NAME_COLOR))
    right:Show()
  else
    tooltip:AddLine(char, unpack(K.CHAR_NAME_COLOR))
  end
end

local function AddProfileLines(tooltip, name, p, other)
  local C = UI.Clean
  if other then
    local rp = strtrim(C(p.rpName))
    if rp ~= "" then
      SetNameLine(tooltip, (p.prefix and p.prefix ~= "" and (C(p.prefix) .. " ") or "") .. rp, K:CharacterName(name))
    end
  elseif strtrim(p.rpName or "") ~= "" then
    SetNameLine(tooltip, K:DisplayName(p), K:CharacterName())
  end
  if p.epithet and p.epithet ~= "" then tooltip:AddLine(C(p.epithet), 0.30, 0.72, 0.68) end
  local who = strtrim(C(p.race) .. " " .. C(p.class))
  if who ~= "" then tooltip:AddLine(who, 0.75, 0.75, 0.75) end
  if p.house and strtrim(p.house) ~= "" then
    local h = K.db.houses[strtrim(p.house):lower()]
    local crest = p.crest or (h and h.crest) or "Interface\\Icons\\INV_Shield_05"
    local family = other and K:HouseKey() == strtrim(p.house):lower() and K:HouseState(name) == "recognised"
    tooltip:AddLine(("|T%s:14:14|t of House %s%s"):format(crest, strtrim(UI.Clean(p.house)), family and "  |cff5fd35f(your house)|r" or ""),
      0.94, 0.82, 0.54)
  end
  local s = K.STATUS[p.status]
  if s then tooltip:AddLine(s.label, unpack(s.color)) end
  local lv = K.Experience and K.Experience.Notable(p)
  if lv then tooltip:AddLine(("|T%s:14:14:0:0:64:64:5:59:5:59|t %s"):format(lv.icon, lv.tip), unpack(lv.color)) end
  -- War stance, then consent as coloured words (green yes, amber ask, red no)
  local stance = K.STANCES[p.stance or (other and "" or "duel")]
  if stance then
    tooltip:AddLine(("|T%s:14:14:0:0:64:64:5:59:5:59|t %s"):format(stance.icon, stance.label), unpack(stance.color))
  end
  local words = {}
  for _, f in ipairs(K.CONSENT) do
    local v = p.consent and p.consent[f.key]
    for _, cv in ipairs(K.CONSENT_VALUES) do
      if cv.key == v and f.key ~= "RR" then words[#words + 1] = ("|cff%s%s|r"):format(UI.Hex(cv.color), f.label) end
    end
  end
  if #words > 0 then tooltip:AddLine(table.concat(words, "  ·  ")) end
  if p.currently and p.currently ~= "" then
    tooltip:AddLine("\"" .. C(p.currently) .. "\"", 0.85, 0.85, 0.85, true)
  end
  if p.ooc and p.ooc ~= "" then
    tooltip:AddLine("|cff8c8c8cOOC:|r " .. C(p.ooc), 0.65, 0.65, 0.65, true)
  end
end

local function OnUnitTooltip(tooltip)
  if tooltip ~= GameTooltip or K:Compat() then return end   -- Total RP 3 draws its own
  local ok, _, unit = pcall(tooltip.GetUnit, tooltip)
  if not ok or not unit or not Safe(unit) or not UnitIsPlayer(unit) then return end
  local function Extras(name, profile, isMe)
    for _, fn in ipairs(K.tooltipProviders) do
      local okP, err = pcall(fn, tooltip, unit, name, profile, isMe)
      if not okP then K:CaughtError("tooltip", err) end
    end
    tooltip:Show()
  end
  if UnitIsUnit(unit, "player") then
    AddProfileLines(tooltip, K:PlayerName(), K:Profile())
    Extras(K:MyName(), K:Profile(), true)
    return
  end
  local name = GetUnitName(unit, true)
  if not Safe(name) or not name then return end
  if K:IsIgnored(name) then return end
  local reg = K:ProfileOf(name)
  if reg and reg.profile then AddProfileLines(tooltip, name, reg.profile, true) end
  local e = K:KinFor(name)
  if e then
    local m = e.met or {}
    tooltip:AddLine(("|T%s:14:14|t %s - met in %s, level %d"):format(K.ICON, K.RelationLabel(e.rel), m.place or "?", m.level or 0),
      0.80, 0.71, 0.51)
  end
  -- Your history with them (works for the other faction too: it's your own record)
  local W = K.War
  if W and K.db.settings.warTooltip then
    local r = W:Get(name)
    if r and W:IsRival(r) then
      local g = W.Grudge(r.grudge)
      local gc = g and g.color or { 0.85, 0.85, 0.85 }
      local fought = (r.wins or 0) + (r.losses or 0) > 0
      tooltip:AddLine(("|T%s:14:14|t |cff%s%s|r%s"):format(K.Art("IconDungeon"), UI.Hex(gc), g and g.label or "Rival",
        fought and ("   " .. W:Tally(r)) or ""), 0.85, 0.85, 0.85)
    end
  end
  local note = K.db.notes[K.NameKey(name) or ""]
  if note then tooltip:AddLine("|TInterface\\Icons\\INV_Misc_Note_01:14:14:0:0:64:64:5:59:5:59|t " .. note, 0.75, 0.75, 0.75, true) end
  Extras(name, reg and reg.profile, false)
end

---------------------------------------------------------------------------
-- Right-click menus
---------------------------------------------------------------------------
local function SetupMenus()
  if not (Menu and Menu.ModifyMenu) then return end
  local function modify(_, root, ctx)
    if not ctx or not ctx.name or not Safe(ctx.name) then return end
    -- The target menu is shared with NPCs and mobs: Kinship only belongs on players'.
    if ctx.unit then
      local ok, isPlayer = pcall(UnitIsPlayer, ctx.unit)
      if not ok or not Safe(isPlayer) or not isPlayer then return end
    end
    local name = ctx.name
    if ctx.server and ctx.server ~= "" and not name:find("-", 1, true) then name = name .. "-" .. ctx.server end
    local unitIsMe = ctx.unit and UnitIsUnit(ctx.unit, "player")
    local isMe = (Safe(unitIsMe) and unitIsMe) or K:IsMe(name) or K:IsMe(ctx.name)

    root:CreateDivider()
    root:CreateTitle(("|T%s:14:14|t Kinship"):format(K.ICON))
    root:CreateButton(isMe and "View my profile" or "View roleplay profile", function()
      if isMe then K:ViewProfile() else K:ViewProfile(name, ctx.unit) end
    end)
    if not isMe then
      root:CreateButton("Write a letter", function() K.Letters:Compose(name) end)
      if K.Relations then K.Relations:FillMenu(root:CreateButton("Relationship"), name) end
      if K.Safety and not K:IsIgnored(name) then
        root:CreateButton("Ignore profile...", function() K.Safety:ConfirmIgnore(name) end)
      end
      local e = K:KinFor(name)
      if e then
        if not K.Relations then
          root:CreateButton("Bond: " .. K.RelationLabel(e.rel) .. "...", function() K.Journal:Open("kin") end)
        end
      else
        root:CreateButton("Add to Kin", function()
          if ctx.unit and UnitExists(ctx.unit) then K:MeetUnit(ctx.unit, "manual") else K:AddKinByName(name) end
          K:Print("Added " .. name .. " to your Kin.")
        end)
      end
    end
  end
  for _, tag in ipairs({ "MENU_UNIT_FRIEND", "MENU_UNIT_PLAYER", "MENU_UNIT_ENEMY_PLAYER", "MENU_UNIT_TARGET",
                         "MENU_UNIT_PARTY", "MENU_UNIT_RAID_PLAYER", "MENU_UNIT_SELF" }) do
    K.Try("menus", Menu.ModifyMenu, tag, modify)
  end
end

---------------------------------------------------------------------------
-- Status button: a small movable badge showing IC / LFRP / OOC
---------------------------------------------------------------------------
local SB = {}
K.StatusButton = SB

function SB:Build()
  local b = CreateFrame("Button", "KinshipRPStatusButton", UIParent)
  b:SetSize(92, 26)
  b:SetFrameStrata("MEDIUM")
  b:SetClampedToScreen(true)
  b:SetMovable(true)
  b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  b:RegisterForDrag("LeftButton")
  b.bg = b:CreateTexture(nil, "BACKGROUND")
  b.bg:SetAllPoints()
  b.edge = UI.Border(b)
  b.bar = b:CreateTexture(nil, "ARTWORK")   -- status colour along the left edge
  b.bar:SetTexture("Interface\\Buttons\\WHITE8X8")
  b.bar:SetWidth(2)
  b.bar:SetPoint("TOPLEFT")
  b.bar:SetPoint("BOTTOMLEFT")
  b.icon = b:CreateTexture(nil, "ARTWORK")
  b.icon:SetTexture(K.ICON)
  b.icon:SetSize(16, 16)
  b.icon:SetPoint("LEFT", 8, 0)
  b.gem = UI.Gem(b, 12)
  b.gem:SetPoint("LEFT", b.icon, "RIGHT", 5, 0)
  b.text = UI.Text(b, "", "Small", "deskText")
  b.text:SetPoint("LEFT", b.gem, "RIGHT", 5, 0)
  b:SetHighlightTexture("Interface\\Buttons\\WHITE8X8", "ADD")
  b:GetHighlightTexture():SetVertexColor(1, 1, 1, 0.06)
  UI:OnTheme(function(t)
    b.bg:SetColorTexture(unpack(t.chrome))
    b.edge:SetColor(unpack(t.chromeEdge))
  end)

  b:SetScript("OnDragStart", function(self) if IsShiftKeyDown() then self:StartMoving() end end)
  b:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    local point, _, relPoint, x, y = self:GetPoint()
    K.db.statusButton.pos = { point, relPoint, x, y }
  end)
  b:SetScript("OnClick", function(_, button)
    if button == "RightButton" then K.Journal:Toggle() else K:CycleStatus() end
  end)
  b:SetScript("OnEnter", function(self)
    local s = K.STATUS[K:Profile().status]
    GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
    GameTooltip:SetText(("|T%s:14:14|t Kinship"):format(K.ICON))
    GameTooltip:AddLine(s.label, unpack(s.color))
    GameTooltip:AddLine(" ")
    GameTooltip:AddLine("Click: change status", 0.8, 0.8, 0.8)
    GameTooltip:AddLine("Right-click: open your journal", 0.8, 0.8, 0.8)
    GameTooltip:AddLine("Shift+drag: move", 0.8, 0.8, 0.8)
    GameTooltip:Show()
  end)
  b:SetScript("OnLeave", function() GameTooltip:Hide() end)

  local pos = K.db.statusButton.pos
  b:ClearAllPoints()
  if pos then b:SetPoint(pos[1], UIParent, pos[2], pos[3], pos[4])
  else b:SetPoint("TOP", UIParent, "TOP", 0, -8) end
  self.button = b
end

function SB:Update()
  local b = self.button
  if not b then return end
  b:SetShown(K.db.statusButton.shown and not K:Compat())   -- Total RP 3's toolbar sets status alongside it
  local status = K:Profile().status
  b.gem:SetStatus(status)
  b.text:SetText(K.STATUS[status].short)
  b.bar:SetVertexColor(unpack(K.STATUS[status].color))
end

---------------------------------------------------------------------------
-- A Kinship button in the game menu (Esc), just below AddOns. The menu adds
-- it as one of its own buttons, so the game lays it out and sizes the menu,
-- and whatever skins the menu (EllesmereUI, GW2 UI, ElvUI...) styles it like
-- the rest. Nothing of the menu's is moved or resized by Kinship.
---------------------------------------------------------------------------
local function GameMenuButton()
  local menu = rawget(_G, "GameMenuFrame")
  if not (menu and type(menu.AddButton) == "function") then return end
  local adding = false
  hooksecurefunc(menu, "AddButton", function(self, text)
    if adding or text ~= (ADDONS or "AddOns") then return end
    if K.db.settings.gameMenuButton == false then return end
    adding = true
    local ok, err = pcall(self.AddButton, self, "Kinship", function()
      HideUIPanel(self)
      K.Journal:Toggle()
    end)
    adding = false
    if not ok then K:CaughtError("game menu", err) end
  end)
end

---------------------------------------------------------------------------
-- The minimap button (LibDBIcon, so minimap button collectors pick it up):
-- click for your journal, right-click for Settings.
---------------------------------------------------------------------------
local function MinimapButton()
  local ldb = LibStub and LibStub("LibDataBroker-1.1", true)
  local icon = LibStub and LibStub("LibDBIcon-1.0", true)
  if not (ldb and icon) then return end
  K.db.minimap = K.db.minimap or { hide = false }
  local obj = ldb:NewDataObject("KinshipRP", {
    type = "launcher", text = "Kinship", icon = K.ICON,
    OnClick = function(_, button)
      if button == "RightButton" then K.Journal:Open("settings") else K.Journal:Toggle() end
    end,
    OnTooltipShow = function(tt)
      tt:AddLine("Kinship", 1, 0.82, 0)
      tt:AddLine("Click to open your journal.", 1, 1, 1)
      tt:AddLine("Right-click for Settings.", 0.62, 0.62, 0.62)
    end,
  })
  if obj then icon:Register("KinshipRP", obj, K.db.minimap) end
  K.MinimapIcon = icon
end

function K:SetMinimapButton(shown)
  K.db.minimap = K.db.minimap or {}
  K.db.minimap.hide = not shown
  if K.MinimapIcon then
    if shown then K.MinimapIcon:Show("KinshipRP") else K.MinimapIcon:Hide("KinshipRP") end
  end
end

---------------------------------------------------------------------------
-- Start-up
---------------------------------------------------------------------------
K:On("LOGIN", function()
  if TooltipDataProcessor and Enum and Enum.TooltipDataType then
    TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Unit, function(tt) K.Try("tooltip", OnUnitTooltip, tt) end)
  end
  SetupMenus()
  SB:Build()
  SB:Update()
  K.Try("minimap button", MinimapButton)
  K.Try("game menu", GameMenuButton)
end)

K:On("PROFILE", function() SB:Update() end)

---------------------------------------------------------------------------
-- Key bindings (Key Bindings > AddOns > Kinship RP)
---------------------------------------------------------------------------
function KinshipRP_DiceKey() if K.Dice then K.Dice:Toggle() end end
function KinshipRP_StatusKey()
  K:CycleStatus()
  K:Print("Status: " .. K.STATUS[K:Profile().status].label)
end
function KinshipRP_ViewKey()
  K:ViewUnitProfile("target")
end
_G["BINDING_NAME_KINSHIPRP_DICE"] = "Dice tray"
_G["BINDING_NAME_KINSHIPRP_STATUS"] = "Cycle IC / LFRP / OOC"
_G["BINDING_NAME_KINSHIPRP_VIEW"] = "View your target's profile"
