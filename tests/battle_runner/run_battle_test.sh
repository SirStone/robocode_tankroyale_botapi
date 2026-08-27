#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# ── JAR location ──────────────────────────────────────────────────────────────
if [ -n "${TANK_ROYALE_JAR:-}" ] && [ -f "$TANK_ROYALE_JAR" ]; then
    JAR="$TANK_ROYALE_JAR"
else
    JAR="/home/davide/Projects/tank-royale/runner/examples/lib/robocode-tankroyale-runner.jar"
    if [ ! -f "$JAR" ]; then
        JAR="$(find /home/davide/Projects/tank-royale -name "robocode-tankroyale-runner*.jar" 2>/dev/null | head -1)"
    fi
fi

if [ ! -f "$JAR" ]; then
    echo "ERROR: runner JAR not found. Set TANK_ROYALE_JAR env var." >&2
    exit 1
fi

export BOT_DIR="${BOT_DIR:-$REPO_ROOT/sample_bots/MyFirstBot}"
export TEST_ROUNDS="${TEST_ROUNDS:-3}"

# ── 1. Compile MyFirstBot ─────────────────────────────────────────────────────
BOT_BIN="$BOT_DIR/MyFirstBot"
if [ ! -x "$BOT_BIN" ]; then
    echo ">>> Compiling MyFirstBot..."
    nim c --threads:on --mm:orc --hints:off -o:"$BOT_BIN" "$BOT_DIR/MyFirstBot.nim"
fi

# ── 2. Compile and run RunBattleTest.java ─────────────────────────────────────
cd "$SCRIPT_DIR"

echo ">>> Compiling RunBattleTest.java..."
javac -cp "$JAR" RunBattleTest.java

echo ">>> Running battle ($TEST_ROUNDS rounds)..."
java -cp ".:$JAR" RunBattleTest
EXIT_CODE=$?

if [ $EXIT_CODE -eq 0 ]; then
    echo ">>> PASS"
else
    echo ">>> FAIL (exit $EXIT_CODE)" >&2
fi
exit $EXIT_CODE
