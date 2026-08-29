## Main entry-point module for Robocode Tank Royale Nim bot API.
##
## This module is the primary interface for writing Robocode Tank Royale bots in Nim.
## It re-exports all public symbols from the submodules, so you only need to import
## this one module in your bot code.
##
## ## Quick Start
##
## 1. Create a bot type that inherits from `Bot`:
##
##    ```nim
##    import robocode_tankroyale_botapi
##
##    type MyBot = ref object of Bot
##    method run(bot: MyBot) =
##      # Your bot logic here
##      forward(100)
##      turnLeft(90)
##      fire(2.0)
##    ```
##
## 2. Create an instance and start it with your bot's JSON configuration file:
##
##    ```nim
##    var bot = MyBot()
##    start(bot, "MyBot.json")
##    ```
##
## The JSON file contains your bot's identity (name, version, authors, etc.) and
## optional settings like initial position and game types. See `BotInfo` for details.
##
## ## Architecture Overview
##
## The API uses a three-thread architecture:
##
## - **Main thread**: Runs the WebSocket receive loop, processes incoming server
##   messages, updates shared state, and wakes the bot thread each tick.
## - **Bot thread**: Runs your `run()` method and event handlers. It blocks on
##   `go()` waiting for the next tick.
## - **Sender thread**: Owns all WebSocket writes, sending your bot's intents to
##   the server.
##
## Communication between threads happens through channels, avoiding shared mutable
## state where possible.
##
## ## Exported Modules
##
## This module re-exports the following submodules:
##
## - `constants` -- Game physics constants and event priorities
## - `color` -- Color type with 141 named colors and hex parsing
## - `schemas` -- Protocol message types (events, game setup, etc.)
## - `utils` -- Math and geometry helpers (bearing, distance, angles)
## - `bot_info` -- Bot identity loading from JSON or environment
## - `ws_client` -- Low-level WebSocket client (internal)
## - `json_parse` -- Safe JSON-to-type parsing (internal)
## - `event_queue` -- Priority-based event dispatch (internal)
## - `bot` -- Core bot implementation, movement, and event handlers
## - `graphics` -- SVG debug graphics for visualization
##
## ## See Also
##
## - `Bot` -- Base class for your bot implementation
## - `start` -- Connect to server and begin the game loop
## - `BotInfo` -- Bot identity configuration

import std/[net, os, json]

import ./robocode_tankroyale_botapi/constants
import ./robocode_tankroyale_botapi/color
import ./robocode_tankroyale_botapi/schemas
import ./robocode_tankroyale_botapi/utils
import ./robocode_tankroyale_botapi/bot_info
import ./robocode_tankroyale_botapi/ws_client
import ./robocode_tankroyale_botapi/json_parse
import ./robocode_tankroyale_botapi/event_queue
import ./robocode_tankroyale_botapi/bot
import ./robocode_tankroyale_botapi/graphics

export constants
export color
export schemas
export utils
export bot_info
export json_parse
export event_queue
export bot
export graphics

# ---------------------------------------------------------------------------
# WebSocket receive loop (main thread)
# ---------------------------------------------------------------------------

proc handleServerHandshake(ws: SyncWebSocket; node: JsonNode; info: BotInfo; secret: string) =
  let sessionId = node{"sessionId"}.getStr
  setServerInfo(node{"variant"}.getStr, node{"version"}.getStr)

  # Build bot handshake
  var h = newJObject()
  h["type"]           = %"BotHandshake"
  h["sessionId"]      = %sessionId
  h["name"]           = %info.name
  h["version"]        = %info.version
  h["authors"]        = %info.authors
  h["description"]    = %info.description
  h["homepage"]       = %info.homepage
  h["countryCodes"]   = %info.countryCodes
  h["gameTypes"]      = %info.gameTypes
  h["platform"]       = %info.platform
  h["programmingLang"]= %info.programmingLang
  h["isDroid"]        = %info.isDroid
  if secret.len > 0:
    h["secret"] = %secret
  let ip = info.initialPosition
  if ip.x != 0.0 or ip.y != 0.0 or ip.direction != 0.0:
    var ipObj = newJObject()
    if ip.x != 0.0:         ipObj["x"]         = %ip.x
    if ip.y != 0.0:         ipObj["y"]         = %ip.y
    if ip.direction != 0.0: ipObj["direction"] = %ip.direction
    h["initialPosition"] = ipObj
  ws.send($h)

