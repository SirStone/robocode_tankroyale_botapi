## Core bot implementation for Robocode Tank Royale Nim bot API.
##
## Threading model
## ---------------
## Main thread:  WebSocket receive loop.  Receives all server messages,
##               updates shared state, runs processTurn, then wakes bot thread.
## Bot thread:   Wakes, dispatches events, runs user's `run()` / go() loop,
##               sends intent JSON via gIntentChan.
## Sender thread: Owns all WebSocket writes during gameplay — reads from
##               gIntentChan and calls ws.send.
##
## Synchronisation uses two channels:
##   tickChan     main → bot      (true = new tick ready; false = stop)
##   intentChan   bot  → sender   (JSON string to send to server; "" = stop)

import std/[json, locks, math, os, posix, syncio, tables]
import ./constants
import ./schemas
import ./color
import ./utils as botutils
import ./ws_client
import ./bot_info
import ./event_queue
import ./graphics

proc toInfiniteValue(rate: float): float {.inline.} =
  if rate > 0.0: Inf
  elif rate < 0.0: NegInf
  else: 0.0

# ---------------------------------------------------------------------------
# Types
# ---------------------------------------------------------------------------

type
  Bot* = ref object of RootObj
    ## Override `run()` and event handler methods in your bot subtype.

  BotState* = object
    ## Snapshot of shared state, read by the bot thread.

# ---------------------------------------------------------------------------
# Global mutable state (module-level; single bot per process)
# ---------------------------------------------------------------------------

# WebSocket
var gWs*: SyncWebSocket

# Thread handles
var gBotThread:    Thread[void]
var gSenderThread: Thread[void]
var gFirstTickOfRound: bool  # main-thread only, no lock needed

# Channels  — must be opened before use
var gTickChan:   Channel[bool]     # main → bot: tick arrived (false = stop)
var gIntentChan: Channel[string]   # bot  → main: send this JSON

# Shared state protected by lock
var gLock: Lock
var gRunning    {.guard: gLock.}: bool
var gMyId       {.guard: gLock.}: int
var gRound      {.guard: gLock.}: int
var gTurn       {.guard: gLock.}: int
var gEnemyCount {.guard: gLock.}: int
var gState      {.guard: gLock.}: schemas.BotState
var gBullets    {.guard: gLock.}: seq[BulletState]
var gGameSetup  {.guard: gLock.}: GameSetup
var gTeammateIds{.guard: gLock.}: seq[int]
var gVariant    {.guard: gLock.}: string
var gServerVersion {.guard: gLock.}: string
var gBotNames      {.guard: gLock.}: Table[int, string]
# Events handed main -> bot thread. Channel move, NOT a locked shared seq:
# the old locked seq[BotEvent] copied GC'd payloads (strings/teamMessages)
# across threads on every tick -> refcount churn under ORC + --threads:on ->
# heap freeList corruption + SIGSEGV inside prepareSeqAddUninit at tps=-1
# (gdb-confirmed). Channels move ownership: zero cross-thread refcount traffic.
var gEventChan: Channel[seq[BotEvent]]

# Saved state for stop/resume
var gStopped:            bool
var gSavedTurnRate:      float
var gSavedGunTurnRate:   float
var gSavedRadarTurnRate: float
var gSavedTargetSpeed:   float

# Motion tracking (bot thread only)
var gDistanceRemaining:    float
var gTurnRemaining:        float
var gGunTurnRemaining:     float
var gRadarTurnRemaining:   float
var gPreviousDirection:     float
var gPreviousGunDirection:  float
var gPreviousRadarDirection: float
var gOverrideTurnRate:      bool
var gOverrideGunTurnRate:   bool
var gOverrideRadarTurnRate: bool
var gOverrideTargetSpeed:   bool
var gContinuousTurnRate:    float
var gContinuousGunTurnRate: float
var gContinuousRadarTurnRate: float
var gContinuousTargetSpeed: float
var gIsOverDriving:         bool

var gMaxSpeed        = MAX_SPEED
var gMaxTurnRate     = MAX_TURN_RATE
var gMaxGunTurnRate  = MAX_GUN_TURN_RATE
var gMaxRadarTurnRate = MAX_RADAR_TURN_RATE

# The bot instance (set by start())
var gBot*: Bot

var gEventQueue: EventQueue   # bot-thread-only, no lock needed
var gInterrupted: bool        # flag-based interruptibility (checked by blocking calls)

# BotInfo (set by start())
var gBotInfo*: BotInfo

# ---------------------------------------------------------------------------
# Safe readers (can be called from bot thread without lock in most cases
# because they read after the tick channel signal — happens-before is enough)
# ---------------------------------------------------------------------------

