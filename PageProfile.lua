-- Kinship RP: Profile page (edit your own character).

local ADDON, ns = ...
local K = ns.K
local UI = K.UI

StaticPopupDialogs["KINSHIPRP_NEW_PROFILE"] = {
  text = "Name your new profile:",
  button1 = OKAY or "OK", button2 = CANCEL or "Cancel",
  hasEditBox = true, maxLetters = 24,
  OnAccept = function(self, copy)
    local eb = self.editBox or self.EditBox or (self.GetEditBox and self:GetEditBox())
    if eb and not K:NewProfile(eb:GetText(), copy) then K:Print("That name is empty or already used.") end
  end,
  EditBoxOnEnterPressed = function(self)
    local parent = self:GetParent()
    if not K:NewProfile(self:GetText(), parent.data) then K:Print("That name is empty or already used.") end
    parent:Hide()
  end,
  EditBoxOnEscapePressed = function(self) self:GetParent():Hide() end,
  timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
}

StaticPopupDialogs["KINSHIPRP_DELETE_PROFILE"] = {
  text = "Delete the profile \"%s\"? This can't be undone.",
  button1 = DELETE or "Delete", button2 = CANCEL or "Cancel",
  OnAccept = function(_, name) K:DeleteProfile(name) end,
  timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
}

local SECTIONS = {
  { key = "identity",    label = "Identity",    hint = "Who your character is, beyond the name the game gives them." },
  { key = "appearance",  label = "Appearance",  hint = "How others see your character: build, face, clothing, the way they carry themselves." },
  { key = "personality", label = "Personality", hint = "Temperament, habits, what they care about, how they treat others." },
  { key = "history",     label = "History",     hint = "Where they come from and what brought them here. Write as much or as little as you like." },
}

