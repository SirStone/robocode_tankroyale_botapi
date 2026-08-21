## Game constants for Robocode Tank Royale Nim bot API

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