proc getMyId*(): int            = withLock(gLock): result = gMyId
proc getRound*(): int           = withLock(gLock): result = gRound
proc getTurn*(): int            = withLock(gLock): result = gTurn
proc getEnemyCount*(): int      = withLock(gLock): result = gEnemyCount
proc getEnergy*(): float        = withLock(gLock): result = gState.energy
proc getX*(): float             = withLock(gLock): result = gState.x
proc getY*(): float             = withLock(gLock): result = gState.y
proc getDirection*(): float     = withLock(gLock): result = gState.direction
proc getGunDirection*(): float  = withLock(gLock): result = gState.gunDirection
proc getRadarDirection*(): float= withLock(gLock): result = gState.radarDirection
proc getRadarSweep*(): float    = withLock(gLock): result = gState.radarSweep
proc getSpeed*(): float         = withLock(gLock): result = gState.speed
proc getTurnRate*(): float      = withLock(gLock): result = gState.turnRate
proc getGunTurnRate*(): float   = withLock(gLock): result = gState.gunTurnRate
proc getRadarTurnRate*(): float = withLock(gLock): result = gState.radarTurnRate
proc getGunHeat*(): float       = withLock(gLock): result = gState.gunHeat
proc getBodyColor*(): Color    = withLock(gLock): result = gState.bodyColor
proc getTurretColor*(): Color  = withLock(gLock): result = gState.turretColor
proc getRadarColor*(): Color   = withLock(gLock): result = gState.radarColor
proc getBulletColor*(): Color  = withLock(gLock): result = gState.bulletColor
proc getScanColor*(): Color    = withLock(gLock): result = gState.scanColor
proc getTracksColor*(): Color  = withLock(gLock): result = gState.tracksColor
proc getGunColor*(): Color     = withLock(gLock): result = gState.gunColor
proc getArenaWidth*(): int      = withLock(gLock): result = gGameSetup.arenaWidth
proc getArenaHeight*(): int     = withLock(gLock): result = gGameSetup.arenaHeight
proc getGameType*(): string     = withLock(gLock): result = gGameSetup.gameType
proc getNumberOfRounds*(): int  = withLock(gLock): result = gGameSetup.numberOfRounds
proc getGunCoolingRate*(): float= withLock(gLock): result = gGameSetup.gunCoolingRate
proc getMaxInactivityTurns*(): int = withLock(gLock): result = gGameSetup.maxInactivityTurns
proc getTurnTimeout*(): int     = withLock(gLock): result = gGameSetup.turnTimeout
proc getTimeLeft*(): int        = getTurnTimeout() # ponytail: returns turnTimeout as ceiling; precise impl needs tick timestamp + elapsed tracking
proc getVariant*(): string      = withLock(gLock): result = gVariant
proc getServerVersion*(): string= withLock(gLock): result = gServerVersion
proc isRunning*(): bool         = withLock(gLock): result = gRunning
proc isDroid*(): bool           = withLock(gLock): result = gState.isDroid
proc isDisabled*(): bool        = getEnergy() == 0.0
proc isStopped*(): bool         = gStopped
proc getBulletStates*(): seq[BulletState] = withLock(gLock): result = gBullets
proc getTeammateIds*(): seq[int]= withLock(gLock): result = gTeammateIds
proc isTeammate*(botId: int): bool =
  withLock(gLock): result = gTeammateIds.contains(botId)

proc getDistanceRemaining*(): float  = gDistanceRemaining
proc getTurnRemaining*(): float      = gTurnRemaining
proc getGunTurnRemaining*(): float   = gGunTurnRemaining
proc getRadarTurnRemaining*(): float = gRadarTurnRemaining

proc getBotName*(id: int): string =
  ## Lookup bot name by id from the last BotListUpdate. Returns "" if unknown.
  withLock(gLock): result = gBotNames.getOrDefault(id, "")

proc updateBotNames*(node: JsonNode) =
  ## Update the id → name table from a BotListUpdate message (full replacement).
  withLock(gLock):
    gBotNames.clear()
    if node.isNil: return
    let botsNode = node{"bots"}
    if botsNode.isNil or botsNode.kind != JArray: return
    for b in botsNode:
      let name = b{"name"}.getStr("")
      if name.len == 0: continue
      var id = -1
      if not b{"id"}.isNil:
        id = b{"id"}.getInt(-1)
      if id == -1 and not b{"botId"}.isNil:
        id = b{"botId"}.getInt(-1)
      if id == -1: continue
      gBotNames[id] = name

proc getMaxSpeed*(): float       = gMaxSpeed
proc getMaxTurnRate*(): float    = gMaxTurnRate
proc getMaxGunTurnRate*(): float = gMaxGunTurnRate
proc getMaxRadarTurnRate*(): float = gMaxRadarTurnRate

proc setMaxSpeed*(v: float)       = gMaxSpeed        = v.clamp(0, MAX_SPEED)
proc setMaxTurnRate*(v: float)    = gMaxTurnRate      = v.clamp(0, MAX_TURN_RATE)
proc setMaxGunTurnRate*(v: float) = gMaxGunTurnRate   = v.clamp(0, MAX_GUN_TURN_RATE)
proc setMaxRadarTurnRate*(v: float)= gMaxRadarTurnRate = v.clamp(0, MAX_RADAR_TURN_RATE)

# ---------------------------------------------------------------------------
# Intent building
# ---------------------------------------------------------------------------

# Intent fields (bot thread writes, main thread reads + clears)
var gIntentTurnRate:      float = 0.0
var gIntentGunTurnRate:   float = 0.0
var gIntentRadarTurnRate: float = 0.0
var gIntentTargetSpeed:   float = 0.0
var gIntentFirepower:     float = 0.0
var gIntentRescan:        bool  = false
var gIntentFireAssist:    bool  = false
var gIntentBodyColor:     Color = Color(0)
var gIntentTurretColor:   Color = Color(0)
var gIntentRadarColor:    Color = Color(0)
var gIntentBulletColor:   Color = Color(0)
var gIntentScanColor:     Color = Color(0)
var gIntentTracksColor:   Color = Color(0)
var gIntentGunColor:      Color = Color(0)
var gIntentAdjGunBody:    bool = false
var gIntentAdjRadarBody:  bool = false
var gIntentAdjRadarGun:   bool = false
# ponytail: static buffers instead of strings/seq. go()'s stop path returns
# before buildIntentJson clears these, so a round's last tick can leave heap
# blocks owned by the exiting bot thread -> the fresh next-round thread
# reallocs a dead allocator block (rawDealloc SIGSEGV). Static storage:
# no heap block crosses threads.
const INTENT_STDOUT_CAP = 4096
const INTENT_STDERR_CAP = 4096
const INTENT_MSG_CAP    = 16

var gIntentTeamMessages: array[INTENT_MSG_CAP, TeamMessage]
var gIntentTeamMsgsLen:  int
var gIntentStdOut:       array[INTENT_STDOUT_CAP, char]
var gIntentStdOutLen:    int
var gIntentStdErr:       array[INTENT_STDERR_CAP, char]
var gIntentStdErrLen:    int

