## TR-API-MDL Tier 1+2: Data model tests.
import std/unittest
import ../../src/robocode_tankroyale_botapi/utils
import ../../src/robocode_tankroyale_botapi/schemas

# TR-API-MDL-001: calcBulletSpeed — positive cases (from bullet-state.json)

# power 0.0 → clamped to MIN_FIRE_POWER (0.1) → 20 - 3*0.1 = 19.7
assert calcBulletSpeed(0.0) == 19.7, "TR-API-MDL-001-speed-0.0"
assert calcBulletSpeed(0.1) == 19.7, "TR-API-MDL-001-speed-0.1"
assert calcBulletSpeed(0.5) == 18.5, "TR-API-MDL-001-speed-0.5"
assert calcBulletSpeed(1.0) == 17.0, "TR-API-MDL-001-speed-1.0"
assert calcBulletSpeed(2.0) == 14.0, "TR-API-MDL-001-speed-2.0"
assert calcBulletSpeed(3.0) == 11.0, "TR-API-MDL-001-speed-3.0"

# TR-API-MDL-001: calcBulletSpeed — negative cases (boundary / out-of-range)
# power > MAX_FIRE_POWER (3.0) → clamped to 3.0 → speed still 11.0
assert calcBulletSpeed(4.0) == 11.0, "TR-API-MDL-001-speed-4.0-clamped"
# negative power → clamped to MIN_FIRE_POWER (0.1) → speed still 19.7
assert calcBulletSpeed(-1.0) == 19.7, "TR-API-MDL-001-speed-neg-clamped"

echo "PASS: TR-API-MDL-001 calcBulletSpeed"

# ---------------------------------------------------------------------------
# TR-API-MDL-002: BotState constructor — verify fields from schema
# ---------------------------------------------------------------------------

suite "TR-API-MDL-002: BotState constructor":
  test "BotState fields set and read correctly":
    var s: BotState
    s.energy         = 75.5
    s.x              = 200.0
    s.y              = 300.0
    s.direction      = 45.0
    s.gunDirection   = 90.0
    s.radarDirection = 135.0
    s.speed          = 4.0
    s.gunHeat        = 0.5
    s.enemyCount     = 3
    s.isDroid        = false
    check s.energy         == 75.5
    check s.x              == 200.0
    check s.y              == 300.0
    check s.direction      == 45.0
    check s.gunDirection   == 90.0
    check s.radarDirection == 135.0
    check s.speed          == 4.0
    check s.gunHeat        == 0.5
    check s.enemyCount     == 3
    check s.isDroid        == false

  test "BotState default-initialised to zero values":
    let s = BotState()
    check s.energy     == 0.0
    check s.x          == 0.0
    check s.enemyCount == 0
    check s.isDroid    == false

  test "negative: mutating one field does not affect others":
    var s = BotState()
    s.energy = 50.0
    check s.x         == 0.0
    check s.enemyCount == 0

# ---------------------------------------------------------------------------
# TR-API-MDL-003: BotResults constructor — verify ResultsForBot fields
# ---------------------------------------------------------------------------

suite "TR-API-MDL-003: BotResults constructor":
  test "ResultsForBot stores all score fields":
    let r = ResultsForBot(
      rank:              2,
      survival:          100,
      lastSurvivorBonus: 50,
      bulletDamage:      300,
      bulletKillBonus:   20,
      ramDamage:         10,
      ramKillBonus:      5,
      totalScore:        485,
      firstPlaces:       1,
      secondPlaces:      2,
      thirdPlaces:       0
    )
    check r.rank              == 2
    check r.survival          == 100
    check r.lastSurvivorBonus == 50
    check r.bulletDamage      == 300
    check r.bulletKillBonus   == 20
    check r.ramDamage         == 10
    check r.ramKillBonus      == 5
    check r.totalScore        == 485
    check r.firstPlaces       == 1
    check r.secondPlaces      == 2
    check r.thirdPlaces       == 0

  test "ResultsForBot default-initialised to zero":
    let r = ResultsForBot()
    check r.rank       == 0
    check r.totalScore == 0

  test "negative: rank=1 is valid (winner)":
    let r = ResultsForBot(rank: 1, totalScore: 999)
    check r.rank == 1

# ---------------------------------------------------------------------------
# TR-API-MDL-004: GameSetup constructor — verify fields
# ---------------------------------------------------------------------------

suite "TR-API-MDL-004: GameSetup constructor":
  test "GameSetup stores all fields":
    let g = GameSetup(
      gameType:                         "classic",
      arenaWidth:                       800,
      isArenaWidthLocked:               false,
      arenaHeight:                      600,
      isArenaHeightLocked:              false,
      minNumberOfParticipants:          2,
      isMinNumberOfParticipantsLocked:  false,
      maxNumberOfParticipants:          10,
      isMaxNumberOfParticipantsLocked:  false,
      numberOfRounds:                   10,
      isNumberOfRoundsLocked:           false,
      gunCoolingRate:                   0.1,
      isGunCoolingRateLocked:           false,
      maxInactivityTurns:               450,
      isMaxInactivityTurnsLocked:       false,
      turnTimeout:                      30000,
      isTurnTimeoutLocked:              false,
      readyTimeout:                     1000000,
      isReadyTimeoutLocked:             false,
      defaultTurnsPerSecond:            30
    )
    check g.gameType                        == "classic"
    check g.arenaWidth                      == 800
    check g.arenaHeight                     == 600
    check g.numberOfRounds                  == 10
    check g.gunCoolingRate                  == 0.1
    check g.maxInactivityTurns              == 450
    check g.turnTimeout                     == 30000
    check g.defaultTurnsPerSecond           == 30
    check g.isArenaWidthLocked              == false
    check g.minNumberOfParticipants         == 2
    check g.maxNumberOfParticipants         == 10

  test "GameSetup default-initialised":
    let g = GameSetup()
    check g.gameType   == ""
    check g.arenaWidth == 0

  test "negative: locked flags toggle independently":
    let g = GameSetup(
      arenaWidth: 400, isArenaWidthLocked: true,
      arenaHeight: 300, isArenaHeightLocked: false
    )
    check g.isArenaWidthLocked  == true
    check g.isArenaHeightLocked == false
