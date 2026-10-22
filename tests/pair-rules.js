// Pair Feature rule tests for Ludo Zing Mymensingh.
// Run in the browser console on the game page (it uses the window.__ludo test hook): paste the whole file.
// Resolves to { passed, failed, failures }.
(async () => {
  const L = window.__ludo;
  const results = [];
  const check = (name, ok, got) => results.push({ name, ok: !!ok, got: ok ? undefined : JSON.stringify(got) });

  // Colours: 0 red (start abs 0), 1 green (13), 2 yellow (26), 3 blue (39). abs = (start + progress) % 52.
  const prog = (c, abs) => (abs - L.OFF[c] + 52) % 52;
  const bAt = a => prog(3, a);
  function state(tok, pairs = [], extra = {}) {
    return Object.assign({ id: -1, players: ['human', 'cpu', 'cpu', 'cpu'], names: ['You', 'Mocha', 'Biscotti', 'Espresso'],
      view: 0, tok, pairs, turn: 0, dice: 0, sixes: 0, phase: 'roll', winner: -1, pick: null }, extra);
  }
  const base = () => [[-1, -1, -1, -1], [-1, -1, -1, -1], [-1, -1, -1, -1], [-1, -1, -1, -1]];
  const saved = L.S;

  // ---- Formation ----
  let t = base(); t[0][0] = 10; t[0][1] = 10; L.setS(state(t));
  check('2. same-colour pawns on a plain track square can pair', L.pairPartner(0, 1) === 0, L.pairPartner(0, 1));
  t = base(); t[0][0] = 0; t[0][1] = 0; L.setS(state(t));
  check('1. no pair offered on own start square (Home Base cell)', L.pairPartner(0, 1) === -1);
  t = base(); t[0][0] = 13; t[0][1] = 13; L.setS(state(t));
  check('1. no pair offered on an opponent start square', L.pairPartner(0, 1) === -1);
  t = base(); t[0][0] = 10; t[0][1] = 12; L.setS(state(t));
  check('passing over a pawn does not offer a pair', L.pairPartner(0, 1) === -1);
  t = base(); t[0][0] = t[0][1] = t[0][2] = 10; L.setS(state(t, [{ c: 0, a: 0, b: 1 }]));
  check('no pairing with pawns already in a pair', L.pairPartner(0, 2) === -1);
  t = base(); t[0][0] = t[0][1] = 53; L.setS(state(t));
  check('no pairing inside the home column', L.pairPartner(0, 1) === -1);

  // ---- Pair movement ----
  t = base(); t[0][0] = t[0][1] = 10; L.setS(state(t, [{ c: 0, a: 0, b: 1 }]));
  check('10. pair: 2 → 1 cell, 4 → 2, 6 → 3', L.dest(0, 0, 2) === 11 && L.dest(0, 0, 4) === 12 && L.dest(0, 0, 6) === 13);
  check('11. pair cannot use 1, 3 or 5', [1, 3, 5].every(d => L.dest(0, 0, d) === null));
  check('either pawn of a pair gives the same move', L.dest(0, 1, 4) === L.dest(0, 0, 4));
  t = base(); t[0][0] = t[0][1] = 10; t[0][2] = 5; L.setS(state(t, [{ c: 0, a: 0, b: 1 }], { dice: 3 }));
  check('11. odd roll still moves a normal pawn', JSON.stringify(L.movables()) === '[2]', L.movables());

  // ---- Blocking ----
  t = base(); t[0][0] = t[0][1] = 10; t[3][0] = bAt(7); L.setS(state(t, [{ c: 0, a: 0, b: 1 }], { turn: 3 }));
  check('6. single cannot jump an opponent pair', L.dest(3, 0, 5) === null);
  check('6. single may land on the pair square', L.dest(3, 0, 3) === bAt(10));
  t[3][0] = bAt(10); L.setS(state(t, [{ c: 0, a: 0, b: 1 }], { turn: 3 }));
  check('6. single on the pair square passes only with a 1', L.dest(3, 0, 1) === bAt(11) && [2, 3, 4, 5, 6].every(d => L.dest(3, 0, d) === null));
  t = base(); t[0][0] = t[0][1] = 10; t[3][0] = t[3][1] = bAt(9); L.setS(state(t, [{ c: 0, a: 0, b: 1 }, { c: 3, a: 0, b: 1 }], { turn: 3 }));
  check('7. a pair passes an opponent pair on an even roll (no 1 needed)', L.dest(3, 0, 4) === bAt(11) && L.dest(3, 0, 6) === bAt(12), [L.dest(3, 0, 4), L.dest(3, 0, 6)]);
  t[3][0] = t[3][1] = bAt(10); L.setS(state(t, [{ c: 0, a: 0, b: 1 }, { c: 3, a: 0, b: 1 }], { turn: 3 }));
  check('7. a pair sharing a square with an opponent pair can leave on an even roll', L.dest(3, 0, 2) === bAt(11));
  check('7. … but still never on an odd roll', L.dest(3, 0, 1) === null);

  // ---- Capture ----
  t = base(); t[0][0] = t[0][1] = 10; t[3][0] = bAt(7); L.setS(state(t, [{ c: 0, a: 0, b: 1 }], { turn: 3 }));
  check('a single pawn cannot capture a pair', L.victimsAt(3, bAt(10), false).length === 0);
  t = base(); t[0][0] = t[0][1] = 10; t[3][0] = t[3][1] = bAt(9); L.setS(state(t, [{ c: 0, a: 0, b: 1 }, { c: 3, a: 0, b: 1 }], { turn: 3 }));
  check('a pair captures a pair (both pawns)', JSON.stringify(L.victimsAt(3, bAt(10), true)) === '[[0,0],[0,1]]');
  t = base(); t[0][0] = t[0][1] = 8; t[3][0] = t[3][1] = bAt(6); L.setS(state(t, [{ c: 0, a: 0, b: 1 }, { c: 3, a: 0, b: 1 }], { turn: 3 }));
  check('no pair capture on a safe square', L.victimsAt(3, bAt(8), true).length === 0);
  t = base(); t[0][2] = 10; t[0][3] = 10; t[3][0] = bAt(7); L.setS(state(t, [], { turn: 3 }));
  check('a single still captures only one of a loose stack', L.victimsAt(3, bAt(10), false).length === 1);

  // ---- Start squares (Home Base cells) ----
  check('3/4. start squares of every colour count', [0, 13, 26, 39].every(p => L.onStartSquare(0, p)));
  check('5. plain and star squares do not', [10, 8, 21].every(p => !L.onStartSquare(0, p)));

  // ---- Regression for normal pawns ----
  t = base(); t[0][3] = 50; L.setS(state(t));
  check('15. leave base only on a 6', L.dest(0, 0, 6) === 0 && L.dest(0, 0, 5) === null);
  check('15. exact roll to finish', L.dest(0, 3, 6) === 56 && (() => { L.S.tok[0][3] = 53; return L.dest(0, 3, 4) === null; })());
  t = base(); t[0][0] = t[0][1] = 20; L.setS(state(t, [{ c: 0, a: 0, b: 1 }]));
  check('13. stuck message for a pair on an odd roll', L.stuckReason(0, 3) === 'A pair needs an even roll.');

  L.setS(saved);
  const failed = results.filter(r => !r.ok);
  return { passed: results.length - failed.length, failed: failed.length, failures: failed };
})();
