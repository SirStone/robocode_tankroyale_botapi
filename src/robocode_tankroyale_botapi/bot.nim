## Core bot implementation for Robocode Tank Royale Nim bot API.
##
## This module defines the `Bot` base type, state query procedures, movement commands,
## and event handler methods.
##
## ## How to Create a Bot
##
## To create a bot, subclass `Bot` and override the `run` method:
##
## ```nim
## import robocode_tankroyale_botapi
##
## type MyBot = ref object of Bot
##
## method run(bot: MyBot) =
##   while isRunning():
##     forward(100)
##     turnGunLeft(360)
##     back(100)
##     turnGunRight(360)
## ```
##
## ## Methods vs Procedures
##
## - **Event Handlers** (like `run`, `onScannedBot`, `onHitByBullet`) are **methods** that take `bot: Bot` as their first parameter. Override these to define your bot's behavior.
## - **Actions and State Queries** (like `forward`, `turnLeft`, `getX`, `getEnergy`) are **procedures** that operate on the active global bot instance automatically. You can call them directly inside `run` or your event handlers.
##
## ## Blocking vs Non-Blocking Commands
##
## The API provides two styles of movement:
##
## 1. **Blocking commands**: `forward(100)`, `turnLeft(90)`, `turnGunRight(45)`.
##    These execute step-by-step each tick and block your bot's execution thread until the action finishes.
## 2. **Non-blocking (Independent) setters**: `setForward(100)`, `setTurnLeft(90)`, `setTurnGunRight(45)`.
##    These set the target movement for future ticks without blocking. You must call `go()` manually to execute one turn/tick.
##
## ## Threading Architecture
##
## Under the hood, Nim bot execution uses three threads:
## - **Main thread**: Runs the WebSocket receive loop, receives server updates, updates shared state, and signals ticks.
## - **Bot thread**: Runs your `run()` loop and event callbacks. Blocks on `go()`.
## - **Sender thread**: Sends your intent commands to the server via WebSocket.

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
var gPendingMsg*: string  ## Message received during waitForBotThreadWhileServicingWs; main loop re-dispatches.

# Thread handles
var gBotThread:    Thread[void]
var gSenderThread: Thread[void]
var gBotThreadStarted: bool        # true after first createThread; never join mid-game
var gFirstTickOfRound: bool  # main-thread only, no lock needed

# Channels  — must be opened before use
var gTickChan:      Channel[bool]     # main → bot: tick arrived (false = stop round)
var gIntentChan:    Channel[string]   # bot  → sender: send this JSON
var gStartRoundChan: Channel[bool]   # main → bot: true = new round; false = shutdown
var gRoundDoneChan:  Channel[bool]   # bot → main: round loop finished

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
# State queries and readers
# ---------------------------------------------------------------------------

proc getMyId*(): int =
  ## Returns your bot's unique ID assigned by the server for the current battle.
  withLock(gLock): result = gMyId

proc getRound*(): int =
  ## Returns the current 1-based round number in the battle.
  withLock(gLock): result = gRound

proc getTurn*(): int =
  ## Returns the current 1-based turn number within the current round.
  withLock(gLock): result = gTurn

proc getEnemyCount*(): int =
  ## Returns the number of opponent bots currently alive in the arena.
  withLock(gLock): result = gEnemyCount

proc getEnergy*(): float =
  ## Returns your bot's current energy level (hit points). Starts at 100.0 (or 120.0 for Droids).
  withLock(gLock): result = gState.energy

proc getX*(): float =
  ## Returns your bot's current X coordinate in the arena (0 is left edge).
  withLock(gLock): result = gState.x

proc getY*(): float =
  ## Returns your bot's current Y coordinate in the arena (0 is top edge).
  withLock(gLock): result = gState.y

proc getDirection*(): float =
  ## Returns your bot body's current heading in degrees [0, 360). 0° = North (up), 90° = East (right).
  withLock(gLock): result = gState.direction

