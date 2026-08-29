# Robocode Tank Royale — Nim Bot API

Welcome! This library lets you write battle tanks for [Robocode Tank Royale](https://robocode.dev) using the [Nim programming language](https://nim-lang.org).

Whether you are completely new to Robocode, new to Nim, or both — this guide will help you build your very first battle bot step by step!

---

## 🌟 What is Robocode Tank Royale?

[Robocode Tank Royale](https://robocode.dev) is an open-source programming game where you write software to control a virtual battle tank. Your tank competes against other player-written tanks in a real-time 2D arena.

- 🌐 **Official Website**: [https://robocode.dev](https://robocode.dev)
- 🐙 **Official GitHub Repository**: [github.com/robocode-dev/tank-royale](https://github.com/robocode-dev/tank-royale)

Every turn (30 turns per second by default), your code decides how far your body moves, how much your gun and radar turn, and whether to fire a bullet!

---

## ⚡ Why Nim for Tank Royale?

[Nim](https://nim-lang.org) is a modern programming language that looks and feels clean like Python, but compiles directly to native machine code like C++.

- 👑 **Official Website**: [https://nim-lang.org](https://nim-lang.org)
- 🐣 **Super Easy to Learn**: Python-like syntax without complex boilerplate.
- 📦 **Standalone Binary**: Compiles into a single executable file. Unlike Java, Python, or Node.js bots, a Nim bot doesn't require any runtime or virtual machine installed on the target machine!
- ⚡ **Fast Execution**: Outstanding performance so your bot never skips a turn.

---

## 🚀 Quick Start Guide

### Step 1: Install Nim and Nimble

Nimble is Nim's package manager (comes bundled with [Nim](https://nim-lang.org)).

- **Linux / macOS**: Open a terminal and run:
  ```bash
  curl https://nim-lang.org/choosenim/init.sh -sSf | sh
  ```
- **Windows**: Download and run the installer from [nim-lang.org/install_windows.html](https://nim-lang.org/install_windows.html).

Verify your installation by opening a new terminal and typing:
```bash
nim -v
nimble -v
```

---

### Step 2: Download Tank Royale

To test your bot visually, download the official Tank Royale GUI and server from the [Robocode Tank Royale GitHub repository](https://github.com/robocode-dev/tank-royale):
1. Go to [Tank Royale Releases on GitHub](https://github.com/robocode-dev/tank-royale/releases).
2. Download the latest `robocode-tankroyale-gui-...jar` (requires Java 11 or newer).
3. Run the GUI by double-clicking it or running `java -jar robocode-tankroyale-gui-*.jar`.

---

### Step 3: Create Your Bot Folder

Create a folder for your bot (for example, `MyFirstBot`). Every Tank Royale bot needs **4 files** with matching names inside its folder:

```
MyFirstBot/
├── MyFirstBot.nimble   # Nim package settings
├── MyFirstBot.json     # Bot metadata (name, author, version)
├── MyFirstBot.nim      # Your bot's source code
├── MyFirstBot.sh       # Startup script for Linux / macOS
└── MyFirstBot.cmd      # Startup script for Windows
```

---

### Step 4: Create Project Files

#### File 1: `MyFirstBot.nimble`
This tells Nim how to build your bot and what libraries it needs.

```nim
version     = "0.1.0"
author      = "Your Name"
description = "My first battle bot"
license     = "MIT"
bin         = @["MyFirstBot"]

requires "nim >= 2.0.0"
requires "robocode_tankroyale_botapi >= 1.0.7"
```

#### File 2: `MyFirstBot.json`
This tells the Tank Royale game manager about your bot's identity.

```json
{
  "name": "My First Bot",
  "version": "1.0",
  "authors": ["Your Name"],
  "description": "A fierce battle tank built with Nim!",
  "homepage": "",
  "countryCodes": ["US"],
  "gameTypes": ["classic", "melee", "1v1"],
  "platform": "Nim",
  "programmingLang": "Nim"
}
```

#### File 3: `MyFirstBot.sh` (Linux / macOS)
Make sure to make it executable later with `chmod +x MyFirstBot.sh`.

```bash
#!/bin/sh
cd -- "$(dirname -- "$0")"
exec "./MyFirstBot"
```

#### File 4: `MyFirstBot.cmd` (Windows)

```cmd
@echo off
cd /d "%~dp0"
MyFirstBot.exe
```

---

### Step 5: Write Your Bot Code (`MyFirstBot.nim`)

Here is a complete, beginner-friendly example of a battle tank:

```nim
import robocode_tankroyale_botapi

# 1. Define your custom bot type inheriting from Bot
type MyFirstBot = ref object of Bot

# 2. Overriding `run` -- this is called once when the round starts
method run(bot: MyFirstBot) =
  # Set custom appearance colors!
  setBodyColor(RED)
  setTurretColor(BLACK)
  setRadarColor(YELLOW)
  setBulletColor(RED)

  # Infinite loop: keep driving and scanning as long as the round is active
  while isRunning():
    forward(100)       # Drive forward 100 pixels/units
    turnGunLeft(360)   # Spin gun in a full circle to scan for enemies
    back(100)          # Drive backward 100 pixels/units
    turnGunLeft(360)   # Spin gun in a full circle again

# 3. Event: Called automatically whenever your radar detects an enemy tank
method onScannedBot(bot: MyFirstBot; e: ScannedBotEvent) =
  # Fire a bullet with power 2.0 (firepower ranges from 0.1 weak to 3.0 strong)
  fire(2.0)

# 4. Event: Called automatically if another tank shoots you
method onHitByBullet(bot: MyFirstBot; e: HitByBulletEvent) =
  # Turn perpendicular to the bullet direction to dodge incoming shots
  let bearing = calcBearing(e.bullet.direction)
  turnLeft(90 - bearing)

# 5. Program Entry Point
var bot = MyFirstBot()
start(bot, "MyFirstBot.json")
```

---

### Step 6: Build and Run Your Bot!

1. Open your terminal in your bot's folder (`MyFirstBot/`).
2. Build your bot binary:
   ```bash
   nimble build
   ```
   *(This generates the executable file `MyFirstBot` or `MyFirstBot.exe`)*.

3. Open the Tank Royale GUI:
   - Go to **Config** -> **Bot Directories**.
   - Add the parent directory containing your `MyFirstBot` folder.
   - Click **Refresh Bot List**.
   - Select `My First Bot` from the list and start a battle!

---

## 🧭 Understanding Tank Physics & Controls

### Tank Components
Your tank consists of three independent parts that can move and rotate separately:
- 🏎️ **Body**: Moves forward/backward and turns left/right.
- 🎯 **Gun**: Sits on top of the body and turns left/right to aim at enemies.
- 📡 **Radar**: Sits on top of the gun and rotates to scan for enemy tanks.

### Coordinate System & Angles
- **(0, 0)** is the top-left corner of the arena.
- **Angles** are measured in **degrees**:
  - `0°` = Up / North
  - `90°` = Right / East
  - `180°` = Down / South
  - `270°` = Left / West
- **Turn Direction**: Positive angles turn **clockwise** (right), negative angles turn **counter-clockwise** (left).

### Movement Commands
You can control your tank in two ways:

#### 1. Blocking Commands (Easiest for Beginners)
These procedures execute step-by-step and automatically wait for each movement to finish before continuing to the next line of code:
- `forward(100)` — Drive forward 100 units.
- `back(50)` — Drive backward 50 units.
- `turnLeft(90)` / `turnRight(90)` — Turn body by 90°.
- `turnGunLeft(360)` / `turnGunRight(360)` — Turn gun by 360°.
- `fire(2.0)` — Shoot a bullet with power 2.0 and wait 1 turn.

#### 2. Non-Blocking Setters (For Advanced Bots)
These set target values without waiting, allowing you to combine actions (drive, turn gun, and fire all in the same turn):
- `setForward(100)`
- `setTurnLeft(45)`
- `setTurnGunRight(90)`
- `setFire(2.0)`
- `go()` — Sends all queued commands to the server for the current turn.

---

## 🎨 SVG Debug Graphics

Want to visualize what your tank is "thinking"? You can draw debug shapes (lines, circles, text) directly onto the battle arena screen!

```nim
method run(bot: MyFirstBot) =
  while isRunning():
    # Draw a green radar circle around your bot
    setStrokeColor(GREEN)
    setStrokeWidth(1.5)
    drawCircle(getX(), getY(), RADAR_RADIUS)

    # Draw text above your tank
    setFillColor(WHITE)
    setFont("Arial", 14)
    drawText("Scanning...", getX() - 30, getY() - 30)

    go()
```

---

## 📚 Sample Bots Included

This repository includes several ready-to-run sample bots in the `sample_bots/` directory:
- **`MyFirstBot`**: Simple beginner bot showing basic movement and targeting.
- **`TrackFire`**: Locks gun onto scanned targets.
- **`Fire`**: Adjusts firepower based on distance to target.
- **`Walls`**: Hugs the arena perimeter.
- **`RamFire`**: Drives straight at enemies to ram them while firing.
- **`Corners`**: Moves to corners and waits for enemies.

---

## 🔗 Useful Links & Documentation

- 📘 **[Nim Bot API Documentation](https://SirStone.github.io/robocode_tankroyale_botapi/)**: Full API reference for all Nim types, events, and procedures.
- 🌐 **[Robocode Tank Royale Official Website](https://robocode.dev)**: General game rules, tutorials, and community.
- 🐙 **[Robocode Tank Royale GitHub Repository](https://github.com/robocode-dev/tank-royale)**: Official game engine, GUI, and protocol specs.
- 👑 **[Nim Programming Language Official Website](https://nim-lang.org)**: Nim language documentation, tutorials, and package directory.

---

## 📜 License

Distributed under the Apache 2.0 License. See `LICENSE` for details.
