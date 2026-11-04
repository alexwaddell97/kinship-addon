-- Kinship RP: groups. Houses are families built on a shared surname; a group
-- is anything else people band together as: an RP guild, a company, an
-- order. You join one by naming it, the same way as a house, and say what
-- you are in it ("Sergeant", "Founder"). Its crest, motto and story are kept
-- here and shared, like a house's.
--
-- Profile: p.group (the name), p.groupRole (your place in it).
-- Saved:   K.db.groups[groupKey] = { crest, motto, desc, members }
-- Shared:  KO name, KR role, KE crest, KB motto, KD story (Kinship's own
--          fields; other RP addons ignore them).

local ADDON, ns = ...
local K = ns.K

K.GROUP_CREST = "Interface\\Icons\\INV_BannerPVP_02"
K.MAX_GROUP_NAME, K.MAX_GROUP_ROLE = 40, 30

function K:GroupName() return strtrim(self:Profile().group or "") end
function K:GroupRole() return strtrim(self:Profile().groupRole or "") end
function K:GroupKey(name) name = name or self:GroupName(); return name ~= "" and name:lower() or nil end

function K:Group()
  local key = self:GroupKey()
  if not key then return nil end
  self.db.groups[key] = self.db.groups[key] or { crest = K.GROUP_CREST, motto = "", desc = "" }
  return self.db.groups[key]
end

-- Join (or found) a group by name; "" leaves it. What you'd set for a group
-- stays saved, so coming back to it finds its crest and story as you left them.
function K:SetGroup(name)
  local p = self:Profile()
  p.group = strtrim(name or ""):sub(1, K.MAX_GROUP_NAME)
  if p.group == "" then p.groupRole = "" end
  self:Fire("PROFILE")
  self:Fire("HOUSE")
end

function K:SetGroupRole(role)
  self:Profile().groupRole = strtrim(role or ""):sub(1, K.MAX_GROUP_ROLE)
  self:Fire("PROFILE")
end

-- Recognition, as for a house: [nameKey] = { name, state = "recognised" | "ignored" }
function K:SetGroupMember(key, name, state)
  local g = self:Group()
  if not g or not key then return end
  g.members = g.members or {}
  g.members[key] = state and { name = name, state = state } or nil
  if state == "recognised" then self:Print(name .. " is now recognised as one of yours.")
  elseif state == "ignored" then self:Print(name .. "'s claim will no longer be shown.") end
  self:Fire("HOUSE")
  if K.Journal then K.Journal:RefreshCurrent() end
end

function K:GroupState(name)
  local g = self:Group()
  local key = K.NameKey(name)
  local m = g and g.members and key and g.members[key]
  return m and m.state or nil
end

-- Recognised members and unconfirmed claims for your group.
function K:GroupMembers()
  local key, group = self:GroupKey(), self:Group()
  local recognised, claims, seen = {}, {}, {}
  if not key or not group then return recognised, claims end
  group.members = group.members or {}

  -- Your own characters who name it
  for guid, p in pairs(self.db.profiles) do
    local prof = p.list and p.list[p.active]
    if prof and self:GroupKey(strtrim(prof.group or "")) == key and p.name then
      local k = K.NameKey(p.name) or p.name:lower()
      if not seen[k] then
        seen[k] = true
        local role = strtrim(prof.groupRole or "")
        recognised[#recognised + 1] = { name = p.name, key = k, mine = true, state = "recognised",
          role = role ~= "" and role or (guid == self:CharKey() and "You" or "Your character") }
      end
    end
  end

  -- People whose shared profile names it
  local recent = time() - 600
  for _, reg in pairs(self.Registry) do
    local pr = reg.profile
    if pr and strtrim(pr.group or ""):lower() == key then
      local k = K.NameKey(reg.name) or reg.name:lower()
      local state = group.members[k] and group.members[k].state
      if not seen[k] and state ~= "ignored" then
        seen[k] = true
        local role = strtrim(K.UI.Clean(pr.groupRole or ""))
        if role == "" and (reg.t or 0) > recent then role = "|cff5fd35fNearby|r" end
        local m = { name = K.Short(reg.name), raw = reg.name, key = k, state = state, role = role }
        if state == "recognised" then recognised[#recognised + 1] = m else claims[#claims + 1] = m end
      end
    end
  end

  -- Anyone recognised earlier who isn't about right now
  for k, m in pairs(group.members) do
    if m.state == "recognised" and not seen[k] then
      seen[k] = true
      recognised[#recognised + 1] = { name = K.Short(m.name), raw = m.name, key = k, state = "recognised" }
    end
  end

  local byName = function(a, b)
    if a.mine ~= b.mine then return a.mine and true or false end
    return a.name < b.name
  end
  table.sort(recognised, byName); table.sort(claims, byName)
  return recognised, claims
end

---------------------------------------------------------------------------
-- Sharing
---------------------------------------------------------------------------
local function Clean(v) v = v and strtrim(v) or ""; return v ~= "" and v or nil end

K:AddProfileField({
  full = { "KO", "KR", "KE", "KB", "KD" },
  tooltip = { "KO", "KR" },
  own = { "KO", "KR", "KE", "KB", "KD" },
  publish = function(my, p)
    local name = Clean(p.group)
    local g = name and K:Group()
    my.KO = name
    my.KR = name and Clean(p.groupRole) or nil
    my.KE = g and K.Comm.ValidCrest(g.crest) or nil
    my.KB = g and Clean(g.motto) or nil
    my.KD = g and Clean(g.desc) or nil
  end,
  read = function(fields, out)
    local function f(k) local v = fields[k]; return (type(v) == "string" and v ~= "") and v or "" end
    out.group, out.groupRole = f("KO"), f("KR")
    out.groupCrest = K.Comm.ValidCrest(f("KE"))
    out.groupMotto, out.groupStory = f("KB"), f("KD")
  end,
})
