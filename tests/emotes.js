// Emote tests for Ludo Zing Mymensingh.
// Run in the browser console on the source game page with ?vt=1, in a foreground tab, after the splash: paste the
// whole file. Resolves to { passed, failed, failures }. Purely visual feature: also checks no game state changes.
(async () => {
  const L = window.__ludo, E = L.Emotes, $ = id => document.getElementById(id);
  const results = [];
  const check = (name, ok, got) => results.push({ name, ok: !!ok, got: ok ? undefined : JSON.stringify(got) });
  const sleep = ms => new Promise(r => setTimeout(r, ms));
  const btn = $('emoteBtn'), panel = $('emotePanel');
  const R = el => el.getBoundingClientRect();
  const overlap = (a, b, m = 0) => a.left < b.right - m && a.right > b.left + m && a.top < b.bottom - m && a.bottom > b.top + m;
  const bubbleOf = c => document.querySelector(`.emote-bubble[data-seat="${c}"]`);

  // ---- home: no emote button ----
  L.goHome(); await sleep(50);
  check('home screen: no emote button', btn.hidden || getComputedStyle(btn).display === 'none');

  // ---- vs Computer ----
  L.newGame(['human', 'cpu', 'cpu', 'cpu'], false); await sleep(400);
  const S0 = JSON.stringify(L.S);
  check('game: the emote button is shown, 44px', !btn.hidden && btn.offsetWidth >= 44 && btn.offsetHeight >= 44);
  const need = ['happy', 'laugh', 'cool', 'angry', 'cry', 'wow', 'love', 'sleepy', 'confused', 'facepalm', 'cheer', 'party', 'think', 'sad', 'hi', 'tease'];
  check('every required reaction exists (16+)', L.EMOTES.length >= 16 && need.every(id => L.EMOTES.some(e => e.id === id)), need.filter(id => !L.EMOTES.some(e => e.id === id)));
  check('4 sets of 6 (rows of the reference): Starter free, others priced, every emote in exactly one set', L.EMOTE_SETS.length === 4 && L.EMOTE_SETS.every(s => s.emotes.length === 6) && L.EMOTE_SETS[0].id === 'starter' && !L.EMOTE_SETS[0].price && L.EMOTE_SETS.slice(1).every(s => s.price > 0) && L.EMOTES.every(e => L.EMOTE_SETS.filter(s => s.emotes.includes(e.id)).length === 1));
  check('a new player owns and has equipped only the Starter set', JSON.stringify(L.P.emoteSets) === '["starter"]' && L.P.emoteSet === 'starter', [L.P.emoteSets, L.P.emoteSet]);
  check('the picker holds only the equipped set (6 emotes)', panel.querySelectorAll('.em-pick').length === 6 && E.list().join() === L.EMOTE_SETS[0].emotes.join());
  check('every emote is a 2D vector sticker (inline SVG on the 172x109 grid, no image files)', L.EMOTES.every(e => /^<svg viewBox="0 0 172 109"/.test(e.art) && !/<image|\.png|\.jpg/.test(e.art)));
  check('every emote is an animated sticker (moving parts inside a still bubble)', L.EMOTES.every(e => /class="sa-/.test(e.art)), L.EMOTES.filter(e => !/class="sa-/.test(e.art)).map(e => e.id));
  check('every copy on the page has its own clip-path ids', (() => { const ids = [...document.querySelectorAll('#emotePanel [id], #pcards [id^="st"]')].map(n => n.id); return ids.length > 0 && new Set(ids).size === ids.length; })());
  check('ids are unique', new Set(L.EMOTES.map(e => e.id)).size === L.EMOTES.length);
  const parts = [...document.querySelectorAll('#pcards .pcard .who, #pcards .pcard .slot, #pcards .tap, #msg, #menuBtn, #gearBtn')].filter(e => e !== btn);
  check('the button covers no card, dice, name or HUD control', parts.every(p => !overlap(R(btn), R(p), 0.5)), parts.filter(p => overlap(R(btn), R(p), .5)).map(p => p.className || p.id));
  const st = R($('stage'));
  check('the button is inside the screen', R(btn).left >= st.left && R(btn).right <= st.right && R(btn).bottom <= st.bottom);
  check('sender in vs Computer is the human (seat 0)', E.sender() === 0);

  // open / close
  btn.click(); await sleep(50);
  check('tapping the button opens the panel', E.open && !panel.hidden && btn.getAttribute('aria-expanded') === 'true');
  check('the panel is fully on screen', R(panel).left >= st.left - .5 && R(panel).right <= st.right + .5 && R(panel).top >= st.top - .5 && R(panel).bottom <= st.bottom + .5);
  const sc = st.width / $('stage').offsetWidth;
  check('the panel sits along the left edge', R(panel).left - st.left <= 12 * sc && (R(panel).left + R(panel).right) / 2 < st.left + st.width / 2, [R(panel).left - st.left]);
  const cardsNow = [...document.querySelectorAll('#pcards .pcard .who, #pcards .pcard .slot, #msg, #menuBtn, #gearBtn, #emoteBtn')];
  check('the panel covers no player card, dice, HUD control or the emote button', cardsNow.every(p => !overlap(R(panel), R(p), .5)), cardsNow.filter(p => overlap(R(panel), R(p), .5)).map(p => p.className || p.id));
  check('it pops out with the slide-in animation, buttons staggered', panel.classList.contains('show') && getComputedStyle(panel.querySelector('.em-pick:nth-child(3)')).getPropertyValue('--i').trim() === '2');
  check('picker buttons are comfortable to tap', [...panel.querySelectorAll('.em-pick')].every(b => b.offsetWidth >= 44 && b.offsetHeight >= 44));
  document.body.dispatchEvent(new PointerEvent('pointerdown', { bubbles: true }));
  check('a tap outside closes it (smooth fade, then hidden)', !E.open && panel.classList.contains('closing'));
  await sleep(220);
  check('…and it is gone after the fade', panel.hidden);
  // (the pause menu also opens whenever the page is hidden, so check that Escape never reaches the game's own handler)
  let leaked = false; const spy = e => { if (e.key === 'Escape') leaked = true; };
  addEventListener('keydown', spy);   // bubble phase on window: where the game's Escape -> pause handler listens
  btn.click(); document.dispatchEvent(new KeyboardEvent('keydown', { key: 'Escape', bubbles: true }));
  removeEventListener('keydown', spy);
  check('Escape closes it and is not passed on (it does not also open the pause menu)', !E.open && !leaked);
  btn.click(); L.openSheet('settingsSheet'); L.closeSheet('settingsSheet');
  check('opening a menu closes it', !E.open);

  // pick -> bubble over the sender's avatar
  btn.click(); panel.querySelector('[data-emote="laugh"]').click();
  check('a picked emote flies out of its picker cell', bubbleOf(0) && bubbleOf(0).classList.contains('fly') && bubbleOf(0).style.getPropertyValue('--fx') !== '');
  check('after sending, the picker cools down (greyed, taps ignored)', panel.classList.contains('cooling'));
  btn.click(); panel.querySelector('[data-emote="cool"]').click();
  check('a tap during the cooldown sends nothing', !(E.queue[0] || []).length);
  E.setOpen(false); await sleep(220);
  const b0 = bubbleOf(0);
  check('picking an emote closes the panel and shows a bubble', !E.open && b0 && b0.dataset.emote === 'laugh');
  // cards are built in seat order for the seats in play
  const cardsAva = c => document.querySelectorAll('#pcards .pcard')[[0, 1, 2, 3].filter(k => L.S.players[k] !== 'off').indexOf(c)].querySelector('.ava');
  const br = R(b0), ar = R(cardsAva(0));
  check('the bubble is centred on the sender\'s avatar', Math.abs((br.left + br.right) / 2 - (ar.left + ar.right) / 2) < 8 && Math.abs((br.top + br.bottom) / 2 - (ar.top + ar.bottom) / 2) < 10, [br, ar]);
  const name0 = document.querySelector('#pcards .pcard .who b');
  check('the bubble leaves the player name readable', R(b0).bottom <= R(name0).top + 2, [R(b0).bottom, R(name0).top]);
  check('the bubble is labelled for screen readers', /: Laugh$/.test(b0.getAttribute('aria-label')));
  check('the bubble ignores taps (never blocks the game)', getComputedStyle(b0).pointerEvents === 'none');

  // queue: one at a time per player, at most two waiting
  E.send('cool'); E.send('love'); E.send('cheer'); E.send('party');
  check('a player\'s further emotes wait (at most 2)', document.querySelectorAll('.emote-bubble[data-seat="0"]').length === 1 && (E.queue[0] || []).length === 2, E.queue);
  await sleep(2500);
  check('the next queued emote follows after ~2.4s', bubbleOf(0) && bubbleOf(0).dataset.emote === 'cool');

  // every seat at once: no two bubbles overlap, none covers the board centre text / dice
  E.reset();
  [0, 1, 2, 3].forEach((c, k) => E.show(c, L.EMOTES[k].id)); await sleep(30);
  const bs = [0, 1, 2, 3].map(bubbleOf);
  check('a bubble for each player at the same time', bs.every(Boolean));
  check('bubbles never overlap each other', bs.every((a, i) => bs.every((b, j) => i === j || !overlap(R(a), R(b)))));
  const dice = $('diceBtn');
  check('bubbles do not cover the dice', bs.every(b => !overlap(R(b), R(dice), 1)));

  // Top View: the cards stay in the corners, so placement still holds
  E.reset(); document.querySelector('input[name=cam][value=top]').click(); await sleep(300);
  E.place();
  check('Top View: the button still covers no card or HUD control', [...document.querySelectorAll('#pcards .pcard .who, #pcards .pcard .slot, #msg, #menuBtn, #gearBtn')].every(p => !overlap(R(btn), R(p), .5)));
  E.show(0, 'wow'); await sleep(30);
  check('Top View: the bubble still sits on the avatar', bubbleOf(0) && overlap(R(bubbleOf(0)), R(document.querySelector('#pcards .pcard .ava'))), [bubbleOf(0) && R(bubbleOf(0)), R(document.querySelector('#pcards .pcard .ava'))]);
  document.querySelector('input[name=cam][value="3d"]').click(); await sleep(200);

  // CPU reactions: forced chance, then throttled
  E.reset(); const rnd = Math.random; Math.random = () => 0;
  E.react('capture', 0, [[1, 0]]); await sleep(1000);
  check('a CPU whose pawn is captured may react (cry / angry / shocked / facepalm / disappointed)', bubbleOf(1) && ['cry', 'angry', 'wow', 'facepalm', 'sad'].includes(bubbleOf(1).dataset.emote));
  E.react('capture', 0, [[2, 0]]); await sleep(1000);
  check('reactions are throttled (no burst right after)', !bubbleOf(2));
  Math.random = rnd;

  // the game itself is untouched
  check('emotes never change the game state', JSON.stringify(L.S) === S0);

  // ---- Pass & Play: the player to move is the sender ----
  E.reset(); L.newGame(['human', 'human', 'human', 'human'], false); await sleep(300);
  check('Pass & Play: sender is the player to move', E.sender() === L.S.turn);
  E.send('cheer'); await sleep(30);
  check('Pass & Play: the bubble shows on that player\'s card', bubbleOf(L.S.turn) && bubbleOf(L.S.turn).dataset.emote === 'cheer');

  // ---- emote sets: shop, buy, equip, inventory, preview ----
  const P = L.P, keep = JSON.stringify({ coins: P.coins, emoteSets: P.emoteSets, emoteSet: P.emoteSet });
  const pals = L.EMOTE_SETS.find(s => s.id === 'pawns');
  L.goHome(); L.renderShop(); L.openSheet('shopSheet'); L.showShopTab('emotes'); await sleep(50);
  const cards = [...$('shopEmotes').querySelectorAll('.item')];
  check('Shop > Emotes: one card per set, each previewing its 6 emotes', cards.length === 4 && cards.every(c => c.querySelectorAll('.emset-prev svg').length === 6));
  check('the cards tell Equipped / Locked apart', /Equipped/.test(cards[0].textContent) && cards.slice(1).every(c => /Locked/.test(c.textContent) && c.querySelector('[data-emset-buy]')));
  P.coins = pals.price - 1; $('shopEmotes').querySelector('[data-emset-buy="pawns"]').click();
  check('not enough coins: nothing spent, still locked', P.coins === pals.price - 1 && !P.emoteSets.includes('pawns'));
  P.coins = pals.price + 10; $('shopEmotes').querySelector('[data-emset-buy="pawns"]').click();
  check('Buy charges the price once, owns and equips the set', P.coins === 10 && P.emoteSets.includes('pawns') && P.emoteSet === 'pawns', [P.coins, P.emoteSets, P.emoteSet]);
  check('an owned set is never sold twice', L.buyEmoteSet('pawns') === false && P.coins === 10);
  check('the purchase is saved', (L.Store.data.profile.emoteSets || []).includes('pawns') && L.Store.data.profile.emoteSet === 'pawns');
  L.closeSheet('shopSheet');
  L.newGame(['human', 'cpu', 'cpu', 'cpu'], false); await sleep(300);
  btn.click(); await sleep(30);
  check('in the game, the picker now holds only the Pawn Pals emotes', [...panel.querySelectorAll('.em-pick')].map(b => b.dataset.emote).join() === pals.emotes.join());
  panel.querySelector('[data-emote="champ"]').click(); await sleep(220);
  check('a Pawn Pals emote plays on your avatar', bubbleOf(0) && bubbleOf(0).dataset.emote === 'champ');
  L.goHome(); L.renderInv(); L.openSheet('invSheet'); await sleep(30);
  const inv = [...$('invEmotes').querySelectorAll('.item')];
  check('Inventory > Emotes lists only owned sets', inv.length === 2);
  $('invEmotes').querySelector('[data-emset-use="starter"]').click();
  check('Use in Inventory equips the Starter set again', P.emoteSet === 'starter');
  L.closeSheet('invSheet');
  L.openEmoteSet('friends'); await sleep(30);
  check('View: the set preview shows its 6 emotes and Buy with the real price', !$('emSetSheet').hidden && $('emSetGrid').children.length === 6 && /Buy — 4K/.test($('emSetAct').textContent));
  P.coins = 0; $('emSetAct').click();
  check('View: Buy without coins explains and spends nothing', /more coins/.test($('emSetNote').textContent) && !P.emoteSets.includes('friends'));
  L.closeSheet('emSetSheet');
  Object.assign(P, JSON.parse(keep));

  // ---- leaving the game ----
  L.goHome(); await sleep(50);
  check('leaving clears bubbles and hides the button', !document.querySelector('.emote-bubble') && (btn.hidden || getComputedStyle(btn).display === 'none') && !E.open);

  const failures = results.filter(r => !r.ok);
  return { passed: results.length - failures.length, failed: failures.length, failures };
})();