K:RegisterPage({
  id = "profile", trp3 = "hide", title = "Profile", heading = "Your character",
  subtitle = "What others see when they look closer.",

  build = function(c)
    local fields = {}
    c.fields = fields

    -- Top strip: name preview, status, profile switcher -------------------
    c.name = UI.Text(c, "", "GameFontNormalHuge", "deskHeading", 290)
    c.name:SetWordWrap(false)
    c.name:SetPoint("TOPLEFT", 4, -2)
    c.epithet = UI.Text(c, "", "GameFontHighlight", "deskAccent")
    c.epithet:SetPoint("TOPLEFT", c.name, "BOTTOMLEFT", 0, -3)

    c.gem = UI.Gem(c, 16)
    c.status = UI.Segments(c, {
      { key = "ic", label = "In Character" }, { key = "lfrp", label = "Looking for RP" }, { key = "ooc", label = "Out of Character" },
    }, 106, function(key) K:SetStatus(key) end)
    c.status:Fit(106)   -- "Out of Character" needs a little more than 106
    c.status:SetPoint("TOPRIGHT", 0, 0)
    local statusLabel = UI.Text(c, "Status", "GameFontNormalSmall", "deskSubtle")
    statusLabel:SetPoint("RIGHT", c.status, "LEFT", -10, 0)
    c.gem:SetPoint("RIGHT", statusLabel, "LEFT", -5, 0)

    c.profileBtn = UI.Button(c, "", 160, 24)
    c.profileBtn:SetPoint("TOPRIGHT", -106, -30)
    c.profileBtn:SetScript("OnClick", function(self)
      UI.Menu(self, function(root)
        root:CreateTitle("Profiles")
        local active = K:MyProfiles().active
        for _, name in ipairs(K:ProfileNames()) do
          root:CreateRadio(name, function() return name == K:MyProfiles().active end, function() K:SwitchProfile(name) end)
        end
        root:CreateDivider()
        root:CreateButton("New blank profile...", function() StaticPopup_Show("KINSHIPRP_NEW_PROFILE", nil, nil, false) end)
        root:CreateButton("Copy this profile...", function() StaticPopup_Show("KINSHIPRP_NEW_PROFILE", nil, nil, true) end)
        root:CreateButton("Delete \"" .. active .. "\"", function() StaticPopup_Show("KINSHIPRP_DELETE_PROFILE", active, nil, active) end)
      end)
    end)
    UI.Tooltip(c.profileBtn, "Profiles", "Keep separate profiles for different stories, and switch between them in one click.")

    c.exp = UI.Button(c, "", 140, 24)
    c.exp:SetPoint("TOPRIGHT", -272, -30)
    c.exp:SetScript("OnClick", function(self) if K.Experience then K.Experience:Menu(self) end end)
    UI.Tooltip(c.exp, "Roleplay experience", "How much you've roleplayed, so others know what to expect. "
      .. "New roleplayers and those happy to help them show it in their tooltips.")

    local preview = UI.Button(c, "Preview", 100, 24)
    c.preview = preview
    preview:SetPoint("TOPRIGHT", 0, -30)
    preview:SetScript("OnClick", function() K.Viewer:ShowSelf() end)
    UI.Tooltip(preview, "Preview", "See your profile the way other players will.")

    -- Left: the details ------------------------------------------------------
    local left = UI.Panel(c)
    left:SetPoint("TOPLEFT", 0, -58)
    left:SetSize(318, 408)
    local lh = UI.Section(left, "Details")
    lh:SetPoint("TOPLEFT", 19, -13)

    local function add(key, label, x, y, w, max)
      local f = UI.Field(left, label, w, max, function(text) K:SetField(key, text) end)
      f:SetPoint("TOPLEFT", x, y)
      fields[key] = f.edit
      return f
    end
    local L, R, FW, HW = 12, 162, 294, 144
    add("epithet",   "Epithet  (e.g. \"the Wanderer\")", L, -38,  FW, 40)
    add("glance",    "At a glance",                      L, -80,  FW, 255)
    add("pronouns",  "Pronouns",                         L, -122, HW, 20)
    add("age",       "Age",                              R, -122, HW, 20)
    add("height",    "Height",                           L, -164, HW, 20)
    add("home",      "Home",                             R, -164, HW, 40)
    local house = add("house", "House (family name)",    L, -206, FW, 30)
    UI.Tooltip(house.edit, "House", "Characters who share a family name can belong to the same house. " ..
      "This starts as your character's last name, but you can change it.")
    add("motto",     "Motto",                            L, -248, FW, 90)
    add("currently", "Currently",                        L, -290, FW, 255)
    local hint = UI.Text(left, "\"Currently\" shows on your tooltip. Use it for what your character is doing right now.",
      "GameFontHighlightSmall", "subtle", 290)
    hint:SetPoint("TOPLEFT", 14, -338)
    hint:SetSpacing(2)

    -- Right: the longer writing ----------------------------------------------
    local right = UI.Panel(c)
    right:SetPoint("TOPLEFT", left, "TOPRIGHT", 8, 0)
    right:SetPoint("BOTTOMRIGHT", 0, 0)
    c.section = "identity"
    c.sectionTabs = UI.Segments(right, SECTIONS, 86, function(key) c.section = key; c:LoadSection() end)
    c.sectionTabs:SetPoint("TOPLEFT", 14, -12)
    c.sectionHint = UI.Text(right, "", "GameFontHighlightSmall", "subtle", 340)
    c.sectionHint:SetPoint("TOPLEFT", 16, -44)
    c.area = UI.TextArea(right, 344, 300, 20000, function(text) K:SetField(c.section, text) end)
    c.area:SetPoint("TOPLEFT", 14, -72)
    c.count = UI.Text(right, "", "GameFontHighlightSmall", "subtle")
    c.count:SetPoint("BOTTOMRIGHT", -16, 12)
    c.area.edit:HookScript("OnTextChanged", function(self)
      c.count:SetText(("%d letters"):format(self:GetNumLetters()))
    end)
    if K.Markup then
      c.toolbar = K.Markup:Toolbar(right, c.area.edit)
      c.toolbar:SetPoint("BOTTOMLEFT", 14, 8)
    end

    -- Identity: the fields that make up a full roleplay name and background
    local id = CreateFrame("Frame", nil, right)
    id:SetPoint("TOPLEFT", 14, -72)
    id:SetPoint("BOTTOMRIGHT", -14, 12)
    c.identity = id
    local IW, HW2 = 342, 166
    local function addId(key, label, x, y, w, max)
      local f = UI.Field(id, label, w, max, function(text) K:SetField(key, text) end)
      f:SetPoint("TOPLEFT", x, y)
      fields[key] = f.edit
      return f
    end
    addId("rpName",     "Full name  (leave empty to use your character's)", 0, 0,    IW, 60)
    addId("prefix",     "Title  (e.g. \"Lord\", \"Sergeant\")",              0, -42,  HW2, 30)
    addId("nickname",   "Nickname",                                          176, -42, HW2, 40)
    addId("race",       "Race",                                              0, -84,  HW2, 40)
    addId("class",      "Class or calling",                                  176, -84, HW2, 40)
    addId("eyes",       "Eyes",                                              0, -126, HW2, 40)
    addId("birthplace", "Birthplace",                                        176, -126, HW2, 60)
    addId("ooc",        "Out of character note",                             0, -168, IW, 255)
    local idHint = UI.Text(id, "Race and class only show when you fill them in; otherwise everyone sees your character's own. "
      .. "The out-of-character note sits under \"Currently\" on your tooltip.", "GameFontHighlightSmall", "subtle", IW)
    idHint:SetPoint("TOPLEFT", 2, -216)
    idHint:SetSpacing(2)

    function c:LoadSection()
      for _, s in ipairs(SECTIONS) do if s.key == self.section then self.sectionHint:SetText(s.hint) end end
      self.sectionTabs:Select(self.section)
      local isId = self.section == "identity"
      self.identity:SetShown(isId)
      self.area:SetShown(not isId)
      self.count:SetShown(not isId)
      if self.toolbar then self.toolbar:SetShown(not isId) end
      if isId then return end
      self.area.edit:SetText(K:Profile()[self.section] or "")
      self.area.edit:SetCursorPosition(0)
    end
  end,

  refresh = function(c)
    local p = K:Profile()
    c.name:SetText(K:DisplayName(p))
    c.epithet:SetText(p.epithet ~= "" and p.epithet or " ")
    c.status:Select(p.status)
    c.gem:SetStatus(p.status)
    c.profileBtn:SetText("Profile: " .. K:MyProfiles().active)
    c.exp:SetText(K.Experience and K.Experience.ButtonText(p) or "")
    for key, eb in pairs(c.fields) do
      if not eb:HasFocus() then eb:SetText(p[key] or ""); eb:SetCursorPosition(0) end
    end
    if not c.area.edit:HasFocus() then c:LoadSection() end
  end,
})
