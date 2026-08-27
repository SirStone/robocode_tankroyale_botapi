## Main entry-point module for Robocode Tank Royale Nim bot API.
##
## Usage:
##   import robocode_tankroyale_botapi
##
##   type MyBot = ref object of Bot
##   method run(bot: MyBot) =
##     forward(100)
##     ...
##
##   var bot = MyBot()
##   start(bot, "MyBot.json")

import std/[os, json]

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

proc runReceiveLoop*(ws: SyncWebSocket; info: BotInfo; secret: string; serverUrl: string) =
  ## Main WebSocket receive loop. Blocks until disconnected.
  while ws.connected:
    var msg: string
    try:
      msg = ws.receive()
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
        discard  # unknown message type — ignore
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

proc start*(bot: Bot; jsonFile: string = "") =
  ## Connect to the server and start the bot.
  ## jsonFile: path to bot JSON profile (optional; falls back to env vars).
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