proc parseGameSetup(node: JsonNode): GameSetup =
  if node.isNil: return
  result.gameType                      = node{"gameType"}.getStr("classic")
  result.arenaWidth                    = node{"arenaWidth"}.getInt(800)
  result.isArenaWidthLocked            = node{"isArenaWidthLocked"}.getBool(false)
  result.arenaHeight                   = node{"arenaHeight"}.getInt(600)
  result.isArenaHeightLocked           = node{"isArenaHeightLocked"}.getBool(false)
  result.numberOfRounds                = node{"numberOfRounds"}.getInt(10)
  result.isNumberOfRoundsLocked        = node{"isNumberOfRoundsLocked"}.getBool(false)
  result.minNumberOfParticipants       = node{"minNumberOfParticipants"}.getInt(2)
  result.isMinNumberOfParticipantsLocked = node{"isMinNumberOfParticipantsLocked"}.getBool(false)
  result.maxNumberOfParticipants       = node{"maxNumberOfParticipants"}.getInt(10)
  result.isMaxNumberOfParticipantsLocked = node{"isMaxNumberOfParticipantsLocked"}.getBool(false)
  result.gunCoolingRate                = node{"gunCoolingRate"}.getFloat(0.1)
  result.isGunCoolingRateLocked        = node{"isGunCoolingRateLocked"}.getBool(false)
  result.maxInactivityTurns            = node{"maxInactivityTurns"}.getInt(450)
  result.isMaxInactivityTurnsLocked    = node{"isMaxInactivityTurnsLocked"}.getBool(false)
  result.turnTimeout                   = node{"turnTimeout"}.getInt(30000)
  result.isTurnTimeoutLocked           = node{"isTurnTimeoutLocked"}.getBool(false)
  result.readyTimeout                  = node{"readyTimeout"}.getInt(1000000)
  result.isReadyTimeoutLocked          = node{"isReadyTimeoutLocked"}.getBool(false)
  result.defaultTurnsPerSecond         = node{"defaultTurnsPerSecond"}.getInt(30)

proc handleGameStarted(ws: SyncWebSocket; node: JsonNode) =
  let setup = parseGameSetup(node{"gameSetup"})

  var teammateIds: seq[int] = @[]
  if not node{"teammateIds"}.isNil and node["teammateIds"].kind == JArray:
    for id in node["teammateIds"]: teammateIds.add id.getInt

  let myId = node{"myId"}.getInt
  setGameStarted(myId, setup, teammateIds)

  # Build event object manually - GameStartedEventForBot has no turnNumber
  let e = GameStartedEventForBot(
    `type`:         "GameStartedEventForBot",
    myId:           myId,
    startX:         node{"startX"}.getFloat(0.0),
    startY:         node{"startY"}.getFloat(0.0),
    startDirection: node{"startDirection"}.getFloat(0.0),
    teammateIds:    teammateIds,
    gameSetup:      setup
  )
  gBot.onGameStarted(e)

  # Send BotReady
  ws.send("""{"type":"BotReady"}""")

proc handleTick(node: JsonNode) =
  # Build TickEventForBot manually to handle optional fields safely
  var tick: TickEventForBot
  tick.`type`      = "TickEventForBot"
  tick.turnNumber  = node{"turnNumber"}.getInt(0)
  tick.roundNumber = node{"roundNumber"}.getInt(0)
  tick.botState    = parseBotState(node{"botState"})
  tick.bulletStates = @[]
  if not node{"bulletStates"}.isNil and node["bulletStates"].kind == JArray:
    for bs in node["bulletStates"]:
      tick.bulletStates.add parseBulletState(bs)
  tick.events = @[]  # sub-events parsed separately into typed BotEvent

  # Parse embedded events into typed BotEvent for priority-based dispatch
  var events: seq[BotEvent] = @[]
  let myId = getMyId()
  if node.hasKey("events") and node["events"].kind == JArray:
    for ev in node["events"]:
      events.add parseBotEvent(ev, myId)

  signalTick(tick, events)          # update shared state
  processTickOnMainThread()         # motion tracking (while bot is blocked)
  wakeBotThread()                   # wake bot - state + motion ready

