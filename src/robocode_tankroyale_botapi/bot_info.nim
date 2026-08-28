## Bot identity and metadata loading for Robocode Tank Royale.
##
## `BotInfo` stores information about your bot such as its name, version, authors,
## description, and supported game types. This metadata is sent to the server
## during the initial connection handshake.
##
## ## How metadata is loaded
##
## When calling `start(bot, "MyBot.json")`, `loadBotInfo` resolves the bot info in this order:
##
## 1. **JSON file**: If a path to a JSON file is provided and exists, metadata is parsed from it.
## 2. **JSON file next to binary**: If `jsonFile` is relative, it also looks in the application directory.
## 3. **Environment variables**: If no JSON file is specified or found, fallback values are read from
##    environment variables (`BOT_NAME`, `BOT_VERSION`, `BOT_AUTHORS`, `BOT_DESCRIPTION`, etc.).
##
## ## JSON Profile Example (`MyBot.json`)
##
## ```
## {
##   "name": "My First Bot",
##   "version": "1.0",
##   "authors": ["Alice", "Bob"],
##   "description": "A battle bot built with Nim",
##   "homepage": "https://example.com/mybot",
##   "countryCodes": ["us", "ca"],
##   "gameTypes": ["classic", "melee", "1v1"],
##   "platform": "Nim 2.0",
##   "programmingLang": "Nim"
## }
## ```

import std/[os, json, strutils, sequtils]
import ./schemas

const MAX_NAME_LEN* = 63  ## Maximum allowed length in characters for `BotInfo.name`.

type
  BotInfo* = object
    ## Contains all metadata identifying a bot to the Tank Royale server.
    name*:           string         ## Name of the bot (max 63 characters)
    version*:        string         ## Version string (e.g. "1.0.0")
    authors*:        seq[string]    ## List of author names
    description*:    string         ## Short summary of what the bot does
    homepage*:       string         ## URL to bot webpage or repo
    countryCodes*:   seq[string]    ## ISO 3166-1 alpha-2 country codes (e.g. @["US"])
    gameTypes*:      seq[string]    ## Supported modes ("classic", "melee", "1v1")
    platform*:       string         ## Platform string (defaults to Nim version)
    programmingLang*: string        ## Programming language ("Nim")
    initialPosition*: InitialPosition ## Optional starting coordinates (x, y, direction)
    isDroid*:         bool          ## True if this bot is a Droid (extra energy, no radar)

proc newBotInfo*(name: string; version: string; authors: seq[string];
                 description = ""; homepage = "";
                 countryCodes: seq[string] = @[];
                 gameTypes: seq[string] = @[];
                 platform = ""; programmingLang = "";
                 isDroid = false): BotInfo =
  ## Construct a validated `BotInfo` object.
  ##
  ## Trims whitespace from all string fields, converts country codes to uppercase,
  ## and ensures `name` does not exceed `MAX_NAME_LEN` (63 characters).
  ##
  ## Raises `ValueError` if the bot name is too long.
  let n = name.strip
  if n.len > MAX_NAME_LEN:
    raise newException(ValueError,
      "BotInfo name exceeds maximum length of " & $MAX_NAME_LEN & " characters")
  result.name    = n
  result.version = version.strip
  result.authors = authors.mapIt(it.strip)
  result.description   = description.strip
  result.homepage      = homepage.strip
  result.countryCodes  = countryCodes.mapIt(it.strip.toUpperAscii)
  result.gameTypes     = gameTypes
  result.platform      = platform
  result.programmingLang = programmingLang
  result.isDroid       = isDroid

proc botInfoFromJson*(path: string): BotInfo =
  ## Parse a `BotInfo` structure from a JSON configuration file at `path`.
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
  ## Load `BotInfo` settings from environment variables.
  ##
  ## Uses variables like `BOT_NAME`, `BOT_VERSION`, `BOT_AUTHORS`, `BOT_DESCRIPTION`,
  ## `BOT_HOMEPAGE`, `BOT_COUNTRY_CODES`, `BOT_GAME_TYPES`, `BOT_PLATFORM`,
  ## `BOT_PROGRAMMING_LANG`, and `BOT_IS_DROID`.
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
  ## Load bot configuration from a JSON file, or fall back to environment variables.
  ##
  ## If `jsonFile` is provided, it tries to read from that path. If not found directly,
  ## it also checks relative to the application's binary directory. If `jsonFile` is empty
  ## or missing, it falls back to environment variables via `botInfoFromEnv`.
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