proc buildIntentJson*(): string =
  ## Serialise current intent to JSON for sending to server.
  var obj = newJObject()
  obj["type"] = %"BotIntent"
  obj["turnRate"]      = %gIntentTurnRate
  obj["gunTurnRate"]   = %gIntentGunTurnRate
  obj["radarTurnRate"] = %gIntentRadarTurnRate
  obj["targetSpeed"]   = %gIntentTargetSpeed
  if gIntentFirepower > 0.0:
    obj["firepower"] = %gIntentFirepower
  if gIntentRescan:
    obj["rescan"] = %true
    gIntentRescan = false  # one-shot
  if gIntentFireAssist:
    obj["fireAssist"] = %true
  if gIntentAdjGunBody:
    obj["adjustGunForBodyTurn"] = %true
  if gIntentAdjRadarBody:
    obj["adjustRadarForBodyTurn"] = %true
  if gIntentAdjRadarGun:
    obj["adjustRadarForGunTurn"] = %true
  if gIntentBodyColor != Color(0):
    obj["bodyColor"]   = %gIntentBodyColor.toHex
  if gIntentTurretColor != Color(0):
    obj["turretColor"] = %gIntentTurretColor.toHex
  if gIntentRadarColor != Color(0):
    obj["radarColor"]  = %gIntentRadarColor.toHex
  if gIntentBulletColor != Color(0):
    obj["bulletColor"] = %gIntentBulletColor.toHex
  if gIntentScanColor != Color(0):
    obj["scanColor"]   = %gIntentScanColor.toHex
  if gIntentTracksColor != Color(0):
    obj["tracksColor"] = %gIntentTracksColor.toHex
  if gIntentGunColor != Color(0):
    obj["gunColor"]    = %gIntentGunColor.toHex
  if gIntentTeamMsgsLen > 0:
    var msgs = newJArray()
    for i in 0 ..< gIntentTeamMsgsLen:
      let m = gIntentTeamMessages[i]
      var mo = newJObject()
      mo["message"]     = %m.message
      mo["messageType"] = %m.messageType
      if m.receiverId != 0:
        mo["receiverId"] = %m.receiverId
      msgs.add mo
    obj["teamMessages"] = msgs
    for i in 0 ..< gIntentTeamMsgsLen: gIntentTeamMessages[i].reset
    gIntentTeamMsgsLen = 0
  if gIntentStdOutLen > 0:
    obj["stdOut"] = %($gIntentStdOut[0 ..< gIntentStdOutLen])
    gIntentStdOutLen = 0
  if gIntentStdErrLen > 0:
    obj["stdErr"] = %($gIntentStdErr[0 ..< gIntentStdErrLen])
    gIntentStdErrLen = 0
  let svg = svgOutput()
  if svg.len > 0:
    obj["debugGraphics"] = %svg
  result = $obj

# ---------------------------------------------------------------------------
# Intent setters (bot thread)
# ---------------------------------------------------------------------------

proc setTurnRate*(rate: float) =
  gIntentTurnRate = rate.clamp(-gMaxTurnRate, gMaxTurnRate)
  gOverrideTurnRate = false
  gContinuousTurnRate = rate
  gTurnRemaining = toInfiniteValue(rate)

proc setGunTurnRate*(rate: float) =
  gIntentGunTurnRate = rate.clamp(-gMaxGunTurnRate, gMaxGunTurnRate)
  gOverrideGunTurnRate = false
  gContinuousGunTurnRate = rate
  gGunTurnRemaining = toInfiniteValue(rate)

proc setRadarTurnRate*(rate: float) =
  gIntentRadarTurnRate = rate.clamp(-gMaxRadarTurnRate, gMaxRadarTurnRate)
  gOverrideRadarTurnRate = false
  gContinuousRadarTurnRate = rate
  gRadarTurnRemaining = toInfiniteValue(rate)

proc setTargetSpeed*(speed: float) =
  gIntentTargetSpeed = speed.clamp(-gMaxSpeed, gMaxSpeed)
  gOverrideTargetSpeed = false
  gContinuousTargetSpeed = speed
  if speed > 0:
    gDistanceRemaining = Inf
  elif speed < 0:
    gDistanceRemaining = NegInf
  else:
    gDistanceRemaining = 0.0

proc setFire*(firepower: float): bool =
  let fp = firepower.clamp(MIN_FIRE_POWER, MAX_FIRE_POWER)
  if getEnergy() < fp or getGunHeat() > 0.0:
    return false
  gIntentFirepower = fp
  return true

proc setRescan*() = gIntentRescan = true

proc setBodyColor*(color: Color)   = gIntentBodyColor   = color
proc setTurretColor*(color: Color) = gIntentTurretColor = color
proc setRadarColor*(color: Color)  = gIntentRadarColor  = color
proc setBulletColor*(color: Color) = gIntentBulletColor = color
proc setScanColor*(color: Color)   = gIntentScanColor   = color
proc setTracksColor*(color: Color) = gIntentTracksColor = color
proc setGunColor*(color: Color)    = gIntentGunColor    = color

proc printToStdOut*(s: string) =
  ## Append s to this tick's stdOut payload (sent to server in BotIntent).
  let n = min(s.len, INTENT_STDOUT_CAP - gIntentStdOutLen)
  for i in 0 ..< n: gIntentStdOut[gIntentStdOutLen + i] = s[i]
  inc gIntentStdOutLen, n

proc printToStdErr*(s: string) =
  ## Append s to this tick's stdErr payload (sent to server in BotIntent).
  let n = min(s.len, INTENT_STDERR_CAP - gIntentStdErrLen)
  for i in 0 ..< n: gIntentStdErr[gIntentStdErrLen + i] = s[i]
  inc gIntentStdErrLen, n

proc broadcastTeamMessage*(message: string) =
  ## Send a message to all teammates this tick.
  if gIntentTeamMsgsLen < INTENT_MSG_CAP:
    gIntentTeamMessages[gIntentTeamMsgsLen] = TeamMessage(message: message, messageType: "String")
    inc gIntentTeamMsgsLen

proc sendTeamMessage*(botId: int; message: string) =
  ## Send a message to a specific teammate this tick.
  if gIntentTeamMsgsLen < INTENT_MSG_CAP:
    gIntentTeamMessages[gIntentTeamMsgsLen] = TeamMessage(message: message, messageType: "String", receiverId: botId)
    inc gIntentTeamMsgsLen

