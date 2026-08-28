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

  # Build event object manually — GameStartedEventForBot has no turnNumber
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
  wakeBotThread()                   # wake bot — state + motion ready

const WS_MAX_CONSECUTIVE_TIMEOUTS = 5
  ## Maximum consecutive WebSocket receive timeouts before disconnecting.
  ## If the server goes silent for this many consecutive reads, the connection
  ## is considered dead and the bot will shut down.

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
  ## The loop runs until the connection is closed or too many consecutive
  ## timeouts occur (see `WS_MAX_CONSECUTIVE_TIMEOUTS`).
  ##
  ## **Note**: This is an internal procedure. You typically don't call it
  ## directly; use `start()` instead.
  ##
  ## Parameters:
  ## - `ws`: The connected WebSocket
  ## - `info`: Your bot's identity information
  ## - `secret`: Optional server secret for authentication
  ## - `serverUrl`: The server URL (used for error reporting)
  var consecutiveTimeouts = 0
  while ws.connected:
    var msg: string
    try:
      msg = ws.receive()
      consecutiveTimeouts = 0  # reset on any successful recv
    except TimeoutError:
      inc consecutiveTimeouts
      stderr.writeLine "[ws] recv timeout (" & $consecutiveTimeouts & "/" &
        $WS_MAX_CONSECUTIVE_TIMEOUTS & ") — server silent, retrying"
      if consecutiveTimeouts >= WS_MAX_CONSECUTIVE_TIMEOUTS:
        stderr.writeLine "[ws] max consecutive timeouts reached — disconnecting"
        ws.connected = false
        break
      continue
    except Exception as e:
      stderr.writeLine "[ws] receive error: " & e.msg
      gBot.onConnectionError(ConnectionErrorEvent(serverUrl: serverUrl, error: e.msg))
      break

    if msg.len == 0:
      break  # connection closed

    var node: JsonNode
    try:
      node = parseJson(msg)
    except Exception as e:
      stderr.writeLine "[ws] json parse error: " & e.msg
      continue

    let msgType = node{"type"}.getStr
    try:
      case msgType
      of "ServerHandshake":
        handleServerHandshake(ws, node, info, secret)
      of "GameStartedEventForBot":
        handleGameStarted(ws, node)
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
        waitForBotThread()   # wait for bot to finish round loop (back to idle)
        debugLog("[WT-EXIT] round=" & $e.roundNumber & " tid=" & $getThreadId())
        debugLog("[DR-ENTER] round=" & $e.roundNumber & " tid=" & $getThreadId())
        drainTickChan()      # drain stop signal if bot exited via isRunning() check
        drainIntentChan()    # drain while bot is idle — no more writes this round
        drainEventChan()     # drop any unconsumed tick events (stale into next round)
        debugLog("[DR-EXIT] round=" & $e.roundNumber & " tid=" & $getThreadId())
        debugLog("[ONRE-ENTER] round=" & $e.roundNumber & " tid=" & $getThreadId())
        gBot.onRoundEnded(e)
        debugLog("[ONRE-EXIT] round=" & $e.roundNumber & " tid=" & $getThreadId())
      of "GameEndedEventForBot":
        setRunning(false)
        let e = node.to(GameEndedEventForBot)
        signalStop()         # unblock bot thread if mid-round
        waitForBotThread()   # wait for round loop to finish
        drainTickChan()
        drainIntentChan()
        drainEventChan()
        gBot.onGameEnded(e)
      of "GameAbortedEvent":
        setRunning(false)
        signalStop()         # unblock bot thread (game aborted mid-round)
        waitForBotThread()   # wait for round loop to finish
        drainTickChan()      # drain stop signal if bot exited via isRunning() check
        drainIntentChan()    # drain while bot is idle — no more writes this round
        drainEventChan()     # drop any unconsumed tick events
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
  gBot = bot
  gBotInfo = loadBotInfo(jsonFile)
  initGlobals()

  let serverUrl    = getEnv("SERVER_URL", "ws://localhost:7654")
  let serverSecret = getEnv("SERVER_SECRET", "")

  try:
    gWs = newSyncWebSocket(serverUrl)
  except Exception as e:
    stderr.writeLine "[start] Cannot connect to " & serverUrl & ": " & e.msg
    quit(1)

  bot.onConnected(ConnectedEvent(serverUrl: serverUrl))
  startSenderThread()
  runReceiveLoop(gWs, gBotInfo, serverSecret, serverUrl)
  stopSenderThread()
