## MyFirstDroid — a droid bot: more energy, no radar. Follows orders from team leader.
##
## A sample bot originally made for Robocode by Mathew Nelson.
## Ported to Nim.

import std/[os, json]
import ../../src/robocode_tankroyale_botapi

const botJsonPath = currentSourcePath().parentDir / "MyFirstDroid.json"

type MyFirstDroid = ref object of Bot

method run(bot: MyFirstDroid) =
  echo "MyFirstDroid ready"
  while isRunning():
    go()  # onTeamMessage handles all logic

method onTeamMessage(bot: MyFirstDroid, e: TeamMessageEvent) =
  let data = parseJson(e.message)
  case data{"type"}.getStr
  of "Point":
    # Turn toward the target and fire hard
    let tx = data{"x"}.getFloat
    let ty = data{"y"}.getFloat
    turnRight(bearingTo(tx, ty))
    fire(3)
  of "RobotColors":
    setBodyColor(data{"body"}.getStr)
    setTracksColor(data{"tracks"}.getStr)
    setTurretColor(data{"turret"}.getStr)
    setGunColor(data{"gun"}.getStr)
    setRadarColor(data{"radar"}.getStr)
    setScanColor(data{"scan"}.getStr)
    setBulletColor(data{"bullet"}.getStr)
  else:
    discard

when isMainModule:
  var bot = MyFirstDroid()
  start(bot, botJsonPath)