proc getGunDirection*(): float =
  ## Returns your bot gun's current heading in degrees [0, 360). 0° = North, 90° = East.
  withLock(gLock): result = gState.gunDirection

proc getRadarDirection*(): float =
  ## Returns your bot radar's current heading in degrees [0, 360). 0° = North, 90° = East.
  withLock(gLock): result = gState.radarDirection

proc getRadarSweep*(): float =
  ## Returns the radar sweep angle (degrees turned) during the last turn.
  withLock(gLock): result = gState.radarSweep

proc getSpeed*(): float =
  ## Returns your bot's current velocity in units per turn from `-8.0` to `8.0`. Positive is forward, negative is backward.
  withLock(gLock): result = gState.speed

proc getTurnRate*(): float =
  ## Returns your body's turn rate in degrees per turn from `-10.0` to `10.0`.
  withLock(gLock): result = gState.turnRate

proc getGunTurnRate*(): float =
  ## Returns your gun's turn rate in degrees per turn from `-20.0` to `20.0`.
  withLock(gLock): result = gState.gunTurnRate

proc getRadarTurnRate*(): float =
  ## Returns your radar's turn rate in degrees per turn from `-45.0` to `45.0`.
  withLock(gLock): result = gState.radarTurnRate

proc getGunHeat*(): float =
  ## Returns current gun heat. You can only fire when gun heat is 0.0.
  withLock(gLock): result = gState.gunHeat

proc getBodyColor*(): Color =
  ## Returns current body color of your bot.
  withLock(gLock): result = gState.bodyColor

proc getTurretColor*(): Color =
  ## Returns current turret color of your bot.
  withLock(gLock): result = gState.turretColor

proc getRadarColor*(): Color =
  ## Returns current radar color of your bot.
  withLock(gLock): result = gState.radarColor

proc getBulletColor*(): Color =
  ## Returns current color of bullets fired by your bot.
  withLock(gLock): result = gState.bulletColor

proc getScanColor*(): Color =
  ## Returns current color of your radar scan arc.
  withLock(gLock): result = gState.scanColor

proc getTracksColor*(): Color =
  ## Returns current color of your bot's tracks.
  withLock(gLock): result = gState.tracksColor

proc getGunColor*(): Color =
  ## Returns current color of your gun barrel.
  withLock(gLock): result = gState.gunColor

proc getArenaWidth*(): int =
  ## Returns the arena width in pixels/units (typically 800).
  withLock(gLock): result = gGameSetup.arenaWidth

proc getArenaHeight*(): int =
  ## Returns the arena height in pixels/units (typically 600).
  withLock(gLock): result = gGameSetup.arenaHeight

proc getGameType*(): string =
  ## Returns the game mode ("classic", "melee", or "1v1").
  withLock(gLock): result = gGameSetup.gameType

proc getNumberOfRounds*(): int =
  ## Returns the total number of rounds in this battle.
  withLock(gLock): result = gGameSetup.numberOfRounds

proc getGunCoolingRate*(): float =
  ## Returns the gun cooling rate per turn (typically 0.1).
  withLock(gLock): result = gGameSetup.gunCoolingRate

proc getMaxInactivityTurns*(): int =
  ## Returns maximum allowed inactive turns before taking zap damage.
  withLock(gLock): result = gGameSetup.maxInactivityTurns

proc getTurnTimeout*(): int =
  ## Returns the maximum turn processing timeout in microseconds.
  withLock(gLock): result = gGameSetup.turnTimeout

proc getTimeLeft*(): int =
  ## Returns turn timeout limit in microseconds.
  getTurnTimeout()

proc getVariant*(): string =
  ## Returns server variant string.
  withLock(gLock): result = gVariant

proc getServerVersion*(): string =
  ## Returns server version string.
  withLock(gLock): result = gServerVersion

proc isRunning*(): bool =
  ## Returns true while the current round is actively running.
  withLock(gLock): result = gRunning

proc isDroid*(): bool =
  ## Returns true if your bot is configured as a Droid.
  withLock(gLock): result = gState.isDroid

