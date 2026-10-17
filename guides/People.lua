-- Kinship RP: guided tours for the People and Stories pages: Directory, Kin,
-- House, Letters, Chronicle, Quests and Gatherings. See Guide.lua for how tours work.
local ADDON, ns = ...
local K = ns.K

-- A region if it's showing, else nil (so the next choice can take over).
local function Shown(r)
  if r and r.IsShown and r:IsShown() then return r end
end

-- Walk up n parents (cards that a page keeps only as locals).
local function Up(r, n)
  for _ = 1, n or 1 do r = r and r.GetParent and r:GetParent() or nil end
  return r
end

-- Switch a tabbed page (c.tab / c.frames) to tab i.
local function Tab(i)
  return function(c)
    if c.tab ~= i then
      c.tab = i
      K.Journal:RefreshCurrent()
    end
  end
end

---------------------------------------------------------------------------
-- Directory
---------------------------------------------------------------------------
K:RegisterGuide({
  id = "directory", page = "directory", title = "The Directory",
  steps = {
    { title = "Everyone you've met",
      text = "Profiles gather here as you meet people: mouse over a roleplayer and theirs arrives. It reads Kinship and other RP addons, Total RP 3, MyRolePlay and XRP among them, so most roleplayers will appear.",
      target = function(c) return c.list end },
    { title = "Narrow it down",
      text = "Show only those seen in the last quarter of an hour, those in character, those looking for roleplay, or your own Kin. Choose Everyone to see the whole Directory again.",
      target = function(c) return c.filters end },
    { title = "Find a name",
      text = "Search by character name, roleplay name, house or epithet. Handy when you remember a face from last night's tavern but not quite the name, or want everyone of one house.",
      target = function(c) return c.searchBox or c.filters end },
    { title = "More with a right-click",
      text = "The gem shows whether someone is in character, and the tag which addon they use. Right-click a name to write to them, add them to your Kin, name your relationship or ignore them.",
      target = function(c) return c.list end },
    { title = "At a glance",
      text = "Choose someone to see their profile in brief: status, stance, house, a few facts, what they're up to and which stories they're happy to share. Double-click to open it in full.",
      target = function(c) return Up(c.detail) end },
    { title = "Your private note",
      text = "Jot down where you met or what you made of them. Notes stay with you; nobody else sees them. The buttons beneath open their profile, start a letter or add them to your Kin.",
      target = function(c) return Shown(c.detail) and c.detail.note or Up(c.detail) end },
  },
})

---------------------------------------------------------------------------
-- Kin
---------------------------------------------------------------------------
K:RegisterGuide({
  id = "kin", page = "kin", title = "Your Kin",
  steps = {
    { title = "Everyone you've adventured with",
      text = "Group up with someone and they join your Kin on their own, with where, when and at what level you met. The meeting goes into your Chronicle too. You can add anyone else by name.",
      target = function(c) return c.list end },
    { title = "How you met",
      text = "Show everyone, or only those you travelled with or those you added yourself. Each name carries a small mark at the start of its row for how you met.",
      target = function(c) return c.groups end },
    { title = "Find someone",
      text = "Search your Kin by name. Useful once your travels have taken you far, the list has grown long, and you want the one face you shared a road with last week.",
      target = function(c) return c.searchBox or c.groups end },
    { title = "Bonds",
      text = "Click a name to read their profile. The bond button, or a right-click, says what they are to your character: friend, family, mentor, rival and more. Whisper or remove them there too.",
      target = function(c) return c.list end },
    { title = "Add someone by name",
      text = "Met someone the game didn't notice, perhaps over a letter or at a gathering? Type their name here and choose Add, and they join your Kin as someone you added yourself.",
      target = function(c) return c.addBox or c end },
    { title = "Kin elsewhere",
      text = "Your Kin turn up elsewhere too: the Directory can show only them, those who share your house name appear on the House page, and Settings can let letters through from your Kin alone.",
    },
  },
})

---------------------------------------------------------------------------
-- House
---------------------------------------------------------------------------
K:RegisterGuide({
  id = "house", page = "house", title = "Your house",
  steps = {
    { title = "A family name",
      text = "A house is a family built on a shared name. Set a house name on your profile to found one; your other characters, and anyone else who shares that name, can join it.",
      target = function(c) return Shown(c.none) or c.hero end },
    { title = "Your crest",
      text = "Click the crest to choose your house's arms from shields, beasts, blades and stars. It's pressed into the wax of every letter you seal, so your family is known before a word is read.",
      target = function(c) return c.crest end, pad = 6 },
    { title = "A motto",
      text = "A few words your house lives by. Write something your characters would say with pride at a feast, or mutter under their breath when the family name is mocked. It shows on your profile and your house's card.",
      target = function(c) return c.motto end },
    { title = "The house's story",
      text = "Set down the house's history: its seat, its old feuds, its debts and hopes. It travels with your profile, so anyone with Kinship can read it by clicking your house's name on your profile.",
      target = function(c) return Up(c.desc) end },
    { title = "Members and claims",
      text = "Your own characters are always family. Others who share the name, from the profiles that reach you or among your Kin, appear as claims until you recognise them.",
      target = function(c) return c.members end },
    { title = "Recognise or ignore",
      text = "Click Recognise to welcome someone in, or right-click to ignore a claim. Anyone can write a house name, so these choices are yours alone, and only you see them.",
      target = function(c) return c.members end },
  },
})

