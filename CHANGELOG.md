# Kinship RP changelog

## Unreleased

### New
- Letters go by post. Seal a letter anywhere and it waits in your Sent
  letters until you next open a mailbox, where Kinship posts it as game mail,
  so it reaches people even when they're offline, and your own characters
  too. Kinship letters wear the Kinship seal in the mailbox, and Kinship
  keeps them on your Letters page, sealed until you open them. People without
  Kinship get an ordinary, readable mail. Long letters go in parts and are
  joined back together.
- Write in your character's hand (plain, fine or a rough scrawl), on paper
  that arrives pristine, aged or singed.
- Ciphers: scramble a letter with a key word you tell them in character.
  Without it, the letter is nonsense; with it, Decipher reveals the words.
- Name suggestions: typing a name in a letter's To box, Give an item or Add
  to Kin offers your own characters, your Kin, the people you've written to
  and your Directory. It matches either of a character's names, or their
  roleplay name.
- Enclose Kinship items in a letter, up to three kinds: they leave your bags
  when you seal it and go into theirs when they break the seal. Real gold and
  game items on the Send Mail tab can go with a letter too.

## 1.1.1

**After updating, restart the game fully** (not just /reload): Kinship's
files have moved into folders, and the game only picks up new files when it
starts.

### Fixes
- The quest editor no longer throws errors when the theme changes before a
  quest is open.

### Behind the scenes
- Kinship's files are organised into folders, and every release is checked
  for mistakes before it goes out.
- New releases go to CurseForge and GitHub at the same time.

## 1.1.0

### New
- Kinship works alongside Total RP 3. When both are running, Kinship asks
  once: keep both, or move to Kinship.
  - Keep both: Total RP 3 looks after your profile, tooltips, nameplates,
    chat names, status and target bar. Kinship hides its own versions and
    keeps everything Total RP 3 doesn't have: quests you write, worn items
    and outfits, your stage, houses, Warfront, letters, the satchel and the
    rest. Your name, house and RP style come from Total RP 3, and your
    Kinship profiles are left as they were.
  - Move to Kinship: your Total RP 3 profiles come across, Total RP 3 and
    its add-ons are switched off, and the game reloads. Their saved data
    isn't touched, so you can switch back any time.
- With Total RP 3: Extended running too, Kinship asks who looks after items,
  documents and effects: Kinship (and Extended can be switched off), or
  Extended (and Kinship switches its own off, keeping quests and the rest).
- Total RP 3's target bar gets a Kinship button: what someone wears, their
  house and their stage.
- When keeping both, Preview and View profile open Total RP 3's profile
  window.
- Switching Total RP 3 profiles changes your outfit too, if you've tied
  one to it.
- A Kinship minimap button: click for your journal, right-click for
  Settings. It can be hidden under Settings > General.
- Change your mind any time under Settings > General.

### Fixes
- If the game ever blocks something Kinship asked for, it's noted for
  /kin bug, to help track it down.

## 1.0.9

- Fixed: members' names on a house card were hard to read (gold on the
  light card) and could be cut short. They're now in the card's own ink,
  with the character's name softer beside them, and use the whole row.

## 1.0.8

### New
- Wear your roleplay items. Mark a Workshop design as something you wear
  ("Worn on") and put it on: a hood, a ring, a charm, the blade at your hip.
  There's a slot for every piece of gear on the character screen, nineteen
  in all, from head and shoulders to two rings, a charm and what you carry.
- A new Worn tab on the Inventory page shows your character with their
  slots around them, laid out like the character screen, and lists what in
  your bags can be worn.
- Drag items from your bags or satchel onto a slot to put them on, and drag
  them back to take them off. Right-click a slot to take its item off.
- On the character screen's Roleplay tab, the gear slots show your
  roleplay items instead of your real gear.
- Other Kinship users see what you wear on your profile, as a neat column
  of items beside your character, each ringed in its quality colour.
- Outfits: save what you have on under a name, then change into it with one
  click, or from a macro with /kin outfit and its name. Tie an outfit to a
  profile and switching to that profile changes your clothes too. Saving
  under a name you already use warns you first.
- The Worn tab has a short tour of its own.

### Fixes
- The character window keeps your portrait on the Roleplay tab, instead of
  showing Kinship's icon.
- Stat text from some character screen skins no longer shows faintly
  through the Roleplay pane.

### New
- Houses have their own card. Click "of House ..." on any profile to see the
  house's crest, motto, history and the members you know of, and click a
  member to open their profile.
- A house's history now travels with your profile, so other Kinship users
  can read it.
- Profiles are easier to read: a new Nature tab holds personality and traits,
  and About keeps the essentials, with identity and boundaries on one line
  each.
- Settings > General has a Key bindings button.

### Fixes
- Kinship's key bindings now show up, under Key Bindings > AddOns > Kinship RP.
- Trait bars on profiles line up, each under its two traits.
- The value you see while dragging a trait slider no longer overlaps the
  next trait.
- Search box hints stay inside their boxes.
- Preview brings your profile back to the front if it was behind the journal.
- Window titles keep the character's name beside the roleplay name, as
  everywhere else.
- The tours are updated for all of the above.

## 1.0.6

- New look for Kinship's icon: a simple gold K, in the same gold as
  Kinship's headings.
- Icons throughout Kinship (notes, Kin, gatherings, places, milestones,
  battles) now use the game's own icons.
- Panels and documents lose their leather and paper textures for plain
  colours, which keeps the look cleaner.
- Removed artwork that wasn't used any more, so the download is smaller.

## 1.0.5

- Fixed: the Whisper option on the Directory and Kin pages now works on
  newer clients too. If the client can't start a whisper directly, it opens
  "/w Name" in your chat box instead.
