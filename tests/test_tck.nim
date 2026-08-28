## TR-API-TCK Tier 2 protocol conformance tests.
##
## Uses mock_server.nim to drive the full WS handshake → game lifecycle
## without a real Java server.
##
## Design:
##   All TCK scenarios run against a SINGLE bot session (one start() call,
##   which calls initGlobals() exactly once — calling it twice corrupts the
##   already-opened channels).  The mock server drives one scenario per round.
##   The bot is started once, runs through all rounds, then the session is
##   terminated by sendGameEnded (used to assert TCK-011).
##
##   Each scenario uses awaitChan helpers on test-side channels filled by the
##   overridden TestBot method handlers.
##
## Real-protocol note:
##   GameEndedEventForBot is sent by the real server WHILE a round is in
##   progress (after a tick, instead of RoundEndedEventForBot), so it is
##   always placed as the LAST test in this file.
##
## TR-API-TCK-013: unknown server message type fires onConnectionError.
##   Fixed in robocode_tankroyale_botapi.nim: else branch in runReceiveLoop
##   now calls gBot.onConnectionError instead of silently discarding.

import std/[json, os, strutils, times]
import ./mock_server
import ../src/robocode_tankroyale_botapi

# ---------------------------------------------------------------------------
# Test-side capture channels  (opened once for the lifetime of the process)
# ---------------------------------------------------------------------------

var capRoundStarted:   Channel[int]       # roundNumber
var capRoundEnded:     Channel[(int,int)] # (roundNumber, turnNumber)
var capGameEnded:      Channel[int]       # numberOfRounds
var capSkippedTurn:    Channel[int]       # turnNumber
var capDeath:          Channel[bool]      # true = onDeath fired
var capBotDeath:       Channel[int]       # victimId
var capHitByBullet:    Channel[bool]      # true = onHitByBullet fired
var capBulletHit:      Channel[int]       # victimId from onBulletHit
var capWonRound:       Channel[bool]      # true = onWonRound fired
var capTeamMessage:    Channel[string]    # message text from onTeamMessage
var capConnError:      Channel[string]    # error text from onConnectionError

capRoundStarted.open(16)
capRoundEnded.open(16)
capGameEnded.open(16)
capSkippedTurn.open(16)
capDeath.open(16)
capBotDeath.open(16)
capHitByBullet.open(16)
capBulletHit.open(16)
capWonRound.open(16)
capTeamMessage.open(16)
capConnError.open(16)

# ---------------------------------------------------------------------------
# TestBot — captures every event into test-side channels
# ---------------------------------------------------------------------------

type TestBot = ref object of Bot

method onRoundStarted(bot: TestBot, e: RoundStartedEvent) =
  {.cast(gcsafe).}: capRoundStarted.send(e.roundNumber)

method onRoundEnded(bot: TestBot, e: RoundEndedEventForBot) =
  {.cast(gcsafe).}: capRoundEnded.send((e.roundNumber, e.turnNumber))

method onGameEnded(bot: TestBot, e: GameEndedEventForBot) =
  {.cast(gcsafe).}: capGameEnded.send(e.numberOfRounds)

method onSkippedTurn(bot: TestBot, e: SkippedTurnEvent) =
  {.cast(gcsafe).}: capSkippedTurn.send(e.turnNumber)

method onDeath(bot: TestBot, e: BotDeathEvent) =
  {.cast(gcsafe).}: capDeath.send(true)

method onBotDeath(bot: TestBot, e: BotDeathEvent) =
  {.cast(gcsafe).}: capBotDeath.send(e.victimId)

method onHitByBullet(bot: TestBot, e: HitByBulletEvent) =
  {.cast(gcsafe).}: capHitByBullet.send(true)

method onBulletHit(bot: TestBot, e: BulletHitBotEvent) =
  {.cast(gcsafe).}: capBulletHit.send(e.victimId)

method onWonRound(bot: TestBot, e: WonRoundEvent) =
  {.cast(gcsafe).}: capWonRound.send(true)

method onTeamMessage(bot: TestBot, e: TeamMessageEvent) =
  {.cast(gcsafe).}: capTeamMessage.send(e.message)

method onConnectionError(bot: TestBot, e: ConnectionErrorEvent) =
  {.cast(gcsafe).}: capConnError.send(e.error)

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

