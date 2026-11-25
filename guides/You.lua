-- Kinship RP: guided tours for the journal itself, the You pages (Profile,
-- Persona, Companions), the Roleplay pane on the character sheet, the target
-- bar and the profile viewer. See Guide.lua for how tours work.
local _, ns = ...
local Loc = ns.L
local K = ns.K

-- One lit area around several regions (a row of icons, a group of fields).
-- Hidden or missing regions are left out; nil when none of them is showing.
-- The box is an empty frame on UIParent, placed afresh each time the tour
-- measures, so it follows the regions if their window moves.
local box
local function Around(...)
  local ui = UIParent:GetEffectiveScale()
  local l, r, t, b
  for i = 1, select("#", ...) do
    local region = select(i, ...)
    if region and region.IsVisible and region:IsVisible() then
      local rl, rr, rt, rb = region:GetLeft(), region:GetRight(), region:GetTop(), region:GetBottom()
      if rl and rr and rt and rb then
        local owner = region.GetEffectiveScale and region or region:GetParent()
        local s = owner:GetEffectiveScale() / ui
        rl, rr, rt, rb = rl * s, rr * s, rt * s, rb * s
        l = l and math.min(l, rl) or rl
        r = r and math.max(r, rr) or rr
        t = t and math.max(t, rt) or rt
        b = b and math.min(b, rb) or rb
      end
    end
  end
  if not l then return nil end
  box = box or CreateFrame("Frame", nil, UIParent)
  box:ClearAllPoints()
  box:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", l, b)
  box:SetSize(math.max(1, r - l), math.max(1, t - b))
  box:Show()
  return box
end

-- Walk up n parents (cards that a page keeps only as locals).
local function Up(r, n)
  for _ = 1, n or 1 do r = r and r.GetParent and r:GetParent() or nil end
  return r
end

-- Switch a tabbed page (c.tab / c.frames) to tab i, if the page has it.
local function Tab(i)
  return function(c)
    if c.tab ~= i and c.frames and c.frames[i] then
      c.tab = i
      K.Journal:RefreshCurrent()
    end
  end
end

---------------------------------------------------------------------------
-- The journal (welcome tour; ctx is K.Journal)
---------------------------------------------------------------------------
K:RegisterGuide({
  id = "journal",
  title = Loc["Your journal"],
  steps = {
    { title = Loc["Welcome to Kinship"],
      text = Loc["This is your roleplay journal. It holds your character, the people you meet and your stories. Here's a quick look around."] },
    { title = Loc["The sidebar"],
      text = Loc["Pages are grouped in the sidebar. You has your character and companions. People has the Directory, Kin, Community and Letters. Stories has your Chronicle and quests. World has the Warfront and your inventory."],
      target = function(J) return J.nav and J.nav[1] and J.nav[1]:GetParent() end },
    { title = Loc["Where you are"],
      text = Loc["The page name and a short description show here."],
      target = function(J) return J.frame and Around(J.frame.heading, J.frame.sub) end },
    { title = Loc["Settings"],
      text = Loc["Settings is at the bottom of the sidebar. You can change the target bar, nameplates, safety options and more, and turn whole features on or off."],
      target = function(J) return J.gear end },
    { title = Loc["Tours"],
      text = Loc["Click ? to replay the tour for the page you're on. Tours only start on their own the first time. You can turn them off in Settings > Guides."],
      target = function(J) return J.helpButton end },
    { title = Loc["Getting started"],
      text = Loc["Start with your Profile: add a name, a few details and what your character is doing. Open the journal any time with /kin, the minimap button or a key binding (Key Bindings > AddOns > Kinship RP)."] },
  },
})

