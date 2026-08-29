## Minimal synchronous WebSocket client for Robocode Tank Royale bot API.
##
## This is an internal module implementing a light-weight synchronous (blocking)
## WebSocket client protocol over standard TCP sockets (`std/net`).
##
## ## Features
##
## - Simple HTTP 101 WebSocket Upgrade handshake
## - Client-side masking (RFC 6455 compliant)
## - Text frame encoding and decoding
## - Automatic Ping/Pong frame handling
## - Configurable per-read socket timeout (`WS_RECV_TIMEOUT_MS`)

import std/[net, base64, random, strutils, uri]

const WS_RECV_TIMEOUT_MS* = 30_000  ## Socket read timeout in milliseconds (default 30s).

type
  SyncWebSocket* = ref object
    ## Encapsulates a synchronous WebSocket connection.
    socket*:    Socket   ## Underlying OS socket handle
    connected*: bool     ## Connection status flag

  WebSocketError* = object of IOError
    ## Raised when a WebSocket protocol or network error occurs.

# ---- WebSocket frame helpers -------------------------------------------------

proc genKey(): string =
  var raw = newString(16)
  for i in 0 ..< 16:
    raw[i] = char(rand(255))
  base64.encode(raw)

proc encodeTextFrame*(payload: string, masked: bool = true): string =
  ## Encode a WebSocket text frame (opcode 0x1, FIN=1).
  ## Clients MUST mask frames.
  var frame = ""
  frame.add(char(0x81))  # FIN + opcode=text

  let plen = payload.len
  var maskKey: array[4, uint8]
  if masked:
    for i in 0 ..< 4: maskKey[i] = uint8(rand(255))

  if plen <= 125:
    frame.add(char(if masked: 0x80 or plen else: plen))
  elif plen <= 65535:
    frame.add(char(if masked: 0x80 or 126 else: 126))
    frame.add(char((plen shr 8) and 0xFF))
    frame.add(char(plen and 0xFF))
  else:
    frame.add(char(if masked: 0x80 or 127 else: 127))
    for shift in [56, 48, 40, 32, 24, 16, 8, 0]:
      frame.add(char((plen shr shift) and 0xFF))

  if masked:
    for b in maskKey: frame.add(char(b))
    for i, c in payload:
      frame.add(char(uint8(c) xor maskKey[i mod 4]))
  else:
    frame.add(payload)

  result = frame

proc decodeFrameTimeout*(socket: Socket, timeoutMs: int): string =
  ## Like decodeFrame but with an explicit per-read timeout.
  ## Returns "" on close frame. Raises TimeoutError on timeout, WebSocketError on hard fail.
  while true:
    var header: array[2, uint8]
    discard socket.recv(addr header[0], 2, timeoutMs)
    let fin    = (header[0] and 0x80) != 0
    let opcode = header[0] and 0x0F
    let masked = (header[1] and 0x80) != 0
    var plen   = int(header[1] and 0x7F)

    if plen == 126:
      var ext: array[2, uint8]
      discard socket.recv(addr ext[0], 2, timeoutMs)
      plen = int(ext[0]) shl 8 or int(ext[1])
    elif plen == 127:
      var ext: array[8, uint8]
      discard socket.recv(addr ext[0], 8, timeoutMs)
      plen = 0
      for b in ext: plen = (plen shl 8) or int(b)

    var maskKey: array[4, uint8]
    if masked:
      discard socket.recv(addr maskKey[0], 4, timeoutMs)

    var payload = newString(plen)
    if plen > 0:
      discard socket.recv(addr payload[0], plen, timeoutMs)

    if masked:
      for i in 0 ..< plen:
        payload[i] = char(uint8(payload[i]) xor maskKey[i mod 4])

    case opcode
    of 0x8:  # close
      result = ""
      return
    of 0x9:  # ping — send pong
      let pong = char(0x8A) & char(plen) & payload
      socket.send(pong)
      continue
    of 0xA:  # pong — ignore
      continue
    else:
      if not fin:
        raise newException(WebSocketError, "Fragmented frames not supported")
      result = payload
      return

