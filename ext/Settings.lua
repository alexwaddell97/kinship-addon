-- Kinship RP: Settings > Extended features. One master switch and a switch
-- per module, kept in K.db.settings.ext. Features ask K:ExtOn(module).

local ADDON, ns = ...
local K = ns.K
local UI = K.UI

local MODULES = {
  { key = "inventory", label = "Inventory",  desc = "Bags, the Workshop, giving items and stashes." },
  { key = "documents", label = "Documents",  desc = "Books, letters and notices you write and read." },
  { key = "auras",     label = "Effects",    desc = "Wounds, boons and states on your character, shared with others." },
  { key = "campaigns", label = "Campaigns and quests", desc = "Quests you follow and the ones you write." },
  -- Cutscenes ("dialogues"), workflows ("scripting") and Total RP 3: Extended
  -- trading ("interop") have switches in K.EXT_MODULES too, but nothing behind
  -- them yet, so they're left off this card until they do something.
}

K:RegisterSettings({ id = "extended", title = "Extended features", order = 80, build = function(card)
  card:Toggle("Extended features", "Items, documents, effects, campaigns and everything that reads Total RP 3: Extended creations.", {
    get = function() return K:ExtWanted() end,
    set = function(v) K:SetExt(nil, v) end,
  })
  card:EndRow()
  for _, m in ipairs(MODULES) do
    card:Toggle(m.label, m.desc, {
      get = function() return K:ExtWanted(m.key) end,
      set = function(v) K:SetExt(m.key, v) end,
    })
  end
  card:EndRow()
  local note = card:Note("", 30)
  local reload = card:Button("Reload now", function() ReloadUI() end, 140)
  card:OnRefresh(function()
    local need = K:ExtNeedsReload()
    local text
    if need then
      text = ("|cff%sSomething you switched on needs a reload to start.|r Switching off takes effect at once.")
        :format(UI.CardHex({ 0.95, 0.60, 0.25 }))
    elseif not K:ExtWanted() then
      text = "Extended features are off: their pages, tabs and messages are gone until you switch them back on."
    else
      text = "Switching a feature off hides it and ignores its messages at once. Switching it back on needs a reload."
    end
    note:SetText(text)
    reload:SetEnabled(need)
  end)
end })
