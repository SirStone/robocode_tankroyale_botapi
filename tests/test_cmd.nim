## TR-API-CMD Tier 1: movement clamping and fire validation.
## TR-API-CMD-001: setTurnRate/setGunTurnRate/setRadarTurnRate/setTargetSpeed clamp to limits.
## TR-API-CMD-002: setFire returns false when gunHeat > 0, energy < firepower, or invalid fp.

import std/[json, math]
import ../src/robocode_tankroyale_botapi/bot
import ../src/robocode_tankroyale_botapi/constants
import ../src/robocode_tankroyale_botapi/schemas

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

proc intentField(field: string): float =
  let j = parseJson(buildIntentJson())
  j[field].getFloat()

proc setupState(energy: float; gunHeat: float; speed: float = 0.0) =
  ## Inject bot state via signalTick (the only public path to set gState).
  var s: schemas.BotState
  s.energy   = energy
  s.gunHeat  = gunHeat
  s.speed    = speed
  var tick: TickEventForBot
  tick.botState = s
  signalTick(tick, @[])
  drainEventChan()

proc check(label: string; cond: bool) =
  if not cond:
    echo "FAIL: " & label
    quit 1
  echo "PASS: " & label

# ---------------------------------------------------------------------------
# Init
# ---------------------------------------------------------------------------

initGlobals()

# ---------------------------------------------------------------------------
# TR-API-CMD-001: movement clamping
# ---------------------------------------------------------------------------

# turnRate above max → clamped to MAX_TURN_RATE
setTurnRate(999.0)
check("TR-API-CMD-001 turnRate above max clamped", intentField("turnRate") == MAX_TURN_RATE)

# turnRate below min → clamped to -MAX_TURN_RATE
setTurnRate(-999.0)
check("TR-API-CMD-001 turnRate below min clamped", intentField("turnRate") == -MAX_TURN_RATE)

# turnRate in range → exact value
setTurnRate(5.0)
check("TR-API-CMD-001 turnRate in range exact", intentField("turnRate") == 5.0)

# gunTurnRate above max
setGunTurnRate(999.0)
check("TR-API-CMD-001 gunTurnRate above max clamped", intentField("gunTurnRate") == MAX_GUN_TURN_RATE)

setGunTurnRate(-999.0)
check("TR-API-CMD-001 gunTurnRate below min clamped", intentField("gunTurnRate") == -MAX_GUN_TURN_RATE)

setGunTurnRate(10.0)
check("TR-API-CMD-001 gunTurnRate in range exact", intentField("gunTurnRate") == 10.0)

# radarTurnRate above max
setRadarTurnRate(999.0)
check("TR-API-CMD-001 radarTurnRate above max clamped", intentField("radarTurnRate") == MAX_RADAR_TURN_RATE)

setRadarTurnRate(-999.0)
check("TR-API-CMD-001 radarTurnRate below min clamped", intentField("radarTurnRate") == -MAX_RADAR_TURN_RATE)

setRadarTurnRate(20.0)
check("TR-API-CMD-001 radarTurnRate in range exact", intentField("radarTurnRate") == 20.0)

# targetSpeed above max
setTargetSpeed(999.0)
check("TR-API-CMD-001 targetSpeed above max clamped", intentField("targetSpeed") == MAX_SPEED)

setTargetSpeed(-999.0)
check("TR-API-CMD-001 targetSpeed below min clamped", intentField("targetSpeed") == -MAX_SPEED)

setTargetSpeed(4.0)
check("TR-API-CMD-001 targetSpeed in range exact", intentField("targetSpeed") == 4.0)

# boundary: exactly at limits must not be clamped further
setTurnRate(MAX_TURN_RATE)
check("TR-API-CMD-001 turnRate at exact max", intentField("turnRate") == MAX_TURN_RATE)

setTurnRate(-MAX_TURN_RATE)
check("TR-API-CMD-001 turnRate at exact min", intentField("turnRate") == -MAX_TURN_RATE)

# ---------------------------------------------------------------------------
# TR-API-CMD-002: fire validation
# ---------------------------------------------------------------------------

# gunHeat > 0 → setFire returns false
setupState(energy = 100.0, gunHeat = 1.0)
check("TR-API-CMD-002 setFire fails when gunHeat > 0", not setFire(1.0))

# energy < firepower → setFire returns false
setupState(energy = 0.05, gunHeat = 0.0)
check("TR-API-CMD-002 setFire fails when energy < firepower", not setFire(1.0))

# energy == 0 → setFire returns false
setupState(energy = 0.0, gunHeat = 0.0)
check("TR-API-CMD-002 setFire fails when energy is zero", not setFire(0.1))