proc isDisabled*(): bool =
  ## Returns true if your bot is disabled (energy <= 0.0).
  getEnergy() == 0.0

proc isStopped*(): bool =
  ## Returns true if movement has been paused via `stop()` or `setStop()`.
  gStopped

proc getBulletStates*(): seq[BulletState] =
  ## Returns states of all active bullets currently traveling in the arena.
  withLock(gLock): result = gBullets

proc getTeammateIds*(): seq[int] =
  ## Returns a sequence of bot IDs belonging to your team.
  withLock(gLock): result = gTeammateIds

proc isTeammate*(botId: int): bool =
  ## Returns true if the given `botId` belongs to a teammate.
  withLock(gLock): result = gTeammateIds.contains(botId)

proc getDistanceRemaining*(): float =
  ## Returns remaining distance for current `forward()` or `setForward()` movement.
  gDistanceRemaining

proc getTurnRemaining*(): float =
  ## Returns remaining degrees for current `turnLeft()` / `turnRight()` movement.
  gTurnRemaining

proc getGunTurnRemaining*(): float =
  ## Returns remaining degrees for current gun turning command.
  gGunTurnRemaining

proc getRadarTurnRemaining*(): float =
  ## Returns remaining degrees for current radar turning command.
  gRadarTurnRemaining

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
var gIntentTeamMessages: seq[TeamMessage]
var gIntentStdOut:       string
var gIntentStdErr:       string

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
  if gIntentTeamMessages.len > 0:
    var msgs = newJArray()
    for m in gIntentTeamMessages:
      var mo = newJObject()
      mo["message"]     = %m.message
      mo["messageType"] = %m.messageType
      if m.receiverId != 0:
        mo["receiverId"] = %m.receiverId
      msgs.add mo
    obj["teamMessages"] = msgs
    gIntentTeamMessages.setLen(0)
  if gIntentStdOut.len > 0:
    obj["stdOut"] = %gIntentStdOut
    gIntentStdOut.setLen(0)
  if gIntentStdErr.len > 0:
    obj["stdErr"] = %gIntentStdErr
    gIntentStdErr.setLen(0)
  let svg = svgOutput()
  if svg.len > 0:
    obj["debugGraphics"] = %svg
  result = $obj

# ---------------------------------------------------------------------------
# Intent setters (bot thread)
# ---------------------------------------------------------------------------

proc setTurnRate*(rate: float) =
  ## Non-blocking: Set continuous body turn rate in degrees per turn from `-10.0` to `10.0`.
  gIntentTurnRate = rate.clamp(-gMaxTurnRate, gMaxTurnRate)
  gOverrideTurnRate = false
  gContinuousTurnRate = rate
  gTurnRemaining = toInfiniteValue(rate)

proc setGunTurnRate*(rate: float) =
  ## Non-blocking: Set continuous gun turn rate in degrees per turn from `-20.0` to `20.0`.
  gIntentGunTurnRate = rate.clamp(-gMaxGunTurnRate, gMaxGunTurnRate)
  gOverrideGunTurnRate = false
  gContinuousGunTurnRate = rate
  gGunTurnRemaining = toInfiniteValue(rate)

proc setRadarTurnRate*(rate: float) =
  ## Non-blocking: Set continuous radar turn rate in degrees per turn from `-45.0` to `45.0`.
  gIntentRadarTurnRate = rate.clamp(-gMaxRadarTurnRate, gMaxRadarTurnRate)
  gOverrideRadarTurnRate = false
  gContinuousRadarTurnRate = rate
  gRadarTurnRemaining = toInfiniteValue(rate)

proc setTargetSpeed*(speed: float) =
  ## Non-blocking: Set continuous target speed in units per turn from `-8.0` to `8.0`.
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
  ## Non-blocking: Attempt to queue a bullet to fire on the next tick with `firepower` between 0.1 and 3.0.
  ## Returns true if firepower is valid, bot has enough energy, and gun heat is 0.0.
  let fp = firepower.clamp(MIN_FIRE_POWER, MAX_FIRE_POWER)
  if getEnergy() < fp or getGunHeat() > 0.0:
    return false
  gIntentFirepower = fp
  return true