proc awaitChan[T](ch: var Channel[T]; timeoutMs: int = 5000): T =
  let deadline = epochTime() + timeoutMs.float / 1000.0
  while epochTime() < deadline:
    let (ok, v) = ch.tryRecv()
    if ok: return v
    sleep(10)
  raise newException(ValueError, "awaitChan: timeout after " & $timeoutMs & "ms")

proc defaultTickState(): MockTickState =
  MockTickState(energy: 100.0, x: 200.0, y: 300.0, direction: 45.0,
                gunDirection: 45.0, radarDirection: 45.0, speed: 0.0,
                gunHeat: 1.0, enemyCount: 1)

proc pass(name: string) = echo "PASS " & name
proc fail(name, msg: string) =
  raise newException(AssertionDefect, "FAIL " & name & ": " & msg)

template assertEq[T](a, b: T; name, msg: string) =
  if a != b: fail(name, msg & " (got " & $a & ", want " & $b & ")")

template assertTrue(cond: bool; name, msg: string) =
  if not cond: fail(name, msg)

template assertFalse(cond: bool; name, msg: string) =
  if cond: fail(name, msg)

# ---------------------------------------------------------------------------
# Single bot session — one thread, one start() call for the whole test run
# ---------------------------------------------------------------------------

var gBotThread: Thread[void]
# Kept as a global so ORC doesn't try to collect it while gBot* still holds a ref.
# ponytail: global bot ref, single-bot-per-process constraint
var gTestBotInst: TestBot

proc botThreadMain() {.thread.} =
  {.cast(gcsafe).}:
    putEnv("BOT_NAME",    "TCKBot")
    putEnv("BOT_VERSION", "1.0")
    putEnv("BOT_AUTHORS", "Tester")
    putEnv("BOT_IS_DROID","false")
    start(gTestBotInst, "")

var srv = startMockServer()
putEnv("SERVER_URL", srv.wsUrl())
gTestBotInst = TestBot()
createThread(gBotThread, botThreadMain)

# ---------------------------------------------------------------------------
# Round helper: start a round, run one tick, end the round
# Returns after awaitBotIntent and capRoundEnded have both been consumed.
# ---------------------------------------------------------------------------
proc runRound(roundN, myId: int; extraEvents: JsonNode = nil): MockBotIntent =
  srv.sendRoundStarted(roundN)
  discard capRoundStarted.awaitChan()
  srv.sendTick(roundN, 1, defaultTickState(), extraEvents)
  result = srv.awaitBotIntent()
  srv.sendRoundEnded(roundN, 1)
  discard capRoundEnded.awaitChan()

# ---- TCK-007: BotHandshake fields ------------------------------------------
block:
  let name = "TCK-007"
  let hs = srv.awaitBotHandshake()
  assertEq(hs.sessionId, "mock-session-001", name, "sessionId")
  assertEq(hs.name,      "TCKBot",           name, "name")
  assertEq(hs.version,   "1.0",              name, "version")
  assertEq(hs.authors,   @["Tester"],        name, "authors")
  assertFalse(hs.isDroid,                    name, "isDroid must be false")
  assertTrue(hs.name.len > 0,                name, "name not empty (neg)")
  pass(name)

# ---- TCK-008: Bot sends BotReady after GameStarted -------------------------
block:
  let name = "TCK-008"
  srv.sendGameStarted(myId = 1)
  srv.awaitBotReady()  # raises ValueError on timeout
  # negative: awaitBotReady already proved exactly one BotReady arrived
  pass(name)

# ---- TCK-009: onRoundStarted fires with roundNumber -------------------------
block:
  let name = "TCK-009"
  # Round 1: check roundNumber == 1
  srv.sendRoundStarted(1)
  let rn1 = capRoundStarted.awaitChan()
  assertEq(rn1, 1, name, "roundNumber round 1")
  assertFalse(rn1 == 0, name, "roundNumber != 0 (neg)")
  srv.sendTick(1, 1, defaultTickState())
  discard srv.awaitBotIntent()
  srv.sendRoundEnded(1, 1)
  discard capRoundEnded.awaitChan()
  pass(name)