proc runReceiveLoop*(
  ws: SyncWebSocket;
  info: BotInfo;
  secret: string;
  serverUrl: string
) =
  ## Main WebSocket receive loop.
  ##
  ## This procedure runs on the main thread and handles all incoming messages
  ## from the Tank Royale server. It:
  ##
  ## - Receives WebSocket frames
  ## - Parses JSON messages
  ## - Dispatches messages to appropriate handlers (handshake, game start, ticks,
  ##   round end, game end, etc.)
  ## - Updates shared game state
  ## - Signals the bot thread when a new tick arrives
  ##
  ## The loop runs until the connection is closed or a fatal error occurs.
  ## Timeouts are ignored; the bot waits indefinitely for server messages.
  ##
  ## **Note**: This is an internal procedure. You typically don't call it
  ## directly; use `start()` instead.
  ##
  ## Parameters:
  ## - `ws`: The connected WebSocket
  ## - `info`: Your bot's identity information
  ## - `secret`: Optional server secret for authentication
  ## - `serverUrl`: The server URL (used for error reporting)
  stderr.writeLine "[LIVELINESS] MAIN_THREAD: alive — entering receive loop"
  while ws.connected:
    stderr.writeLine "[LIVELINESS] MAIN_THREAD: top-of-loop ws.connected=" & $ws.connected
    stderr.writeLine "[LIVELINESS] MAIN_THREAD: heartbeat round=" & $getRound() & " turn=" & $getTurn() & " ws.connected=" & $ws.connected & " running=" & $isRunning()
    var msg: string
    if gPendingMsg.len > 0:
      msg = gPendingMsg
      gPendingMsg = ""
    else:
      try:
        msg = ws.receive()
      except TimeoutError:
        debugLog "[ws] recv timeout, retrying"
        continue
      except Exception as e:
        stderr.writeLine "[ws] receive error: " & e.msg
        gBot.onConnectionError(ConnectionErrorEvent(serverUrl: serverUrl, error: e.msg))
        break

    if msg.len == 0:
      stderr.writeLine "[ws] server closed connection - disconnected"
      break  # connection closed

    var node: JsonNode
    try:
      node = parseJson(msg)
    except Exception as e:
      stderr.writeLine "[ws] json parse error: " & e.msg
      continue

    let msgType = node{"type"}.getStr
    stderr.writeLine "[LIVELINESS] MAIN_THREAD: msg_type=" & msgType & " ws.connected=" & $ws.connected
    try:
      case msgType
      of "ServerHandshake":
        handleServerHandshake(ws, node, info, secret)
      of "GameStartedEventForBot":
        # A new game can start mid-fight when the host restarts the match; the
        # server does NOT send GameAbortedEvent in this path. Reference bots keep
        # the same WebSocket and reply with BotReady quickly, because the server
        # enforces readyTimeout and drops a bot that answers late. Order matters:
        #   1) kick the stale round to stop FIRST (fast signalStop, non-blocking)
        #      so onGameStarted sees a clean state;
        #   2) then handleGameStarted sets state, publishes onGameStarted, and
        #      sends BotReady -- all fast, well within readyTimeout;
        #   3) only AFTER BotReady is out do the blocking wait for the old bot
        #      thread, so the wait can never delay BotReady past readyTimeout.
        # (If we waited on the bot thread before sending BotReady, the old round's
        # unwinding would delay our response and the server would kick us.)
        let wasRunning = isRunning()
        if wasRunning:
          setRunning(false)
          signalStop()
        handleGameStarted(ws, node)
        if wasRunning:
          waitForBotThreadWhileServicingWs(ws)
          drainTickChan()      # drain stop signal if bot exited via isRunning() check
          drainIntentChan()    # drain while bot is idle - no more writes this round
          drainEventChan()     # drop any unconsumed tick events
      of "RoundStartedEvent":
        let e = node.to(RoundStartedEvent)
        debugLog("[NS-ENTER] round=" & $e.roundNumber & " tid=" & $getThreadId())
        # Signal new round to persistent bot thread (creates it on first call).
        startRound()
        startBotThread()
        gBot.onRoundStarted(e)
        debugLog("[NS-EXIT] round=" & $e.roundNumber & " tid=" & $getThreadId())
      of "TickEventForBot":
        handleTick(node)
      of "RoundEndedEventForBot":
        setRunning(false)
        let e = node.to(RoundEndedEventForBot)
        debugLog("[RE-ENTER] round=" & $e.roundNumber & " tid=" & $getThreadId())
        signalStop()         # unblock bot thread blocked in go()
        debugLog("[WT-ENTER] round=" & $e.roundNumber & " tid=" & $getThreadId())
        waitForBotThreadWhileServicingWs(ws)
        debugLog("[WT-EXIT] round=" & $e.roundNumber & " tid=" & $getThreadId())
        debugLog("[DR-ENTER] round=" & $e.roundNumber & " tid=" & $getThreadId())
        drainTickChan()      # drain stop signal if bot exited via isRunning() check
        drainIntentChan()    # drain while bot is idle - no more writes this round
        drainEventChan()     # drop any unconsumed tick events (stale into next round)
        debugLog("[DR-EXIT] round=" & $e.roundNumber & " tid=" & $getThreadId())
        debugLog("[ONRE-ENTER] round=" & $e.roundNumber & " tid=" & $getThreadId())
        gBot.onRoundEnded(e)
        debugLog("[ONRE-EXIT] round=" & $e.roundNumber & " tid=" & $getThreadId())
      of "GameEndedEventForBot":
        let e = node.to(GameEndedEventForBot)
        # Bot is only EVER mid-round if running==true. When the game ends after
        # the final RoundEndedEventForBot (the user's symptom: running==false at
        # GameEnded), the bot thread is ALREADY idle (blocked at gStartRoundChan),
        # and its round-done signal was already consumed by the RoundEnded wait.
        # In that state we must NOT signalStop (it would leave a stray `false` in
        # gTickChan that the next round's first gTickChan.recv() would misread as
        # "stop before first tick", skipping the whole new round) and must NOT
        # waitForBotThreadWhileServicingWs (no round-done is ever coming — deadlock
        # until the ws closes, so the server can never start a new game on this ws).
        if isRunning():
          setRunning(false)
          signalStop()         # unblock bot thread if mid-round
          waitForBotThreadWhileServicingWs(ws)
          drainTickChan()
          drainIntentChan()
          drainEventChan()
        else:
          # already idle: just drop any leftovers; do not inject a stop signal
          drainTickChan()
          drainIntentChan()
          drainEventChan()
        gBot.onGameEnded(e)
      of "GameAbortedEvent":
        # Same invariant as GameEnded: only wait/signalStop when actually mid-round.
        if isRunning():
          setRunning(false)
          signalStop()         # unblock bot thread (game aborted mid-round)
          waitForBotThreadWhileServicingWs(ws)
          drainTickChan()      # drain stop signal if bot exited via isRunning() check
          drainIntentChan()    # drain while bot is idle - no more writes this round
          drainEventChan()     # drop any unconsumed tick events
        else:
          drainTickChan()
          drainIntentChan()
          drainEventChan()
        gBot.onGameAborted()
      of "SkippedTurnEvent":
        let e = node.to(SkippedTurnEvent)
        gBot.onSkippedTurn(e)
      of "BotListUpdate":
        updateBotNames(node)
      else:
        let errMsg = "Unknown message type: " & msgType
        stderr.writeLine "[ws] " & errMsg
        gBot.onConnectionError(ConnectionErrorEvent(serverUrl: serverUrl, error: errMsg))
    except Exception as e:
      # A raised handler/callback must not kill the receive loop — that is the
      # silent corpse path (process lives, no intents ever again). Log and continue.
      stderr.writeLine "[ws] handler error (" & msgType & "): " & e.msg
      debugLog("[WS-HANDLER-ERR] " & msgType & ": " & e.msg)

  # Loop exited: server disconnected or ws error. Stop the bot if still running,
  # then join the persistent bot thread so the process exits cleanly.
  if isRunning():
    debugLog("[DBG] receive loop exited while running — stopping bot thread")
    setRunning(false)
    signalStop()
    waitForBotThread()
    drainTickChan()
    drainIntentChan()
    drainEventChan()
  stderr.writeLine "[LIVELINESS] MAIN_THREAD: exiting receive loop — ws.connected=" & $ws.connected
  shutdownBotThread()  # final join of persistent thread
  gBot.onDisconnected(DisconnectedEvent(serverUrl: serverUrl))