proc setRescan*() =
  ## Non-blocking: Queue a radar rescan for the next tick.
  gIntentRescan = true

proc setBodyColor*(color: Color)   =
  ## Set body color of your bot. Accepts `Color` or hex string.
  gIntentBodyColor = color

proc setTurretColor*(color: Color) =
  ## Set turret color of your bot. Accepts `Color` or hex string.
  gIntentTurretColor = color

proc setRadarColor*(color: Color)  =
  ## Set radar color of your bot. Accepts `Color` or hex string.
  gIntentRadarColor = color

proc setBulletColor*(color: Color) =
  ## Set color of bullets fired by your bot. Accepts `Color` or hex string.
  gIntentBulletColor = color

proc setScanColor*(color: Color)   =
  ## Set color of your radar scan arc. Accepts `Color` or hex string.
  gIntentScanColor = color

proc setTracksColor*(color: Color) =
  ## Set color of your bot's tracks. Accepts `Color` or hex string.
  gIntentTracksColor = color

proc setGunColor*(color: Color)    =
  ## Set color of your gun barrel. Accepts `Color` or hex string.
  gIntentGunColor = color

proc printToStdOut*(s: string) =
  ## Append s to this tick's stdOut payload (sent to server in BotIntent).
  gIntentStdOut.add s

proc printToStdErr*(s: string) =
  ## Append s to this tick's stdErr payload (sent to server in BotIntent).
  gIntentStdErr.add s

proc broadcastTeamMessage*(message: string) =
  ## Send a text message to all teammates during this tick.
  gIntentTeamMessages.add TeamMessage(message: message, messageType: "String")

proc sendTeamMessage*(botId: int; message: string) =
  ## Send a text message to a specific teammate (`botId`) during this tick.
  gIntentTeamMessages.add TeamMessage(message: message, messageType: "String", receiverId: botId)

proc setAdjustGunForBodyTurn*(v: bool) =
  ## Configure whether gun stays independent of body turning (true) or turns with body (false).
  gIntentAdjGunBody = v

proc setAdjustRadarForBodyTurn*(v: bool) =
  ## Configure whether radar stays independent of body turning (true) or turns with body (false).
  gIntentAdjRadarBody = v

proc setFireAssist*(enable: bool) =
  ## Enable or disable auto-fire assist when gun is on target.
  gIntentFireAssist = enable

proc setAdjustRadarForGunTurn*(v: bool) =
  ## Configure whether radar stays independent of gun turning (true) or turns with gun (false).
  gIntentAdjRadarGun = v
  setFireAssist(not v)

proc isAdjustGunForBodyTurn*(): bool    =
  ## Returns true if gun stays independent of body turning.
  gIntentAdjGunBody

proc isAdjustRadarForBodyTurn*(): bool  =
  ## Returns true if radar stays independent of body turning.
  gIntentAdjRadarBody

proc isAdjustRadarForGunTurn*(): bool   =
  ## Returns true if radar stays independent of gun turning.
  gIntentAdjRadarGun

proc getTargetSpeed*(): float =
  ## Returns target speed set for current turn.
  gIntentTargetSpeed

proc getFirepower*(): float =
  ## Returns queued firepower for current turn.
  gIntentFirepower

# Convenience math re-exports (state-aware wrappers; pure-math helpers come from utils)
proc calcBearing*(direction: float): float =
  ## Calculate relative bearing in degrees [-180, 180) from your bot's body heading to `direction`.
  botutils.calcDeltaAngle(direction, getDirection())

proc calcGunBearing*(direction: float): float =
  ## Calculate relative bearing in degrees [-180, 180) from your gun heading to `direction`.
  botutils.calcDeltaAngle(direction, getGunDirection())

proc calcRadarBearing*(direction: float): float =
  ## Calculate relative bearing in degrees [-180, 180) from your radar heading to `direction`.
  botutils.calcDeltaAngle(direction, getRadarDirection())

