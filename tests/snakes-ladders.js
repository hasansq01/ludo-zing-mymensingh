// Snakes & Ladders tests for Ludo Zing Mymensingh.
// Run in the browser console on the source game page with ?vt=1 (no saving; uses the window.__ludo test hook):
// paste the whole file. Resolves to { passed, failed, failures }. Plays real turns with forced dice values.
(async () => {
  const L = window.__ludo, SL = L.SL, P = L.P, $ = id => document.getElementById(id);
  const results = [];
  const check = (name, ok, got) => results.push({ name, ok: !!ok, got: ok ? undefined : JSON.stringify(got) });
  const sleep = ms => new Promise(r => setTimeout(r, ms));
  async function until(pred, ms = 60000) { const t0 = performance.now(); while (performance.now() - t0 < ms) { if (pred()) return true; await sleep(40); } return false; }
  const coins0 = P.coins, stats0 = JSON.stringify(P.stats);
  const G = () => SL.G;

  // ---- board data and the landing rule ----
  const L8 = SL.LADDERS, S8 = SL.SNAKES;
  check('every ladder goes up, every snake goes down', Object.entries(L8).every(([a, b]) => b > a) && Object.entries(S8).every(([a, b]) => b < a));
  check('no square is both a ladder foot and a snake head; 100 is never a snake head', Object.keys(L8).every(k => !S8[k]) && !S8[100]);
  check('plain move', JSON.stringify(SL.land(10, 2)) === JSON.stringify({ to: 12, steps: 2 }));
  check('off the board, a 1 enters on square 1 (no ladder there any more)', SL.land(0, 1).to === 1 && SL.land(0, 1).steps === 1 && !SL.land(0, 1).ladder);
  check('removed ladders: no 1 -> 38 and no 80 -> 100 in the board data', !(1 in SL.LADDERS) && !(80 in SL.LADDERS) && !Object.values(SL.LADDERS).includes(38) && !Object.values(SL.LADDERS).includes(100) && Object.keys(SL.LADDERS).length === 7, SL.LADDERS);
  check('landing on 80 stays on 80; landing on 1 from the board stays on 1', SL.land(77, 3).to === 80 && !SL.land(77, 3).ladder && SL.land(0, 1).to === 1);
  check('every remaining ladder still climbs', [[4, 14], [9, 31], [21, 42], [28, 84], [36, 44], [51, 67], [71, 91]].every(([f, t]) => SL.land(f - 1, 1).to === t && SL.land(f - 1, 1).ladder));
  check('every snake still slides', Object.entries(SL.SNAKES).every(([h, t]) => SL.land(+h - 2, 2).to === +t && SL.land(+h - 2, 2).snake));
  check('off the board, 2-6 never enter', [2, 3, 4, 5, 6].every(v => SL.land(0, v).to === 0 && SL.land(0, v).wait));
  check('on the board every roll moves (no entry rule after entering)', [1, 2, 3, 5, 6].every(v => SL.land(10, v).to !== 10));
  check('landing on a ladder foot climbs it (4 -> 14)', SL.land(3, 1).to === 14 && SL.land(3, 1).ladder);
  check('landing on a snake head slides down (16 -> 6)', SL.land(13, 3).to === 6 && SL.land(13, 3).snake);
  check('overshooting 100 does not move', SL.land(97, 5).to === 97 && SL.land(97, 5).over);
  check('exact roll reaches 100', SL.land(97, 3).to === 100);
  check('reward replay: a real path reaches 100', SL.replayReaches100([1, 3, 6, 1, 6, 3, 4, 6, 3]));   // 1, 4>14, 20, 21>42, 48, 51>67, 71>91, 97, 100
  check('reward replay: the old shortcut via 1 -> 38 no longer reaches 100', !SL.replayReaches100([1, 6, 6, 1, 4, 6, 3]));
  check('reward replay: invented rolls do not', !SL.replayReaches100([3]) && !SL.replayReaches100([7, 7]) && !SL.replayReaches100([2.5]));
  check('reward replay: the same path without the entering 1 does not reach 100', !SL.replayReaches100([6, 6, 1, 4, 6, 3]));

  // ---- page and setup ----
  SL.open();
  check('Snake button opens the 3D jungle landing first (no setup card yet)', !$('slPage').hidden && SL.landing && $('slOv').hidden && !$('slLand').hidden);
  $('slCpu').click();
  check('VS COMPUTER opens the centred vs Computer popup over the landing', !$('slCpuSheet').hidden && SL.landing && $('slOv').hidden);
  check('the popup has colour + opponents, and no mode selector', $('slCpuSheet').querySelectorAll('input[name=slCol]').length === 4 && $('slCpuSheet').querySelectorAll('input[name=slOpp]').length === 3 && !document.querySelector('[name=slMode]'));
  $('slCpuSheet').querySelector('[data-close]').click();
  check('Back closes the popup and stays on the landing', $('slCpuSheet').hidden && SL.landing);
  $('slCpu').click(); $('slCol2').click(); $('slOpp2').click();
  $('slCpuSheet').querySelector('[type=submit]').click();
  check('Start game: vs Computer as Yellow with 2 computers', $('slCpuSheet').hidden && !SL.landing && SL.G.mode === 'cpu' && SL.G.players.length === 3 && SL.G.players[0].you && SL.G.players[0].c === 2, SL.G && SL.G.players.map(p => p.c));
  $('slBack').click(); document.querySelector('[data-sl="quit"]').click(); SL.open();
  $('slLocal').click();
  check('PASS & PLAY opens the Pass & Play popup (players only)', !$('slLocalSheet').hidden && $('slLocalSheet').querySelectorAll('input[name=slPpl]').length === 3 && !$('slLocalSheet').querySelector('[name=slCol]'));
  $('slPpl4').click(); $('slLocalSheet').querySelector('[type=submit]').click();
  check('Start game: Pass & Play with 4 players', $('slLocalSheet').hidden && SL.G.mode === 'local' && SL.G.players.length === 4 && $('slOv').hidden);
  check('the 3D room stops rendering while open', document.body.classList.contains('sl-open'));
  // keep running in a background tab: no auto-pause from visibility changes during the test
  const keep = setInterval(() => { if (SL.paused && SL.G && SL.G.phase !== 'over') document.querySelector('[data-sl="resume"]')?.click(); }, 50);

  // ---- Pass & Play turns ----
  SL.newGame('local', 2);
  check('Pass & Play with 2 players', G().players.length === 2 && G().players.every(p => !p.cpu && p.pos === 0) && $('slOv').hidden);
  for (const v of [2, 3, 4, 5]) {
    SL.roll(v);
    await until(() => G().turn === 1 && G().phase === 'roll');
    check(`off the board, a ${v} does not enter and the turn passes`, G().players[0].pos === 0 && G().turn === 1, [G().players[0].pos, G().turn]);
    G().turn = 0; G().phase = 'roll';
  }
  SL.roll(6);
  await until(() => G().phase === 'roll');
  check('off the board, a 6 does not enter but still earns another roll', G().players[0].pos === 0 && G().turn === 0, [G().players[0].pos, G().turn]);
  G().sixes = 0;
  SL.roll(1);
  await until(() => G().turn === 1 && G().phase === 'roll');
  check('a 1 enters on square 1 (no climb) and the turn passes', G().players[0].pos === 1 && G().players[0].ladders === 0, G().players[0].pos);
  G().players[0].pos = 3; G().players[0].xy = null;
  G().players[1].pos = 0; G().turn = 0;
  SL.roll(1);
  await until(() => G().turn === 1 && G().phase === 'roll');
  check('after entering, a 1 is an ordinary move (3 -> 4 climbs to 14)', G().players[0].pos === 14, G().players[0].pos);
  G().players[1].pos = 2; G().players[1].xy = null;   // already entered
  SL.roll(4);
  await until(() => G().turn === 0 && G().phase === 'roll');
  check('after entering, a 4 moves normally (2 -> 6)', G().players[1].pos === 6, G().players[1].pos);
  G().turn = 1;
  SL.roll(6);
  await until(() => G().players[1].pos === 12 && G().phase === 'roll');
  check('a 6 moves and the same player rolls again', G().turn === 1, G().turn);
  SL.roll(2);
  await until(() => G().turn === 0 && G().phase === 'roll');
  check('after the extra roll the turn passes', G().players[1].pos === 14, G().players[1].pos);
  G().players[0].pos = 13; G().players[0].xy = null;
  SL.roll(3);
  await until(() => G().turn === 1 && G().phase === 'roll');
  check('landing on 16 slides down the snake to 6', G().players[0].pos === 6 && G().players[0].snakes === 1, G().players[0].pos);
  G().players[1].pos = 97;
  SL.roll(5);
  await until(() => G().turn === 0 && G().phase === 'roll');
  check('a roll past 100 leaves the player on 97', G().players[1].pos === 97, G().players[1].pos);
  G().players[0].pos = 40; G().players[0].xy = null;
  SL.roll(6); await until(() => G().players[0].pos === 46 && G().phase === 'roll');
  SL.roll(6); await until(() => G().players[0].pos === 52 && G().phase === 'roll');
  SL.roll(6); await until(() => G().turn === 1 && G().phase === 'roll');
  check('three 6s in a row: the third does not move and the turn ends', G().players[0].pos === 52 && G().sixes === 0, [G().players[0].pos, G().turn]);
  const played0 = P.stats.slPlayed || 0, wins0 = P.stats.slWins || 0, c0 = P.coins;
  SL.roll(3);
  await until(() => G().phase === 'over');
  check('exactly 100 wins (Pass & Play: no coins, no win stat)', G().winner === 1 && P.coins === c0 && P.stats.slPlayed === played0 + 1 && (P.stats.slWins || 0) === wins0, [G().winner, P.coins - c0]);
  check('the win card is shown', !$('slOv').hidden && /wins/.test($('slOv').textContent));

  // ---- vs Computer: rewards and the computer's turn ----
  SL.newGame('cpu', 2);
  check('vs Computer: you + 1 computer', G().players[0].you && G().players[1].cpu);
  SL.roll(2);
  await until(() => G().turn === 1);
  await until(() => G().turn === 0 && G().phase === 'roll' && G().players[1].rolls.length > 0);
  check('the computer takes its own turn and hands back', G().players[1].rolls.length >= 1 && G().turn === 0, G().players[1].rolls);
  const me = G().players[0]; me.pos = 97; me.xy = null; me.rolls = [1, 3, 6, 1, 6, 3, 4, 6];   // a real path that reaches 97
  const c1 = P.coins, w1 = P.stats.slWins || 0;
  SL.roll(3);
  await until(() => G().phase === 'over');
  await sleep(50);
  check(`beating the computer pays ${100} coins once`, P.coins === c1 + 100 && G().paid && P.stats.slWins === w1 + 1, [P.coins - c1, G().paid]);
  SL.newGame('cpu', 2);
  const me2 = G().players[0]; me2.pos = 97; me2.xy = null; me2.rolls = [];   // a position the recorded rolls cannot explain
  const c2 = P.coins;
  SL.roll(3);
  await until(() => G().phase === 'over'); await sleep(50);
  check('a win the rolls cannot explain pays nothing', P.coins === c2 && !G().paid, [P.coins - c2]);

  // ---- 3 and 4 players ----
  SL.newGame('cpu', 4);
  check('vs Computer with 4 players: 3 computers', G().players.length === 4 && G().players.filter(p => p.cpu).length === 3);
  SL.newGame('local', 3);
  check('Pass & Play with 3 players', G().players.length === 3 && G().players.every(p => !p.cpu));

  // ---- pause / resume / quit ----
  clearInterval(keep);
  $('slBack').click();
  check('Back during a game pauses it', SL.paused && !$('slOv').hidden && !$('slPage').hidden);
  document.querySelector('[data-sl="resume"]').click();
  check('Resume continues the game', !SL.paused && $('slOv').hidden && !$('slDice').disabled);
  $('slBack').click(); document.querySelector('[data-sl="quit"]').click();
  check('Quit closes the board and resumes the 3D room', $('slPage').hidden && !document.body.classList.contains('sl-open'));

  // restore the profile so the tests leave no trace
  P.coins = coins0; Object.assign(P.stats, JSON.parse(stats0)); L.Store.save('profile', P);
  const failed = results.filter(r => !r.ok);
  return { passed: results.length - failed.length, failed: failed.length, failures: failed };
})();