proc setAdjustGunForBodyTurn*(v: bool)   = gIntentAdjGunBody   = v
proc setAdjustRadarForBodyTurn*(v: bool) = gIntentAdjRadarBody = v
proc setFireAssist*(enable: bool) = gIntentFireAssist = enable
proc setAdjustRadarForGunTurn*(v: bool)  =
  gIntentAdjRadarGun = v
  setFireAssist(not v)

proc isAdjustGunForBodyTurn*(): bool    = gIntentAdjGunBody
proc isAdjustRadarForBodyTurn*(): bool  = gIntentAdjRadarBody
proc isAdjustRadarForGunTurn*(): bool   = gIntentAdjRadarGun

proc getTargetSpeed*(): float = gIntentTargetSpeed
proc getFirepower*(): float   = gIntentFirepower

# Convenience math re-exports (state-aware wrappers; pure-math helpers come from utils)
proc calcBearing*(direction: float): float = botutils.calcDeltaAngle(direction, getDirection())
proc calcGunBearing*(direction: float): float = botutils.calcDeltaAngle(direction, getGunDirection())
proc calcRadarBearing*(direction: float): float = botutils.calcDeltaAngle(direction, getRadarDirection())
proc bearingTo*(x, y: float): float = botutils.bearingTo(getX(), getY(), getDirection(), x, y)
proc gunBearingTo*(x, y: float): float = botutils.bearingTo(getX(), getY(), getGunDirection(), x, y)
proc radarBearingTo*(x, y: float): float = botutils.normalizeRelativeAngle(botutils.directionTo(getX(), getY(), x, y) - getRadarDirection())
proc directionTo*(x, y: float): float = botutils.directionTo(getX(), getY(), x, y)
proc distanceTo*(x, y: float): float  = botutils.distanceTo(getX(), getY(), x, y)

# ---------------------------------------------------------------------------
# Bot motion processing (called on first turn and each subsequent turn)
# NOTE: must be defined before go() so it can be called inside go()
# ---------------------------------------------------------------------------

var gDebugLog: File        # nil unless PPOB_DEBUG_LOG=1 (debug-only knob)
var gDebugLogBytes: int64  # written bytes since last truncation
const gDebugLogCap = 100 * 1024 * 1024  # 100 MB ceiling
const gDebugLogPath = "/tmp/walls_debug.log"

proc resetDebugLog() =
  ## Truncate the debug log to zero (Nim's stdlib has no File truncate, so do
  ## it by path via POSIX — the open fmAppend handle stays valid).
  discard truncate(gDebugLogPath, 0)
  gDebugLogBytes = 0

proc debugLog*(msg: string) =
  ## Debug tracing, only active when PPOB_DEBUG_LOG=1. Called from both the
  ## main and bot threads, so writes are serialized under gLock (File writes
  ## are not thread-safe); the log is truncated and restarted at the cap so a
  ## long campaign can't grow a GB-scale file again.
  if gDebugLog == nil: return
  withLock(gLock):
    if gDebugLogBytes >= gDebugLogCap:
      resetDebugLog()
    gDebugLog.writeLine(msg)
    gDebugLog.flushFile()
    gDebugLogBytes += int64(msg.len) + 1

proc clearRemaining*() =
  gDistanceRemaining  = 0.0
  gTurnRemaining      = 0.0
  gGunTurnRemaining   = 0.0
  gRadarTurnRemaining = 0.0
  gContinuousTurnRate      = 0.0
  gContinuousGunTurnRate   = 0.0
  gContinuousRadarTurnRate = 0.0
  gContinuousTargetSpeed   = 0.0
  # Reset override flags — prevents stale state carrying across rounds
  gOverrideTurnRate      = false
  gOverrideGunTurnRate   = false
  gOverrideRadarTurnRate = false
  gOverrideTargetSpeed   = false
  gIsOverDriving         = false
  # Reset intent values to zero for a clean slate each round
  gIntentTurnRate      = 0.0
  gIntentGunTurnRate   = 0.0
  gIntentRadarTurnRate = 0.0
  gIntentTargetSpeed   = 0.0
  # Reset stop/resume state — stale gStopped=true would hijack forward/turn calls
  gStopped            = false
  gSavedTurnRate      = 0.0
  gSavedGunTurnRate   = 0.0
  gSavedRadarTurnRate = 0.0
  gSavedTargetSpeed   = 0.0
  # Reset prevDir to current tick values — prevents wrong delta on first processTurn
  gPreviousDirection      = getDirection()
  gPreviousGunDirection   = getGunDirection()
  gPreviousRadarDirection = getRadarDirection()
  # Reset event queue state for new round
  gEventQueue.clear()
  gInterrupted = false

proc updateTurnRemaining() =
  let delta = calcDeltaAngle(getDirection(), gPreviousDirection)
  gPreviousDirection = getDirection()
  if not gOverrideTurnRate:
    gIntentTurnRate = gContinuousTurnRate.clamp(-gMaxTurnRate, gMaxTurnRate)
    return
  if abs(gTurnRemaining) <= abs(delta):
    gTurnRemaining = 0.0
  else:
    gTurnRemaining -= delta
    if isNearZero(gTurnRemaining): gTurnRemaining = 0.0
  gIntentTurnRate = gTurnRemaining.clamp(-gMaxTurnRate, gMaxTurnRate)

proc updateGunTurnRemaining() =
  let delta = calcDeltaAngle(getGunDirection(), gPreviousGunDirection)
  gPreviousGunDirection = getGunDirection()
  if not gOverrideGunTurnRate:
    gIntentGunTurnRate = gContinuousGunTurnRate.clamp(-gMaxGunTurnRate, gMaxGunTurnRate)
    return
  if abs(gGunTurnRemaining) <= abs(delta):
    gGunTurnRemaining = 0.0
  else:
    gGunTurnRemaining -= delta
    if isNearZero(gGunTurnRemaining): gGunTurnRemaining = 0.0
  gIntentGunTurnRate = gGunTurnRemaining.clamp(-gMaxGunTurnRate, gMaxGunTurnRate)

