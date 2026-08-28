## Schema types for Robocode Tank Royale protocol messages.
##
## This module defines all the data types used in the Tank Royale protocol.
## These types mirror the official YAML schemas and are used for:
##
## - **Server → Bot messages**: Events, game state, tick data
## - **Bot → Server messages**: Intents, handshake, ready signals
## - **Shared types**: Game setup, bot state, bullet state, results
##
## Most of these types are used internally by the API. You typically interact
## with them through the event handler methods in your `Bot` subtype (e.g.,
## `onScannedBot`, `onHitByBullet`, `onTick`).
##
## ## Type Categories
##
### Shared / Embedded Types
##
## - `InitialPosition` -- Optional starting position for your bot
## - `GameSetup` -- Game configuration (arena size, rules, physics)
## - `BotState` -- Your bot's state each tick (position, energy, heading, etc.)
## - `BulletState` -- Bullet info (position, velocity, owner, power)
## - `ResultsForBot` -- Round results (rank, score breakdown)
## - `TeamMessage` -- Team communication payload
##
### Connection Events
##
## - `ConnectedEvent` -- Fired in `onConnected`
## - `DisconnectedEvent` -- Fired in `onDisconnected`
## - `ConnectionErrorEvent` -- Fired in `onConnectionError`
##
### Game Lifecycle Events
##
## - `ServerHandshake` -- Initial server connection info
## - `GameStartedEventForBot` -- Fired in `onGameStarted`
## - `RoundStartedEvent` -- Fired in `onRoundStarted`
## - `RoundEndedEventForBot` -- Fired in `onRoundEnded`
## - `GameEndedEventForBot` -- Fired in `onGameEnded`
## - `GameAbortedEvent` -- Fired in `onGameAborted`
## - `SkippedTurnEvent` -- Fired in `onSkippedTurn`
##
### Tick Events (inside `TickEventForBot.events`)
##
## - `BotDeathEvent` -- Another bot died (`onBotDeath`)
## - `BotHitBotEvent` -- You rammed a bot (`onHitBot`)
## - `BotHitWallEvent` -- You hit a wall (`onHitWall`)
## - `BulletFiredEvent` -- You fired (`onBulletFired`)
## - `BulletHitBotEvent` -- Your bullet hit a bot (`onBulletHit`)
## - `BulletHitBulletEvent` -- Bullet collision (`onBulletHitBullet`)
## - `BulletHitWallEvent` -- Bullet hit wall (`onBulletHitWall`)
## - `HitByBulletEvent` -- You were hit (`onHitByBullet`)
## - `ScannedBotEvent` -- Radar scan (`onScannedBot`)
## - `WonRoundEvent` -- You won the round (`onWonRound`)
## - `TeamMessageEvent` -- Teammate message (`onTeamMessage`)
## - `TickEventForBot` -- Main tick event (`onTick`)
##
### Bot → Server Messages (mostly internal)
##
## - `BotHandshake` -- Sent during connection
## - `BotReady` -- Sent when ready for round
## - `BotIntent` -- Your commands each tick (built by `buildIntentJson`)
##
## ## Accessing Data in Event Handlers
##
## When you override event handlers, you receive typed event objects:
##
## ```nim
## method onScannedBot(bot: MyBot; e: ScannedBotEvent) =
##   echo "Scanned bot " & $e.scannedBotId & " at " & $e.x & ", " & $e.y
##   echo "Energy: " & $e.energy & ", Speed: " & $e.speed
##   
## method onHitByBullet(bot: MyBot; e: HitByBulletEvent) =
##   echo "Ouch! Damage: " & $e.damage
##   echo "Bullet power: " & $e.bullet.power
## ```
##
## ## See Also
##
## - `bot.Bot` -- Base class with all event handler methods
## - `event_queue.BotEvent` -- Typed event wrapper for priority dispatch
## - `json_parse.parseBotEvent` -- Internal JSON parsing

import ./color

