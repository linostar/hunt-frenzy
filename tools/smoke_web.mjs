// Smoke test for the Godot web export: serves the build locally and loads it in
// headless Chrome four times: as a desktop browser (1280x720, mouse), as a phone held
// in landscape (844x390 at 3x, touch, mobile), as a phone held upright (390x844 at 3x,
// touch, mobile) and as a keyboard-only desktop player. Each run fails on any failed
// request, page error, console error, missing engine boot log, a still-visible Godot
// status overlay, a missing canvas, a page whose touch/selection CSS is not applied, or
// a screenshot with nothing drawn (taken once the title has arrived: "[Game] Arrived at
// TITLE"). Then:
//   desktop, mobile-landscape: tap Play where the title logged it ("[Title] Play button
//     at ...", base units) with the mouse / a CDP touch, and require "[Title] Play pressed (1)";
//   mobile-portrait: require "[Game] Rotate overlay shown ... tree paused", check that a
//     touch where Play is and Enter press nothing, turn the phone to landscape (844x390),
//     require "[Game] Rotate overlay hidden ... unpaused", then tap Play and require the press;
//   keyboard: Tab (shows the focus ring) and Enter on the focused Play, require the press.
// Not covered yet: hitting the first bird of level 1 (plan AC 32) needs the play scene of step 2.
// Usage: node tools/smoke_web.mjs [buildDir]   (default: build/web)
// Env:   SMOKE_BOOT_TIMEOUT_MS (default 30000), SMOKE_SETTLE_MS (default 2000),
//        SMOKE_STEP_TIMEOUT_MS (each waited-for log line, default 20000)
// Screenshots (next to buildDir): build/smoke-<run>.png (title) and build/smoke-<run>-play.png
// (after Play), plus build/smoke-mobile-portrait-rotate.png (the overlay) and
// build/smoke-keyboard-focus.png (the focus ring after Tab).
import { join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { launchChrome, serveBuild } from './web_util.mjs';

const repoRoot = resolve(fileURLToPath(import.meta.url), '..', '..');
const buildDir = resolve(process.argv[2] ?? join(repoRoot, 'build', 'web'));
const bootTimeoutMs = Number(process.env.SMOKE_BOOT_TIMEOUT_MS ?? 30000);
const settleMs = Number(process.env.SMOKE_SETTLE_MS ?? 2000);
const STEP_TIMEOUT_MS = Number(process.env.SMOKE_STEP_TIMEOUT_MS ?? 20000);

const PHONE = { deviceScaleFactor: 3, hasTouch: true, isMobile: true };
const LANDSCAPE_PHONE = { width: 844, height: 390 };
const RUNS = [
  { name: 'desktop', context: { viewport: { width: 1280, height: 720 } } },
  { name: 'mobile-landscape', context: { viewport: LANDSCAPE_PHONE, ...PHONE } },
  { name: 'mobile-portrait', portrait: true, context: { viewport: { width: 390, height: 844 }, ...PHONE } },
  { name: 'keyboard', keyboard: true, context: { viewport: { width: 1280, height: 720 } } },
];

// Set by html/head_include in export_presets.cfg so pull-to-refresh, double-tap zoom,
// text selection and long-press menus never fire. -webkit-touch-callout is iOS-only and
// Chrome does not compute it; test_gameplay.gd checks it is in the preset's head_include.
const TOUCH_CSS = { touchAction: 'none', overscrollBehavior: 'none', userSelect: 'none' };
// project.godot base viewport (aspect expand: the visible area grows on one axis from (0, 0)).
const BASE = { width: 960, height: 540 };
// How long a blocked input is given to (wrongly) reach the game.
const BLOCKED_WAIT_MS = 1500;
const PLAY_RECT = /^\[Title\] Play button at \[P: \(([\d.-]+), ([\d.-]+)\), S: \(([\d.-]+), ([\d.-]+)\)\]/;

// Waits until a console line logged at or after index `from` matches `pattern` (a RegExp)
// and returns its match.
async function waitForLog(page, logs, pattern, what, from = 0) {
  const deadline = Date.now() + STEP_TIMEOUT_MS;
  while (Date.now() < deadline) {
    for (let i = logs.length - 1; i >= from; i--) {
      const match = logs[i].match(pattern);
      if (match) return match;
    }
    await page.waitForTimeout(50);
  }
  throw new Error(`timed out after ${STEP_TIMEOUT_MS} ms waiting for ${what} (${pattern})`);
}

// Pointer input for one run: real touches (CDP touch events) on a phone, the mouse on desktop.
async function pointerFor(page, context, run) {
  if (!run.context.hasTouch) return { tap: (p) => page.mouse.click(p.x, p.y) };
  const cdp = await context.newCDPSession(page);
  // id 7: iOS Safari gives touches large identifiers, never 0, and Godot web uses them as the index.
  const touch = (type, points) => cdp.send('Input.dispatchTouchEvent', { type, touchPoints: points });
  return {
    tap: async (p) => {
      await touch('touchStart', [{ x: p.x, y: p.y, id: 7 }]);
      await touch('touchEnd', []);
    },
  };
}

// The centre of the Play button in page coordinates, from the latest logged rect.
// Godot fits the 960x540 base by the smaller ratio and expands the other axis from the
// top-left; the web reports no safe-area insets.
async function playPoint(page, logs) {
  const match = await waitForLog(page, logs, PLAY_RECT, 'the Play button layout');
  const [x, y, w, h] = match.slice(1).map(Number);
  const box = await page.locator('canvas').boundingBox();
  const scale = Math.min(box.width / BASE.width, box.height / BASE.height);
  return { x: box.x + (x + w / 2) * scale, y: box.y + (y + h / 2) * scale };
}

function pressCount(logs) {
  return logs.filter((l) => /^\[Title\] Play pressed/.test(l)).length;
}

// The run's scripted path once the title is up; throws on a missing log line.
async function playPath(page, context, run, logs, shot) {
  if (run.keyboard) {
    // Tab is keyboard navigation, which shows the focus ring (hidden on arrival) before the press.
    await page.keyboard.press('Tab');
    await page.waitForTimeout(300);
    await shot('focus');
    await page.keyboard.press('Enter');
    await waitForLog(page, logs, /^\[Title\] Play pressed \(1\)/, 'Play to be pressed (Tab, Enter on the focused Play)');
    await shot('play');
    return [];
  }
  const pointer = await pointerFor(page, context, run);
  const failures = [];
  if (run.portrait) {
    await waitForLog(page, logs, /^\[Game\] Rotate overlay shown .*tree paused/, 'the rotate overlay (portrait)');
    await shot('rotate');
    await pointer.tap(await playPoint(page, logs));
    await page.keyboard.press('Enter');
    await page.waitForTimeout(BLOCKED_WAIT_MS);
    if (pressCount(logs) !== 0) failures.push('Play was pressed under the rotate overlay');
    const turned = logs.length;
    await page.setViewportSize(LANDSCAPE_PHONE);
    await waitForLog(page, logs, /^\[Game\] Rotate overlay hidden .*unpaused/, 'the rotate overlay to hide (turned to landscape)', turned);
    // The title refits to the landscape safe area and logs Play's new rect.
    await waitForLog(page, logs, PLAY_RECT, 'the Play button layout in landscape', turned);
  } else if (logs.some((l) => /^\[Game\] Rotate overlay shown/.test(l))) {
    failures.push('rotate overlay shown in a landscape viewport');
  }
  await pointer.tap(await playPoint(page, logs));
  await waitForLog(page, logs, /^\[Title\] Play pressed \(1\)/, `Play to be pressed (${run.context.hasTouch ? 'touch' : 'mouse'} tap)`);
  await shot('play');
  return failures;
}

async function smoke(browser, url, run) {
  const failures = [];
  const logs = [];
  const context = await browser.newContext(run.context);
  try {
    const page = await context.newPage();
    page.on('pageerror', (e) => failures.push(`page error: ${e.message}`));
    page.on('requestfailed', (r) => failures.push(`request failed: ${r.url()} ${r.failure()?.errorText}`));
    page.on('response', (r) => { if (r.status() >= 400) failures.push(`HTTP ${r.status()}: ${r.url()}`); });
    page.on('console', (m) => {
      // SwiftShader emits GPU performance warnings; only real errors fail the test.
      if (m.type() === 'error') failures.push(`console error: ${m.text()}`);
      logs.push(m.text());
    });
    const shot = async (tag) => {
      const path = join(buildDir, '..', `smoke-${run.name}-${tag}.png`);
      await page.screenshot({ path });
      console.log(`[${run.name}] screenshot: ${path}`);
    };
    // Settled to a value up front so it can never become an unhandled rejection if goto throws.
    const booted = page.waitForEvent('console', {
      predicate: (m) => m.text().startsWith('Godot Engine v'),
      timeout: bootTimeoutMs,
    }).then(() => null, (err) => err);
    await page.goto(url, { timeout: bootTimeoutMs });
    const bootError = await booted;
    if (bootError !== null) throw new Error(`engine did not boot: ${bootError.message.split('\n')[0]}`);
    await waitForLog(page, logs, /^\[Game\] Arrived at TITLE/, 'the title (the main scene)');
    await page.waitForTimeout(settleMs);
    const overlayVisible = await page.evaluate(() => {
      const status = document.getElementById('status');
      return status !== null && getComputedStyle(status).display !== 'none' && getComputedStyle(status).visibility !== 'hidden';
    });
    if (overlayVisible) failures.push('Godot status overlay still visible (engine failed to start)');
    if ((await page.locator('canvas').count()) === 0) failures.push('no canvas element');
    const css = await page.evaluate((expected) => {
      const wrong = [];
      for (const selector of ['html', 'body', 'canvas']) {
        const style = getComputedStyle(document.querySelector(selector));
        for (const [prop, value] of Object.entries(expected)) {
          if (style[prop] !== value) wrong.push(`${selector} ${prop}=${style[prop]}`);
        }
      }
      return wrong;
    }, TOUCH_CSS);
    for (const w of css) failures.push(`touch CSS not applied: ${w}`);
    const screenshotPath = join(buildDir, '..', `smoke-${run.name}.png`);
    const png = await page.screenshot({ path: screenshotPath });
    console.log(`[${run.name}] screenshot: ${screenshotPath}`);
    // A booted engine that draws nothing leaves one flat colour; count distinct colours in the screenshot.
    const distinctColors = await page.evaluate(async (b64) => {
      const img = new Image();
      img.src = `data:image/png;base64,${b64}`;
      await img.decode();
      const canvas = document.createElement('canvas');
      canvas.width = img.width;
      canvas.height = img.height;
      const ctx = canvas.getContext('2d');
      ctx.drawImage(img, 0, 0);
      const data = ctx.getImageData(0, 0, canvas.width, canvas.height).data;
      const colors = new Set();
      for (let i = 0; i < data.length && colors.size < 16; i += 4) {
        colors.add((data[i] << 16) | (data[i + 1] << 8) | data[i + 2]);
      }
      return colors.size;
    }, png.toString('base64'));
    if (distinctColors < 2) failures.push('screenshot is a single flat colour (nothing rendered)');
    if (failures.length === 0) failures.push(...await playPath(page, context, run, logs, shot));
    for (const line of logs.filter((l) => /^\[(Game|Title)\]/.test(l))) console.log(`[${run.name}] ${line}`);
  } catch (err) {
    failures.push(`smoke test aborted: ${err.message}`);
    // The game's last log lines show where the run got stuck.
    for (const line of logs.slice(-12)) failures.push(`  log: ${line}`);
  } finally {
    await context.close();
  }
  return failures.map((f) => `[${run.name}] ${f}`);
}

const failures = [];
let browser;
let server;
try {
  const served = await serveBuild(buildDir);
  server = served.server;
  browser = await launchChrome();
  for (const run of RUNS) failures.push(...await smoke(browser, served.url, run));
} catch (err) {
  failures.push(`smoke test aborted: ${err.message}`);
} finally {
  await browser?.close();
  server?.close();
}

if (failures.length > 0) {
  for (const f of failures) console.error(`FAIL ${f}`);
  process.exit(1);
}
console.log(`PASS ${buildDir} (${RUNS.map((r) => r.name).join(', ')})`);
