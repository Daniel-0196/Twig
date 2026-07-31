// Twig 原型 E2E 测试电池（headless Chrome + CDP）
// 用法: node tests/proto-e2e.mjs <url>
const url = process.argv[2] || 'http://localhost:64973/?key=56af68c04f00e580af04981e8b8f3c4422f72cb0d57336da3cd613dd4c9c4283';
const { spawn } = await import('child_process');
const chrome = spawn('/Applications/Google Chrome.app/Contents/MacOS/Google Chrome',
  ['--headless=new', '--remote-debugging-port=9333', '--user-data-dir=/tmp/twig-e2e-' + Date.now(),
   '--window-size=1400,900', url], { stdio: 'ignore' });
let list = null;
for (let i = 0; i < 20 && !list; i++) {
  await new Promise(r => setTimeout(r, 500));
  list = await fetch('http://127.0.0.1:9333/json/list').then(r => r.json()).catch(() => null);
}
if (!list) { console.log('Chrome CDP 连接失败'); chrome.kill(); process.exit(2); }
const page = list.find(t => t.type === 'page' && t.url.includes('localhost'));
const ws = new WebSocket(page.webSocketDebuggerUrl);
let id = 0;
const pending = new Map();
const send = (method, params = {}) => new Promise((resolve) => {
  const mid = ++id; pending.set(mid, resolve);
  ws.send(JSON.stringify({ id: mid, method, params }));
});
ws.onmessage = (ev) => {
  const msg = JSON.parse(ev.data);
  if (msg.id && pending.has(msg.id)) { pending.get(msg.id)(msg); pending.delete(msg.id); }
};

let passed = 0, failed = 0;
function check(name, cond, detail = '') {
  if (cond) { passed++; console.log(`  ✅ ${name}`); }
  else { failed++; console.log(`  ❌ ${name} ${detail}`); }
}
async function evaljs(expr) {
  const r = await send('Runtime.evaluate', { expression: expr, returnByValue: true });
  if (r.result?.exceptionDetails) return { __error: r.result.exceptionDetails.text };
  return r.result?.result?.value;
}
async function nodePos(title) {
  return evaljs(`(() => {
    const el = [...document.querySelectorAll('.node')].find(n => n.querySelector('.t')?.textContent.includes('${title}'));
    if (!el) return null;
    const r = el.getBoundingClientRect();
    return JSON.stringify({x: r.x + r.width/2, y: r.y + r.height/2, op: getComputedStyle(el).opacity, cls: el.className});
  })()`).then(v => v ? JSON.parse(v) : null);
}
async function drag(from, dx, dy, steps = 15) {
  await send('Input.dispatchMouseEvent', { type: 'mousePressed', x: from.x, y: from.y, button: 'left', clickCount: 1 });
  for (let i = 1; i <= steps; i++) {
    await send('Input.dispatchMouseEvent', { type: 'mouseMoved', x: from.x + dx * i / steps, y: from.y + dy * i / steps });
    await new Promise(r => setTimeout(r, 40));
  }
}
async function mouseUp(x, y) {
  await send('Input.dispatchMouseEvent', { type: 'mouseReleased', x, y, button: 'left', clickCount: 1 });
}
const sleep = ms => new Promise(r => setTimeout(r, ms));

