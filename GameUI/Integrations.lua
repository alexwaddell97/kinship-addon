-- Kinship RP: tooltips, right-click menus and the status button.

local ADDON, ns = ...
local K = ns.K
local UI = K.UI
local Safe = K.Safe

---------------------------------------------------------------------------
-- Tooltips
---------------------------------------------------------------------------
-- The roleplay name (with its short title) on the tooltip's first line, in
-- its player's colour or roleplay gold, and the character's own name on the
-- right of it in grey.
local function SetNameLine(tooltip, text, char, p)
  local base = tooltip.GetName and tooltip:GetName() or ""
  local fs = _G[base .. "TextLeft1"]
  if not (fs and text and text ~= "") then return end
  fs:SetText(text)
  fs:SetTextColor(K.NameColorOf(p))
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

-- A player's tooltip is a short card: who they are, how they're playing and
-- what they're up to. Holding Shift (or the "Everything" setting) adds the
-- rest, on a wider tooltip so it reads as paragraphs instead of a column.
-- Lines added by other files ask K:TooltipFull() and, when they hold back,
-- call K:TooltipMore() so the "Hold Shift" hint knows there is more.
local FULL_WIDTH = 320
local tip = { full = false, more = false, active = false, widened = false }
function K:TooltipFull() return tip.full end
function K:TooltipMore() tip.more = true end

local function WantFull()
  return K.Settings().tooltipDetail == "full" or IsShiftKeyDown()
end

local function Cut(text, n)
  text = strtrim((text or ""):gsub("%s+", " "))
  if #text <= n then return text end
  local cut = text:sub(1, n):match("^(.*)%s") or text:sub(1, n)
  return (cut:gsub("[\192-\255][\128-\191]*$", "")) .. "..."
end

local function Colored(text, c) return ("|cff%s%s|r"):format(UI.Hex(c), text) end

-- The people who make Kinship, by character name. Never by roleplay name:
-- anyone can choose that one.
local DEVELOPERS = { ["brennan black"] = true, ["mira moonshadow"] = true }
local function IsDeveloper(name)
  local key = K.NameKey(name)
  return key ~= nil and DEVELOPERS[(key:gsub("%-.*$", ""))] == true
end
local function AddDeveloperLine(tooltip, name)
  if IsDeveloper(name) then tooltip:AddLine(("|T%s:14:14|t Kinship developer"):format(K.ICON), 0.62, 0.90, 0.84) end
end