---------------------------------------------------------------------------
-- Letters
---------------------------------------------------------------------------
K:RegisterGuide({
  id = "letters", page = "letters", title = "Letters",
  -- Put away the blank sheet the tour opened (never one you've started writing).
  finish = function(_, c)
    if not (c and c.guideOpened and c.mode == "write" and c.write) then return end
    local empty = true
    for _, f in ipairs({ c.write.to, c.write.title, c.write.body }) do
      local eb = f and f.edit
      if eb and strtrim(eb:GetText() or "") ~= "" then empty = false end
    end
    c.guideOpened = nil
    if empty then c.mode = "read"; K.Journal:RefreshCurrent() end
  end,
  steps = {
    { title = "Received and sent",
      text = "Letters are written in character, sealed in wax and sent by the game's own post. Switch between the letters that have come to you and the ones you've sent, newest at the top.",
      target = function(c) return c.boxes end,
      before = function(c) c.guideOpened = nil end },
    { title = "The pile",
      text = "Unopened letters wear their seal brightly. Sent letters say how they fared: waiting to be posted, posted, or not sent if the post turned them back. Each shows the day it was written or arrived.",
      target = function(c) return c.list end },
    { title = "Reading a letter",
      text = "Choose a letter to read it here. A new one arrives sealed with its sender's wax: break the seal to open it, then reply, or burn it if it's best forgotten.",
      target = function(c) return c.paper end,
      before = function(c)
        -- Stepping back from the writing step: put the sheet the tour opened away again.
        if c.guideOpened and c.mode == "write" then
          c.guideOpened, c.mode = nil, "read"
          K.Journal:RefreshCurrent()
        end
      end },
    { title = "Writing",
      text = "The Write a letter button opens a fresh sheet. Address it to a character, add a title if you like, write what you have to say, and sign it as your character would.",
      target = function(c) return Shown(c.write) or c.paper end,
      before = function(c)
        if c.mode ~= "write" then   -- never wipe a letter you were already writing
          c:Compose("")
          c.guideOpened = true
        end
        c.write.to.edit:ClearFocus()
      end },
    { title = "Hand, paper and cipher",
      text = "Across the top: the hand your character writes in, which they'll see too; the state the paper arrives in, from pristine to blood-stained or singed; and a cipher, which scrambles the letter with a key word you tell them in character.",
      target = function(c) return Shown(c.write) and c.write.hand end, pad = 6 },
    { title = "Your seal",
      text = "Pick a colour of wax beneath, and click the seal to press in your house crest or the Kinship monogram. It's the first thing they see, before the letter is even opened.",
      target = function(c) return Shown(c.write) and c.write.seal end, pad = 8 },
    { title = "Seal and send",
      text = "Sealed letters wait in your Sent letters until you open a mailbox, where Kinship posts them for you. They arrive as game mail, so they reach people who are offline: Kinship users find a sealed letter, and anyone else reads an ordinary one.",
      target = function(c) return Shown(c.write) and c.write.send end },
    { title = "Only from your Kin",
      text = "If you'd rather not hear from strangers, Settings can quietly turn letters away from anyone who isn't among your Kin. Nobody is told; the letter simply never arrives.",
    },
  },
})

---------------------------------------------------------------------------
-- Chronicle
---------------------------------------------------------------------------
K:RegisterGuide({
  id = "chronicle", page = "chronicle", title = "Your Chronicle",
  steps = {
    { title = "Your story so far",
      text = "Your Chronicle writes itself as you play. New places, levels, dungeons, battles, letters and the people you travel with all leave a page, so your character's story is never lost.",
      target = function(c) return Up(c.list, 2) end },
    { title = "Show one kind",
      text = "Show everything, or only places, milestones, dungeons, Kin, battles, letters or the pages you wrote yourself. Handy when you want to find one moment among many.",
      target = function(c) return c.filterBtn end },
    { title = "Moments",
      text = "Each line is a moment with its date, newest first. Click one to read it in full, with where it happened and the level you were then. The count beneath shows how many you've gathered.",
      target = function(c) return c.list end },
    { title = "In your own words",
      text = "Every moment can hold your character's thoughts. Choose Write beneath one to add how it felt and what changed, or Remove if it doesn't belong in the story.",
      target = function(c) return Up(c.read, 2) end },
    { title = "A new page",
      text = "Write a new page for what the game can't see: a conversation, a dream, a vow made by a campfire. Give it a title and it joins your timeline, under Your own pages.",
      target = function(c) return c.writeBtn or Up(c.list, 2) end },
  },
})

---------------------------------------------------------------------------
-- Quests
---------------------------------------------------------------------------
K:RegisterGuide({
  id = "quests", page = "quests", title = "Quests",
  steps = {
    { title = "Three parts",
      text = "Journal holds the quests you're on, Write is where you make your own to offer others, and Campaigns gathers them into longer stories. Quests are written by players, for players.",
      target = function(c) return c.tabs end,
      before = Tab(1) },
    { title = "Your journal",
      text = "Quests offered by friends land here once you accept them. Switch between those you're on, those you've finished and those you've set aside; right-click one for more.",
      target = function(c) return c.frames[1].list end,
      before = Tab(1) },
    { title = "Reading a quest",
      text = "Each quest reads like a page from its giver, with objectives beneath. Track it to keep it close, set it aside, or mark it complete. When its author tells the story, you see their ticks as they happen.",
      target = function(c) local f = c.frames[1]; return Shown(f.sheet) or f.empty end,
      before = Tab(1) },
    { title = "Write a quest",
      text = "Give it a title, a quest giver and an icon, tell the story and list up to eight things that must be done. A campaign name ties it to others in the same tale, and a reward is up to you.",
      target = function(c) return Up(c.frames[2].body, 2) end,
      before = Tab(2) },
    { title = "See it as they will",
      text = "The preview shows your quest just as others will read it, and changes as you type. Read it through once before you share it; it's how your quest giver will sound.",
      target = function(c) return c.frames[2].preview end,
      before = Tab(2) },
    { title = "Offer it",
      text = "Save keeps it in your library. Share offers it to your group or your target, or lets you run it yourself. As its storyteller, you tick objectives for everyone who took it up.",
      target = function(c) return c.frames[2].share end,
      before = Tab(2) },
    { title = "Campaigns",
      text = "Quests that share a campaign name gather here, with how far along you are. Those without one sit together as standalone quests, and your own drafts appear too.",
      target = function(c) return c.frames[3].list end,
      before = Tab(3) },
    { title = "Following a campaign",
      text = "Choose a campaign to see its quests in order and who wrote them. Click one to read it in your journal, or to open your own draft in the editor and carry on writing.",
      target = function(c) return c.frames[3].card end,
      before = Tab(3) },
    { title = "Out in the world",
      text = "Tracked quests also sit in your objective tracker under Roleplay Quests, each with its own icon, and the quest log has a Roleplay tab listing them all. Settings > Quests switches either off." },
    { title = "Levels and markers",
      text = "When writing, give a quest a level and pin where it happens, or pin each objective. Pins show on the world map and minimap, and the tracker counts down the yards as you go." },
    { title = "Objectives that tick themselves",
      text = "The lightning button beside an objective gives it a rule: reach the pin, keep watch, answer a riddle, win a duel, roll a check and more. Add conditions (at the pin, after dark, in character), make it optional or hidden, or let it fail. Kinship ticks it when it happens, and tells the storyteller." },
  },
})

---------------------------------------------------------------------------
-- Gatherings
---------------------------------------------------------------------------
K:RegisterGuide({
  id = "gatherings", page = "gatherings", title = "Gatherings",
  steps = {
    { title = "The board",
      text = "Roleplay events appear here as cards: what, when, where and how many are going. Click one to open it. If the board is empty, be the first to post something for others to find.",
      target = function(c) return Shown(c.cards[1]) or c.emptyText end },
    { title = "Three boards",
      text = "Three boards: your guild, your house (everyone who shares your house name) and a public board for Kinship users near you. Post to whichever one you're looking at.",
      target = function(c) return c.scopes end },
    { title = "Who sees them",
      text = "Everyone keeps a copy and passes news along: the guild board instantly, house and public as people meet. A public gathering reaches further the longer it's up.",
      target = function(c) return c.shareNote end },
    { title = "Post a gathering",
      text = "Name your event, say when and where, and add the details. Where starts as the place you're standing, you're counted as going, and the board you're on hears of it.",
      target = function(c) return c.postBtn or c end },
    { title = "Going",
      text = "Open a gathering to say you're going, see who else is coming, or copy it to share on Discord. One with a date can go on your game calendar too, and saying you're going adds it. Only its host can change or remove it.",
      target = function(c) return Shown(c.cards[1]) end },
    { title = "Passed along",
      text = "A gathering heard from someone other than its host says who shared it, and stays unconfirmed until the host's own copy reaches you. That way nobody can post in another's name.",
    },
  },
})
