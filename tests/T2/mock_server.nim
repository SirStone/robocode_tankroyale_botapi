## Mock WebSocket server for Tier 2 bot API testing.
##
## Replicates the Robocode Tank Royale server's protocol so tests can exercise
## the full bot lifecycle without a real Java server.
##
## Threading model:
##   Caller thread  — creates MockServer, calls awaitBotHandshake / sendTick / etc.
##   Server thread  — runs the accept + message loop (asyncdispatch).
##
## Synchronisation via stdlib Channels (allocated on heap via `create`):
##   handshakeChan  server → caller: BotHandshake received
##   readyChan      server → caller: BotReady received
##   intentChan     server → caller: BotIntent JSON received
##   outboundChan   caller → server: JSON strings to send to the bot

import std/[asyncdispatch, asyncnet, base64, json, net, os, strutils, times]
{.push warning[Deprecated]: off.}
import std/sha1
{.pop.}

# ---------------------------------------------------------------------------
# Public types
# ---------------------------------------------------------------------------

type
  MockBotHandshake* = object
    sessionId*:  string
    name*:       string
    version*:    string
    authors*:    seq[string]
    isDroid*:    bool

  MockBotIntent* = object
    turnRate*:      float
    gunTurnRate*:   float
    radarTurnRate*: float
    targetSpeed*:   float
    firepower*:     float

  MockTickState* = object
    ## Configurable per-tick bot state delivered in TickEventForBot.
    energy*:         float
    x*:              float
    y*:              float
    direction*:      float
    gunDirection*:   float
    radarDirection*: float
    speed*:          float
    gunHeat*:        float
    enemyCount*:     int

  # Internal context — heap-allocated so channels + port have a stable address
  # across thread boundaries (Channel must not be moved after open()).
  MockCtx = object
    port:          int
    sessionId:     string
    handshakeChan: Channel[MockBotHandshake]
    readyChan:     Channel[bool]
    intentChan:    Channel[string]
    outboundChan:  Channel[string]
    stopChan:      Channel[bool]

  MockServer* = object
    port*:          int
    lastHandshake*: MockBotHandshake
    ctx:            ptr MockCtx
    thread:         Thread[ptr MockCtx]

# ---------------------------------------------------------------------------
# WebSocket server helpers (raw framing — mirrors ws_client.nim server-side)
# ---------------------------------------------------------------------------

proc wsAcceptKey(clientKey: string): string =
  ## Compute Sec-WebSocket-Accept value per RFC 6455.
  let magic = "258EAFA5-E914-47DA-95CA-C5AB0DC85B11"
  base64.encode($secureHash(clientKey & magic))

proc sendFrame(sock: AsyncSocket; payload: string) {.async.} =
  ## Send an unmasked text frame (server→client; server MUST NOT mask).
  var frame = ""
  frame.add(char(0x81))  # FIN + opcode=text
  let plen = payload.len
  if plen <= 125:
    frame.add(char(plen))
  elif plen <= 65535:
    frame.add(char(126))
    frame.add(char((plen shr 8) and 0xFF))
    frame.add(char(plen and 0xFF))
  else:
    frame.add(char(127))
    for shift in [56, 48, 40, 32, 24, 16, 8, 0]:
      frame.add(char((plen shr shift) and 0xFF))
  frame.add(payload)
  await sock.send(frame)

proc recvFrame(sock: AsyncSocket): Future[string] {.async.} =
  ## Read one complete WebSocket frame (client sends masked frames).
  while true:
    let h = await sock.recv(2)
    if h.len < 2: return ""
    let opcode = uint8(h[0]) and 0x0F
    let masked  = (uint8(h[1]) and 0x80) != 0
    var plen    = int(uint8(h[1]) and 0x7F)

    if plen == 126:
      let ext = await sock.recv(2)
      if ext.len < 2: return ""
      plen = int(uint8(ext[0])) shl 8 or int(uint8(ext[1]))
    elif plen == 127:
      let ext = await sock.recv(8)
      if ext.len < 8: return ""
      plen = 0
      for ch in ext: plen = (plen shl 8) or int(uint8(ch))

    var maskKey: array[4, uint8]
    if masked:
      let mk = await sock.recv(4)
      if mk.len < 4: return ""
      for i in 0..3: maskKey[i] = uint8(mk[i])

    var payload = if plen > 0: (await sock.recv(plen)) else: ""
    if masked:
      for i in 0 ..< payload.len:
        payload[i] = char(uint8(payload[i]) xor maskKey[i mod 4])

    case opcode
    of 0x8: return ""   # close
    of 0x9:             # ping → pong
      await sock.send(char(0x8A) & char(plen) & payload)
      continue
    of 0xA: continue    # pong — ignore
    else: return payload