proc updateRadarTurnRemaining() =
  let delta = calcDeltaAngle(getRadarDirection(), gPreviousRadarDirection)
  gPreviousRadarDirection = getRadarDirection()
  if not gOverrideRadarTurnRate:
    gIntentRadarTurnRate = gContinuousRadarTurnRate.clamp(-gMaxRadarTurnRate, gMaxRadarTurnRate)
    return
  if abs(gRadarTurnRemaining) <= abs(delta):
    gRadarTurnRemaining = 0.0
  else:
    gRadarTurnRemaining -= delta
    if isNearZero(gRadarTurnRemaining): gRadarTurnRemaining = 0.0
  gIntentRadarTurnRate = gRadarTurnRemaining.clamp(-gMaxRadarTurnRate, gMaxRadarTurnRate)

proc updateMovement() =
  if not gOverrideTargetSpeed:
    gIntentTargetSpeed = gContinuousTargetSpeed.clamp(-gMaxSpeed, gMaxSpeed)
    if abs(gDistanceRemaining) < abs(getSpeed()):
      gDistanceRemaining = 0.0
    else:
      gDistanceRemaining -= getSpeed()
  elif gDistanceRemaining == Inf:
    gIntentTargetSpeed = gMaxSpeed
  elif gDistanceRemaining == NegInf:
    gIntentTargetSpeed = -gMaxSpeed
  else:
    let dist     = gDistanceRemaining
    let newSpeed = getNewTargetSpeed(gMaxSpeed, getSpeed(), dist)
    gIntentTargetSpeed = newSpeed.clamp(-gMaxSpeed, gMaxSpeed)

    if isNearZero(newSpeed) and gIsOverDriving:
      gDistanceRemaining = 0.0
      gIsOverDriving     = false
    else:
      if math.sgn(dist * newSpeed).float != -1.0:
        gIsOverDriving = getDistanceTraveledUntilStop(gMaxSpeed, newSpeed) > abs(dist)
      gDistanceRemaining = dist - newSpeed

proc processTurn*() =
  ## Update motion tracking at the start of each tick (called from go() and
  ## botThreadEntry after each tick signal).
  if isDisabled():
    clearRemaining()
  else:
    updateTurnRemaining()
    updateGunTurnRemaining()
    updateRadarTurnRemaining()
    updateMovement()

# ---------------------------------------------------------------------------
# Default event handlers (no-ops; override in your Bot subtype)
# NOTE: must be defined before dispatchEvent() below
# ---------------------------------------------------------------------------

method run*(bot: Bot)               {.base.} = discard
method onConnected*(bot: Bot, e: ConnectedEvent)       {.base.} = discard
method onDisconnected*(bot: Bot, e: DisconnectedEvent) {.base.} = discard
method onConnectionError*(bot: Bot, e: ConnectionErrorEvent) {.base.} = discard
method onGameStarted*(bot: Bot, e: GameStartedEventForBot) {.base.} = discard
method onGameEnded*(bot: Bot, e: GameEndedEventForBot)     {.base.} = discard
method onGameAborted*(bot: Bot)     {.base.} = discard
method onRoundStarted*(bot: Bot, e: RoundStartedEvent) {.base.} = discard
method onRoundEnded*(bot: Bot, e: RoundEndedEventForBot) {.base.} = discard
method onTick*(bot: Bot, e: TickEventForBot) {.base.} = discard
method onSkippedTurn*(bot: Bot, e: SkippedTurnEvent) {.base.} = discard
method onBotDeath*(bot: Bot, e: BotDeathEvent) {.base.} = discard
method onBulletFired*(bot: Bot, e: BulletFiredEvent) {.base.} = discard
method onBulletHit*(bot: Bot, e: BulletHitBotEvent) {.base.} = discard
method onBulletHitBullet*(bot: Bot, e: BulletHitBulletEvent) {.base.} = discard
method onBulletHitWall*(bot: Bot, e: BulletHitWallEvent) {.base.} = discard
method onHitByBullet*(bot: Bot, e: HitByBulletEvent) {.base.} = discard
method onHitBot*(bot: Bot, e: BotHitBotEvent) {.base.} = discard
method onHitWall*(bot: Bot, e: BotHitWallEvent) {.base.} = discard
method onScannedBot*(bot: Bot, e: ScannedBotEvent) {.base.} = discard
method onWonRound*(bot: Bot, e: WonRoundEvent) {.base.} = discard
method onTeamMessage*(bot: Bot, e: TeamMessageEvent) {.base.} = discard
method onDeath*(bot: Bot, e: BotDeathEvent)          {.base.} = discard
method onCustomEvent*(bot: Bot, e: Condition)        {.base.} = discard

# ---------------------------------------------------------------------------
# Event dispatch (called from bot thread)
# NOTE: must be defined before go() below
# ---------------------------------------------------------------------------

proc dispatchSingleEvent(bot: Bot; e: BotEvent) =
  ## Dispatch a typed BotEvent to the appropriate handler.
  case e.kind
  of ekTick:            bot.onTick(e.tick)
  of ekSkippedTurn:     bot.onSkippedTurn(e.skippedTurn)
  of ekBotDeath:        bot.onBotDeath(e.botDeath)
  of ekDeath:           bot.onDeath(e.death)
  of ekBulletFired:
    bot.onBulletFired(e.bulletFired)
    gIntentFirepower = 0.0
  of ekBulletHitBot:    bot.onBulletHit(e.bulletHitBot)
  of ekBulletHitBullet: bot.onBulletHitBullet(e.bulletHitBullet)
  of ekBulletHitWall:   bot.onBulletHitWall(e.bulletHitWall)
  of ekHitByBullet:     bot.onHitByBullet(e.hitByBullet)
  of ekHitBot:
    if e.hitBot.rammed: gDistanceRemaining = 0.0
    bot.onHitBot(e.hitBot)
  of ekHitWall:
    gDistanceRemaining = 0.0
    bot.onHitWall(e.hitWall)
  of ekScannedBot:      bot.onScannedBot(e.scannedBot)
  of ekWonRound:        bot.onWonRound(e.wonRound)
  of ekTeamMessage:     bot.onTeamMessage(e.teamMessage)
  of ekCustom:          bot.onCustomEvent(e.condition)

