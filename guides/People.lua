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
    { title = "Profiles",
      text = "Profiles appear here as you meet people. Mouse over a roleplayer to get theirs. It works with Kinship, Total RP 3, MyRolePlay and XRP.",
      target = function(c) return c.list end },
    { title = "Filters and sorting",
      text = "Show only people seen in the last 15 minutes, people who are IC or LFRP, your Kin, or people new to RP and mentors. The buttons at the bottom sort the list.",
      target = function(c) return c.filters end },
    { title = "Search",
      text = "Search by character name, roleplay name, house, group or epithet.",
      target = function(c) return c.searchBox or c.filters end },
    { title = "Right-click",
      text = "The gem shows their status and the tag shows which addon they use. Right-click a name to write to them, add them to your Kin, set your relationship or ignore them.",
      target = function(c) return c.list end },
    { title = "Preview",
      text = "Select someone to see a short version of their profile. Double-click to open it in full.",
      target = function(c) return Up(c.detail) end },
    { title = "Notes",
      text = "Write a note about them, like where you met. Only you can see it. The buttons below open their profile, start a letter or add them to your Kin.",
      target = function(c) return Shown(c.detail) and c.detail.note or Up(c.detail) end },
  },
})

---------------------------------------------------------------------------
-- Kin
---------------------------------------------------------------------------
K:RegisterGuide({
  id = "kin", page = "kin", title = "Your Kin",
  steps = {
    { title = "Your Kin",
      text = "Your Kin are the people you know, with where, when and at what level you met. Roleplayers you group with are added automatically, and you can add anyone by name. Settings > Kin changes who gets added.",
      target = function(c) return c.list end },
    { title = "How you met",
      text = "Show everyone, only people you grouped with, or only people you added. The icon at the start of each row shows which.",
      target = function(c) return c.groups end },
    { title = "Search",
      text = "Search your Kin by name.",
      target = function(c) return c.searchBox or c.groups end },
    { title = "Bonds",
      text = "Click a name to open their profile. Use the bond button or right-click to set what they are to you, like friend, family, mentor or rival. New bonds are added to your Chronicle. You can also whisper or remove someone here.",
      target = function(c) return c.list end },
    { title = "Adding someone",
      text = "Type a name and click Add to add someone you didn't group with.",
      target = function(c) return c.addBox or c end },
    { title = "Kin elsewhere",
      text = "Kin are marked on nameplates, can be filtered in the Directory, and Settings can limit letters to Kin only. People who share your house name appear on the Community page.",
    },
  },
})

---------------------------------------------------------------------------
-- House
---------------------------------------------------------------------------
K:RegisterGuide({
  id = "house", page = "house", title = "Your community",
  steps = {
    { title = "Your house",
      text = "A house is a family that shares a name. Set a house name on your profile to start one. Anyone with the same house name can join.",
      before = Tab(1),
      target = function(c) return Shown(c.none) or c.hero end },
    { title = "Crest",
      text = "Click the crest to choose any icon in the game. It's also pressed into the seal of your letters.",
      target = function(c) return c.crest end, pad = 6 },
    { title = "Motto",
      text = "A few words your house lives by. It shows on your profile and your house's card.",
      target = function(c) return c.motto end },
    { title = "History",
      text = "Write your house's history. It's shared with your profile, so other Kinship users can read it by clicking your house name.",
      target = function(c) return Up(c.desc) end },
    { title = "Members and claims",
      text = "Your own characters are always members. Other players with the same house name show as claims until you recognise them.",
      target = function(c) return c.members end },
    { title = "Recognise or ignore",
      text = "Click Recognise to accept someone, or right-click to ignore their claim. Only you see these choices.",
      target = function(c) return c.members end },
    { title = "Groups",
      text = "A group is for anything that isn't family, like a company, an order or an RP guild. Enter a name to start one, or use the same name as others to join them. Groups have their own banner, motto, history and members, and your rank shows on your tooltip.",
      before = Tab(2),
      target = function(c) return Shown(c.group.none) or c.group.hero end },
    { title = "Gatherings",
      text = "The Gatherings tab is for roleplay events. It has its own tour the first time you open it.",
      target = function(c) return c.tabs end },
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
    { title = "Your letters",
      text = "Letters are written in character and sent by in-game mail. Switch between letters you've received and letters you've sent.",
      target = function(c) return c.boxes end,
      before = function(c) c.guideOpened = nil end },
    { title = "The list",
      text = "Unopened letters show a bright seal. Sent letters show whether they're waiting, posted or returned.",
      target = function(c) return c.list end },
    { title = "Reading",
      text = "Select a letter to read it. Click the seal to open a new one. You can reply, or burn it to delete it.",
      target = function(c) return c.paper end,
      before = function(c)
        -- Stepping back from the writing step: put the sheet the tour opened away again.
        if c.guideOpened and c.mode == "write" then
          c.guideOpened, c.mode = nil, "read"
          K.Journal:RefreshCurrent()
        end
      end },
    { title = "Writing",
      text = "Click Write a letter to start a new one. Add who it's to, a title if you want, your message and a signature.",
      target = function(c) return Shown(c.write) or c.paper end,
      before = function(c)
        if c.mode ~= "write" then   -- never wipe a letter you were already writing
          c:Compose("")
          c.guideOpened = true
        end
        c.write.to.edit:ClearFocus()
      end },
    { title = "Handwriting, paper and cipher",
      text = "At the top, choose the handwriting, the paper's condition and an optional cipher. A cipher scrambles the letter with a key word you tell the reader in character.",
      target = function(c) return Shown(c.write) and c.write.hand end, pad = 6 },
    { title = "Seal",
      text = "Choose a wax colour, and click the seal to use your house crest or the Kinship logo.",
      target = function(c) return Shown(c.write) and c.write.seal end, pad = 8 },
    { title = "Enclosing items",
      text = "Enclose adds up to three kinds of Kinship items to the letter. They leave your bags when you seal it and arrive when it's opened. You can also send gold and game items from the mailbox as normal.",
      target = function(c) return Shown(c.write) and c.write.enclose end, pad = 6 },
    { title = "Posting",
      text = "Sealed letters wait in Sent until you visit a mailbox. The Kinship letters panel there shows what's waiting and the postage. Click Post them to send them as in-game mail. Players without Kinship get a normal letter.",
      target = function(c) return Shown(c.write) and c.write.send end },
    { title = "Letters from Kin only",
      text = "You can set Kinship to decline letters from anyone who isn't in your Kin. The sender isn't told.",
    },
  },
})

