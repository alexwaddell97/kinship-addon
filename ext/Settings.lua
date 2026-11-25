-- Kinship RP: Settings > Extended features. One master switch and a switch
-- per module, kept in K.db.settings.ext. Features ask K:ExtOn(module).

local _, ns = ...
local Loc = ns.L
local K = ns.K
local UI = K.UI

local MODULES = {
  { key = "inventory", label = Loc["Inventory"],  desc = Loc["Bags, the Workshop, giving items and stashes."] },
  { key = "documents", label = Loc["Documents"],  desc = Loc["Books, letters and notices you write and read."] },
  { key = "auras",     label = Loc["Effects"],    desc = Loc["Wounds, boons and states on your character, shared with others."] },
  { key = "campaigns", label = Loc["Campaigns and quests"], desc = "Quests you follow and write, and Total RP 3: Extended campaigns." },
  -- Cutscenes ("dialogues"), workflows ("scripting") and Total RP 3: Extended
  -- trading ("interop") have switches in K.EXT_MODULES too, but nothing behind
  -- them yet, so they're left off this card until they do something.
}

K:RegisterSettings({ id = "extended", title = Loc["Extended features"], order = 80, build = function(card)
  card:Toggle(Loc["Extended features"], Loc["Items, documents, effects, campaigns, and support for Total RP 3: Extended creations."], {
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
  local reload = card:Button(Loc["Reload now"], function() ReloadUI() end, 140)
  card:OnRefresh(function()
    local need = K:ExtNeedsReload()
    local text
    if need then
      text = (Loc["|cff%sReload to start the features you turned on.|r"])
        :format(UI.CardHex({ 0.95, 0.60, 0.25 }))
    elseif not K:ExtWanted() then
      text = Loc["Extended features are off. Their pages and tabs are hidden until you turn them back on."]
    else
      text = Loc["Turning a feature off works straight away. Turning it back on needs a reload."]
    end
    note:SetText(text)
    reload:SetEnabled(need)
  end)
end })
