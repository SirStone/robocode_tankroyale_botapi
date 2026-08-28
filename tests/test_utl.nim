## TR-API-UTL — Tier 1 utility tests.
##   TR-API-UTL-001: ColorUtil hex round-trip and string parsing
##   TR-API-UTL-002: JSON converter serialization/deserialization
##   TR-API-UTL-003: Country code validation and local detection

import std/[json, os]
import ../src/robocode_tankroyale_botapi/color
import ../src/robocode_tankroyale_botapi/json_parse
import ../src/robocode_tankroyale_botapi/bot_info

# ---------------------------------------------------------------------------
# TR-API-UTL-001: Color hex round-trip and string parsing
# ---------------------------------------------------------------------------

block colorRgbRoundTrip:
  let c = fromRgb(255, 0, 0)
  assert c.toHex == "#FF0000", "red hex: " & c.toHex
  assert c.r == 255 and c.g == 0 and c.b == 0 and c.a == 255

block colorRgbaRoundTrip:
  let c = fromRgba(0, 128, 255, 64)
  assert c.toHex == "#0080FF40", "rgba hex: " & c.toHex
  assert c.r == 0 and c.g == 128 and c.b == 255 and c.a == 64

block colorParseHex6:
  let c = fromHex("#1A2B3C")
  assert c.r == 0x1A and c.g == 0x2B and c.b == 0x3C and c.a == 0xFF

block colorParseHex8:
  let c = fromHex("#AABBCCDD")
  assert c.r == 0xAA and c.g == 0xBB and c.b == 0xCC and c.a == 0xDD

block colorRoundTripOpaque:
  # parse then serialize back must produce the same string (alpha==FF omitted)
  let hex = "#3C7AE1"
  assert fromHex(hex).toHex == hex

block colorRoundTripTranslucent:
  let hex = "#3C7AE180"
  assert fromHex(hex).toHex == hex

block colorParseNegative:
  var caught = false
  try: discard fromHex("ZZZZZZ")
  except: caught = true
  assert caught, "bad hex must raise"

block colorParseNegativeWrongLength:
  var caught = false
  try: discard fromHex("#ABC")   # 3 hex digits — invalid
  except ValueError: caught = true
  assert caught, "3-digit hex must raise ValueError"

block colorEqualityAndDollarSign:
  let a = fromHex("#FF0000")
  let b = fromRgb(255, 0, 0)
  assert a == b
  assert $a == "#FF0000"

echo "PASS: TR-API-UTL-001 Color"

# ---------------------------------------------------------------------------
# TR-API-UTL-002: JSON converter serialization/deserialization
# ---------------------------------------------------------------------------

block parseBulletStateBasic:
  let node = %*{
    "bulletId": 7, "ownerId": 2, "power": 1.5,
    "x": 10.0, "y": 20.0, "direction": 90.0, "color": "#FF0000"
  }
  let bs = parseBulletState(node)
  assert bs.bulletId == 7
  assert bs.ownerId == 2
  assert bs.power == 1.5
  assert bs.x == 10.0 and bs.y == 20.0
  assert bs.direction == 90.0
  assert bs.color == fromHex("#FF0000")

block parseBulletStateMissingColor:
  # color absent → Color(0)
  let node = %*{"bulletId": 1, "ownerId": 1, "power": 1.0,
                 "x": 0.0, "y": 0.0, "direction": 0.0}
  let bs = parseBulletState(node)
  assert bs.color == Color(0)

block parseBulletStateNil:
  let bs = parseBulletState(nil)
  assert bs.bulletId == 0

block parseBotStateBasic:
  let node = %*{
    "isDroid": false, "energy": 100.0,
    "x": 50.0, "y": 60.0, "direction": 45.0,
    "gunDirection": 90.0, "radarDirection": 135.0, "radarSweep": 30.0,
    "speed": 5.0, "turnRate": 1.0, "gunTurnRate": 2.0,
    "radarTurnRate": 3.0, "gunHeat": 0.5, "enemyCount": 3,
    "bodyColor": "#FF0000", "turretColor": "#00FF00",
    "radarColor": "#0000FF", "bulletColor": "#FFFFFF",
    "scanColor": "#000000", "tracksColor": "#AABBCC",
    "gunColor": "#112233"
  }
  let bs = parseBotState(node)
  assert bs.energy == 100.0
  assert bs.x == 50.0 and bs.y == 60.0
  assert bs.enemyCount == 3
  assert bs.bodyColor == fromHex("#FF0000")
  assert bs.gunColor == fromHex("#112233")

block parseBotStateNil:
  let bs = parseBotState(nil)
  assert bs.energy == 0.0

echo "PASS: TR-API-UTL-002 JSON"

# ---------------------------------------------------------------------------
# TR-API-UTL-003: Country code loading and local detection
# ---------------------------------------------------------------------------

block countryCodesFromJson:
  # Use an existing sample bot JSON that has countryCodes
  const sampleJson = currentSourcePath.parentDir / "../sample_bots/MyFirstBot/MyFirstBot.json"
  let info = botInfoFromJson(sampleJson)
  assert "IT" in info.countryCodes, "expected IT in countryCodes"

block countryCodesFromEnv:
  putEnv("BOT_NAME", "TestBot")
  putEnv("BOT_VERSION", "0.1")
  putEnv("BOT_AUTHORS", "Tester")
  putEnv("BOT_COUNTRY_CODES", "US, GB, DE")
  putEnv("BOT_GAME_TYPES", "classic")
  let info = botInfoFromEnv()
  assert info.countryCodes.len == 3, "expected 3 codes, got " & $info.countryCodes.len
  assert "US" in info.countryCodes
  assert "GB" in info.countryCodes
  assert "DE" in info.countryCodes

block countryCodesEmptyEnv:
  putEnv("BOT_COUNTRY_CODES", "")
  let info = botInfoFromEnv()
  assert info.countryCodes.len == 0, "empty env should yield no codes"

block countryCodesAbsentInJson:
  # Write a minimal JSON without countryCodes
  let tmpPath = getTempDir() / "test_bot_nocountry.json"
  writeFile(tmpPath, """{"name":"X","version":"1","authors":["A"],"gameTypes":["classic"]}""")
  let info = botInfoFromJson(tmpPath)
  assert info.countryCodes.len == 0
  removeFile(tmpPath)

echo "PASS: TR-API-UTL-003 Country codes"
