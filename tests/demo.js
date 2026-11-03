// Demo mode tests for Ludo Zing Mymensingh.
// Run in the browser console on the source game page with ?vt=1&demo=1, after the splash: paste the whole file.
// Resolves to { passed, failed, failures }. Demo mode: every price is 0 and everything is owned / unlocked.
(async () => {
  const L = window.__ludo, P = L.P, $ = id => document.getElementById(id);
  const results = [];
  const check = (name, ok, got) => results.push({ name, ok: !!ok, got: ok ? undefined : JSON.stringify(got) });
  const sleep = ms => new Promise(r => setTimeout(r, ms));

  check('demo mode is on (?demo=1)', L.DEMO === true);
  check('the root carries the demo class', document.documentElement.classList.contains('demo'));
  check('every room is owned', L.ROOM_LIST.every(r => P.rooms.includes(r.id) && r.price === 0));
  check('every Snakes & Ladders scene is owned', L.SL_SCENES.every(s => P.scenes.includes(s.id) && s.price === 0));
  check('every emote set is owned', L.EMOTE_SETS.every(s => P.emoteSets.includes(s.id) && s.price === 0));
  check('every pawn skin is owned', L.PawnSkins.LIST.every(s => P.pawnSkins.includes(s.id) && s.price === 0));
  check('every dice skin is owned', ['classic', 'crema', 'espresso', 'gold'].every(id => P.owned.includes(id)));

  L.renderShop(); L.openSheet('shopSheet'); await sleep(30);
  check('the Shop shows the demo note', getComputedStyle(document.querySelector('#shopSheet .demo-note')).display !== 'none');
  check('the Shop sells nothing: no Buy button anywhere is enabled', ![...document.querySelectorAll('#shopSheet [data-buy],#shopSheet [data-room-buy],#shopSheet [data-scene-buy],#shopSheet [data-emset-buy],#shopSheet [data-pawn-buy]')].some(b => !b.disabled));
  check('…and shows no prices on item cards', !document.querySelector('#shopRooms .price,#shopScenes .price,#shopDice .price,#shopEmotes .price,#shopPawns .price'));
  check('the Dice tab still lists the three dice (as owned)', $('shopDice').querySelectorAll('.item').length === 3);
  check('no Locked tags', !document.querySelector('#shopSheet .tag.lock'));
  $('shopPawns').querySelector('[data-pawn-use="pirate"]').click();
  check('any pawn skin can be used straight away, at no cost', P.pawnSkin === 'pirate' && L.PawnSkins.current === 'pirate');
  L.closeSheet('shopSheet');

  $('profileBtn').click(); await sleep(300);
  const locked = {};
  for (const t of ['avatars', 'chars', 'frames', 'plates', 'dice', 'rooms']) {
    document.querySelector(`#ppColTabs [data-tab="${t}"]`).click(); await sleep(40);
    const n = $('ppCol').querySelectorAll('.cit.locked, [data-buy-av]').length; if (n) locked[t] = n;
  }
  check('Collection: every character, avatar, frame, nameplate, die and room is unlocked', !Object.keys(locked).length, locked);
  $('ppBack').click(); await sleep(50);

  P.pawnSkins = ['classic']; P.rooms = ['night']; L.ensureProfile();
  check('a demo profile always comes back owning everything', P.pawnSkins.length === 12 && P.rooms.length === L.ROOM_LIST.length);

  L.goHome(); L.PawnSkins.apply('classic'); P.pawnSkin = 'classic';
  const failures = results.filter(r => !r.ok);
  return { passed: results.length - failures.length, failed: failures.length, failures };
})();
