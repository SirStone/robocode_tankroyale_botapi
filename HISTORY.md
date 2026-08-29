# History

This package was extracted from the `nim` branch of [SirStone/tank-royale](https://github.com/SirStone/tank-royale) (a fork of [robocode-dev/tank-royale](https://github.com/robocode-dev/tank-royale)).

## Development timeline

- **Issues #1–#6 (Wayfinder Map #1):** Behavioral parity — fixed one-tick pipeline delay via three-thread model (main=WS reader+processTurn, bot=user logic+events, sender=WS writer). All 8 sample bots passed battle test.
- **Issues #7–#23 (Wayfinder Map #7):** Full Java API parity — priority event queue, interruptibility, custom conditions/events, Color type, getters/setters/math helpers, team messaging, stdOut/stdErr, InitialPosition, SVG debug graphics, Droid support, API encapsulation, BotListUpdate handling.
- **Issue #24:** Ported 14 battle-tested bug fixes from SirRoboGarage — all addressing SIGSEGV crashes from ORC GC + threads:on (cross-thread realloc of heap blocks owned by dead thread allocators). Includes Channel-based event passing, static array buffers, signalStop drain, robust sender thread, debug log opt-in.
- **Release 1.0.6:** Bug fixes — emit a `viewBox` on debug-graphics SVG so the GUI (jsvg) renders it; don't deadlock on game end so a bot can join the next game on the same connection; survive a silent mid-fight match restart; proper `<svg>` root element + WS keepalive at round boundaries; drop the redundant `nimble build` step from the `test` task.

## Architecture

- **3 threads:** main (WebSocket reader + processTurn), bot (user logic + events), sender (WebSocket writer)
- **Static arrays** for cross-thread buffers (event queue, SVG graphics, intent stdout/stderr/team messages) to avoid ORC GC cross-thread realloc
- **Channels** for thread communication (tick signals, pending events, intents)

## Key decisions

- Independent versioning (not tracking upstream Tank Royale versions)
- Community Bot API tier per [ADR-0045](https://github.com/robocode-dev/tank-royale/blob/main/docs/decisions/0045-official-bot-api-language-set.md)
- Test parity tracked against upstream [TEST-REGISTRY.md](https://github.com/robocode-dev/tank-royale/blob/main/bot-api/tests/TEST-REGISTRY.md)
