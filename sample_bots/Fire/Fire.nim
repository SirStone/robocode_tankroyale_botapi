## Fire — sits still, rotates gun, fires when it sees a bot, moves when hit.
##
## A sample bot originally made for Robocode by Mathew Nelson.

import std/os
import ../../src/robocode_tankroyale_botapi

const botJsonPath = currentSourcePath().parentDir / "Fire.json"

type Fire = ref object of Bot
  dist: float  ## Distance to move when hit — alternates between positive and negative

method run(bot: Fire) =
  bot.dist = 50
  setBodyColor("#FFAA00")    # orange
  setGunColor("#FF7700")     # dark orange
  setTurretColor("#FF7700")  # dark orange
  setRadarColor("#FF0000")   # red
  setScanColor("#FF0000")    # red
  setBulletColor("#0088FF")  # light blue

  while isRunning():
    turnGunRight(5)

method onScannedBot(bot: Fire, e: ScannedBotEvent) =
  let distance = distanceTo(e.x, e.y)
  if distance < 50 and getEnergy() > 50:
    fire(3)
  else:
    fire(1)
  rescan()

method onHitByBullet(bot: Fire, e: HitByBulletEvent) =
  # Turn perpendicular to the incoming bullet, then move
  turnLeft(normalizeRelativeAngle(90 - (getDirection() - e.bullet.direction)))
  forward(bot.dist)
  bot.dist *= -1  # alternate forward / backward
  rescan()

method onHitBot(bot: Fire, e: BotHitBotEvent) =
  # Aim gun at the colliding bot and fire hard
  let gunBearing = normalizeRelativeAngle(directionTo(e.x, e.y) - getGunDirection())
  turnGunRight(gunBearing)
  fire(3)

when isMainModule:
  var bot = Fire()
  start(bot, botJsonPath)