proc bearingTo*(x, y: float): float =
  ## Calculate relative bearing in degrees [-180, 180) from your bot's position and heading to target (x, y).
  botutils.bearingTo(getX(), getY(), getDirection(), x, y)

proc gunBearingTo*(x, y: float): float =
  ## Calculate relative bearing in degrees [-180, 180) from your gun heading to target (x, y).
  botutils.bearingTo(getX(), getY(), getGunDirection(), x, y)

proc radarBearingTo*(x, y: float): float =
  ## Calculate relative bearing in degrees [-180, 180) from your radar heading to target (x, y).
  botutils.normalizeRelativeAngle(botutils.directionTo(getX(), getY(), x, y) - getRadarDirection())

proc directionTo*(x, y: float): float =
  ## Calculate absolute direction in degrees [0, 360) from your bot's position to target (x, y).
  botutils.directionTo(getX(), getY(), x, y)

proc distanceTo*(x, y: float): float =
  ## Calculate Euclidean distance in units from your bot's position to target (x, y).
  botutils.distanceTo(getX(), getY(), x, y)

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

method run*(bot: Bot) {.base.} =
  ## Main entry point for your bot's behavior.
  ##
  ## Override this method in your `Bot` subtype to define what your bot does.
  ## This method is called once per round on the dedicated bot thread.
  ##
  ## Example:
  ## ```nim
  ## type MyBot = ref object of Bot
  ##
  ## method run(bot: MyBot) =
  ##   while isRunning():
  ##     forward(100)
  ##     turnGunLeft(360)
  ##     back(100)
  ##     turnGunRight(360)
  ## ```
  discard

method onConnected*(bot: Bot, e: ConnectedEvent) {.base.} =
  ## Called when your bot successfully connects to the Tank Royale server.
  discard

method onDisconnected*(bot: Bot, e: DisconnectedEvent) {.base.} =
  ## Called when your bot disconnects from the server.
  discard

method onConnectionError*(bot: Bot, e: ConnectionErrorEvent) {.base.} =
  ## Called when a network connection error occurs.
  discard

method onGameStarted*(bot: Bot, e: GameStartedEventForBot) {.base.} =
  ## Called when a new game starts.
  ## `e` contains initial position, your bot ID, teammate IDs, and arena setup rules.
  discard

method onGameEnded*(bot: Bot, e: GameEndedEventForBot) {.base.} =
  ## Called when the entire game (all rounds) finishes.
  ## `e` contains final score results and ranking.
  discard

method onGameAborted*(bot: Bot) {.base.} =
  ## Called if the game was aborted prematurely by the server host.
  discard

method onRoundStarted*(bot: Bot, e: RoundStartedEvent) {.base.} =
  ## Called at the beginning of each round before `run()` starts.
  discard

method onRoundEnded*(bot: Bot, e: RoundEndedEventForBot) {.base.} =
  ## Called at the end of each round.
  ## `e` contains score breakdown for the round.
  discard

method onTick*(bot: Bot, e: TickEventForBot) {.base.} =
  ## Called on every game turn (tick) with updated game state.
  discard

method onSkippedTurn*(bot: Bot, e: SkippedTurnEvent) {.base.} =
  ## Called when your bot took too long to compute and skipped a turn.
  discard

method onBotDeath*(bot: Bot, e: BotDeathEvent) {.base.} =
  ## Called when another bot in the arena is destroyed.
  discard

method onBulletFired*(bot: Bot, e: BulletFiredEvent) {.base.} =
  ## Called when your bot fires a bullet.
  discard

method onBulletHit*(bot: Bot, e: BulletHitBotEvent) {.base.} =
  ## Called when one of your bullets strikes an enemy bot.
  discard

method onBulletHitBullet*(bot: Bot, e: BulletHitBulletEvent) {.base.} =
  ## Called when one of your bullets collides with an opponent's bullet.
  discard

method onBulletHitWall*(bot: Bot, e: BulletHitWallEvent) {.base.} =
  ## Called when one of your bullets hits an arena wall.
  discard