# ---- TCK-004: Bot sees first tick and sends initial BotIntent --------------
block:
  let name = "TCK-004"
  srv.sendRoundStarted(2)
  discard capRoundStarted.awaitChan()
  srv.sendTick(2, 1, defaultTickState())
  let intent = srv.awaitBotIntent()
  # default no-op run() → zeroed motion
  assertEq(intent.turnRate,    0.0, name, "turnRate default")
  assertEq(intent.targetSpeed, 0.0, name, "targetSpeed default")
  assertFalse(intent.firepower < 0.0, name, "firepower >= 0 (neg)")
  srv.sendRoundEnded(2, 1)
  discard capRoundEnded.awaitChan()
  pass(name)

# ---- TCK-010: onRoundEnded fires with correct roundNumber and turnNumber ----
block:
  let name = "TCK-010"
  srv.sendRoundStarted(3)
  discard capRoundStarted.awaitChan()
  srv.sendTick(3, 1, defaultTickState())
  discard srv.awaitBotIntent()
  srv.sendRoundEnded(roundNumber = 3, turnNumber = 5)
  let (rn, tn) = capRoundEnded.awaitChan()
  assertEq(rn, 3, name, "roundNumber")
  assertEq(tn, 5, name, "turnNumber")
  # negative: no spurious second roundEnded
  sleep(80)
  let (extra, _) = capRoundEnded.tryRecv()
  assertFalse(extra, name, "no spurious second roundEnded")
  pass(name)

# ---- TCK-012: onSkippedTurn fires with turnNumber==7 -----------------------
block:
  let name = "TCK-012"
  srv.sendRoundStarted(4)
  discard capRoundStarted.awaitChan()
  srv.sendTick(4, 1, defaultTickState())
  discard srv.awaitBotIntent()
  # SkippedTurnEvent is a top-level server message (not inside a tick)
  srv.sendRaw("""{"type":"SkippedTurnEvent","turnNumber":7}""")
  let tn = capSkippedTurn.awaitChan()
  assertEq(tn, 7, name, "turnNumber")
  assertFalse(tn == 0, name, "turnNumber != 0 (neg)")
  srv.sendRoundEnded(4, 7)
  discard capRoundEnded.awaitChan()
  pass(name)

# ---- TCK-005: WonRoundEvent in tick events → onWonRound --------------------
block:
  let name = "TCK-005"
  srv.sendRoundStarted(5)
  discard capRoundStarted.awaitChan()
  let extraEvents = %*[{"type": "WonRoundEvent", "turnNumber": 1}]
  srv.sendTick(5, 1, defaultTickState(), extraEvents)
  discard srv.awaitBotIntent()
  let fired = capWonRound.awaitChan()
  assertTrue(fired, name, "onWonRound fired")
  srv.sendRoundEnded(5, 1)
  discard capRoundEnded.awaitChan()
  pass(name)

# ---- TCK-006: TeamMessageEvent in tick events → onTeamMessage --------------
block:
  let name = "TCK-006"
  srv.sendRoundStarted(6)
  discard capRoundStarted.awaitChan()
  let extraEvents = %*[{
    "type":        "TeamMessageEvent",
    "turnNumber":  1,
    "message":     "hello-team",
    "messageType": "String",
    "senderId":    2
  }]
  srv.sendTick(6, 1, defaultTickState(), extraEvents)
  discard srv.awaitBotIntent()
  let msg = capTeamMessage.awaitChan()
  assertEq(msg, "hello-team", name, "message text")
  srv.sendRoundEnded(6, 1)
  discard capRoundEnded.awaitChan()
  pass(name)

# ---- TCK-014: BotDeathEvent victimId==myId → onDeath (not onBotDeath) ------
# myId=1 from sendGameStarted above
block:
  let name = "TCK-014"
  srv.sendRoundStarted(7)
  discard capRoundStarted.awaitChan()
  let extraEvents = %*[{"type": "BotDeathEvent", "turnNumber": 1, "victimId": 1}]
  srv.sendTick(7, 1, defaultTickState(), extraEvents)
  discard srv.awaitBotIntent()
  let fired = capDeath.awaitChan()
  assertTrue(fired, name, "onDeath fired")
  sleep(80)
  let (extra, _) = capBotDeath.tryRecv()
  assertFalse(extra, name, "onBotDeath must NOT fire for self-death (neg)")
  srv.sendRoundEnded(7, 1)
  discard capRoundEnded.awaitChan()
  pass(name)

