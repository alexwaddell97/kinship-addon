-- Kinship RP: guided tours for the journal itself, the You pages (Profile,
-- Persona, Companions), the Roleplay pane on the character sheet, the target
-- bar and the profile viewer. See Guide.lua for how tours work.
local ADDON, ns = ...
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
  title = "Your journal",
  steps = {
    { title = "Welcome to Kinship",
      text = "This is your roleplay journal. Your character, the people you meet and the stories you share all live here. "
        .. "A few quick notes first, then it's yours to explore." },
    { title = "Pages, in four groups",
      text = "The sidebar keeps every page. You is your own character; People holds those you meet, your house and letters; "
        .. "Stories keeps your chronicle, quests and gatherings; World covers the warfront and your belongings.",
      target = function(J) return J.nav and J.nav[1] and J.nav[1]:GetParent() end },
    { title = "Where you are",
      text = "Each page names itself up here, with a line on what it's for. Whatever you open, from your profile to your letters, "
        .. "you can always tell where you are and what the page can do for you.",
      target = function(J) return J.frame and Around(J.frame.heading, J.frame.sub) end },
    { title = "Settings",
      text = "Settings sits at the foot of the sidebar: the target bar, nameplates, the character sheet, safety and more. "
        .. "Whole features can be switched on or off there too.",
      target = function(J) return J.gear end },
    { title = "Tours on request",
      text = "The ? replays the tour for whichever page you're on. Tours only start by themselves the first time; "
        .. "Settings > Guides turns them off, or shows them all again.",
      target = function(J) return J.helpButton end },
    { title = "Make a start",
      text = "Begin with your Profile: a name, a few details and a line about what you're doing now go a long way. "
        .. "Every page has its own short tour the first time you open it. Come back any time with /kin, the "
        .. "minimap button, or Kinship in the game menu (Esc)." },
  },
})

---------------------------------------------------------------------------
-- Profile
---------------------------------------------------------------------------
K:RegisterGuide({
  id = "profile", page = "profile",
  title = "Your character",
  steps = {
    { title = "Your name, as others see it",
      text = "This is how your name reads to other players, with your title and epithet. It changes as you type, "
        .. "so try a few and keep the one that sounds like your character.",
      target = function(c) return Around(c.name, c.epithet) end },
    { title = "Your status",
      text = "In Character, Looking for RP or Out of Character. Your status shows on your tooltip and target bar, "
        .. "so others know whether to come over in character or just say hello.",
      target = function(c) return Around(c.gem, c.status) end },
    { title = "The details",
      text = "Quick facts: epithet, pronouns, age, height, home and house. Keep Currently fresh: it sits on your tooltip "
        .. "and tells people what your character is doing right now.",
      target = function(c) return Up(c.fields.epithet, 2) end },
    { title = "Four kinds of writing",
      text = "Identity, Appearance, Personality and History. Write as much or as little as you like: these are what people open "
        .. "when a first glance has made them curious about your character.",
      target = function(c) return c.sectionTabs end },
    { title = "Identity",
      text = "Your full name, title and nickname, plus race, class and more. Leave the name empty to use your character's own; "
        .. "race and class only show when you fill them in.",
      target = function(c) return c.identity end,
      before = function(c)
        if c.section ~= "identity" then c.section = "identity"; c:LoadSection() end
      end },
    { title = "Free writing",
      text = "Appearance, Personality and History are yours to write freely. The toolbar adds headings, emphasis, colour, "
        .. "icons and dividers, and everything saves as you type.",
      target = function(c) return Up(c.sectionTabs) end,
      before = function(c)
        if c.section == "identity" then c.section = "appearance"; c:LoadSection() end
      end },
    { title = "Profiles and preview",
      text = "Keep a separate profile for each story or character idea, and switch between them in one click. Preview, beside it, "
        .. "shows your profile exactly as other players will see it.",
      target = function(c) return Around(c.profileBtn, c.preview) end },
  },
})

