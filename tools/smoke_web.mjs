// Smoke test for the Godot web export: serves the build locally and loads it in
// headless Chrome four times: as a desktop browser (1280x720, mouse), as a phone held
// in landscape (844x390 at 3x, touch, mobile), as a phone held upright (390x844 at 3x,
// touch, mobile) and as a keyboard-only desktop player. Each run fails on any failed
// request, page error, console error, missing engine boot log, a still-visible Godot
// status overlay, a missing canvas, a page whose touch/selection CSS is not applied, or
// a screenshot with nothing drawn (taken once the title has arrived: "[Game] Arrived at
// TITLE"). Then:
//   desktop, mobile-landscape: tap Play where the title logged it ("[Title] Play button
//     at ...", base units) with the mouse / a CDP touch, require "[Title] Play pressed (1)"
//     and the play scene, then shoot the run's first goose where it logs itself ("[Bird]
//     goose #1 at (x, y) ... age a ahead (x1, y1) ...", base units, every 0.25 s, with the
//     positions its flight reaches every 0.1 s ahead), at the point of that path it reaches
//     when the shot lands: the time since the line arrived plus the input latency (first
//     guessed, then measured from each logged shot's game time), and require "[Play] Hit
//     goose #1" (up to HIT_ATTEMPTS attempts; after a miss a phone fires a salvo of SALVO
//     fingers along the path around the measured latency); then a
//     visibilitychange with document.hidden true must log "[Play] Paused (page hidden)";
//   mobile-portrait: require "[Game] Rotate overlay shown ... tree paused", check that a
//     touch where Play is and Enter press nothing, turn the phone to landscape (844x390),
//     require "[Game] Rotate overlay hidden ... unpaused", then tap Play and require the press;
//   keyboard: Tab (shows the focus ring) and Enter on the focused Play, require the press and
//     the play scene; Escape opens the pause menu, Enter on the focused Resume resumes,
//     Escape opens it again, Down Down Enter quits to the title.
// Usage: node tools/smoke_web.mjs [buildDir]   (default: build/web)
// Env:   SMOKE_BOOT_TIMEOUT_MS (default 30000), SMOKE_SETTLE_MS (default 2000),
//        SMOKE_STEP_TIMEOUT_MS (each waited-for log line, default 20000)
// Screenshots (next to buildDir): build/smoke-<run>.png (title) and build/smoke-<run>-play.png
// (after the goose is hit; the run's start for keyboard; the title for portrait), plus
// build/smoke-mobile-portrait-rotate.png (the overlay), build/smoke-keyboard-focus.png (the
// focus ring after Tab) and build/smoke-keyboard-pause.png (the pause menu).
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
const FIRST_GOOSE = /^\[Bird\] goose #1 at \(([\d.-]+), ([\d.-]+)\) v \([\d.-]+, [\d.-]+\) age ([\d.]+) ahead (.*)$/;
const FIRST_SPAWN = /^\[Play\] Spawned goose #1 \(.*\) at t ([\d.-]+)/;
// Shot outcomes the play scene logs for a shot, with the wave time it was handled at.
const SHOT_RESULT = /^\[Play\] (Hit \w+ #\d+|Miss|Shot refused).* at t ([\d.-]+)/;
// Seconds between two "ahead" points of a [Bird] line (Bird.TRACK_AHEAD_STEP).
const AHEAD_STEP_S = 0.1;
// Points ahead per [Bird] line (Bird.TRACK_AHEAD_STEPS).
const AHEAD_STEPS = 20;
// After a miss, a phone shoots a salvo of SALVO fingers at once along the goose's path,
// SALVO_SPREAD_S apart around the measured latency: a slow runner (SwiftShader at 3x)
// handles input a whole slow frame late, which a single aimed touch cannot predict.
const SALVO = 5;
const SALVO_SPREAD_S = 0.15;
// The grass line (Play.GRASS_Y): the goose is aimed at once its centre is well above it.
const AIM_ABOVE_Y = 400;
// First guess of the seconds from a click or touch to the frame that handles it; each
// shot then measures it.
const AIM_LATENCY_S = 0.1;
const HIT_ATTEMPTS = 5;

// Waits until a console line logged at or after index `from` matches `pattern` (a RegExp)
// and returns its match (with `index`: the line's index in logs).
async function waitForLog(page, logs, pattern, what, from = 0) {
  const deadline = Date.now() + STEP_TIMEOUT_MS;
  while (Date.now() < deadline) {
    for (let i = logs.length - 1; i >= from; i--) {
      const match = logs[i].match(pattern);
      if (match) return Object.assign(match, { index: i });
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
    // Several fingers pressing at once (ids 7, 8, ...): one shot each, in one frame.
    salvo: async (points) => {
      await touch('touchStart', points.map((p, i) => ({ x: p.x, y: p.y, id: 7 + i })));
      await touch('touchEnd', []);
    },
  };
}

// A base-unit point in page coordinates. Godot fits the 960x540 base by the smaller ratio
// and expands the other axis from the top-left; the web reports no safe-area insets.
async function pagePoint(page, x, y) {
  return toPage(await page.locator('canvas').boundingBox(), x, y);
}

// pagePoint for a known canvas bounding box (no round trip to the page).
function toPage(box, x, y) {
  const scale = Math.min(box.width / BASE.width, box.height / BASE.height);
  return { x: box.x + x * scale, y: box.y + y * scale };
}

// The centre of the Play button in page coordinates, from the latest logged rect.
async function playPoint(page, logs) {
  const match = await waitForLog(page, logs, PLAY_RECT, 'the Play button layout');
  const [x, y, w, h] = match.slice(1).map(Number);
  return pagePoint(page, x + w / 2, y + h / 2);
}

// The point of a logged path (`points[k]` at k x AHEAD_STEP_S seconds) at `lead` seconds.
function pathAt(points, lead) {
  const k = Math.min(Math.floor(lead / AHEAD_STEP_S), points.length - 2);
  const f = lead / AHEAD_STEP_S - k;
  return { x: points[k].x + (points[k + 1].x - points[k].x) * f, y: points[k].y + (points[k + 1].y - points[k].y) * f };
}

// Shoots the run's first goose at the point of its logged path it reaches when the shot
// lands; retries on a miss, measuring the input latency from each shot's logged game time.
// Throws unless it is hit.
async function shootFirstGoose(page, logs, logTimes, pointer, from) {
  const spawned = Number((await waitForLog(page, logs, FIRST_SPAWN, 'the first goose to spawn', from))[1]);
  const horizon = AHEAD_STEPS * AHEAD_STEP_S;
  // Measured once: a round trip to the page per shot would add to the input latency.
  const box = await page.locator('canvas').boundingBox();
  const outcomes = [];
  let latency = AIM_LATENCY_S;
  for (let attempt = 1; attempt <= HIT_ATTEMPTS; attempt++) {
    let track;
    let lead;
    // The latest line of the goose above the grass whose path still reaches the shot.
    const skipped = [];
    for (;;) {
      track = await waitForLog(page, logs, FIRST_GOOSE, `the first goose to fly above the grass (skipped: ${skipped.slice(-6).join(', ')})`, from);
      from = track.index + 1;
      lead = (Date.now() - logTimes[track.index]) / 1000 + latency;
      if (Number(track[2]) <= AIM_ABOVE_Y && lead + SALVO_SPREAD_S * SALVO / 2 < horizon) break;
      skipped.push(`age ${track[3]} y ${track[2]} lead ${lead.toFixed(2)}`);
    }
    const points = [{ x: Number(track[1]), y: Number(track[2]) }].concat(
      [...track[4].matchAll(/\(([\d.-]+), ([\d.-]+)\)/g)].map((m) => ({ x: Number(m[1]), y: Number(m[2]) })));
    const shotFrom = logs.length;
    const salvo = attempt > 1 && pointer.salvo !== undefined;
    const leads = salvo ? Array.from({ length: SALVO }, (_, i) => Math.max(0, lead + (i - (SALVO - 1) / 2) * SALVO_SPREAD_S)) : [lead];
    const aims = leads.map((each) => {
      const at = pathAt(points, each);
      return toPage(box, at.x, at.y);
    });
    const sent = (Date.now() - logTimes[track.index]) / 1000;
    await (salvo ? pointer.salvo(aims) : pointer.tap(aims[0]));
    const outcome = await waitForLog(page, logs, SHOT_RESULT, 'the shot to be logged', shotFrom);
    // Every shot of a salvo is handled in one frame; any of them may be the hit.
    await page.waitForTimeout(salvo ? 500 : 0);
    const hit = logs.slice(shotFrom).some((l) => /^\[Play\] Hit goose #1 /.test(l));
    outcomes.push(`${hit ? 'Hit goose #1' : outcome[1]} (${salvo ? `salvo of ${SALVO}, ` : ''}lead ${lead.toFixed(2)} s)`);
    if (hit) return outcomes;
    // The goose's age when the shot was handled, against its age when the tap was sent.
    latency = Math.max(0, Number(outcome[2]) - spawned - (Number(track[3]) + sent));
  }
  throw new Error(`the first goose was not hit in ${HIT_ATTEMPTS} shots: ${outcomes.join(', ')}`);
}

function pressCount(logs) {
  return logs.filter((l) => /^\[Title\] Play pressed/.test(l)).length;
}

// The run's scripted path once the title is up; throws on a missing log line.
async function playPath(page, context, run, logs, logTimes, shot) {
  if (run.keyboard) {
    // Tab is keyboard navigation, which shows the focus ring (hidden on arrival) before the press.
    await page.keyboard.press('Tab');
    await page.waitForTimeout(300);
    await shot('focus');
    await page.keyboard.press('Enter');
    await waitForLog(page, logs, /^\[Title\] Play pressed \(1\)/, 'Play to be pressed (Tab, Enter on the focused Play)');
    await waitForLog(page, logs, /^\[Game\] Arrived at PLAY/, 'the play scene');
    await shot('play');
    let from = logs.length;
    await page.keyboard.press('Escape');
    await waitForLog(page, logs, /^\[Play\] Paused \(Escape\)/, 'Escape to open the pause menu', from);
    await page.waitForTimeout(300);
    await shot('pause');
    from = logs.length;
    await page.keyboard.press('Enter');
    await waitForLog(page, logs, /^\[Play\] Resumed/, 'Enter on the focused Resume to resume', from);
    from = logs.length;
    await page.keyboard.press('Escape');
    await waitForLog(page, logs, /^\[Play\] Paused \(Escape\)/, 'Escape to open the pause menu again', from);
    from = logs.length;
    for (const key of ['ArrowDown', 'ArrowDown', 'Enter']) await page.keyboard.press(key);
    await waitForLog(page, logs, /^\[Play\] Left the run \(Quit to title\)/, 'Down, Down, Enter to press Quit to title', from);
    await waitForLog(page, logs, /^\[Game\] Arrived at TITLE/, 'the title after quitting', from);
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
  if (run.portrait) {
    await shot('play');
    return failures;
  }
  const arrived = await waitForLog(page, logs, /^\[Game\] Arrived at PLAY/, 'the play scene');
  const outcomes = await shootFirstGoose(page, logs, logTimes, pointer, arrived.index + 1);
  console.log(`[${run.name}] shots at the first goose: ${outcomes.join(', ')}`);
  await shot('play');
  // The page becoming hidden (another tab, the phone's home button) pauses the run.
  const hiddenFrom = logs.length;
  await page.evaluate(() => {
    Object.defineProperty(document, 'hidden', { value: true, configurable: true });
    document.dispatchEvent(new Event('visibilitychange'));
  });
  await waitForLog(page, logs, /^\[Play\] Paused \(page hidden\)/, 'the hidden page to pause the run', hiddenFrom);
  return failures;
}

async function smoke(browser, url, run) {
  const failures = [];
  const logs = [];
  // When each console line arrived (Date.now()), for aiming at a logged position.
  const logTimes = [];
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
      logTimes.push(Date.now());
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
    if (failures.length === 0) failures.push(...await playPath(page, context, run, logs, logTimes, shot));
    for (const line of logs.filter((l) => /^\[(Game|Title|Play|Results)\]/.test(l))) console.log(`[${run.name}] ${line}`);
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