- The satchel button checks the bag bar a little less often, for a touch
  less work each frame.
- Tidied the code and removed internal developer notes from the download.

## 1.0.4

### New
- Set the stage for your profile. The palette button on your own profile
  picks a backdrop (seven scenes, or a colour of your own), an optional
  spotlight, and what's under your character's feet: a shadow, a pool of
  light, or nothing. Other Kinship users see the stage you chose.
- Gatherings can go on the game's calendar. A gathering with a date has an
  "Add to calendar" button, and saying you're going adds it too (switch that
  off under Settings > Gatherings). It goes on your own calendar only.

### Fixes
- Clicking a profile link in chat now opens the profile.
- In the theme music list, a track's name no longer runs under the "Your
  theme" tag.

### Tidied
- The Kin page's "Shared a fire" tab is gone: nothing ever filled it.
- Three Extended switches that didn't do anything yet (Cutscenes, Workflows
  and Total RP 3 users) are hidden until they do.

## 1.0.3

- Fixed: a quest kill could count twice when you clicked the corpse to loot
  it. Each enemy now counts once.
- Fixed: on the profile viewer, the roleplay experience tag (such as "Happy to
  help newcomers") could run off the edge of the card. It now moves to the
  house line when there isn't room.

## 1.0.2

- Fixed: with EllesmereUI unit frames, a 2D portrait (often your own) could
  stay blank after loading in. Kinship now redraws it once the art is ready.

## 1.0.1

### A satchel by your bags
- Your Kinship items now have a bag of their own: a satchel button at the end
  of your bag bar, and a satchel window that opens and closes with your bags,
  docked beside them.
- It takes on the look of the bags you use: EllesmereUI Bags, or the game's
  own bags, where it stands as tall as they do. Your bags' search box searches
  it too.
- Hover for the tooltip, right-click to use, drag to move or stack, and
  shift-click to split.
- Search and Stashes open a small stash pane beside the satchel: stashes
  found nearby, or your own, and what's in them to take.
- Minimise it to a thin strip when you're not roleplaying. It still comes up
  with your bags, out of the way, until you click it.
- The bag-bar button matches the bag bar's own buttons (EllesmereUI's skin
  included) and follows its visibility settings, fading and hiding with it.
- New settings under Items & stashes, a key binding, and `/kin satchel`.

### Roleplay names you can always read
- Roleplay names are the same gold everywhere: tooltips, nameplates, unit
  frames and chat.
- The character's real name is always shown beside them, so whispers,
  invites and /who are never a guess. On nameplates the roleplay name now sits
  above the character name instead of replacing it.
- Your own chat lines now show your roleplay name too.
- Someone who speaks before their profile has arrived now has it asked for,
  so their next line shows their roleplay name.
- "Colour by relationship" on nameplates now colours the ring round the
  status dot.

## 1.0.0 (first public release)

Kinship is a roleplay addon for World of Warcraft Forever. This is the first
version released to everyone.

### Profiles and persona
- A full roleplay profile: name and title, pronouns, age, home, appearance,
  personality and history.
- Keep several profiles per character and switch between them.
- In Character, Looking for RP and Out of Character status, set from the
  journal, the character sheet or a small status button.
- Glances, personality traits and short-term effects such as wounds and boons.
- Share any profile as a block of text (`/kin share`, `/kin import`).

### Houses
- Characters who share a family name can form a house with a crest, motto and
  history.

### Directory and tooltips
- Every roleplay profile you come across is kept in the directory, whichever
  addon the other player uses (Mary Sue Protocol).
- Filter by in character, looking for roleplay, your Kin, and players new to
  roleplay or offering to help them.
- Tooltips show roleplay name, house, status, war stance, boundaries and what
  someone is up to.

### Roleplay quests
- Write your own quests and offer them to the players around you, or run one
  as its storyteller.
- Automatic objectives: reach a place or keep watch, talk to someone or emote
  at them, carry, gather or wear items, find a stash, pass a dice roll, answer
  a riddle, defeat enemies, win a duel, take on an effect, read a document,
  turn up at a certain hour, with extra conditions on top.
- Optional and hidden objectives.
- Failure options: try again, carry on, open a backup objective, or fail the
  whole quest.
- Item rewards, fixed or chosen by the player, sent on completion and retried
  later if someone is offline.
- A section in the objective tracker, a tab in the quest log, and pins on the
  world map and minimap.

### Items, documents and stashes
- Design your own items, write letters and documents, and seal them with wax.
- Hand items to other players, and hide them in stashes for someone to find.

### Character sheet
- A Roleplay tab on the character sheet with your status, notes, glances,
  effects and boundaries.
- Optional roleplay names in window titles and on unit frames.

### RP-PvP
- War stances: Open war, Honour first or Non-combatant.
- Boundaries for injury, death, capture, crime and romance, each set to yes,
  ask first or no.
- The Warfront page: enemies you've met, rivals and past battles, recorded in
  your Chronicle if you like.
- Parley, a wheel of the game's own emotes the other faction can see.

### Settings
- A search box that finds settings by what they do, with suggestions as you
  type.
- Back up everything: one copyable text holding all of Kinship's saved data
  for your account, and a way to restore it (Settings > General).

### Moving from Total RP 3
- Copy your Total RP 3 profiles into Kinship: names, descriptions, glances,
  traits, status and more. Total RP 3's own saved data is left untouched.

### Other
- `/kin bug` opens a report to copy into a bug report: Kinship's version, the
  game build, recent errors Kinship caught and your loaded addons.
- Saved data now carries a version number, so later updates can upgrade older
  saves safely.
