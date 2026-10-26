// Smoke test for the Godot web export: serves the build locally and loads it in
// headless Chrome four times: as a desktop browser (1280x720, mouse), as a phone held
// in landscape (844x390 at 3x, touch, mobile), as a phone held upright (390x844 at 3x,
// touch, mobile) and as a keyboard-only desktop player. Each run fails on any failed
// request, page error, console error, missing engine boot log, a still-visible Godot
// status overlay, a missing canvas, a page whose touch/selection CSS is not applied, or
// a screenshot with nothing drawn (taken once the title has arrived: "[Game] Arrived at
// TITLE"). Then:
//   desktop, mobile-landscape: reach campaign level dawn_1 through the menus with the mouse /
//     CDP touches, each tapped where its screen logged it (base units): Campaign ("[Title]
//     Campaign button at ...", require "[Title] Campaign pressed (1)" and the chapter select),
//     dawn ("[ChapterSelect] Chapter dawn at ...", require its press and the level select),
//     level 1 ("[LevelSelect] Level dawn_1 at ...", require its press and the play scene with
//     "[Play] Run start: level dawn_1"), then shoot the level's first goose where it logs itself ("[Bird]
//     goose #1 at (x, y) ... age a ahead (x1, y1) ...", base units, every 0.25 s, with the
//     positions its flight reaches every 0.1 s ahead), at the point of that path it reaches
//     when the shot lands: the time since the line arrived plus the input latency (first
//     guessed, then measured from each logged shot's game time), and require "[Play] Hit
//     goose #1" (HIT_ATTEMPTS real attempts within wave 1's logged shell pool: after a miss a
//     phone fires a salvo of up to SALVO fingers along the path around the measured latency,
//     keeping one shell for each attempt still to come; a refused shot fails at once); then
//     require a rival line ("[Play] Heckle (<category>) #n: ..." or "[Play] Aim cue on ...":
//     a miss, a combo, a steal or at the latest wave 1's end always brings one); then a
//     visibilitychange with document.hidden true must log "[Play] Paused (page hidden)";
//     then the page is reloaded to the title, Time Attack is tapped where it logs itself
//     ("[Title] Time Attack button at ..."), requiring its press, "[Play] Run start: mode
//     time_attack" and the play scene, and its first goose is shot as above; reloaded once
//     more, Endless is tapped, requiring its press, "[Play] Run start: mode endless" and the
//     play scene;
//   desktop only, then the backdrop tour: a save that has finished every level of the first
//     three chapters is written to the page's IndexedDB (where Godot's user:// lives) and the
//     page reloaded, requiring "[Game] Loaded save ... 18 levels finished"; then level 1 of
//     each chapter (dawn_1, noon_1, sunset_1, night_1), Endless and Time Attack are started
//     by mouse (Campaign, the chapter, level 1 where they log themselves; the mode buttons),
//     each requiring its run start and "[Play] Backdrop <id>, weather <weather> from wave 1"
//     (the chapter's or the mode's first stage); a screenshot is taken once the first bird
//     has been in the air for BACKDROP_SHOT_DELAY_MS, and Escape, Down, Down, Enter quits
//     to the title;
//   mobile-portrait: require "[Game] Rotate overlay shown ... tree paused", check that a
//     touch where Campaign is and Enter press nothing, turn the phone to landscape (844x390),
//     require "[Game] Rotate overlay hidden ... unpaused", then tap Campaign and require the press;
//   keyboard: Tab, Tab, Tab (through Endless and Time Attack back to Campaign, showing the
//     focus ring) and Enter on the focused Campaign, Enter on the focused dawn chapter, Enter
//     on the focused level 1, require each press and the play scene running dawn_1; Escape
//     opens the pause menu, Enter on the focused Resume resumes, Escape opens it again, Down
//     Down Enter quits to the title; Tab, Tab, Enter starts Time Attack (its press, its run
//     start, the play scene), Escape and Down Down Enter quit it to the title; Tab, Enter
//     starts Endless (its press, its run start, the play scene).
// Usage: node tools/smoke_web.mjs [buildDir]   (default: build/web)
// Env:   SMOKE_BOOT_TIMEOUT_MS (default 30000), SMOKE_SETTLE_MS (default 2000),
//        SMOKE_STEP_TIMEOUT_MS (each waited-for log line, default 20000)
// Screenshots (next to buildDir): build/smoke-<run>.png (title) and build/smoke-<run>-play.png
// (after the goose is hit; the run's start for keyboard; the title for portrait),
// build/smoke-<run>-time-attack.png (after Time Attack's goose is hit; its start for
// keyboard), plus
// build/smoke-mobile-portrait-rotate.png (the overlay), build/smoke-keyboard-focus.png (the
// focus ring after Tab), build/smoke-keyboard-pause.png (the pause menu) and the desktop
// backdrop tour's build/smoke-desktop-backdrop-<dawn_1|noon_1|sunset_1|night_1|endless|time_attack>.png.
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
  { name: 'desktop', backdrops: true, context: { viewport: { width: 1280, height: 720 } } },
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
// Where each screen logs the button the path taps (base units).
const CAMPAIGN_RECT = /^\[Title\] Campaign button at \[P: \(([\d.-]+), ([\d.-]+)\), S: \(([\d.-]+), ([\d.-]+)\)\]/;
const ENDLESS_RECT = /^\[Title\] Endless button at \[P: \(([\d.-]+), ([\d.-]+)\), S: \(([\d.-]+), ([\d.-]+)\)\]/;
const TIME_ATTACK_RECT = /^\[Title\] Time Attack button at \[P: \(([\d.-]+), ([\d.-]+)\), S: \(([\d.-]+), ([\d.-]+)\)\]/;
const DAWN_RECT = /^\[ChapterSelect\] Chapter dawn at \[P: \(([\d.-]+), ([\d.-]+)\), S: \(([\d.-]+), ([\d.-]+)\)\]/;
const LEVEL_RECT = /^\[LevelSelect\] Level dawn_1 at \[P: \(([\d.-]+), ([\d.-]+)\), S: \(([\d.-]+), ([\d.-]+)\)\]/;
// The campaign level the path plays, logged by the play scene before it arrives.
const LEVEL_RUN = /^\[Play\] Run start: level dawn_1 /;
// The mode runs the title starts, logged by the play scene before it arrives.
const TIME_ATTACK_RUN = /^\[Play\] Run start: mode time_attack, seed \d+ \(time limit 60\.00 s, no escape limit, /;
const ENDLESS_RUN = /^\[Play\] Run start: mode endless, seed \d+ \(escape limit /;
const FIRST_GOOSE = /^\[Bird\] goose #1 at \(([\d.-]+), ([\d.-]+)\) v \([\d.-]+, [\d.-]+\) age ([\d.]+) ahead (.*)$/;
const FIRST_SPAWN = /^\[Play\] Spawned goose #1 \(.*\) at t ([\d.-]+)/;
// The first wave's shell pool (logged by the play scene before it arrives).
const FIRST_WAVE = /^\[Play\] Wave 1 start: \d+ birds \(.*\), (\d+) shells/;
// Shot outcomes the play scene logs for a shot, with the wave time it was handled at.
const SHOT_RESULT = /^\[Play\] (Hit \w+ #\d+|Miss|Shot refused).* at t ([\d.-]+)/;
// The rival speaking or aiming (Play logs every heckle shown and every aim cue started).
const RIVAL_LINE = /^\[Play\] (Heckle \(\w+\) #\d+: |Aim cue on )/;
// Seconds between two "ahead" points of a [Bird] line (Bird.TRACK_AHEAD_STEP).
const AHEAD_STEP_S = 0.1;
// Points ahead per [Bird] line (Bird.TRACK_AHEAD_STEPS).
const AHEAD_STEPS = 20;
// After a miss, a phone shoots a salvo of up to SALVO fingers at once along the goose's
// path, SALVO_SPREAD_S apart around the measured latency: a slow runner (SwiftShader at 3x)
// handles input a whole slow frame late, which a single aimed touch cannot predict. Each
// finger uses a shell, so a salvo keeps one shell of wave 1's pool for every attempt
// still to come: all HIT_ATTEMPTS attempts are real shots.
const SALVO = 5;
const SALVO_SPREAD_S = 0.15;
// The grass line (Play.GRASS_Y): the goose is aimed at once its centre is well above it.
const AIM_ABOVE_Y = 400;
// First guess of the seconds from a click or touch to the frame that handles it; each
// shot then measures it.
const AIM_LATENCY_S = 0.1;
const HIT_ATTEMPTS = 5;
// The backdrop tour: each run the desktop screenshots, with the backdrop and weather it must
// start on (data/chapters.json, data/modes.json), and how long after its first spawn the
// screenshot waits (birds in the air).
const BACKDROP_TOUR = [
  { shot: 'dawn_1', chapter: 'dawn', backdrop: 'dawn', weather: 'mist' },
  { shot: 'noon_1', chapter: 'noon', backdrop: 'noon', weather: 'wind' },
  { shot: 'sunset_1', chapter: 'sunset', backdrop: 'sunset', weather: 'rain' },
  { shot: 'night_1', chapter: 'night', backdrop: 'night', weather: 'snow' },
  { shot: 'endless', mode: 'Endless', backdrop: 'dawn', weather: 'mist' },
  { shot: 'time_attack', mode: 'Time Attack', backdrop: 'noon', weather: 'wind' },
];
const BACKDROP_SHOT_DELAY_MS = 2500;
// A version 3 save (GameState.SAVE_VERSION) with every level of the first three chapters
// finished, so each chapter's level 1 is open; Godot's web user:// is Emscripten IDBFS in
// IndexedDB database /userfs, store FILE_DATA, key = the file's path, which the game logs
// (SAVE_FILE) along with its directories, each stored as an entry of its own.
const SAVE_FILE = /^\[Game\] Browser storage \(IndexedDB\) is available for user:\/\/save\.json \((\/userfs\/.+)\)$/;
const TOUR_LEVELS = ['dawn', 'noon', 'sunset'].flatMap((c) => [1, 2, 3, 4, 5, 6].map((i) => `${c}_${i}`));
const TOUR_SAVE = JSON.stringify({
  version: 3,
  bests: { endless: 0, time_attack: 0 },
  levels: Object.fromEntries(TOUR_LEVELS.map((id) => [id, { stars: 1, score: 1000 }])),
  settings: { music: 70, sfx: 80, music_muted: false, sfx_muted: false },
});

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

// The centre of a button in page coordinates, from the latest rect matching `pattern`
// logged at or after index `from`.
async function buttonPoint(page, logs, pattern, what, from = 0) {
  const match = await waitForLog(page, logs, pattern, what, from);
  const [x, y, w, h] = match.slice(1).map(Number);
  return pagePoint(page, x + w / 2, y + h / 2);
}

// Taps Campaign, the dawn chapter and level 1 where their screens log them, requiring each
// press and screen; returns the "[Game] Arrived at PLAY" match.
async function reachFirstLevel(page, logs, pointer, how) {
  let from = logs.length;
  await pointer.tap(await buttonPoint(page, logs, CAMPAIGN_RECT, 'the Campaign button layout'));
  await waitForLog(page, logs, /^\[Title\] Campaign pressed \(1\)/, `Campaign to be pressed (${how} tap)`, from);
  await waitForLog(page, logs, /^\[Game\] Arrived at CHAPTER_SELECT/, 'the chapter select', from);
  from = logs.length;
  await pointer.tap(await buttonPoint(page, logs, DAWN_RECT, 'the dawn chapter button layout'));
  await waitForLog(page, logs, /^\[ChapterSelect\] Chapter dawn pressed/, `the dawn chapter to be pressed (${how} tap)`, from);
  await waitForLog(page, logs, /^\[Game\] Arrived at LEVEL_SELECT/, 'the level select', from);
  from = logs.length;
  await pointer.tap(await buttonPoint(page, logs, LEVEL_RECT, 'the level 1 button layout'));
  await waitForLog(page, logs, /^\[LevelSelect\] Level dawn_1 pressed/, `level 1 to be pressed (${how} tap)`, from);
  await waitForLog(page, logs, LEVEL_RUN, 'level dawn_1 to start', from);
  return waitForLog(page, logs, /^\[Game\] Arrived at PLAY/, 'the play scene', from);
}

// The point of a logged path (`points[k]` at k x AHEAD_STEP_S seconds) at `lead` seconds.
function pathAt(points, lead) {
  const k = Math.min(Math.floor(lead / AHEAD_STEP_S), points.length - 2);
  const f = lead / AHEAD_STEP_S - k;
  return { x: points[k].x + (points[k + 1].x - points[k].x) * f, y: points[k].y + (points[k + 1].y - points[k].y) * f };
}

// Shoots the run's first goose at the point of its logged path it reaches when the shot
// lands; retries on a miss, measuring the input latency from each shot's logged game time.
// Throws unless it is hit, and at once on a refused shot (the shell budget is wrong).
async function shootFirstGoose(page, logs, logTimes, pointer, from) {
  // Logged in the play scene's _ready, before "[Game] Arrived at PLAY".
  const shells = Number((await waitForLog(page, logs, FIRST_WAVE, 'the first wave to start'))[1]);
  if (shells < HIT_ATTEMPTS) throw new Error(`wave 1 has ${shells} shells, fewer than the ${HIT_ATTEMPTS} attempts at the first goose`);
  let left = shells;
  const spawned = Number((await waitForLog(page, logs, FIRST_SPAWN, 'the first goose to spawn', from))[1]);
  const horizon = AHEAD_STEPS * AHEAD_STEP_S;
  // Measured once: a round trip to the page per shot would add to the input latency.
  const box = await page.locator('canvas').boundingBox();
  const outcomes = [];
  let latency = AIM_LATENCY_S;
  for (let attempt = 1; attempt <= HIT_ATTEMPTS; attempt++) {
    // One shell stays for every later attempt.
    const fingers = attempt > 1 && pointer.salvo !== undefined ? Math.max(1, Math.min(SALVO, left - (HIT_ATTEMPTS - attempt))) : 1;
    let track;
    let lead;
    // The latest line of the goose above the grass whose path still reaches the shot.
    const skipped = [];
    for (;;) {
      track = await waitForLog(page, logs, FIRST_GOOSE, `the first goose to fly above the grass (skipped: ${skipped.slice(-6).join(', ')})`, from);
      from = track.index + 1;
      lead = (Date.now() - logTimes[track.index]) / 1000 + latency;
      if (Number(track[2]) <= AIM_ABOVE_Y && lead + SALVO_SPREAD_S * fingers / 2 < horizon) break;
      skipped.push(`age ${track[3]} y ${track[2]} lead ${lead.toFixed(2)}`);
    }
    const points = [{ x: Number(track[1]), y: Number(track[2]) }].concat(
      [...track[4].matchAll(/\(([\d.-]+), ([\d.-]+)\)/g)].map((m) => ({ x: Number(m[1]), y: Number(m[2]) })));
    const shotFrom = logs.length;
    const salvo = fingers > 1;
    const leads = Array.from({ length: fingers }, (_, i) => Math.max(0, lead + (i - (fingers - 1) / 2) * SALVO_SPREAD_S));
    const aims = leads.map((each) => {
      const at = pathAt(points, each);
      return toPage(box, at.x, at.y);
    });
    const sent = (Date.now() - logTimes[track.index]) / 1000;
    await (salvo ? pointer.salvo(aims) : pointer.tap(aims[0]));
    left -= fingers;
    const outcome = await waitForLog(page, logs, SHOT_RESULT, 'the shot to be logged', shotFrom);
    // Every shot of a salvo is handled in one frame; any of them may be the hit.
    await page.waitForTimeout(salvo ? 500 : 0);
    const shotLogs = logs.slice(shotFrom);
    const hit = shotLogs.some((l) => /^\[Play\] Hit goose #1 /.test(l));
    outcomes.push(`${hit ? 'Hit goose #1' : outcome[1]} (${salvo ? `salvo of ${fingers}, ` : ''}lead ${lead.toFixed(2)} s)`);
    if (hit) return outcomes;
    const refused = shotLogs.find((l) => /^\[Play\] Shot refused/.test(l));
    if (refused !== undefined) {
      throw new Error(`attempt ${attempt} of ${HIT_ATTEMPTS} at the first goose was refused: wave 1's ${shells} shells ran out (${outcomes.join(', ')}; "${refused}")`);
    }
    // The goose's age when the shot was handled, against its age when the tap was sent.
    latency = Math.max(0, Number(outcome[2]) - spawned - (Number(track[3]) + sent));
  }
  throw new Error(`the first goose was not hit in ${HIT_ATTEMPTS} attempts (${shells - left} of wave 1's ${shells} shells): ${outcomes.join(', ')}`);
}

function pressCount(logs) {
  return logs.filter((l) => /^\[Title\] (Campaign|Endless|Time Attack) pressed/.test(l)).length;
}

// Reloads the page and waits for the title (the main scene) to arrive again.
async function reloadToTitle(page, logs) {
  const from = logs.length;
  await page.reload({ timeout: bootTimeoutMs });
  await waitForLog(page, logs, /^\[Game\] Arrived at TITLE/, 'the title after a reload', from);
  await page.waitForTimeout(settleMs);
}

// Taps a mode's title button where the title logs it (`rect`) and requires its press
// ("[Title] <label> pressed (1)"), its run start (`run`) and the play scene; returns the
// "[Game] Arrived at PLAY" match.
async function startMode(page, logs, pointer, rect, label, run, how) {
  const from = logs.length;
  await pointer.tap(await buttonPoint(page, logs, rect, `the ${label} button layout`));
  await waitForLog(page, logs, new RegExp(`^\\[Title\\] ${label} pressed \\(1\\)`), `${label} to be pressed (${how} tap)`, from);
  await waitForLog(page, logs, run, `${label} to start`, from);
  return waitForLog(page, logs, /^\[Game\] Arrived at PLAY/, `the play scene (${label})`, from);
}

// Writes TOUR_SAVE as user://save.json into the page's IndexedDB as Godot's IDBFS stores
// files and directories ({timestamp: Date, mode[, contents]}), then reloads and requires it
// loaded.
async function plantTourSave(page, logs) {
  const file = (await waitForLog(page, logs, SAVE_FILE, 'the save file\'s path in browser storage'))[1];
  const error = await page.evaluate(([path, text]) => new Promise((resolveWrite) => {
    const request = indexedDB.open('/userfs');
    request.onerror = () => resolveWrite(`cannot open IndexedDB /userfs: ${request.error}`);
    request.onsuccess = () => {
      const db = request.result;
      try {
        const write = db.transaction(['FILE_DATA'], 'readwrite');
        const store = write.objectStore('FILE_DATA');
        // Every directory between the mount (/userfs) and the file (mode 040777), then the file (0100644).
        const parts = path.split('/');
        for (let i = 3; i < parts.length; i++) store.put({ timestamp: new Date(), mode: 16895 }, parts.slice(0, i).join('/'));
        store.put({ timestamp: new Date(), mode: 33188, contents: new TextEncoder().encode(text) }, path);
        write.oncomplete = () => { db.close(); resolveWrite(''); };
        write.onerror = () => { db.close(); resolveWrite(`cannot write the save: ${write.error}`); };
      } catch (e) {
        db.close();
        resolveWrite(`cannot write the save: ${e}`);
      }
    };
  }), [file, TOUR_SAVE]);
  if (error !== '') throw new Error(error);
  const from = logs.length;
  await reloadToTitle(page, logs);
  await waitForLog(page, logs, new RegExp(`^\\[Game\\] Loaded save from user://save\\.json: version 3, .*, ${TOUR_LEVELS.length} levels finished`), 'the planted save to load', from);
}

// Starts each BACKDROP_TOUR run from the title, requires its backdrop and weather, takes
// its screenshot with birds in the air and quits to the title.
async function backdropTour(page, logs, pointer, shot) {
  await plantTourSave(page, logs);
  for (const stop of BACKDROP_TOUR) {
    let from = logs.length;
    if (stop.mode !== undefined) {
      const rect = stop.mode === 'Endless' ? ENDLESS_RECT : TIME_ATTACK_RECT;
      await startMode(page, logs, pointer, rect, stop.mode, stop.mode === 'Endless' ? ENDLESS_RUN : TIME_ATTACK_RUN, 'mouse');
    } else {
      // The title logged its layout on arrival: the latest rect is this title's.
      await pointer.tap(await buttonPoint(page, logs, CAMPAIGN_RECT, 'the Campaign button layout'));
      await waitForLog(page, logs, /^\[Game\] Arrived at CHAPTER_SELECT/, 'the chapter select', from);
      const chapterRect = new RegExp(`^\\[ChapterSelect\\] Chapter ${stop.chapter} at \\[P: \\(([\\d.-]+), ([\\d.-]+)\\), S: \\(([\\d.-]+), ([\\d.-]+)\\)\\] \\(open`);
      await pointer.tap(await buttonPoint(page, logs, chapterRect, `the ${stop.chapter} chapter button (open)`, from));
      await waitForLog(page, logs, /^\[Game\] Arrived at LEVEL_SELECT/, `the ${stop.chapter} level select`, from);
      const levelRect = new RegExp(`^\\[LevelSelect\\] Level ${stop.shot} at \\[P: \\(([\\d.-]+), ([\\d.-]+)\\), S: \\(([\\d.-]+), ([\\d.-]+)\\)\\] \\(open`);
      const levelFrom = logs.length;
      await pointer.tap(await buttonPoint(page, logs, levelRect, `the ${stop.shot} button (open)`, from));
      await waitForLog(page, logs, new RegExp(`^\\[Play\\] Run start: level ${stop.shot} `), `${stop.shot} to start`, levelFrom);
      await waitForLog(page, logs, /^\[Game\] Arrived at PLAY/, `the play scene (${stop.shot})`, levelFrom);
    }
    await waitForLog(page, logs, new RegExp(`^\\[Play\\] Backdrop ${stop.backdrop}, weather ${stop.weather} from wave 1$`), `the ${stop.backdrop} backdrop with ${stop.weather}`, from);
    await waitForLog(page, logs, /^\[Play\] Spawned /, 'the first bird to spawn', from);
    await page.waitForTimeout(BACKDROP_SHOT_DELAY_MS);
    await shot(`backdrop-${stop.shot}`);
    from = logs.length;
    await page.keyboard.press('Escape');
    await waitForLog(page, logs, /^\[Play\] Paused \(Escape\)/, `Escape to pause ${stop.shot}`, from);
    for (const key of ['ArrowDown', 'ArrowDown', 'Enter']) await page.keyboard.press(key);
    await waitForLog(page, logs, /^\[Game\] Arrived at TITLE/, `the title after quitting ${stop.shot}`, from);
    await page.waitForTimeout(300);
  }
}

// The run's scripted path once the title is up; throws on a missing log line.
async function playPath(page, context, run, logs, logTimes, shot) {
  if (run.keyboard) {
    // Tab is keyboard navigation, which shows the focus ring (hidden on arrival); two more
    // wrap through Endless and Time Attack back to Campaign.
    for (const key of ['Tab', 'Tab', 'Tab']) await page.keyboard.press(key);
    await page.waitForTimeout(300);
    await shot('focus');
    let from = logs.length;
    await page.keyboard.press('Enter');
    await waitForLog(page, logs, /^\[Title\] Campaign pressed \(1\)/, 'Campaign to be pressed (Tab, Tab, Enter on the focused Campaign)', from);
    await waitForLog(page, logs, /^\[Game\] Arrived at CHAPTER_SELECT/, 'the chapter select', from);
    from = logs.length;
    await page.keyboard.press('Enter');
    await waitForLog(page, logs, /^\[ChapterSelect\] Chapter dawn pressed/, 'Enter on the focused dawn chapter', from);
    await waitForLog(page, logs, /^\[Game\] Arrived at LEVEL_SELECT/, 'the level select', from);
    from = logs.length;
    await page.keyboard.press('Enter');
    await waitForLog(page, logs, /^\[LevelSelect\] Level dawn_1 pressed/, 'Enter on the focused level 1', from);
    await waitForLog(page, logs, LEVEL_RUN, 'level dawn_1 to start', from);
    await waitForLog(page, logs, /^\[Game\] Arrived at PLAY/, 'the play scene', from);
    await shot('play');
    from = logs.length;
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
    // Campaign is focused again on arrival: Tab, Tab reach Time Attack.
    await page.waitForTimeout(300);
    from = logs.length;
    for (const key of ['Tab', 'Tab', 'Enter']) await page.keyboard.press(key);
    await waitForLog(page, logs, /^\[Title\] Time Attack pressed \(1\)/, 'Time Attack to be pressed (Tab, Tab, Enter)', from);
    await waitForLog(page, logs, TIME_ATTACK_RUN, 'Time Attack to start', from);
    await waitForLog(page, logs, /^\[Game\] Arrived at PLAY/, 'the play scene (Time Attack)', from);
    await shot('time-attack');
    from = logs.length;
    await page.keyboard.press('Escape');
    await waitForLog(page, logs, /^\[Play\] Paused \(Escape\)/, 'Escape to pause Time Attack', from);
    for (const key of ['ArrowDown', 'ArrowDown', 'Enter']) await page.keyboard.press(key);
    await waitForLog(page, logs, /^\[Play\] Left the run \(Quit to title\): mode time_attack/, 'Down, Down, Enter to quit Time Attack', from);
    await waitForLog(page, logs, /^\[Game\] Arrived at TITLE/, 'the title after quitting Time Attack', from);
    await page.waitForTimeout(300);
    from = logs.length;
    for (const key of ['Tab', 'Enter']) await page.keyboard.press(key);
    await waitForLog(page, logs, /^\[Title\] Endless pressed \(1\)/, 'Endless to be pressed (Tab, Enter)', from);
    await waitForLog(page, logs, ENDLESS_RUN, 'Endless to start', from);
    await waitForLog(page, logs, /^\[Game\] Arrived at PLAY/, 'the play scene (Endless)', from);
    return [];
  }
  const pointer = await pointerFor(page, context, run);
  const failures = [];
  if (run.portrait) {
    await waitForLog(page, logs, /^\[Game\] Rotate overlay shown .*tree paused/, 'the rotate overlay (portrait)');
    await shot('rotate');
    await pointer.tap(await buttonPoint(page, logs, CAMPAIGN_RECT, 'the Campaign button layout'));
    await page.keyboard.press('Enter');
    await page.waitForTimeout(BLOCKED_WAIT_MS);
    if (pressCount(logs) !== 0) failures.push('a title button was pressed under the rotate overlay');
    const turned = logs.length;
    await page.setViewportSize(LANDSCAPE_PHONE);
    await waitForLog(page, logs, /^\[Game\] Rotate overlay hidden .*unpaused/, 'the rotate overlay to hide (turned to landscape)', turned);
    // The title refits to the landscape safe area and logs Campaign's new rect.
    await waitForLog(page, logs, CAMPAIGN_RECT, 'the Campaign button layout in landscape', turned);
    const pressed = logs.length;
    await pointer.tap(await buttonPoint(page, logs, CAMPAIGN_RECT, 'the Campaign button layout'));
    await waitForLog(page, logs, /^\[Title\] Campaign pressed \(1\)/, 'Campaign to be pressed (touch tap, back in landscape)', pressed);
    await shot('play');
    return failures;
  } else if (logs.some((l) => /^\[Game\] Rotate overlay shown/.test(l))) {
    failures.push('rotate overlay shown in a landscape viewport');
  }
  const arrived = await reachFirstLevel(page, logs, pointer, run.context.hasTouch ? 'touch' : 'mouse');
  const outcomes = await shootFirstGoose(page, logs, logTimes, pointer, arrived.index + 1);
  console.log(`[${run.name}] shots at the first goose: ${outcomes.join(', ')}`);
  await shot('play');
  const rival = await waitForLog(page, logs, RIVAL_LINE, 'a rival line (a heckle or an aim cue)', arrived.index + 1);
  console.log(`[${run.name}] rival: ${rival.input}`);
  // The page becoming hidden (another tab, the phone's home button) pauses the run.
  const hiddenFrom = logs.length;
  await page.evaluate(() => {
    Object.defineProperty(document, 'hidden', { value: true, configurable: true });
    document.dispatchEvent(new Event('visibilitychange'));
  });
  await waitForLog(page, logs, /^\[Play\] Paused \(page hidden\)/, 'the hidden page to pause the run', hiddenFrom);
  const how = run.context.hasTouch ? 'touch' : 'mouse';
  await reloadToTitle(page, logs);
  const timed = await startMode(page, logs, pointer, TIME_ATTACK_RECT, 'Time Attack', TIME_ATTACK_RUN, how);
  const timedOutcomes = await shootFirstGoose(page, logs, logTimes, pointer, timed.index + 1);
  console.log(`[${run.name}] Time Attack shots at the first goose: ${timedOutcomes.join(', ')}`);
  await shot('time-attack');
  await reloadToTitle(page, logs);
  await startMode(page, logs, pointer, ENDLESS_RECT, 'Endless', ENDLESS_RUN, how);
  if (run.backdrops) await backdropTour(page, logs, pointer, shot);
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
    for (const line of logs.filter((l) => /^\[(Game|Title|ChapterSelect|LevelSelect|Play|Results)\]/.test(l))) console.log(`[${run.name}] ${line}`);
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
