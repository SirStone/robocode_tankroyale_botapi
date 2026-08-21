## Math / geometry utilities for Robocode Tank Royale bot API.

import std/math
import ./constants

proc isNearZero*(value: float): bool {.inline.} =
  abs(value) < 0.00001

proc normalizeRelativeAngle*(angle: float): float =
  ## Normalise angle to [-180, 180).
  result = angle mod 360.0
  if result >= 180.0:
    result -= 360.0
  elif result < -180.0:
    result += 360.0

proc normalizeAbsoluteAngle*(angle: float): float {.inline.} =
  ## Normalise angle to [0, 360).
  (angle mod 360.0 + 360.0) mod 360.0

proc calcDeltaAngle*(targetAngle, sourceAngle: float): float {.inline.} =
  normalizeRelativeAngle(targetAngle - sourceAngle)

proc calcMaxTurnRate*(speed: float): float {.inline.} =
  ## Maximum body turn rate at a given speed.
  MAX_TURN_RATE - 0.75 * abs(speed.clamp(-MAX_SPEED, MAX_SPEED))

proc calcBulletSpeed*(firepower: float): float {.inline.} =
  20.0 - 3.0 * firepower.clamp(MIN_FIRE_POWER, MAX_FIRE_POWER)

proc calcGunHeat*(firepower: float): float {.inline.} =
  1.0 + firepower.clamp(MIN_FIRE_POWER, MAX_FIRE_POWER) / 5.0

proc directionTo*(fromX, fromY, toX, toY: float): float {.inline.} =
  normalizeAbsoluteAngle(180.0 * arctan2(toY - fromY, toX - fromX) / PI)

proc distanceTo*(fromX, fromY, toX, toY: float): float {.inline.} =
  let dx = toX - fromX
  let dy = toY - fromY
  sqrt(dx * dx + dy * dy)

proc bearingTo*(fromX, fromY, fromDir, toX, toY: float): float {.inline.} =
  normalizeRelativeAngle(directionTo(fromX, fromY, toX, toY) - fromDir)

# ---- Speed / distance helpers -----------------------------------------------

proc getMaxDeceleration(speed: float): float =
  let decelerationTime = speed / ABS_DECELERATION
  let accelerationTime = 1.0 - decelerationTime
  min(1.0, decelerationTime) * ABS_DECELERATION + max(0.0, accelerationTime) * ACCELERATION

proc getMaxSpeed(distance: float): float =
  let decelerationTime = max(1.0, ceil((sqrt(4.0 * 2.0 / ABS_DECELERATION * distance + 1.0) - 1.0) / 2.0))
  if decelerationTime == Inf: return MAX_SPEED
  let decelerationDistance = (decelerationTime / 2.0) * (decelerationTime - 1.0) * ABS_DECELERATION
  ((decelerationTime - 1.0) * ABS_DECELERATION) + ((distance - decelerationDistance) / decelerationTime)

proc getNewTargetSpeed*(maxSpeed, speed, distance: float): float =
  if distance < 0.0:
    return -getNewTargetSpeed(maxSpeed, -speed, -distance)
  let targetSpeed =
    if distance == Inf: maxSpeed
    else: min(maxSpeed, getMaxSpeed(distance))
  if speed >= 0.0:
    targetSpeed.clamp(speed - ABS_DECELERATION, speed + ACCELERATION)
  else:
    targetSpeed.clamp(speed - ACCELERATION, speed + getMaxDeceleration(-speed))

proc getDistanceTraveledUntilStop*(maxSpeed, speed: float): float =
  var s = abs(speed)
  var dist = 0.0
  while s > 0.0:
    s = getNewTargetSpeed(maxSpeed, s, 0.0)
    dist += s
  dist
