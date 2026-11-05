// Pawn skin tests for Ludo Zing Mymensingh.
// Run in the browser console on the source game page with ?vt=1, in a foreground tab, after the splash: paste the
// whole file. Resolves to { passed, failed, failures }. Purely cosmetic feature: checks the board behaves exactly as
// with the Classic pawn (footprint, layout, picking, moves, stacks, captures, pairs, Pair Mode) for every skin.
(async () => {
  const L = window.__ludo, K = L.PawnSkins, $ = id => document.getElementById(id), P = L.P;
  const results = [];
  const check = (name, ok, got) => results.push({ name, ok: !!ok, got: ok ? undefined : JSON.stringify(got) });
  const sleep = ms => new Promise(r => setTimeout(r, ms));
  const frame = () => new Promise(r => { requestAnimationFrame(() => requestAnimationFrame(r)); setTimeout(r, 120); });   // a hidden pane has no frames
  async function until(pred, ms = 20000) { const t0 = performance.now(); while (performance.now() - t0 < ms) { if (pred()) return true; await sleep(40); } return false; }
  const unpause = setInterval(() => { if (!$('pauseSheet').hidden) $('resumeBtn').click(); }, 50);
  const keep = JSON.stringify({ coins: P.coins, pawnSkins: P.pawnSkins, pawnSkin: P.pawnSkin });
  const IDS = ['classic', 'royal', 'ice', 'candy', 'marble', 'robo', 'wizard', 'fruity', 'blossom', 'pirate', 'space', 'dragon'];
    const near = (a, b, e = 1e-4) => Math.abs(a - b) < e;
  const flat = () => L.toks.flat();

  // ---- the catalogue ----
  check('12 skins in the expected order', K.LIST.map(s => s.id).join() === IDS.join(), K.LIST.map(s => s.id));
  check('Classic is free; every other skin has a price', !K.byId('classic').price && K.LIST.slice(1).every(s => s.price > 0));
  check('every skin has a name, a description and a card colour', K.LIST.every(s => s.name && s.desc && /gradient/.test(s.g)));
  check('a new player owns and has equipped only Classic', JSON.stringify(P.pawnSkins) === '["classic"]' && P.pawnSkin === 'classic', [P.pawnSkins, P.pawnSkin]);

  // ---- every skin x colour: built, same footprint / base / pivot, player colour first, light on triangles ----
  const box = new THREE.Box3(), b = new THREE.Box3();
  const classicBox = (() => { const g = new THREE.Group(); K.meshes('classic', 0).forEach(m => g.add(m)); return new THREE.Box3().setFromObject(g); })();
  const bad = { build: [], base: [], foot: [], height: [], colour: [], tris: [] };
  for (const id of IDS) for (let c = 0; c < 4; c++) {
    let ms;
    try { ms = K.meshes(id, c); } catch (e) { bad.build.push(id + c + ': ' + e.message); continue; }
    box.makeEmpty(); ms.forEach(m => { m.geometry.computeBoundingBox(); b.copy(m.geometry.boundingBox); box.union(b); });
    if (!near(box.min.y, 0, .002)) bad.base.push([id, c, box.min.y]);
    const r = Math.max(-box.min.x, box.max.x, -box.min.z, box.max.z);
    if (r > .385) bad.foot.push([id, c, +r.toFixed(3)]);
    if (box.max.y < .9 || box.max.y > 1.3) bad.height.push([id, c, +box.max.y.toFixed(3)]);
    const main = ms[0].material;   // the body: the player-colour material, also the one the movable glow drives
    if (!main.emissive || main.emissive.getHexString() !== L.toks[c][0].classicMat.emissive.getHexString()) bad.colour.push([id, c]);
    if (K.tris(id, c) > 3600) bad.tris.push([id, c, K.tris(id, c)]);
  }
  // Top View pose: head parts tipped back fully must still stand inside the footprint
  const tilted = [];
  for (const id of IDS) for (let c = 0; c < 4; c++) {
    const g = new THREE.Group(), ms = K.meshes(id, c); ms.forEach(m => g.add(m));
    K.pose({ c, skin: ms }, 1); g.updateMatrixWorld(true);
    const bb = new THREE.Box3().setFromObject(g), r = Math.max(-bb.min.x, bb.max.x, -bb.min.z, bb.max.z);
    if (r > .385 || bb.min.y < -.002) tilted.push([id, c, +r.toFixed(3), +bb.min.y.toFixed(3)]);
  }
  check('all 48 variants build', !bad.build.length, bad.build);
  check('…and with the head tipped back for Top View they still fit the footprint', !tilted.length, tilted);
  check('every variant stands on the same base (bottom at y = 0, like Classic)', !bad.base.length && near(classicBox.min.y, 0), bad.base);
  check('every variant stays inside the Classic footprint (radius .385)', !bad.foot.length, bad.foot);
  check('every variant keeps a pawn height (0.9 – 1.3)', !bad.height.length, bad.height);
  check('the body of every variant uses the player colour (and drives the movable glow)', !bad.colour.length, bad.colour);
  check('every variant stays under 3,600 triangles', !bad.tris.length, bad.tris);
  check('Fruity: a different fruit head per colour', new Set([0, 1, 2, 3].map(c => K.meshes('fruity', c).filter(m => m.userData.head).map(m => m.geometry.uuid).join())).size === 4);
  check('every themed skin has its own body (not the Classic one), except Royal Crown and Marble', K.LIST.filter(x => !['classic', 'royal', 'marble'].includes(x.id)).every(x => K.meshes(x.id, 0)[0].geometry !== K.meshes('classic', 0)[0].geometry));

  // ---- swapping skins on the board ----
  L.newGame(['human', 'human', 'human', 'human'], false); await sleep(400);
  const pickBefore = L.pickables.length, ringsOk = () => flat().every(t => t.g.children.includes(t.ring) && t.g.children.includes(t.pairRing));
  const S0 = JSON.stringify(L.S);
  P.pawnSkins = IDS.slice();
  const layout = () => JSON.stringify(flat().map(t => [t.target.x.toFixed(4), t.target.z.toFixed(4), t.scale, t.paired, t.g.visible]));
  const lay0 = layout();
  const sharing = [], picks = [], glows = [];
  for (const id of IDS) {
    L.usePawnSkin(id); await frame();
    const t0 = L.toks[1][0], t1 = L.toks[1][3];
    if (!t0.skin.every((m, k) => m.geometry === t1.skin[k].geometry && m.material === t1.skin[k].material)) sharing.push(id);
    if (L.pickables.length !== flat().reduce((n, t) => n + t.skin.length, 0) || !flat().every(t => t.skin.every(m => L.pickables.includes(m) && m.parent === t.g && m.userData.tok.c === t.c && m.userData.tok.i === t.i))) picks.push(id);
    if (!flat().every(t => t.mat === t.skin[0].material)) glows.push(id);
  }
  check('switching through all 12 skins never touches the game state', JSON.stringify(L.S) === S0);
  check('…nor the layout (targets, scales, pairs, visibility)', layout() === lay0);
  check('every token keeps its selection ring and pair ring', ringsOk());
  check('the 16 tokens of a skin share geometry and materials', !sharing.length, sharing);
  check('pickables hold exactly the current skin’s meshes, each tagged with its token', !picks.length, picks);
  check('the movable glow follows the skin’s player-colour material', !glows.length, glows);
  L.usePawnSkin('dragon'); await frame();
  check('themed pawns turn to face the camera', flat().every(t => near(t.g.rotation.y, L.toks[0][0].g.rotation.y)) && Math.abs(L.toks[0][0].g.rotation.y) > 0);
  L.usePawnSkin('classic'); await frame();
  check('Classic never turns (unchanged from before)', flat().every(t => t.g.rotation.y === 0) && L.pickables.length === pickBefore);

  // ---- Top View: heads look up at the camera, faces upright on screen; 3D View untouched ----
  const camRadio = v => { const r = document.querySelector(`input[name=cam][value="${v}"]`); r.checked = true; r.dispatchEvent(new Event('change')); };
  const headTilt = () => flat().flatMap(t => t.skin.filter(m => m.userData.head).map(m => m.rotation.x));
  L.usePawnSkin('robo'); camRadio('top'); await sleep(400); await frame();
  check('Top View: a themed pawn’s head parts tip back to face the camera', headTilt().length && headTilt().every(a => a < -1), headTilt().slice(0, 4));
  { const t = L.toks[0][0], up = L.camera.up, a = t.g.rotation.y;   // the face's "up" (local -z after the tilt) along the screen's up
    check('Top View: faces are upright on screen (turned with the camera roll)', (-Math.sin(a)) * up.x + (-Math.cos(a)) * up.z > .99, [a, up]); }
  { const before = layout(); L.usePawnSkin('classic'); await frame();
    check('Top View: Classic stays exactly as before (no turn, no tilt)', flat().every(t => t.g.rotation.y === 0 && t.skin.every(m => m.rotation.x === 0)) && layout() === before); }
  camRadio('3d'); L.usePawnSkin('space'); await sleep(400); await frame();
  check('3D View: heads stay upright (no tilt)', headTilt().every(a => a === 0), headTilt().slice(0, 4));

  // ---- the real game with skins: moves for all 4 colours, picking, stacks, captures, pairs, Pair Mode ----
  const base = () => [[-1, -1, -1, -1], [-1, -1, -1, -1], [-1, -1, -1, -1], [-1, -1, -1, -1]];
  let nextId = 9700;
  const state = (tok, pairs = [], extra = {}) => Object.assign({ id: ++nextId, players: ['human', 'human', 'human', 'human'],
    names: ['Red', 'Green', 'Yellow', 'Blue'], view: 0, tok, pairs, turn: 0, dice: 0, sixes: 0, phase: 'roll', winner: -1, pick: null,
    teams: false, free: [false, false, false, false] }, extra);
  async function play(v, pick) {
    L.roll(v);
    await until(() => ['choose', 'pick', 'roll', 'over'].includes(L.S.phase));
    if (L.S.phase === 'choose' && pick !== undefined) L.move(pick);
    await until(() => L.S.phase === 'roll' || L.S.phase === 'over');
  }
  const moved = [];
  for (let k = 0; k < IDS.length; k++) {
    const id = IDS[k], c = k % 4;
    L.usePawnSkin(id);
    const t = base(); t[c][0] = 3; L.setS(state(t, [], { turn: c }));
    await play(4);
    const tk = L.toks[c][0];
    await until(() => tk.g.position.distanceTo(tk.target) < .02, 4000);
    if (L.S.tok[c][0] !== 7 || tk.g.position.distanceTo(tk.target) > .02) moved.push([id, c, L.S.tok[c][0]]);
  }
  check('a roll moves the pawn and it lands on its square: 12 skins, every colour 3 times', !moved.length, moved);

  // picking: tap a glowing token on the canvas
  const cv = L.renderer.domElement, rect = cv.getBoundingClientRect();
  if (rect.width < 10) check('picking needs a visible page (the browser pane is hidden)', false, rect);
  else {
    const pickFails = [];
    for (const id of ['robo', 'blossom', 'wizard', 'pirate']) {
      L.usePawnSkin(id);
      for (const c of [0, 1, 2, 3]) {
        const t = base(); t[c][0] = 3; t[c][1] = 20; L.setS(state(t, [], { turn: c }));
        await frame(); await sleep(250);
        L.roll(3); await until(() => L.S.phase === 'choose');
        const tk = L.toks[c][1]; await frame();
        const p = tk.g.position.clone().setY(tk.g.position.y + .45).project(L.camera);
        const x = rect.left + (p.x + 1) / 2 * rect.width, y = rect.top + (1 - p.y) / 2 * rect.height;
        cv.dispatchEvent(new PointerEvent('pointerup', { clientX: x, clientY: y, bubbles: true }));
        await until(() => L.S.phase === 'roll' || L.S.phase === 'over');
        if (L.S.tok[c][1] !== 23 || L.S.tok[c][0] !== 3) pickFails.push([id, c, L.S.tok[c]]);
      }
    }
    check('tapping a skinned pawn picks exactly that pawn (4 skins x 4 colours)', !pickFails.length, pickFails);
    camRadio('top'); await sleep(400);
    const topFails = [];
    for (const id of ['robo', 'space', 'pirate']) {
      L.usePawnSkin(id);
      for (const c of [0, 2]) {
        const t = base(); t[c][0] = 3; t[c][1] = 20; L.setS(state(t, [], { turn: c }));
        await frame(); await sleep(250);
        L.roll(3); await until(() => L.S.phase === 'choose');
        const tk = L.toks[c][1]; await frame();
        const p = tk.g.position.clone().setY(tk.g.position.y + .7).project(L.camera);
        cv.dispatchEvent(new PointerEvent('pointerup', { clientX: rect.left + (p.x + 1) / 2 * rect.width, clientY: rect.top + (1 - p.y) / 2 * rect.height, bubbles: true }));
        await until(() => L.S.phase === 'roll' || L.S.phase === 'over');
        if (L.S.tok[c][1] !== 23 || L.S.tok[c][0] !== 3) topFails.push([id, c, L.S.tok[c]]);
      }
    }
    check('Top View: tapping the tipped-back head picks that pawn', !topFails.length, topFails);
    camRadio('3d'); await sleep(400);
  }

  // stacks: same layout as Classic
  const stackT = base(); stackT[0][0] = 8; stackT[1][0] = (8 - 13 + 52) % 52; stackT[2][0] = (8 - 26 + 52) % 52; stackT[3][0] = (8 - 39 + 52) % 52;
  L.usePawnSkin('classic'); L.setS(state(stackT)); const stackClassic = layout();
  L.usePawnSkin('space'); L.setS(state(stackT));
  check('a stack of all 4 colours on a star square lays out exactly like Classic', layout() === stackClassic);
  check('…the stacked pawns shrink to .66 and stand apart', [0, 1, 2, 3].every(c => L.toks[c][0].scale === .66) && new Set([0, 1, 2, 3].map(c => L.toks[c][0].target.x.toFixed(3) + L.toks[c][0].target.z.toFixed(3))).size === 4);

  // capture: a red single lands on a lone blue pawn (not safe) -> blue goes home
  const capFails = [];
  for (const id of ['candy', 'dragon', 'ice']) {
    L.usePawnSkin(id);
    const t = base(); t[0][0] = 10; t[3][0] = (12 - 39 + 52) % 52; L.setS(state(t));
    await play(2);
    const vt = L.toks[3][0];
    await until(() => vt.g.position.distanceTo(vt.target) < .02, 5000);
    if (L.S.tok[3][0] !== -1 || L.S.tok[0][0] !== 12 || vt.g.position.distanceTo(vt.target) > .02) capFails.push([id, L.S.tok[0][0], L.S.tok[3][0]]);
  }
  check('captures send the pawn home with skins on (3 skins)', !capFails.length, capFails);

  // same-colour pair: ring, side-by-side .8 scale, moves together
  L.usePawnSkin('royal');
  { const t = base(); t[1][0] = t[1][1] = 20; L.setS(state(t, [{ c: 1, a: 0, b: 1 }], { turn: 1 }));
    const pairClassic = (L.usePawnSkin('classic'), L.setS(state(t, [{ c: 1, a: 0, b: 1 }], { turn: 1 })), layout());
    L.usePawnSkin('royal'); L.setS(state(t, [{ c: 1, a: 0, b: 1 }], { turn: 1 })); await frame();
    check('a pair lays out like Classic (side by side, .8 scale) and shows its gold ring', layout() === pairClassic && L.toks[1][0].pairRing.visible && L.toks[1][1].pairRing.visible && L.toks[1][0].scale === .8);
    await play(4, 0);
    check('the pair moves together (half the roll)', L.S.tok[1][0] === 22 && L.S.tok[1][1] === 22, L.S.tok[1]); }

  // Pair Mode (teams): partners never capture each other, with skins
  L.usePawnSkin('fruity');
  { const t = base(); t[0][0] = 10; t[2][0] = (12 - 26 + 52) % 52;
    L.setS(state(t, [], { teams: true })); await play(2);
    check('Pair Mode: landing on the partner captures nothing', L.S.tok[0][0] === 12 && L.S.tok[2][0] === (12 - 26 + 52) % 52, L.S.tok); }

  // ---- Shop / Inventory ----
  Object.assign(P, JSON.parse(keep));
  L.usePawnSkin('classic');
  L.goHome(); await sleep(50);
  P.coins = 100;
  check('Buy without coins spends nothing and owns nothing', L.buyPawnSkin('royal') === false && P.coins === 100 && !P.pawnSkins.includes('royal'));
  P.coins = 3010;
  check('Buy charges the price once, owns and equips the skin', L.buyPawnSkin('royal') === true && P.coins === 10 && P.pawnSkins.includes('royal') && P.pawnSkin === 'royal' && K.current === 'royal');
  check('an owned skin is never sold twice', L.buyPawnSkin('royal') === false && P.coins === 10);
  check('the purchase is saved', (L.Store.data.profile.pawnSkins || []).includes('royal') && L.Store.data.profile.pawnSkin === 'royal');
  L.renderShop(); L.openSheet('shopSheet'); L.showShopTab('pawns'); await sleep(900);
  const cards = [...$('shopPawns').querySelectorAll('.item')];
  check('Shop has a Pawns tab', !!document.querySelector('#shopTabs [data-tab="pawns"]') && !$('shopPawns').hidden);
  check('Shop > Pawns lists all 12 skins', cards.length === 12 && cards.map(c => c.dataset.skin).join() === IDS.join());
  check('each card shows a rendered picture of the four colours', cards.every(c => { const i = c.querySelector('img[data-pawn-pic]'); return i && !i.hidden && /^data:image\/png/.test(i.src); }));
  check('tags: Equipped / Owned / Locked', /Equipped/.test(cards[1].textContent) && /Owned/.test(cards[0].textContent) && /Locked/.test(cards[2].textContent));
  $('shopPawns').querySelector('[data-pawn-use="classic"]').click();
  check('Use in the Shop equips an owned skin', P.pawnSkin === 'classic' && K.current === 'classic');
  $('shopPawns').querySelector('[data-pawn-all]').click(); await sleep(900);
  const figs = [...$('pawnAllGrid').querySelectorAll('figure')];
  check('Compare all: the 12 skins side by side, each with its picture and name', !$('pawnAllSheet').hidden && figs.length === 12 && figs.every(f => !f.querySelector('img').hidden && f.querySelector('figcaption').textContent));
  L.closeSheet('pawnAllSheet'); L.closeSheet('shopSheet');
  L.renderInv(); L.openSheet('invSheet'); await sleep(30);
  $('invTabs').querySelector('[data-tab="pawns"]').click(); await sleep(300);
  const inv = [...$('invPawns').querySelectorAll('.item')];
  check('Inventory > Pawns lists only owned skins', inv.map(c => c.dataset.skin).join() === 'classic,royal', inv.map(c => c.dataset.skin));
  $('invPawns').querySelector('[data-pawn-use="royal"]').click();
  check('Use in Inventory equips the skin and saves it', P.pawnSkin === 'royal' && K.current === 'royal' && L.Store.data.profile.pawnSkin === 'royal');
  L.closeSheet('invSheet');
  P.pawnSkins = ['bogus', 'royal', 'royal']; P.pawnSkin = 'dragon'; L.ensureProfile();
  check('the profile repairs itself: known ids only, Classic always owned, an unowned equip falls back to Classic', JSON.stringify(P.pawnSkins) === '["classic","royal"]' && P.pawnSkin === 'classic', [P.pawnSkins, P.pawnSkin]);
  delete P.pawnSkins; delete P.pawnSkin; L.ensureProfile();
  check('an older save gains the fields (owns Classic, Classic equipped)', JSON.stringify(P.pawnSkins) === '["classic"]' && P.pawnSkin === 'classic');

  Object.assign(P, JSON.parse(keep)); L.usePawnSkin('classic'); K.apply(P.pawnSkin);
  clearInterval(unpause);
  L.goHome(); await sleep(50);
  const failures = results.filter(r => !r.ok);
  return { passed: results.length - failures.length, failed: failures.length, failures };
})();
