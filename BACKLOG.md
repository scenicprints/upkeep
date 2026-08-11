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

### To build
- [ ] **Item model + storage.** App-internal JSON, no seeding, survives
      updates. Nothing is ever auto-created or reset.
- [ ] **Three item types**
  - Time — exact, app knows.
  - Usage — exact **target** number is the headline (`Rotation at 48,000`);
    learned rate → projected date; asks for a hard reading at 90% of the
    projection, which recalibrates. Learns the real interval after two logs.
  - Inspect-on-cadence — never claims due, prompts you to look.
- [ ] **The cluster.** Hero gauge for the most urgent item, arcs sweeping up
      from zero on open, everything else as compact rows grouped by asset.
- [ ] **Add / edit flow**, including assets (Jenny's RAV4, The House, Me).
- [ ] **Links** — label + URL, opens in the browser (dealer booking, Amazon).
- [ ] **Part numbers** — tap to copy.
- [ ] **Text handoff.** Pick a recipient from contacts, per-item message
      template with the numbers filled in, opens the SMS app prefilled.
      **Never sends by itself.**
- [ ] **Notifications** for time-based items and for the 90% ask.
- [ ] **History tab** — what was done and when; feeds interval learning.
- [ ] Mascot moods wired to the real worst-state on the panel.

---

## Later
- [ ] **FuelWise bridge.** `scenicprints/fuelwise` already records an
      `odometer` on every fill-up, so Upkeep could stop asking about his own
      car. Blocked: `fuelwise-data` is empty except a README — FuelWise isn't
      publishing its log yet, so this needs a change in both apps.
- [ ] Export / backup so a dead phone doesn't cost the entries.
- [ ] Photos on an item (the filter size, the part on the shelf).