# ---- TCK-015: BotDeathEvent victimId!=myId → onBotDeath (not onDeath) ------
block:
  let name = "TCK-015"
  srv.sendRoundStarted(8)
  discard capRoundStarted.awaitChan()
  let extraEvents = %*[{"type": "BotDeathEvent", "turnNumber": 1, "victimId": 99}]
  srv.sendTick(8, 1, defaultTickState(), extraEvents)
  discard srv.awaitBotIntent()
  let vid = capBotDeath.awaitChan()
  assertEq(vid, 99, name, "victimId")
  sleep(80)
  let (extra, _) = capDeath.tryRecv()
  assertFalse(extra, name, "onDeath must NOT fire for other-bot-death (neg)")
  srv.sendRoundEnded(8, 1)
  discard capRoundEnded.awaitChan()
  pass(name)

# ---- TCK-016: BulletHitBotEvent victimId==myId → onHitByBullet -------------
block:
  let name = "TCK-016"
  srv.sendRoundStarted(9)
  discard capRoundStarted.awaitChan()
  let extraEvents = %*[{
    "type":       "BulletHitBotEvent",
    "turnNumber": 1,
    "victimId":   1,
    "bullet":     {"bulletId": 1, "ownerId": 2, "power": 1.0,
                   "x": 100.0, "y": 100.0, "direction": 0.0},
    "damage":     4.0,
    "energy":     96.0
  }]
  srv.sendTick(9, 1, defaultTickState(), extraEvents)
  discard srv.awaitBotIntent()
  let fired = capHitByBullet.awaitChan()
  assertTrue(fired, name, "onHitByBullet fired")
  sleep(80)
  let (extra, _) = capBulletHit.tryRecv()
  assertFalse(extra, name, "onBulletHit must NOT fire for self-hit (neg)")
  srv.sendRoundEnded(9, 1)
  discard capRoundEnded.awaitChan()
  pass(name)

# ---- TCK-017: BulletHitBotEvent victimId!=myId → onBulletHit ---------------
block:
  let name = "TCK-017"
  srv.sendRoundStarted(10)
  discard capRoundStarted.awaitChan()
  let extraEvents = %*[{
    "type":       "BulletHitBotEvent",
    "turnNumber": 1,
    "victimId":   55,
    "bullet":     {"bulletId": 2, "ownerId": 1, "power": 1.5,
                   "x": 150.0, "y": 200.0, "direction": 90.0},
    "damage":     6.0,
    "energy":     50.0
  }]
  srv.sendTick(10, 1, defaultTickState(), extraEvents)
  discard srv.awaitBotIntent()
  let vid = capBulletHit.awaitChan()
  assertEq(vid, 55, name, "victimId")
  sleep(80)
  let (extra, _) = capHitByBullet.tryRecv()
  assertFalse(extra, name, "onHitByBullet must NOT fire for other-bot-hit (neg)")
  srv.sendRoundEnded(10, 1)
  discard capRoundEnded.awaitChan()
  pass(name)

# ---- TCK-013: unknown server message type → onConnectionError --------------
block:
  let name = "TCK-013"
  # Send an unrecognised message type between rounds.
  # The receive loop must call onConnectionError (not silently discard).
  srv.sendRaw("""{"type":"UnknownFutureServerMessage","data":"test"}""")
  let errMsg = capConnError.awaitChan()
  assertTrue(errMsg.contains("UnknownFutureServerMessage"), name,
             "error must name the unknown type (got: " & errMsg & ")")
  # negative: no spurious second error
  sleep(80)
  let (extra, _) = capConnError.tryRecv()
  assertFalse(extra, name, "no spurious second onConnectionError (neg)")
  pass(name)

# ---- TCK-011: onGameEnded fires with numberOfRounds==10 --------------------
# Must be LAST: GameEndedEventForBot terminates the receive loop.
# Real protocol: server sends GameEnded while a round is in progress
# (replaces the final RoundEndedEventForBot), so we send it after a tick.
block:
  let name = "TCK-011"
  srv.sendRoundStarted(11)
  discard capRoundStarted.awaitChan()
  srv.sendTick(11, 1, defaultTickState())
  discard srv.awaitBotIntent()
  srv.sendGameEnded(numberOfRounds = 10)
  let nr = capGameEnded.awaitChan()
  assertEq(nr, 10, name, "numberOfRounds")
  assertFalse(nr == 0, name, "numberOfRounds != 0 (neg)")
  pass(name)

# ---- Teardown ---------------------------------------------------------------
stopMockServer(srv)
joinThread(gBotThread)

echo "ALL TR-API-TCK Tier 2 tests PASSED"
