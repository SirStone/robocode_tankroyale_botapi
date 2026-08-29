## WS keep-alive / round-boundary disconnect regression tests.
##
## Verifies that the bot's main thread continues to service WS pings between
## rounds. The bug: waitForBotThread blocked the main thread so WS pings went
## unanswered; a strict server could time out and close the connection.
## The fix: waitForBotThreadWhileServicingWs interleaves receiveWithTimeout.
##
## Single bot session (like test_tck.nim) — initGlobals() must be called once.
## KA-001: 3 rounds with ~2 s inter-round delay (catches the original block).
## KA-002: explicit WS ping (opcode 0x9) between rounds; bot must stay connected.
## GameEnded terminates the receive loop and is sent last.

import std/[json, os, times]
import ../T2/mock_server
import ../../src/robocode_tankroyale_botapi

# ---------------------------------------------------------------------------
# Capture channels
# ---------------------------------------------------------------------------

var capRoundStarted: Channel[int]
var capRoundEnded:   Channel[int]
var capGameEnded:    Channel[bool]

capRoundStarted.open(16)
capRoundEnded.open(16)
capGameEnded.open(4)

# ---------------------------------------------------------------------------
# Bot
# ---------------------------------------------------------------------------

type KABot = ref object of Bot

method onRoundStarted(bot: KABot, e: RoundStartedEvent) =
  {.cast(gcsafe).}: capRoundStarted.send(e.roundNumber)

method onRoundEnded(bot: KABot, e: RoundEndedEventForBot) =
  {.cast(gcsafe).}: capRoundEnded.send(e.roundNumber)

method onGameEnded(bot: KABot, e: GameEndedEventForBot) =
  {.cast(gcsafe).}: capGameEnded.send(true)

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

proc awaitChan[T](ch: var Channel[T]; timeoutMs: int = 8000): T =
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

# runRound: send roundStarted → tick → awaitIntent → roundEnded
proc runRound(srv: var MockServer; roundN: int): MockBotIntent =
  srv.sendRoundStarted(roundN)
  discard capRoundStarted.awaitChan()
  srv.sendTick(roundN, 1, defaultTickState())
  result = srv.awaitBotIntent(timeoutMs = 8000)
  srv.sendRoundEnded(roundN, 1)
  discard capRoundEnded.awaitChan()

# ---------------------------------------------------------------------------
# Single bot session
# ---------------------------------------------------------------------------

var gBotThread: Thread[void]
var gKABotInst: KABot

proc botThreadMain() {.thread.} =
  {.cast(gcsafe).}:
    putEnv("BOT_NAME",    "KABot")
    putEnv("BOT_VERSION", "1.0")
    putEnv("BOT_AUTHORS", "Tester")
    putEnv("BOT_IS_DROID","false")
    start(gKABotInst, "")

var srv = startMockServer()
putEnv("SERVER_URL", srv.wsUrl())
gKABotInst = KABot()
createThread(gBotThread, botThreadMain)
discard srv.awaitBotHandshake()
srv.sendGameStarted(myId = 1)
srv.awaitBotReady()

# ---------------------------------------------------------------------------
# KA-001: 3 rounds with ~2 s inter-round delay
## Old code: main thread blocked in waitForBotThread during the gap;
## a strict server (or a 2 s WS ping timeout) would close the connection.
# ---------------------------------------------------------------------------
block:
  const name = "KA-001"
  for roundN in 1 .. 3:
    discard srv.runRound(roundN)
    # ~2 s gap; new code services WS pings here via waitForBotThreadWhileServicingWs
    if roundN < 3: sleep(2000)
  pass(name)

# ---------------------------------------------------------------------------
# KA-002: explicit WS ping between rounds
## Mock server sends a real ping frame (opcode 0x9) between rounds 4 and 5.
## The bot must pong (handled inside waitForBotThreadWhileServicingWs) and
## remain connected for the next round.
# ---------------------------------------------------------------------------
block:
  const name = "KA-002"
  discard srv.runRound(4)
  srv.sendPing()
  sleep(300)  # give bot time to receive and pong
  discard srv.runRound(5)
  pass(name)

# ---------------------------------------------------------------------------
# Teardown — GameEnded must be last (terminates receive loop)
# ---------------------------------------------------------------------------
srv.sendRoundStarted(6)
discard capRoundStarted.awaitChan()
srv.sendTick(6, 1, defaultTickState())
discard srv.awaitBotIntent(timeoutMs = 8000)
srv.sendGameEnded(numberOfRounds = 6)
discard capGameEnded.awaitChan()

stopMockServer(srv)
joinThread(gBotThread)

echo "ALL WS keep-alive tests PASSED"
