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
