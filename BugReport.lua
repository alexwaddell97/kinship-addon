-- Kinship RP: /kin bug. A copyable report for bug reports: Kinship's
-- version, the game build, the errors Kinship caught recently (K.errors,
-- see Core.lua) and the addons that are loaded. It holds no profile text and
-- no character or player names.

local ADDON, ns = ...
local K = ns.K
local UI = K.UI
local R = {}
K.BugReport = R

local MAX_SHOWN = 15   -- most recent errors in the report

local function Call(fn, ...)
  if type(fn) ~= "function" then return nil end
  local ok, a, b, c, d = pcall(fn, ...)
  if ok then return a, b, c, d end
end

local function Addons()
  local api = C_AddOns or {}
  local num = api.GetNumAddOns or _G.GetNumAddOns
  local info = api.GetAddOnInfo or _G.GetAddOnInfo
  local loaded = api.IsAddOnLoaded or _G.IsAddOnLoaded
  local meta = api.GetAddOnMetadata or _G.GetAddOnMetadata
  local out = {}
  for i = 1, Call(num) or 0 do
    local name = Call(info, i)
    if type(name) == "string" and Call(loaded, i) then
      local v = Call(meta, name, "Version")
      out[#out + 1] = (type(v) == "string" and v ~= "") and (name .. " " .. v) or name
    end
  end
  table.sort(out, function(a, b) return a:lower() < b:lower() end)
  return out
end

function R:Text()
  local lines = {}
  local function Add(s) lines[#lines + 1] = s end
  local version, build, built, toc = Call(GetBuildInfo)
  Add(("Kinship RP %s (saved data schema %s of %s)"):format(tostring(K.VERSION), tostring(K.db and K.db.schema or "?"),
    tostring(K.SCHEMA)))
  Add(("Game: %s, build %s (%s), interface %s, %s"):format(tostring(version or "?"), tostring(build or "?"),
    tostring(built or "?"), tostring(toc or "?"), tostring(Call(GetLocale) or "?")))
  local other = K.Comm and K.Comm:OtherRPAddon()
  if other then Add("Other roleplay addon running: " .. other) end
  if K.EXT_MODULES then
    local off = {}
    for _, m in ipairs(K.EXT_MODULES) do if not K:ExtWanted(m) then off[#off + 1] = m end end
    Add("Extended features: " .. (not K:ExtWanted() and "off" or (#off > 0 and ("on, except " .. table.concat(off, ", ")) or "all on")))
  end
  if K.newerSchema then Add("Saved data is from a newer Kinship (schema " .. K.newerSchema .. ")") end
  if K.migrationFailed then Add("Updating saved data failed at step " .. K.migrationFailed) end

  local errors = K.errors or {}
  Add("")
  if #errors == 0 then
    Add("Errors Kinship caught: none")
  else
    Add(("Errors Kinship caught (%d, newest last):"):format(#errors))
    for i = math.max(1, #errors - MAX_SHOWN + 1), #errors do
      local e = errors[i]
      Add(("[%s]%s%s %s: %s"):format(date("%d %b %H:%M", e.t or 0), (e.n or 1) > 1 and (" x" .. e.n) or "",
        (e.v and e.v ~= K.VERSION) and (" (" .. e.v .. ")") or "", tostring(e.where), tostring(e.msg)))
    end
  end

  local list = Addons()
  Add("")
  Add(("Loaded addons (%d):"):format(#list))
  for _, a in ipairs(list) do Add("  " .. a) end
  -- Text in the report is shown as typed, not as links or colours.
  return UI.Escape(table.concat(lines, "\n"))
end

---------------------------------------------------------------------------
-- The window
---------------------------------------------------------------------------
local W, H = 560, 460
local PW = W - 32

function R:Build()
  if self.frame then return end
  local f = UI.Window("KinshipRPBugReport", "Bug report", W, H)
  f:SetFrameStrata("DIALOG")
  self.frame = f
  local desk = UI.Desk(f)
  desk:SetPoint("TOPLEFT", 1, -35)
  desk:SetPoint("BOTTOMRIGHT", -1, 1)

  local hint = UI.Text(f, "Copy this (Ctrl+C) and paste it into your bug report, along with what you were doing when "
    .. "it went wrong. It has no profile text or character names in it.", "Small", "deskSubtle", PW)
  hint:SetPoint("TOPLEFT", 17, -48)
  hint:SetSpacing(2)

  f.area = UI.TextArea(f, PW, 314, 0, nil, "desk")
  f.area:SetPoint("TOPLEFT", 16, -84)
  -- Read-only: any typing puts the report back.
  f.area.edit:HookScript("OnTextChanged", function(self, user)
    if user and R.text and self:GetText() ~= R.text then self:SetText(R.text); self:HighlightText() end
  end)

  f.done = UI.Button(f, "Done", 100, 28)
  f.done:SetPoint("BOTTOMRIGHT", -16, 14)
  f.done:SetScript("OnClick", function() f:Hide() end)
  f.select = UI.Button(f, "Select all", 110, 28)
  f.select:SetPoint("RIGHT", f.done, "LEFT", -8, 0)
  f.select:SetScript("OnClick", function()
    f.area.edit:SetFocus()
    f.area.edit:HighlightText()
  end)
  f.clear = UI.Button(f, "Clear errors", 120, 28)
  f.clear:SetPoint("BOTTOMLEFT", 16, 14)
  UI.Tooltip(f.clear, "Clear errors", "Forget the errors listed here, e.g. once you've reported them.")
  f.clear:SetScript("OnClick", function()
    if K.errors then wipe(K.errors) end
    R:Refresh()
  end)
end

function R:Refresh()
  local f = self.frame
  self.text = self:Text()
  f.area.edit:SetText(self.text)
  f.area.edit:SetCursorPosition(0)
  f.area.edit:SetFocus()
  f.area.edit:HighlightText()
  f.clear:SetEnabled(K.errors ~= nil and #K.errors > 0)
end

function R:Open()
  self:Build()
  self.frame:Show()
  self:Refresh()
end
