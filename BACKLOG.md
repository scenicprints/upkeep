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

### Still to build
- [ ] Mascot moods wired to the real worst-state on the panel (he only
      appears on the empty state today).
- [ ] Reorder / group the cluster by asset rather than pure urgency.

---

## Later
- [ ] **FuelWise bridge.** `scenicprints/fuelwise` already records an
      `odometer` on every fill-up, so Upkeep could stop asking about his own
      car. Blocked: `fuelwise-data` is empty except a README — FuelWise isn't
      publishing its log yet, so this needs a change in both apps.
- [ ] Export / backup so a dead phone doesn't cost the entries.
- [ ] Photos on an item (the filter size, the part on the shelf).
