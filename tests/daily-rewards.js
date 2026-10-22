// Daily Reward tests for Ludo Zing Mymensingh.
// Run in the browser console on the source game page with ?vt=1 (test mode: nothing is written to browser storage):
// paste the whole file. Resolves to { passed, failed, failures }. Days are simulated by moving the saved last-claim date.
(async () => {
  const L = window.__ludo, P = L.P, $ = id => document.getElementById(id);
  const results = [];
  const check = (name, ok, got) => results.push({ name, ok: !!ok, got: ok ? undefined : JSON.stringify(got) });
  const sleep = ms => new Promise(r => setTimeout(r, ms));
  const idle = async () => { const t0 = performance.now(); while (L.dailyBusy && performance.now() - t0 < 8000) await sleep(40); await sleep(60); };
  const key = days => L.dayKey(new Date(Date.now() + days * 864e5));
  const backup = JSON.stringify(P), storeBackup = JSON.stringify(L.Store.data.profile || null);
  const C = L.DAILY_CYCLES;

  // a fresh player: no daily data, plain dice and characters only
  delete P.daily; P.coins = 1000; P.owned = ['classic']; P.avOwned = [];
  let st = L.dailyState();
  check('a new player can claim Day 1 of cycle 1', st.claimable && st.today === 0 && st.cycle === 0, st);

  // ---- Day 1, then duplicate claims ----
  L.openDaily();
  check('the popup lists 7 days, Day 1 marked today', $('dailyGrid').children.length === 7 && $('dailyGrid').children[0].classList.contains('today'));
  let c0 = P.coins;
  $('dailyClaim').click(); $('dailyClaim').click(); L.claimDaily();   // rapid taps
  await idle();
  check('Day 1 pays its coins exactly once', P.coins === c0 + C[0][0].coins && P.daily.history.length === 1, [P.coins - c0, P.daily.history.length]);
  check('Day 1 is saved as claimed today', P.daily.streak === 1 && P.daily.last === key(0) && P.daily.lastAt > 0, P.daily);
  c0 = P.coins; L.claimDaily(); await idle(); L.openDaily(); L.claimDaily(); await idle();
  check('claiming again today (or after reopening) does nothing', P.coins === c0 && P.daily.history.length === 1, [P.coins - c0]);
  check('the popup shows Day 1 claimed and the button off', $('dailyGrid').children[0].classList.contains('claimed') && $('dailyClaim').disabled && /Next reward in/.test($('dailyNote').textContent));
  check('the home badge is off once claimed', $('dailyBadge').hidden);

  // ---- Days 2-7 on consecutive days ----
  for (let k = 1; k < 7; k++) {
    P.daily.last = key(-1);   // a day has passed
    st = L.dailyState();
    const r = C[0][k], before = { coins: P.coins, owned: P.owned.slice(), av: P.avOwned.slice() };
    check(`Day ${k + 1} is claimable the next day`, st.claimable && st.today === k && st.cycle === 0, st);
    L.claimDaily(); await idle();
    const ok = P.coins === before.coins + (r.coins || 0) && P.daily.streak === k + 1 && P.daily.last === key(0)
      && (!r.dice || P.owned.includes(r.dice) && !before.owned.includes(r.dice)) && (!r.char || P.avOwned.includes(r.char));
    check(`Day ${k + 1} grants ${JSON.stringify(r)}`, ok, { coins: P.coins - before.coins, streak: P.daily.streak, owned: P.owned, av: P.avOwned });
  }
  L.openDaily();
  check('after Day 7 all seven tiles show claimed', [...$('dailyGrid').children].every(t => t.classList.contains('claimed')));

  // ---- the next cycle ----
  P.daily.last = key(-1);
  st = L.dailyState();
  check('the day after Day 7 starts cycle 2 at Day 1', st.claimable && st.cycle === 1 && st.today === 0, st);
  let cc = P.coins; L.claimDaily(); await idle();
  check('cycle 2 Day 1 pays the cycle-2 amount', P.coins === cc + C[1][0].coins && P.daily.cycle === 1 && P.daily.streak === 1, [P.coins - cc, P.daily]);

  // ---- missed days ----
  P.daily.streak = 3; P.daily.last = key(-3);
  st = L.dailyState();
  check('missing a day restarts at Day 1 (same cycle)', st.claimable && st.today === 0 && st.cycle === 1 && st.missed, st);
  L.openDaily();
  check('the popup explains the restart', /missed a day/.test($('dailyNote').textContent));
  cc = P.coins; L.claimDaily(); await idle();
  check('the restart pays Day 1', P.coins === cc + C[1][0].coins && P.daily.streak === 1, [P.coins - cc]);
  P.daily.streak = 7; P.daily.cycle = 1; P.daily.last = key(-5);
  st = L.dailyState();
  check('a finished cycle followed by a break starts the next cycle at Day 1', st.claimable && st.cycle === 2 && st.today === 0, st);

  // ---- items never given twice ----
  P.daily = { cycle: 0, streak: 3, last: key(-1), lastAt: 1, history: [] };
  if (!P.owned.includes('crema')) P.owned.push('crema');
  cc = P.coins; const n0 = P.owned.length; L.claimDaily(); await idle();
  check('an already-owned dice skin pays its coins instead', P.coins === cc + C[0][3].or && P.owned.length === n0, [P.coins - cc, P.owned]);
  P.daily = { cycle: 0, streak: 6, last: key(-1), lastAt: 1, history: [] };
  cc = P.coins; const a0 = P.avOwned.length; L.claimDaily(); await idle();
  check('an already-owned character pays coins instead (Day 7)', P.coins === cc + C[0][6].coins + C[0][6].or && P.avOwned.length === a0, [P.coins - cc]);

  // ---- clock moved back, damaged data ----
  P.daily = { cycle: 0, streak: 2, last: key(1), lastAt: 1, history: [] };
  check('a claim dated in the future (clock moved back) cannot be repeated', !L.dailyState().claimable);
  P.daily = { cycle: -3, streak: 99, last: 'garbage', history: 'x' };
  st = L.dailyState();
  check('damaged saved data is repaired, not trusted', st.claimable && st.today === 0 && P.daily.streak === 0 && P.daily.cycle === 0 && Array.isArray(P.daily.history), P.daily);

  // ---- separate profiles ----
  P.daily = { cycle: 0, streak: 2, last: key(0), lastAt: Date.now(), history: [] };
  L.Store.save('profile', P);
  const mine = JSON.parse(JSON.stringify(L.Store.data.profile));
  L.Store.data.profile = { name: 'Other', coins: 50 };   // another player's saved profile, no daily data yet
  L.reloadSaved();
  check('another profile has its own calendar (Day 1 open)', L.dailyState().claimable && L.dailyState().today === 0, L.P.daily);
  L.Store.data.profile = mine; L.reloadSaved();
  check('switching back keeps the first profile\'s claim', !L.dailyState().claimable && L.P.daily.streak === 2, L.P.daily);

  // restore
  L.Store.data.profile = JSON.parse(storeBackup); Object.keys(P).forEach(k => delete P[k]); Object.assign(P, JSON.parse(backup));
  document.querySelectorAll('.sheet').forEach(s => { s.hidden = true; });
  const failed = results.filter(r => !r.ok);
  return { passed: results.length - failed.length, failed: failed.length, failures: failed };
})();