---------------------------------------------------------------------------
-- Chronicle
---------------------------------------------------------------------------
K:RegisterGuide({
  id = "chronicle", page = "chronicle", title = "Your Chronicle",
  steps = {
    { title = "Your Chronicle",
      text = "Your Chronicle fills in as you play. New places, levels, dungeons, battles, letters and the bonds you make are all added.",
      target = function(c) return Up(c.list, 2) end },
    { title = "Filter",
      text = "Show everything, or only one kind of entry, like places, dungeons, battles or pages you wrote.",
      target = function(c) return c.filterBtn end },
    { title = "Entries",
      text = "Entries are listed newest first. Click one to read it, with where it happened and your level at the time.",
      target = function(c) return c.list end },
    { title = "Your thoughts",
      text = "Click Write under an entry to add your character's thoughts, or Remove to delete it.",
      target = function(c) return Up(c.read, 2) end },
    { title = "A new page",
      text = "Write a page for things the game doesn't record, like a conversation or a promise. It's added to your timeline under Your own pages.",
      target = function(c) return c.writeBtn or Up(c.list, 2) end },
  },
})

---------------------------------------------------------------------------
-- Quests
---------------------------------------------------------------------------
K:RegisterGuide({
  id = "quests", page = "quests", title = "Quests",
  steps = {
    { title = "Quests",
      text = "Journal has the quests you're on, Write is for making your own, and Campaigns groups quests into longer stories. Quests are written by players.",
      target = function(c) return c.tabs end,
      before = Tab(1) },
    { title = "Your journal",
      text = "Quests you accept appear here. Switch between active, finished and set aside. Right-click a quest for more options.",
      target = function(c) return c.frames[1].list end,
      before = Tab(1) },
    { title = "Reading a quest",
      text = "Each quest has its story and objectives. You can track it, set it aside or mark it complete. Objectives tick as the quest's author updates them.",
      target = function(c) local f = c.frames[1]; return Shown(f.sheet) or f.empty end,
      before = Tab(1) },
    { title = "Writing a quest",
      text = "Add a title, quest giver and icon, write the story and list up to eight objectives. A campaign name links it to other quests. Rewards are optional.",
      target = function(c) return Up(c.frames[2].body, 2) end,
      before = Tab(2) },
    { title = "Preview",
      text = "The preview shows your quest as others will see it. It updates as you type.",
      target = function(c) return c.frames[2].preview end,
      before = Tab(2) },
    { title = "Sharing",
      text = "Save keeps it in your library. Share offers it to your group or your target, or lets you run it yourself. As the author, you tick objectives for everyone on the quest.",
      target = function(c) return c.frames[2].share end,
      before = Tab(2) },
    { title = "Campaigns",
      text = "Quests with the same campaign name are grouped here with your progress. Quests without one are listed as standalone, along with your drafts.",
      target = function(c) return c.frames[3].list end,
      before = Tab(3) },
    { title = "Campaign details",
      text = "Select a campaign to see its quests in order and who wrote them. Click a quest to read it, or to keep editing your own draft.",
      target = function(c) return c.frames[3].card end,
      before = Tab(3) },
    { title = "Tracker and quest log",
      text = "Tracked quests show under your objective tracker, and the quest log has a Roleplay tab. You can turn either off in Settings > Quests." },
    { title = "Map pins",
      text = "When writing a quest, you can set a level and pin its location or each objective. Pins show on the world map and minimap, and the tracker shows the distance." },
    { title = "Automatic objectives",
      text = "The lightning button next to an objective adds a rule, like reaching a pin, answering a riddle, winning a duel or rolling a check. You can add conditions, make it optional or hidden, or let it fail. Kinship ticks it off and tells the author." },
  },
})

---------------------------------------------------------------------------
-- Gatherings
---------------------------------------------------------------------------
K:RegisterGuide({
  id = "gatherings", page = "gatherings", title = "Gatherings",
  steps = {
    { title = "Events",
      text = "Roleplay events show here as cards with what, when, where and how many are going. Click one to open it.",
      target = function(c) return Shown(c.cards[1]) or c.emptyText end },
    { title = "Boards",
      text = "There are three boards: your guild, your house and a public board for nearby Kinship users. Posts go to the board you're viewing.",
      target = function(c) return c.scopes end },
    { title = "Sharing",
      text = "The guild board updates instantly. House and public boards spread as players meet.",
      target = function(c) return c.shareNote end },
    { title = "Posting",
      text = "Add a name, time, place and details. The place starts as where you're standing, and you're marked as going.",
      target = function(c) return c.postBtn or c end },
    { title = "Going",
      text = "Open a gathering to say you're going, see who else is, or copy it for Discord. Gatherings with a date can be added to your calendar. Only the host can edit or remove one.",
      target = function(c) return Shown(c.cards[1]) end },
    { title = "Shared by others",
      text = "A gathering shared by someone other than the host shows who shared it. It stays unconfirmed until the host's copy reaches you.",
    },
  },
})
