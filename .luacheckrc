-- luacheck settings for Kinship RP (runs on GitHub with every push, and
-- before every release). It only looks for what can break the addon: syntax
-- errors, and names that aren't defined anywhere, such as a misspelt
-- function or a local used before the line that makes it.
-- A new game function? Add it to read_globals below.
std = "lua51"
max_line_length = false
only = { "011", "1" }
exclude_files = { "Libs/**" }

-- Kinship's own globals, and the game's tables it adds to
globals = {
  "KinshipRPDB", "KinshipRP", "SLASH_KINSHIPRP1", "SLASH_KINSHIPRP2", "BINDING_HEADER_KINSHIPRP",
  "BINDING_NAME_KINSHIPRP_DICE", "BINDING_NAME_KINSHIPRP_JOURNAL", "BINDING_NAME_KINSHIPRP_PARLEY",
  "BINDING_NAME_KINSHIPRP_SATCHEL", "BINDING_NAME_KINSHIPRP_STATUS", "BINDING_NAME_KINSHIPRP_VIEW",
  "KinshipRP_OnCompartmentClick", "KinshipRP_DiceKey", "KinshipRP_StatusKey", "KinshipRP_ViewKey",
  "KinshipRP_SatchelKey", "KinshipRP_ParleyKey", "msp_RPAddOn", "SlashCmdList", "StaticPopupDialogs",
  "UISpecialFrames", "msp", "ColorPickerFrame",
}

-- The game's API that Kinship uses, and other addons it talks to
read_globals = {
  "AddOn_Chomp", "AddOn_TotalRP3", "Ambiguate", "BreakUpLargeNumbers", "ButtonFrameTemplate_HideButtonBar",
  "CANCEL", "CLASS_ICON_TCOORDS", "C_AddOns", "C_CVar", "C_Calendar", "C_ChatInfo", "C_ClassColor",
  "C_EncodingUtil", "C_Item", "C_Map", "C_MountJournal", "C_NamePlate", "C_SuperTrack", "C_Texture",
  "C_Timer", "C_UIFileAsset", "C_UnitAuras", "ChatEdit_GetActiveWindow", "ChatFrameUtil",
  "ChatFrame_AddMessageEventFilter", "ChatFrame_OpenChat", "ChatTypeInfo", "CheckInteractDistance",
  "CopyTable", "CreateColor", "CreateFont", "CreateFrame", "CreateFromMixins", "CreateVector2D",
  "DEFAULT_CHAT_FRAME", "DELETE", "DisableAddOn", "DoEmote", "ERR_CHAT_PLAYER_NOT_FOUND_S", "EllesmereUI",
  "Enum", "EventRegistry", "GameFontNormal", "GameFontNormalSmall", "GameTooltip", "GetAddOnInfo",
  "GetBindingKey", "GetBuildInfo", "GetCVar", "GetCurrentKeyBoardFocus", "GetCursorPosition",
  "GetDefaultLanguage", "GetGameTime", "GetGuildInfo", "GetInboxHeaderInfo", "GetInboxNumItems",
  "GetInboxText", "GetInstanceInfo", "GetInventoryItemID", "GetItemCount", "GetItemInfo",
  "GetLanguageByIndex", "GetLocale", "GetLootSourceInfo", "GetMinimapZoneText", "GetMouseFoci",
  "GetMouseFocus", "GetNormalizedRealmName", "GetNumAddOns", "GetNumGroupMembers", "GetNumLanguages",
  "GetNumLootItems", "GetNumSubgroupMembers", "GetPhysicalScreenSize", "GetPlayerFacing",
  "GetPlayerInfoByGUID", "GetQuestDifficultyColor", "GetRaidRosterInfo", "GetRealZoneText", "GetSendMailCOD",
  "GetSendMailItem", "GetSendMailMoney", "GetServerTime", "GetSubZoneText", "GetTime", "GetTimePreciseSec",
  "GetUnitName", "GetZonePVPInfo", "GetZoneText", "HideUIPanel", "InCombatLockdown", "IsAddOnLoaded",
  "IsEquippedItem", "IsInGroup", "IsInGuild", "IsInInstance", "IsInRaid", "IsIndoors", "IsLoggedIn",
  "IsMounted", "IsResting", "IsShiftKeyDown", "LOCALIZED_CLASS_NAMES_MALE", "LibStub",
  "MapCanvasDataProviderMixin", "Menu", "MenuUtil", "NUM_CHAT_WINDOWS", "OKAY", "PlayMusic", "PlaySound",
  "RAID_CLASS_COLORS", "ReloadUI", "SAVE", "SEARCH", "SOUNDKIT", "STANDARD_TEXT_FONT", "SaveAddOns",
  "ScrollingEdit_OnCursorChanged", "ScrollingEdit_OnTextChanged", "ScrollingEdit_OnUpdate",
  "SendChatMessage", "SendMail", "SetItemRef", "SetPortraitTexture", "SetPortraitToTexture", "Settings",
  "ShowUIPanel", "StaticPopup_Show", "StopMusic", "ToggleCharacter", "ToggleWorldMap",
  "TooltipDataProcessor", "UIErrorsFrame", "UIParent", "UNKNOWNOBJECT", "UiMapPoint", "UnitAffectingCombat",
  "UnitBuff", "UnitCanAttack", "UnitClass", "UnitExists", "UnitFactionGroup", "UnitFullName", "UnitGUID",
  "UnitHealth", "UnitInParty", "UnitInRaid", "UnitInRange", "UnitIsDead", "UnitIsEnemy",
  "UnitIsOtherPlayersPet", "UnitIsPVP", "UnitIsPlayer", "UnitIsTapDenied", "UnitIsUnit", "UnitLevel",
  "UnitName", "UnitPlayerControlled", "UnitRace", "WorldMapFrame", "abs", "bit", "ceil", "date",
  "debugprofilestop", "debugstack", "floor", "format", "geterrorhandler", "gsub", "hooksecurefunc",
  "issecretvalue", "max", "min", "mod", "random", "securecall", "seterrorhandler", "sort", "sqrt", "strfind",
  "strjoin", "strlen", "strlower", "strmatch", "strrep", "strsplit", "strsub", "strtrim", "strupper",
  "tContains", "time", "tinsert", "tremove", "wipe",
}
