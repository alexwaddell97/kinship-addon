-- Kinship RP: guided tours for the Warfront, Inventory and Settings pages. See Guide.lua for how tours work.
local ADDON, ns = ...
local K = ns.K

---------------------------------------------------------------------------
-- Helpers
---------------------------------------------------------------------------
-- Switch a tabbed page (c.tab = i) and let it redraw.
local function ShowTab(c, i)
  c.tab = i
  K.Journal:RefreshCurrent()
end

local function Tab(i) return function(c) ShowTab(c, i) end end

-- An invisible frame stretched from a's top-left to b's bottom-right, so a
-- row or grid of controls can be lit as one. Made once per key.
local spans = {}
local function Span(key, a, b)
  if not (a and b) then return nil end
  local parent = a:GetParent()
  local s = spans[key]
  if not s or s:GetParent() ~= parent then
    s = CreateFrame("Frame", nil, parent)
    spans[key] = s
  end
  s:ClearAllPoints()
  s:SetPoint("TOPLEFT", a, "TOPLEFT")
  s:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT")
  return s
end

---------------------------------------------------------------------------
-- Warfront
---------------------------------------------------------------------------
-- The Parley tab's emote cards (first and last), for lighting the grid.
local function ParleySlots(tab)
  if tab.slots and #tab.slots > 0 then return tab.slots[1], tab.slots[#tab.slots] end
  local first, last
  for _, ch in ipairs({ tab:GetChildren() }) do
    if ch.sees and ch.label and ch.icon then
      first = first or ch
      last = ch
    end
  end
  return first, last
end

K:RegisterGuide({
  id = "warfront", page = "warfront", title = "The Warfront",
  steps = {
    { title = "Rivals, stance, parley",
      text = "Warfront is where your RP-PvP lives: the people you've clashed with, how you like fights to go, "
        .. "and a way to speak across the battle line. Your records here stay private to you.",
      before = Tab(1),
      target = function(c) return c.tabs end },
    { title = "Rivals and sightings",
      text = "Enemy players you target or mouse over are noted as sightings. Duels and honourable kills record "
        .. "themselves as victories and defeats. Switch between Rivals, Sighted and Everyone above the list.",
      before = Tab(1),
      target = function(c) return c.frames[1].list end },
    { title = "Your record with them",
      text = "Choose someone to see your tally of victories, defeats, draws and parleys, where you first met, "
        .. "and a standing from Respect to Nemesis. The notes are for your eyes only.",
      before = Tab(1),
      target = function(c) return c.frames[1].detail:GetParent() end },
    { title = "After a fall",
      text = "When you die, a card asks whether the enemy you were last facing brought you down, and one click "
        .. "records it. Fights settled with emotes and dice never reach the game, so log those by hand here.",
      before = Tab(1),
      target = function(c) return c.frames[1].detail end },
    { title = "Your war stance",
      text = "Choose how you like PvP stories to go: open war, honour first, or staying out of it. Others see it "
        .. "on your tooltip and profile, and the chip at the top right of this page shows yours.",
      before = Tab(2),
      target = function(c) return c.frames[2].stances[1]:GetParent() end },
    { title = "Consent",
      text = "Yes, Ask or No for injury, death, capture, crime and romance. It's shared through the standard "
        .. "roleplay fields (MSP), so other RP addons read it, and Kinship's wounds and captures always respect it.",
      before = Tab(2),
      target = function(c) return c.frames[2].consent[1]:GetParent() end },
    { title = "Across the line",
      text = "The other faction can't read your words, and your own emotes reach them as strange gestures. "
        .. "The game's built-in emotes are the only thing that gets through, so Parley keeps the useful ones close.",
      before = Tab(3),
      target = function(c) return c.frames[3].key:GetParent() end },
    { title = "The emotes",
      text = "Each card says what the other side will see. Click one to use it now on your target, or on everyone "
        .. "nearby if you have none. A parley with an enemy is added to your record with them.",
      before = Tab(3),
      target = function(c)
        local a, b = ParleySlots(c.frames[3])
        return Span("parley", a, b)
      end },
    { title = "Hold, aim, release",
      text = "Bind a key in Key Bindings, under AddOns > Kinship RP. Hold it to open the wheel at your cursor, "
        .. "point toward an emote and let go. Right-click or Esc closes it without sending anything.",
      before = Tab(3),
      target = function(c) return c.frames[3].key end,
      pad = 8 },
  },
})

