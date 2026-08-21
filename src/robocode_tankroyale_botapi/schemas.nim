## Schema types for Robocode Tank Royale protocol messages.
## These mirror the YAML schemas in schema/schemas/.

import ./color

type
  # ---- Shared / embedded types -----------------------------------------------

  InitialPosition* = object
    x*:         float
    y*:         float
    direction*: float

  GameSetup* = object
    gameType*:                     string
    arenaWidth*:                   int
    isArenaWidthLocked*:           bool
    arenaHeight*:                  int
    isArenaHeightLocked*:          bool
    minNumberOfParticipants*:      int
    isMinNumberOfParticipantsLocked*: bool
    maxNumberOfParticipants*:      int
    isMaxNumberOfParticipantsLocked*: bool
    numberOfRounds*:               int
    isNumberOfRoundsLocked*:       bool
    gunCoolingRate*:               float
    isGunCoolingRateLocked*:       bool
    maxInactivityTurns*:           int
    isMaxInactivityTurnsLocked*:   bool
    turnTimeout*:                  int    # microseconds
    isTurnTimeoutLocked*:          bool
    readyTimeout*:                 int    # microseconds
    isReadyTimeoutLocked*:         bool
    defaultTurnsPerSecond*:        int

  BotState* = object
    isDroid*:        bool
    energy*:         float
    x*:              float
    y*:              float
    direction*:      float
    gunDirection*:   float
    radarDirection*: float
    radarSweep*:     float
    speed*:          float
    turnRate*:       float
    gunTurnRate*:    float
    radarTurnRate*:  float
    gunHeat*:        float
    enemyCount*:     int
    bodyColor*:      Color
    turretColor*:    Color
    radarColor*:     Color
    bulletColor*:    Color
    scanColor*:      Color
    tracksColor*:    Color
    gunColor*:       Color

  BulletState* = object
    bulletId*:  int
    ownerId*:   int
    power*:     float
    x*:         float
    y*:         float
    direction*: float
    color*:     Color

  ResultsForBot* = object
    rank*:              int
    survival*:          int
    lastSurvivorBonus*: int
    bulletDamage*:      int
    bulletKillBonus*:   int
    ramDamage*:         int
    ramKillBonus*:      int
    totalScore*:        int
    firstPlaces*:       int
    secondPlaces*:      int
    thirdPlaces*:       int

  TeamMessage* = object
    message*:     string
    messageType*: string
    receiverId*:  int

  # ---- Connection event types ------------------------------------------------

  ConnectedEvent* = object
    serverUrl*: string

  DisconnectedEvent* = object
    serverUrl*: string
    remote*:    bool
    statusCode*: int    ## 0 when not provided
    reason*:    string

  ConnectionErrorEvent* = object
    serverUrl*: string
    error*:     string

  # ---- Server → Bot messages -------------------------------------------------

  ServerHandshake* = object
    `type`*:      string
    sessionId*:   string
    name*:        string
    variant*:     string
    version*:     string
    gameTypes*:   seq[string]

  GameStartedEventForBot* = object
    `type`*:         string
    myId*:           int
    startX*:         float
    startY*:         float
    startDirection*: float
    teammateIds*:    seq[int]
    gameSetup*:      GameSetup

  RoundStartedEvent* = object
    `type`*:      string
    roundNumber*: int

  RoundEndedEventForBot* = object
    `type`*:       string
    turnNumber*:   int
    roundNumber*:  int
    results*:      ResultsForBot

  GameEndedEventForBot* = object
    `type`*:          string
    numberOfRounds*:  int
    results*:         ResultsForBot

  GameAbortedEvent* = object
    `type`*:     string

  SkippedTurnEvent* = object
    `type`*:     string
    turnNumber*: int

  # Events inside TickEventForBot.events
  BotDeathEvent* = object
    `type`*:     string
    turnNumber*: int
    victimId*:   int

  BotHitBotEvent* = object
    `type`*:     string
    turnNumber*: int
    victimId*:   int
    botId*:      int
    energy*:     float
    x*:          float
    y*:          float
    rammed*:     bool

  BotHitWallEvent* = object
    `type`*:     string
    turnNumber*: int
    victimId*:   int

  BulletFiredEvent* = object
    `type`*:     string
    turnNumber*: int
    bullet*:     BulletState

  BulletHitBotEvent* = object
    `type`*:     string
    turnNumber*: int
    victimId*:   int
    bullet*:     BulletState
    damage*:     float
    energy*:     float

  BulletHitBulletEvent* = object
    `type`*:     string
    turnNumber*: int
    bullet*:     BulletState
    hitBullet*:  BulletState

  BulletHitWallEvent* = object
    `type`*:     string
    turnNumber*: int
    bullet*:     BulletState

  HitByBulletEvent* = object
    `type`*:     string
    turnNumber*: int
    bullet*:     BulletState
    damage*:     float
    energy*:     float

  ScannedBotEvent* = object
    `type`*:          string
    turnNumber*:      int
    scannedByBotId*:  int
    scannedBotId*:    int
    energy*:          float
    x*:               float
    y*:               float
    direction*:       float
    speed*:           float

  WonRoundEvent* = object
    `type`*:     string
    turnNumber*: int

  TeamMessageEvent* = object
    `type`*:      string
    turnNumber*:  int
    message*:     string
    messageType*: string
    senderId*:    int

  TickEventForBot* = object
    `type`*:        string
    turnNumber*:    int
    roundNumber*:   int
    botState*:      BotState
    bulletStates*:  seq[BulletState]
    events*:        seq[RawEvent]   # heterogeneous; decoded by type field

  # A raw event with just a type field, for first-pass dispatch
  RawEvent* = object
    `type`*:     string
    turnNumber*: int

  # ---- Bot → Server messages -------------------------------------------------

  BotHandshake* = object
    `type`*:           string
    sessionId*:        string
    name*:             string
    version*:          string
    authors*:          seq[string]
    description*:      string
    homepage*:         string
    countryCodes*:     seq[string]
    gameTypes*:        seq[string]
    platform*:         string
    programmingLang*:  string
    initialPosition*:  InitialPosition
    teamId*:           int
    teamName*:         string
    teamVersion*:      string
    isDroid*:          bool
    secret*:           string

  BotReady* = object
    `type`*: string

  BotIntent* = object
    `type`*:                  string
    turnRate*:                float
    gunTurnRate*:             float
    radarTurnRate*:           float
    targetSpeed*:             float
    firepower*:               float
    adjustGunForBodyTurn*:    bool
    adjustRadarForBodyTurn*:  bool
    adjustRadarForGunTurn*:   bool
    rescan*:                  bool
    fireAssist*:              bool
    bodyColor*:               Color
    turretColor*:             Color
    radarColor*:              Color
    bulletColor*:             Color
    scanColor*:               Color
    tracksColor*:             Color
    gunColor*:                Color
    stdOut*:                  string
    stdErr*:                  string
    teamMessages*:            seq[TeamMessage]
    debugGraphics*:           string
