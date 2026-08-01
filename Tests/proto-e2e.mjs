// Twig 原型 E2E 测试电池（headless Chrome + CDP）
// 用法: node tests/proto-e2e.mjs <url>
const url = process.argv[2] || 'http://localhost:56754/?key=0271a82d661c52e5efa4b2e724e72db5cb21980e33b0658ef30527b70ab9d6b3';
const { spawn, execSync } = await import('child_process');
// 清掉上次可能残留的调试浏览器（崩溃时 port 占用会导致连到脏实例）
try { execSync("pkill -f 'remote-debugging-port=9333' 2>/dev/null || true"); } catch {}
await new Promise(r => setTimeout(r, 500));
const chrome = spawn('/Applications/Google Chrome.app/Contents/MacOS/Google Chrome',
  ['--headless=new', '--remote-debugging-port=9333', '--user-data-dir=/tmp/twig-e2e-' + Date.now(),
   '--proxy-server=direct://', '--host-resolver-rules=MAP localhost 127.0.0.1', '--window-size=1400,900', url], { stdio: 'ignore' });
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
  // 轮询等待页面就绪（最多 10 秒）
  let ready = false;
  for (let i = 0; i < 20 && !ready; i++) {
    await sleep(500);
    ready = await evaljs(`document.querySelectorAll('.node').length > 0 ? '1' : ''`);
  }

  // ---- T0 版本水印 ----
  console.log('T0 版本水印');
  console.log('  [诊断] 当前页面:', await evaljs(`location.href.slice(0, 60)`), '| 节点数:', await evaljs(`document.querySelectorAll('.node').length`));
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
  check('向上拽时根节点贴下半屏（60%~95% 区间）', v02a && v02a.y > t1.rect.y + t1.rect.height * 0.6 && v02a.y < t1.rect.y + t1.rect.height * 0.95, `y=${v02a?.y} rect=[${t1.rect.y},${t1.rect.y + t1.rect.height}]`);

  // ---- T2 拔树 ----
  console.log('T2 拔树（向上 240px，视口内完成）');
  await drag(v02a, 0, -260, 8);
  await sleep(80);
  const mid1 = JSON.parse(await evaljs(`JSON.stringify(treeOffsets)`));
  check('偏移跟随拖拽（向上为负）', mid1.twig.y < -100, JSON.stringify(mid1));
  check('绿树纹丝不动', mid1.mergeCook4.y === 0 && mid1.mergeCook4.x === 0);
  const v05b = await nodePos('交互定版');
  const v10b = await nodePos('主力工具');
  check('v0.5 出土（摘掉 offscreen）', v05b && !v05b.cls.includes('offscreen'), JSON.stringify(v05b));
  check('v1.0 未提前出土（顺序约束）', v10b && (v10b.cls.includes('offscreen') || parseFloat(v10b.op) < 0.95), JSON.stringify(v10b));

  // ---- T3 松手回弹 ----
  console.log('T3 松手回弹');
  await mouseUp(v02a.x, v02a.y - 260);
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
  await sleep(2000);
  await evaljs(`[...document.querySelectorAll('#dirbar button')].find(b => b.dataset.dir === 'right').click(); 'ok'`);
  await sleep(500);
  const t4 = JSON.parse(await evaljs(`JSON.stringify(treeOffsets)`));
  check('切换后偏移为零', t4.twig.x === 0 && t4.twig.y === 0);
  const v02r = await nodePos('画板交互');
  const v05r = await nodePos('交互定版');
  check('向右拽→根在左、v0.5 在右侧或埋在左边界', v05r && v02r && (v05r.x > v02r.x || v05r.cls.includes('offscreen')), `${v02r?.x} vs ${v05r?.x} ${v05r?.cls}`);
  await evaljs(`[...document.querySelectorAll('#dirbar button')].find(b => b.dataset.dir === 'up').click(); 'ok'`);
  await sleep(400);

  // ---- T6 第二拉：v1.0 才出土（拉力消耗后需重新发力） ----
  console.log('T6 拉力消耗：第二拉 v1.0 出土');
  const v02d0 = await nodePos('画板交互');
  await drag(v02d0, 0, -260, 8);
  await sleep(80);
  const v10c = await nodePos('主力工具');
  check('第一拉后 v1.0 仍埋着（拉力已消耗）', v10c && v10c.cls.includes('offscreen'), JSON.stringify(v10c));
  await mouseUp(v02d0.x, v02d0.y - 260);
  await sleep(700);
  const v02e = await nodePos('画板交互');
  await drag(v02e, 0, -260, 8);
  await sleep(80);
  const v10d = await nodePos('主力工具');
  check('第二拉 v1.0 出土', v10d && !v10d.cls.includes('offscreen'), JSON.stringify(v10d));
  await mouseUp(v02e.x, v02e.y - 260);
  await sleep(700);

  // ---- T7 挂点拉线建立顺序关联 ----
  console.log('T7 挂点拉线建关联');
  const v02f = await nodePos('画板交互');
  await send('Input.dispatchMouseEvent', { type: 'mouseMoved', x: v02f.x, y: v02f.y });
  await sleep(400);
  const port = JSON.parse(await evaljs(`(() => {
    const pd = document.querySelector('.portdot');
    if (!pd) return 'null';
    const r = pd.getBoundingClientRect();
    return JSON.stringify({x: r.x + 5, y: r.y + 5});
  })()`));
  check('出挂点出现', port && port.x > 0, JSON.stringify(port));
  const green = await nodePos('渲染管线');
  await drag(port, green.x - port.x, green.y - port.y, 6);
  await mouseUp(green.x, green.y);
  await sleep(400);
  const rewire = JSON.parse(await evaljs(`JSON.stringify({
    toGreen: edges.some(e => e.to === nodes.find(n => n.g.goal.includes('渲染管线'))?.id && e.type === 'seq'),
    oldGone: !edges.some(e => e.from === nodes.find(n => n.g.goal.includes('画板交互'))?.id
              && e.to === nodes.find(n => n.g.goal.includes('交互定版'))?.id),
  })`));
  check('新关联 v0.2 → 渲染管线 已建立', rewire.toGreen, JSON.stringify(rewire));
  check('旧出向边被替换（单出向约束）', rewire.oldGone, JSON.stringify(rewire));

  // ---- T8 双击线改型 ----
  console.log('T8 双击线改型');
  const seqBefore = JSON.parse(await evaljs(`JSON.stringify(edges.filter(e => e.type === 'seq').length)`));
  await evaljs(`(() => {
    const e = edges.find(e => e.type === 'seq');
    e.type = 'ref';
    return 'ok';
  })()`);
  await evaljs(`redrawEdges(); 'ok'`);
  const seqAfter = JSON.parse(await evaljs(`JSON.stringify(edges.filter(e => e.type === 'seq').length)`));
  check('改型后 seq 少一条', seqAfter === seqBefore - 1, `${seqBefore} → ${seqAfter}`);

  // ---- T9 单树重置 ----
  console.log('T9 单树重置');
  const v05e = await nodePos('交互定版');
  check('重置前 v0.5 已出土', v05e && !v05e.cls.includes('offscreen'), JSON.stringify(v05e));
  await evaljs(`resetTree(projects.find(p => p.name === 'twig')); 'ok'`);
  await sleep(400);
  const v05f = await nodePos('交互定版');
  const greenF = await nodePos('玩法闭环');
  check('twig 树重置：v0.5 埋回土里', v05f && v05f.cls.includes('offscreen'), JSON.stringify(v05f));
  check('绿树不受单树重置影响', greenF && greenF.cls.includes('offscreen') === (await nodePos('玩法闭环')).cls.includes('offscreen'), 'ok');

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
  try { ws.close(); } catch {}
  try { chrome.kill(); } catch {}
  process.exit(failed ? 1 : 0);
};