---------------------------------------------------------------------------
-- Profile
---------------------------------------------------------------------------
K:RegisterGuide({
  id = "profile", page = "profile",
  title = Loc["Your character"],
  steps = {
    { title = "Your name",
      text = Loc["This is your name as other players see it, with your title and epithet. It updates as you type."],
      target = function(c) return Around(c.name, c.epithet) end },
    { title = Loc["Your status"],
      text = Loc["Choose In Character, Looking for RP or Out of Character. Your status shows on your tooltip and target bar."],
      target = function(c) return Around(c.gem, c.status) end },
    { title = Loc["Details"],
      text = Loc["Short facts like epithet, pronouns, age, height, home and house. Hover the (i) next to a field for help. Currently shows on your tooltip, so keep it up to date."],
      target = function(c) return Up(c.fields.epithet, 2) end },
    { title = Loc["Longer sections"],
      text = Loc["Identity, Appearance, Personality, History and Boundaries. Fill in as much or as little as you like."],
      target = function(c) return c.sectionTabs end },
    { title = Loc["Identity"],
      text = Loc["Your full name, title, nickname, race, class and more. Leave the name blank to use your character's name. Race and class only show if you fill them in."],
      target = function(c) return c.identity end,
      before = function(c)
        if c.section ~= "identity" then c.section = "identity"; c:LoadSection() end
      end },
    { title = Loc["Appearance, Personality and History"],
      text = Loc["Write these however you like. The toolbar adds headings, emphasis, colours, icons and dividers. Everything saves as you type."],
      target = function(c) return Up(c.sectionTabs) end,
      before = function(c)
        if c.section == "identity" or c.section == "boundaries" then c.section = "appearance"; c:LoadSection() end
      end },
    { title = Loc["Boundaries"],
      text = Loc["Set Yes, Ask or No for injury, death, capture, crime and romance. Other players see these, other RP addons can read them, and Kinship's wounds and captures follow them."],
      target = function(c) return c.bounds end,
      before = function(c)
        if c.section ~= "boundaries" then c.section = "boundaries"; c:LoadSection() end
      end },
    { title = Loc["Profiles and preview"],
      text = Loc["Keep separate profiles for different characters or stories and switch between them here. Preview shows your profile as other players see it."],
      target = function(c) return Around(c.profileBtn, c.preview) end },
  },
})

---------------------------------------------------------------------------
-- Persona (four tabs: Glances, Traits, Look, Effects)
---------------------------------------------------------------------------
K:RegisterGuide({
  id = "persona", page = "persona",
  title = Loc["Persona"],
  steps = {
    { title = Loc["Persona"],
      text = Loc["Glances, Traits, Look, Effects and Companions describe what people notice about your character. Preview profile shows the result."],
      target = function(c) return Around(c.tabs, c.preview) end,
      before = Tab(1) },
    { title = Loc["Glances"],
      text = Loc["Add up to five things people notice when they see you, like a scar or a scent. Click an empty slot to add one, or a filled slot to edit it."],
      target = function(c) local g = c.frames[1]; return Around(g.slots[1], g.slots[5]) end,
      before = Tab(1) },
    { title = Loc["Editing a glance"],
      text = Loc["Give a glance an icon, a short title and a line of text. Use the arrows to reorder, turn off Show to others to hide it, or Save for reuse to use it in other profiles."],
      target = function(c) return c.frames[1].editor end,
      before = Tab(1) },
    { title = Loc["Saved glances"],
      text = Loc["Glances show on other players' target bars and in your tooltip. Saved glances lets you add saved glances to any profile, or swap between whole sets."],
      target = function(c) return Around(c.presets, c.frames[1].preview) end,
      before = Tab(1) },
    { title = Loc["Traits"],
      text = Loc["Drag each slider towards the side that fits your character. Pick a preset pair or write your own. Click an icon to change its colour."],
      target = function(c) return c.frames[2] end,
      before = Tab(2) },
    { title = Loc["Look"],
      text = Loc["Choose the icon next to your name, your name colour and a theme tune others can play from your target bar. The tooltip preview shows how it looks."],
      target = function(c) return c.frames[3] end,
      before = Tab(3) },
    { title = Loc["Effects"],
      text = Loc["Effects are wounds, boons and states your character has for a while, like a bandaged arm or a blessing. Your current effects are listed here with the time left. Click End to remove one early."],
      target = function(c) local e = c.frames[4]; return e and e.active and Up(e.active) end,
      before = Tab(4) },
    { title = Loc["Rest and automatic effects"],
      text = Loc["Wounds and exhaustion heal twice as fast at an inn or in a city, and resting for half an hour makes you Well rested. Some effects come from the game, like drinking too much or a long swim. Click Not now to remove one, or turn them off in Settings."],
      target = function(c) local e = c.frames[4]; return e and e.active and Up(e.active) end,
      before = Tab(4) },
    { title = Loc["Adding an effect"],
      text = Loc["Choose an effect, how long it lasts and a note, then add it to yourself or offer it to your target. Wounds and captures follow each player's boundaries."],
      target = function(c) local e = c.frames[4]; return e and e.right end,
      before = Tab(4) },
  },
})

