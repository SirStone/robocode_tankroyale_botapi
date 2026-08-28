## TR-API-EVT Tier 1 tests — event criticality, priorities, queue behaviour.
import std/unittest
import ../../src/robocode_tankroyale_botapi/event_queue
import ../../src/robocode_tankroyale_botapi/constants
import ../../src/robocode_tankroyale_botapi/schemas

# helpers to build minimal BotEvent values for each kind
proc mkDeath(turn: int): BotEvent =
  BotEvent(kind: ekDeath, turnNumber: turn, death: BotDeathEvent())

proc mkWonRound(turn: int): BotEvent =
  BotEvent(kind: ekWonRound, turnNumber: turn, wonRound: WonRoundEvent())

proc mkSkippedTurn(turn: int): BotEvent =
  BotEvent(kind: ekSkippedTurn, turnNumber: turn, skippedTurn: SkippedTurnEvent())

proc mkBotDeath(turn: int): BotEvent =
  BotEvent(kind: ekBotDeath, turnNumber: turn, botDeath: BotDeathEvent())

proc mkHitBot(turn: int): BotEvent =
  BotEvent(kind: ekHitBot, turnNumber: turn, hitBot: BotHitBotEvent())

proc mkHitWall(turn: int): BotEvent =
  BotEvent(kind: ekHitWall, turnNumber: turn, hitWall: BotHitWallEvent())

proc mkBulletFired(turn: int): BotEvent =
  BotEvent(kind: ekBulletFired, turnNumber: turn, bulletFired: BulletFiredEvent())

proc mkBulletHitBot(turn: int): BotEvent =
  BotEvent(kind: ekBulletHitBot, turnNumber: turn, bulletHitBot: BulletHitBotEvent())

proc mkBulletHitBullet(turn: int): BotEvent =
  BotEvent(kind: ekBulletHitBullet, turnNumber: turn, bulletHitBullet: BulletHitBulletEvent())

proc mkBulletHitWall(turn: int): BotEvent =
  BotEvent(kind: ekBulletHitWall, turnNumber: turn, bulletHitWall: BulletHitWallEvent())

proc mkHitByBullet(turn: int): BotEvent =
  BotEvent(kind: ekHitByBullet, turnNumber: turn, hitByBullet: HitByBulletEvent())

proc mkScannedBot(turn: int): BotEvent =
  BotEvent(kind: ekScannedBot, turnNumber: turn, scannedBot: ScannedBotEvent())

proc mkCustom(turn: int): BotEvent =
  BotEvent(kind: ekCustom, turnNumber: turn,
    condition: Condition(name: "test", test: proc(): bool = true))

proc mkTeamMessage(turn: int): BotEvent =
  BotEvent(kind: ekTeamMessage, turnNumber: turn, teamMessage: TeamMessageEvent())

suite "TR-API-EVT-002: critical events":
  test "DeathEvent isCritical":
    check mkDeath(1).isCritical == true
  test "WonRoundEvent isCritical":
    check mkWonRound(1).isCritical == true
  test "SkippedTurnEvent isCritical":
    check mkSkippedTurn(1).isCritical == true

suite "TR-API-EVT-003: non-critical events":
  test "BotDeathEvent not critical":
    check mkBotDeath(1).isCritical == false
  test "BotHitBotEvent not critical":
    check mkHitBot(1).isCritical == false
  test "BotHitWallEvent not critical":
    check mkHitWall(1).isCritical == false
  test "BulletFiredEvent not critical":
    check mkBulletFired(1).isCritical == false
  test "BulletHitBotEvent not critical":
    check mkBulletHitBot(1).isCritical == false
  test "BulletHitBulletEvent not critical":
    check mkBulletHitBullet(1).isCritical == false
  test "BulletHitWallEvent not critical":
    check mkBulletHitWall(1).isCritical == false
  test "HitByBulletEvent not critical":
    check mkHitByBullet(1).isCritical == false
  test "ScannedBotEvent not critical":
    check mkScannedBot(1).isCritical == false
  test "CustomEvent not critical":
    check mkCustom(1).isCritical == false
  test "TeamMessageEvent not critical":
    check mkTeamMessage(1).isCritical == false