method onHitByBullet*(bot: Bot, e: HitByBulletEvent) {.base.} =
  ## Called when your bot is struck by an opponent's bullet.
  discard

method onHitBot*(bot: Bot, e: BotHitBotEvent) {.base.} =
  ## Called when your bot collides with another bot (ramming).
  discard

method onHitWall*(bot: Bot, e: BotHitWallEvent) {.base.} =
  ## Called when your bot collides with an arena wall.
  discard

method onScannedBot*(bot: Bot, e: ScannedBotEvent) {.base.} =
  ## Called when your radar detects an enemy bot.
  ## `e` contains the scanned bot's position, heading, velocity, and energy.
  discard

method onWonRound*(bot: Bot, e: WonRoundEvent) {.base.} =
  ## Called when your bot is the last one alive and wins the round!
  discard

method onTeamMessage*(bot: Bot, e: TeamMessageEvent) {.base.} =
  ## Called when a teammate sends a message to your bot.
  discard

method onDeath*(bot: Bot, e: BotDeathEvent) {.base.} =
  ## Called when your own bot is destroyed.
  discard

method onCustomEvent*(bot: Bot, e: Condition) {.base.} =
  ## Called when a custom event registered via `addCustomEvent` evaluates to true.
  discard

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
  while gEventQueue.events.len > 0:
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
  ## Send current intent commands to the server and block until the next tick arrives.
  ##
  ## `go()` is the core time-step primitive. If you use non-blocking setters like
  ## `setForward`, `setTurnLeft`, or `setFire`, call `go()` to execute one turn:
  ##
  ## ```nim
  ## setForward(100)
  ## setTurnGunLeft(90)
  ## setFire(2.0)
  ## go() # Sends all commands for this turn
  ## ```
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
  ## Non-blocking: Pause movement by setting target speed and turn rates to 0.0,
  ## while saving current movement state so it can be restored later via `setResume()`.
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
  ## Non-blocking: Resume movement that was paused with `setStop()` or `stop()`.
  if gStopped:
    gIntentTurnRate     = gSavedTurnRate
    gIntentGunTurnRate  = gSavedGunTurnRate
    gIntentRadarTurnRate = gSavedRadarTurnRate
    gIntentTargetSpeed  = gSavedTargetSpeed
    gStopped = false

proc stop*(overwrite: bool = false) =
  ## Blocking: Pause movement state (via `setStop`), then call `go()` to execute the turn.
  setStop(overwrite)

proc resume*() =
  ## Blocking: Restore saved movement state (via `setResume`), then call `go()`.
  setResume()

# ---------------------------------------------------------------------------
# Independent Movement Setters (Non-Blocking)
# ---------------------------------------------------------------------------

proc setForward*(distance: float) =
  ## Non-blocking: Set target forward distance in units (negative to move backward).
  ## Call `go()` to process each turn.
  gOverrideTargetSpeed = true
  let speed = getNewTargetSpeed(gMaxSpeed, getSpeed(), distance)
  gIntentTargetSpeed = speed.clamp(-gMaxSpeed, gMaxSpeed)
  gDistanceRemaining = distance

proc setTurnLeft*(degrees: float) =
  ## Non-blocking: Set target left turn amount in degrees (negative to turn right).
  ## Call `go()` to process each turn.
  gOverrideTurnRate = true
  gTurnRemaining    = degrees
  gIntentTurnRate   = degrees.clamp(-gMaxTurnRate, gMaxTurnRate)

proc setTurnRight*(degrees: float) =
  ## Non-blocking: Set target right turn amount in degrees.
  setTurnLeft(-degrees)

proc setBack*(distance: float) =
  ## Non-blocking: Set target backward distance in units.
  setForward(-distance)

proc setTurnGunLeft*(degrees: float) =
  ## Non-blocking: Set target left turn amount for the gun in degrees.
  gOverrideGunTurnRate = true
  gGunTurnRemaining    = degrees
  gIntentGunTurnRate   = degrees.clamp(-gMaxGunTurnRate, gMaxGunTurnRate)

