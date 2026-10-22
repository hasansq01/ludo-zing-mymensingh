// Pair capture rules + automatic pair split in the home lane, for Ludo Zing Mymensingh.
// Run in the browser console on the source game page with ?vt=1 (uses the window.__ludo test hook): paste the whole file.
// Resolves to { passed, failed, failures }. Plays real rolls (forced values) and real moves.
(async () => {
  const L = window.__ludo;
  const results = [];
  const check = (name, ok, got) => results.push({ name, ok: !!ok, got: ok ? undefined : JSON.stringify(got) });
  const sleep = ms => new Promise(r => setTimeout(r, ms));
  async function until(pred, ms = 30000) { const t0 = performance.now(); while (performance.now() - t0 < ms) { if (pred()) return true; await sleep(40); } return false; }
  // the game pauses itself when the page is hidden (e.g. a background tab); keep it running while the tests play
  const unpause = setInterval(() => { if (!document.getElementById('pauseSheet').hidden) document.getElementById('resumeBtn').click(); }, 50);

  // Colours: 0 red (start abs 0), 1 green (13), 2 yellow (26), 3 blue (39). abs = (start + progress) % 52.
  const prog = (c, abs) => (abs - L.OFF[c] + 52) % 52;
  const base = () => [[-1, -1, -1, -1], [-1, -1, -1, -1], [-1, -1, -1, -1], [-1, -1, -1, -1]];
  let nextId = 9500;
  const state = (tok, pairs = [], extra = {}) => Object.assign({ id: ++nextId, players: ['human', 'human', 'human', 'human'],
    names: ['Red', 'Green', 'Yellow', 'Blue'], view: 0, tok, pairs, turn: 0, dice: 0, sixes: 0, phase: 'roll', winner: -1, pick: null,
    teams: false, free: [false, false, false, false] }, extra);
  const snap = () => JSON.stringify([L.S.tok, L.S.pairs]);
  // one real roll; `pick` is the token to move when the game asks for a choice
  async function play(v, pick) {
    const turn = L.S.turn;
    L.roll(v);
    await until(() => L.S.phase === 'choose' || L.S.phase === 'roll' || L.S.phase === 'over');
    if (L.S.phase === 'choose' && pick !== undefined) { L.move(pick); }
    await until(() => L.S.phase === 'roll' || L.S.phase === 'over');
    return turn;
  }
  const saved = L.S;

  // ---- 1. Capture rules (static) ----
  const R = 0, B = 3, bAt = a => prog(B, a);
  let t = base(); t[R][0] = t[R][1] = 10; t[B][0] = bAt(12); L.setS(state(t, [{ c: R, a: 0, b: 1 }]));
  check('static: a pair landing on a single captures nothing', L.victimsAt(R, 12, true).length === 0, L.victimsAt(R, 12, true));
  t = base(); t[R][0] = 10; t[B][0] = t[B][1] = bAt(12); L.setS(state(t, [{ c: B, a: 0, b: 1 }]));
  check('static: a single landing on a pair captures nothing', L.victimsAt(R, 12, false).length === 0);
  t = base(); t[R][0] = t[R][1] = 10; t[B][0] = t[B][1] = bAt(12); t[B][2] = bAt(12); L.setS(state(t, [{ c: R, a: 0, b: 1 }, { c: B, a: 0, b: 1 }]));
  check('static: on a square with a pair and a single, a pair takes only the pair', JSON.stringify(L.victimsAt(R, 12, true)) === '[[3,0],[3,1]]', L.victimsAt(R, 12, true));
  check('static: …and a single takes only the single', JSON.stringify(L.victimsAt(R, 12, false)) === '[[3,2]]', L.victimsAt(R, 12, false));

  // ---- 1. Capture rules (real moves) ----
  t = base(); t[R][0] = t[R][1] = 10; t[B][0] = bAt(12); L.setS(state(t, [{ c: R, a: 0, b: 1 }])); L.updateHUD();
  await play(4);
  check('real: a pair moving onto a single does not capture it; both share the square', L.S.tok[R][0] === 12 && L.S.tok[R][1] === 12 && L.S.tok[B][0] === bAt(12) && L.S.pairs.length === 1, L.S.tok);
  check('real: …no capture means no extra roll (turn passes on a 4)', L.S.turn !== R, L.S.turn);

  t = base(); t[R][0] = 10; t[B][0] = t[B][1] = bAt(12); L.setS(state(t, [{ c: B, a: 0, b: 1 }])); L.updateHUD();
  await play(2);
  check('real: a single moving onto a pair does not capture it', L.S.tok[R][0] === 12 && L.S.tok[B][0] === bAt(12) && L.S.tok[B][1] === bAt(12) && L.S.pairs.some(q => q.c === B), [L.S.tok, L.S.pairs]);

  t = base(); t[R][0] = t[R][1] = 10; t[B][0] = t[B][1] = bAt(12); L.setS(state(t, [{ c: R, a: 0, b: 1 }, { c: B, a: 0, b: 1 }])); L.updateHUD();
  await play(4);
  check('real: a pair moving onto a pair captures both pawns and rolls again', L.S.tok[B][0] === -1 && L.S.tok[B][1] === -1 && !L.S.pairs.some(q => q.c === B) && L.S.turn === R, [L.S.tok[B], L.S.turn]);

  t = base(); t[R][0] = 10; t[B][0] = bAt(12); L.setS(state(t)); L.updateHUD();
  await play(2);
  check('real: a single still captures a single (unchanged)', L.S.tok[B][0] === -1 && L.S.turn === R, [L.S.tok[B], L.S.turn]);

  t = base(); t[R][0] = t[R][1] = 6; t[B][0] = bAt(8); L.setS(state(t, [{ c: R, a: 0, b: 1 }])); L.updateHUD();
  await play(4);
  check('real: safe squares still protect (pair on a star with a single)', L.S.tok[B][0] === bAt(8) && L.S.tok[R][0] === 8, L.S.tok);

  // ---- 2. Automatic split on every home-lane cell (HOME[c], progress 51-55), all four colours ----
  // 51-53 are reached straight from the track (a pair moves half the roll); 54-55 can only be reached by a pair that
  // was already in the lane (e.g. a game saved before this rule), so those start from 52 / 53.
  const cases = [[50, 2, 51], [50, 4, 52], [50, 6, 53], [52, 4, 54], [53, 4, 55], [49, 4, 51], [48, 6, 51]];
  for (let c = 0; c < 4; c++) {
    for (const [from, d, to] of cases) {
      t = base(); t[c][0] = t[c][1] = from; t[c][2] = t[c][3] = 56;   // spare pawns home, so a 6 has only the pair to move
      const other = (c + 1) % 4; t[other][0] = 20;   // a bystander that must not change
      L.setS(state(t, [{ c, a: 0, b: 1 }], { turn: c })); L.updateHUD();
      check(`${c}: pair at ${from} can move ${d} to ${to}`, L.dest(c, 0, d) === to, L.dest(c, 0, d));
      await play(d);
      const ok = L.S.tok[c][0] === to && L.S.tok[c][1] === to && L.S.tok[c][2] === 56 && L.S.tok[c][3] === 56
        && L.S.pairs.length === 0 && L.S.tok[other][0] === 20 && L.S.tok.flat().length === 16;
      check(`${['Red', 'Green', 'Yellow', 'Blue'][c]}: pair ${from} +${d} lands on lane cell ${to} and splits once into two singles there`, ok, [L.S.tok[c], L.S.pairs]);
      check(`${['Red', 'Green', 'Yellow', 'Blue'][c]} ${to}: the split leaves no pairing offer and the turn follows the roll`, L.S.turn === (d === 6 ? c : (c + 1) % 4), L.S.turn);
      // afterwards the two pawns move independently under the normal rules
      L.S.turn = c; L.S.phase = 'roll'; L.S.sixes = 0; L.updateHUD();
      const before = snap();
      await play(1, 0);
      check(`${['Red', 'Green', 'Yellow', 'Blue'][c]} ${to}: a 1 then moves one pawn alone (odd rolls are fine: no longer a pair)`, L.S.tok[c][0] === to + 1 && L.S.tok[c][1] === to && L.S.pairs.length === 0, [before, L.S.tok[c]]);
      if (to + 2 <= 56) {
        L.S.turn = c; L.S.phase = 'roll'; L.S.sixes = 0; L.updateHUD();
        await play(1, 1);
        check(`${['Red', 'Green', 'Yellow', 'Blue'][c]} ${to}: the other pawn moves on its own too`, L.S.tok[c][1] === to + 1 && L.S.tok[c][0] === to + 1 && L.S.pairs.length === 0, L.S.tok[c]);
      }
    }
  }

  // ---- Unchanged pair behaviour elsewhere ----
  t = base(); t[R][0] = t[R][1] = 10; L.setS(state(t, [{ c: R, a: 0, b: 1 }])); L.updateHUD();
  await play(4);
  check('a pair on a plain track square stays a pair', L.S.tok[R][0] === 12 && L.S.pairs.length === 1, [L.S.tok[R], L.S.pairs]);
  t = base(); t[R][0] = t[R][1] = 11; L.setS(state(t, [{ c: R, a: 0, b: 1 }])); L.updateHUD();
  await play(4);
  check('a pair still splits on a start square (Green 13)', L.S.tok[R][0] === 13 && L.S.tok[R][1] === 13 && L.S.pairs.length === 0, [L.S.tok[R], L.S.pairs]);
  t = base(); t[R][0] = t[R][1] = 48; t[R][2] = 50; L.setS(state(t, [{ c: R, a: 0, b: 1 }])); L.updateHUD();
  check('a pair one cell before the lane cannot reach the centre in one move', L.dest(R, 0, 6) === 51);
  t = base(); t[R][0] = t[R][1] = 54; L.setS(state(t, [{ c: R, a: 0, b: 1 }])); L.updateHUD();
  await play(4);
  check('a legacy pair in the lane that reaches the centre finishes both pawns', L.S.tok[R][0] === 56 && L.S.tok[R][1] === 56 && L.S.pairs.length === 0, L.S.tok[R]);

  // Pair Mode: a team-mate pawn is never captured, by a pair or a single
  t = base(); t[0][0] = t[0][1] = 10; t[2][0] = prog(2, 12); L.setS(state(t, [{ c: 0, a: 0, b: 1 }], { teams: true }));
  check('Pair Mode: a pair landing on a partner single captures nothing', L.victimsAt(0, 12, true).length === 0);

  clearInterval(unpause);
  L.setS(saved); L.updateHUD();
  const failed = results.filter(r => !r.ok);
  return { passed: results.length - failed.length, failed: failed.length, failures: failed };
})();
