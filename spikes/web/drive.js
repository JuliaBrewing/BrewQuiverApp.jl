const { chromium } = require('playwright');
(async () => {
  const b = await chromium.launch(); const p = await b.newPage({viewport:{width:1420,height:820}});
  p.on('pageerror', e => console.log('pageerror', e.message));
  const t0 = Date.now(); await p.goto('http://127.0.0.1:8765/');
  await p.waitForFunction(() => window.renderedAt); console.log('page load+layout ms', Date.now()-t0);
  // drag a node with the real mouse: grab -> many drags -> free
  const pos = await p.evaluate(() => { const n = cy.getElementById('kettle1').renderedPosition(); const r = document.getElementById('cy').getBoundingClientRect(); return {x:n.x+r.x, y:n.y+r.y}; });
  await p.mouse.move(pos.x, pos.y); await p.mouse.down();
  for (let i=1;i<=30;i++) await p.mouse.move(pos.x+i*3, pos.y+i*2);
  await p.mouse.up(); await p.waitForTimeout(300);
  console.log('history after drag', await p.textContent('#hist'));
  console.log('move msgs median latency ms', await p.evaluate(() => { const a=[...lat].sort((x,y)=>x-y); return a[a.length>>1].toFixed(2); }));
  // form-like edit: scale a lot -> rebrew -> update
  const r = [];
  for (let i=0;i<20;i++) { const t=performance.now(); const m = await p.evaluate(() => send({cmd:'scale', node:'grist1_1', factor:1.01})); r.push(m.ms); }
  console.log('rebrew! server ms (median)', r.sort((a,b)=>a-b)[10].toFixed(2));
  console.log('round-trip scale ms (median)', await p.evaluate(async () => { const a=[]; for (let i=0;i<20;i++){const t=performance.now(); await send({cmd:'scale',node:'goldings',factor:1.0}); a.push(performance.now()-t);} a.sort((x,y)=>x-y); return a[10].toFixed(2); }));
  console.log('changed after scaling goldings', await p.evaluate(() => cy.nodes('.changed').length));
  // create an arrow programmatically via edgehandles flow -> server connect!
  const m = await p.evaluate(() => send({cmd:'connect', source:'invert', target:'kettle2'}));
  console.log('connect reply', m.type, m.changed && m.changed.length, 'edges now', m.graph && m.graph.edges.length);
  const bad = await p.evaluate(() => send({cmd:'connect', source:'bitter', target:'mash1'}));
  console.log('cycle refused:', bad.type, bad.message);
  const u = await p.evaluate(() => send({cmd:'undo'})); console.log('undo ->', u.history);
  await p.screenshot({path:'web.png'}); await b.close();
})();