proc doHttpUpgrade(sock: AsyncSocket): Future[bool] {.async.} =
  ## Read the HTTP upgrade request and respond with 101.
  var clientKey = ""
  while true:
    let line = await sock.recvLine()
    if line == "\r\n" or line == "": break
    let parts = line.strip().split(": ", 1)
    if parts.len == 2 and parts[0].toLowerAscii == "sec-websocket-key":
      clientKey = parts[1].strip()
  if clientKey.len == 0: return false
  let accept = wsAcceptKey(clientKey)
  await sock.send(
    "HTTP/1.1 101 Switching Protocols\r\n" &
    "Upgrade: websocket\r\n" &
    "Connection: Upgrade\r\n" &
    "Sec-WebSocket-Accept: " & accept & "\r\n\r\n"
  )
  return true

# ---------------------------------------------------------------------------
# JSON builders (server → bot)
# ---------------------------------------------------------------------------

proc serverHandshakeJson(sessionId: string): string =
  $(%*{
    "type":      "ServerHandshake",
    "sessionId": sessionId,
    "name":      "MockServer",
    "version":   "0.0.1",
    "variant":   "Tank Royale",
    "gameTypes": ["classic"]
  })

proc gameStartedJson(myId: int; sessionId: string): string =
  $(%*{
    "type":           "GameStartedEventForBot",
    "myId":           myId,
    "startX":         100.0,
    "startY":         100.0,
    "startDirection": 0.0,
    "teammateIds":    newJArray(),
    "gameSetup": {
      "gameType":                        "classic",
      "arenaWidth":                      800,
      "isArenaWidthLocked":              false,
      "arenaHeight":                     600,
      "isArenaHeightLocked":             false,
      "minNumberOfParticipants":         2,
      "isMinNumberOfParticipantsLocked": false,
      "maxNumberOfParticipants":         10,
      "isMaxNumberOfParticipantsLocked": false,
      "numberOfRounds":                  10,
      "isNumberOfRoundsLocked":          false,
      "gunCoolingRate":                  0.1,
      "isGunCoolingRateLocked":          false,
      "maxInactivityTurns":              450,
      "isMaxInactivityTurnsLocked":      false,
      "turnTimeout":                     30000,
      "isTurnTimeoutLocked":             false,
      "readyTimeout":                    1000000,
      "isReadyTimeoutLocked":            false,
      "defaultTurnsPerSecond":           30
    }
  })

proc roundStartedJson(roundNumber: int): string =
  $(%*{"type": "RoundStartedEvent", "roundNumber": roundNumber})

proc tickJson(roundNumber, turnNumber: int; state: MockTickState;
              extraEvents: JsonNode = nil): string =
  var obj = %*{
    "type":        "TickEventForBot",
    "turnNumber":  turnNumber,
    "roundNumber": roundNumber,
    "botState": {
      "isDroid":        false,
      "energy":         state.energy,
      "x":              state.x,
      "y":              state.y,
      "direction":      state.direction,
      "gunDirection":   state.gunDirection,
      "radarDirection": state.radarDirection,
      "radarSweep":     0.0,
      "speed":          state.speed,
      "turnRate":       0.0,
      "gunTurnRate":    0.0,
      "radarTurnRate":  0.0,
      "gunHeat":        state.gunHeat,
      "enemyCount":     state.enemyCount
    },
    "bulletStates": newJArray(),
    "events":       newJArray()
  }
  if not extraEvents.isNil and extraEvents.kind == JArray:
    obj["events"] = extraEvents
  $obj

proc roundEndedJson(roundNumber, turnNumber: int): string =
  $(%*{
    "type":        "RoundEndedEventForBot",
    "roundNumber": roundNumber,
    "turnNumber":  turnNumber,
    "results": {
      "rank": 1, "survival": 0, "lastSurvivorBonus": 0,
      "bulletDamage": 0, "bulletKillBonus": 0,
      "ramDamage": 0, "ramKillBonus": 0,
      "totalScore": 0, "firstPlaces": 0, "secondPlaces": 0, "thirdPlaces": 0
    }
  })

