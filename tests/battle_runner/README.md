# Battle Runner Test Harness

Integration test that spins up an embedded Tank Royale server and runs a real battle.

## Quick start

```sh
cd tests/battle_runner
./run_battle_test.sh
```

Or via nimble from repo root:

```sh
nimble test
```

## Env vars

| Variable         | Default                                      | Purpose                        |
|------------------|----------------------------------------------|--------------------------------|
| `BOT_DIR`        | `../../sample_bots/MyFirstBot`               | Bot directory (runs two instances) |
| `TEST_ROUNDS`    | `3`                                          | Number of rounds               |
| `TANK_ROYALE_JAR`| auto-detected under `/home/davide/Projects/tank-royale` | Runner JAR path |

## Testing a different bot

```sh
BOT_DIR=/path/to/MyBot TEST_ROUNDS=5 ./run_battle_test.sh
```

The harness runs `BOT_DIR` vs `BOT_DIR` (same bot, two instances). Exit code 0 = all rounds completed.
