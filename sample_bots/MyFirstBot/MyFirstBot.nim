## MyFirstBot — moves in a seesaw pattern and spins the gun at each end.
##
## A sample bot originally made for Robocode by Mathew Nelson.

import std/os
import ../../src/robocode_tankroyale_botapi

const botJsonPath = currentSourcePath().parentDir / "MyFirstBot.json"

type MyFirstBot = ref object of Bot

method run(bot: MyFirstBot) =
  while isRunning():
    forward(100)
    turnGunLeft(360)
    back(100)
    turnGunLeft(360)

method onScannedBot(bot: MyFirstBot, e: ScannedBotEvent) =
  fire(1)

method onHitByBullet(bot: MyFirstBot, e: HitByBulletEvent) =
  let bearing = calcBearing(e.bullet.direction)
  turnRight(90 - bearing)

when isMainModule:
  var bot = MyFirstBot()
  start(bot, botJsonPath)
