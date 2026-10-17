-- Kinship RP: worn items. Nineteen roleplay slots, one for each of the
-- character screen's gear slots (head and neck down to the ring, charm and
-- what you carry), for the Kinship items your character has on. A design says which slot it fits
-- (the Workshop's "Worn on"); wearing one takes it out of your bags and
-- taking it off puts it back. What you wear shows on your Roleplay pane and
-- around your character on the profile stage, and travels with your profile
-- (field KQ: name, icon, quality and a short description per slot) so other
-- Kinship users see it too. Other addons ignore the field.

local ADDON, ns = ...
local K = ns.K
local UI = K.UI
local I = K.Items
local W = {}
K.Worn = W

local DESC_MAX = 140   -- characters of each worn item's description that travel

-- What you have on: [slot key] = { def = item id }
function W:Table()
  local key = K:CharKey()
  local inv = K.db.inventory[key]
  if type(inv) ~= "table" then inv = {}; K.db.inventory[key] = inv end
  if type(inv.worn) ~= "table" then inv.worn = {} end
  return inv.worn
end

-- The design worn in a slot (yours), or nil.
function W:In(slot)
  local e = self:Table()[slot]
  return e and I:Get(e.def), e
end

-- While an outfit goes on, each piece changing waits: one refresh, one
-- sound and one publish at the end instead of one per piece.
local batch

local function Changed()
  if batch then batch.dirty = true return end
  K:Fire("INVENTORY")
  K:Fire("WORN")
  if K.Comm and K.Comm.SchedulePublish then K.Comm:SchedulePublish() end
end

local function Sound(on)
  if batch then batch.sound = batch.sound or on return end
  if on then
    if SOUNDKIT and SOUNDKIT.PUT_DOWN_SMALL_CHAIN then PlaySound(SOUNDKIT.PUT_DOWN_SMALL_CHAIN)
    elseif SOUNDKIT and SOUNDKIT.IG_BACKPACK_OPEN then PlaySound(SOUNDKIT.IG_BACKPACK_OPEN) end
  elseif SOUNDKIT and SOUNDKIT.IG_BACKPACK_CLOSE then
    PlaySound(SOUNDKIT.IG_BACKPACK_CLOSE)
  end
end

-- Put on the item in a bag slot. A stack gives up one; whatever was in that
-- slot comes back to your bags in its place.
function W:Wear(bagIndex)
  local bag = I:Bag()
  local s = bag[bagIndex]
  local def = s and I:Get(s.def)
  if not def then return false end
  local slot = def.wear
  if not (slot and I.WEAR_LABEL[slot]) then I.Error(UI.Escape(def.name) .. " isn't something you wear.") return false end
  if I:Available(def.id) < 1 then I.Error("That item is promised in a trade.") return false end
  local worn = self:Table()
  local old = worn[slot]
  -- Room for what comes off: the bag slot it frees, or a spare one.
  if old and s.count > 1 and I:FreeSlots() == 0 then
    local oldDef = I:Get(old.def)
    local stacks = false
    for i = 1, I.SLOTS do
      local b = bag[i]
      if b and b.def == old.def and oldDef and b.count < oldDef.stack then stacks = true end
    end
    if not stacks then I.Error("There's no room in your bags for what you're wearing there.") return false end
  end
  s.count = s.count - 1
  if s.count <= 0 then bag[bagIndex] = nil end
  worn[slot] = { def = def.id }
  if old then
    if not bag[bagIndex] then bag[bagIndex] = { def = old.def, count = 1 } else I:Add(old.def, 1) end
  end
  Sound(true)
  Changed()
  return true
end

-- Take off what's in a slot, back into your bags: into bag slot toIndex if
-- it's given and empty, swapped for what's there if that fits the same slot,
-- or wherever there's room.
function W:TakeOff(slot, toIndex)
  local worn = self:Table()
  local e = worn[slot]
  if not e then return false end
  if not I:Get(e.def) then worn[slot] = nil; Changed() return true end   -- its design is gone
  local bag = I:Bag()
  local there = toIndex and bag[toIndex]
  if there then
    local def = I:Get(there.def)
    if def and def.wear == slot and there.def ~= e.def then return self:Wear(toIndex) end
  end
  if toIndex and toIndex >= 1 and toIndex <= I.SLOTS and not there then
    bag[toIndex] = { def = e.def, count = 1 }
  elseif I:Add(e.def, 1) > 0 then I.Error("There's no room in your bags to take it off.") return false end
  worn[slot] = nil
  Sound(false)
  Changed()
  return true
end

-- Bag slots holding something that fits a slot: { { index, def, count } }
function W:Fitting(slot)
  local out, seen = {}, {}
  local bag = I:Bag()
  for i = 1, I.SLOTS do
    local s = bag[i]
    local def = s and I:Get(s.def)
    if def and def.wear == slot and not seen[def.id] then
      seen[def.id] = true
      out[#out + 1] = { index = i, def = def, count = s.count }
    end
  end
  return out
end

---------------------------------------------------------------------------
-- Outfits: named sets of what you wear, saved per character, to change into
-- with one click (the Worn tab) or from a macro (/kin outfit Name).
--   { name = "At court", slots = { [slot] = item id } }
-- An outfit is the whole look: changing into it takes off anything it
-- doesn't have, and anything it has that isn't in your bags is left off.
---------------------------------------------------------------------------
W.OUTFIT_MAX, W.OUTFIT_NAME = 20, 32

function W:Outfits()
  local key = K:CharKey()
  local inv = K.db.inventory[key]
  if type(inv) ~= "table" then inv = {}; K.db.inventory[key] = inv end
  if type(inv.outfits) ~= "table" then inv.outfits = {} end
  return inv.outfits
end

local function CleanName(name)
  name = strtrim(UI.Clean and UI.Clean(tostring(name or "")) or tostring(name or ""))
  return I.Cut(name, W.OUTFIT_NAME)
end

function W:FindOutfit(name)
  name = CleanName(name):lower()
  if name == "" then return nil end
  for i, o in ipairs(self:Outfits()) do
    if o.name:lower() == name then return o, i end
  end
end

-- What you have on now, as an outfit's slots.
local function Snapshot()
  local slots = {}
  for slot, e in pairs(W:Table()) do
    if I.WEAR_LABEL[slot] and type(e) == "table" and e.def and I:Get(e.def) then slots[slot] = e.def end
  end
  return slots
end

-- Save what you're wearing under a name: a new outfit, or over the one
-- already called that. Returns the outfit, or nil and why not.
function W:SaveOutfit(name)
  name = CleanName(name)
  if name == "" then return nil, "Give the outfit a name." end
  local o = self:FindOutfit(name)
  local list = self:Outfits()
  if not o then
    if #list >= W.OUTFIT_MAX then return nil, ("You can keep up to %d outfits."):format(W.OUTFIT_MAX) end
    o = { name = name }
    list[#list + 1] = o
  end
  o.name, o.slots = name, Snapshot()
  K:Fire("WORN")
  return o
end

function W:RenameOutfit(o, name)
  name = CleanName(name)
  if name == "" then return false, "Give the outfit a name." end
  local other = self:FindOutfit(name)
  if other and other ~= o then return false, "You already have an outfit called that." end
  o.name = name
  K:Fire("WORN")
  return true
end

function W:DeleteOutfit(o)
  for i, x in ipairs(self:Outfits()) do
    if x == o then table.remove(self:Outfits(), i); K:Fire("WORN") return true end
  end
  return false
end

-- How an outfit stands: pieces in it, pieces you have (worn or in your bags),
-- and whether you're wearing exactly it.
function W:OutfitState(o)
  local pieces, have, exact = 0, 0, true
  local worn = self:Table()
  for _, w in ipairs(I.WEAR) do
    local want = o.slots and o.slots[w.key]
    local cur = worn[w.key] and worn[w.key].def
    if want then
      pieces = pieces + 1
      if cur == want or (I:Get(want) and I:Available(want) > 0) then have = have + 1 end
    end
    if want ~= cur then exact = false end
  end
  return pieces, have, exact
end

local function BagIndexOf(id)
  local bag = I:Bag()
  for i = 1, I.SLOTS do
    if bag[i] and bag[i].def == id then return i end
  end
end

-- Change into an outfit. Returns the names of anything it couldn't put on.
function W:PutOn(o)
  local missing, worn = {}, self:Table()
  batch = {}
  local ok, err = pcall(function()
    -- Everything it has first (each swap puts the old piece back in your bags)...
    for _, w in ipairs(I.WEAR) do
      local want = o.slots and o.slots[w.key]
      local cur = worn[w.key] and worn[w.key].def
      if want and want ~= cur then
        local idx = I:Available(want) > 0 and BagIndexOf(want)
        local def = I:Get(want)
        if not (idx and def and def.wear == w.key and self:Wear(idx)) then
          missing[#missing + 1] = def and UI.Escape(def.name) or "something you no longer have"
        end
      end
    end
    -- ...then off with anything it doesn't, or that it wants but you don't have.
    for _, w in ipairs(I.WEAR) do
      local want = o.slots and o.slots[w.key]
      local cur = worn[w.key] and worn[w.key].def
      if cur and cur ~= want then self:TakeOff(w.key) end
    end
  end)
  local b = batch
  batch = nil
  if b.sound ~= nil then Sound(b.sound) end
  if b.dirty then Changed() end
  if not ok then K.Try("outfit", error, err) end
  return missing
end

-- Outfits tied to profiles: switch to a profile and you change into its
-- outfit. The link lives on the outfit (o.profile = profile name), one
-- outfit per profile, so nothing about it travels with the profile itself.
function W:OutfitFor(profileName)
  if not profileName then return nil end
  for _, o in ipairs(self:Outfits()) do
    if o.profile == profileName then return o end
  end
end

function W:LinkOutfit(o, profileName)
  if profileName then
    for _, x in ipairs(self:Outfits()) do
      if x ~= o and x.profile == profileName then x.profile = nil end
    end
  end
  o.profile = profileName
  K:Fire("WORN")
end

-- PutOn, said out loud: "You change into At court." and anything missing.
function W:ChangeInto(o)
  local missing = self:PutOn(o)
  if #missing == 0 then
    K:Print(("You change into %s."):format(UI.Escape(o.name)))
  else
    K:Print(("You change into %s, without %s (not in your bags)."):format(UI.Escape(o.name),
      table.concat(missing, ", ")))
  end
end

---------------------------------------------------------------------------
-- Sharing: one line per worn item, "slot~quality~icon~name~description"
---------------------------------------------------------------------------
local function Flat(s, max)
  s = tostring(s or ""):gsub("[\r\n~]", " ")
  return strtrim(I.Cut(s, max))
end

local function IconName(icon)
  if type(icon) == "number" then return tostring(icon) end
  icon = tostring(icon or "")
  return (icon:gsub("^[Ii]nterface\\[Ii]cons\\", ""))
end

function W.Encode()
  local lines = {}
  for _, w in ipairs(I.WEAR) do
    local def = W:In(w.key)
    if def then
      lines[#lines + 1] = ("%s~%d~%s~%s~%s"):format(w.key, def.quality or 1, IconName(def.icon), Flat(def.name, I.MAX.name),
        Flat(def.description, DESC_MAX))
    end
  end
  return #lines > 0 and table.concat(lines, "\n") or nil
end

-- Another player's worn items, as tooltip-ready designs: [slot] = def
function W.Decode(text)
  if type(text) ~= "string" or text == "" or #text > 6000 then return nil end
  local out, n = {}, 0
  for line in text:gmatch("[^\n]+") do
    local slot, q, icon, name, desc = line:match("^([%a%d]+)~(%d)~([^~]*)~([^~]+)~(.*)$")
    if slot and I.WEAR_LABEL[slot] and not out[slot] then
      local num = tonumber(icon)
      out[slot] = { id = "worn:" .. slot, name = strtrim(I.Cut(UI.Clean(name), I.MAX.name)),
        icon = I.IconTexture(num or (icon ~= "" and ("Interface\\Icons\\" .. icon)) or nil),
        quality = math.max(0, math.min(5, tonumber(q) or 1)), description = I.Cut(UI.Clean(desc), DESC_MAX),
        stack = 1, useText = "", flavor = "", creator = "", wear = slot }
      n = n + 1
      if n >= #I.WEAR then break end
    end
  end
  return n > 0 and out or nil
end

K:AddProfileField({
  full = { "KQ" },
  publish = function(my) my.KQ = (K:ExtOn("inventory") and W.Encode()) or nil end,
  read = function(fields, out) out.worn = W.Decode(fields.KQ) end,
})

-- Whatever's worn by the owner of a profile: yours, or theirs from the profile.
function W.Of(profile, mine)
  if mine then
    local out = {}
    for _, w in ipairs(I.WEAR) do out[w.key] = W:In(w.key) end
    return out
  end
  return profile and profile.worn or {}
end

---------------------------------------------------------------------------
-- Dragging between your bags and your slots. Each bag window hands over its
-- cells (W:BagCells); your own slot buttons are listed as they're made. The
-- drag ends where the mouse is let go, whichever window that's in.
---------------------------------------------------------------------------
local mySlots, bagCells = {}, {}

function W:BagCells(cells) bagCells[#bagCells + 1] = cells end

local function Under(list)
  for _, b in ipairs(list) do
    if b:IsVisible() and b:IsMouseOver() then return b end
  end
end

local ghost
function W.Ghost(icon)
  if not ghost then
    ghost = CreateFrame("Frame", nil, UIParent)
    ghost:SetSize(38, 38)
    ghost:SetFrameStrata("TOOLTIP")
    ghost.icon = ghost:CreateTexture(nil, "ARTWORK")
    ghost.icon:SetAllPoints()
    ghost.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    ghost.icon:SetAlpha(0.85)
    UI.Round(ghost.icon)
    ghost:SetScript("OnUpdate", function(self)
      local x, y = GetCursorPosition()
      local s = UIParent:GetEffectiveScale()
      self:ClearAllPoints()
      self:SetPoint("CENTER", UIParent, "BOTTOMLEFT", x / s, y / s)
    end)
    ghost:Hide()
  end
  if icon then ghost.icon:SetTexture(icon) end
  return ghost
end

-- A bag item let go: on one of your slots, it's put on. True if it landed on
-- a slot (whether or not it fit), so the bag knows the drag was dealt with.
function W:DropFromBag(index)
  local b = Under(mySlots)
  if not b then return false end
  local s = I:Slot(index)
  local def = s and I:Get(s.def)
  if not def then return true end
  if def.wear ~= b.slot then
    if def.wear and I.WEAR_LABEL[def.wear] then
      I.Error(("%s goes in the %s slot."):format(UI.Escape(def.name), I.WEAR_LABEL[def.wear]:lower()))
    else
      I.Error(UI.Escape(def.name) .. " isn't something you wear. Choose \"Worn on\" in the Workshop.")
    end
    return true
  end
  self:Wear(index)
  return true
end

---------------------------------------------------------------------------
-- A slot button: the item (or the slot's name when empty), its tooltip,
-- and on your own slots: click for a menu, right-click to take it off, or
-- drag it into your bags.
---------------------------------------------------------------------------
local function SlotMenu(b)
  local slot = b.slot
  local def = W:In(slot)
  UI.Menu(b, function(root)
    root:CreateTitle(I.WEAR_LABEL[slot])
    if def then
      root:CreateButton("Take off " .. UI.Escape(def.name), function() W:TakeOff(slot) end)
    end
    local fit = W:Fitting(slot)
    for _, f in ipairs(fit) do
      local label = (def and "Swap for " or "Wear ") .. UI.Escape(f.def.name)
      root:CreateButton(label, function() W:Wear(f.index) end)
    end
    if not def and #fit == 0 then
      root:CreateButton("|cff9a9a9aNothing in your bags fits here. Choose \"Worn on\" in the Workshop.|r", function() end)
    end
  end)
end

-- The game's own outline for each empty slot, as on its character screen.
local PAPERDOLL = "Interface\\PaperDoll\\UI-PaperDoll-Slot-"
W.SLOT_ART = {
  head = PAPERDOLL .. "Head", neck = PAPERDOLL .. "Neck", shoulder = PAPERDOLL .. "Shoulder", back = PAPERDOLL .. "Chest",
  chest = PAPERDOLL .. "Chest", shirt = PAPERDOLL .. "Shirt", tabard = PAPERDOLL .. "Tabard", wrist = PAPERDOLL .. "Wrists",
  hands = PAPERDOLL .. "Hands", waist = PAPERDOLL .. "Waist", legs = PAPERDOLL .. "Legs", feet = PAPERDOLL .. "Feet",
  finger = PAPERDOLL .. "Finger", finger2 = PAPERDOLL .. "Finger", keepsake = PAPERDOLL .. "Trinket",
  charm = PAPERDOLL .. "Trinket", main = PAPERDOLL .. "MainHand", off = PAPERDOLL .. "SecondaryHand",
  carried = PAPERDOLL .. "Ranged",
}

function W.SlotButton(parent, size, slot, mine)
  local b = I.NewSlot(parent, size)
  b.slot, b.mine = slot, mine
  -- Empty: the slot's outline, faint, so you can tell which is which
  b.outline = b:CreateTexture(nil, "ARTWORK", nil, -1)
  b.outline:SetAllPoints(b.icon)
  b.outline:SetTexture(W.SLOT_ART[slot])
  b.outline:SetAlpha(0.45)
  hooksecurefunc(b, "SetItem", function(self, def) self.outline:SetShown(def == nil) end)
  b.tooltipAnchor = "ANCHOR_RIGHT"
  b:HookScript("OnEnter", function(self)
    if self.def then
      GameTooltip:AddLine(I.WEAR_LABEL[self.slot], 0.55, 0.80, 1)
      if self.mine then GameTooltip:AddLine("Right-click or drag it to your bags to take it off. Click to swap.", 0.62, 0.62, 0.62, true) end
      GameTooltip:Show()
    elseif self.mine then
      GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
      GameTooltip:SetText(I.WEAR_LABEL[self.slot], 1, 0.82, 0)
      GameTooltip:AddLine("Nothing worn here. Click to put something on, or drag it here from your bags.", 1, 1, 1, true)
      GameTooltip:Show()
    end
  end)
  if mine then
    mySlots[#mySlots + 1] = b
    b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    b:RegisterForDrag("LeftButton")
    b:SetScript("OnClick", function(self, button)
      if button == "RightButton" then
        if W:In(self.slot) then GameTooltip:Hide(); W:TakeOff(self.slot) end
      else
        SlotMenu(self)
      end
    end)
    b:SetScript("OnDragStart", function(self)
      local def = W:In(self.slot)
      if not def then return end
      self.dragging = true
      W.Ghost(I.IconTexture(def.icon)):Show()
      self:SetAlpha(0.4)
      GameTooltip:Hide()
    end)
    b:SetScript("OnDragStop", function(self)
      self:SetAlpha(1)
      W.Ghost():Hide()
      if not self.dragging then return end
      self.dragging = nil
      for _, cells in ipairs(bagCells) do
        local c = Under(cells)
        if c then W:TakeOff(self.slot, c.index) return end
      end
    end)
  end
  return b
end

K:On("ITEMDEFS", function() K:Fire("WORN") end)

-- Changing profile changes outfit, when the new one has an outfit tied to it.
-- Only a change of profile does it: editing your profile fires the same event.
local lastProfile
K:On("LOGIN", function() lastProfile = K:MyProfiles().active end)
K:On("PROFILE", function()
  local active = K.db and K:MyProfiles().active
  if active == lastProfile then return end
  local was = lastProfile
  lastProfile = active
  if was == nil or not K:ExtOn("inventory") then return end
  local o = W:OutfitFor(active)
  if o and not select(3, W:OutfitState(o)) then W:ChangeInto(o) end
end)