proc gameEndedJson(numberOfRounds: int): string =
  $(%*{
    "type":           "GameEndedEventForBot",
    "numberOfRounds": numberOfRounds,
    "results": {
      "rank": 1, "survival": 0, "lastSurvivorBonus": 0,
      "bulletDamage": 0, "bulletKillBonus": 0,
      "ramDamage": 0, "ramKillBonus": 0,
      "totalScore": 0, "firstPlaces": 0, "secondPlaces": 0, "thirdPlaces": 0
    }
  })

# ---------------------------------------------------------------------------
# Server async loop (runs in server thread)
# ---------------------------------------------------------------------------

proc parseHandshake(node: JsonNode): MockBotHandshake =
  result.sessionId = node{"sessionId"}.getStr
  result.name      = node{"name"}.getStr
  result.version   = node{"version"}.getStr
  result.isDroid   = node{"isDroid"}.getBool(false)
  if not node{"authors"}.isNil and node["authors"].kind == JArray:
    for a in node["authors"]: result.authors.add a.getStr

proc parseIntent(node: JsonNode): MockBotIntent =
  result.turnRate      = node{"turnRate"}.getFloat(0.0)
  result.gunTurnRate   = node{"gunTurnRate"}.getFloat(0.0)
  result.radarTurnRate = node{"radarTurnRate"}.getFloat(0.0)
  result.targetSpeed   = node{"targetSpeed"}.getFloat(0.0)
  result.firepower     = node{"firepower"}.getFloat(0.0)

proc clientLoop(ctx: ptr MockCtx; sock: AsyncSocket) {.async.} =
  if not (await doHttpUpgrade(sock)): return

  # Send ServerHandshake
  await sock.sendFrame(serverHandshakeJson(ctx.sessionId))

  # Drain any queued outbound messages and handle inbound — interleaved.
  # Strategy: start a recv future, then poll every 10ms; drain outbound while waiting.
  # ponytail: single-client model; extend to multi-client list if needed
  var recvFut: Future[string] = sock.recvFrame()

  while true:
    # Drain all pending outbound messages before sleeping
    while true:
      let (hasOut, outMsg) = ctx.outboundChan.tryRecv()
      if not hasOut: break
      if outMsg.len == 0:
        sock.close()  # force EOF on bot side so its recv fails immediately
        return  # stop sentinel
      await sock.sendFrame(outMsg)

    # Check stop signal
    let (hasStop, _) = ctx.stopChan.tryRecv()
    if hasStop: break

    # If inbound frame is ready, process it and start the next recv
    if recvFut.finished:
      let msg = recvFut.read()
      if msg.len == 0: break
      recvFut = sock.recvFrame()  # start next recv immediately

      var node: JsonNode
      try: node = parseJson(msg)
      except: continue

      case node{"type"}.getStr
      of "BotHandshake": ctx.handshakeChan.send(parseHandshake(node))
      of "BotReady":     ctx.readyChan.send(true)
      of "BotIntent":    ctx.intentChan.send(msg)
      else: discard
    else:
      await sleepAsync(10)

proc serverThread(ctx: ptr MockCtx) {.thread.} =
  {.cast(gcsafe).}:
    var server = newAsyncSocket()
    server.setSockOpt(OptReuseAddr, true)
    server.bindAddr(Port(ctx.port))
    server.listen()

    proc doAccept() {.async.} =
      let (_, client) = await server.acceptAddr()
      asyncCheck clientLoop(ctx, client)

    asyncCheck doAccept()

    while true:
      let (hasStop, _) = ctx.stopChan.tryRecv()
      if hasStop: break
      poll(10)

    server.close()

# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------

proc startMockServer*(port: int = 0): MockServer =
  ## Start the mock server. Pass port=0 for an OS-assigned free port.
  ## The actual listening port is in result.port.
  let ctx = create(MockCtx)
  ctx.sessionId = "mock-session-001"

  if port == 0:
    # Probe for a free port then release it; the server thread will re-bind.
    # ponytail: tiny TOCTOU window — accept if port contention matters in CI
    let probe = newSocket()
    probe.setSockOpt(OptReuseAddr, true)
    probe.bindAddr(Port(0))
    let (_, p) = probe.getLocalAddr()
    ctx.port = p.int
    probe.close()
  else:
    ctx.port = port

  ctx.handshakeChan.open(4)
  ctx.readyChan.open(4)
  ctx.intentChan.open(64)
  ctx.outboundChan.open(128)
  ctx.stopChan.open(4)

  result.port = ctx.port
  result.ctx  = ctx
  createThread(result.thread, serverThread, ctx)
  sleep(50)  # let server thread bind + listen