suite "TR-API-EVT-004: default event priorities":
  test "WonRoundEvent = 150":
    check priorityOf(ekWonRound) == PRIORITY_WON_ROUND
    check PRIORITY_WON_ROUND == 150
  test "SkippedTurnEvent = 140":
    check priorityOf(ekSkippedTurn) == PRIORITY_SKIPPED_TURN
    check PRIORITY_SKIPPED_TURN == 140
  test "TickEvent = 130":
    check priorityOf(ekTick) == PRIORITY_TICK
    check PRIORITY_TICK == 130
  test "CustomEvent = 120":
    check priorityOf(ekCustom) == PRIORITY_CUSTOM
    check PRIORITY_CUSTOM == 120
  test "TeamMessageEvent = 110":
    check priorityOf(ekTeamMessage) == PRIORITY_TEAM_MESSAGE
    check PRIORITY_TEAM_MESSAGE == 110
  test "BotDeathEvent = 100":
    check priorityOf(ekBotDeath) == PRIORITY_BOT_DEATH
    check PRIORITY_BOT_DEATH == 100
  test "BulletHitWallEvent = 90":
    check priorityOf(ekBulletHitWall) == PRIORITY_BULLET_HIT_WALL
    check PRIORITY_BULLET_HIT_WALL == 90
  test "BulletHitBulletEvent = 80":
    check priorityOf(ekBulletHitBullet) == PRIORITY_BULLET_HIT_BULLET
    check PRIORITY_BULLET_HIT_BULLET == 80
  test "BulletHitBotEvent = 70":
    check priorityOf(ekBulletHitBot) == PRIORITY_BULLET_HIT_BOT
    check PRIORITY_BULLET_HIT_BOT == 70
  test "BulletFiredEvent = 60":
    check priorityOf(ekBulletFired) == PRIORITY_BULLET_FIRED
    check PRIORITY_BULLET_FIRED == 60
  test "HitByBulletEvent = 50":
    check priorityOf(ekHitByBullet) == PRIORITY_HIT_BY_BULLET
    check PRIORITY_HIT_BY_BULLET == 50
  test "HitWallEvent = 40":
    check priorityOf(ekHitWall) == PRIORITY_HIT_WALL
    check PRIORITY_HIT_WALL == 40
  test "HitBotEvent = 30":
    check priorityOf(ekHitBot) == PRIORITY_HIT_BOT
    check PRIORITY_HIT_BOT == 30
  test "ScannedBotEvent = 20":
    check priorityOf(ekScannedBot) == PRIORITY_SCANNED_BOT
    check PRIORITY_SCANNED_BOT == 20
  test "DeathEvent = 10":
    check priorityOf(ekDeath) == PRIORITY_DEATH
    check PRIORITY_DEATH == 10

suite "TR-API-EVT-005: EventQueue priority ordering":
  test "critical before non-critical, higher priority critical first":
    var eq = initEventQueue()
    eq.addEvent mkDeath(1)       # critical, priority 10
    eq.addEvent mkWonRound(1)    # critical, priority 150
    eq.addEvent mkScannedBot(1)  # non-critical, priority 20
    eq.sortEvents()
    let evts = eq.getEvents()
    check evts.len == 3
    check evts[0].kind == ekWonRound   # highest priority critical
    check evts[1].kind == ekDeath      # lower priority critical
    check evts[2].kind == ekScannedBot # non-critical last

suite "TR-API-EVT-006: EventQueue age culling":
  test "non-critical events older than MAX_EVENTS_AGE turns are culled; critical kept":
    # MAX_EVENTS_AGE = 2; at turn 10: cull if turnNumber < 10-2 = 8
    var eq = initEventQueue()
    eq.addEvent mkScannedBot(7)  # non-critical, age = 3 → culled
    eq.addEvent mkScannedBot(8)  # non-critical, age = 2 → kept
    eq.addEvent mkWonRound(7)    # critical → always kept
    eq.removeOldEvents(10)
    eq.sortEvents()
    let evts = eq.getEvents()
    check evts.len == 2
    check evts[0].kind == ekWonRound   # critical first
    check evts[1].kind == ekScannedBot # the surviving non-critical

suite "TR-API-EVT-007: EventQueue size cap":
  test "addEvent silently discards events beyond MAX_QUEUE_SIZE (256)":
    var eq = initEventQueue()
    for i in 0 ..< 266:
      eq.addEvent mkSkippedTurn(0)
    check eq.getEvents().len == MAX_QUEUE_SIZE
    check MAX_QUEUE_SIZE == 256

