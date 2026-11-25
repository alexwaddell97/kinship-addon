-- Kinship RP: translations. Each other file in this folder fills ns.L for one
-- game language, and only on a client in that language. Code shows text as
-- Loc["English text"]: the translation when there is one, else the English.

local _, ns = ...

ns.L = setmetatable({}, { __index = function(_, text) return text end })