proc awaitBotHandshake*(srv: var MockServer; timeoutMs: int = 5000): MockBotHandshake =
  ## Block until BotHandshake received or timeout (raises ValueError on timeout).
  let deadline = epochTime() + timeoutMs.float / 1000.0
  while epochTime() < deadline:
    let (ok, hs) = srv.ctx.handshakeChan.tryRecv()
    if ok:
      srv.lastHandshake = hs
      return hs
    sleep(10)
  raise newException(ValueError, "awaitBotHandshake: timeout after " & $timeoutMs & "ms")

proc awaitBotReady*(srv: var MockServer; timeoutMs: int = 5000) =
  ## Block until BotReady received or timeout.
  let deadline = epochTime() + timeoutMs.float / 1000.0
  while epochTime() < deadline:
    let (ok, _) = srv.ctx.readyChan.tryRecv()
    if ok: return
    sleep(10)
  raise newException(ValueError, "awaitBotReady: timeout after " & $timeoutMs & "ms")

proc awaitBotIntent*(srv: var MockServer; timeoutMs: int = 5000): MockBotIntent =
  ## Block until BotIntent received or timeout. Returns parsed intent.
  let deadline = epochTime() + timeoutMs.float / 1000.0
  while epochTime() < deadline:
    let (ok, raw) = srv.ctx.intentChan.tryRecv()
    if ok: return parseIntent(parseJson(raw))
    sleep(10)
  raise newException(ValueError, "awaitBotIntent: timeout after " & $timeoutMs & "ms")

proc awaitBotIntentRaw*(srv: var MockServer; timeoutMs: int = 5000): string =
  ## Block until BotIntent received or timeout. Returns raw JSON.
  let deadline = epochTime() + timeoutMs.float / 1000.0
  while epochTime() < deadline:
    let (ok, raw) = srv.ctx.intentChan.tryRecv()
    if ok: return raw
    sleep(10)
  raise newException(ValueError, "awaitBotIntentRaw: timeout after " & $timeoutMs & "ms")

proc sendGameStarted*(srv: MockServer; myId: int = 1) =
  srv.ctx.outboundChan.send(gameStartedJson(myId, srv.ctx.sessionId))

proc sendRoundStarted*(srv: MockServer; roundNumber: int = 1) =
  srv.ctx.outboundChan.send(roundStartedJson(roundNumber))

proc sendTick*(srv: MockServer; roundNumber, turnNumber: int;
               state: MockTickState; extraEvents: JsonNode = nil) =
  srv.ctx.outboundChan.send(tickJson(roundNumber, turnNumber, state, extraEvents))

proc sendRoundEnded*(srv: MockServer; roundNumber: int = 1; turnNumber: int = 1) =
  srv.ctx.outboundChan.send(roundEndedJson(roundNumber, turnNumber))

proc sendGameEnded*(srv: MockServer; numberOfRounds: int = 1) =
  srv.ctx.outboundChan.send(gameEndedJson(numberOfRounds))

proc sendRaw*(srv: MockServer; json: string) =
  ## Inject any raw JSON (for unknown-type / error-path testing).
  srv.ctx.outboundChan.send(json)

proc stopMockServer*(srv: var MockServer) =
  srv.ctx.outboundChan.send("")  # sentinel → break client loop
  srv.ctx.stopChan.send(true)    # break server accept loop
  joinThread(srv.thread)
  srv.ctx.handshakeChan.close()
  srv.ctx.readyChan.close()
  srv.ctx.intentChan.close()
  srv.ctx.outboundChan.close()
  srv.ctx.stopChan.close()
  dealloc(srv.ctx)
  srv.ctx = nil

proc wsUrl*(srv: MockServer): string =
  "ws://127.0.0.1:" & $srv.port

# ---------------------------------------------------------------------------
# Self-test (nim c -r tests/mock_server.nim)
# ---------------------------------------------------------------------------