suite "TR-API-EVT-001: Event constructors store fields correctly":
  ## Verify event objects created from schema types have correct field values.
  ## These are plain Nim object constructors — no server protocol needed.
  test "ScannedBotEvent stores all fields":
    let e = ScannedBotEvent(
      turnNumber:     5,
      scannedByBotId: 1,
      scannedBotId:   2,
      energy:         80.0,
      x:              300.0,
      y:              400.0,
      direction:      90.0,
      speed:          4.0
    )
    check e.turnNumber     == 5
    check e.scannedByBotId == 1
    check e.scannedBotId   == 2
    check e.energy         == 80.0
    check e.x              == 300.0
    check e.y              == 400.0
    check e.direction      == 90.0
    check e.speed          == 4.0

  test "BulletFiredEvent stores bullet fields":
    let b = BulletState(bulletId: 7, ownerId: 1, power: 2.5, x: 10.0, y: 20.0, direction: 45.0)
    let e = BulletFiredEvent(turnNumber: 3, bullet: b)
    check e.turnNumber      == 3
    check e.bullet.bulletId == 7
    check e.bullet.power    == 2.5
    check e.bullet.x        == 10.0

  test "HitByBulletEvent stores damage and energy":
    let b = BulletState(bulletId: 9, ownerId: 2, power: 1.0, x: 0.0, y: 0.0, direction: 0.0)
    let e = HitByBulletEvent(turnNumber: 8, bullet: b, damage: 4.0, energy: 60.0)
    check e.damage == 4.0
    check e.energy == 60.0

  test "BotHitBotEvent stores rammed flag":
    let e = BotHitBotEvent(turnNumber: 2, victimId: 3, botId: 1,
                            energy: 50.0, x: 5.0, y: 6.0, rammed: true)
    check e.rammed == true
    check e.victimId == 3

  test "WonRoundEvent stores turnNumber":
    let e = WonRoundEvent(turnNumber: 42)
    check e.turnNumber == 42

  test "negative: zero-value event has default fields":
    let e = ScannedBotEvent()
    check e.turnNumber     == 0
    check e.energy         == 0.0
    check e.scannedBotId   == 0

suite "TR-API-EVT-008: Condition.test() callable and overridable":
  ## Condition is a struct with a closure field — verify it is callable
  ## and can be assigned different implementations.
  test "Condition.test() returns true when proc returns true":
    let c = Condition(name: "always", test: proc(): bool = true)
    check c.test() == true

  test "Condition.test() returns false when proc returns false":
    let c = Condition(name: "never", test: proc(): bool = false)
    check c.test() == false

  test "Condition closure captures external state":
    var flag = false
    let c = Condition(name: "flag", test: proc(): bool = flag)
    check c.test() == false
    flag = true
    check c.test() == true

  test "negative: two conditions with same name are independent":
    let c1 = Condition(name: "x", test: proc(): bool = true)
    let c2 = Condition(name: "x", test: proc(): bool = false)
    check c1.test() == true
    check c2.test() == false

suite "TR-API-EVT-009: CustomEvent dispatches when Condition.test() is true":
  ## addCustomEvents evaluates all conditions each tick and enqueues ekCustom
  ## events for those whose test() returns true.
  test "condition that returns true fires a custom event":
    var eq = initEventQueue()
    eq.addCondition(Condition(name: "fire", test: proc(): bool = true))
    eq.addCustomEvents(turnNumber = 1)
    let evts = eq.getEvents()
    check evts.len == 1
    check evts[0].kind == ekCustom
    check evts[0].condition.name == "fire"

  test "condition that returns false does not fire":
    var eq = initEventQueue()
    eq.addCondition(Condition(name: "no-fire", test: proc(): bool = false))
    eq.addCustomEvents(turnNumber = 1)
    check eq.getEvents().len == 0

  test "only true conditions fire when mixed":
    var eq = initEventQueue()
    eq.addCondition(Condition(name: "yes", test: proc(): bool = true))
    eq.addCondition(Condition(name: "no",  test: proc(): bool = false))
    eq.addCustomEvents(turnNumber = 2)
    let evts = eq.getEvents()
    check evts.len == 1
    check evts[0].condition.name == "yes"

  test "removeConditionByName prevents future firing":
    var eq = initEventQueue()
    eq.addCondition(Condition(name: "to-remove", test: proc(): bool = true))
    eq.removeConditionByName("to-remove")
    eq.addCustomEvents(turnNumber = 1)
    check eq.getEvents().len == 0

  test "negative: condition raising exception is silently swallowed":
    var eq = initEventQueue()
    eq.addCondition(Condition(name: "boom", test: proc(): bool = raise newException(ValueError, "oops"); false))
    # addCustomEvents wraps in try/except — must not propagate
    eq.addCustomEvents(turnNumber = 1)
    check eq.getEvents().len == 0
