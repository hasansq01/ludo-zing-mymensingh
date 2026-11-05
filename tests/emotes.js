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
  { const av = R(document.querySelector('#pcards .pcard[data-pos="bl"] .ava')), bb = R(btn);
    check('the button sits just above your avatar (or in the HUD row when there is no room)', btn.classList.contains('in-hud') || (bb.bottom <= av.top && av.top - bb.bottom <= 12 && Math.abs((bb.left + bb.right) / 2 - (av.left + av.right) / 2) < 3), [bb, av]); }
  const need = ['happy', 'laugh', 'cool', 'angry', 'cry', 'wow', 'love', 'confused', 'facepalm', 'cheer', 'party', 'sad', 'hi', 'tease', 'grr', 'hmph'];
  check('every required reaction exists (16+)', L.EMOTES.length >= 16 && need.every(id => L.EMOTES.some(e => e.id === id)), need.filter(id => !L.EMOTES.some(e => e.id === id)));
  check('5 sets: Pawn (free), Girl and Boy (6 core emotions each), two Premium packs of 8 extras; every emote in exactly one set', L.EMOTE_SETS.map(s => s.id).join() === 'starter,friends,boys,pawns,game' && !L.EMOTE_SETS[0].price && L.EMOTE_SETS.slice(1).every(s => s.price > 0) && L.EMOTE_SETS.slice(0, 3).every(s => s.emotes.length === 6 && !s.premium) && L.EMOTE_SETS.slice(3).every(s => s.emotes.length === 8 && s.premium) && L.EMOTES.filter(e => e.group !== 'text').every(e => L.EMOTE_SETS.filter(s => s.emotes.includes(e.id)).length === 1));
  check('the 6 core emotions: happy, laugh, cry, angry, shocked, love', L.EMOTE_FEELS.join() === 'happy,laugh,cry,angry,shocked,love');
  check('every character set has the same emotions, in the same order and with the same names', L.EMOTE_SETS.slice(0, 3).every(s => s.emotes.map(id => L.EMOTES.find(e => e.id === id).feel).join() === L.EMOTE_FEELS.join()) && new Set(L.EMOTE_SETS.slice(0, 3).map(s => s.emotes.map(id => L.EMOTES.find(e => e.id === id).name).join())).size === 1, L.EMOTE_SETS.map(s => [s.id, s.emotes.map(id => (L.EMOTES.find(e => e.id === id) || {}).feel)]));
  check('each character set is one character: pawn, girl, boy', ['pawn', 'girl', 'boy'].every((g, k) => L.EMOTE_SETS[k].emotes.every(id => L.EMOTES.find(e => e.id === id).group === g)));
  check('the first two sets (Pawn, Girl) have a real angry emote', ['angry', 'gAngry'].every((id, k) => L.EMOTE_SETS[k].emotes.includes(id) && L.EMOTES.find(e => e.id === id).motion === 'em-rage'));
  check('Premium packs hold only extras (no core emotion)', L.EMOTE_SETS.slice(3).every(s => s.emotes.every(id => !L.EMOTES.find(e => e.id === id).feel)));
  check('a new player owns and has equipped only the Starter set', JSON.stringify(L.P.emoteSets) === '["starter"]' && L.P.emoteSet === 'starter', [L.P.emoteSets, L.P.emoteSet]);
  check('the picker holds only the equipped Pawn set (6 emotes)', panel.querySelectorAll('.em-pick').length === 6 && E.list().join() === L.EMOTE_SETS[0].emotes.join());
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
  check('it pops out with the slide-in animation, buttons staggered', panel.classList.contains('show') && getComputedStyle(panel.querySelectorAll('.em-pick')[2]).getPropertyValue('--i').trim() === '2');
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

  // pick -> a reaction just above the sender's avatar and dice
  check('the button is a bare outlined chat bubble with three dots (no filled background)', getComputedStyle(btn).backgroundImage === 'none' && /rgba\(0, 0, 0, 0\)|transparent/.test(getComputedStyle(btn).backgroundColor) && btn.querySelectorAll('svg circle').length === 3);
  btn.click(); panel.querySelector('[data-emote="laugh"]').click();
  check('a picked emote pops in with a small bounce, then fades out (test mode freezes animation, so read the rule)', bubbleOf(0) && [...document.styleSheets].some(sh => { try { return [...sh.cssRules].some(r => r.selectorText === '.emote-bubble' && /emPop/.test(r.style.animation) && /emOut/.test(r.style.animation)); } catch (e) { return false; } }));
  check('after sending, the picker cools down (greyed, taps ignored)', panel.classList.contains('cooling'));
  btn.click(); panel.querySelector('[data-emote="love"]').click();
  check('a tap during the cooldown sends nothing', !(E.queue[0] || []).length);
  E.setOpen(false); await sleep(220);
  const b0 = bubbleOf(0);
  check('picking an emote closes the panel and shows a bubble', !E.open && b0 && b0.dataset.emote === 'laugh');
  // cards are built in seat order for the seats in play
  const cardsAva = c => document.querySelectorAll('#pcards .pcard')[[0, 1, 2, 3].filter(k => L.S.players[k] !== 'off').indexOf(c)].querySelector('.ava');
  const br = R(b0), card0 = cardsAva(0).closest('.pcard'), cr = R(card0), stR = R($('stage')), k = stR.width / $('stage').offsetWidth;
  check('the reaction sits just above the sender\'s avatar and dice, clear of them', br.bottom <= cr.top - 4 * k && cr.top - br.bottom <= 26 * k, [br, cr]);
  const slot0 = R(card0.querySelector('.slot'));
  const av0 = R(cardsAva(0)), mid = (stR.left + stR.right) / 2;
  check('it sits beside the dice towards the middle, on its own half of the screen', (br.left + br.right) / 2 > (av0.left + av0.right) / 2 && br.right <= mid + 1 && ((br.left + br.right) / 2 >= slot0.right - 2 * k || br.right >= mid - 6 * k), [br, slot0, mid]);
  check('it is big enough to read (about 70-116px wide, sized to the screen) and inside the screen', br.width / k >= 70 && br.width / k <= 117 && br.left >= stR.left + 6 * k && br.right <= stR.right - 6 * k && br.top >= stR.top, [br.width / k, br.left, br.right]);
  { const parts0 = [...document.querySelectorAll('#pcards .pcard .who, #pcards .pcard .slot, #msg, #menuBtn, #gearBtn, #emoteBtn')];
    check('it covers no player card, dice, name or HUD control', parts0.every(p => !overlap(br, R(p), .5)), parts0.filter(p => overlap(br, R(p), .5)).map(p => (p.id || p.className) + ' ' + JSON.stringify(R(p))).concat([JSON.stringify(br)])); }
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
  check('top players\' reactions show just below their cards', [1, 2].filter(c => L.S.players[c] !== 'off').every(c => { const card = cardsAva(c).closest('.pcard'); return card.dataset.pos[0] !== 't' || R(bubbleOf(c)).top >= R(card).bottom; }));

  // Top View: the cards stay in the corners, so placement still holds
  E.reset(); document.querySelector('input[name=cam][value=top]').click(); await sleep(300);
  E.place();
  check('Top View: the button still covers no card or HUD control', [...document.querySelectorAll('#pcards .pcard .who, #pcards .pcard .slot, #msg, #menuBtn, #gearBtn')].every(p => !overlap(R(btn), R(p), .5)));
  E.show(0, 'wow'); await sleep(30);
  check('Top View: the reaction still sits just above the player\'s card', bubbleOf(0) && R(bubbleOf(0)).bottom <= R(cardsAva(0).closest('.pcard')).top && R(bubbleOf(0)).left < R(cardsAva(0).closest('.pcard')).right, [bubbleOf(0) && R(bubbleOf(0)), R(cardsAva(0).closest('.pcard'))]);
  document.querySelector('input[name=cam][value="3d"]').click(); await sleep(200);

  // CPU reactions: forced chance, then throttled
  E.reset(); const rnd = Math.random; Math.random = () => 0;
  E.react('capture', 0, [[1, 0]]); await sleep(1000);
  check('a CPU whose pawn is captured may react (cry / angry / shocked / facepalm / disappointed / grr / hmph)', bubbleOf(1) && ['cry', 'angry', 'wow', 'facepalm', 'sad', 'grr', 'hmph'].includes(bubbleOf(1).dataset.emote));
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
  const cards = [...$('shopEmotes').querySelectorAll('.item[data-set]')];
  check('Shop > Emotes: one card per set, previewing its emotes (6, or 8 for a pack, marked Premium)', cards.length === 5 && cards.every((c, k) => c.querySelectorAll('.emset-prev svg').length === (k < 3 ? 6 : 8) && !!c.querySelector('.tag.prem') === k >= 3));
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
  check('in the game, the picker now holds only the Party Pack emotes (all 8)', [...panel.querySelectorAll('.em-pick')].map(b => b.dataset.emote).join() === pals.emotes.join());
  { const st2 = R($('stage')), pr = R(panel), parts2 = [...document.querySelectorAll('#pcards .pcard .who, #pcards .pcard .slot, #msg, #menuBtn, #gearBtn, #emoteBtn')];
    check('the 8-emote picker is fully on screen, covers no card or control, buttons 44px+', pr.left >= st2.left - .5 && pr.right <= st2.right + .5 && pr.top >= st2.top - .5 && pr.bottom <= st2.bottom + .5 &&
      parts2.every(p => !overlap(pr, R(p), .5)) && [...panel.querySelectorAll('.em-pick')].every(b => b.offsetWidth >= 44 && b.offsetHeight >= 44), [pr, parts2.filter(p => overlap(pr, R(p), .5)).map(p => p.className || p.id)]); }
  panel.querySelector('[data-emote="party"]').click(); await sleep(220);
  check('a Party Pack emote plays on your avatar', bubbleOf(0) && bubbleOf(0).dataset.emote === 'party');
  L.goHome(); L.renderInv(); L.openSheet('invSheet'); await sleep(30);
  const inv = [...$('invEmotes').querySelectorAll('.item[data-set]')];
  check('Inventory > Emotes lists only owned sets', inv.length === 2);
  $('invEmotes').querySelector('[data-emset-use="starter"]').click();
  check('Use in Inventory equips the Starter set again', P.emoteSet === 'starter');
  L.closeSheet('invSheet');
  L.openEmoteSet('friends'); await sleep(30);
  check('View: the Girl Set preview shows its 6 emotes and Buy with the real price', !$('emSetSheet').hidden && $('emSetGrid').children.length === 6 && /Buy — 2.5K/.test($('emSetAct').textContent));
  P.coins = 0; $('emSetAct').click();
  check('View: Buy without coins explains and spends nothing', /more coins/.test($('emSetNote').textContent) && !P.emoteSets.includes('friends'));
  L.closeSheet('emSetSheet');
  Object.assign(P, JSON.parse(keep));

  // ---- text emotes ----
  const T = L.TEXT_EMOTES, packIds = L.TEXT_PACKS.map(t => t.id).join();
  check('text packs: Good Manners (free), Ludo Talk, Reactions, Bangla (priced)', packIds === 'basic,ludo,react,bangla' && !L.TEXT_PACKS[0].price && L.TEXT_PACKS.slice(1).every(t => t.price > 0));
  check('8 phrases per pack, plus 4 team phrases', ['basic', 'ludo', 'react', 'bangla'].every(id => L.packPhrases(id).length === 8) && L.packPhrases('team').length === 4 && T.length === 36);
  check('the free pack has the basics: Hi, Good luck, Have fun, GG, Well played, Thanks, Sorry, Bye', L.packPhrases('basic').map(id => T.find(t => t.id === id).text).join() === 'Hi!,Good luck!,Have fun!,GG,Well played!,Thanks!,Sorry!,Bye!');
  check('each phrase is a sticker with the phrase written in it, big enough to read', T.every(t => /^<svg viewBox="0 0 172 109"/.test(t.art) && /class="sa-say"/.test(t.art) && [...t.art.matchAll(/font-size="([\d.]+)"/g)].every(m => +m[1] >= 17) && t.art.includes(t.text.split(' ')[0].replace('&', '&amp;'))), T.filter(t => !t.art.includes(t.text.split(' ')[0])).map(t => t.id));
  check('Bangla phrases are written in Bangla', L.packPhrases('bangla').every(id => /[\u0980-\u09FF]/.test(T.find(t => t.id === id).text)));
  check('a new player owns and has equipped Good Manners', JSON.stringify(L.P.textPacks) === '["basic"]' && L.P.textPack === 'basic');
  L.newGame(['human', 'cpu', 'cpu', 'cpu'], false); await sleep(300);
  E.setOpen(true); await sleep(30);
  check('the picker has Stickers / Text tabs and opens on Stickers', panel.querySelectorAll('[data-emtab]').length === 2 && E.mode === 'em' && !panel.querySelector('.em-pick-txt'));
  panel.querySelector('[data-emtab="text"]').click(); await sleep(30);
  check('the Text tab lists the equipped pack and the picker stays open', E.open && E.mode === 'text' && [...panel.querySelectorAll('.em-pick-txt')].map(b => b.dataset.emote).join() === L.packPhrases('basic').join());
  const txtBtns = [...panel.querySelectorAll('.em-pick-txt')], tr = txtBtns[0].getBoundingClientRect();
  check('text buttons are comfortable to tap (needs a visible pane)', !tr.width || txtBtns.every(b => b.offsetWidth >= 44 && b.offsetHeight >= 44));
  panel.querySelector('[data-emote="t-gg"]').click(); await sleep(220);
  check('a phrase pops up beside your card like any emote, then the picker cools down', bubbleOf(0) && bubbleOf(0).dataset.emote === 't-gg' && /GG/.test(bubbleOf(0).getAttribute('aria-label')) && panel.classList.contains('cooling'));
  check('no team phrases outside Pair Mode', !L.packPhrases('team').some(id => E.list().includes(id)) || E.mode !== 'text');
  E.reset(); check('a new game opens the picker on Stickers again', E.mode === 'em');
  L.newGame(['human', 'cpu', 'cpu', 'cpu'], true); await sleep(300);
  E.setMode('text');
  check('Pair Mode adds the 4 team phrases to the Text tab', E.list().join() === [...L.packPhrases('basic'), ...L.packPhrases('team')].join());
  { const rnd2 = Math.random; Math.random = () => 0; E.reset(); E.react('start'); await sleep(1000); Math.random = rnd2;
    check('a computer may wish the table luck at the start', [1, 2, 3].some(c => bubbleOf(c) && bubbleOf(c).dataset.emote === 't-luck')); }
  // buying a text pack
  { const P2 = L.P, keep2 = JSON.stringify({ coins: P2.coins, textPacks: P2.textPacks, textPack: P2.textPack });
    L.goHome(); L.renderShop(); L.openSheet('shopSheet'); L.showShopTab('emotes'); await sleep(50);
    const tc = [...$('shopEmotes').querySelectorAll('[data-tpack]')];
    check('Shop › Emotes lists the 4 text packs, each previewing its 8 phrases', tc.length === 4 && tc.every(c => c.querySelectorAll('.tpack-prev > span:not(.tag)').length === 8));
    P2.coins = 10; check('no coins: nothing bought', L.buyTextPack('ludo') === false && P2.coins === 10 && !P2.textPacks.includes('ludo'));
    P2.coins = L.TEXT_PACKS[1].price + 10;
    check('Buy charges once, owns and equips the pack', L.buyTextPack('ludo') === true && P2.coins === 10 && P2.textPacks.includes('ludo') && P2.textPack === 'ludo');
    check('an owned pack is never sold twice', L.buyTextPack('ludo') === false && P2.coins === 10);
    check('the purchase is saved', (L.Store.data.profile.textPacks || []).includes('ludo') && L.Store.data.profile.textPack === 'ludo');
    L.closeSheet('shopSheet');
    L.newGame(['human', 'cpu', 'cpu', 'cpu'], false); await sleep(300); E.setMode('text');
    check('in the game the Text tab now holds Ludo Talk', E.list().join() === L.packPhrases('ludo').join());
    L.goHome(); L.renderInv(); L.openSheet('invSheet'); await sleep(30);
    $('invTabs').querySelector('[data-tab="emotes"]').click(); await sleep(30);
    $('invEmotes').querySelector('[data-tpack-use="basic"]').click();
    check('Use in Inventory equips Good Manners again', P2.textPack === 'basic');
    L.closeSheet('invSheet');
    P2.textPacks = ['bogus', 'react']; P2.textPack = 'bogus'; L.ensureProfile();
    check('the profile repairs text packs (known ids only, Good Manners always owned)', JSON.stringify(P2.textPacks) === '["basic","react"]' && P2.textPack === 'basic');
    Object.assign(P2, JSON.parse(keep2)); }

  // ---- leaving the game ----
  L.goHome(); await sleep(50);
  check('leaving clears bubbles and hides the button', !document.querySelector('.emote-bubble') && (btn.hidden || getComputedStyle(btn).display === 'none') && !E.open);

  const failures = results.filter(r => !r.ok);
  return { passed: results.length - failures.length, failed: failures.length, failures };
})();
