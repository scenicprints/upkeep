# Upkeep — backlog

Releases are **batched**. Work lands on a feature branch, gets merged
`--no-ff` and tagged as one release with real notes — not a tag per fix.

---

## v0.2.0 — the actual tracker (in progress, branch `feature/batch-v0.2`)

### Done
- [x] **Bottom nav sits above the system navigation bar.** The labels were
      42px under the gesture bar. Cause: reading `MediaQuery.viewPadding` by
      hand from an ancestor context, which Android 15's forced edge-to-edge
      makes unreliable. Now `SafeArea` inside the coloured container so the
      background still fills the strip. Guarded by `test/insets_test.dart`,
      which injects a 48px system bar and asserts the geometry — verified to
      fail against the old code.
- [x] **Launcher icon.** Gauge at 90% around a wrench.
      `tools/make_icon.py` → `dart run flutter_launcher_icons`. The script
      also renders `_launcher_preview.png` simulating the real adaptive mask,
      because flutter_launcher_icons adds a 16% inset that silently shrinks
      the mark.

- [x] **Item model + storage** (`models.dart`, `store.dart`). App-internal
      JSON, atomic write, no seeding. A corrupt read never presents as
      "you have no items".
- [x] **Three item types.** Time / usage / inspect, per above. An inspect
      item is capped at amber and can NEVER go red — red means "past due"
      and the app cannot know that about brake pads. A test enforces it.
- [x] **The cluster.** Hero gauge, arcs sweeping up from zero, staggered
      rows, status strip.
- [x] **Add / edit flow** with assets.
- [x] **Links** — label + URL, opens externally.
- [x] **Part numbers** — tap to copy.
- [x] **Text handoff.** Contact picker, template with {item} {asset}
      {target} {due}, opens the SMS app prefilled. Never sends by itself.
- [x] **Notifications** at 90%, rescheduled from scratch on every change,
      inexact so no exact-alarm permission is needed.
- [x] **History** — newest first, swipe to remove, feeds interval learning.

---

## v0.3.0 — batch in progress (branch `feature/batch-v0.3`)

### Done
- [x] **Mileage OR months, whichever comes first.** A usage item takes an
      optional second limit in months. Whichever is further along drives the
      gauge, so a car that barely moves still comes due on time. Both limits
      show in the headline (`43,410 mi or Oct 13`). Calendar arithmetic, not
      30-day approximations — six months from Aug 31 is Feb 28. The 90% ask
      and the notification only mention the odometer when MILEAGE is the
      limit about to trip; if the calendar gets there first, a reading tells
      you nothing.

- [x] **The odometer belongs to the CAR, not to each item.** Readings moved
      from `Item` to `Asset`; everything that reads the meter moved to a new
      `Tracked` view. One entry now moves every mileage item on that car,
      instead of asking for the same number once per item and letting the
      ones you skipped coast on a stale guess. Migration folds v0.2 files up
      automatically — additive, idempotent, and it leaves an orphaned item's
      readings alone rather than dropping them.
- [x] **A mistyped reading can be fixed.** New meter screen per asset: see
      every reading, tap to correct, swipe to remove. Entering one that goes
      backwards, or that implies a wild jump, asks you to look twice — but
      never blocks it, because a swapped cluster is a real thing.
- [x] **Backup.** Export a dated .json through the share sheet (Drive, email
      to yourself). Restore by pasting it back, with a confirm that shows
      what's being traded for what. Paste rather than a file picker on
      purpose — file_picker needs a newer Android toolchain than this
      project builds on.

### Candidates
- [ ] Group the cluster by asset rather than pure urgency.
- [ ] Snooze — defer an item without logging it as done.
- [ ] A note on a logged service (the field exists; there's no box for it).

---

## v0.4.0 — batch in progress (branch `feature/batch-v0.4`)

### Done
- [x] **The gremlin reads the panel.** Four moods (idle / content / alert /
      overdue) driven by `moodFor(controller.worstState)`. His eyes take the
      worst state's colour and his mouth changes with it; the wrench sways
      faster the worse things get. He now rides in the cluster header at
      42px as a live wordmark — no new information, since the counts below
      already say it, but the screen has a pulse before you've read a word.
      Nothing tracked keeps him idle rather than worried.
- [x] **Poke him.** Tap the gremlin and he startles: eyes wide, a hop with
      stretch in the air and a compress on landing, and the wrench spins a
      full turn. Light haptic. Squash-and-stretch the right way round —
      flattening at the top of a jump reads as a pancake.

---

## Later
- [ ] **FuelWise bridge.** `scenicprints/fuelwise` already records an
      `odometer` on every fill-up, so Upkeep could stop asking about his own
      car. Blocked: `fuelwise-data` is empty except a README — FuelWise isn't
      publishing its log yet, so this needs a change in both apps.
- [ ] Export / backup so a dead phone doesn't cost the entries.
- [ ] Photos on an item (the filter size, the part on the shelf).