---------------------------------------------------------------------------
-- Inventory
---------------------------------------------------------------------------
-- Choose something in the bags if nothing is chosen, so the item card has
-- something to show.
local function PickItem(c)
  local tab = c.frames and c.frames[1]
  local I = K.Items
  if not tab or tab.sel or not I or not I.Bag then return end
  local bag = I:Bag()
  for i = 1, I.SLOTS or 0 do
    if bag[i] then tab.sel = i break end
  end
end

K:RegisterGuide({
  id = "inventory", page = "inventory", title = "Your inventory",
  steps = {
    { title = "Carry, make, write",
      text = "Everything your character carries, makes and writes lives here. Each tab follows its own switch "
        .. "under Extended features in Settings, so anything you've turned off stays out of the way.",
      before = Tab(1),
      target = function(c) return c.tabs end },
    { title = "Your bags",
      text = "Drag an item to move it, right-click to use it, and shift-click a stack to split it in two. "
        .. "The chip at the top tells you how much room is left. Your items also sit in a satchel beside your game bags.",
      before = Tab(1),
      target = function(c) return c.frames[1].cells[1]:GetParent() end },
    { title = "A closer look",
      text = "Choose an item to see it up close: its description, what happens when you use it, any writing "
        .. "it carries, and who made it.",
      before = function(c) PickItem(c); ShowTab(c, 1) end,
      target = function(c) return c.frames[1].card end },
    { title = "What you can do",
      text = "Use it, Give it to another Kinship player, or Stash it out in the world. Split halves a stack, "
        .. "Edit design opens your own designs in the Workshop, and Destroy asks twice before it throws anything away.",
      before = function(c) PickItem(c); ShowTab(c, 1) end,
      target = function(c)
        local d = c.frames[1].detail
        return Span("itemButtons", d.use, d.destroy)
      end },
    { title = "Stashes",
      text = "Search the area for stashes other players have left nearby; hidden ones only turn up when you're "
        .. "standing right on top of them. Your stashes lists everything you've left out, and where.",
      before = Tab(1),
      target = function(c)
        local tab = c.frames[1]
        return Span("stashButtons", tab.search, tab.stashes)
      end },
    { title = "What you're wearing",
      text = "Worn is where your character gets dressed in roleplay: a hood, a ring, a blade at the hip. "
        .. "It has a short tour of its own the first time you open it.",
      before = Tab(5),
      target = function(c) return c.frames[5] end },
    { title = "The Workshop",
      text = "Design the things your character carries: keepsakes, potions, writs, trinkets. Give each a name, "
        .. "icon, quality and an emote for when it's used, then put as many as you like in your bags. "
        .. "Choose Worn on to make it something your character wears.",
      before = Tab(2),
      target = function(c) return c.frames[2].card end },
    { title = "The writing desk",
      text = "Write books, notices and contracts of up to ten pages, on parchment, vellum or a pinned notice, "
        .. "with a wax seal if you like. Make an item from one, and whoever holds it can read it.",
      before = Tab(3),
      target = function(c) return c.frames[3].card end },
    { title = "The Database",
      text = "Creations from Total RP 3: Extended live here. Import takes an export string from Extended Tools, "
        .. "and Export gives one back for Extended or another Kinship player. Anything that needs your permission to run says so.",
      before = Tab(4),
      target = function(c) return c.frames[4] end },
  },
})

-- The Worn tab: its own tour, the first time it's opened (PageInventory.lua),
-- and from the ? while it's showing.
local WORN = 5
local function Worn(c) return c.frames and c.frames[WORN] end

