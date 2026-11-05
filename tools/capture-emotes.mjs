// Dev: captures the web version's emote stickers (index.html on the branch that has them) frame by frame into
// godot/assets/emotes/<id>/NNN.webp + icon.webp, 344 x 218 with a clear background (server/EMOTES.md "Art").
//   mkdir www www/f; git show <branch>:index.html > www/index.html; copy LilitaOne / NotoSansBengali.woff2 to www/f
//   npm i puppeteer-core; CHROME=<a Chrome or chrome-headless-shell> node capture-emotes.mjs <outDir> [ids...]
// A sticker's loop: seamless when its animations' periods fit in 2.4 s (the time a reaction holds), else 2.4 s; 15 fps.
// Phrase stickers: their 1.4 s bob at 8 fps. Write the frames / fps of a new emote into emotes.json (captured.json has them).
import puppeteer from 'puppeteer-core'; import http from 'http'; import fs from 'fs'; import path from 'path';
const CHROME = process.env.CHROME, OUT = process.argv[2], WANT = process.argv.slice(3);
const www = new URL('./www/', import.meta.url).pathname;
const types = {'.html':'text/html; charset=utf-8','.woff2':'font/woff2'};
const srv = http.createServer((q,s)=>{ const p = path.join(www, q.url.split('?')[0]); if(!fs.existsSync(p)||fs.statSync(p).isDirectory()){s.writeHead(404);return s.end();} s.writeHead(200,{'content-type':types[path.extname(p)]||'application/octet-stream','cache-control':'no-store'}); fs.createReadStream(p).pipe(s); }).listen(8120,'127.0.0.1');
const b = await puppeteer.launch({executablePath:CHROME, headless:'shell', args:['--no-sandbox']});
const pg = await b.newPage(); await pg.setViewport({width:172,height:109,deviceScaleFactor:2});
pg.on('pageerror',e=>console.error('pageerror',String(e).slice(0,200)));
await pg.goto('http://127.0.0.1:8120/index.html?vt=1',{waitUntil:'load'}); await new Promise(r=>setTimeout(r,1500));
const list = await pg.evaluate(async()=>{
  for (const [fam,file] of [['Lilita One','LilitaOne'],['Noto Sans Bengali','NotoSansBengali']]) { const f=new FontFace(fam,`url(/f/${file}.woff2)`,{weight:'100 900'}); await f.load(); document.fonts.add(f); }
  const st=document.createElement('style'); st.textContent='html,body{background:transparent!important;margin:0!important;overflow:hidden!important} body>*:not(#__h){display:none!important} #__h{position:fixed;left:0;top:0;width:172px;height:109px;z-index:99999} #__h svg{display:block;width:172px;height:109px;overflow:hidden}';
  document.head.appendChild(st);
  document.documentElement.classList.remove('vt'); document.body.classList.remove('vt');
  for (const el of [...document.querySelectorAll('style')]) if (el!==st && /animation:\s*none\s*!important/.test(el.textContent)) el.textContent=el.textContent.replace(/animation:\s*none\s*!important/g,'');
  const h=document.createElement('div'); h.id='__h'; document.body.appendChild(h);
  return window.__ludo.EMOTES.map(e=>({id:e.id,name:e.name,group:e.group,pack:e.pack||''}));
});
const manifest=[]; const group_text=e=>e.group==='text';
for (const e of list) { if (WANT.length && !WANT.includes(e.id)) continue;
  const durs = await pg.evaluate(id=>{ const E=window.__ludo.EMOTES.find(x=>x.id===id); const h=document.getElementById('__h'); h.innerHTML=E.art;
    const an=h.getAnimations({subtree:true}); an.forEach(a=>a.pause()); return an.map(a=>{const t=a.effect.getComputedTiming(); return {d:t.duration, dir:t.direction}; }); }, e.id);
  // the sticker's loop: the least common multiple of its animations' periods (alternate counts double), at most 2.8 s, else the longest under it
  const per=[...new Set(durs.map(x=>Math.round(x.d*(x.dir==='alternate'?2:1))))].filter(Boolean);
  const gcd=(a,b)=>b?gcd(b,a%b):a, lcm=(a,b)=>a*b/gcd(a,b);
  let loop=per.reduce(lcm,1); if(per.length===0) loop=1400; if(group_text(e)) loop=1400; else if(loop>2400) loop=2400;
  const isText=e.group==='text'; const fps=isText?8:15; const n=Math.max(2,Math.round(loop/1000*fps)); const dir=path.join(OUT,e.id); fs.mkdirSync(dir,{recursive:true});
  for(let k=0;k<n;k++){ const t=loop*k/n; await pg.evaluate(t=>{document.getElementById('__h').getAnimations({subtree:true}).forEach(a=>{a.currentTime=t;});},t);
    await pg.screenshot({path:path.join(dir,String(k).padStart(3,'0')+'.webp'),type:'webp',quality:82,omitBackground:true}); }
  fs.copyFileSync(path.join(dir,String(Math.floor(n/3)).padStart(3,'0')+'.webp'),path.join(dir,'icon.webp'));
  manifest.push({id:e.id,name:e.name,group:e.group,pack:e.pack,frames:n,fps:+(n/(loop/1000)).toFixed(3),loop_s:loop/1000,periods:per}); console.log(e.id,n,loop,per.join(','));
}
fs.writeFileSync(path.join(OUT,'captured.json'),JSON.stringify(manifest,null,1)); await b.close(); srv.close();
