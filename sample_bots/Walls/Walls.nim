## Walls — navigates around the perimeter of the arena with gun pointed inward.
##
## A sample bot originally made for Robocode by Mathew Nelson.

import std/[os, math]
import ../../src/robocode_tankroyale_botapi

const botJsonPath = currentSourcePath().parentDir / "Walls.json"

type Walls = ref object of Bot
  peek:       bool   ## Whether to rescan after moving up a wall segment
  moveAmount: float  ## Length of each wall segment to travel

method run(bot: Walls) =
  setBodyColor("#000000")    # black
  setTurretColor("#000000")  # black
  setRadarColor("#FFA500")   # orange
  setBulletColor("#00FFFF")  # cyan
  setScanColor("#00FFFF")    # cyan

  bot.moveAmount = float(max(getArenaWidth(), getArenaHeight()))
  bot.peek = false

  # Align to the nearest wall
  turnRight(floorMod(getDirection(), 90.0))
  forward(bot.moveAmount)

  # Point the gun inward and begin wall-following
  bot.peek = true
  turnGunLeft(90)
  turnLeft(90)

  while isRunning():
    bot.peek = true
    forward(bot.moveAmount)
    bot.peek = false
    turnLeft(90)

method onHitBot(bot: Walls, e: BotHitBotEvent) =
  let bearing = bearingTo(e.x, e.y)
  if bearing > -90 and bearing < 90:
    back(100)
  else:
    forward(100)

method onScannedBot(bot: Walls, e: ScannedBotEvent) =
  fire(2)
  # Rescan to make sure no bot is on the next wall segment before moving
  if bot.peek:
    rescan()

when isMainModule:
  var bot = Walls()
  start(bot, botJsonPath)
