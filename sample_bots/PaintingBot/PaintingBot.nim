## PaintingBot — demonstrates debug graphics by drawing a fading red circle
## at the last known position of a scanned bot.
##
## A sample bot originally made for Robocode by Pavel Savara.
## Remember to enable Graphical Debugging when running a battle.

import std/[os, math]
import ../../src/robocode_tankroyale_botapi

const botJsonPath = currentSourcePath().parentDir / "PaintingBot.json"

type PaintingBot = ref object of Bot
  scannedX:    float
  scannedY:    float
  scannedTime: int   ## Turn when the bot was last scanned; 0 = not yet scanned

method run(bot: PaintingBot) =
  bot.scannedTime = 0  # reset so no ghost circle bleeds in from a previous round
  while isRunning():
    forward(100)
    turnGunLeft(360)
    back(100)
    turnGunLeft(360)

method onScannedBot(bot: PaintingBot, e: ScannedBotEvent) =
  bot.scannedX    = e.x
  bot.scannedY    = e.y
  bot.scannedTime = e.turnNumber
  fire(1)

method onTick(bot: PaintingBot, e: TickEventForBot) =
  if bot.scannedTime == 0:
    return
  let deltaTime = e.turnNumber - bot.scannedTime
  let alpha     = max(0xFF - deltaTime * 16, 0)
  setFillColor(fromRgba(0xFF, 0x00, 0x00, uint8(alpha)))
  fillCircle(bot.scannedX, bot.scannedY, 20)

when isMainModule:
  var bot = PaintingBot()
  start(bot, botJsonPath)
