# Upkeep

Maintenance tracker for Android. Every tracked thing is a gauge on an
instrument cluster: it fills as it consumes its interval, turns amber at 90%,
red past due.

## What it tracks

Three kinds of item, and the app never pretends one is another:

| Type | The app… | Example |
|---|---|---|
| **Time** | knows exactly | furnace filter every 3 months |
| **Usage** | holds an exact **target** and *guesses* the date | oil at 48,000 mi |
| **Inspect** | never claims it's due — asks you to look | brake pads, tire tread |

For a usage item the headline is the target number — `Rotation at 48,000` —
because you read your odometer every time you get in the car. The learned
rate (miles/day, from your readings and from FuelWise while it's connected)
turns that into a projected date, and at 90% of the projection the app asks
for a hard number, which recalibrates the rate and the date. Log the same
service twice and it learns your real interval.

Each item can carry links (dealer booking page, the part on Amazon) and part
numbers, plus a message template that opens your SMS app prefilled. **The app
never sends a text itself** — it composes, you read it and hit send.

## Releasing

```powershell
.\publish.ps1
```

Bumps `pubspec.yaml`, commits, tags `vX.Y.Z` with your release notes, pushes.
GitHub Actions builds the signed APK and publishes a Release; the tag message
becomes the "What's New" text the app shows.

On the phone: the app checks silently on launch, or gear icon → **Check for
updates**.

`pubspec.yaml`'s `version:` is the single source of truth and must match the
tag — the updater compares them.

## Building

There's no Android SDK on the dev machine, so **CI builds every APK**. Local
verification is:

```bash
flutter analyze
flutter test
```

The gremlin can be inspected without a device — `flutter test --update-goldens`
writes `test/goldens/*.png`. Those goldens are Windows-only by design so
rasterisation differences can never fail a release build.

## Signing

Release APKs are signed with one key, forever. Android refuses to update an
installed app whose signature changed, so losing it means every phone has to
uninstall (and lose its data) to move forward.

- `android/app/upload-keystore.jks` — gitignored, local only
- `android/key.properties` — gitignored, local only
- Backed up to `OneDrive\App Keystores\upkeep\`
- CI restores it from the `KEYSTORE_BASE64` / `STORE_PASSWORD` /
  `KEY_PASSWORD` / `KEY_ALIAS` repo secrets

CI verifies the built APK is signed with `CN=Upkeep` and fails the release if
it isn't — a debug-signed APK installs once and can then never be updated.

## Your data

Nothing is seeded and nothing is sampled — every item is typed in by hand.
It lives in app-internal storage, which an in-place update preserves.
**Never uninstall to update.**
