# robocode_tankroyale_botapi — Nim Bot API for Robocode Tank Royale

This is a continuation of the [My First Bot](https://robocode.dev/tutorial/my-first-bot.html) tutorial on robocode.dev. Nim bots compile to native binaries — no VM or interpreter required.

## Why Nim?

Nim reads and writes a lot like Python, so it is a comfortable place to start even if you have never used a compiled language before. When you build your bot, Nim turns your code into a single standalone program — no Python interpreter, no Java runtime, no Node.js required on the machine that runs it, just one file that you can run directly. That is what makes it stand out from the other Tank Royale bot languages: Java, Python, .NET, and TypeScript bots all need their runtime installed wherever they run, while a Nim bot is entirely self-contained the moment it is compiled. You write friendly, readable code and get a lean, fast program out the other end — a pretty great deal.

## Install Nim and Nimble

The recommended way is [choosenim](https://github.com/dom96/choosenim) — Nim's version manager, which installs both Nim and Nimble in one shot.

**Linux/macOS:**

```sh
curl https://nim-lang.org/choosenim/init.sh -sSf | sh
```

**Windows:** download the choosenim installer from https://nim-lang.org/install_windows.html

**Alternatives** (may not be the latest release): `brew install nim` (macOS), `apt install nim` (Debian/Ubuntu), `pacman -S nim` (Arch).

Nimble is bundled with Nim — no separate install needed. Verify your install:

```sh
nim --version
nimble --version
```

## Install the API and build

Install the Nim bot API via [Nimble](https://github.com/nim-lang/nimble):

```sh
nimble install robocode_tankroyale_botapi
```

You should see `robocode_tankroyale_botapi` listed with its version:

```sh
nimble list --installed | grep tankroyale
```

Then build your bot (from inside the bot directory):

```sh
nimble build
```

This produces a native binary — `MyFirstBot` on Linux/macOS, `MyFirstBot.exe` on Windows.

By default `nimble build` places the binary in the project root (the same directory as the `.nimble` file) — this is correct for the bot layout since the startup scripts reference `./MyFirstBot` in that same directory.

To compile to a different output directory, add `binDir = "bin"` to the `.nimble` file and update the startup scripts accordingly (`exec "./bin/MyFirstBot"` on Linux/macOS, `bin\MyFirstBot.exe` on Windows).

For an optimised release build:

```sh
nimble build -d:release
```

## Create a bot project

- Create a directory for your bot, e.g. `~/bots/MyFirstBot/` — all files share this name
- Register the directory in the Robocode GUI's **Bot Root Configuration**
- Create a `myFirstBot.nimble` file in that directory:

```nim
version     = "0.1.0"
author      = "Your Name"
description = "My first Tank Royale bot"
license     = "MIT"
bin         = @["MyFirstBot"]

requires "nim >= 2.0.0"
requires "robocode_tankroyale_botapi >= 1.0.1"
```

## Create the JSON config file

`MyFirstBot.json` — required fields are `name`, `version`, `authors`:

```json
{
  "name": "My First Bot",
  "version": "1.0",
  "authors": ["Your Name"],
  "description": "My first bot",
  "homepage": "",
  "countryCodes": ["us"],
  "gameTypes": ["classic", "melee", "1v1"],
  "platform": "Nim",
  "programmingLang": "Nim"
}
```

## Initial code — `MyFirstBot.nim`

```nim
import std/os
import robocode_tankroyale_botapi

const botJson = currentSourcePath().parentDir / "MyFirstBot.json"

type MyFirstBot = ref object of Bot
```

## The `run` method

```nim
method run(bot: MyFirstBot) =
  while isRunning():
    forward(100)
    turnGunRight(360)
    back(100)
    turnGunRight(360)
```

## Event handlers

```nim
method onScannedBot(bot: MyFirstBot, e: ScannedBotEvent) =
  fire(1)

method onHitByBullet(bot: MyFirstBot, e: HitByBulletEvent) =
  let bearing = calcBearing(e.bullet.direction)
  turnLeft(90 - bearing)
```

## The main entry point

```nim
when isMainModule:
  var bot = MyFirstBot()
  start(bot, botJson)
```

## Putting it all together

Full combined listing:

```nim
import std/os
import robocode_tankroyale_botapi

const botJson = currentSourcePath().parentDir / "MyFirstBot.json"

type MyFirstBot = ref object of Bot

method run(bot: MyFirstBot) =
  while isRunning():
    forward(100)
    turnGunRight(360)
    back(100)
    turnGunRight(360)

method onScannedBot(bot: MyFirstBot, e: ScannedBotEvent) =
  fire(1)

method onHitByBullet(bot: MyFirstBot, e: HitByBulletEvent) =
  let bearing = calcBearing(e.bullet.direction)
  turnLeft(90 - bearing)

when isMainModule:
  var bot = MyFirstBot()
  start(bot, botJson)
```

## Startup scripts

The Robocode booter launches bots via shell scripts. Create these two files:

**`MyFirstBot.sh`** (Linux/macOS):

```sh
#!/bin/sh
cd -- "$(dirname -- "$0")"
exec "./MyFirstBot"
```

Make it executable: `chmod 755 MyFirstBot.sh`

**`MyFirstBot.cmd`** (Windows):

```
@echo off
cd /d "%~dp0"
MyFirstBot.exe
```

## Packaging your bot

Compile for your target platform, then zip the following files:

- `MyFirstBot.nim`
- `MyFirstBot.json`
- `MyFirstBot.sh`
- `MyFirstBot.cmd`
- `MyFirstBot` _(compiled binary — Linux/macOS)_
- `MyFirstBot.exe` _(compiled binary — Windows)_
- `README.md` _(optional)_

Upload the zip to share your bot.

## Bot Secrets

If you're connecting to a server that requires authentication, set the `BOT_SECRETS` environment variable before launching:

**bash:**

```sh
export BOT_SECRETS=my-secret
```

**cmd:**

```
set BOT_SECRETS=my-secret
```

**PowerShell:**

```powershell
$env:BOT_SECRETS = "my-secret"
```

## API Reference

Docs not yet published — see source in `src/`.