# valid state: energy sufficient and gunHeat == 0 → setFire returns true
setupState(energy = 100.0, gunHeat = 0.0)
check("TR-API-CMD-002 setFire succeeds with energy and no gunHeat", setFire(1.0))

# firepower below MIN_FIRE_POWER: clamped up to MIN_FIRE_POWER (0.1),
# still fires if energy >= 0.1 and gunHeat == 0
setupState(energy = 100.0, gunHeat = 0.0)
check("TR-API-CMD-002 setFire below min fp clamped and fires", setFire(0.001))

# firepower above MAX_FIRE_POWER: clamped down to MAX_FIRE_POWER (3.0),
# still fires if energy >= 3.0
setupState(energy = 100.0, gunHeat = 0.0)
check("TR-API-CMD-002 setFire above max fp clamped and fires", setFire(999.0))

# NaN firepower: clamp(NaN, lo, hi) in Nim returns lo; treated as MIN_FIRE_POWER
setupState(energy = 100.0, gunHeat = 0.0)
let nanResult = setFire(NaN)
# NaN clamped to MIN_FIRE_POWER (0.1), energy=100 > 0.1, gunHeat=0 → fires
check("TR-API-CMD-002 setFire NaN fp is clamped to min and fires", nanResult)

echo "All TR-API-CMD Tier 1 tests passed."

# ---------------------------------------------------------------------------
# TR-API-CMD-003: Radar commands — rescan and adjust flags
# ---------------------------------------------------------------------------
# Pure intent-state tests; no server required.
# setRescan() sets gIntentRescan=true which buildIntentJson() emits as "rescan":true (one-shot).
# adjustRadar/adjustGun flags are direct bool setters reflected in buildIntentJson().

block:
  initGlobals()

  # rescan: after setRescan(), buildIntentJson() must include "rescan":true
  setRescan()
  let j1 = parseJson(buildIntentJson())
  check("TR-API-CMD-003 setRescan sets rescan=true in intent",
    j1{"rescan"}.getBool(false) == true)

  # one-shot: after building, a second build must NOT carry rescan again
  let j2 = parseJson(buildIntentJson())
  check("TR-API-CMD-003 rescan is one-shot (cleared after buildIntentJson)",
    not j2.hasKey("rescan") or j2{"rescan"}.getBool(false) == false)

  # adjustGunForBodyTurn: flag written into intent when true
  setAdjustGunForBodyTurn(true)
  let j3 = parseJson(buildIntentJson())
  check("TR-API-CMD-003 adjustGunForBodyTurn=true emitted",
    j3{"adjustGunForBodyTurn"}.getBool(false) == true)

  # flag is persistent (not one-shot): still true on next build
  let j4 = parseJson(buildIntentJson())
  check("TR-API-CMD-003 adjustGunForBodyTurn persists across ticks",
    j4{"adjustGunForBodyTurn"}.getBool(false) == true)

  # clear the flag: not emitted when false
  setAdjustGunForBodyTurn(false)
  let j5 = parseJson(buildIntentJson())
  check("TR-API-CMD-003 adjustGunForBodyTurn=false not emitted",
    not j5.hasKey("adjustGunForBodyTurn") or j5{"adjustGunForBodyTurn"}.getBool(true) == false)

  # adjustRadarForBodyTurn
  setAdjustRadarForBodyTurn(true)
  let j6 = parseJson(buildIntentJson())
  check("TR-API-CMD-003 adjustRadarForBodyTurn=true emitted",
    j6{"adjustRadarForBodyTurn"}.getBool(false) == true)

  setAdjustRadarForBodyTurn(false)
  let j7 = parseJson(buildIntentJson())
  check("TR-API-CMD-003 adjustRadarForBodyTurn=false not emitted",
    not j7.hasKey("adjustRadarForBodyTurn") or j7{"adjustRadarForBodyTurn"}.getBool(true) == false)

  # adjustRadarForGunTurn (also toggles fireAssist)
  setAdjustRadarForGunTurn(true)
  let j8 = parseJson(buildIntentJson())
  check("TR-API-CMD-003 adjustRadarForGunTurn=true emitted",
    j8{"adjustRadarForGunTurn"}.getBool(false) == true)

  # negative: setRescan() not yet called → rescan absent from next intent
  let j9 = parseJson(buildIntentJson())
  check("TR-API-CMD-003 no rescan when setRescan not called",
    not j9.hasKey("rescan") or j9{"rescan"}.getBool(false) == false)

echo "PASS: TR-API-CMD-003 radar commands"
