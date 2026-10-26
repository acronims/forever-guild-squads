-- luacheck config for Guild Squads (WoW Forever 1.60.1, Interface 16001). Run: luacheck .
-- Not part of CI; provided for local use (luacheck needs luarocks/Lua). tests/gates.js is the enforced API gate.
std = "lua51"
max_line_length = false
codes = true
exclude_files = { "tests/", ".node/", "node_modules/", ".release/", "docs/" }

-- Globals the addon writes.
globals = {
  "GuildSquadsDB",
  "SLASH_GUILDSQUADS1",
  "BINDING_HEADER_GUILDSQUADS",
  "BINDING_NAME_GUILDSQUADS_TOGGLE",
  SlashCmdList = { fields = { "GUILDSQUADS" } },
  StaticPopupDialogs = { fields = { "GUILDSQUADS_CONFIRM", "GUILDSQUADS_PROMPT" } },
}

-- Read-only globals: the vendored 1.60.1 API list (tests/tools/api-16001.txt) plus FrameXML constants/frames
-- also allowlisted in tests/gates.js (REF_ALLOW).
read_globals = {
  "_G", "RAID_CLASS_COLORS", "CLASS_ICON_TCOORDS", "UIParent", "GameTooltip", "DEFAULT_CHAT_FRAME", "Minimap",
  "UISpecialFrames", "STANDARD_TEXT_FONT", "GameFontNormal", "GameFontHighlight", "GameFontHighlightSmall",
  "GameFontNormalSmall", "GameFontNormalLarge", "GameFontDisable", "GameFontDisableSmall", "ChatFontNormal",
  "NORMAL_FONT_COLOR", "HIGHLIGHT_FONT_COLOR", "GRAY_FONT_COLOR", "RED_FONT_COLOR", "GREEN_FONT_COLOR",
  "YES", "NO", "OKAY", "CANCEL", "ACCEPT", "CLOSE",
  -- legacy / version-dependent APIs that the addon only uses behind a guard
  "GetAddOnMetadata", "IsEncounterInProgress", "SendChatMessage", "UnitPVPRank", "GetPVPRankInfo",
}
do
  local fields = {}
  local fh = io.open("tests/tools/api-16001.txt", "r")
  if fh then
    for line in fh:lines() do
      if line ~= "" and line:sub(1, 1) ~= "#" then
        local ns, fn = line:match("^([%w_]+)%.([%w_]+)$")
        if ns then
          fields[ns] = fields[ns] or {}
          fields[ns][#fields[ns] + 1] = fn
        elseif line:match("^[%w_]+$") then
          read_globals[#read_globals + 1] = line
        end
      end
    end
    fh:close()
  end
  for ns, list in pairs(fields) do
    if ns ~= "string" and ns ~= "table" and ns ~= "math" and ns ~= "os" and ns ~= "io" and ns ~= "coroutine" then
      read_globals[ns] = { fields = list }
    end
  end
end

