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
  check('the collection has 8 free emotes', L.EMOTES.length === 8 && panel.querySelectorAll('.em-pick').length === 8 && E.list().length === 8);
  const parts = [...document.querySelectorAll('#pcards .pcard .who, #pcards .pcard .slot, #pcards .tap, #msg, #menuBtn, #gearBtn')].filter(e => e !== btn);
  check('the button covers no card, dice, name or HUD control', parts.every(p => !overlap(R(btn), R(p), 0.5)), parts.filter(p => overlap(R(btn), R(p), .5)).map(p => p.className || p.id));
  const st = R($('stage'));
  check('the button is inside the screen', R(btn).left >= st.left && R(btn).right <= st.right && R(btn).bottom <= st.bottom);
  check('sender in vs Computer is the human (seat 0)', E.sender() === 0);

  // open / close
  btn.click(); await sleep(50);
  check('tapping the button opens the panel', E.open && !panel.hidden && btn.getAttribute('aria-expanded') === 'true');
  check('the panel is fully on screen', R(panel).left >= st.left - .5 && R(panel).right <= st.right + .5 && R(panel).top >= st.top - .5 && R(panel).bottom <= st.bottom + .5);
  document.body.dispatchEvent(new PointerEvent('pointerdown', { bubbles: true }));
  check('a tap outside closes it', !E.open && panel.hidden);
  btn.click(); document.dispatchEvent(new KeyboardEvent('keydown', { key: 'Escape', bubbles: true }));
  check('Escape closes it (and does not open the pause menu)', !E.open && $('pauseSheet').hidden);
  btn.click(); L.openSheet('settingsSheet'); L.closeSheet('settingsSheet');
  check('opening a menu closes it', !E.open);

  // pick -> bubble over the sender's avatar
  btn.click(); panel.querySelector('[data-emote="laugh"]').click(); await sleep(30);
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
  E.send('cool'); E.send('love'); E.send('clap'); E.send('party');
  check('a player\'s further emotes wait (at most 2)', document.querySelectorAll('.emote-bubble[data-seat="0"]').length === 1 && (E.queue[0] || []).length === 2, E.queue);
  await sleep(1900);
  check('the next queued emote follows after ~1.8s', bubbleOf(0) && bubbleOf(0).dataset.emote === 'cool');

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
  check('Top View: the bubble still sits on the avatar', bubbleOf(0) && overlap(R(bubbleOf(0)), R(document.querySelector('#pcards .pcard .ava'))));
  document.querySelector('input[name=cam][value="3d"]').click(); await sleep(200);

  // CPU reactions: forced chance, then throttled
  E.reset(); const rnd = Math.random; Math.random = () => 0;
  E.react('capture', 0, [[1, 0]]); await sleep(1000);
  check('a CPU whose pawn is captured may react (sad / angry / surprised)', bubbleOf(1) && ['cry', 'angry', 'wow'].includes(bubbleOf(1).dataset.emote));
  E.react('capture', 0, [[2, 0]]); await sleep(1000);
  check('reactions are throttled (no burst right after)', !bubbleOf(2));
  Math.random = rnd;

  // the game itself is untouched
  check('emotes never change the game state', JSON.stringify(L.S) === S0);

  // ---- Pass & Play: the player to move is the sender ----
  E.reset(); L.newGame(['human', 'human', 'human', 'human'], false); await sleep(300);
  check('Pass & Play: sender is the player to move', E.sender() === L.S.turn);
  E.send('clap'); await sleep(30);
  check('Pass & Play: the bubble shows on that player\'s card', bubbleOf(L.S.turn) && bubbleOf(L.S.turn).dataset.emote === 'clap');

  // ---- leaving the game ----
  L.goHome(); await sleep(50);
  check('leaving clears bubbles and hides the button', !document.querySelector('.emote-bubble') && (btn.hidden || getComputedStyle(btn).display === 'none') && !E.open);

  const failures = results.filter(r => !r.ok);
  return { passed: results.length - failures.length, failed: failures.length, failures };
})();
