## Target — a stationary bot that moves when its energy drops below a threshold.
##
## A sample bot originally made for Robocode by Mathew Nelson.
## Demonstrates condition-based triggering (equivalent to addCustomEvent in Java).

import std/os
import ../../src/robocode_tankroyale_botapi

const botJsonPath = currentSourcePath().parentDir / "Target.json"

type Target = ref object of Bot
  trigger: int  ## Energy threshold at which to move

method run(bot: Target) =
  setBodyColor("#FFFFFF")  # white
  setTurretColor("#FFFFFF")
  setRadarColor("#FFFFFF")

  # Initially move when energy drops to 80
  bot.trigger = 80

  # Wait for each threshold and move when crossed.
  # waitFor keeps calling go() until the condition is true (or bot stops running).
  while isRunning():
    waitFor(proc(): bool = getEnergy() <= float(bot.trigger))
    bot.trigger -= 20
    echo "Ouch, down to " & $int(getEnergy() + 0.5) & " energy."
    turnRight(65)
    forward(100)

when isMainModule:
  var bot = Target()
  start(bot, botJsonPath)