local function AddProfileLines(tooltip, name, p, other)
  local C = UI.Clean
  local full = tip.full
  -- Their roleplay name, or their own under a title ("Operative Brennan
  -- Black"), with the character's name on the right when it differs.
  local char = K:CharacterName(other and name or nil)
  local shown, own = K:ShownName(p, char)
  if shown then SetNameLine(tooltip, shown, not own and char or nil, p) end
  if p.epithet and p.epithet ~= "" then tooltip:AddLine(C(p.epithet), 0.30, 0.72, 0.68) end
  local who = strtrim(C(p.race) .. " " .. C(p.class))
  if who ~= "" then tooltip:AddLine(who, 0.75, 0.75, 0.75) end

  -- How they're playing, on one line: status, war stance, experience.
  local bits = {}
  local s = K.STATUS[p.status]
  if s then bits[#bits + 1] = Colored(s.label, s.color) end
  local stance = K.STANCES[p.stance or (other and "" or "duel")]
  if stance then
    bits[#bits + 1] = ("|T%s:14:14:0:0:64:64:5:59:5:59|t %s"):format(stance.icon, Colored(stance.label, stance.color))
  end
  local lv = K.Experience and K.Experience.Notable(p)
  if lv then bits[#bits + 1] = ("|T%s:14:14:0:0:64:64:5:59:5:59|t %s"):format(lv.icon, Colored(lv.tip, lv.color)) end
  if #bits > 0 then tooltip:AddLine(table.concat(bits, "   ")) end

  local currently = strtrim(C(p.currently or ""))
  local ooc = strtrim(C(p.ooc or ""))
  local hasHouse = p.house and strtrim(p.house) ~= ""
  local hasGroup = strtrim(C(p.group)) ~= ""
  -- Consent as coloured words (green yes, amber ask, red no)
  local words = {}
  for _, f in ipairs(K.CONSENT) do
    local v = p.consent and p.consent[f.key]
    for _, cv in ipairs(K.CONSENT_VALUES) do
      if cv.key == v and f.key ~= "RR" then words[#words + 1] = Colored(f.label, cv.color) end
    end
  end
  local hasConsent = #words > 0

  if not full then
    if currently ~= "" then
      local short = Cut(currently, 90)
      tooltip:AddLine("\"" .. short .. "\"", 0.85, 0.85, 0.85, true)
      if short ~= currently then tip.more = true end
    end
    if hasHouse or hasGroup or hasConsent or ooc ~= "" then tip.more = true end
    return
  end

  if hasHouse or hasGroup or hasConsent then tooltip:AddLine(" ") end
  if hasHouse then
    local h = K.db.houses[strtrim(p.house):lower()]
    local crest = p.crest or (h and h.crest) or "Interface\\Icons\\INV_Shield_05"
    local family = other and K:HouseKey() == strtrim(p.house):lower() and K:HouseState(name) == "recognised"
    tooltip:AddLine(("|T%s:14:14|t of House %s%s"):format(crest, strtrim(UI.Clean(p.house)), family and "  |cff5fd35f(your house)|r" or ""),
      0.94, 0.82, 0.54)
  end
  local group = strtrim(C(p.group))
  if group ~= "" then
    local g = K.db.groups[group:lower()]
    local crest = (other and p.groupCrest) or (g and g.crest) or K.GROUP_CREST
    local role = strtrim(C(p.groupRole))
    local ours = other and K:GroupKey() == group:lower() and K:GroupState(name) == "recognised"
    tooltip:AddLine(("|T%s:14:14|t %s%s%s"):format(crest, role ~= "" and (role .. ", ") or "", group,
      ours and "  |cff5fd35f(your group)|r" or ""), 0.94, 0.82, 0.54)
  end
  if hasConsent then tooltip:AddLine(table.concat(words, "  ·  ")) end
  if currently ~= "" or ooc ~= "" then tooltip:AddLine(" ") end
  if currently ~= "" then tooltip:AddLine("\"" .. currently .. "\"", 0.85, 0.85, 0.85, true) end
  if ooc ~= "" then tooltip:AddLine("|cff8c8c8cOOC:|r " .. ooc, 0.65, 0.65, 0.65, true) end
end

local function OnUnitTooltip(tooltip)
  if tooltip ~= GameTooltip or K:Compat() then return end   -- Total RP 3 draws its own
  local ok, _, unit = pcall(tooltip.GetUnit, tooltip)
  if not ok or not unit or not Safe(unit) or not UnitIsPlayer(unit) then return end
  tip.full, tip.more, tip.active, tip.tried = WantFull(), false, true, nil
  local function Extras(name, profile, isMe)
    for _, fn in ipairs(K.tooltipProviders) do
      local okP, err = pcall(fn, tooltip, unit, name, profile, isMe)
      if not okP then K:CaughtError("tooltip", err) end
    end
    if tip.full then
      if tooltip.SetMinimumWidth then tooltip:SetMinimumWidth(FULL_WIDTH); tip.widened = true end
    elseif tip.more then
      tooltip:AddLine("Hold Shift for more", 0.50, 0.50, 0.50)
    end
    tooltip:Show()
  end
  if UnitIsUnit(unit, "player") then
    AddProfileLines(tooltip, K:PlayerName(), K:Profile())
    AddDeveloperLine(tooltip, K:MyName())
    Extras(K:MyName(), K:Profile(), true)
    return
  end
  local name = GetUnitName(unit, true)
  if not Safe(name) or not name then return end
  if K:IsIgnored(name) then return end
  local reg = K:ProfileOf(name)
  if reg and reg.profile then AddProfileLines(tooltip, name, reg.profile, true) end
  AddDeveloperLine(tooltip, name)
  local e = K:KinFor(name)
  if e and not tip.full then
    tip.more = true
  elseif e then
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
  if note and not tip.full then
    tip.more = true
  elseif note then tooltip:AddLine("|TInterface\\Icons\\INV_Misc_Note_01:14:14:0:0:64:64:5:59:5:59|t " .. note, 0.75, 0.75, 0.75, true) end
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
  -- The Blizzard look: the HUD's bronze box (made once; flat when the client has none).
  b.hud = UI.Skin.Hud(b, 12)
  UI:OnTheme(function(t)
    local hud = t.skin == "blizzard" and b.hud
    if b.hud then b.hud:SetShown(hud) end
    b.bg:SetShown(not hud); b.edge:SetShown(not hud); b.bar:SetShown(not hud)
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
-- Pressing or letting go of Shift over a player redraws their tooltip on
-- the very next frame. The tooltip checks every frame while it's open
-- (cheap: one key test, and a unit lookup only when Shift no longer matches
-- what's drawn), so it never waits on the game's own slower refresh.
local function Watch(tt)
  if not tip.active then return end
  local want = WantFull()
  if want == tip.full or want == tip.tried then return end
  tip.tried = want   -- one go per press, even if the game won't redraw it
  local ok, _, unit = pcall(tt.GetUnit, tt)
  if not (ok and unit and Safe(unit)) then return end
  local okP, isPlayer = pcall(UnitIsPlayer, unit)
  if okP and Safe(isPlayer) and isPlayer then tt:SetUnit(unit) end
end

-- The tooltip is shared by everything: put its width back whenever it's
-- cleared, and stop watching Shift once it closes.
local function Reset(tt, closed)
  if closed then tip.active = false end
  if tip.widened then
    tip.widened = false
    if tt.SetMinimumWidth then tt:SetMinimumWidth(0) end
  end
end

K:On("LOGIN", function()
  if TooltipDataProcessor and Enum and Enum.TooltipDataType then
    TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Unit, function(tt) K.Try("tooltip", OnUnitTooltip, tt) end)
  end
  GameTooltip:HookScript("OnHide", function(tt) Reset(tt, true) end)
  if GameTooltip:HasScript("OnTooltipCleared") then GameTooltip:HookScript("OnTooltipCleared", function(tt) Reset(tt) end) end
  GameTooltip:HookScript("OnUpdate", function(tt) K.Try("tooltip", Watch, tt) end)
  SetupMenus()
  SB:Build()
  SB:Update()
  K.Try("minimap button", MinimapButton)
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

---------------------------------------------------------------------------
-- Settings
---------------------------------------------------------------------------
K:RegisterSettings({ id = "tooltips", trp3 = "hide", title = "Tooltips", order = 13,
  keywords = "mouseover hover shift short full detail crowded", build = function(card)
  card:Segments("When you mouse over a player", {
    { key = "short", label = "Short" },
    { key = "full", label = "Everything" },
  }, function() return K.Settings().tooltipDetail == "full" and "full" or "short" end,
  function(v) K.Settings().tooltipDetail = v == "full" and "full" or nil end, 100)
  card:Note("Short shows who they are, how they're playing and what they're up to. Hold Shift over them for "
    .. "everything else: house, group, consent, OOC notes, effects, mounts and your own notes.")
end })