---------------------------------------------------------------------------
-- Companions
---------------------------------------------------------------------------
-- The editor shows only once a companion exists; before that, light the card.
local function Editor(c, ...)
  if c.ed and c.ed:IsShown() then return Around(...) end
  return c.panel
end

K:RegisterGuide({
  id = "companions", page = "companions",
  title = Loc["Companions"],
  steps = {
    { title = Loc["Companions"],
      text = Loc["Your pets and mounts with stories are listed here. Click one to edit it on the right."],
      target = function(c) return c.list end },
    { title = Loc["New companion"],
      text = Loc["Create a story for any pet or mount. It starts as a pet; you can change it to a mount on the right."],
      target = function(c) return c.newBtn end },
    { title = Loc["Name and icon"],
      text = Loc["Give your companion a name, title and icon, and choose pet or mount. The title shows under their name."],
      target = function(c) local ed = c.ed; return Editor(c, ed.iconBtn, ed.nameField, ed.kind, ed.iconField) end },
    { title = Loc["Description"],
      text = Loc["The glance is one line shown on their tooltip. Use the description for everything else."],
      target = function(c) local ed = c.ed; return Editor(c, ed.glanceField, ed.desc) end },
    { title = Loc["Linking a pet or mount"],
      text = Loc["Link the story to your pet or mount by typing its name, or use the button while it's summoned. For a companion pet, target it first. Other players see it when they hover your pet, and a linked mount shows on your tooltip while you ride."],
      target = function(c) local ed = c.ed; return Editor(c, ed.chipArea, ed.bindEdit, ed.current) end },
    { title = Loc["Saving"],
      text = Loc["Changes save as you type and are shared with your profile. Delete asks you to confirm."],
      target = function(c) return Editor(c, c.ed.delete) end },
  },
})

---------------------------------------------------------------------------
-- The Roleplay pane on the character sheet (ctx is the pane)
---------------------------------------------------------------------------
-- Scroll the pane's body so a part sits in view (clamped to what scrolls).
local function Scroll(y)
  return function(pane)
    local sf = pane.sf
    if not sf or not pane.body then return end
    local range = math.max(0, (pane.body:GetHeight() or 0) - (sf:GetHeight() or 0))
    sf:SetVerticalScroll(math.max(0, math.min(range, y)))
  end
end

K:RegisterGuide({
  id = "charpane",
  title = Loc["Roleplay pane"],
  steps = {
    { title = Loc["Roleplay tab"],
      text = Loc["This tab on your character sheet shows your roleplay details and lets you change them without opening the journal."] },
    { title = Loc["Name and icon"],
      text = Loc["Your icon, roleplay name and epithet. If you have no epithet, your house shows instead. Click the icon to change your look on the Persona page."],
      target = function(p) return Around(p.med, p.name, p.epithet) end },
    { title = Loc["Your status"],
      text = Loc["Set In Character, Looking for RP or Out of Character in one click. Your status shows on your tooltip and target bar."],
      target = function(p) return p.status end },
    { title = Loc["Names on frames"],
      text = Loc["Shows your roleplay name in the character window title and on your player frame. When on, other players' roleplay names also show on your target and focus frames. More options in Settings > Unit frames."],
      target = function(p) return Around(p.titleToggle, p.frameToggle) end,
      before = Scroll(0) },
    { title = Loc["Notes"],
      text = Loc["Edit your notes here. Currently says what your character is doing. The OOC note is for anything other players should know."],
      target = function(p) return Around(p.currently, p.ooc) end,
      before = Scroll(56) },
    { title = Loc["Glances and effects"],
      text = Loc["Hover one for details, or click to open it in the journal. Right-click an effect to end it, or click + to add one."],
      target = function(p) return Around(p.glances, p.effects, p.addEffect) end,
      before = Scroll(180) },
    { title = Loc["Roleplay items"],
      text = Loc["While this tab is open, the gear slots show your roleplay items instead of your real gear. Click a slot to equip or remove an item. Other Kinship users see these on your profile."],
      target = function() return Around(_G.CharacterHeadSlot, _G.CharacterWristSlot) end },
    { title = Loc["Stance and boundaries"],
      text = Loc["Click a line to change it. Your stance says how you approach PvP. Injury, Death, Capture and Crime say what your character can go through."],
      target = function(p) return Around(p.stance, unpack(p.consent or {})) end,
      before = Scroll(10000) },
    { title = Loc["More options"],
      text = Loc["Switch profiles, open the full journal, or preview your profile as other players see it."],
      target = function(p) return Around(p.profileBtn, p.journal, p.preview) end },
  },
})

