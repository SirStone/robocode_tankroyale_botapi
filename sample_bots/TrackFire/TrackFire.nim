## TrackFire — sits still while tracking and firing at the nearest robot it detects.
##
## A sample bot originally made for Robocode by Mathew Nelson.

import std/os
import std/math
import ../../src/robocode_tankroyale_botapi

const botJsonPath = currentSourcePath().parentDir / "TrackFire.json"

type TrackFire = ref object of Bot

method run(bot: TrackFire) =
  setBodyColor("#FF69B4")   # hot pink
  setTurretColor("#FF69B4")
  setRadarColor("#FF69B4")
  setScanColor("#FF69B4")
  setBulletColor("#FF69B4")

  while isRunning():
    turnGunRight(10)  # radar rides on gun — scans automatically

method onScannedBot(bot: TrackFire, e: ScannedBotEvent) =
  let bearingFromGun = gunBearingTo(e.x, e.y)

  # Align the gun on the target
  turnGunLeft(bearingFromGun)

  # Fire if we're close enough and the gun is ready
  if abs(bearingFromGun) <= 3 and getGunHeat() == 0:
    fire(min(3.0 - abs(bearingFromGun), getEnergy() - 0.1))

  rescan()  # keep tracking

method onWonRound(bot: TrackFire, e: WonRoundEvent) =
  turnRight(36_000)  # victory dance

when isMainModule:
  var bot = TrackFire()
  start(bot, botJsonPath)