proc dispatchPendingEvents*(bot: Bot) =
  var pending: seq[BotEvent]
  let (hasEvents, evs) = gEventChan.tryRecv()  # non-blocking: stop signals carry no events
  if hasEvents: pending = evs
  for e in pending:
    gEventQueue.addEvent(e)
  let turnNumber = getTurn()
  gEventQueue.addCustomEvents(turnNumber)
  gEventQueue.removeOldEvents(turnNumber)
  gEventQueue.sortEvents()
  while gEventQueue.eventsLen > 0:
    let e = gEventQueue.events[0]
    let p = gEventQueue.getPriority(e.kind)
    if p < gEventQueue.currentTopPriority:
      break
    if p == gEventQueue.currentTopPriority:
      if gEventQueue.currentTopEventKind in gEventQueue.interruptible:
        gEventQueue.setInterruptible(gEventQueue.currentTopEventKind, false)
        gInterrupted = true
      break
    discard gEventQueue.popFirst()
    let oldPriority = gEventQueue.currentTopPriority
    let oldKind = gEventQueue.currentTopEventKind
    gEventQueue.currentTopPriority = p
    gEventQueue.currentTopEventKind = e.kind
    try: dispatchSingleEvent(bot, e)
    except Exception as ex:
      stderr.writeLine "[bot] event dispatch error: " & ex.msg
    gInterrupted = false
    gEventQueue.currentTopPriority = oldPriority
    gEventQueue.currentTopEventKind = oldKind

# ---------------------------------------------------------------------------
# go() — send intent and wait for next tick
# ---------------------------------------------------------------------------

var gDroppedIntents: int  # bot-thread only; rate-limits drop logging

proc go*() =
  ## Send current intent to the server and block until the next tick arrives.
  ## This is the fundamental time-step primitive — all blocking methods use it.
  if not isRunning():
    raise newException(CatchableError, "Bot is not running")
  # Stop-signal check BEFORE emitting an intent: a pending `false` means the
  # round/game ended while we were computing. Consume it and bail without an
  # intent so a stop is never treated as a tick (kills the duplicate-intent /
  # duplicate-GO-RECV storm at round boundaries).
  let (hasStop, stopVal) = gTickChan.tryRecv()
  if hasStop and not stopVal:
    debugLog("[GO-STOP] pending stop consumed — no intent emitted")
    return
  let json = buildIntentJson()
  debugLog("[GO-SEND] turn=" & $getTurn() &
    " intentTR=" & $gIntentTurnRate &
    " intentGTR=" & $gIntentGunTurnRate &
    " intentSpd=" & $gIntentTargetSpeed &
    " turnRem=" & $gTurnRemaining &
    " gunTurnRem=" & $gGunTurnRemaining &
    " distRem=" & $gDistanceRemaining &
    " overTR=" & $gOverrideTurnRate &
    " overGTR=" & $gOverrideGunTurnRate)
  clearGraphics()              # reset SVG buffer and style state for next tick
  # ponytail: trySend, drop if the cap-1 channel is full — a stalled sender
  # must never wedge the bot thread mid-round (corpse signature). Sender
  # drains unconditionally (see senderThreadEntry); the drop is pure belt.
  if not gIntentChan.trySend(json):
    inc gDroppedIntents
    if gDroppedIntents mod 100 == 1:
      debugLog("[GO-DROP] intent chan full (sender stalled/dead) — dropped " &
        $gDroppedIntents & " intents")
  let gotTick = gTickChan.recv()  # block until main thread finishes processTurn + wake
  if not gotTick:
    # Stop signal: round/game ended while we were blocked. No tick dispatch,
    # no further intent — the caller's isRunning() check exits the loop.
    debugLog("[GO-STOP] stop consumed in recv — no dispatch")
    return
  debugLog("[GO-RECV] turn=" & $getTurn() &
    " dir=" & $getDirection() &
    " gunDir=" & $getGunDirection() &
    " spd=" & $getSpeed() &
    " prevDir=" & $gPreviousDirection &
    " prevGunDir=" & $gPreviousGunDirection)
  # processTurn already ran on main thread — just dispatch events
  dispatchPendingEvents(gBot)  # fire event handlers for this tick

# ---------------------------------------------------------------------------
# Stop / Resume
# ---------------------------------------------------------------------------

proc setStop*(overwrite: bool = false) =
  ## Non-blocking: save current movement state (IBaseBot API).
  if not gStopped or overwrite:
    gStopped = true
    gSavedTurnRate      = gIntentTurnRate
    gSavedGunTurnRate   = gIntentGunTurnRate
    gSavedRadarTurnRate = gIntentRadarTurnRate
    gSavedTargetSpeed   = gIntentTargetSpeed
    gIntentTurnRate     = 0.0
    gIntentGunTurnRate  = 0.0
    gIntentRadarTurnRate = 0.0
    gIntentTargetSpeed  = 0.0

proc setResume*() =
  ## Non-blocking: restore saved movement state (IBaseBot API).
  if gStopped:
    gIntentTurnRate     = gSavedTurnRate
    gIntentGunTurnRate  = gSavedGunTurnRate
    gIntentRadarTurnRate = gSavedRadarTurnRate
    gIntentTargetSpeed  = gSavedTargetSpeed
    gStopped = false

proc stop*(overwrite: bool = false) =
  ## Blocking: save movement state, then call go() (IBot API).
  setStop(overwrite)

proc resume*() =
  ## Blocking: restore saved movement state, then call go() (IBot API).
  setResume()

# ---------------------------------------------------------------------------
# Blocking movement methods
# ---------------------------------------------------------------------------

proc setForward*(distance: float) =
  gOverrideTargetSpeed = true
  let speed = getNewTargetSpeed(gMaxSpeed, getSpeed(), distance)
  gIntentTargetSpeed = speed.clamp(-gMaxSpeed, gMaxSpeed)
  gDistanceRemaining = distance

