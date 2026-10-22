// Feature info (ⓘ) tests for Ludo Zing Mymensingh.
// Run in the browser console on the source game page with ?vt=1 (test mode: nothing is written to browser storage):
// paste the whole file. Resolves to { passed, failed, failures }. Run it in a foreground tab (CPU turns use timers / rAF).
(async () => {
  const L = window.__ludo, I = L.Info, $ = id => document.getElementById(id);
  const results = [];
  const check = (name, ok, got) => results.push({ name, ok: !!ok, got: ok ? undefined : JSON.stringify(got) });
  const sleep = ms => new Promise(r => setTimeout(r, ms));
  const tip = $('infoTip');
  const icon = (root, k) => root.querySelector(`.info-i[data-info="${k}"]`);
  const tap = el => el.dispatchEvent(new MouseEvent('click', { bubbles: true, cancelable: true }));
  const inView = r => r.left >= 0 && r.top >= 0 && r.right <= innerWidth + 0.5 && r.bottom <= innerHeight + 0.5;
  const hit = b => {   // the tap area: the dot plus its ::after inset on each side
    const r = b.getBoundingClientRect(), a = getComputedStyle(b, '::after');
    return { w: r.width - parseFloat(a.left) - parseFloat(a.right), h: r.height - parseFloat(a.top) - parseFloat(a.bottom) };
  };
  L.Info.load({});   // a player who has never opened any explanation

  // ---- every icon names a real explanation, and every explanation is placed somewhere ----
  L.renderShop(); L.renderInv();
  const keys = new Set([...document.querySelectorAll('.info-i')].map(b => b.dataset.info));
  ['capture', 'free'].forEach(k => keys.add(k));   // built with the Pair Mode player cards (checked below)
  check('every ⓘ has an explanation', [...keys].every(k => L.INFO[k]), [...keys].filter(k => !L.INFO[k]));
  check('every explanation has an ⓘ', Object.keys(L.INFO).every(k => keys.has(k)), Object.keys(L.INFO).filter(k => !keys.has(k)));
  const unfilled = [...document.querySelectorAll('.info-i')].filter(b => b.getAttribute('role') !== 'button' || b.tabIndex !== 0 || !/^About /.test(b.getAttribute('aria-label')) || !b.querySelector('svg'));
  check('every ⓘ is a labelled, focusable button with its art', !unfilled.length, unfilled.map(b => b.dataset.info));
  check('placements: Individual + Pair in both Ludo setups', ['cpuForm', 'localForm'].every(f => icon($(f), 'ind') && icon($(f), 'team') && icon($(f), 'ind').closest('label').htmlFor.endsWith('modeI') && icon($(f), 'team').closest('label').htmlFor.endsWith('modeP')));
  check('placements: S&L setups, status line, both camera rows, Daily heading, Pair controls', icon($('slCpuSheet'), 'slEntry') && icon($('slLocalSheet'), 'slEntry') && $('slMsg').nextElementSibling.dataset.info === 'sl'
    && icon($('camLab'), 'cam') && icon($('slCamLab'), 'slcam') && icon($('dailyTitle'), 'daily') && icon($('unitPick'), 'pair') && icon($('pairSheet'), 'pair'));
  check('placements: Scenes note in Shop and Inventory', icon($('shopScenes'), 'scenes') && icon($('invScenes'), 'scenes'));

  // ---- Ludo setup: the selected mode pulses; tapping an ⓘ explains without picking that option ----
  L.openSheet('cpuSheet'); $('opp3').checked = true; $('cmodeI').checked = true; L.syncModes();
  const f = $('cpuForm'), ind = icon(f, 'ind'), team = icon(f, 'team');
  check('Individual (selected) pulses, Pair does not', ind.classList.contains('pulse') && !team.classList.contains('pulse'));
  $('cmodeP').checked = true; L.syncModes();
  check('selecting Pair moves the pulse to its ⓘ', team.classList.contains('pulse') && !ind.classList.contains('pulse'));
  let h = hit(team);
  check('ⓘ tap area is at least 44 x 44 px', h.w >= 44 && h.h >= 44, h);
  tap(ind);
  check('tapping Individual ⓘ opens its explanation', !tip.hidden && /Individual/.test(tip.querySelector('h3').textContent) && I.openKey === 'ind');
  check('…and does not switch the mode', $('cmodeP').checked && !$('cmodeI').checked);
  check('the bubble stays on screen', inView(tip.getBoundingClientRect()), tip.getBoundingClientRect());
  tap(team);
  check('Pair ⓘ shows the team rules (teams, partners, Free Hand, win)', /Red \+ Yellow/.test(tip.textContent) && /never capture or block/.test(tip.textContent) && /Free Hand/.test(tip.textContent) && /both partners/.test(tip.textContent));
  check('opening stops the pulse and is remembered', !team.classList.contains('pulse') && I.seen.team === 'open');
  $('cmodeI').checked = true; L.syncModes(); $('cmodeP').checked = true; L.syncModes();
  check('a read ⓘ does not pulse again', !team.classList.contains('pulse'));
  document.dispatchEvent(new KeyboardEvent('keydown', { key: 'Escape', bubbles: true }));
  check('Escape closes the bubble but not the setup sheet', tip.hidden && !$('cpuSheet').hidden);
  tap(team); tap(document.body);
  check('a tap elsewhere dismisses the bubble', tip.hidden);
  tap(team); tap(tip.querySelector('.x'));
  check('the close button dismisses it', tip.hidden);
  team.dispatchEvent(new KeyboardEvent('keydown', { key: 'Enter', bubbles: true }));
  check('Enter on a focused ⓘ opens it (keyboard)', !tip.hidden && I.openKey === 'team');
  L.closeSheet('cpuSheet');
  check('closing the sheet closes the bubble', tip.hidden);

  // ---- pulse cap: an unread ⓘ stops nagging after 3 showings ----
  I.load({});
  for (let k = 0; k < 4; k++) { L.openSheet('dailySheet'); if (k < 3) check(`Daily ⓘ pulses on showing ${k + 1}`, icon($('dailyTitle'), 'daily').classList.contains('pulse')); L.closeSheet('dailySheet'); }
  L.openSheet('dailySheet');
  check('…and not on the 4th', !icon($('dailyTitle'), 'daily').classList.contains('pulse'), I.seen.daily);
  tap(icon($('dailyTitle'), 'daily'));
  check('Daily ⓘ: 7 days, missed day resets to Day 1, owned items become coins', /Day 1 to Day 7/.test(tip.textContent) && /Miss a day/.test(tip.textContent) && /already own/.test(tip.textContent));
  check('Daily bubble on screen at 375 px wide', inView(tip.getBoundingClientRect()), tip.getBoundingClientRect());
  L.closeSheet('dailySheet');

  // ---- explanations agree with the rules in the code ----
  check('S&L: only a 1 enters the board', L.SL.land(0, 1).to === 1 && [2, 3, 4, 5, 6].every(v => L.SL.land(0, v).to === 0));
  check('S&L: an overshoot of 100 stays put', L.SL.land(97, 6).to === 97 && L.SL.land(97, 6).over);
  const lad = +Object.keys(L.SL.LADDERS)[1], sn = +Object.keys(L.SL.SNAKES)[1];
  check('S&L: ladder foot climbs, snake head slides', L.SL.land(lad - 1, 1).to === L.SL.LADDERS[lad] && L.SL.land(sn - 1, 1).to === L.SL.SNAKES[sn]);

  // ---- Pair Mode game: capture ⓘ on one card, Free Hand ⓘ appears with its state ----
  L.newGame(['human', 'cpu', 'cpu', 'cpu'], true);
  await sleep(50);
  const caps = document.querySelectorAll('#pcards .info-i[data-info="capture"]');
  check('Pair Mode: one capture-rules ⓘ, on your card beside the team tag', caps.length === 1 && caps[0].previousElementSibling.classList.contains('team-tag') && caps[0].closest('.pcard') === document.querySelector('#pcards .pcard'));
  tap(caps[0]);
  check('capture ⓘ: pair-only captures, partners safe, safe squares', /Only a pair can capture a pair/.test(tip.textContent) && /partner/.test(tip.textContent) && /Star squares/.test(tip.textContent));
  tap(document.body);
  const freeLine = document.querySelectorAll('#pcards .tline')[1];
  check('Free Hand ⓘ is hidden while nobody has finished', freeLine.hidden);
  L.S.tok[0] = [L.GOAL, L.GOAL, L.GOAL, L.GOAL]; L.updateHUD();
  const fl = $('pcards').querySelector('.tstate').parentNode, fi = icon(fl, 'free');
  check('a finished player shows "Done · need 6" with a pulsing Free Hand ⓘ', !fl.hidden && /need 6/i.test(fl.textContent) && fi.classList.contains('pulse'));
  h = hit(fi);
  check('small ⓘ (cards) still has a 44 x 44 px tap area', h.w >= 44 && h.h >= 44, h);
  tap(fi);
  check('Free Hand ⓘ: needs a 6, then rolls move the partner’s pawns', /need a 6/.test(tip.textContent) && /partner’s pawns/.test(tip.textContent) && inView(tip.getBoundingClientRect()));
  check('the card ⓘ stays inside the screen', inView(fi.getBoundingClientRect()), fi.getBoundingClientRect());
  tap(document.body);
  L.newGame(['human', 'cpu', 'cpu', 'cpu'], false);
  await sleep(50);
  check('Individual game: no team or Free Hand ⓘ on the cards', !document.querySelector('#pcards .info-i'));
  check('Single/Pair picker carries the pairs ⓘ', /half the roll/.test(L.INFO.pair.b.join(' ')) && icon($('unitPick'), 'pair'));

  // ---- Scenes ⓘ in the shop ----
  L.openSheet('shopSheet'); L.showShopTab('scenes');
  const si = icon($('shopScenes'), 'scenes');
  check('Scenes tab: its ⓘ pulses for a new player', si && si.classList.contains('pulse'));
  tap(si);
  check('Scenes ⓘ: same rules in every scene, paid once, Use to switch', /same in every scene/.test(tip.textContent) && /paid once/.test(tip.textContent) && /Use/.test(tip.textContent));
  L.closeSheet('shopSheet');
  L.goHome();

  const failures = results.filter(r => !r.ok);
  return { passed: results.length - failures.length, failed: failures.length, failures };
})();
