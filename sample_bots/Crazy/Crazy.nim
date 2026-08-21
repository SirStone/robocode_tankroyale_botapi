## Crazy — zigzags wildly while firing at any bot it scans.
##
## A sample bot originally made for Robocode by Mathew Nelson.

import std/os
import ../../src/robocode_tankroyale_botapi

const botJsonPath = currentSourcePath().parentDir / "Crazy.json"

type Crazy = ref object of Bot
  movingForward: bool

proc reverseDirection(bot: Crazy) =
  if bot.movingForward:
    setBack(40000)
    bot.movingForward = false
  else:
    setForward(40000)
    bot.movingForward = true

method run(bot: Crazy) =
  setBodyColor("#00C800")   # lime
  setTurretColor("#009632") # green
  setRadarColor("#006464")  # dark cyan
  setBulletColor("#FFFF64") # yellow
  setScanColor("#FFC8C8")   # light red

  while isRunning():
    setForward(40000)
    bot.movingForward = true
    setTurnLeft(90)
    waitFor(proc(): bool = getTurnRemaining() == 0)
    setTurnRight(180)
    waitFor(proc(): bool = getTurnRemaining() == 0)
    setTurnLeft(180)
    waitFor(proc(): bool = getTurnRemaining() == 0)

method onHitWall(bot: Crazy, e: BotHitWallEvent) =
  reverseDirection(bot)

method onScannedBot(bot: Crazy, e: ScannedBotEvent) =
  fire(1)

method onHitBot(bot: Crazy, e: BotHitBotEvent) =
  if e.rammed:
    reverseDirection(bot)

when isMainModule:
  var bot = Crazy()
  start(bot, botJsonPath)