proc decodeFrame*(socket: Socket): string =
  ## Read one complete WebSocket frame from the socket and return the payload.
  ## Handles text frames; pings are responded to automatically.
  ## Raises TimeoutError (from std/net) if no data arrives within WS_RECV_TIMEOUT_MS.
  while true:
    var header: array[2, uint8]
    discard socket.recv(addr header[0], 2, WS_RECV_TIMEOUT_MS)
    let fin    = (header[0] and 0x80) != 0
    let opcode = header[0] and 0x0F
    let masked = (header[1] and 0x80) != 0
    var plen   = int(header[1] and 0x7F)

    if plen == 126:
      var ext: array[2, uint8]
      discard socket.recv(addr ext[0], 2, WS_RECV_TIMEOUT_MS)
      plen = int(ext[0]) shl 8 or int(ext[1])
    elif plen == 127:
      var ext: array[8, uint8]
      discard socket.recv(addr ext[0], 8, WS_RECV_TIMEOUT_MS)
      plen = 0
      for b in ext: plen = (plen shl 8) or int(b)

    var maskKey: array[4, uint8]
    if masked:
      discard socket.recv(addr maskKey[0], 4, WS_RECV_TIMEOUT_MS)

    var payload = newString(plen)
    if plen > 0:
      discard socket.recv(addr payload[0], plen, WS_RECV_TIMEOUT_MS)

    if masked:
      for i in 0 ..< plen:
        payload[i] = char(uint8(payload[i]) xor maskKey[i mod 4])

    case opcode
    of 0x8:  # close
      result = ""
      return
    of 0x9:  # ping — send pong
      let pong = char(0x8A) & char(plen) & payload
      socket.send(pong)
      continue
    of 0xA:  # pong — ignore
      continue
    else:
      if not fin:
        raise newException(WebSocketError, "Fragmented frames not supported")
      result = payload
      return

# ---- Public API --------------------------------------------------------------

proc newSyncWebSocket*(url: string): SyncWebSocket =
  ## Connect to a WebSocket server. url must be ws:// or wss://.
  randomize()
  let u   = parseUri(url)
  let host = u.hostname
  let port = if u.port == "": "7654" else: u.port
  let path = if u.path == "": "/" else: u.path

  let sock = newSocket()
  sock.connect(host, Port(parseInt(port)))

  # HTTP upgrade handshake
  let key = genKey()
  let request = "GET " & path & " HTTP/1.1\r\n" &
    "Host: " & host & ":" & port & "\r\n" &
    "Upgrade: websocket\r\n" &
    "Connection: Upgrade\r\n" &
    "Sec-WebSocket-Key: " & key & "\r\n" &
    "Sec-WebSocket-Version: 13\r\n\r\n"
  sock.send(request)

  # Read HTTP 101 response
  var line = ""
  var upgraded = false
  while true:
    line = sock.recvLine()
    if line == "\r\n" or line == "":
      break
    if line.startsWith("HTTP/1.1 101"):
      upgraded = true

  if not upgraded:
    raise newException(WebSocketError, "WebSocket upgrade failed for " & url)

  result = SyncWebSocket(socket: sock, connected: true)

proc send*(ws: SyncWebSocket, text: string) =
  ## Send a text message (masked, as required for clients).
  if not ws.connected:
    raise newException(WebSocketError, "WebSocket is not connected")
  let frame = encodeTextFrame(text, masked = true)
  ws.socket.send(frame)

proc receive*(ws: SyncWebSocket): string =
  ## Block until a text message arrives. Returns "" on close.
  ## Raises TimeoutError if no data arrives within WS_RECV_TIMEOUT_MS (caller should retry).
  ## Raises WebSocketError on hard socket failure (caller should disconnect).
  if not ws.connected:
    return ""
  try:
    result = decodeFrame(ws.socket)
  except TimeoutError:
    raise  # let caller decide: retry vs disconnect
  except Exception as e:
    ws.connected = false
    raise newException(WebSocketError, "Receive failed: " & e.msg)

proc receiveWithTimeout*(ws: SyncWebSocket, timeoutMs: int): tuple[timedOut: bool, msg: string] =
  ## Try to receive one frame with the given timeout.
  ## Returns (timedOut=true, msg="") on timeout; (false, msg) on success; (false, "") on close.
  ## Pings inside decodeFrameTimeout are answered automatically.
  ## Raises WebSocketError on hard socket failure.
  if not ws.connected:
    return (false, "")
  try:
    result = (false, decodeFrameTimeout(ws.socket, timeoutMs))
  except TimeoutError:
    result = (true, "")
  except Exception as e:
    ws.connected = false
    raise newException(WebSocketError, "Receive failed: " & e.msg)

proc close*(ws: SyncWebSocket) =
  if ws.connected:
    ws.connected = false
    try:
      # Send close frame
      ws.socket.send(char(0x88) & char(0))
    except: discard
    ws.socket.close()
