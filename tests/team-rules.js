// Pair Mode (teams) + Free Hand rule tests for Ludo Zing Mymensingh.
// Run in the browser console on the source game page with ?vt=1 (no saving; uses the window.__ludo test hook):
// paste the whole file. Resolves to { passed, failed, failures }. Plays real rolls (forced values): ~30s in a visible tab, a few minutes in a background tab (timers are throttled).
(async () => {
  const L = window.__ludo;
  const results = [];
  const check = (name, ok, got) => results.push({ name, ok: !!ok, got: ok ? undefined : JSON.stringify(got) });
  const sleep = ms => new Promise(r => setTimeout(r, ms));
  async function until(pred, ms = 45000) { const t0 = performance.now(); while (performance.now() - t0 < ms) { if (pred()) return true; await sleep(40); } return false; }
  // close any sheet a finished game opened (win screen)
  const closeWin = () => { document.querySelectorAll('.sheet').forEach(s => { s.hidden = true; }); };
  // the game pauses itself when the page is hidden (e.g. a background tab); keep it running while the tests play
  const unpause = setInterval(() => { if (!document.getElementById('pauseSheet').hidden) document.getElementById('resumeBtn').click(); }, 50);

  // Colours: 0 red (start abs 0), 1 green (13), 2 yellow (26), 3 blue (39). abs = (start + progress) % 52.
  const prog = (c, abs) => (abs - L.OFF[c] + 52) % 52;
  const base = () => [[-1, -1, -1, -1], [-1, -1, -1, -1], [-1, -1, -1, -1], [-1, -1, -1, -1]];
  const HOME = [56, 56, 56, 56];
  let nextId = 9000;
  function state(tok, extra = {}) {
    return Object.assign({ id: ++nextId, players: ['human', 'human', 'human', 'human'], names: ['Red', 'Green', 'Yellow', 'Blue'],
      view: 0, tok, pairs: [], turn: 0, dice: 0, sixes: 0, phase: 'roll', winner: -1, pick: null,
      teams: true, free: [false, false, false, false] }, extra);
  }
  const saved = L.S;

  // ---- Setup ----
  L.newGame(['human', 'cpu', 'cpu', 'cpu'], true);
  check('Pair Mode on with four seats', L.S.teams === true && JSON.stringify(L.S.free) === '[false,false,false,false]', [L.S.teams, L.S.free]);
  check('teams are opposite seats: Red+Yellow, Green+Blue', L.mateOf(0) === 2 && L.mateOf(2) === 0 && L.mateOf(1) === 3 && L.mateOf(3) === 1);
  L.newGame(['human', 'off', 'human', 'off'], true);
  check('2-player game can never be Pair Mode', L.S.teams === false);
  L.newGame(['human', 'human', 'human', 'off'], true);
  check('3-player game can never be Pair Mode', L.S.teams === false);
  L.newGame(['human', 'cpu', 'cpu', 'cpu'], false);
  check('Individual 4-player game has no teams', L.S.teams === false);
  L.newGame(['human', 'cpu', 'cpu', 'cpu'], true); L.S.free[0] = true;
  L.newGame(['human', 'cpu', 'cpu', 'cpu'], true);
  check('a new game never inherits Free Hand state', L.S.free.every(f => !f));

  // ---- Captures and blocking between partners ----
  let t = base(); t[0][0] = 10; t[2][0] = prog(2, 14); L.setS(state(t));
  check('Pair Mode: landing on a partner pawn captures nothing', L.victimsAt(0, 14, false).length === 0, L.victimsAt(0, 14, false));
  check('Pair Mode: partner is not a foe, opponents are', !L.foe(0, 2) && L.foe(0, 1) && L.foe(0, 3));
  t = base(); t[0][0] = 10; t[1][0] = prog(1, 14); L.setS(state(t));
  check('Pair Mode: opponents are still captured', JSON.stringify(L.victimsAt(0, 14, false)) === '[[1,0]]', L.victimsAt(0, 14, false));
  t = base(); t[0][0] = 10; t[2][0] = prog(2, 14); L.setS(state(t, { teams: false }));
  check('Individual: the same landing still captures Yellow', JSON.stringify(L.victimsAt(0, 14, false)) === '[[2,0]]');
  t = base(); t[0][0] = 10; t[2][0] = t[2][1] = prog(2, 12); L.setS(Object.assign(state(t), { pairs: [{ c: 2, a: 0, b: 1 }] }));
  check('Pair Mode: a partner pair does not block', L.dest(0, 0, 4) === 14);
  check('Pair Mode: a single cannot capture a partner pair either', L.victimsAt(0, 12, false).length === 0);
  L.setS(Object.assign(state(t, { teams: false }), { pairs: [{ c: 2, a: 0, b: 1 }] }));
  check('Individual: that pair still blocks (unchanged)', L.dest(0, 0, 4) === null);

  // ---- Free Hand gating (static) ----
  t = base(); t[0] = HOME.slice(); t[2][0] = 10; L.setS(state(t, { dice: 4 }));
  check('finished, no Free Hand yet: nothing to move', L.waitingSix(0) && L.movables().length === 0);
  L.S.free[0] = true;
  check('Free Hand on: rolls move the partner', L.moverOf(0) === 2 && JSON.stringify(L.movables()) === '[0]', L.movables());
  check('Free Hand never moves opponents or own pawns', L.moverOf(0) !== 1 && L.moverOf(0) !== 3 && L.moverOf(0) !== 0);
  t = base(); t[0][0] = 10; L.setS(state(t));
  check('unfinished player moves its own pawns', L.moverOf(0) === 0 && !L.waitingSix(0));

  // ---- Free Hand flow (real rolls) ----
  // 1. finished Red rolls a 3: no Free Hand, nothing moves, turn passes
  t = base(); t[0] = HOME.slice(); t[2][0] = 10; t[2][1] = 20; L.setS(state(t)); L.updateHUD();
  L.roll(3);
  await until(() => L.S.turn !== 0 && L.S.phase === 'roll');
  check('non-6 does not start Free Hand and the turn passes', !L.S.free[0] && L.S.turn === 1 && L.S.tok[2][0] === 10, [L.S.free[0], L.S.turn, L.S.tok[2]]);
  // 2. finished Red rolls a 6: Free Hand starts and the 6 moves a Yellow pawn
  t = base(); t[0] = HOME.slice(); t[2] = [10, 56, 56, 56]; L.setS(state(t)); L.updateHUD();   // one Yellow pawn left, so the 6 has one move
  L.roll(6);
  await until(() => L.S.phase === 'roll' && L.S.tok[2][0] !== 10);
  check('a 6 starts Free Hand and moves the partner pawn', L.S.free[0] && L.S.tok[2][0] === 16 && L.S.turn === 0, [L.S.free, L.S.tok[2], L.S.turn]);
  // 3. after activation a normal roll moves the partner (no further 6 needed)
  L.roll(4);
  await until(() => L.S.phase === 'roll' && L.S.turn !== 0);
  check('after activation a 4 moves Yellow 4 squares and ends the turn', L.S.tok[2][0] === 20 && L.S.turn === 1, [L.S.tok[2], L.S.turn]);
  // 4. Free Hand stays on and Red's opponents are captured normally by Yellow's pawn
  t = base(); t[0] = HOME.slice(); t[2][0] = 12; t[1][0] = prog(1, 41); L.setS(state(t, { free: [true, false, false, false] })); L.updateHUD();   // Yellow 12 = abs 38; +3 = abs 41 (not safe)
  L.roll(3);
  await until(() => L.S.phase === 'roll' && L.S.tok[2][0] === 15);
  check('Free Hand move captures an opponent and earns another roll', L.S.tok[1][0] === -1 && L.S.turn === 0, [L.S.tok[1], L.S.turn]);
  // 5. exact finish still applies to the partner's pawns
  t = base(); t[0] = HOME.slice(); t[2] = [56, 56, 56, 54]; L.setS(state(t, { free: [true, false, false, false] })); L.updateHUD();
  L.roll(5);
  await until(() => L.S.phase === 'roll' && L.S.turn !== 0);
  check('overshooting the centre is not allowed (exact finish)', L.S.tok[2][3] === 54 && L.S.phase !== 'over', [L.S.tok[2], L.S.phase]);

  // ---- Wins ----
  // one partner finishing is not a team win
  t = base(); t[0] = [56, 56, 56, 55]; t[2][0] = 10; L.setS(state(t)); L.updateHUD();
  L.roll(1);
  await until(() => L.S.tok[0][3] === 56 && L.S.phase === 'roll');
  check('Red finishing alone does not win; Red rolls again and needs a 6', L.S.phase === 'roll' && L.S.winner === -1 && L.S.turn === 0 && L.waitingSix(0), [L.S.phase, L.S.winner, L.S.turn]);
  // the team wins when the second partner finishes (through Free Hand)
  t = base(); t[0] = HOME.slice(); t[2] = [56, 56, 56, 55]; L.setS(state(t, { free: [true, false, false, false] })); L.updateHUD();
  L.roll(1);
  await until(() => L.S.phase === 'over');
  check('team victory as soon as both partners are home', L.S.phase === 'over' && [0, 2].includes(L.S.winner) && /Red & Yellow|team/i.test(document.getElementById('winTitle').textContent), [L.S.phase, L.S.winner, document.getElementById('winTitle').textContent]);
  closeWin();
  // the partner can also finish on its own turn
  t = base(); t[0] = HOME.slice(); t[2] = [56, 56, 56, 55]; L.setS(state(t, { turn: 2 })); L.updateHUD();
  L.roll(1);
  await until(() => L.S.phase === 'over');
  check('team victory when Yellow finishes on its own turn', L.S.phase === 'over' && [0, 2].includes(L.S.winner), [L.S.phase, L.S.winner]);
  closeWin();
  // Individual Mode: finishing four pawns still wins at once (unchanged)
  t = base(); t[0] = [56, 56, 56, 55]; L.setS(state(t, { teams: false })); L.updateHUD();
  L.roll(1);
  await until(() => L.S.phase === 'over');
  check('Individual: four pawns home wins immediately', L.S.phase === 'over' && L.S.winner === 0, [L.S.phase, L.S.winner]);
  closeWin();

  // ---- Computer players follow the same rules ----
  t = base(); t[1] = HOME.slice(); t[3][0] = 10;
  L.setS(state(t, { players: ['human', 'cpu', 'human', 'cpu'], names: ['Red', 'Mocha', 'Yellow', 'Espresso'], turn: 1 })); L.updateHUD();
  L.roll(2);
  await until(() => L.S.phase === 'roll' && L.S.turn !== 1);
  check('computer: finished, no 6 yet, cannot move its partner', !L.S.free[1] && L.S.tok[3][0] === 10, [L.S.free, L.S.tok[3]]);
  t = base(); t[1] = HOME.slice(); t[3][0] = 10;
  L.setS(state(t, { players: ['human', 'cpu', 'human', 'cpu'], names: ['Red', 'Mocha', 'Yellow', 'Espresso'], turn: 1, free: [false, true, false, false] })); L.updateHUD();
  L.roll(2);
  await until(() => L.S.tok[3][0] === 12);
  check('computer with Free Hand moves its partner (Blue)', L.S.tok[3][0] === 12, L.S.tok[3]);
  await until(() => L.S.phase === 'roll');

  clearInterval(unpause);
  L.setS(saved); L.updateHUD();
  const failed = results.filter(r => !r.ok);
  return { passed: results.length - failed.length, failed: failed.length, failures: failed };
})();
