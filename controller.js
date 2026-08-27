// Minimal Tank Royale controller: handshake then start game with connected bots
const WebSocket = require('ws');

const ws = new WebSocket('ws://localhost:7654');
let sessionId = null;
let botHandshakes = [];
let gameStarted = false;
let roundsCompleted = 0;
let targetRounds = 3;

ws.on('open', () => console.log('[ctrl] connected to server'));

ws.on('message', (data) => {
  let msg;
  try { msg = JSON.parse(data); } catch { return; }
  const t = msg.type;
  console.log('[ctrl] <-', t, JSON.stringify(msg).slice(0, 120));

  if (t === 'ServerHandshake') {
    sessionId = msg.sessionId;
    ws.send(JSON.stringify({
      type: 'ControllerHandshake',
      sessionId,
      name: 'TestController',
      version: '1.0',
    }));
  } else if (t === 'BotListUpdate') {
    botHandshakes = msg.bots || [];
    console.log('[ctrl] bots available:', botHandshakes.length);
    if (!gameStarted && botHandshakes.length >= 2) {
      startGame();
    }
  } else if (t === 'RoundStartedEvent') {
    console.log('[ctrl] round started:', msg.roundNumber);
  } else if (t === 'RoundEndedEvent') {
    roundsCompleted++;
    console.log('[ctrl] round ended:', msg.roundNumber, '— completed so far:', roundsCompleted);
  } else if (t === 'GameEndedEventForObserver') {
    console.log('[ctrl] game ended. rounds completed:', roundsCompleted);
    ws.close();
    process.exit(0);
  } else if (t === 'GameAbortedEvent') {
    console.log('[ctrl] game aborted');
    ws.close();
    process.exit(1);
  }
});

ws.on('error', (e) => { console.error('[ctrl] error:', e.message); process.exit(1); });
ws.on('close', () => { console.log('[ctrl] disconnected'); });

function startGame() {
  gameStarted = true;
  const botAddresses = botHandshakes.map(b => ({ host: b.host, port: b.port }));
  const msg = {
    type: 'StartGame',
    gameSetup: {
      gameType: 'classic',
      arenaWidth: 800,
      isArenaWidthLocked: false,
      arenaHeight: 600,
      isArenaHeightLocked: false,
      minNumberOfParticipants: 2,
      isMinNumberOfParticipantsLocked: false,
      isMaxNumberOfParticipantsLocked: false,
      numberOfRounds: targetRounds,
      isNumberOfRoundsLocked: false,
      gunCoolingRate: 0.1,
      isGunCoolingRateLocked: false,
      maxInactivityTurns: 450,
      isMaxInactivityTurnsLocked: false,
      turnTimeout: 30000,
      isTurnTimeoutLocked: false,
      readyTimeout: 1000000,
      isReadyTimeoutLocked: false,
      defaultTurnsPerSecond: 30,
    },
    botAddresses,
  };
  console.log('[ctrl] starting game with', botAddresses.length, 'bots,', targetRounds, 'rounds');
  ws.send(JSON.stringify(msg));
}

// Timeout safety
setTimeout(() => {
  console.error('[ctrl] TIMEOUT after 120s — rounds completed:', roundsCompleted);
  process.exit(roundsCompleted >= targetRounds ? 0 : 2);
}, 120000);
