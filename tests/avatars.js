// Avatar tests for Ludo Zing Mymensingh: the 12 "More characters" avatars (WORLD).
// Run in the browser console on the source game page with ?vt=1, in a foreground tab, after the splash: paste the
// whole file. Resolves to { passed, failed, failures }.
(async () => {
  const L = window.__ludo, P = L.P, $ = id => document.getElementById(id);
  const results = [];
  const check = (name, ok, got) => results.push({ name, ok: !!ok, got: ok ? undefined : JSON.stringify(got) });
  const sleep = ms => new Promise(r => setTimeout(r, ms));
  const keep = JSON.stringify({ avatar: P.avatar, name: P.name });
  const svgOk = s => /^<svg viewBox="0 0 40 40"/.test(s) && !/undefined|NaN/.test(s);

  // ---- the avatars ----
  const W = L.WORLD;
  check('12 more characters', W.length === 12);
  check('no labels by origin: no region field', W.every(a => !('region' in a)));
  check('they are free, unlocked and in the avatar list', W.every(a => a.price === 0 && L.AVATARS.includes(a)));
  check('avatar ids are unique', new Set(L.AVATARS.map(a => a.id)).size === L.AVATARS.length);
  check('every avatar draws cleanly', W.every(a => svgOk(L.personSVG(a))), W.filter(a => !svgOk(L.personSVG(a))).map(a => a.id));
  check('they cover light to deep skin tones and several eye shapes', new Set(W.map(a => a.skin)).size >= 7 && new Set(W.map(a => a.eye || 'round')).size >= 3);
  check('the original characters keep their look (Sabbir keeps the buzz-cut beard, Nadia her lashes and lips)',
    /M12\.6 18\.4C12\.8 25\.2/.test(L.personSVG(L.CHARS.find(c => c.id === 'ch-sabbir'))) && /M15\.2 17\.3L14\.6 16\.6/.test(L.personSVG(L.CHARS.find(c => c.id === 'ch-nadia'))) && /#d9536a/.test(L.personSVG(L.CHARS.find(c => c.id === 'ch-nadia'))));

  // ---- where players find them ----
  L.goHome(); await sleep(50);
  $('profileBtn').click(); await sleep(200);
  $('ppEditBtn').click(); await sleep(200);
  const grid = $('ppAvaGrid');
  check('the avatars are in the Edit Profile grid', W.every(a => grid.querySelector(`[data-av="${a.id}"]`)));
  check('no avatar maker: no Make your own button or tile', !$('ppMakeAva') && !grid.querySelector('[data-avm]') && !$('avMakerSheet'));
  grid.querySelector('[data-av="w-kenji"]').click();
  $('ppNameInput').value = 'Tester'; $('ppNameInput').dispatchEvent(new Event('input')); $('ppSave').click(); await sleep(100);   // a new player's name field starts empty
  check('picking one in Edit Profile and saving equips it', P.avatar === 'w-kenji' && L.Store.data.profile.avatar === 'w-kenji');
  document.querySelector('#ppColTabs [data-tab="chars"]').click(); await sleep(50);
  const col = $('ppCol');
  check('Collection › Characters: Male, Female, then all 12 together under More characters', [...col.querySelectorAll('.col-h')].map(h => h.textContent).join() === 'Male,Female,More characters' && W.every(a => col.querySelector(`[data-equip="${a.id}"]`) || P.avatar === a.id));
  col.querySelector('[data-equip="w-maya"]').click(); await sleep(50);
  check('a avatar can be equipped from Collection', P.avatar === 'w-maya');
  $('ppBack').click(); await sleep(50);
  check('the home chip shows it', $('profileAva').innerHTML.includes('#8d5a3b'));
  L.newGame(['human', 'cpu', 'cpu', 'cpu'], false); await sleep(300);
  check('in a game, your card wears it', document.querySelector('#pcards .pcard[data-pos="bl"] .ava').innerHTML.includes('#8d5a3b'));
  L.goHome(); await sleep(50);
  P.avatar = 'w-emma'; L.ensureProfile();
  check('a avatar survives ensureProfile', P.avatar === 'w-emma');

  const k = JSON.parse(keep); P.avatar = k.avatar; P.name = k.name;
  const failures = results.filter(r => !r.ok);
  return { passed: results.length - failures.length, failed: failures.length, failures };
})();