type
  # ---- Shared / embedded types -----------------------------------------------

  InitialPosition* = object
    ## Optional starting position for your bot.
    ## Set in your bot's JSON config or BotInfo.
    x*:         float  ## X coordinate
    y*:         float  ## Y coordinate
    direction*: float  ## Initial heading in degrees [0, 360)

  GameSetup* = object
    ## Game configuration received at game start.
    ## Available via `getGameSetup()` or in `onGameStarted`.
    gameType*:                     string  ## "classic", "melee", or "1v1"
    arenaWidth*:                   int     ## Arena width in units
    isArenaWidthLocked*:           bool    ## Whether width can be changed
    arenaHeight*:                  int     ## Arena height in units
    isArenaHeightLocked*:          bool    ## Whether height can be changed
    minNumberOfParticipants*:      int     ## Minimum bots to start
    isMinNumberOfParticipantsLocked*: bool
    maxNumberOfParticipants*:      int     ## Maximum bots allowed
    isMaxNumberOfParticipantsLocked*: bool
    numberOfRounds*:               int     ## Total rounds in this game
    isNumberOfRoundsLocked*:       bool
    gunCoolingRate*:               float   ## Gun heat cooled per tick (default 0.1)
    isGunCoolingRateLocked*:       bool
    maxInactivityTurns*:           int     ## Turns before inactivity damage
    isMaxInactivityTurnsLocked*:   bool
    turnTimeout*:                  int     ## Max microseconds per turn
    isTurnTimeoutLocked*:          bool
    readyTimeout*:                 int     ## Max microseconds to send BotReady
    isReadyTimeoutLocked*:         bool
    defaultTurnsPerSecond*:        int     ## Default game speed (usually 30)

  BotState* = object
    ## Your bot's state snapshot each tick.
    ## Access individual fields via getters like `getX()`, `getEnergy()`, etc.
    isDroid*:        bool    ## True if bot is a droid (no radar)
    energy*:         float   ## Current energy (0 = dead)
    x*:              float   ## X position
    y*:              float   ## Y position
    direction*:      float   ## Body heading [0, 360)
    gunDirection*:   float   ## Gun heading [0, 360)
    radarDirection*: float   ## Radar heading [0, 360)
    radarSweep*:     float   ## Radar sweep angle this tick
    speed*:          float   ## Current velocity (-8 to 8)
    turnRate*:       float   ## Body turn rate this tick
    gunTurnRate*:    float   ## Gun turn rate this tick
    radarTurnRate*:  float   ## Radar turn rate this tick
    gunHeat*:        float   ## Current gun heat (0 = ready to fire)
    enemyCount*:     int     ## Number of live enemies
    bodyColor*:      Color   ## Body color
    turretColor*:    Color   ## Turret color
    radarColor*:     Color   ## Radar color
    bulletColor*:    Color   ## Bullet color
    scanColor*:      Color   ## Scan arc color
    tracksColor*:    Color   ## Tracks color
    gunColor*:       Color   ## Gun color

  BulletState* = object
    ## Bullet information.
    bulletId*:  int     ## Unique bullet ID
    ownerId*:   int     ## Bot ID that fired it
    power*:     float   ## Firepower (0.1 - 3.0)
    x*:         float   ## Current X position
    y*:         float   ## Current Y position
    direction*: float   ## Heading [0, 360)
    color*:     Color   ## Bullet color

  ResultsForBot* = object
    ## Round results for your bot.
    rank*:              int  ## Final rank (1 = winner)
    survival*:          int  ## Survival points
    lastSurvivorBonus*: int  ## Bonus for being last alive
    bulletDamage*:      int  ## Damage dealt by bullets
    bulletKillBonus*:   int  ## Bonus for bullet kills
    ramDamage*:         int  ## Damage dealt by ramming
    ramKillBonus*:      int  ## Bonus for ram kills
    totalScore*:        int  ## Total round score
    firstPlaces*:       int  ## Season: 1st place finishes
    secondPlaces*:      int  ## Season: 2nd place finishes
    thirdPlaces*:       int  ## Season: 3rd place finishes

  TeamMessage* = object
    ## Team message payload.
    message*:     string  ## Message content
    messageType*: string  ## Type identifier (e.g., "String")
    receiverId*:  int     ## 0 = broadcast, else specific bot ID

  # ---- Connection event types ------------------------------------------------

  ConnectedEvent* = object
    ## Fired when connected to server. Received in `onConnected`.
    serverUrl*: string  ## The server URL we connected to

  DisconnectedEvent* = object
    ## Fired when disconnected from server. Received in `onDisconnected`.
    serverUrl*: string   ## The server URL
    remote*:    bool     ## True if server initiated disconnect
    statusCode*: int     ## HTTP/WebSocket status code (0 if not provided)
    reason*:    string   ## Human-readable reason

  ConnectionErrorEvent* = object
    ## Fired on connection error. Received in `onConnectionError`.
    serverUrl*: string  ## The server URL
    error*:     string  ## Error description

  # ---- Server → Bot messages -------------------------------------------------

  ServerHandshake* = object
    ## Initial handshake from server after WebSocket upgrade.
    `type`*:      string       ## Always "ServerHandshake"
    sessionId*:   string       ## Unique session ID for this connection
    name*:        string       ## Server name
    variant*:     string       ## Game variant (e.g., "tankroyale")
    version*:     string       ## Server version
    gameTypes*:   seq[string]  ## Supported game types

  GameStartedEventForBot* = object
    ## Fired when game starts. Received in `onGameStarted`.
    `type`*:         string       ## Always "GameStartedEventForBot"
    myId*:           int         ## Your bot ID for this game
    startX*:         float       ## Your starting X position
    startY*:         float       ## Your starting Y position
    startDirection*: float       ## Your starting heading
    teammateIds*:    seq[int]    ## Teammate bot IDs (team games)
    gameSetup*:      GameSetup   ## Game configuration

  RoundStartedEvent* = object
    ## Fired when a round starts. Received in `onRoundStarted`.
    `type`*:      string  ## Always "RoundStartedEvent"
    roundNumber*: int     ## 1-based round number

  RoundEndedEventForBot* = object
    ## Fired when a round ends. Received in `onRoundEnded`.
    `type`*:       string         ## Always "RoundEndedEventForBot"
    turnNumber*:   int           ## Final turn number
    roundNumber*:  int           ## Round number
    results*:      ResultsForBot ## Your results for this round

  GameEndedEventForBot* = object
    ## Fired when game ends. Received in `onGameEnded`.
    `type`*:           string         ## Always "GameEndedEventForBot"
    numberOfRounds*:  int           ## Total rounds played
    results*:         ResultsForBot ## Your final results

  GameAbortedEvent* = object
    ## Fired when game is aborted. Received in `onGameAborted`.
    `type`*: string  ## Always "GameAbortedEvent"

  SkippedTurnEvent* = object
    ## Fired when you skip a turn (exceeded turn timeout).
    ## Received in `onSkippedTurn`.
    `type`*:      string  ## Always "SkippedTurnEvent"
    turnNumber*: int     ## The turn that was skipped

  # Events inside TickEventForBot.events
  BotDeathEvent* = object
    ## Another bot died. Received in `onBotDeath` (or `onDeath` if you).
    `type`*:     string  ## Always "BotDeathEvent"
    turnNumber*: int     ## Turn when death occurred
    victimId*:   int     ## Bot ID that died

  BotHitBotEvent* = object
    ## You rammed another bot. Received in `onHitBot`.
    `type`*:     string  ## Always "BotHitBotEvent"
    turnNumber*: int     ## Turn of collision
    victimId*:   int     ## Bot you hit
    botId*:      int     ## Your bot ID (same as getMyId())
    energy*:     float   ## Your energy after collision
    x*:          float   ## Your X position
    y*:          float   ## Your Y position
    rammed*:     bool    ## True if you were the rammer

  BotHitWallEvent* = object
    ## You hit a wall. Received in `onHitWall`.
    `type`*:     string  ## Always "BotHitWallEvent"
    turnNumber*: int     ## Turn of collision
    victimId*:   int     ## Your bot ID

  BulletFiredEvent* = object
    ## You fired a bullet. Received in `onBulletFired`.
    `type`*:     string       ## Always "BulletFiredEvent"
    turnNumber*: int         ## Turn when fired
    bullet*:     BulletState ## The fired bullet's state

  BulletHitBotEvent* = object
    ## Your bullet hit a bot. Received in `onBulletHit`.
    `type`*:     string       ## Always "BulletHitBotEvent"
    turnNumber*: int         ## Turn of impact
    victimId*:   int         ## Bot that was hit
    bullet*:     BulletState ## The bullet that hit
    damage*:     float       ## Damage dealt
    energy*:     float       ## Victim's energy after hit

  BulletHitBulletEvent* = object
    ## Your bullet hit another bullet. Received in `onBulletHitBullet`.
    `type`*:     string       ## Always "BulletHitBulletEvent"
    turnNumber*: int         ## Turn of collision
    bullet*:     BulletState ## Your bullet
    hitBullet*:  BulletState ## The bullet you hit

  BulletHitWallEvent* = object
    ## Your bullet hit a wall. Received in `onBulletHitWall`.
    `type`*:     string       ## Always "BulletHitWallEvent"
    turnNumber*: int         ## Turn of impact
    bullet*:     BulletState ## The bullet

  HitByBulletEvent* = object
    ## You were hit by a bullet. Received in `onHitByBullet`.
    `type`*:     string       ## Always "HitByBulletEvent"
    turnNumber*: int         ## Turn of impact
    bullet*:     BulletState ## The bullet that hit you
    damage*:     float       ## Damage taken
    energy*:     float       ## Your energy after hit

  ScannedBotEvent* = object
    ## Your radar scanned a bot. Received in `onScannedBot`.
    `type`*:           string  ## Always "ScannedBotEvent"
    turnNumber*:     int     ## Turn of scan
    scannedByBotId*: int     ## Your bot ID (who scanned)
    scannedBotId*:   int     ## The bot that was scanned
    energy*:         float   ## Scanned bot's energy
    x*:              float   ## Scanned bot's X position
    y*:              float   ## Scanned bot's Y position
    direction*:      float   ## Scanned bot's heading
    speed*:          float   ## Scanned bot's velocity

  WonRoundEvent* = object
    ## You won the round! Received in `onWonRound`.
    `type`*:     string  ## Always "WonRoundEvent"
    turnNumber*: int     ## Final turn number

  TeamMessageEvent* = object
    ## Received a team message. Received in `onTeamMessage`.
    `type`*:      string  ## Always "TeamMessageEvent"
    turnNumber*:  int     ## Turn received
    message*:     string  ## Message content
    messageType*: string  ## Message type
    senderId*:    int     ## Bot ID of sender

  TickEventForBot* = object
    ## Main tick event with complete game state. Received in `onTick`.
    `type`*:        string          ## Always "TickEventForBot"
    turnNumber*:    int             ## Current turn number
    roundNumber*:   int             ## Current round number
    botState*:      BotState        ## Your bot's state
    bulletStates*:  seq[BulletState] ## All bullets in air
    events*:        seq[RawEvent]   ## Sub-events (parsed separately)

  # A raw event with just a type field, for first-pass dispatch
  RawEvent* = object
    `type`*:     string  ## Event type string
    turnNumber*: int     ## Turn number

  # ---- Bot → Server messages -------------------------------------------------

  BotHandshake* = object
    ## Sent to server during connection handshake.
    `type`*:           string          ## Always "BotHandshake"
    sessionId*:        string          ## From ServerHandshake
    name*:             string          ## Your bot name
    version*:          string          ## Your bot version
    authors*:          seq[string]     ## Author list
    description*:      string          ## Bot description
    homepage*:         string          ## Bot homepage URL
    countryCodes*:     seq[string]     ## ISO country codes
    gameTypes*:        seq[string]     ## Supported game types
    platform*:         string          ## "Nim " & NimVersion
    programmingLang*:  string          ## "Nim"
    initialPosition*:  InitialPosition ## Optional starting position
    teamId*:           int             ## Team ID (0 = no team)
    teamName*:         string          ## Team name
    teamVersion*:      string          ## Team version
    isDroid*:          bool            ## True if droid (no radar)
    secret*:           string          ## Server secret (if required)

  BotReady* = object
    ## Sent when bot is ready for round to start.
    `type`*: string  ## Always "BotReady"

  BotIntent* = object
    ## Your commands for this tick. Built by `buildIntentJson()`.
    `type`*:                  string          ## Always "BotIntent"
    turnRate*:                float           ## Body turn rate [-10, 10]
    gunTurnRate*:             float           ## Gun turn rate [-20, 20]
    radarTurnRate*:           float           ## Radar turn rate [-45, 45]
    targetSpeed*:             float           ## Target velocity [-8, 8]
    firepower*:               float           ## Fire power (0.1-3.0, 0 = don't fire)
    adjustGunForBodyTurn*:    bool            ## Gun turns with body
    adjustRadarForBodyTurn*:  bool            ## Radar turns with body
    adjustRadarForGunTurn*:   bool            ## Radar turns with gun
    rescan*:                  bool            ## Request radar rescan
    fireAssist*:              bool            ## Auto-fire when gun on target
    bodyColor*:               Color           ## Body color this tick
    turretColor*:             Color           ## Turret color this tick
    radarColor*:              Color           ## Radar color this tick
    bulletColor*:             Color           ## Bullet color this tick
    scanColor*:               Color           ## Scan arc color this tick
    tracksColor*:             Color           ## Tracks color this tick
    gunColor*:                Color           ## Gun color this tick
    stdOut*:                  string          ## Stdout to send to server
    stdErr*:                  string          ## Stderr to send to server
    teamMessages*:            seq[TeamMessage] ## Team messages this tick
    debugGraphics*:           string          ## SVG debug graphics
