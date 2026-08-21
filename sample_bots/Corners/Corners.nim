## Corners — moves to a corner and sweeps the gun back and forth.
## If it dies early, it switches corner for the next round.
##
## A sample bot originally made for Robocode by Mathew Nelson.

import std/[os, random]
import ../../src/robocode_tankroyale_botapi

const botJsonPath = currentSourcePath().parentDir / "Corners.json"

var corner = 90 * rand(3)  # random starting corner (0, 90, 180, or 270)

type Corners = ref object of Bot
  enemies:         int
  stopWhenSeeEnemy: bool

proc smartFire(distance: float) =
  if distance > 200 or getEnergy() < 15:
    fire(1)
  elif distance > 50:
    fire(2)
  else:
    fire(3)

proc goCorner(bot: Corners) =
  bot.stopWhenSeeEnemy = false
  turnLeft(calcBearing(float(corner)))
  bot.stopWhenSeeEnemy = true
  forward(5000)
  turnLeft(90)
  forward(5000)
  turnGunLeft(90)

method run(bot: Corners) =
  setBodyColor("#FF0000")   # red
  setTurretColor("#000000") # black
  setRadarColor("#FFFF00")  # yellow
  setBulletColor("#00FF00") # green
  setScanColor("#00FF00")   # green

  bot.enemies = getEnemyCount()

  goCorner(bot)

  var gunIncrement = 3.0
  while isRunning():
    for i in 0 ..< 30:
      turnGunLeft(gunIncrement)
    gunIncrement = -gunIncrement

method onScannedBot(bot: Corners, e: ScannedBotEvent) =
  let distance = distanceTo(e.x, e.y)
  if bot.stopWhenSeeEnemy:
    stop()
    smartFire(distance)
    rescan()
    resume()
  else:
    smartFire(distance)

method onDeath(bot: Corners, e: BotDeathEvent) =
  if bot.enemies == 0:
    return
  if getEnemyCount().float / bot.enemies.float >= 0.75:
    corner = (corner + 90) mod 360
    echo "I died and did poorly... switching corner to " & $corner
  else:
    echo "I died but did well. I will still use corner " & $corner

when isMainModule:
  randomize()
  var bot = Corners()
  start(bot, botJsonPath)