---------------------------------------------------------------------------
-- Persona (four tabs: Glances, Traits, Look, Effects)
---------------------------------------------------------------------------
K:RegisterGuide({
  id = "persona", page = "persona",
  title = "Persona",
  steps = {
    { title = "First impressions",
      text = "Glances, Traits, Look and Effects: what people notice about your character before they ever open your profile. "
        .. "Preview profile, on the right, shows the result.",
      target = function(c) return Around(c.tabs, c.preview) end,
      before = Tab(1) },
    { title = "Five glances",
      text = "Up to five details people notice the moment they see you: a scar, a scent, a sigil. Click the empty slot to add one, "
        .. "or a filled slot to change it. They show in the order you set.",
      target = function(c) local g = c.frames[1]; return Around(g.slots[1], g.slots[5]) end,
      before = Tab(1) },
    { title = "Shaping a glance",
      text = "Give each glance an icon, a few words of title and a line or two on what people notice. Move it left or right to reorder, "
        .. "or switch off Show to others to keep it aside without deleting it.",
      target = function(c) return c.frames[1].editor end,
      before = Tab(1) },
    { title = "As others see it",
      text = "See your glances on someone's target bar and in the tooltip when they hover. "
        .. "Glance presets, above, keeps sets under a name to swap in a click: travelling clothes, court dress, after the battle.",
      target = function(c) return Around(c.presets, c.frames[1].preview) end,
      before = Tab(1) },
    { title = "Personality traits",
      text = "Drag each slider toward the side that fits your character. Pick a ready-made pair on the right or write your own; "
        .. "click a side's icon to change its colour.",
      target = function(c) return c.frames[2] end,
      before = Tab(2) },
    { title = "Your look",
      text = "Choose the emblem beside your name, the colour your name is shown in, and a theme tune others can play "
        .. "from your target bar. The small tooltip shows how it all looks.",
      target = function(c) return c.frames[3] end,
      before = Tab(3) },
    { title = "Effects on you",
      text = "Effects are the wounds, boons and states your character carries for a while: a bandaged arm, a blessing, a hangover. "
        .. "What's on you now is listed here with the time left; End takes one off early.",
      target = function(c) local e = c.frames[4]; return e and e.active and Up(e.active) end,
      before = Tab(4) },
    { title = "Rest, and what comes on its own",
      text = "At an inn or in a city, wounds and exhaustion pass twice as fast, and half an hour's rest leaves you "
        .. "Well rested. A few light effects come from the game itself: a drink too many, a long swim, a real "
        .. "bandage on a wound. Every one can be taken off with Not now, and each has its own switch in Settings.",
      target = function(c) local e = c.frames[4]; return e and e.active and Up(e.active) end,
      before = Tab(4) },
    { title = "Laying an effect",
      text = "Choose an effect, how long it lasts and a note, then take it on or offer it to your target. "
        .. "Wounds and captures follow each player's boundaries, so no one carries what they haven't agreed to.",
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
  title = "Companions",
  steps = {
    { title = "Your companions",
      text = "A loyal wolf, a stubborn kodo, an imp with opinions. Every pet and mount you've given a story is listed here, "
        .. "with what it's bound to. Click one to open it on the right.",
      target = function(c) return c.list end },
    { title = "A new companion",
      text = "Start a story for any pet or mount, even one you only call on now and then. It begins as a pet; "
        .. "you can make it a mount on the right, and give it a name of its own.",
      target = function(c) return c.newBtn end },
    { title = "Who they are",
      text = "Give them a name, a title and an icon, and say whether they're a pet or a mount. "
        .. "The title sits under their name, like an epithet of their own, such as Eater of boots.",
      target = function(c) local ed = c.ed; return Editor(c, ed.iconBtn, ed.nameField, ed.kind, ed.iconField) end },
    { title = "Their story",
      text = "The glance is one line, shown on their tooltip. The description has room for the rest: "
        .. "where you found them, what they're like, and the trouble they keep getting into.",
      target = function(c) local ed = c.ed; return Editor(c, ed.glanceField, ed.desc) end },
    { title = "Binding them",
      text = "Bind the story to your pet or mount by name, or with the button while it's out. "
        .. "Anyone hovering over that pet meets it properly, and a bound mount shows on your tooltip while you ride.",
      target = function(c) local ed = c.ed; return Editor(c, ed.chipArea, ed.bindEdit, ed.current) end },
    { title = "Saved as you go",
      text = "Everything saves as you type and travels with your profile, so others meet your companions too. "
        .. "Delete asks twice, so a slip of the mouse won't cost you a story.",
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
  title = "Roleplay pane",
  steps = {
    { title = "Your Roleplay pane",
      text = "This tab on your character sheet keeps your roleplay close at hand: who you are, how you're playing right now, "
        .. "and your boundaries, all changeable in place." },
    { title = "Who you are",
      text = "Your icon, roleplay name and epithet, as others see them; with no epithet, your house shows instead. "
        .. "Click the icon to change your look, name colour and theme music on the Persona page.",
      target = function(p) return Around(p.med, p.name, p.epithet) end },
    { title = "Your status",
      text = "In Character, Looking for RP or Out of Character, in one click. Your status shows on your tooltip and target bar, "
        .. "so people know whether to approach you in character or simply say hello.",
      target = function(p) return p.status end },
    { title = "Names on the screen",
      text = "Show your roleplay name in the character window's title and on your player frame. With it on, other players' "
        .. "roleplay names show on your target and focus frames too, in gold with the character's own name beside them. "
        .. "More in Settings > Unit frames.",
      target = function(p) return Around(p.titleToggle, p.frameToggle) end,
      before = Scroll(0) },
    { title = "Right now",
      text = "Change your notes without opening the journal. Currently says what your character is doing; "
        .. "the out-of-character note is for anything the players behind them should know.",
      target = function(p) return Around(p.currently, p.ooc) end,
      before = Scroll(56) },
    { title = "Glances and effects",
      text = "Your glances and effects at a look; hover over one for details, or click to open it in the journal. "
        .. "Right-click an effect to end it, or use + to take one on: a wound, a blessing, a bottle too many.",
      target = function(p) return Around(p.glances, p.effects, p.addEffect) end,
      before = Scroll(180) },
    { title = "What you're wearing",
      text = "While this tab is open, the gear slots beside your character show the Kinship items they wear in roleplay: "
        .. "a hat, a cloak, a ring, a blade at the hip. Click one to put something on or take it off. Other Kinship users "
        .. "see them around you on your profile.",
      target = function() return Around(_G.CharacterHeadSlot, _G.CharacterWristSlot) end },
    { title = "Stance and boundaries",
      text = "Click a line to change it. Your stance says how you meet a fight; Injury, Death, Capture and Crime say "
        .. "what your character can go through. Others see these before a story turns rough.",
      target = function(p) return Around(p.stance, unpack(p.consent or {})) end,
      before = Scroll(10000) },
    { title = "More, a click away",
      text = "Switch profiles when you start a different story, open the full journal for everything else, "
        .. "or preview your profile exactly as other players will see it when they click your portrait.",
      target = function(p) return Around(p.profileBtn, p.journal, p.preview) end },
  },
})

---------------------------------------------------------------------------
-- The target bar (ctx is the bar)
---------------------------------------------------------------------------
K:RegisterGuide({
  id = "targetbar",
  title = "Target bar",
  steps = {
    { title = "Who you're looking at",
      text = "When you target a roleplayer, this bar shows who they are. Click their portrait for their full profile; the small gem "
        .. "on it shows whether they're in character, looking for roleplay or out of character.",
      target = function(f) return f.portrait end,
      side = "bottom" },
    { title = "Name and standing",
      text = "Their roleplay name in their chosen colour. Underneath: their epithet, status and war stance, "
        .. "plus how you know them, if you've set a relationship. Enough to tell whether to wave or keep walking.",
      target = function(f) return Around(f.name, f.sub) end,
      side = "bottom" },
    { title = "At first glance",
      text = "Their glances: what you'd notice at first sight, like a scar or the smell of pipe smoke. "
        .. "Hover over one to read it, so a scene can start before either of you has said a word.",
      target = function(f) return Around(unpack(f.glances or {})) end,
      side = "bottom" },
    { title = "What they carry",
      text = "Effects they're carrying, each ringed in its colour: red for wounds, green for boons. Hover over one to see "
        .. "what it is and how long it lasts, so a fresh wound from last night's skirmish doesn't go unnoticed.",
      target = function(f) return Around(unpack(f.auras or {})) end,
      side = "bottom" },
    { title = "Things to do",
      text = "View their profile, write a letter, roll dice, say how you know them, lay an effect and more. "
        .. "Hover over any button to see what it does before you click.",
      target = function(f) return Around(f.split, unpack(f.buttons or {})) end,
      side = "bottom" },
    { title = "Put it where you like",
      text = "Drag the bar wherever suits you. Settings > Target bar can lock it in place, hide it during combat, "
        .. "or show it for players who don't use a roleplay addon at all.",
      target = function(f) return f end,
      side = "bottom" },
  },
})

---------------------------------------------------------------------------
-- The profile viewer (ctx is K.Viewer)
---------------------------------------------------------------------------
K:RegisterGuide({
  id = "viewer",
  title = "Profile viewer",
  steps = {
    { title = "On the stage",
      text = "Their character stands here when they're nearby; drag to turn them round. Their glances sit along "
        .. "the foot of the stage, so hover over one to read what people notice first.",
      target = function(V) return V.stage end },
    { title = "Name and stance",
      text = "Name, epithet and house, then their status and war stance. The stance tells you how they feel about a fight, "
        .. "from open war to non-combatant, before you start one. Click their house to see its motto, history and members.",
      target = function(V) return Around(V.name, V.epithet, V.house, V.gem, V.stance) end },
    { title = "Quick facts",
      text = "Pronouns, age, height and home at a look. Under them is what they're doing right now in their own words, "
        .. "or where you first met, if they haven't said.",
      target = function(V) return Around(V.facts and V.facts.Pronouns, V.facts and V.facts.Home, V.currently) end },
    { title = "Reading their profile",
      text = "About gathers their glance, identity, house, boundaries and any effects they carry. Nature holds their "
        .. "personality and traits, and Looks and History the rest. Your own profile has your Chronicle too.",
      target = function(V) return Around(V.tabs, V.body) end },
    { title = "Set the stage",
      text = "On your own profile, the palette in the corner of the stage sets the scene behind your character: a backdrop, "
        .. "a spotlight, and what's under their feet. Other Kinship users see it when they open your profile.",
      target = function(V) return V.palette and V.palette:IsShown() and V.palette or nil end, pad = 6 },
    { title = "Covered, if you like",
      text = "If a profile's words match your mature filter, it stays covered until you choose to look. "
        .. "You can look anyway or leave it covered; Settings > Safety sets what the filter catches.",
      target = function(V) return V.cover and V.cover:IsShown() and V.cover or nil end },
    { title = "Finding profiles",
      text = "Open anyone's profile from their target bar portrait, a profile link in chat or the Directory. "
        .. "Preview, on your own pages, shows yours just as others see it, which is handy after an edit." },
  },
})
