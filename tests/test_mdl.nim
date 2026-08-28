## TR-API-MDL Tier 1: BulletState data model tests.
## Test cases derived from tests/shared/bullet-state.json.
import ../src/robocode_tankroyale_botapi/utils

# TR-API-MDL-001: calcBulletSpeed — positive cases (from bullet-state.json)

# power 0.0 → clamped to MIN_FIRE_POWER (0.1) → 20 - 3*0.1 = 19.7
assert calcBulletSpeed(0.0) == 19.7, "TR-API-MDL-001-speed-0.0"
assert calcBulletSpeed(0.1) == 19.7, "TR-API-MDL-001-speed-0.1"
assert calcBulletSpeed(0.5) == 18.5, "TR-API-MDL-001-speed-0.5"
assert calcBulletSpeed(1.0) == 17.0, "TR-API-MDL-001-speed-1.0"
assert calcBulletSpeed(2.0) == 14.0, "TR-API-MDL-001-speed-2.0"
assert calcBulletSpeed(3.0) == 11.0, "TR-API-MDL-001-speed-3.0"

# TR-API-MDL-001: calcBulletSpeed — negative cases (boundary / out-of-range)
# power > MAX_FIRE_POWER (3.0) → clamped to 3.0 → speed still 11.0
assert calcBulletSpeed(4.0) == 11.0, "TR-API-MDL-001-speed-4.0-clamped"
# negative power → clamped to MIN_FIRE_POWER (0.1) → speed still 19.7
assert calcBulletSpeed(-1.0) == 19.7, "TR-API-MDL-001-speed-neg-clamped"

echo "PASS: TR-API-MDL-001 calcBulletSpeed"
