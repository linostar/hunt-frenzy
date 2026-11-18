# Hunt Frenzy: Google Play listing

Copy each value into Google Play Console, in the order of the Console's pages. Never use the
names Nintendo, Duck Hunt, NES or Zapper (plan AC 30).

## Create app

| Field | Value |
|---|---|
| App name | Hunt Frenzy |
| Default language | English (United States) – en-US |
| App or game | Game |
| Free or paid | Free |

## Release (Testing → Internal testing first, then Production)

| Item | Value |
|---|---|
| App bundle | `build/android/huntfrenzy.aab` from `tools/build_android.sh release` |
| Play App Signing | Accept Google's app signing. Your keystore (`uniquity-apps-sign-key-2026`) becomes the upload key. |
| Release name | 1.0.0 (1) |
| Release notes (en-US) | First release: a 24-level campaign, Endless and Time Attack. |

Each new upload needs a higher `version/code` in both Android presets of `huntfrenzy/export_presets.cfg`.

## Main store listing

| Field | Limit | Value |
|---|---|---|
| App name | 30 | Hunt Frenzy |
| Short description | 80 | A retro-inspired arcade shooter: clear the marsh before your rival does. |
| App icon | 512 × 512 | `store/google-play/icon_512.png` |
| Feature graphic | 1024 × 500 | `store/google-play/feature_graphic.png` |
| Phone screenshots | 2 to 8 | `itch/screenshots/01_title.png` … `06_results.png` (1920 × 1080) |
| Video | YouTube link | The trailer link from the itch.io page (optional) |

### Full description (4000 characters at most)

```
The geese are up. The shells are counted. And the hunter next to you wants every bird you miss.

Hunt Frenzy is a retro-inspired arcade shooter. Tap to shoot birds over a cartoon marsh. Shoot each wave before it flies away. Do it fast, or your rival takes the shot and the points.

FEATURES
• A 24-level campaign in four chapters: dawn mist, noon wind, sunset rain and night snow. Each chapter ends with a boss flock.
• Six bird types: geese, armored geese that take two hits, splitters that burst into goslings, zigzagging swifts, a rare golden goose for big points, and a pigeon in a top hat that you must not shoot.
• A rival hunter who mocks your misses, sulks at your hits, and steals the birds that you leave in the air.
• Endless and Time Attack modes, each with its own best score.
• Combos, stars and best scores. Every shot counts: each wave has a limited number of shells.
• An original bluegrass soundtrack with banjo, fiddle and washboard.

HOW TO PLAY
• Tap a bird to shoot it.
• Each wave has a limited number of shells. When they run out, the birds escape.
• Hit birds one after another to increase your combo.
• Do not shoot the pigeon in the top hat. It costs you points and your combo.
• A red target mark on a bird means that the rival aims at it. Shoot that bird first.

NO ADS, NO ACCOUNTS, NO TRACKING
The game works offline and asks for no permissions. Your progress stays on your device.

Settings: music and sound volume, mute, and Reduce motion (no screen shake, calm pop-ups and screen changes).
```

## App content (Policy → App content)

| Section | Answer |
|---|---|
| Privacy policy | `https://github.com/linostar/hunt-frenzy/blob/main/store/privacy-policy.md` |
| Ads | No, my app does not contain ads |
| App access | All functionality is available without special access |
| Content rating (IARC questionnaire) | Category: Game. Violence: yes, cartoon or fantasy violence against animals (birds are shot and fall; no blood, no gore, no humans hurt). Fear, sexuality, language, controlled substances, gambling, user interaction, sharing location, digital purchases: no. Expected result: about PEGI 7 / ESRB Everyone 10+. |
| Target audience and content | Ages 13 and over. Do not choose a children's age group: the Families policy then applies. The store listing does not appeal to children only. |
| News app | No |
| COVID-19 apps | Not a contact tracing or status app |
| Data safety | Does your app collect or share any of the required user data types? **No.** Is all data encrypted in transit? Not applicable (no data leaves the device). Do you provide a way to request data deletion? Not applicable (no data collected). |
| Government apps | No |
| Financial features | None |
| Health | None |

## Store settings

| Field | Value |
|---|---|
| App category | Game → Arcade |
| Tags | Arcade, Shooter, Casual, Offline, Single player (choose the closest that the Console offers) |
| Contact email | Your choice (it is public on the listing) |
| Website | `https://linostar.itch.io/hunt-frenzy` |

## Before production

1. Upload the AAB to an **Internal testing** release. Install it from the testing link on a real phone.
2. On the phone: start a level, shoot birds, hear the sound, press Back (pause, then resume), press Back on the title (the app closes).
3. New personal developer accounts must run a **closed test with at least 12 testers for 14 days** before production access. Check the Console's Dashboard for this requirement.
4. Promote the release to Production.
