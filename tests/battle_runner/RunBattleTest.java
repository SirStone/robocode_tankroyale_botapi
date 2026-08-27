import dev.robocode.tankroyale.runner.*;
import dev.robocode.tankroyale.client.model.*;
import java.util.List;
import java.util.Map;
import java.util.concurrent.ConcurrentHashMap;
import java.util.concurrent.atomic.AtomicInteger;
import java.util.logging.Level;
import java.util.logging.Logger;

/**
 * Integration test harness: runs BOT_DIR vs BOT_DIR (same bot, two instances).
 *
 * Env vars:
 *   BOT_DIR      path to bot directory (default: ../../sample_bots/MyFirstBot)
 *   TEST_ROUNDS  number of rounds (default: 3)
 *
 * Exits 0 if all rounds complete, 1 on error.
 */
public class RunBattleTest {

    static final Map<Integer, String> idToName = new ConcurrentHashMap<>();

    public static void main(String[] args) {
        Logger.getLogger("dev.robocode.tankroyale").setLevel(Level.WARNING);

        String botDir = System.getenv().getOrDefault("BOT_DIR", "../../sample_bots/MyFirstBot");
        int rounds = Integer.parseInt(System.getenv().getOrDefault("TEST_ROUNDS", "3"));

        System.out.printf("=== Battle test: %s vs %s (%d rounds) ===%n", botDir, botDir, rounds);

        AtomicInteger completedRounds = new AtomicInteger(0);

        try (var runner = BattleRunner.create(b -> b.embeddedServer().suppressServerOutput())) {
            var setup = BattleSetup.classic(s -> s.setNumberOfRounds(rounds));
            var bots = List.of(BotEntry.of(botDir), BotEntry.of(botDir));

            var owner = new Object();
            try (var handle = runner.startBattleAsync(setup, bots)) {

                handle.getOnGameStarted().on(owner, event -> {
                    System.out.println("=== GAME STARTED ===");
                    for (var p : event.getParticipants()) {
                        idToName.put(p.getId(), p.getName());
                        System.out.printf("  #%d  %s%n", p.getId(), p.getName());
                    }
                });

                handle.getOnRoundStarted().on(owner, event ->
                    System.out.printf("%n--- ROUND %d STARTED ---%n", event.getRoundNumber()));

                handle.getOnRoundEnded().on(owner, event -> {
                    int r = event.getRoundNumber();
                    completedRounds.set(r);
                    System.out.printf("--- ROUND %d ENDED (turn %d) ---%n", r, event.getTurnNumber());
                });

                var results = handle.awaitResults();
                System.out.printf("%n=== RESULTS (%d rounds) ===%n", results.getNumberOfRounds());
                for (var r : results.getResults()) {
                    System.out.printf("  #%d  %-25s  %d pts%n",
                        r.getRank(), r.getName(), r.getTotalScore());
                }
            }

            if (completedRounds.get() != rounds) {
                System.err.printf("FAIL: expected %d rounds, got %d%n", rounds, completedRounds.get());
                System.exit(1);
            }
            System.out.printf("%n=== PASS: all %d rounds completed ===%n", rounds);

        } catch (Exception e) {
            System.err.println("FAIL: " + e.getMessage());
            e.printStackTrace();
            System.exit(1);
        }
    }
}