proc setTurnGunRight*(degrees: float) =
  ## Non-blocking: Set target right turn amount for the gun in degrees.
  setTurnGunLeft(-degrees)

proc setTurnRadarLeft*(degrees: float) =
  ## Non-blocking: Set target left turn amount for the radar in degrees.
  gOverrideRadarTurnRate = true
  gRadarTurnRemaining    = degrees
  gIntentRadarTurnRate   = degrees.clamp(-gMaxRadarTurnRate, gMaxRadarTurnRate)

proc setTurnRadarRight*(degrees: float) =
  ## Non-blocking: Set target right turn amount for the radar in degrees.
  setTurnRadarLeft(-degrees)

# ---------------------------------------------------------------------------
# Blocking Movement Commands
# ---------------------------------------------------------------------------

proc forward*(distance: float) =
  ## Blocking command: Move forward by `distance` units.
  ##
  ## Automatically calls `go()` each tick until movement completes.
  ## Negative values move the bot backward.
  ##
  ## Example:
  ## ```nim
  ## forward(100) # Move forward 100 units
  ## ```
  debugLog("[FORWARD] distance=" & $distance & " dir=" & $getDirection())
  if gStopped:
    go()
  else:
    setForward(distance)
    while isRunning() and not gInterrupted and
          not (gDistanceRemaining == 0.0 and getSpeed() == 0.0):
      go()
  debugLog("[FORWARD-DONE] dir=" & $getDirection() & " distRem=" & $gDistanceRemaining)

proc back*(distance: float) =
  ## Blocking command: Move backward by `distance` units.
  forward(-distance)

proc turnLeft*(degrees: float) =
  ## Blocking command: Turn body left (counter-clockwise) by `degrees`.
  ##
  ## Automatically calls `go()` each tick until turning completes.
  debugLog("[TURNLEFT] degrees=" & $degrees & " dir=" & $getDirection() & " gunDir=" & $getGunDirection())
  if gStopped:
    go()
  else:
    setTurnLeft(degrees)
    while isRunning() and not gInterrupted and gTurnRemaining != 0.0:
      go()
  debugLog("[TURNLEFT-DONE] dir=" & $getDirection() & " gunDir=" & $getGunDirection() & " turnRem=" & $gTurnRemaining)

proc turnRight*(degrees: float) =
  ## Blocking command: Turn body right (clockwise) by `degrees`.
  turnLeft(-degrees)

proc turnGunLeft*(degrees: float) =
  ## Blocking command: Turn gun left (counter-clockwise) by `degrees`.
  debugLog("[GUNLEFT] degrees=" & $degrees & " gunDir=" & $getGunDirection())
  if gStopped:
    go()
  else:
    setTurnGunLeft(degrees)
    while isRunning() and not gInterrupted and gGunTurnRemaining != 0.0:
      go()
  debugLog("[GUNLEFT-DONE] gunDir=" & $getGunDirection() & " gunTurnRem=" & $gGunTurnRemaining)

proc turnGunRight*(degrees: float) =
  ## Blocking command: Turn gun right (clockwise) by `degrees`.
  turnGunLeft(-degrees)

proc turnRadarLeft*(degrees: float) =
  ## Blocking command: Turn radar left (counter-clockwise) by `degrees`.
  if gStopped:
    go()
  else:
    setTurnRadarLeft(degrees)
    while isRunning() and not gInterrupted and gRadarTurnRemaining != 0.0:
      go()

proc turnRadarRight*(degrees: float) =
  ## Blocking command: Turn radar right (clockwise) by `degrees`.
  turnRadarLeft(-degrees)

proc fire*(firepower: float) =
  ## Blocking command: Fire a bullet with given `firepower` (between 0.1 and 3.0) and wait one turn.
  discard setFire(firepower)
  go()

proc rescan*() =
  ## Request an immediate radar rescan and wait one turn.
  setRescan()
  go()