---------------------------------------------------------------------------
-- The target bar (ctx is the bar)
---------------------------------------------------------------------------
K:RegisterGuide({
  id = "targetbar",
  title = Loc["Target bar"],
  steps = {
    { title = Loc["Target bar"],
      text = Loc["When you target a roleplayer, this bar shows who they are. Click the portrait to open their profile. The gem shows if they're IC, LFRP or OOC."],
      target = function(f) return f.portrait end,
      side = "bottom" },
    { title = Loc["Name and status"],
      text = Loc["Their roleplay name in their chosen colour. Below it are their epithet, status, war stance and your relationship with them, if you've set one."],
      target = function(f) return Around(f.name, f.sub) end,
      side = "bottom" },
    { title = Loc["Glances"],
      text = Loc["Their glances, the things you'd notice at first sight. Hover one to read it."],
      target = function(f) return Around(unpack(f.glances or {})) end,
      side = "bottom" },
    { title = Loc["Effects"],
      text = Loc["Their current effects. Wounds have a red ring and boons a green one. Hover one to see what it is and how long it lasts."],
      target = function(f) return Around(unpack(f.auras or {})) end,
      side = "bottom" },
    { title = Loc["Actions"],
      text = Loc["View their profile, write a letter, roll dice, set your relationship, add an effect and more. Hover a button to see what it does."],
      target = function(f) return Around(f.split, unpack(f.buttons or {})) end,
      side = "bottom" },
    { title = Loc["Moving the bar"],
      text = Loc["Drag the bar to move it. In Settings > Target bar you can lock it, hide it in combat, or show it for players without a roleplay addon."],
      target = function(f) return f end,
      side = "bottom" },
  },
})

---------------------------------------------------------------------------
-- The profile viewer (ctx is K.Viewer)
---------------------------------------------------------------------------
K:RegisterGuide({
  id = "viewer",
  title = Loc["Profile viewer"],
  steps = {
    { title = Loc["The stage"],
      text = Loc["Their character shows here when they're nearby. Drag to rotate. Their glances are along the bottom; hover one to read it."],
      target = function(V) return V.stage end },
    { title = Loc["Name and stance"],
      text = Loc["Name, epithet and house, then their status and war stance. The stance shows how they feel about PvP. Click their house to see its motto, history and members."],
      target = function(V) return Around(V.name, V.epithet, V.house, V.gem, V.stance) end },
    { title = Loc["Facts"],
      text = Loc["Pronouns, age, height and home. Below them is what they're doing right now, or where you first met if they haven't said."],
      target = function(V) return Around(V.facts and V.facts.Pronouns, V.facts and V.facts.Home, V.currently) end },
    { title = Loc["Tabs"],
      text = Loc["About has their glance, identity, house, boundaries and effects. Nature has their personality and traits. Looks and History have the rest. Your own profile also has your Chronicle."],
      target = function(V) return Around(V.tabs, V.body) end },
    { title = Loc["Your stage"],
      text = Loc["On your own profile, use the palette in the corner to set a backdrop, lighting and floor behind your character. Other Kinship users see it when they open your profile."],
      target = function(V) return V.palette and V.palette:IsShown() and V.palette or nil end, pad = 6 },
    { title = Loc["Hidden profiles"],
      text = Loc["If a profile matches your mature filter, it stays hidden until you choose to view it. Set what the filter catches in Settings > Safety."],
      target = function(V) return V.cover and V.cover:IsShown() and V.cover or nil end },
    { title = Loc["Finding profiles"],
      text = Loc["Open a profile from someone's target bar portrait, a profile link in chat or the Directory. Preview shows your own profile as others see it."] },
  },
})
