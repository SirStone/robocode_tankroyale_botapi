## Priority-based event queue for Robocode Tank Royale bot API.
## Typed BotEvent variants wrapping schema types, priority-sorted dispatch.

import std/[algorithm, tables]
import ./constants
import ./schemas

type
  EventKind* = enum
    ekTick
    ekSkippedTurn
    ekBotDeath
    ekDeath           ## self-death; isCritical=true
    ekBulletFired
    ekBulletHitBot
    ekBulletHitBullet
    ekBulletHitWall
    ekHitByBullet
    ekHitBot
    ekHitWall
    ekScannedBot
    ekWonRound
    ekTeamMessage
    ekCustom

  Condition* = object
    name*: string
    test*: proc(): bool {.closure.}

  BotEvent* = object
    turnNumber*: int
    case kind*: EventKind
    of ekTick:            tick*: TickEventForBot
    of ekSkippedTurn:     skippedTurn*: SkippedTurnEvent
    of ekBotDeath:        botDeath*: BotDeathEvent
    of ekDeath:           death*: BotDeathEvent
    of ekBulletFired:     bulletFired*: BulletFiredEvent
    of ekBulletHitBot:    bulletHitBot*: BulletHitBotEvent
    of ekBulletHitBullet: bulletHitBullet*: BulletHitBulletEvent
    of ekBulletHitWall:   bulletHitWall*: BulletHitWallEvent
    of ekHitByBullet:     hitByBullet*: HitByBulletEvent
    of ekHitBot:          hitBot*: BotHitBotEvent
    of ekHitWall:         hitWall*: BotHitWallEvent
    of ekScannedBot:      scannedBot*: ScannedBotEvent
    of ekWonRound:        wonRound*: WonRoundEvent
    of ekTeamMessage:     teamMessage*: TeamMessageEvent
    of ekCustom:          condition*: Condition

  EventQueue* = object
    # ponytail: fixed static storage instead of a seq. The queue outlives bot
    # threads (a fresh thread runs each round), so a heap seq's backing array
    # is realloc'd by a *different* dead thread's allocator mid-round ->
    # rawDealloc SIGSEGV in addEvent (7 gdb-confirmed dumps). Static array:
    # no heap block crosses threads, realloc can never happen.
    events*:     array[MAX_QUEUE_SIZE, BotEvent]
    eventsLen*:  int
    priorities:  Table[EventKind, int]   ## runtime-mutable overrides
    interruptible*: set[EventKind]
    currentTopEventKind*: EventKind
    currentTopPriority*:  int
    conditions*: seq[Condition]

proc priorityOf*(kind: EventKind): int =
  case kind
  of ekTick:            PRIORITY_TICK
  of ekSkippedTurn:     PRIORITY_SKIPPED_TURN
  of ekBotDeath:        PRIORITY_BOT_DEATH
  of ekDeath:           PRIORITY_DEATH
  of ekBulletFired:     PRIORITY_BULLET_FIRED
  of ekBulletHitBot:    PRIORITY_BULLET_HIT_BOT
  of ekBulletHitBullet: PRIORITY_BULLET_HIT_BULLET
  of ekBulletHitWall:   PRIORITY_BULLET_HIT_WALL
  of ekHitByBullet:     PRIORITY_HIT_BY_BULLET
  of ekHitBot:          PRIORITY_HIT_BOT
  of ekHitWall:         PRIORITY_HIT_WALL
  of ekScannedBot:      PRIORITY_SCANNED_BOT
  of ekWonRound:        PRIORITY_WON_ROUND
  of ekTeamMessage:     PRIORITY_TEAM_MESSAGE
  of ekCustom:          PRIORITY_CUSTOM

proc isCritical*(e: BotEvent): bool =
  e.kind in {ekDeath, ekWonRound, ekSkippedTurn}

proc initEventQueue*(): EventQueue =
  result.currentTopPriority = MIN_VALUE

proc getPriority*(eq: EventQueue; kind: EventKind): int =
  eq.priorities.getOrDefault(kind, priorityOf(kind))

proc setPriority*(eq: var EventQueue; kind: EventKind; p: int) =
  eq.priorities[kind] = p

proc addEvent*(eq: var EventQueue; e: BotEvent) =
  if eq.eventsLen < MAX_QUEUE_SIZE:
    eq.events[eq.eventsLen] = e
    inc eq.eventsLen

proc clear*(eq: var EventQueue) =
  for i in 0 ..< eq.eventsLen:
    eq.events[i].reset  # destroy refcounted payloads before len drops to 0
  eq.eventsLen = 0
  eq.currentTopPriority = MIN_VALUE

proc clearEvents*(eq: var EventQueue) =
  clear(eq)

proc removeOldEvents*(eq: var EventQueue; turnNumber: int) =
  var i = 0
  while i < eq.eventsLen:
    if eq.events[i].turnNumber < turnNumber - MAX_EVENTS_AGE and
       not eq.events[i].isCritical:
      for j in i ..< eq.eventsLen - 1:
        eq.events[j] = eq.events[j + 1]
      dec eq.eventsLen
      eq.events[eq.eventsLen].reset
    else:
      inc i

proc popFirst*(eq: var EventQueue): BotEvent =
  ## Remove and return the head element (replaces seq delete(0)).
  if eq.eventsLen == 0: return
  result = eq.events[0]
  for i in 0 ..< eq.eventsLen - 1:
    eq.events[i] = eq.events[i + 1]
  dec eq.eventsLen
  eq.events[eq.eventsLen].reset

proc addCustomEvents*(eq: var EventQueue; turnNumber: int) =
  for c in eq.conditions:
    try:
      if c.test():
        eq.addEvent(BotEvent(kind: ekCustom, turnNumber: turnNumber, condition: c))
    except: discard

proc sortEvents*(eq: var EventQueue) =
  # ponytail: copy priorities table for closure capture (cheap, overrides are rare)
  let prio = eq.priorities
  if eq.eventsLen > 1:
    eq.events.toOpenArray(0, eq.eventsLen - 1).sort(proc(a, b: BotEvent): int =
      let dc = b.isCritical.int - a.isCritical.int
      if dc != 0: return dc
      let dt = a.turnNumber - b.turnNumber
      if dt != 0: return dt
      let pa = prio.getOrDefault(a.kind, priorityOf(a.kind))
      let pb = prio.getOrDefault(b.kind, priorityOf(b.kind))
      pb - pa
    )

proc setInterruptible*(eq: var EventQueue; kind: EventKind; v: bool) =
  if v: eq.interruptible.incl kind
  else: eq.interruptible.excl kind

proc isInterruptible*(eq: EventQueue; kind: EventKind): bool =
  kind in eq.interruptible

proc addCondition*(eq: var EventQueue; c: Condition) =
  eq.conditions.add c

proc removeConditionByName*(eq: var EventQueue; name: string) =
  for i in countdown(eq.conditions.high, 0):
    if eq.conditions[i].name == name:
      eq.conditions.del i
      return

proc getEvents*(eq: EventQueue): seq[BotEvent] =
  for i in 0 ..< eq.eventsLen:
    result.add eq.events[i]
