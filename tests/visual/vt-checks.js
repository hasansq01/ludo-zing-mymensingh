/* Layout regression checks for the LOCKED home screen (see tests/visual/README.md).
   Loaded by index.html only in test mode (?vt=1). Results go to document.title ("VT:PASS" / "VT:FAIL") and to a JSON
   block #vt-report, which tests/visual/run.ps1 reads. Never loosen these numbers to make a failing run pass: a failure
   means the approved design changed. Update them only together with an approved new baseline. */
(function () {
  // Approved layout at the 390x844 reference viewport (measured 2026-10-19).
  const LOCK = {
    viewport: [390, 844],
    button: { w: 177, h: 62, gap: 12, edge: 12, gapNav: 46, labels: ['VS COMPUTER', 'PASS & PLAY'] },
    table: { elevationDeg: 33, widthPct: 99, topPct: 38.8, bottomPct: 70.0 },
    tol: { px: 2, pct: 0.8, deg: 0.2 },
  };
  const checks = [];
  const add = (name, ok, detail) => checks.push({ name, ok: !!ok, detail });
  const near = (a, b, t) => Math.abs(a - b) <= t;

  function run() {
    const V = window.__vt, stage = document.getElementById('stage');
    const W = stage.clientWidth, H = stage.clientHeight, sr = stage.getBoundingClientRect(), sc = sr.width / W;
    const rel = e => { const q = e.getBoundingClientRect(); return { l: (q.left - sr.left) / sc, r: (q.right - sr.left) / sc, t: (q.top - sr.top) / sc, b: (q.bottom - sr.top) / sc, w: q.width / sc, h: q.height / sc }; };
    const visible = e => { if (!e || e.closest('[hidden]')) return false; const q = rel(e), cs = getComputedStyle(e); return q.w > 0 && q.h > 0 && cs.visibility !== 'hidden' && cs.display !== 'none' && +cs.opacity > 0.05; };
    const inside = q => q.l >= -0.5 && q.t >= -0.5 && q.r <= W + 0.5 && q.b <= H + 0.5;
    const pct = v => v / H * 100;

    add('home screen is showing', V.screen === 'home' && !document.getElementById('home').hidden, V.screen);

    /* HUD, logo, side controls, bottom navigation */
    const must = { 'profile chip': '#profileBtn', 'coin pill': '#coinPill', 'settings button': '#homeGear', 'logo': '.logo-block', 'tab bar': '.tabbar',
      'daily spin': '#spinBtn', 'rewards': '#dailyBtn', 'free coins': '#freeBtn', 'share': '#shareBtn' };
    Object.entries(must).forEach(([n, sel]) => { const e = document.querySelector(sel); add(`${n} visible inside the screen`, visible(e) && inside(rel(e)), e && rel(e)); });
    const tabs = [...document.querySelectorAll('.tabbar .tab')];
    add('5 bottom tabs visible', tabs.length === 5 && tabs.every(t => visible(t) && inside(rel(t))), tabs.length);

    /* game buttons */
    const btns = [...document.querySelectorAll('#home .modes .mode')], md = document.querySelector('#home .modes'),   // the home screen's own buttons (other pages reuse the style)
    tb = document.querySelector('.tabbar');
    const [a, b] = btns.map(rel);
    add('two game buttons visible', btns.length === 2 && btns.every(x => visible(x) && inside(rel(x))), btns.length);
    add('buttons in one row (same top)', near(a.t, b.t, 1), [a.t, b.t]);
    add('buttons equal size', near(a.w, b.w, 1) && near(a.h, b.h, 1), [a.w, a.h, b.w, b.h]);
    add('VS COMPUTER left, PASS & PLAY right', btns[0].id === 'btnCpu' && btns[1].id === 'btnLocal' && a.l < b.l, btns.map(x => x.id));
    add('button labels', btns.map(x => x.querySelector('b').textContent.trim()).join('|') === LOCK.button.labels.join('|'), btns.map(x => x.querySelector('b').textContent));
    add('button labels not clipped', [...document.querySelectorAll('#home .mode b')].every(x => x.scrollWidth <= x.clientWidth + 0.5));
    add('outer margins equal', near(a.l, W - b.r, 1), [a.l, W - b.r]);
    const gapNav = rel(tb).t - rel(md).b;
    add('at least 12px between buttons and bottom navigation', gapNav >= 12, gapNav);
    add('buttons are tappable (topmost element at their centre)', btns.every(x => { const q = x.getBoundingClientRect(); const hit = document.elementFromPoint(q.left + q.width / 2, q.top + q.height / 2); return hit && x.contains(hit); }));

    /* 3D table framing */
    const f = V.homeFit(), [t, bt, hw] = V.rimOnScreen(f.d), top = t + f.dy, bot = bt + f.dy;
    const logo = document.querySelector('.logo-block'), logoBottom = logo.offsetTop + logo.offsetHeight;
    const sideBottom = Math.max(...[...document.querySelectorAll('.side-btn')].filter(visible).map(e => rel(e).b));
    add('table starts below the logo', top > logoBottom, [top, logoBottom]);
    add('table starts below the side controls', top > sideBottom, [top, sideBottom]);
    add('table ends above the game buttons', bot < rel(md).t, [bot, rel(md).t]);
    add('whole table width on screen', hw * 2 <= W + 0.5, hw * 2);

    /* overflow */
    const over = [...document.querySelectorAll('#home *')].filter(e => { if (!visible(e)) return false; return !inside(rel(e)); }).map(e => e.id || e.className.baseVal || e.className);
    add('nothing in the home screen overflows the viewport', over.length === 0, over.slice(0, 5));
    const wrap = document.querySelector('.home-wrap');
    add('home content does not scroll vertically', wrap.scrollHeight <= wrap.clientHeight + 1, [wrap.scrollHeight, wrap.clientHeight]);
    add('no page scroll', document.documentElement.scrollHeight <= innerHeight + 1 && document.documentElement.scrollWidth <= innerWidth + 1);

    /* locked numbers at the reference viewport */
    const metrics = { stage: [W, H], button: [a.w, a.h], buttonGap: b.l - a.r, edges: [a.l, W - b.r], gapNav,
      elevationDeg: f.el * 180 / Math.PI, tableWidthPct: hw * 2 / W * 100, tableTopPct: pct(top), tableBottomPct: pct(bot) };
    if (W === LOCK.viewport[0] && H === LOCK.viewport[1]) {
      const L = LOCK, T = L.tol;
      add('LOCK button size 177x62', near(a.w, L.button.w, T.px) && near(a.h, L.button.h, T.px), metrics.button);
      add('LOCK button gap 12px', near(metrics.buttonGap, L.button.gap, T.px), metrics.buttonGap);
      add('LOCK screen-edge margins 12px', near(a.l, L.button.edge, T.px) && near(W - b.r, L.button.edge, T.px), metrics.edges);
      add('LOCK gap above bottom navigation 46px', near(gapNav, L.button.gapNav, T.px), gapNav);
      add('LOCK camera tilt 33°', near(metrics.elevationDeg, L.table.elevationDeg, T.deg), metrics.elevationDeg);
      add('LOCK table width 99%', near(metrics.tableWidthPct, L.table.widthPct, T.pct), metrics.tableWidthPct);
      add('LOCK table top 38.8%', near(metrics.tableTopPct, L.table.topPct, T.pct), metrics.tableTopPct);
      add('LOCK table bottom 70.0%', near(metrics.tableBottomPct, L.table.bottomPct, T.pct), metrics.tableBottomPct);
    }
    const failed = checks.filter(c => !c.ok);
    const out = document.createElement('script');
    out.type = 'application/json'; out.id = 'vt-report';
    out.textContent = JSON.stringify({ pass: failed.length === 0, failed: failed.length, total: checks.length, metrics, checks });
    document.head.appendChild(out);
    document.title = failed.length ? `VT:FAIL ${failed.length}/${checks.length}` : `VT:PASS ${checks.length}`;
  }
  (function wait() {   // home is up, its layout measured, and the frozen camera has rendered
    if (window.__vt && window.__vt.screen === 'home' && document.fonts.status === 'loaded') setTimeout(() => { try { run(); } catch (e) { document.title = 'VT:ERROR ' + e.message; } }, 1500);
    else setTimeout(wait, 100);
  })();
})();
