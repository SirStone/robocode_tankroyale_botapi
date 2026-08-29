# Test Infrastructure

This project includes both fast unit tests and integration tests via a battle harness. Use these when developing the API or testing bots.

## Unit Tests

Fast, in-process Nim tests using `nim compile --run`:

```sh
nimble unit
```

Runs all `tests/test_*.nim` files. For example:

```sh
tests/test_graphics_escape.nim
```

Test files are standard Nim — compile and execute directly, no external harness needed. Add new tests by creating `tests/test_<name>.nim` and the `unit` task will pick them up.

## Integration Tests

Full battle harness that compiles a bot, starts an embedded Tank Royale server, and runs a real battle:

```sh
nimble test
```

This runs:
1. All unit tests (`nimble unit`)
2. API build (`nimble build`)
3. Battle integration harness (`tests/battle_runner/run_battle_test.sh`)

Exit code 0 means all rounds completed successfully.

### Battle Runner Requirements

The battle harness needs:

- **Tank Royale runner JAR**: `robocode-tankroyale-runner.jar`
  - Auto-detected under `/home/davide/Projects/tank-royale` by default
  - Override with `TANK_ROYALE_JAR` environment variable
  - Get it from [Tank Royale releases](https://github.com/robocode-dev/tank-royale)

- **A bot to test**: defaults to `sample_bots/MyFirstBot`
  - Override with `BOT_DIR` environment variable (runs the bot against itself)

### Environment Variables

| Variable         | Default                            | Purpose                                  |
|------------------|------------------------------------|------------------------------------------|
| `TANK_ROYALE_JAR`| auto-detected                      | Path to `robocode-tankroyale-runner.jar` |
| `BOT_DIR`        | `sample_bots/MyFirstBot`           | Bot directory (runs two instances)       |
| `TEST_ROUNDS`    | `3`                                | Number of rounds to play                 |

### Testing a Different Bot

```sh
BOT_DIR=/path/to/MyBot TEST_ROUNDS=5 nimble test
```

Or run the battle harness directly:

```sh
cd tests/battle_runner
BOT_DIR=/path/to/MyBot TEST_ROUNDS=5 ./run_battle_test.sh
```

The harness compiles the bot (if needed) and runs `BOT_DIR` vs `BOT_DIR` (same bot, two instances, to verify a bot can run multiple times safely).

## Agent skills

### Issue tracker

Issues are tracked on GitHub Issues (via `gh` CLI). See `docs/agents/issue-tracker.md`.

### Triage labels

Default label vocabulary (`needs-triage`, `needs-info`, `ready-for-agent`, `ready-for-human`, `wontfix`). See `docs/agents/triage-labels.md`.

### Domain docs

Single-context layout: `CONTEXT.md` + `docs/adr/` at repo root. See `docs/agents/domain.md`.

## Coding Standards

### Build profiles and checks

Nim's default behavior gives us a clean three-tier profile with no config overrides:

| Build | `assert` | `doAssert` | Runtime checks | Stack traces |
|-------|----------|------------|----------------|--------------|
| debug (none) | ✅ active | ❌ forbidden | all on | on |
| `-d:release` | ✅ active | ❌ forbidden | all on | off |
| `-d:danger` | stripped | ❌ forbidden | stripped | off |

- **`assert`** is for internal invariants — conditions that can only be false due to a bug in *our* code. These fire in debug and release (catch bugs early), and are stripped only in `-d:danger` (max speed).
- **`doAssert`** is **banned** in this codebase. Since release keeps `assert` active, `assert` already covers the "important invariant" role. `doAssert` would add an unstrippable check in `-d:danger`, violating the max-speed requirement.
- **External conditions** (network failures, malformed server input, user bot exceptions) must use `try/except` with proper exception types — never `assert`/`doAssert`. External failures aren't bugs; they're expected runtime conditions.

### Decision rule for checks

```
Is the condition driven by external input (network, server, user code)?
  → YES: use try/except + exception (e.g. WebSocketError, CatchableError)
  → NO:  Is it an internal invariant that should never be false?
           → YES: use assert (fires in debug+release, stripped in danger)
           → NO:  not a check, just normal code
```

Never use `doAssert`.
