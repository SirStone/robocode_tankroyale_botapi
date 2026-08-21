## HelloWorld bot — connects, says hello, fires, moves in a square.

import std/os
import ../../src/robocode_tankroyale_botapi

## Embed the absolute path to HelloWorld.json at compile time so the bot
## always finds it regardless of working directory or getAppDir() quirks.
const botJsonPath = currentSourcePath().parentDir / "HelloWorld.json"

type HelloWorld = ref object of Bot

method run(bot: HelloWorld) =
  echo "HelloWorld bot started (round ", getRound(), ")"
  setBodyColor("#FF0000")
  setTurretColor("#FF0000")
  setRadarColor("#FFFFFF")

  while isRunning():
    forward(100)
    turnGunRight(360)
    forward(100)
    turnRight(90)

method onScannedBot(bot: HelloWorld, e: ScannedBotEvent) =
  fire(2)

method onHitBot(bot: HelloWorld, e: BotHitBotEvent) =
  if e.rammed:
    back(50)
  else:
    let bearing = bearingTo(e.x, e.y)
    if bearing > -90 and bearing < 90:
      back(50)
    else:
      forward(50)

method onHitWall(bot: HelloWorld, e: BotHitWallEvent) =
  back(50)
  turnRight(30)

when isMainModule:
  var bot = HelloWorld()
  start(bot, botJsonPath)
