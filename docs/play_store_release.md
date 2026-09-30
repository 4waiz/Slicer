# Play Store Release

## App identity

| | |
| --- | --- |
| App name | Kanban Slicer |
| Short tagline | Cut Through Complexity |
| Package | `ae.kanbanstudios.kanban_slicer` |
| Version | 1.0.0 (`versionCode` 1) |
| Orientation | landscape (`sensorLandscape`, locked in both manifest and `main.dart`) |
| Min / target SDK | Flutter defaults for this toolchain |
| Category | Games → Puzzle |
| Content rating | Everyone — no violence, no gore, no user-generated content |

> The package name is a **temporary placeholder** as specified. Confirm the
> final applicationId before the first upload — it can never be changed after
> publishing.

## Artifacts

```bash
flutter build appbundle --release
```

- `build/app/outputs/bundle/release/app-release.aab` (47.3 MB) — **upload this**
- `build/app/outputs/flutter-apk/app-release.apk` (47.0 MB) — direct install / QA

Play generates per-device splits from the AAB, so the real download is roughly
a third of the universal APK.

## Signing

The release build currently uses the **debug signing key**, which Play will
reject. Before the first upload:

1. Create an upload keystore:

```bash
keytool -genkey -v -keystore upload-keystore.jks -keyalg RSA -keysize 2048 -validity 10000 -alias upload
```

2. Create `android/key.properties` (git-ignored, never commit it):

```
storePassword=<password>
keyPassword=<password>
keyAlias=upload
storeFile=<absolute path to upload-keystore.jks>
```

3. Wire it into `android/app/build.gradle.kts`: load `key.properties`, declare a
   `release` signing config from it, and point `buildTypes.release` at that
   config instead of `signingConfigs.debug`.

4. Enrol in Play App Signing so Google holds the app signing key and the
   keystore above is only the upload key.

## Store listing assets

| Asset | Path | Status |
| --- | --- | --- |
| App icon 512×512 | `docs/store/play_icon_512.png` | ready |
| Feature graphic 1024×500 | `docs/store/feature_graphic_1024x500.png` | ready |
| Adaptive launcher icons | `android/app/src/main/res/mipmap-*/ic_launcher.png` | ready (48–192 px) |
| Screenshots | — | **to capture**: minimum 2 landscape phone screenshots |

Screenshots can be captured from a running device with:

```bash
adb exec-out screencap -p > screenshot.png
```

Recommended shots: the home screen, a structure mid-slice, the PERFECT CUT
result, the level-select map, and the blade shop.

## Suggested listing copy

**Short description (80 chars max)**

> One swipe. One cut. Split the structure and land every piece where it belongs.

**Full description**

> Kanban Slicer is a one-swipe 3D physics puzzle. A structure hangs above a row
> of glowing pads. You get one look and one swipe — and the blade cuts it for
> real, exposing bright interior faces as the pieces separate and fall.
>
> The trick isn't aim. It's composition. Each piece is sorted by what it's
> actually made of, so a cut two degrees off leaves the wrong material attached
> and contaminates the wrong pad.
>
> • 60 handcrafted levels across six worlds
> • Seven materials that genuinely behave differently — crystal, jelly, fruit,
>   plastic, metal, ice and volatile cores
> • Magnets, wind, moving pads, protected cores and precision cut budgets
> • A new seeded Daily Slice every day, playable offline
> • Endless Slicing Lab with procedurally generated structures
> • Ten cosmetic blades that never touch the physics
>
> No timers. No energy. Just one clean cut.

## Privacy and data safety

The Data Safety form can be completed as **no data collected, no data shared**:

- All progress is stored locally via `SharedPreferences`. No account, no login.
- No analytics, crash reporting or attribution SDK is linked.
- No network permission is requested by the app itself.
- The advertising layer (`lib/core/monetization/ad_service.dart`) is an
  interface with a no-op default and **no ad SDK is linked in this build**.
  `ADS_ENABLED` defaults to false. If ads are enabled later, the Data Safety
  form and privacy policy must be updated before that build ships.

A privacy policy URL is required by Play even for apps that collect nothing.

## Monetization (currently inert)

Implemented behind configuration flags, with no SDK linked:

- Rewarded hint, rewarded extra cut, rewarded double coins
- Occasional interstitial after a *completed* level
- Remove-ads purchase, blade cosmetic packs

Rules enforced in code regardless of provider: never during a slice, never
after a failure, never in the first three levels, and never more often than
every third completed level. If a provider is installed and fails, rewards are
granted anyway — a convenience bonus is never withheld because an ad did not
load.

Production unit IDs come from `--dart-define` (`AD_UNIT_REWARDED`,
`AD_UNIT_INTERSTITIAL`); the defaults are Google's public test IDs, and ads are
disabled entirely in debug builds.

## Pre-launch checklist

- [ ] Confirm the final package name
- [ ] Create the upload keystore and wire release signing
- [ ] Enrol in Play App Signing
- [ ] Capture and upload landscape screenshots
- [ ] Publish a privacy policy and link it
- [ ] Complete the Data Safety form (no data collected)
- [ ] Set content rating via the questionnaire
- [ ] Test the AAB through internal testing on physical hardware
- [ ] Verify landscape behaviour on a tablet and on a device with a display cutout
