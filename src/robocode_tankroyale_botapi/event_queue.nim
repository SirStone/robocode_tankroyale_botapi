## Priority-based event queue for Robocode Tank Royale bot API.
##
## Every tick, the server may deliver several events at once (for example you
## scanned a bot, got hit by a bullet, and a bullet of yours hit an enemy).
## This module collects them, sorts them by importance, and dispatches them to
## your bot's event handlers in the correct order.
##
## ## Why priority matters
##
## Some events are more urgent than others. If you die this tick, it makes no
## sense to also run your `onScannedBot` logic. Events are sorted so the most
## important ones run first. The default priority values come from
## `constants` (e.g. `PRIORITY_DEATH` = 10 is lowest, `PRIORITY_WON_ROUND` =
## 150 is highest). You can change a kind's priority at runtime with
## `bot.setEventPriority`.
##
## ## Critical events
##
## Three event kinds are marked *critical*: `ekDeath`, `ekWonRound`, and
## `ekSkippedTurn`. Critical events are never deleted when old events are
## cleaned up, and they are allowed to interrupt a lower-priority handler that
## is currently running.
##
## ## See also
## - `bot.setEventPriority` -- change dispatch order at runtime
## - `bot.setInterruptible` -- let the current handler be interrupted
## - `bot.addCustomEvent` -- register your own event condition

import std/[algorithm, tables]
import ./constants
import ./schemas

type
  EventKind* = enum
    ## The kind of an event. Used as the sort key and dispatch selector.
    ekTick            ## Regular tick (normal game state update)
    ekSkippedTurn     ## You ran out of time on a turn (critical)
    ekBotDeath        ## Another bot was destroyed
    ekDeath           ## Your bot was destroyed (critical)
    ekBulletFired     ## You fired a bullet
    ekBulletHitBot    ## Your bullet struck an enemy
    ekBulletHitBullet ## Your bullet struck another bullet
    ekBulletHitWall   ## Your bullet struck a wall
    ekHitByBullet     ## You were struck by a bullet
    ekHitBot          ## You collided with another bot
    ekHitWall         ## You collided with a wall
    ekScannedBot      ## Your radar detected a bot
    ekWonRound        ## You won the round (critical)
    ekTeamMessage     ## A teammate sent you a message
    ekCustom          ## A custom condition you registered became true

  Condition* = object
    ## A named boolean test evaluated every tick for custom events.
    name*: string
    test*: proc(): bool {.closure.}

  BotEvent* = object
    ## A single event with a `turnNumber` and a `kind`-specific payload.
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
    ## Internal queue holding the events for the current tick.
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
