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
    events*:     seq[BotEvent]
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
  if eq.events.len < MAX_QUEUE_SIZE:
    eq.events.add e

proc clear*(eq: var EventQueue) =
  eq.events.setLen(0)
  eq.currentTopPriority = MIN_VALUE

proc clearEvents*(eq: var EventQueue) =
  clear(eq)

proc removeOldEvents*(eq: var EventQueue; turnNumber: int) =
  var i = 0
  while i < eq.events.len:
    if eq.events[i].turnNumber < turnNumber - MAX_EVENTS_AGE and
       not eq.events[i].isCritical:
      eq.events.delete(i)
    else:
      inc i

proc popFirst*(eq: var EventQueue): BotEvent =
  ## Remove and return the head element.
  if eq.events.len == 0: return
  result = eq.events[0]
  eq.events.delete(0)

proc addCustomEvents*(eq: var EventQueue; turnNumber: int) =
  for c in eq.conditions:
    try:
      if c.test():
        eq.addEvent(BotEvent(kind: ekCustom, turnNumber: turnNumber, condition: c))
    except: discard

proc sortEvents*(eq: var EventQueue) =
  # ponytail: copy priorities table for closure capture (cheap, overrides are rare)
  let prio = eq.priorities
  if eq.events.len > 1:
    eq.events.sort(proc(a, b: BotEvent): int =
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
  result = eq.events
