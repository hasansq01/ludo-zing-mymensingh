// Shop preview (View on Rooms / Scenes cards) tests for Ludo Zing Mymensingh.
// Run in the browser console on the source game page with ?vt=1 (test mode: nothing is written to browser storage),
// in a foreground tab, after the splash: paste the whole file. Resolves to { passed, failed, failures }.
(async () => {
  const L = window.__ludo, P = L.P, Pv = L.Preview, $ = id => document.getElementById(id);
  const results = [];
  const check = (name, ok, got) => results.push({ name, ok: !!ok, got: ok ? undefined : JSON.stringify(got) });
  const sleep = ms => new Promise(r => setTimeout(r, ms));
  const frames = n => new Promise(r => { let k = 0; const f = () => (++k >= n ? r() : requestAnimationFrame(f)); requestAnimationFrame(f); });
  const backup = JSON.stringify({ coins: P.coins, rooms: P.rooms, room: P.room, scenes: P.scenes, scene: P.scene });
  await sleep(800);   // the home camera settles after the splash first
  const camBefore = JSON.stringify(L.cam()), slViewBefore = L.slView();
  const act = $('pvAct'), view = $('pvView');
  const shopOpen = () => { L.renderShop(); L.openSheet('shopSheet'); };
  const ptr = (type, x, y, id = 1) => view.dispatchEvent(new PointerEvent(type, { bubbles: true, cancelable: true, clientX: x, clientY: y, pointerId: id, isPrimary: id === 1 }));

  // a fresh-ish player: default rooms, jungle only, little money
  const room = L.ROOM_LIST.find(r => r.price > 0), room2 = L.ROOM_LIST.filter(r => r.price > 0)[1];
  P.rooms = L.ROOM_LIST.filter(r => !r.price).map(r => r.id); P.room = P.rooms[0]; L.Rooms.set(P.room);
  P.scenes = ['jungle']; P.scene = 'jungle'; L.Jungle.setScene('jungle'); P.coins = 0;

  // ---- cards ----
  shopOpen();
  const roomCards = [...document.querySelectorAll('#shopRooms .item')], sceneCards = [...document.querySelectorAll('#shopScenes .item')];
  check('every Shop room card has View + its own action', roomCards.length === L.ROOM_LIST.length && roomCards.every(c => c.querySelector('[data-pv^="room:"]') && c.querySelectorAll('button').length === 2));
  check('every Shop scene card has View + its own action', sceneCards.length === L.SL_SCENES.length && sceneCards.every(c => c.querySelector('[data-pv^="scene:"]') && c.querySelectorAll('button').length === 2));
  const eqCard = roomCards.find(c => c.classList.contains('eq'));
  check('the room in use keeps "In use" next to View', eqCard && /In use/.test(eqCard.querySelector('.btns button:not(.alt)').textContent) && eqCard.querySelector('.btns button:not(.alt)').disabled);
  check('Dice and Coins tabs have no View', !document.querySelector('#shopDice [data-pv], #shopItems [data-pv]'));
  L.renderInv();
  check('Inventory has no View buttons', !document.querySelector('#invPane [data-pv]'));

  // ---- room preview: opening changes nothing about the player ----
  const coins0 = P.coins, room0 = P.room;
  shopOpen();
  document.querySelector(`#shopRooms [data-pv="room:${room.id}"]`).click();
  await frames(3);
  check('View opens the full preview', Pv.on && !$('pvSheet').hidden && $('shopSheet').hidden && document.body.classList.contains('pv-open'));
  check('the real room is drawn (switched in for the preview)', Pv.ready && L.Rooms.current === room.id);
  check('panel: name, description, price, Buy — price', $('pvName').textContent === room.name && $('pvDesc').textContent === room.desc && /Buy — /.test(act.textContent) && act.textContent.includes(act.textContent.split('— ')[1]) && $('pvPrice').textContent.trim().length > 0);
  check('opening a preview spends nothing and equips nothing', P.coins === coins0 && P.room === room0 && !P.rooms.includes(room.id));
  const b = Pv.box(), card = document.querySelector('.pv').getBoundingClientRect(), cv = document.querySelector('#pvView canvas.pv-canvas');
  check('one card: the 3D view fills the card width, its own canvas fills the view', b.w >= card.width - 10 && b.h >= 120 && cv && Math.abs(cv.clientWidth - b.w) <= 1 && Math.abs(cv.clientHeight - b.h) <= 1, [b, card.width]);
  check('the card fits the frame (no overflow)', card.top >= 0 && card.bottom <= innerHeight + .5 && document.querySelector('.pv').scrollHeight <= document.querySelector('.pv').clientHeight + 1);

  // ---- camera controls ----
  const g0 = { ...Pv.goal };
  ptr('pointerdown', 200, 300); ptr('pointermove', 150, 280); ptr('pointerup', 150, 280);
  check('dragging turns the camera', Pv.goal.az !== g0.az || Pv.goal.el !== g0.el, [g0, Pv.goal]);
  check('drag hides the hint', $('pvHint').classList.contains('gone'));
  ptr('pointerdown', 200, 300); ptr('pointermove', -2000, 2000); ptr('pointerup', 0, 0);
  check('turning stops at the room limits', Pv.goal.az >= .3 - 1e-9 && Pv.goal.az <= .9 + 1e-9 && Pv.goal.el >= 0 && Pv.goal.el <= .62 + 1e-9, Pv.goal);
  let z = Pv.goal.zoom; $('pvZoomIn').click();
  check('zoom in button', Pv.goal.zoom < z); z = Pv.goal.zoom; $('pvZoomOut').click();
  check('zoom out button', Pv.goal.zoom > z);
  view.dispatchEvent(new WheelEvent('wheel', { deltaY: -5000, bubbles: true, cancelable: true }));
  check('wheel zoom stops at the closest limit', Math.abs(Pv.goal.zoom - .45) < 1e-9, Pv.goal.zoom);
  ptr('pointerdown', 100, 300, 1); ptr('pointerdown', 200, 300, 2); ptr('pointermove', 300, 300, 2); ptr('pointerup', 300, 300, 2); ptr('pointerup', 100, 300, 1);
  check('pinch apart zooms in / stays in limits', Pv.goal.zoom >= .45 && Pv.goal.zoom <= 1);
  $('pvReset').click();
  check('reset returns to the start view', Pv.goal.az === .72 && Pv.goal.el === 0 && Pv.goal.zoom === 1);
  await frames(4);
  check('the camera eases to its goal (in test mode at once)', Math.abs(Pv.o.az - .72) < 1e-6 && Math.abs(Pv.o.zoom - 1) < 1e-6, Pv.o);

  // ---- buy from the preview ----
  P.coins = room.price - 1; act.click();
  check('not enough coins: nothing spent, a clear note', P.coins === room.price - 1 && !P.rooms.includes(room.id) && /more coins/.test($('pvNote').textContent));
  P.coins = room.price + 50; act.click();
  check('Buy charges the price once and owns it', P.coins === 50 && P.rooms.includes(room.id), [P.coins, P.rooms]);
  check('…without equipping it; the button now reads Use', P.room === room0 && act.textContent === 'Use' && !act.disabled && !Pv.on === false);
  check('a second buy is refused (no double charge)', L.buyRoom(room.id, false) === false && P.coins === 50);
  check('the purchase is saved', (L.Store.data.profile.rooms || []).includes(room.id) && L.Store.data.profile.coins === 50);
  act.click();
  check('Use from the preview equips it; button reads In Use', P.room === room.id && act.textContent === 'In Use' && act.disabled && Pv.on);
  L.closeSheet('pvSheet'); await sleep(30);
  check('closing returns to the Shop with the new state', !Pv.on && !$('shopSheet').hidden && !document.body.classList.contains('pv-open') && /In use/.test(document.querySelector(`#shopRooms [data-pv="room:${room.id}"]`).closest('.item').textContent));
  check('…and the room in use is the one shown again', L.Rooms.current === P.room);
  check('the preview canvas (and its GPU context) is released on close', !document.querySelector('#pvView canvas'));

  // ---- just looking: close (Escape) brings back exactly what was in use ----
  const coins1 = P.coins, roomIn = P.room;
  document.querySelector(`#shopRooms [data-pv="room:${room2.id}"]`).click(); await frames(2);
  check('previewing another room switches the view only', L.Rooms.current === room2.id && P.room === roomIn);
  document.dispatchEvent(new KeyboardEvent('keydown', { key: 'Escape', bubbles: true }));
  await sleep(30);
  check('Escape closes the preview; room, coins unchanged', $('pvSheet').hidden && L.Rooms.current === roomIn && P.room === roomIn && P.coins === coins1);

  // ---- scene preview ----
  const sc = L.SL_SCENES.find(s => s.id === 'candy');
  L.showShopTab('scenes');
  document.querySelector(`#shopScenes [data-pv="scene:candy"]`).click();
  for (let i = 0; i < 40 && !Pv.ready; i++) await sleep(100);
  await frames(3);
  check('scene preview builds the real world', Pv.ready && L.Jungle.scene === 'candy' && L.Jungle.previewing);
  check('scene panel: S&L scene, Buy — 22K', /Snakes/.test($('pvKind').textContent) && $('pvName').textContent === sc.name && act.textContent === 'Buy — 22K');
  check('the equipped scene is not changed by looking', P.scene === 'jungle');
  P.coins = 1000; act.click();
  check('scene: not enough coins, nothing spent', P.coins === 1000 && !P.scenes.includes('candy'));
  P.coins = sc.price; act.click();
  check('scene: Buy charges once, owned, not equipped, button Use', P.coins === 0 && P.scenes.includes('candy') && P.scene === 'jungle' && act.textContent === 'Use');
  check('scene: no double charge', L.buyScene('candy', false) === false && P.coins === 0);
  L.closeSheet('pvSheet'); await sleep(30);
  check('closing restores the equipped scene (jungle) and frees the preview', !L.Jungle.previewing && L.Jungle.scene === 'jungle');
  document.querySelector(`#shopScenes [data-pv="scene:candy"]`).click();
  for (let i = 0; i < 40 && !Pv.ready; i++) await sleep(100);
  act.click();
  check('scene: Use from the preview equips it', P.scene === 'candy' && act.textContent === 'In Use');
  L.closeSheet('pvSheet'); await sleep(30);
  check('after equipping, the equipped scene stays built', L.Jungle.scene === 'candy');

  // ---- fallback + retry ----
  const realOpen = L.Jungle.previewOpen;
  L.Jungle.previewOpen = () => Promise.reject(new Error('test failure'));
  document.querySelector(`#shopScenes [data-pv="scene:desert"]`).click(); await sleep(60);
  check('a failed 3D preview shows the message and Retry', !$('pvMsg').hidden && !Pv.ready);
  L.Jungle.previewOpen = realOpen;
  $('pvRetry').click();
  for (let i = 0; i < 40 && !Pv.ready; i++) await sleep(100);
  check('Retry loads the 3D preview', Pv.ready && $('pvMsg').hidden && L.Jungle.scene === 'desert');
  L.closeSheet('pvSheet'); await sleep(30);
  check('…and closing restores the equipped scene', L.Jungle.scene === 'candy');

  // ---- nothing else moved ----
  await frames(3);
  check('game camera and its preferences untouched', JSON.stringify(L.cam()) === camBefore && L.slView() === slViewBefore, [camBefore, JSON.stringify(L.cam())]);

  // restore the player
  L.closeAllSheets && L.closeAllSheets();
  const bk = JSON.parse(backup); Object.assign(P, bk); L.Rooms.set(P.room); L.Jungle.setScene(P.scene); L.closeSheet('shopSheet');
  const failures = results.filter(r => !r.ok);
  return { passed: results.length - failures.length, failed: failures.length, failures };
})();
