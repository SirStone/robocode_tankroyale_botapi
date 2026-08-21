## BotInfo: bot identification loaded from a JSON file or environment variables.

import std/[os, json, strutils, sequtils]
import ./schemas

type
  BotInfo* = object
    name*:           string
    version*:        string
    authors*:        seq[string]
    description*:    string
    homepage*:       string
    countryCodes*:   seq[string]
    gameTypes*:      seq[string]
    platform*:       string
    programmingLang*: string
    initialPosition*: InitialPosition
    isDroid*:         bool

proc botInfoFromJson*(path: string): BotInfo =
  let data = parseJson(readFile(path))
  result.name    = data{"name"}.getStr
  result.version = data{"version"}.getStr
  if data.hasKey("authors"):
    for a in data["authors"]: result.authors.add a.getStr
  result.description   = data{"description"}.getStr
  result.homepage      = data{"homepage"}.getStr
  if data.hasKey("countryCodes"):
    for c in data["countryCodes"]: result.countryCodes.add c.getStr
  if data.hasKey("gameTypes"):
    for g in data["gameTypes"]: result.gameTypes.add g.getStr
  result.platform      = data{"platform"}.getStr("Nim " & NimVersion)
  result.programmingLang = data{"programmingLang"}.getStr("Nim")
  if data.hasKey("initialPosition"):
    let ip = data["initialPosition"]
    result.initialPosition.x         = ip{"x"}.getFloat
    result.initialPosition.y         = ip{"y"}.getFloat
    result.initialPosition.direction = ip{"direction"}.getFloat
  result.isDroid = data{"isDroid"}.getBool(false)

proc botInfoFromEnv*(): BotInfo =
  ## Fall back to environment variables when no JSON file is given.
  result.name    = getEnv("BOT_NAME", "Unnamed Bot")
  result.version = getEnv("BOT_VERSION", "1.0")
  let authorsStr = getEnv("BOT_AUTHORS", "Unknown")
  result.authors = authorsStr.split(',').mapIt(it.strip)
  result.description = getEnv("BOT_DESCRIPTION", "")
  result.homepage    = getEnv("BOT_HOMEPAGE", "")
  let ccStr = getEnv("BOT_COUNTRY_CODES", "")
  if ccStr.len > 0:
    result.countryCodes = ccStr.split(',').mapIt(it.strip)
  let gtStr = getEnv("BOT_GAME_TYPES", "classic,melee,1v1")
  result.gameTypes = gtStr.split(',').mapIt(it.strip)
  result.platform      = getEnv("BOT_PLATFORM", "Nim " & NimVersion)
  result.programmingLang = getEnv("BOT_PROGRAMMING_LANG", "Nim")
  result.isDroid = getEnv("BOT_IS_DROID", "false").toLowerAscii == "true"

proc loadBotInfo*(jsonFile: string = ""): BotInfo =
  var resolved = ""
  if jsonFile.len > 0:
    if fileExists(jsonFile):
      resolved = jsonFile
    else:
      # Try alongside the executable
      let appPath = getAppDir() / jsonFile
      if fileExists(appPath):
        resolved = appPath

  if resolved.len > 0:
    result = botInfoFromJson(resolved)
  else:
    result = botInfoFromEnv()
  # Ensure gameTypes has at least one entry
  if result.gameTypes.len == 0:
    result.gameTypes = @["classic", "melee", "1v1"]
  if result.platform.len == 0:
    result.platform = "Nim " & NimVersion
  if result.programmingLang.len == 0:
    result.programmingLang = "Nim"