ws.onopen = async () => {
  await send('Runtime.enable');
  await send('Page.enable');
  await send('Emulation.setDeviceMetricsOverride', { width: 1400, height: 900, deviceScaleFactor: 1, mobile: false });
  await send('Page.reload', { ignoreCache: true });
  await sleep(1500);

  // ---- T0 版本水印 ----
  console.log('T0 版本水印');
  const ver = await evaljs(`document.querySelector('.hint b')?.textContent`);
  check('页面带版本水印', /v\d+/.test(ver || ''), ver);

  // ---- T1 初始布局 ----
  console.log('T1 初始布局');
  const t1 = JSON.parse(await evaljs(`JSON.stringify({
    rect: document.querySelector('.screen-rect').getBoundingClientRect().toJSON(),
    stage: document.getElementById('stage').getBoundingClientRect().toJSON(),
    offsets: treeOffsets,
  })`));
  const rectCX = t1.rect.x + t1.rect.width / 2, stageCX = t1.stage.x + t1.stage.width / 2;
  check('屏幕矩形水平居中', Math.abs(rectCX - stageCX) < 30, `rect中点${rectCX} vs stage中点${stageCX}`);
  check('偏移为零', t1.offsets.twig.x === 0 && t1.offsets.twig.y === 0);
  const v02a = await nodePos('画板交互');
  const v05a = await nodePos('交互定版');
  const greenA = await nodePos('渲染管线');
  check('根节点(v0.2)在屏内', v02a && v02a.y > t1.rect.y && v02a.y < t1.rect.y + t1.rect.height, JSON.stringify(v02a));
  check('v0.5 埋在土壤线下（半透明）', v05a && v05a.y > t1.rect.y + t1.rect.height && parseFloat(v05a.op) < 0.3, JSON.stringify(v05a));
  check('两树根同高度', v02a && greenA && Math.abs(v02a.y - greenA.y) < 30, `${v02a?.y} vs ${greenA?.y}`);

  // ---- T2 拔树 ----
  console.log('T2 拔树（向上 300px）');
  await drag(v02a, 0, -300);
  await sleep(200);
  const mid1 = JSON.parse(await evaljs(`JSON.stringify(treeOffsets)`));
  check('偏移跟随拖拽（向上为负）', mid1.twig.y < -100, JSON.stringify(mid1));
  check('绿树纹丝不动', mid1.mergeCook4.y === 0 && mid1.mergeCook4.x === 0);
  const v05b = await nodePos('交互定版');
  const v10b = await nodePos('主力工具');
  check('v0.5 出土（变实）', v05b && parseFloat(v05b.op) > 0.9, JSON.stringify(v05b));
  check('v1.0 未提前出土（顺序约束）', v10b && (v10b.cls.includes('offscreen') || parseFloat(v10b.op) < 0.95), JSON.stringify(v10b));

  // ---- T3 松手回弹 ----
  console.log('T3 松手回弹');
  await mouseUp(v02a.x, v02a.y - 300);
  await sleep(900);
  const mid2 = JSON.parse(await evaljs(`JSON.stringify(treeOffsets)`));
  check('偏移归零（弹回）', Math.abs(mid2.twig.y) < 1 && Math.abs(mid2.twig.x) < 1, JSON.stringify(mid2));
  const v02b = await nodePos('画板交互');
  check('v0.2 回到初始位置', v02b && Math.abs(v02b.y - v02a.y) < 15, `${v02a.y} → ${v02b?.y}`);
  const v05c = await nodePos('交互定版');
  check('出土的 v0.5 留下', v05c && !v05c.cls.includes('offscreen'));

  // ---- T4 方向切换 ----
  console.log('T4 方向切换到向右');
  await evaljs(`localStorage.clear(); location.reload();`);
  await sleep(1500);
  await evaljs(`[...document.querySelectorAll('#dirbar button')].find(b => b.dataset.dir === 'right').click(); 'ok'`);
  await sleep(500);
  const t4 = JSON.parse(await evaljs(`JSON.stringify(treeOffsets)`));
  check('切换后偏移为零', t4.twig.x === 0 && t4.twig.y === 0);
  const v02r = await nodePos('画板交互');
  const v05r = await nodePos('交互定版');
  check('向右布局：v0.5 在 v0.2 右侧（或埋着）', v05r && v02r && v05r.x > v02r.x, `${v02r?.x} vs ${v05r?.x}`);
  await evaljs(`[...document.querySelectorAll('#dirbar button')].find(b => b.dataset.dir === 'up').click(); 'ok'`);
  await sleep(400);

  // ---- T5 悬停功能区 ----
  console.log('T5 悬停出功能区');
  const v02d = await nodePos('画板交互');
  await send('Input.dispatchMouseEvent', { type: 'mouseMoved', x: v02d.x, y: v02d.y });
  await sleep(400);
  const t5 = JSON.parse(await evaljs(`JSON.stringify({
    acts: document.querySelectorAll('.acts').length,
    display: document.querySelector('.acts') ? getComputedStyle(document.querySelector('.acts')).display : null,
  })`));
  check('功能区出现且可见', t5.acts === 1 && t5.display === 'flex', JSON.stringify(t5));

  console.log(`\n结果: ${passed} 通过, ${failed} 失败`);
  ws.close();
  chrome.kill();
  process.exit(failed ? 1 : 0);
};
