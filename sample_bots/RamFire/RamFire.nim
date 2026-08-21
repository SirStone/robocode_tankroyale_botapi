## RamFire — actively seeks out opponents, rams them, and fires accordingly.
##
## A sample bot originally made for Robocode by Mathew Nelson.

import std/os
import ../../src/robocode_tankroyale_botapi

const botJsonPath = currentSourcePath().parentDir / "RamFire.json"

type RamFire = ref object of Bot
  turnDirection: int  ## 1 = counterclockwise, -1 = clockwise

proc turnToFaceTarget(bot: RamFire; x, y: float) =
  ## Turn to face (x, y) and update the default spin direction based on bearing.
  let bearing = bearingTo(x, y)
  bot.turnDirection = if bearing >= 0: 1 else: -1
  turnLeft(bearing)

method run(bot: RamFire) =
  bot.turnDirection = 1
  setBodyColor("#999999")    # lighter gray
  setTurretColor("#888888")  # gray
  setRadarColor("#666666")   # dark gray

  while isRunning():
    turnRight(float(5 * bot.turnDirection))

method onScannedBot(bot: RamFire, e: ScannedBotEvent) =
  bot.turnToFaceTarget(e.x, e.y)
  forward(distanceTo(e.x, e.y) + 5)
  rescan()

method onHitBot(bot: RamFire, e: BotHitBotEvent) =
  bot.turnToFaceTarget(e.x, e.y)
  # Fire just below kill threshold so bonus ram points still apply
  if e.energy > 16:
    fire(3)
  elif e.energy > 10:
    fire(2)
  elif e.energy > 4:
    fire(1)
  elif e.energy > 2:
    fire(0.5)
  elif e.energy > 0.4:
    fire(0.1)
  forward(40)  # ram again

when isMainModule:
  var bot = RamFire()
  start(bot, botJsonPath)
