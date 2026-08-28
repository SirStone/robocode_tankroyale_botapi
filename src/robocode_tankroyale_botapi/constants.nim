## Game constants for Robocode Tank Royale Nim bot API.
##
## This module defines all the physics constants, event priorities, and game
## configuration values used by the Tank Royale game engine. These values match
## the official Robocode Tank Royale specification.
##
## ## Event Priorities
##
## Events are dispatched in priority order (higher = processed first). You can
## override these at runtime using `setEventPriority`.
##
## | Priority | Constant | Value |
## |----------|----------|-------|
## | 150 | `PRIORITY_WON_ROUND` | Highest - round victory |
## | 140 | `PRIORITY_SKIPPED_TURN` | Skipped turn penalty |
## | 130 | `PRIORITY_TICK` | Regular tick event |
## | 120 | `PRIORITY_CUSTOM` | Custom events |
## | 110 | `PRIORITY_TEAM_MESSAGE` | Team messages |
## | 100 | `PRIORITY_BOT_DEATH` | Another bot died |
## | 90 | `PRIORITY_BULLET_HIT_WALL` | Bullet hit wall |
## | 80 | `PRIORITY_BULLET_HIT_BULLET` | Bullet hit bullet |
## | 70 | `PRIORITY_BULLET_HIT_BOT` | Bullet hit enemy bot |
## | 60 | `PRIORITY_BULLET_FIRED` | You fired a bullet |
## | 50 | `PRIORITY_HIT_BY_BULLET` | You were hit by a bullet |
## | 40 | `PRIORITY_HIT_WALL` | You hit a wall |
## | 30 | `PRIORITY_HIT_BOT` | You rammed another bot |
## | 20 | `PRIORITY_SCANNED_BOT` | You scanned a bot (lowest) |
## | 10 | `PRIORITY_DEATH` | You died |
##
## ## Physics Constants
##
## These control bot movement, shooting, and collision physics:
##
## - **Movement**: `MAX_SPEED` (8.0), `MAX_TURN_RATE` (10°/tick),
##   `ACCELERATION` (1.0), `DECELERATION` (-2.0)
## - **Gun**: `MAX_GUN_TURN_RATE` (20°/tick), `MAX_FIRE_POWER` (3.0),
##   `MIN_FIRE_POWER` (0.1), `STARTING_GUN_HEAT` (3.0)
## - **Radar**: `MAX_RADAR_TURN_RATE` (45°/tick), `RADAR_RADIUS` (1200)
## - **Collision**: `BOT_RADIUS` (18.0), `RAM_DAMAGE` (0.6),
##   `INACTIVITY_ZAP` (0.1 energy/tick when inactive)
##
## ## Game Types
##
## - `CLASSIC` ("classic") -- Standard free-for-all
## - `MELEE` ("melee") -- Many bots, last one standing
## - `ONE_VS_ONE` ("1v1") -- Duel mode
##
## ## Team Messaging Limits
##
## - `TEAM_MESSAGE_MAX_SIZE` (32768 bytes per message)
## - `MAX_NUMBER_OF_TEAM_MESSAGES_PER_TURN` (10 messages/turn)
##
## ## See Also
##
## - `utils.calcBulletSpeed` -- Calculate bullet velocity from firepower
## - `utils.calcGunHeat` -- Calculate gun heat from firepower
## - `bot.setEventPriority` -- Override event dispatch priority at runtime

const
  # Infinity helpers
  POSITIVE_INFINITY* = high(float)
  NEGATIVE_INFINITY* = low(float)

  # Event queue limits
  MAX_QUEUE_SIZE*    = 256
  MAX_EVENTS_AGE*    = 2
  MIN_VALUE*         = low(int32)

  # Event priorities (higher = processed first)
  PRIORITY_WON_ROUND*       = 150
  PRIORITY_SKIPPED_TURN*    = 140
  PRIORITY_TICK*            = 130
  PRIORITY_CUSTOM*          = 120
  PRIORITY_TEAM_MESSAGE*    = 110
  PRIORITY_BOT_DEATH*       = 100
  PRIORITY_BULLET_HIT_WALL* = 90
  PRIORITY_BULLET_HIT_BULLET* = 80
  PRIORITY_BULLET_HIT_BOT*  = 70
  PRIORITY_BULLET_FIRED*    = 60
  PRIORITY_HIT_BY_BULLET*   = 50
  PRIORITY_HIT_WALL*        = 40
  PRIORITY_HIT_BOT*         = 30
  PRIORITY_SCANNED_BOT*     = 20
  PRIORITY_DEATH*           = 10

  # Physics
  ACCELERATION*     = 1.0
  DECELERATION*     = -2.0
  ABS_DECELERATION* = 2.0

  MAX_SPEED*          = 8.0
  MAX_TURN_RATE*      = 10.0
  MAX_GUN_TURN_RATE*  = 20.0
  MAX_RADAR_TURN_RATE* = 45.0

  MAX_FIRE_POWER* = 3.0
  MIN_FIRE_POWER* = 0.1

  BOT_RADIUS*         = 18.0
  RADAR_RADIUS*       = 1200.0

  # Game physics
  INACTIVITY_ZAP*     = 0.1
  RAM_DAMAGE*         = 0.6
  STARTING_GUN_HEAT*  = 3.0

  # Game types
  CLASSIC*   = "classic"
  MELEE*     = "melee"
  ONE_VS_ONE* = "1v1"

  # Team messaging
  TEAM_MESSAGE_MAX_SIZE*              = 32768
  MAX_NUMBER_OF_TEAM_MESSAGES_PER_TURN* = 10
