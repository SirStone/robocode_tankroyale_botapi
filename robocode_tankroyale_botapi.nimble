# Package
version       = "1.0.4"
author        = "Davide Cappellini"
description   = "Nim Bot API for Robocode Tank Royale — community-maintained"
license       = "Apache-2.0"
srcDir        = "src"
skipDirs      = @["sample_bots"]

# Dependencies
requires "nim >= 2.0.0"
requires "jsony >= 1.1.5"

task unit, "Run unit tests":
  exec "nim compile --run tests/test_val.nim"
  exec "nim compile --run tests/test_cmd.nim"
  exec "nim compile --run tests/test_evt.nim"
  exec "nim compile --run tests/test_mdl.nim"
  exec "nim compile --run tests/test_bot.nim"
  exec "nim compile --run tests/test_utl.nim"
  exec "nim compile --run tests/test_gfx.nim"
  exec "nim compile --run tests/test_tck.nim"

task fetch_test_data, "Download shared JSON test definitions from upstream Tank Royale repo":
  let baseUrl = "https://raw.githubusercontent.com/robocode-dev/tank-royale/main/bot-api/tests/shared/"
  let files = @[
    "basebot-defaults.json",
    "bot-math.json",
    "botinfo-validation.json",
    "bullet-state.json",
    "color-values.json",
    "constants.json",
    "event-priorities.json",
    "event-queue.json",
    "intent-validation.json",
    "movement-physics.json",
    "test-definition.schema.json",
  ]
  mkDir "tests/shared"
  for f in files:
    exec "curl -fsSL -o tests/shared/" & f & " " & baseUrl & f

task test, "Run all tests (unit + battle integration)":
  exec "nimble fetch_test_data"
  exec "nimble unit"
  when hostOS != "windows":
    exec "nimble build"
    exec "tests/battle_runner/run_battle_test.sh"
