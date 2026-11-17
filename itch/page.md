# Hunt Frenzy: itch.io page

Copy each field into itch.io's "Create new project" form, in this order. Never use the names
Nintendo, Duck Hunt, NES or Zapper on the page (plan AC 30).

## Project settings

| Field | Value |
|---|---|
| Title | Hunt Frenzy |
| Project URL | `hunt-frenzy` |
| Short description or tagline | A retro-inspired arcade shooter: clear the marsh before your rival does. |
| Classification | Games |
| Kind of project | HTML |
| Release status | Released |
| Pricing | No payments (free), or "Donate" if you want tips |
| Uploads | `build/huntfrenzy.zip` from `tools/build_web.sh`, with "This file will be played in the browser" on |
| Viewport dimensions | 960 × 540 |
| Orientation | Landscape |
| Mobile friendly | On |
| Automatically start on page load | Off (sound can start only after the first tap) |
| Fullscreen button | On |
| Enable scrollbars | Off |
| SharedArrayBuffer support | Off (the build is single-threaded) |
| Genre | Shooter |
| Tags | arcade, shooter, birds, retro, casual, cartoon, 2d, mobile, godot, singleplayer |
| AI generation disclosure | Answer this yourself. |
| Cover image | `itch/cover.png` (630 × 500) |
| Gameplay video or trailer | Upload `itch/trailer.mp4` to YouTube or Vimeo, then paste its link here. |
| Screenshots | `itch/screenshots/`, in file order: 01 to 06 |
| Community | Comments |
| Visibility | Draft first. Play it on a real iPhone and a real Android phone (plan AC 37), then make it Public. |

## Description

Paste the text below the line into the description field.

---

**The geese are up. The shells are counted. And the hunter next to you wants every bird you miss.**

Hunt Frenzy is a retro-inspired arcade shooter for your browser, on desktop and on phones. Tap or click to shoot birds over a cartoon marsh. Shoot each wave before it flies away. Do it fast, or your rival takes the shot and the points.

### Features

- **A 24-level campaign** in four chapters: dawn mist, noon wind, sunset rain and night snow. Each chapter ends with a boss flock.
- **Six bird types:** geese, armored geese that take two hits, splitters that burst into goslings, zigzagging swifts, a rare golden goose for big points, and a pigeon in a top hat that you must not shoot.
- **A rival hunter** who mocks your misses, sulks at your hits, and steals the birds that you leave in the air.
- **Endless and Time Attack modes**, each with its own best score.
- **Combos, stars and best scores.** Every shot counts: each wave has a limited number of shells.
- **An original bluegrass soundtrack** with banjo, fiddle and washboard.

### How to play

- Tap or click a bird to shoot it.
- Each wave has a limited number of shells. When they run out, the birds escape.
- Hit birds one after another to increase your combo.
- Do not shoot the pigeon in the top hat. It costs you points and your combo.
- A red target mark on a bird means that the rival aims at it. Shoot that bird first.

### Controls

| Action | Desktop | Phone |
|---|---|---|
| Shoot | Click | Tap |
| Pause | Esc or the pause button | The pause button |
| Menus | Mouse, or Tab, the arrow keys and Enter | Tap |

Play with the phone in landscape. On a phone, use the fullscreen button for the best view.

### Settings

You can set the music and sound volume, mute each one, and turn on **Reduce motion**. Reduce motion stops the screen shake and makes the pop-ups and the screen changes calm.

Your progress and best scores stay in your browser. If you clear your browser data, they are lost.

### Credits

- Game, art, music and code: **linostar**
- Made with the [Godot Engine](https://godotengine.org) (MIT license)
- Fonts: Lilita One by Juan Montoreano and Nunito by the Nunito Project Authors, under the SIL Open Font License 1.1
- The rival's laugh: "evil laugh" by WeaponGuy (OpenGameArt), CC0
- Bird calls: Bert76 (CC0), Oona Räisänen and the U.S. Fish and Wildlife Service (public domain), via Wikimedia Commons

All other content: © linostar, all rights reserved.

---

## Upload checklist

1. Run `tools/build_web.sh`. It must end with `PASS build: build/huntfrenzy.zip` and a size under 50 MB.
2. Create the project as a draft. Fill in the fields above.
3. Upload the zip, set "played in the browser", and set the embed options from the table.
4. Upload the cover and the six screenshots. Paste the trailer link.
5. Open the draft on a desktop browser, a real iPhone (Safari) and a real Android phone (Chrome). On each: start a level, shoot birds, hear the sound, pause, rotate the phone to portrait and back.
6. Make the page Public.
