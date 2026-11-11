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
    { title = "Warfront",
      text = "Warfront is for RP-PvP: the players you've fought, how you approach PvP, and emotes the other faction can see. Your records here are private.",
      before = Tab(1),
      target = function(c) return c.tabs end },
    { title = "Rivals and sightings",
      text = "Enemy players you target or mouse over are saved as sightings. Duels and honourable kills count as wins and losses. Switch between Rivals, Sighted and Everyone above the list.",
      before = Tab(1),
      target = function(c) return c.frames[1].list end },
    { title = "Your record",
      text = "Select someone to see your wins, losses, draws and parleys, where you first met, and your standing, from Respect to Nemesis. Notes are only visible to you.",
      before = Tab(1),
      target = function(c) return c.frames[1].detail:GetParent() end },
    { title = "Logging fights",
      text = "When you die in world PvP, Kinship asks if your last enemy killed you. Log fights settled with emotes and dice here by hand. Your record also shows next to the PvP window, and rivals are marked on nameplates.",
      before = Tab(1),
      target = function(c) return c.frames[1].detail end },
    { title = "War stance",
      text = "Choose how you like PvP to go: open war, honour first, or staying out of it. Others see it on your tooltip and profile.",
      before = Tab(2),
      target = function(c) return c.frames[2].stances[1]:GetParent() end },
    { title = "Boundaries",
      text = "Your Yes, Ask or No answers for injury, death, capture, crime and romance. The button takes you to your profile to change them.",
      before = Tab(2),
      target = function(c) return c.frames[2].consent[1]:GetParent() end },
    { title = "Parley",
      text = "The other faction can't read your chat, and custom emotes show as strange gestures. Only the game's built-in emotes get through, so Parley puts the useful ones in one place.",
      before = Tab(3),
      target = function(c) return c.frames[3].key:GetParent() end },
    { title = "Emotes",
      text = "Each card shows what the other side will see. Click one to use it on your target, or on everyone nearby if you have no target. Parleys with enemies are added to your record.",
      before = Tab(3),
      target = function(c)
        local a, b = ParleySlots(c.frames[3])
        return Span("parley", a, b)
      end },
    { title = "The Parley wheel",
      text = "Set a key in Key Bindings under AddOns > Kinship RP. Hold it to open the wheel, point at an emote and let go. Right-click or Esc closes it.",
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
    { title = "Inventory",
      text = "Your items, designs and documents. Each tab can be turned off under Extended features in Settings.",
      before = Tab(1),
      target = function(c) return c.tabs end },
    { title = "Your bags",
      text = "Drag to move an item, right-click to use it, and shift-click to split a stack (or link it while typing in chat). The top shows how much space is left. Your items are also in a satchel next to your game bags.",
      before = Tab(1),
      target = function(c) return c.frames[1].cells[1]:GetParent() end },
    { title = "Item details",
      text = "Select an item to see its description, what it does when used, any writing on it, and who made it.",
      before = function(c) PickItem(c); ShowTab(c, 1) end,
      target = function(c) return c.frames[1].card end },
    { title = "Item actions",
      text = "Use it, Give it to another Kinship user, or Stash it in the world. Split halves a stack, Edit design opens it in the Workshop, and Destroy asks you to confirm.",
      before = function(c) PickItem(c); ShowTab(c, 1) end,
      target = function(c)
        local d = c.frames[1].detail
        return Span("itemButtons", d.use, d.destroy)
      end },
    { title = "Trades and the bank",
      text = "When trading with a Kinship user, right-click Kinship items into the panel next to the trade window. At a banker, your Kinship vault opens next to the bank. Right-click to store an item, click to take it out.",
      before = Tab(1),
      target = function(c) return c.frames[1].cells[1]:GetParent() end },
    { title = "Stashes",
      text = "Search the area for stashes other players left nearby. Hidden ones only show when you're standing on them. Your stashes lists everything you've left and where.",
      before = Tab(1),
      target = function(c)
        local tab = c.frames[1]
        return Span("stashButtons", tab.search, tab.stashes)
      end },
    { title = "Worn",
      text = "Worn is where you dress your character in roleplay items. It has its own tour the first time you open it.",
      before = Tab(5),
      target = function(c) return c.frames[5] end },
    { title = "Workshop",
      text = "Design your own items with a name, icon, quality and an emote for when they're used. Make as many copies as you want. Set Worn on to make one wearable.",
      before = Tab(2),
      target = function(c) return c.frames[2].card end },
    { title = "Writing desk",
      text = "Write books, notices and contracts up to ten pages long, with a paper style and an optional wax seal. Turn one into an item so whoever holds it can read it.",
      before = Tab(3),
      target = function(c) return c.frames[3].card end },
    { title = "Database",
      text = "Holds creations from Total RP 3: Extended. Import takes an export string from Extended Tools, and Export creates one. Anything that needs your permission to run will ask.",
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
    { title = "Roleplay outfit",
      text = "This shows your character in their roleplay items, made in the Workshop. They don't change your real gear or stats.",
      before = Tab(WORN),
      target = function(c) return Worn(c).stage end },
    { title = "Slots",
      text = "There's a slot for each gear slot on the character screen. Hover a slot to see its name. Each item fits one slot.",
      before = Tab(WORN),
      target = function(c)
        local s = Worn(c).slots
        return s and Span("wornSlots", s[1], s[8])
      end },
    { title = "Wearing items",
      text = "Wearable items in your bags are listed here. Click one or drag it onto its slot. If the slot is full, the old item goes back to your bags. You can drag from the satchel too.",
      before = function(c) ShowTab(c, WORN); local t = Worn(c); if t and t.ShowView then t:ShowView("wear") end end,
      target = function(c) return Worn(c).fit end },
    { title = "Removing items",
      text = "Right-click a slot to remove its item, or drag it to a bag slot. Left-click a slot to see everything you have that fits it.",
      before = Tab(WORN),
      target = function(c) local s = Worn(c).slots return s and s[1] end },
    { title = "Character screen",
      text = "On your character screen's Roleplay tab, the gear slots show your roleplay items and work the same way." },
    { title = "Outfits",
      text = "Save what you're wearing as an outfit and click it to change in one go. Right-click to update, rename or link it to a profile, so switching profiles changes your outfit. You can use /kin outfit and its name in a macro.",
      before = function(c) ShowTab(c, WORN); local t = Worn(c); if t and t.ShowView then t:ShowView("outfits") end end,
      target = function(c) return Worn(c).outfits end },
    { title = "Who can see it",
      text = "Other Kinship users see your roleplay items on your profile, with each item's name, quality and description. Other RP addons don't show them.",
      before = Tab(WORN),
      target = function(c) return Worn(c).fitNote end },
    { title = "Making new items",
      text = "To make something new, open the Workshop, design an item and set Worn on to its slot.",
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
    { title = "Settings",
      text = "Settings are grouped into cards, one for each part of Kinship. Cards for features you've turned off are hidden.",
      before = function(c) ScrollTo(c, nil) end,
      target = function(c) return c.child and c.child:GetParent() end },
    { title = "Search",
      text = "Type what you're looking for, like nameplates, pvp or map pins. Matching cards show first, with the matching options highlighted. Add on or off to find options that are on or off.",
      target = function(c) return c.search end },
    CardStep("guides", "Guides",
      "Turn tours off here, or reset them. Click ? at the top of the journal to replay the tour for the current page."),
    CardStep("profiles", "Profiles",
      "Export a profile as text to back it up, use it on another character or share it. You can import one here too."),
    CardStep("chat", "Roleplay chat",
      "Roleplay names in chat, coloured emotes and speech, and greyed-out (( OOC )) text. Works in say, emote, party, raid, guild and whispers."),
    CardStep("safety", "Safety",
      "The mature content filter and your ignore list. Ignored players are hidden everywhere in Kinship."),
    CardStep("extended", "Extended features",
      "Items, documents, effects and support for Total RP 3: Extended creations. Turning a feature off works straight away. Turning it on needs a reload."),
  },
})
