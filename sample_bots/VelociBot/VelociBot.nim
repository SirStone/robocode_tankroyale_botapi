## VelociBot — example bot demonstrating how to use turn rates.
##
## A sample bot originally made for Robocode by Joshua Galecki.

import std/os
import ../../src/robocode_tankroyale_botapi

const botJsonPath = currentSourcePath().parentDir / "VelociBot.json"

type VelociBot = ref object of Bot
  turnCounter: int

method run(bot: VelociBot) =
  bot.turnCounter = 0
  setGunTurnRate(15)

  while isRunning():
    if bot.turnCounter mod 64 == 0:
      # Straighten out in case we were hit by a bullet (ends turning)
      setTurnRate(0)
      # Go forward at speed 4
      setTargetSpeed(4)

    if bot.turnCounter mod 64 == 32:
      # Go backwards, faster
      setTargetSpeed(-6)

    inc bot.turnCounter
    go()

method onScannedBot(bot: VelociBot, e: ScannedBotEvent) =
  fire(1)

method onHitByBullet(bot: VelociBot, e: HitByBulletEvent) =
  # Turn to confuse the other bots
  setTurnRate(5)

method onHitWall(bot: VelociBot, e: BotHitWallEvent) =
  # Move away from the wall by reversing the current target speed
  setTargetSpeed(-1 * getTargetSpeed())

when isMainModule:
  var bot = VelociBot()
  start(bot, botJsonPath)