proc setTurnLeft*(degrees: float) =
  gOverrideTurnRate = true
  gTurnRemaining    = degrees
  gIntentTurnRate   = degrees.clamp(-gMaxTurnRate, gMaxTurnRate)

proc setTurnRight*(degrees: float)     = setTurnLeft(-degrees)
proc setBack*(distance: float)         = setForward(-distance)

proc setTurnGunLeft*(degrees: float) =
  gOverrideGunTurnRate = true
  gGunTurnRemaining    = degrees
  gIntentGunTurnRate   = degrees.clamp(-gMaxGunTurnRate, gMaxGunTurnRate)

proc setTurnGunRight*(degrees: float)  = setTurnGunLeft(-degrees)

proc setTurnRadarLeft*(degrees: float) =
  gOverrideRadarTurnRate = true
  gRadarTurnRemaining    = degrees
  gIntentRadarTurnRate   = degrees.clamp(-gMaxRadarTurnRate, gMaxRadarTurnRate)

proc setTurnRadarRight*(degrees: float) = setTurnRadarLeft(-degrees)

proc forward*(distance: float) =
  debugLog("[FORWARD] distance=" & $distance & " dir=" & $getDirection())
  if gStopped:
    go()
  else:
    setForward(distance)
    while isRunning() and not gInterrupted and
          not (gDistanceRemaining == 0.0 and getSpeed() == 0.0):
      go()
  debugLog("[FORWARD-DONE] dir=" & $getDirection() & " distRem=" & $gDistanceRemaining)

proc back*(distance: float) = forward(-distance)

proc turnLeft*(degrees: float) =
  debugLog("[TURNLEFT] degrees=" & $degrees & " dir=" & $getDirection() & " gunDir=" & $getGunDirection())
  if gStopped:
    go()
  else:
    setTurnLeft(degrees)
    while isRunning() and not gInterrupted and gTurnRemaining != 0.0:
      go()
  debugLog("[TURNLEFT-DONE] dir=" & $getDirection() & " gunDir=" & $getGunDirection() & " turnRem=" & $gTurnRemaining)

proc turnRight*(degrees: float) = turnLeft(-degrees)

proc turnGunLeft*(degrees: float) =
  debugLog("[GUNLEFT] degrees=" & $degrees & " gunDir=" & $getGunDirection())
  if gStopped:
    go()
  else:
    setTurnGunLeft(degrees)
    while isRunning() and not gInterrupted and gGunTurnRemaining != 0.0:
      go()
  debugLog("[GUNLEFT-DONE] gunDir=" & $getGunDirection() & " gunTurnRem=" & $gGunTurnRemaining)

proc turnGunRight*(degrees: float) = turnGunLeft(-degrees)

proc turnRadarLeft*(degrees: float) =
  if gStopped:
    go()
  else:
    setTurnRadarLeft(degrees)
    while isRunning() and not gInterrupted and gRadarTurnRemaining != 0.0:
      go()

proc turnRadarRight*(degrees: float) = turnRadarLeft(-degrees)

proc fire*(firepower: float) =
  discard setFire(firepower)
  go()

proc rescan*() =
  setRescan()
  go()

proc waitFor*(condition: proc(): bool) =
  while isRunning() and not condition():
    go()

# ---------------------------------------------------------------------------
# Event queue public API
# ---------------------------------------------------------------------------

proc addCustomEvent*(name: string; test: proc(): bool) =
  ## Register a custom event condition. Evaluated each tick; fires onCustomEvent when true.
  gEventQueue.addCondition(Condition(name: name, test: test))

proc removeCustomEvent*(name: string) =
  ## Remove a custom event condition by name.
  gEventQueue.removeConditionByName(name)

proc setInterruptible*(v: bool) =
  ## Mark the current event handler as interruptible by same-priority events.
  if v: gEventQueue.interruptible.incl gEventQueue.currentTopEventKind
  else: gEventQueue.interruptible.excl gEventQueue.currentTopEventKind

proc getEventPriority*(kind: EventKind): int =
  ## Get the dispatch priority for an event kind.
  gEventQueue.getPriority(kind)

proc setEventPriority*(kind: EventKind; p: int) =
  ## Set the dispatch priority for an event kind.
  gEventQueue.setPriority(kind, p)

proc getEvents*(): seq[BotEvent] =
  ## Get all events currently in the queue.
  gEventQueue.getEvents()

proc clearEvents*() =
  ## Clear all events from the queue.
  gEventQueue.clearEvents()

# ---------------------------------------------------------------------------
# Bot thread entry point
# ---------------------------------------------------------------------------

proc botThreadEntry() {.thread.} =
  ## Runs `bot.run()` after waiting for the first tick.
  {.cast(gcsafe).}:
    # Wait for first tick signal from main thread
    # (clearRemaining + processTurn already ran on main thread)
    let firstTick = gTickChan.recv()
    if not firstTick:
      debugLog("[DBG] botThreadEntry: stop before first tick — exiting")
      return
    debugLog("[DBG] botThreadEntry: first tick" &
      "  dir=" & $getDirection() &
      "  gunDir=" & $getGunDirection() &
      "  prevDir=" & $gPreviousDirection &
      "  prevGunDir=" & $gPreviousGunDirection)

    # Reset graphics + intent buffers on the thread that owns them. go()'s
    # stop path (round end) returns before buildIntentJson/clearGraphics, so
    # the previous round's thread can leave content behind; resetting here
    # keeps it from leaking into this round's first intent.
    clearGraphics()
    gIntentStdOutLen = 0
    gIntentStdErrLen = 0
    for i in 0 ..< gIntentTeamMsgsLen: gIntentTeamMessages[i].reset
    gIntentTeamMsgsLen = 0

    dispatchPendingEvents(gBot)  # dispatch events embedded in the first tick

    try:
      gBot.run()
    except Exception as e:
      stderr.writeLine "[bot] run() exception: " & e.msg

    # After run() exits, keep calling go() to skip turns until game ends
    while isRunning():
      try: go()
      except: break

# ---------------------------------------------------------------------------
# Exported initialiser (called from start() in tankroyale_botapi.nim)
# ---------------------------------------------------------------------------