when isMainModule:
  ## Inline helpers to avoid import-path issues when run directly from tests/.

  proc encodeClientFrame(payload: string): string =
    ## Masked client→server text frame (deterministic mask for test simplicity).
    var frame = ""
    frame.add(char(0x81))
    let plen = payload.len
    let maskKey = [uint8(0xAB), uint8(0xCD), uint8(0xEF), uint8(0x01)]
    if plen <= 125:
      frame.add(char(0x80 or plen))
    else:
      frame.add(char(0x80 or 126))
      frame.add(char((plen shr 8) and 0xFF))
      frame.add(char(plen and 0xFF))
    for b in maskKey: frame.add(char(b))
    for i, c in payload:
      frame.add(char(uint8(c) xor maskKey[i mod 4]))
    result = frame

  proc recvServerFrame(sock: Socket): string =
    ## Read one unmasked server→client text frame.
    var header: array[2, uint8]
    discard sock.recv(addr header[0], 2, 5000)
    var plen = int(header[1] and 0x7F)
    if plen == 126:
      var ext: array[2, uint8]
      discard sock.recv(addr ext[0], 2, 5000)
      plen = int(ext[0]) shl 8 or int(ext[1])
    var payload = newString(plen)
    if plen > 0: discard sock.recv(addr payload[0], plen, 5000)
    result = payload

  echo "Starting mock server self-test..."
  var srv = startMockServer()
  echo "Server listening on port " & $srv.port

  let sock = newSocket()
  sock.connect("127.0.0.1", Port(srv.port))

  let key = base64.encode("0123456789abcdef")
  sock.send(
    "GET / HTTP/1.1\r\n" &
    "Host: 127.0.0.1:" & $srv.port & "\r\n" &
    "Upgrade: websocket\r\n" &
    "Connection: Upgrade\r\n" &
    "Sec-WebSocket-Key: " & key & "\r\n" &
    "Sec-WebSocket-Version: 13\r\n\r\n"
  )

  var upgraded = false
  while true:
    let line = sock.recvLine()
    if line == "\r\n" or line == "": break
    if line.startsWith("HTTP/1.1 101"): upgraded = true
  assert upgraded, "WebSocket upgrade failed"
  echo "WS upgrade OK"

  let serverMsg = recvServerFrame(sock)
  let hsNode = parseJson(serverMsg)
  assert hsNode{"type"}.getStr == "ServerHandshake",
    "expected ServerHandshake, got: " & serverMsg
  echo "ServerHandshake received: sessionId=" & hsNode{"sessionId"}.getStr

  sock.send(encodeClientFrame(
    """{"type":"BotHandshake","sessionId":"mock-session-001","name":"TestBot","version":"1.0","authors":["Tester"],"isDroid":false}"""
  ))

  let captured = srv.awaitBotHandshake(timeoutMs = 2000)
  assert captured.name == "TestBot", "expected TestBot, got: " & captured.name
  echo "BotHandshake captured: name=" & captured.name

  srv.sendGameStarted(myId = 42)
  let gameStartMsg = recvServerFrame(sock)
  assert parseJson(gameStartMsg){"type"}.getStr == "GameStartedEventForBot"
  echo "GameStartedEventForBot received by client"

  sock.send(encodeClientFrame("""{"type":"BotReady"}"""))
  srv.awaitBotReady(timeoutMs = 2000)
  echo "BotReady captured"

  let st = MockTickState(energy: 100.0, x: 200.0, y: 300.0, direction: 45.0,
                         gunDirection: 45.0, radarDirection: 45.0, speed: 2.0,
                         gunHeat: 0.0, enemyCount: 1)
  srv.sendTick(1, 1, st)
  let tickMsg = recvServerFrame(sock)
  let tickNode = parseJson(tickMsg)
  assert tickNode{"type"}.getStr == "TickEventForBot"
  echo "TickEventForBot received, turn=" & $tickNode{"turnNumber"}.getInt

  sock.send(encodeClientFrame(
    """{"type":"BotIntent","turnRate":5.0,"gunTurnRate":0.0,"radarTurnRate":10.0,"targetSpeed":3.0,"firepower":0.0}"""
  ))
  let intent = srv.awaitBotIntent(timeoutMs = 2000)
  assert intent.turnRate == 5.0, "expected turnRate=5.0, got " & $intent.turnRate
  echo "BotIntent captured: turnRate=" & $intent.turnRate

  sock.close()
  stopMockServer(srv)
  echo "Self-test PASSED."