proc waitFor*(condition: proc(): bool) =
  ## Blocking helper: keep calling `go()` until `condition()` returns true or round ends.
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
  ## Persistent bot thread. Loops over rounds until shutdown signal.
  ## Each iteration: wait for start-round → run bot → signal round-done.
  {.cast(gcsafe).}:
    while true:
      # Wait for main thread to signal a new round (true) or final shutdown (false)
      let startRound = gStartRoundChan.recv()
      if not startRound:
        debugLog("[DBG] botThreadEntry: shutdown signal — exiting")
        break

      # Reset graphics + intent buffers (same thread, no heap crossing).
      clearGraphics()
      gIntentStdOut.setLen(0)
      gIntentStdErr.setLen(0)
      gIntentTeamMessages.setLen(0)

      # Wait for first tick signal from main thread
      # (clearRemaining + processTurn already ran on main thread)
      let firstTick = gTickChan.recv()
      if not firstTick:
        debugLog("[DBG] botThreadEntry: stop before first tick — signalling done")
        gRoundDoneChan.send(true)
        continue

      debugLog("[DBG] botThreadEntry: first tick" &
        "  dir=" & $getDirection() &
        "  gunDir=" & $getGunDirection() &
        "  prevDir=" & $gPreviousDirection &
        "  prevGunDir=" & $gPreviousGunDirection)

      dispatchPendingEvents(gBot)  # dispatch events embedded in the first tick

      try:
        gBot.run()
      except Exception as e:
        stderr.writeLine "[bot] run() exception: " & e.msg

      # After run() exits, keep calling go() to skip turns until round/game ends
      while isRunning():
        try: go()
        except: break

      # Signal main thread: round loop finished, back to idle
      gRoundDoneChan.send(true)
      debugLog("[DBG] botThreadEntry: round done, waiting for next round")

# ---------------------------------------------------------------------------
# Exported initialiser (called from start() in tankroyale_botapi.nim)
# ---------------------------------------------------------------------------

proc initGlobals*() =
  gTickChan.open(1)
  gIntentChan.open(1)
  gEventChan.open(8)
  gStartRoundChan.open(1)
  gRoundDoneChan.open(1)
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
  ## race; `(true, false)` and `(false)` orderings both unblock cleanly.
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
  ## Called after waitForBotThread confirms the bot is idle — prevents stale
  ## previous-round events leaking into the next round.
  while true:
    let (hasEvents, _) = gEventChan.tryRecv()
    if not hasEvents: break

proc startBotThread*() =
  ## Create the persistent bot thread on first call; signal a new round on every call.
  if not gBotThreadStarted:
    createThread(gBotThread, botThreadEntry)
    gBotThreadStarted = true
  gStartRoundChan.send(true)

proc waitForBotThread*() =
  ## Block until the bot thread finishes its current round loop (is back to idle).
  ## Does NOT join — the thread persists until shutdownBotThread().
  discard gRoundDoneChan.recv()

proc waitForBotThreadWhileServicingWs*(ws: SyncWebSocket) =
  ## Like waitForBotThread but interleaves ws.receiveWithTimeout so server pings
  ## are answered while the main thread waits at round/game boundaries.
  ## Any non-ping text frame received during the wait is stored in gPendingMsg
  ## for the receive loop to re-dispatch once this returns.
  ## ponytail: stores only the first such message; additional ones are dropped.
  ## Upgrade path: replace gPendingMsg with a seq if multiple messages can arrive.
  gPendingMsg = ""
  while true:
    let (done, _) = gRoundDoneChan.tryRecv()
    if done: return
    let (timedOut, msg) = ws.receiveWithTimeout(1_000)
    if not timedOut:
      if msg.len > 0 and gPendingMsg.len == 0:
        gPendingMsg = msg  # first unexpected message — main loop will re-dispatch
      elif msg.len == 0:
        return  # connection closed

proc shutdownBotThread*() =
  ## Send final shutdown to the bot thread and join it. Call once at process exit.
  if gBotThreadStarted:
    gStartRoundChan.send(false)
    joinThread(gBotThread)
    gBotThreadStarted = false