K:RegisterGuide({
  id = "worn", title = "What you're wearing",
  steps = {
    { title = "Dressed for the part",
      text = "This is your character as you picture them: the hood, the locket, the sword they never leave behind. "
        .. "These are roleplay items, made in the Workshop. They don't touch your real gear or your stats.",
      before = Tab(WORN),
      target = function(c) return Worn(c).stage end },
    { title = "A slot for every piece",
      text = "There's a slot for each piece of gear on the character screen, down both sides: head to wrists on "
        .. "the left, hands to two rings and a charm on the right, and what you hold along the bottom. "
        .. "Hover a slot to see its name. Each item fits one of them.",
      before = Tab(WORN),
      target = function(c)
        local s = Worn(c).slots
        return s and Span("wornSlots", s[1], s[8])
      end },
    { title = "Putting things on",
      text = "Anything in your bags that can be worn is listed here. Click it, or drag it onto its slot. "
        .. "If something's already there, the two swap and the old one goes back in your bags. "
        .. "You can drag straight from the satchel too.",
      before = function(c) ShowTab(c, WORN); local t = Worn(c); if t and t.ShowView then t:ShowView("wear") end end,
      target = function(c) return Worn(c).fit end },
    { title = "Taking things off",
      text = "Right-click a slot to take off what's in it, or drag it back to a bag slot of your choosing. "
        .. "A plain click opens a menu of everything you carry that fits there.",
      before = Tab(WORN),
      target = function(c) local s = Worn(c).slots return s and s[1] end },
    { title = "On your character screen",
      text = "Open your character screen and choose its Roleplay tab. While it's open, the gear slots beside "
        .. "your character show what you wear in roleplay instead, and work just like these: drag from your "
        .. "satchel to put things on, right-click to take them off." },
    { title = "Outfits",
      text = "Save what you have on as an outfit: travelling clothes, your court finery, what you fight in. "
        .. "Click one to change into it in one go. Right-click to save over it, rename it, or tie it to a "
        .. "profile so switching profiles changes your clothes too. /kin outfit and its name works in a macro.",
      before = function(c) ShowTab(c, WORN); local t = Worn(c); if t and t.ShowView then t:ShowView("outfits") end end,
      target = function(c) return Worn(c).outfits end },
    { title = "Who sees it",
      text = "Other Kinship users see what you wear around your character on your profile, with each item's "
        .. "name, quality and a line of its description. Other roleplay addons won't show it.",
      before = Tab(WORN),
      target = function(c) return Worn(c).fitNote end },
    { title = "Something new to wear",
      text = "Nothing to wear yet? Open the Workshop, design an item, and set Worn on to the slot it goes in. "
        .. "Make as many as you like.",
      before = function(c) ShowTab(c, WORN); local t = Worn(c); if t and t.ShowView then t:ShowView("wear") end end,
      target = function(c) return Worn(c).work end },
  },
})

---------------------------------------------------------------------------
-- Settings
---------------------------------------------------------------------------
local function SettingsCard(c, id)
  for _, card in ipairs(c.cards or {}) do
    if card.def and card.def.id == id and card:IsShown() then return card end
  end
end

-- Scroll the settings so a card (or the top, for nil) is in view.
local function ScrollTo(c, card)
  local sf = c.child and c.child:GetParent()
  if not sf or not sf.SetVerticalScroll then return end
  local y = 0
  if card then
    local _, _, _, _, oy = card:GetPoint(1)
    y = -(oy or 0)
  end
  local range = math.max(0, c.child:GetHeight() - sf:GetHeight())
  sf:SetVerticalScroll(math.max(0, math.min(range, y)))
end

local function CardStep(id, title, text)
  return {
    title = title, text = text,
    before = function(c) ScrollTo(c, SettingsCard(c, id)) end,
    target = function(c) return SettingsCard(c, id) end,
  }
end

K:RegisterGuide({
  id = "settings", page = "settings", title = "Settings",
  steps = {
    { title = "A card for everything",
      text = "Settings come as a stack of cards, one for each part of Kinship. Scroll to find the one you want. "
        .. "Cards for a feature you've switched off stay hidden until you turn it back on.",
      before = function(c) ScrollTo(c, nil) end,
      target = function(c) return c.child and c.child:GetParent() end },
    { title = "Search by what it does",
      text = "Type what you're after, in your own words: nameplates, pvp, map pins, mature. Matching cards come first "
        .. "with the right lines lit, and small typos are fine. Add off or on to find switches in that state.",
      target = function(c) return c.search end },
    CardStep("guides", "Guides",
      "Turn these tours off here, or show every one again. The ? at the top of the journal replays the tour "
        .. "for whichever page you're on."),
    CardStep("profiles", "Profiles",
      "Back up a profile as a block of text, move it to another character, or share it with a friend. "
        .. "Importing one is just as quick."),
    CardStep("chat", "Roleplay chat",
      "Roleplay names in chat, coloured emotes and speech, and greyed-out (( out of character )) text. "
        .. "It works in say, emote, party, raid, guild and whispers."),
    CardStep("safety", "Safety",
      "A filter that covers profiles using words from your list, and everyone you've ignored. "
        .. "Someone you ignore disappears from Kinship everywhere."),
    CardStep("extended", "Extended features",
      "Items, documents, effects and anything that reads Total RP 3: Extended creations. Switching something "
        .. "off takes effect at once; switching it on needs a reload."),
  },
})
