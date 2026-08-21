## MyFirstLeader — scans for enemies and orders teammates to fire.
##
## A sample bot originally made for Robocode by Mathew Nelson.
## Ported to Nim.

import std/[os, json, math]
import ../../src/robocode_tankroyale_botapi

const botJsonPath = currentSourcePath().parentDir / "MyFirstLeader.json"

type MyFirstLeader = ref object of Bot

# Build a JSON string for the RobotColors message
proc robotColorsMsg(): string =
  $ %*{
    "type":   "RobotColors",
    "body":   "#FF0000",   # red
    "tracks": "#00FFFF",   # cyan
    "turret": "#FF0000",   # red
    "gun":    "#FFFF00",   # yellow
    "radar":  "#FF0000",   # red
    "scan":   "#FFFF00",   # yellow
    "bullet": "#FFFF00"    # yellow
  }

# Build a JSON string for a Point message
proc pointMsg(x, y: float): string =
  $ %*{"type": "Point", "x": x, "y": y}

method run(bot: MyFirstLeader) =
  # Apply team colors to self
  setBodyColor("#FF0000")    # red
  setTracksColor("#00FFFF")  # cyan
  setTurretColor("#FF0000")  # red
  setGunColor("#FFFF00")     # yellow
  setRadarColor("#FF0000")   # red
  setScanColor("#FFFF00")    # yellow
  setBulletColor("#FFFF00")  # yellow

  # Tell teammates to use the same color scheme
  broadcastTeamMessage(robotColorsMsg())

  # Spin radar continuously
  setTurnRadarLeft(Inf)

  while isRunning():
    forward(100)
    back(100)

method onScannedBot(bot: MyFirstLeader, e: ScannedBotEvent) =
  if isTeammate(e.scannedBotId):
    return
  broadcastTeamMessage(pointMsg(e.x, e.y))

method onHitByBullet(bot: MyFirstLeader, e: HitByBulletEvent) =
  let bulletBearing = calcBearing(e.bullet.direction)
  turnLeft(90 - bulletBearing)

when isMainModule:
  var bot = MyFirstLeader()
  start(bot, botJsonPath)