proc initGlobals*() =
  gTickChan.open(1)
  gIntentChan.open(1)
  gEventChan.open(8)
  initLock(gLock)
  gEventQueue = initEventQueue()
  withLock(gLock):
    gBotNames = initTable[int, string]()
  # Debug log is opt-in: it is written every tick from two threads, so leaving
  # it on by default is a disk hog and an I/O stall source. Enable with
  # PPOB_DEBUG_LOG=1 to debug; starts fresh (truncated) each run.
  if getEnv("PPOB_DEBUG_LOG", "") == "1":
    gDebugLog = open(gDebugLogPath, fmAppend)
    resetDebugLog()
    gDebugLog.writeLine("=== PROCESS START pid=" & $getpid() & " ===")
    gDebugLog.flushFile()

proc setServerInfo*(variant, version: string) =
  withLock(gLock):
    gVariant       = variant
    gServerVersion = version

proc setGameStarted*(myId: int; setup: GameSetup; teammateIds: seq[int]) =
  withLock(gLock):
    gMyId        = myId
    gGameSetup   = setup
    gTeammateIds = teammateIds
  debugLog("=== GAME START myId=" & $myId & " ===")

proc startRound*() =
  withLock(gLock):
    gRunning = true
    gTurn    = 0
  gFirstTickOfRound = true

proc setRunning*(v: bool) =
  withLock(gLock): gRunning = v

proc signalTick*(tick: TickEventForBot; events: seq[BotEvent]) =
  ## Called from main thread when a new tick arrives.
  ## Updates shared state only — caller must call processTickOnMainThread + wakeBotThread.
  withLock(gLock):
    gTurn       = tick.turnNumber
    gRound      = tick.roundNumber
    gEnemyCount = tick.botState.enemyCount   # enemyCount lives in BotState
    gState      = tick.botState
    gBullets    = tick.bulletStates
  # Prepend tick event, then sub-events — queue sorts by priority.
  # Moved through a Channel: ownership transfer, no cross-thread refcounts.
  # Send happens-before wakeBotThread's tickChan signal, so the bot thread
  # always finds its events waiting when it wakes.
  var pending = @[BotEvent(kind: ekTick, turnNumber: tick.turnNumber, tick: tick)]
  pending.add events
  gEventChan.send(move(pending))

proc processTickOnMainThread*() =
  ## Run motion tracking on the main thread while bot is blocked.
  ## Must be called after signalTick and before wakeBotThread.
  if gFirstTickOfRound:
    clearRemaining()
    gFirstTickOfRound = false
  processTurn()

proc wakeBotThread*() =
  ## Wake the bot thread after state + motion tracking are ready.
  gTickChan.send(true)

var gWsFailed = false  # set by sender thread when a ws.send dies

proc senderThreadEntry() {.thread.} =
  ## Sender thread: owns all WebSocket writes during gameplay.
  ## ponytail: never exits — keeps draining gIntentChan so the bot thread's
  ## trySend never wedges. A dead socket just discards intents (the main
  ## receive loop detects the broken connection and exits cleanly).
  {.cast(gcsafe).}:
    while true:
      let json = gIntentChan.recv()
      if json.len == 0: break  # sentinel: stop
      try:
        gWs.send(json)
      except Exception as e:
        gWsFailed = true
        stderr.writeLine "[sender] send error (keeping drain): " & e.msg
        debugLog("[SENDER-ERR] " & e.msg)
        # drain without blocking: bot's go() uses trySend, so the channel is
        # either empty or has at most one fresh intent — the next recv takes it
        continue

proc startSenderThread*() =
  createThread(gSenderThread, senderThreadEntry)

proc stopSenderThread*() =
  gIntentChan.send("")  # sentinel
  joinThread(gSenderThread)

proc signalStop*() =
  ## Unblock the bot thread when a round or the game ends.
  ## Sends a dummy false to gTickChan so the bot wakes from go().
  ## gTickChan has capacity 1 and the server can deliver the final
  ## TickEventForBot + RoundEndedEventForBot back-to-back, leaving the tick's
  ## `true` unconsumed: the bot exits via `raise` on the isRunning() check in
  ## the next go() instead of another recv(), so send(false) would block
  ## forever and freeze the main receive loop (silent corpse). The main thread
  ## is the only gTickChan sender, so draining right before the send cannot
  ## race; [true,false] and [false] orderings both unblock cleanly.
  debugLog("[SS-ENTER] tid=" & $getThreadId())
  let (drained, val) = gTickChan.tryRecv()
  debugLog("[SS-DRAIN] drained=" & $drained & " val=" & $val & " tid=" & $getThreadId())
  gTickChan.send(false)
  debugLog("[SS-SENT] false tid=" & $getThreadId())
  debugLog("[SS-EXIT] tid=" & $getThreadId())

proc recvIntent*(): string =
  ## Called by main thread after signalling a tick.
  ## Blocks until the bot thread sends its intent JSON via go().
  let (ok, json) = gIntentChan.tryRecv()
  if ok: return json
  return gIntentChan.recv()

proc drainIntentChan*() =
  ## Discard any pending intent (used when round/game ends).
  discard gIntentChan.tryRecv()

proc drainTickChan*() =
  ## Discard any pending tick/stop signal left in gTickChan.
  ## Needed when the bot thread exits via isRunning() check instead of
  ## consuming the stop signal from go() — the false sits in the channel
  ## and would be mistaken for the first real tick of the next round.
  let (drained, val) = gTickChan.tryRecv()
  if drained:
    debugLog("[DBG] drainTickChan: drained signal=" & $val)

proc drainEventChan*() =
  ## Discard any unconsumed tick events left in gEventChan (round/game end).
  ## Called after the bot thread joined — no more recv's possible, so this
  ## prevents stale previous-round events leaking into the next round.
  while true:
    let (hasEvents, _) = gEventChan.tryRecv()
    if not hasEvents: break

proc startBotThread*() =
  createThread(gBotThread, botThreadEntry)

proc waitForBotThread*() =
  joinThread(gBotThread)