# ---------------------------------------------------------------------------
# Public start() procedure
# ---------------------------------------------------------------------------

proc start*(
  bot: Bot;
  jsonFile: string = ""
) =
  ## Connect to the Tank Royale server and start the bot's game loop.
  ##
  ## This is the main entry point for running your bot. It:
  ##
  ## 1. Loads your bot's identity from `jsonFile` (or environment variables)
  ## 2. Connects to the WebSocket server (default: `ws://localhost:7654`)
  ## 3. Performs the handshake with the server
  ## 4. Starts the three-thread architecture (receive, bot, sender)
  ## 5. Blocks until the game ends or connection is lost
  ##
  ## The procedure never returns normally -- it runs until the game ends,
  ## the server disconnects, or a fatal error occurs.
  ##
  ## ## Configuration
  ##
  ## You can configure the connection via environment variables:
  ##
  ## - `SERVER_URL` -- WebSocket server URL (default: `ws://localhost:7654`)
  ## - `SERVER_SECRET` -- Optional secret for authenticated servers
  ##
  ## ## Parameters
  ##
  ## - `bot`: An instance of your bot type (must inherit from `Bot`)
  ## - `jsonFile`: Path to your bot's JSON configuration file. If empty or
  ##   not found, falls back to environment variables (`BOT_NAME`, `BOT_VERSION`,
  ##   `BOT_AUTHORS`, etc.). See `loadBotInfo` for details.
  ##
  ## ## Example
  ##
  ## ```nim
  ## import robocode_tankroyale_botapi
  ##
  ## type MyBot = ref object of Bot
  ## method run(bot: MyBot) =
  ##   while true:
  ##     forward(100)
  ##     turnLeft(90)
  ##
  ## var bot = MyBot()
  ## start(bot, "MyBot.json")
  ## ```
  stderr.writeLine "[LIVELINESS] MAIN_THREAD: start() called"
  gBot = bot
  gBotInfo = loadBotInfo(jsonFile)
  initGlobals()

  let serverUrl    = getEnv("SERVER_URL", "ws://localhost:7654")
  let serverSecret = getEnv("SERVER_SECRET", "")

  stderr.writeLine "[LIVELINESS] MAIN_THREAD: connecting to serverUrl=" & serverUrl
  try:
    gWs = newSyncWebSocket(serverUrl)
  except Exception as e:
    stderr.writeLine "[start] Cannot connect to " & serverUrl & ": " & e.msg
    quit(1)

  stderr.writeLine "[LIVELINESS] MAIN_THREAD: WebSocket connected successfully"

  bot.onConnected(ConnectedEvent(serverUrl: serverUrl))
  stderr.writeLine "[LIVELINESS] MAIN_THREAD: connected, starting sender thread"
  startSenderThread()
  stderr.writeLine "[LIVELINESS] MAIN_THREAD: sender thread started"
  runReceiveLoop(gWs, gBotInfo, serverSecret, serverUrl)
  stderr.writeLine "[LIVELINESS] MAIN_THREAD: runReceiveLoop returned, stopping sender"
  stopSenderThread()
  stderr.writeLine "[LIVELINESS] MAIN_THREAD: sender thread stopped"
  stderr.writeLine "[LIVELINESS] MAIN_THREAD: shutdown complete, process exiting"  # note: shutdownBotThread() + onDisconnected already ran at end of runReceiveLoop
