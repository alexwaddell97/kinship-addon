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
  "ADDONS", "AddOn_Chomp", "AddOn_TotalRP3", "Ambiguate", "BNET_CLIENT_WOW", "BreakUpLargeNumbers",
  "ButtonFrameTemplate_HideButtonBar", "CANCEL", "CLASS_ICON_TCOORDS", "C_AddOns", "C_BattleNet", "C_CVar",
  "C_Calendar", "C_ChatInfo", "C_ClassColor", "C_EncodingUtil", "C_FriendList", "C_Item", "C_Map",
  "C_MountJournal", "C_NamePlate", "C_SuperTrack", "C_Texture", "C_Timer", "C_UIFileAsset", "C_UnitAuras",
  "ChatEdit_GetActiveWindow", "ChatFrameUtil", "ChatFrame_AddMessageEventFilter", "ChatFrame_OpenChat",
  "ChatTypeInfo", "CheckInteractDistance", "CopyTable", "CreateColor", "CreateFont", "CreateFrame",
  "CreateFromMixins", "CreateVector2D", "DEFAULT_CHAT_FRAME", "DELETE", "DisableAddOn", "DoEmote",
  "ERR_CHAT_PLAYER_NOT_FOUND_S", "ERR_TRADE_BAG_FULL", "ERR_TRADE_CANCELLED", "ERR_TRADE_COMPLETE",
  "ERR_TRADE_TARGET_BAG_FULL", "EllesmereUI", "Enum", "EventRegistry", "FRIENDS_BUTTON_TYPE_BNET",
  "FRIENDS_BUTTON_TYPE_WOW", "FriendsFrame_UpdateFriendButton", "GameFontNormal", "GameFontNormalSmall",
  "GameTooltip", "GetAddOnInfo", "GetBindingKey", "GetBuildInfo", "GetCVar", "GetCoinText",
  "GetCoinTextureString", "GetCurrentKeyBoardFocus", "GetCursorPosition", "GetDefaultLanguage",
  "GetGameTime", "GetGuildInfo", "GetInboxHeaderInfo", "GetInboxNumItems", "GetInboxText", "GetInstanceInfo",
  "GetInventoryItemID", "GetItemCount", "GetItemInfo", "GetLanguageByIndex", "GetLocale",
  "GetLootSourceInfo", "GetMinimapZoneText", "GetMouseFoci", "GetMouseFocus", "GetNormalizedRealmName",
  "GetNumAddOns", "GetNumGroupMembers", "GetNumLanguages", "GetNumLootItems", "GetNumSubgroupMembers",
  "GetPhysicalScreenSize", "GetPlayerFacing", "GetPlayerInfoByGUID", "GetQuestDifficultyColor",
  "GetRaidRosterInfo", "GetRealZoneText", "GetRealmName", "GetSendMailCOD", "GetSendMailItem",
  "GetSendMailMoney", "GetSendMailPrice", "GetServerTime", "GetSubZoneText", "GetTime", "GetTimePreciseSec",
  "GetUnitName", "GetZonePVPInfo", "GetZoneText", "HideUIPanel", "InCombatLockdown", "IsAddOnLoaded",
  "IsEquippedItem", "IsInGroup", "IsInGuild", "IsInInstance", "IsInRaid", "IsIndoors", "IsLoggedIn",
  "IsMounted", "IsResting", "IsShiftKeyDown", "ItemRefTooltip", "LOCALIZED_CLASS_NAMES_MALE", "LibStub",
  "MapCanvasDataProviderMixin", "Menu", "MenuUtil", "MoneyInputFrame_GetCopper",
  "MoneyInputFrame_ResetMoney", "NUM_CHAT_WINDOWS", "OKAY", "PlayMusic", "PlaySound", "RAID_CLASS_COLORS",
  "RANDOM_ROLL_RESULT", "ReloadUI", "SAVE", "SEARCH", "SOUNDKIT", "STANDARD_TEXT_FONT", "SaveAddOns",
  "ScrollBoxListMixin", "ScrollingEdit_OnCursorChanged", "ScrollingEdit_OnTextChanged",
  "ScrollingEdit_OnUpdate", "SendChatMessage", "SendMail", "SendMailFrame_Update", "SetItemRef",
  "SetPortraitTexture", "SetPortraitToTexture", "SetSendMailCOD", "SetSendMailMoney", "Settings",
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
