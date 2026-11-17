// Frame-rate check of the web export for plan AC 34 (60 fps on a mid-range phone during the
// busiest boss level). A desktop stand-in for that phone: headless Chrome on the real GPU
// (ANGLE on Metal; the smoke test's SwiftShader is software and far slower), an 844x390 phone
// viewport at 3x (2532x1170 pixels drawn) with touch, and the CPU slowed 4x through the
// DevTools protocol. It plants a save with every level before night_6 finished, taps
// Campaign, Night and night_6, lets the level play to its end without shooting (a level has no
// escape limit, so every wave and the closing boss flock fly), and counts the page's animation
// frames. It prints the frame rate per second and its summary for the whole level and for the
// boss wave. A real phone remains the reference: plan AC 37's playtest.
// Usage (repo root): node tools/perf_web.mjs [buildDir] (default build/web).
import { resolve } from 'node:path';
import { chromium } from 'playwright';
import { serveBuild } from './web_util.mjs';

const buildDir = resolve(process.argv[2] ?? 'build/web');
const CPU_SLOWDOWN = 4;
const STEP_TIMEOUT_MS = 30000;
const LEVEL_TIMEOUT_MS = 240000;
const BASE = { width: 960, height: 540 };
const LEVEL = 'night_6';
const SAVE_FILE = /^\[Game\] Browser storage \(IndexedDB\) is available for user:\/\/save\.json \((\/userfs\/.+)\)$/;
const CAMPAIGN_RECT = /^\[Title\] Campaign button at \[P: \(([\d.-]+), ([\d.-]+)\), S: \(([\d.-]+), ([\d.-]+)\)\]/;
const NIGHT_RECT = /^\[ChapterSelect\] Chapter night at \[P: \(([\d.-]+), ([\d.-]+)\), S: \(([\d.-]+), ([\d.-]+)\)\] \(open/;
const LEVEL_RECT = new RegExp(`^\\[LevelSelect\\] Level ${LEVEL} at \\[P: \\(([\\d.-]+), ([\\d.-]+)\\), S: \\(([\\d.-]+), ([\\d.-]+)\\)\\] \\(open`);
const FINISHED = ['dawn', 'noon', 'sunset', 'night'].flatMap((c) => [1, 2, 3, 4, 5, 6].map((i) => `${c}_${i}`)).filter((id) => id !== LEVEL);
const SAVE = JSON.stringify({
  version: 4,
  bests: { endless: 0, time_attack: 0 },
  levels: Object.fromEntries(FINISHED.map((id) => [id, { stars: 1, score: 1000 }])),
  settings: { music: 70, sfx: 80, music_muted: false, sfx_muted: false, reduce_motion: false },
});
// Records each animation frame's time (performance.now()) from page start.
const FRAME_RECORDER = `
  window.__frames = [];
  const tick = (t) => { window.__frames.push(t); requestAnimationFrame(tick); };
  requestAnimationFrame(tick);
`;

async function waitForLog(page, logs, pattern, what, from = 0, timeoutMs = STEP_TIMEOUT_MS) {
  const deadline = Date.now() + timeoutMs;
  while (Date.now() < deadline) {
    for (let i = from; i < logs.length; i++) {
      const match = logs[i].match(pattern);
      if (match) return Object.assign(match, { index: i });
    }
    await page.waitForTimeout(100);
  }
  throw new Error(`timed out waiting for ${what} (${pattern})`);
}

// Taps the centre of the latest button rect matching `pattern` (base units) with a CDP touch.
async function tapButton(page, cdp, logs, pattern, what, from) {
  const [x, y, w, h] = (await waitForLog(page, logs, pattern, what, from)).slice(1).map(Number);
  const box = await page.locator('canvas').boundingBox();
  const scale = Math.min(box.width / BASE.width, box.height / BASE.height);
  const point = { x: box.x + (x + w / 2) * scale, y: box.y + (y + h / 2) * scale, id: 7 };
  await cdp.send('Input.dispatchTouchEvent', { type: 'touchStart', touchPoints: [point] });
  await cdp.send('Input.dispatchTouchEvent', { type: 'touchEnd', touchPoints: [] });
}

async function plantSave(page, logs) {
  const file = (await waitForLog(page, logs, SAVE_FILE, 'the save path'))[1];
  const error = await page.evaluate(([path, text]) => new Promise((done) => {
    const request = indexedDB.open('/userfs');
    request.onerror = () => done(`cannot open IndexedDB: ${request.error}`);
    request.onsuccess = () => {
      const db = request.result;
      const write = db.transaction(['FILE_DATA'], 'readwrite');
      const store = write.objectStore('FILE_DATA');
      const parts = path.split('/');
      for (let i = 3; i < parts.length; i++) store.put({ timestamp: new Date(), mode: 16895 }, parts.slice(0, i).join('/'));
      store.put({ timestamp: new Date(), mode: 33188, contents: new TextEncoder().encode(text) }, path);
      write.oncomplete = () => { db.close(); done(''); };
      write.onerror = () => { db.close(); done(`cannot write the save: ${write.error}`); };
    };
  }), [file, SAVE]);
  if (error !== '') throw new Error(error);
}

// Frames per whole second between `from` and `to` (ms), from the recorded frame times.
function perSecond(frames, from, to) {
  const counts = [];
  for (let start = from; start + 1000 <= to; start += 1000) {
    counts.push(frames.filter((t) => t >= start && t < start + 1000).length);
  }
  return counts;
}

function summary(counts) {
  const sorted = [...counts].sort((a, b) => a - b);
  const mean = counts.reduce((a, b) => a + b, 0) / counts.length;
  return `mean ${mean.toFixed(1)} fps, lowest second ${sorted[0]} fps, 10th percentile ${sorted[Math.floor(sorted.length / 10)]} fps over ${counts.length} s`;
}

const served = await serveBuild(buildDir);
const browser = await chromium.launch({ channel: 'chrome', headless: true, args: ['--use-angle=metal', '--enable-gpu', '--ignore-gpu-blocklist'] });
try {
  const context = await browser.newContext({ viewport: { width: 844, height: 390 }, deviceScaleFactor: 3, hasTouch: true, isMobile: true });
  await context.addInitScript(FRAME_RECORDER);
  const page = await context.newPage();
  const logs = [];

  page.on('console', (m) => logs.push(m.text()));
  const cdp = await context.newCDPSession(page);
  await page.goto(served.url);
  await waitForLog(page, logs, /^\[Game\] Arrived at TITLE/, 'the title');
  const renderer = await page.evaluate(() => {
    const gl = document.createElement('canvas').getContext('webgl2');
    const info = gl?.getExtension('WEBGL_debug_renderer_info');
    return info ? gl.getParameter(info.UNMASKED_RENDERER_WEBGL) : 'unknown';
  });
  console.log(`renderer: ${renderer}`);
  await plantSave(page, logs);
  logs.length = 0;
  await page.reload();
  await waitForLog(page, logs, /^\[Game\] Arrived at TITLE/, 'the title after the planted save');
  await cdp.send('Emulation.setCPUThrottlingRate', { rate: CPU_SLOWDOWN });
  let from = logs.length;
  await tapButton(page, cdp, logs, CAMPAIGN_RECT, 'Campaign', 0);
  await waitForLog(page, logs, /^\[Game\] Arrived at CHAPTER_SELECT/, 'the chapter select', from);
  from = logs.length;
  await tapButton(page, cdp, logs, NIGHT_RECT, 'the Night chapter (open)', 0);
  await waitForLog(page, logs, /^\[Game\] Arrived at LEVEL_SELECT/, 'the level select', from);
  // The level select logs its buttons before it arrives: search from the Night tap.
  await tapButton(page, cdp, logs, LEVEL_RECT, `${LEVEL} (open)`, from);
  from = logs.length;
  await waitForLog(page, logs, /^\[Game\] Arrived at PLAY/, `${LEVEL} to start`, from);
  const start = await page.evaluate(() => performance.now());
  const bossLine = await waitForLog(page, logs, /^\[Play\] Wave 5 start: .*boss flock/, 'the boss wave', from, LEVEL_TIMEOUT_MS);
  const bossStart = await page.evaluate(() => performance.now());
  await waitForLog(page, logs, /^\[Play\] Run end: /, `${LEVEL} to end`, bossLine.index, LEVEL_TIMEOUT_MS);
  const end = await page.evaluate(() => performance.now());
  const frames = await page.evaluate(() => window.__frames);
  console.log(`${LEVEL} at ${CPU_SLOWDOWN}x CPU slowdown, 844x390 at 3x: ${logs[bossLine.index]}`);
  console.log(`per second (whole level): ${perSecond(frames, start, end).join(' ')}`);
  console.log(`whole level: ${summary(perSecond(frames, start, end))}`);
  console.log(`boss wave: ${summary(perSecond(frames, bossStart, end))}`);
} finally {
  await browser.close();
  served.server.close();
}
