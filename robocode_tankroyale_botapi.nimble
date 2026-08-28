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
  exec "nim compile --run tests/test_graphics_escape.nim"
  exec "nim compile --run tests/test_gfx.nim"

task test, "Run all tests (unit + battle integration)":
  exec "nimble unit"
  exec "nimble build"
  exec "tests/battle_runner/run_battle_test.sh"
