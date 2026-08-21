## SpinBot — continuously circles while firing at maximum power.
##
## A sample bot originally made for Robocode by Mathew Nelson.

import std/os
import ../../src/robocode_tankroyale_botapi

const botJsonPath = currentSourcePath().parentDir / "SpinBot.json"

type SpinBot = ref object of Bot

method run(bot: SpinBot) =
  setBodyColor("#0000FF")   # blue
  setTurretColor("#0000FF") # blue
  setRadarColor("#000000")  # black
  setScanColor("#FFFF00")   # yellow

  while isRunning():
    setTurnRight(10_000)
    setMaxSpeed(5)
    forward(10_000)

method onScannedBot(bot: SpinBot, e: ScannedBotEvent) =
  fire(3)

method onHitBot(bot: SpinBot, e: BotHitBotEvent) =
  let bearing = calcBearing(directionTo(e.x, e.y))
  if bearing > -10 and bearing < 10:
    fire(3)
  if e.rammed:
    turnRight(10)

when isMainModule:
  var bot = SpinBot()
  start(bot, botJsonPath)
