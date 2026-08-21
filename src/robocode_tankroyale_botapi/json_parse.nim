## Safe JSON-to-type parsing for Robocode Tank Royale protocol.
##
## Uses the {} accessor (returns nil on missing keys) and typed getters with
## default values so that optional schema fields never raise KeyError.

import std/json
import ./schemas
import ./color
import ./event_queue

proc parseBulletState*(node: JsonNode): BulletState =
  ## Parse a BulletState from JSON; missing optional fields default to zero.
  if node.isNil: return
  result.bulletId  = node{"bulletId"}.getInt(0)
  result.ownerId   = node{"ownerId"}.getInt(0)
  result.power     = node{"power"}.getFloat(0.0)
  result.x         = node{"x"}.getFloat(0.0)
  result.y         = node{"y"}.getFloat(0.0)
  result.direction = node{"direction"}.getFloat(0.0)
  let bulletColorStr = node{"color"}.getStr("")
  result.color = if bulletColorStr.len > 0: fromHex(bulletColorStr) else: Color(0)

proc parseBotState*(node: JsonNode): BotState =
  ## Parse a BotState from JSON; optional colour/flag fields default to empty/false.
  if node.isNil: return
  result.isDroid        = node{"isDroid"}.getBool(false)
  result.energy         = node{"energy"}.getFloat(0.0)
  result.x              = node{"x"}.getFloat(0.0)
  result.y              = node{"y"}.getFloat(0.0)
  result.direction      = node{"direction"}.getFloat(0.0)
  result.gunDirection   = node{"gunDirection"}.getFloat(0.0)
  result.radarDirection = node{"radarDirection"}.getFloat(0.0)
  result.radarSweep     = node{"radarSweep"}.getFloat(0.0)
  result.speed          = node{"speed"}.getFloat(0.0)
  result.turnRate       = node{"turnRate"}.getFloat(0.0)
  result.gunTurnRate    = node{"gunTurnRate"}.getFloat(0.0)
  result.radarTurnRate  = node{"radarTurnRate"}.getFloat(0.0)
  result.gunHeat        = node{"gunHeat"}.getFloat(0.0)
  result.enemyCount     = node{"enemyCount"}.getInt(0)
  template parseColor(field: untyped) =
    let s = node{astToStr(field)}.getStr("")
    result.field = if s.len > 0: fromHex(s) else: Color(0)
  parseColor(bodyColor)
  parseColor(turretColor)
  parseColor(radarColor)
  parseColor(bulletColor)
  parseColor(scanColor)
  parseColor(tracksColor)
  parseColor(gunColor)

proc parseBotEvent*(node: JsonNode; myId: int): BotEvent =
  ## Parse a JSON event node into a typed BotEvent.
  let typeStr = node{"type"}.getStr
  let tn = node{"turnNumber"}.getInt(0)
  case typeStr
  of "BotDeathEvent":
    let victimId = node{"victimId"}.getInt(0)
    if victimId == myId:
      result = BotEvent(kind: ekDeath, turnNumber: tn,
        death: BotDeathEvent(`type`: typeStr, turnNumber: tn, victimId: victimId))
    else:
      result = BotEvent(kind: ekBotDeath, turnNumber: tn,
        botDeath: BotDeathEvent(`type`: typeStr, turnNumber: tn, victimId: victimId))
  of "BulletFiredEvent":
    result = BotEvent(kind: ekBulletFired, turnNumber: tn,
      bulletFired: BulletFiredEvent(`type`: typeStr, turnNumber: tn,
        bullet: parseBulletState(node{"bullet"})))
  of "BulletHitBotEvent":
    let victimId = node{"victimId"}.getInt(0)
    let bullet = parseBulletState(node{"bullet"})
    let damage = node{"damage"}.getFloat(0.0)
    let energy = node{"energy"}.getFloat(0.0)
    if victimId == myId:
      result = BotEvent(kind: ekHitByBullet, turnNumber: tn,
        hitByBullet: HitByBulletEvent(`type`: "HitByBulletEvent", turnNumber: tn,
          bullet: bullet, damage: damage, energy: energy))
    else:
      result = BotEvent(kind: ekBulletHitBot, turnNumber: tn,
        bulletHitBot: BulletHitBotEvent(`type`: typeStr, turnNumber: tn,
          victimId: victimId, bullet: bullet, damage: damage, energy: energy))
  of "BulletHitBulletEvent":
    result = BotEvent(kind: ekBulletHitBullet, turnNumber: tn,
      bulletHitBullet: BulletHitBulletEvent(`type`: typeStr, turnNumber: tn,
        bullet: parseBulletState(node{"bullet"}),
        hitBullet: parseBulletState(node{"hitBullet"})))
  of "BulletHitWallEvent":
    result = BotEvent(kind: ekBulletHitWall, turnNumber: tn,
      bulletHitWall: BulletHitWallEvent(`type`: typeStr, turnNumber: tn,
        bullet: parseBulletState(node{"bullet"})))
  of "BotHitBotEvent":
    result = BotEvent(kind: ekHitBot, turnNumber: tn,
      hitBot: node.to(BotHitBotEvent))
  of "BotHitWallEvent":
    result = BotEvent(kind: ekHitWall, turnNumber: tn,
      hitWall: node.to(BotHitWallEvent))
  of "ScannedBotEvent":
    result = BotEvent(kind: ekScannedBot, turnNumber: tn,
      scannedBot: node.to(ScannedBotEvent))
  of "WonRoundEvent":
    result = BotEvent(kind: ekWonRound, turnNumber: tn,
      wonRound: WonRoundEvent(`type`: typeStr, turnNumber: tn))
  of "TeamMessageEvent":
    result = BotEvent(kind: ekTeamMessage, turnNumber: tn,
      teamMessage: node.to(TeamMessageEvent))
  else:
    discard
