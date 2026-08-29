## Two-games-on-one-websocket reproduction / regression test.
##
## Bug (user symptom): after a game runs to completion (server sent
## GameEndedEventForBot) the server can NO LONGER start a new game — "bot is
## not listening anymore". Log: top-of-loop ws.connected=true → heartbeat
## running=false → msg_type=GameEndedEventForBot → silence from main thread.
##
## Why existing TCK/keepalive tests miss it: they send GameEnded as the last
## event and THEN close the ws (stopMockServer). Closing the ws makes
## waitForBotThreadWhileServicingWs return via `msg.len==0`, masking the deadlock.
##
## This test differs: after GameEnded the server KEEPS the ws open (as the real
## GUI does for the next match) and IMMEDIATELY starts a SECOND game on the same
## ws. It asserts the second game actually plays (onGameEnded fires, BotReady is
## sent for game 2, game 2's round advances).

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

type TwoGameBot = ref object of Bot

method onRoundStarted(bot: TwoGameBot, e: RoundStartedEvent) =
  {.cast(gcsafe).}: capRoundStarted.send(e.roundNumber)

method onRoundEnded(bot: TwoGameBot, e: RoundEndedEventForBot) =
  {.cast(gcsafe).}: capRoundEnded.send(e.roundNumber)

method onGameEnded(bot: TwoGameBot, e: GameEndedEventForBot) =
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

# ---------------------------------------------------------------------------
# Single bot session
# ---------------------------------------------------------------------------

var gBotThread: Thread[void]
var gBotInst: TwoGameBot

proc botThreadMain() {.thread.} =
  {.cast(gcsafe).}:
    putEnv("BOT_NAME",    "TwoGameBot")
    putEnv("BOT_VERSION", "1.0")
    putEnv("BOT_AUTHORS", "Tester")
    putEnv("BOT_IS_DROID","false")
    start(gBotInst, "")

var srv = startMockServer()
putEnv("SERVER_URL", srv.wsUrl())
gBotInst = TwoGameBot()
createThread(gBotThread, botThreadMain)
discard srv.awaitBotHandshake()

proc teardown() =
  # Close the ws so a deadlocked main thread (if any) can unwind, then join.
  stopMockServer(srv)
  joinThread(gBotThread)

try:
  # ---- Game 1: play to completion ----------------------------------------
  block:
    const name = "GAME1"
    srv.sendGameStarted(myId = 1)
    srv.awaitBotReady()
    srv.sendRoundStarted(1)
    discard capRoundStarted.awaitChan()
    srv.sendTick(1, 1, defaultTickState())
    discard srv.awaitBotIntent()
    srv.sendRoundEnded(1, 1)
    discard capRoundEnded.awaitChan()
    # Game ends. User log shows running=false here. Server keeps ws OPEN.
    srv.sendGameEnded(numberOfRounds = 1)
    # active awaited: 1 game
    let fired = capGameEnded.awaitChan(timeoutMs = 3000)
    assert fired, "Game 1 onGameEnded must fire"
    pass(name)

  # ---- Game 2: SAME ws, immediately after GameEnded ----------------------
  # The deadlock is at GameEnded's waitForBotThreadWhileServicingWs (bot already
  # idle → no gRoundDoneChan coming) and onGameEnded above never fired → this
  # block is never reached when the bug is present. Player 2 as RED signal.
  block:
    const name = "GAME2"
    srv.sendGameStarted(myId = 1)
    srv.awaitBotReady(timeoutMs = 5000)  # RED: main thread deadlocked
    srv.sendRoundStarted(2)
    let rn = capRoundStarted.awaitChan(timeoutMs = 5000)
    assert rn == 2, "game 2 round must actually start"
    srv.sendTick(2, 1, defaultTickState())
    discard srv.awaitBotIntent(timeoutMs = 5000)
    srv.sendRoundEnded(2, 1)
    discard capRoundEnded.awaitChan()
    pass(name)

  teardown()
  echo "ALL two-games tests PASSED"
except Exception as e:
  teardown()
  stderr.writeLine "GAME-LOOP-RED: " & e.msg
  raise
