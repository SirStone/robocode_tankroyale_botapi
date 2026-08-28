## Tier-1 validation tests (TR-API-VAL-001..005)
## Driven by tests/shared/botinfo-validation.json and constants.json.
import std/[unittest, strutils]
import ../src/robocode_tankroyale_botapi/bot_info
import ../src/robocode_tankroyale_botapi/constants
import ../src/robocode_tankroyale_botapi/schemas

# ---------------------------------------------------------------------------
# TR-API-VAL-001  BotInfo required fields (positive)
# ---------------------------------------------------------------------------
suite "TR-API-VAL-001 BotInfo required fields":

  test "constructor with only required fields":
    let b = newBotInfo("MyBot", "1.0", @["Author 1"])
    check b.name == "MyBot"
    check b.version == "1.0"
    check b.authors == @["Author 1"]

  test "fields are trimmed":
    let b = newBotInfo("  MyBot  ", "  1.0  ", @[" Author 1 "])
    check b.name == "MyBot"
    check b.version == "1.0"
    check b.authors == @["Author 1"]

# ---------------------------------------------------------------------------
# TR-API-VAL-002  BotInfo invalid fields rejected (negative)
# ---------------------------------------------------------------------------
suite "TR-API-VAL-002 BotInfo invalid fields":

  test "name exceeding max length raises ValueError":
    let longName = "A".repeat(64)
    expect ValueError:
      discard newBotInfo(longName, "1.0", @["Author"])

  test "country codes normalized to upper case":
    let b = newBotInfo("Bot", "1.0", @["Author"],
                       countryCodes = @["gb", " us "])
    check b.countryCodes == @["GB", "US"]

# ---------------------------------------------------------------------------
# TR-API-VAL-003  InitialPosition defaults
# ---------------------------------------------------------------------------
suite "TR-API-VAL-003 InitialPosition defaults":

  test "zero-value InitialPosition has all fields 0.0":
    let ip: InitialPosition = InitialPosition()
    check ip.x == 0.0
    check ip.y == 0.0
    check ip.direction == 0.0

# ---------------------------------------------------------------------------
# TR-API-VAL-004  InitialPosition mapping round-trip
# ---------------------------------------------------------------------------
suite "TR-API-VAL-004 InitialPosition round-trip":

  test "x, y, direction survive assignment":
    let ip = InitialPosition(x: 100.0, y: 200.0, direction: 90.0)
    check ip.x == 100.0
    check ip.y == 200.0
    check ip.direction == 90.0

  test "BotInfo embeds InitialPosition correctly":
    var b = newBotInfo("Bot", "1.0", @["A"])
    b.initialPosition = InitialPosition(x: 50.0, y: 75.0, direction: 45.0)
    check b.initialPosition.x == 50.0
    check b.initialPosition.y == 75.0
    check b.initialPosition.direction == 45.0

# ---------------------------------------------------------------------------
# TR-API-VAL-005  API constants integrity
# ---------------------------------------------------------------------------
suite "TR-API-VAL-005 API constants":

  test "MAX_SPEED":           check MAX_SPEED == 8.0
  test "ACCELERATION":        check ACCELERATION == 1.0
  test "DECELERATION":        check DECELERATION == -2.0
  test "MAX_TURN_RATE":       check MAX_TURN_RATE == 10.0
  test "MAX_GUN_TURN_RATE":   check MAX_GUN_TURN_RATE == 20.0
  test "MAX_RADAR_TURN_RATE": check MAX_RADAR_TURN_RATE == 45.0
  test "CLASSIC":             check CLASSIC == "classic"
  test "MELEE":               check MELEE == "melee"
  test "ONE_VS_ONE":          check ONE_VS_ONE == "1v1"
  test "INACTIVITY_ZAP":      check INACTIVITY_ZAP == 0.1
  test "RAM_DAMAGE":          check RAM_DAMAGE == 0.6
  test "STARTING_GUN_HEAT":   check STARTING_GUN_HEAT == 3.0
  test "TEAM_MESSAGE_MAX_SIZE":
    check TEAM_MESSAGE_MAX_SIZE == 32768
  test "MAX_NUMBER_OF_TEAM_MESSAGES_PER_TURN":
    check MAX_NUMBER_OF_TEAM_MESSAGES_PER_TURN == 10
