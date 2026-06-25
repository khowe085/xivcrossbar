# XIVCrossbar — Edit Target & Overlay Test Plan

Run this after **any** change to XIVCrossbar to confirm the **Select Edit Target** feature
and the **Light/Dark Arts + Addendum overlays** still behave correctly. It starts from a
**clean (empty) character directory** and checks that:

1. The correct XML files are **created and written** (and that nothing is written on load).
2. In-game edits **land in the file matching the selected target**.
3. The **UI** renders as expected (menu, selector, subtitle, icons, footer).
4. **All overlays** load, unload, stack, and switch correctly in-game.

This is a manual plan — XIVCrossbar has no automated test harness. Tick the boxes as you go.

---

## Preconditions

- Be on (or able to switch to) **Scholar** as main or sub job — Light/Dark Arts and the
  Addenda are SCH-only. The examples below use **SCH/RDM**; substitute your real job/sub.
- **Clean slate:** back up and remove every file in
  `data/hotbar/{Server}/{Character}/` for the job/sub you're testing, so the directory
  starts empty. (Keep a backup if these are real hotbars.)
- After applying your change, reload the addon: `//lua r xivcrossbar`.
- Know how you open the **action binder** (the binding menu — e.g. `Ctrl+Minus` /
  gamepad **Minus**).

## File map (target → file)

All files live under `data/hotbar/{Server}/{Character}/`. With no subjob, `{SUB}` = `NOSUB`.

| Selector option   | File pattern              | Example (SCH/RDM)      |
|-------------------|---------------------------|------------------------|
| All Jobs Default  | `ALL-JOBS-DEFAULT.xml`    | `ALL-JOBS-DEFAULT.xml` |
| Job Default       | `{MAIN}-DEFAULT.xml`      | `SCH-DEFAULT.xml`      |
| Job + Sub Default | `{MAIN}-{SUB}.xml`        | `SCH-RDM.xml`          |
| Light Arts        | `{MAIN}-{SUB}-LA.xml`     | `SCH-RDM-LA.xml`       |
| Dark Arts         | `{MAIN}-{SUB}-DA.xml`     | `SCH-RDM-DA.xml`       |
| Addendum: White   | `{MAIN}-{SUB}-LA-AW.xml`  | `SCH-RDM-LA-AW.xml`    |
| Addendum: Black   | `{MAIN}-{SUB}-DA-AB.xml`  | `SCH-RDM-DA-AB.xml`    |

## How to verify

- **Disk is the source of truth.** "Did the edit land in the right file?" → open the XML
  and look for the action you assigned (the file is a `<hotbar>` tree; search it for the
  action name).
- **In-game merged view** is secondary. Layers merge by priority, **lowest to highest**:
  `all-jobs (1) < job-default (2) < job+sub (3) < arts overlay < addendum`. A higher layer
  wins per slot — so if an edit "doesn't show," a higher layer already defines that slot.
  Test on an **empty slot**, or trust the file.
- **Windower console** (`//console`) is used only for the "no stray messages" checks.

**Tip:** assign a *different, recognizable* action per layer (e.g. a unique spell per
target) so you can tell at a glance which file/overlay is showing.

---

## Phase 0 — Clean slate

- [ ] **0.1** `data/hotbar/{Server}/{Character}/` is **empty** for the test job/sub.
- [ ] **0.2** `//lua r xivcrossbar` loads with no Lua errors in the console.

## Phase 1 — Nothing is written on load (lazy creation)

- [ ] **1.1** Immediately after the clean load, the directory is **still empty** — no
  `*-DEFAULT.xml`, no `*-NOSUB.xml`, nothing created just by loading or logging in.
- [ ] **1.2** The console shows **no** `No … found; creating it` / `create the file by
  hand` / `Load …` messages (these were removed).

## Phase 2 — First edit creates the job-default file

- [ ] **2.1** Open the binder. The footer reads **`Editing: SCH-DEFAULT.xml`** (default
  target is Job Default).
- [ ] **2.2** Assign a recognizable action to an empty slot.
- [ ] **2.3** On disk, **`SCH-DEFAULT.xml` now exists** and contains that action.
- [ ] **2.4** No other files were created.

## Phase 3 — Edits land in the file matching the selected target

For each target below: open binder → **Select Edit Target** → pick the target → assign a
**distinct** action to a **different empty slot** per target → verify on disk. Use a
different slot for each so all three stay visible at once; if you reuse one slot, only the
highest-priority layer (job+sub) shows in-game even though every file is written correctly.

- [ ] **3.1 Job + Sub Default** → assignment written to **`SCH-RDM.xml`**.
- [ ] **3.2 All Jobs Default** → assignment written to **`ALL-JOBS-DEFAULT.xml`**.
- [ ] **3.3 Job Default** → assignment written to **`SCH-DEFAULT.xml`**.
- [ ] **3.4 Cross-check isolation:** each assignment appears **only** in its target file,
  not duplicated into the others.
- [ ] **3.5 Delete routes too:** with target = Job + Sub, delete a slot → the deletion is
  reflected in **`SCH-RDM.xml`** (not job-default).
- [ ] **3.6 (optional)** copy / move / re-alias / change-icon also write to the selected
  target file.
- [ ] **3.7 (optional) merge priority:** assign the **same** slot in two layers (e.g. Job
  Default and Job + Sub) → in-game only the **higher** layer (job+sub) shows, but **both
  files** still hold their own copy of that slot. Confirms layering without data loss.

## Phase 4 — UI

- [ ] **4.1 Menu entry:** the action-type list shows **"Select Edit Target"** with a
  **grimoire (white book)** icon — visually distinct from "Switch Crossbars".
- [ ] **4.2 Selector screen:** title reads **"Select Edit Target File"**; **7 options**,
  each with the grimoire icon; **no "(active)" text** appended to any option.
- [ ] **4.3 Subtitle:** a line under the title reads **`Active: <current layer>`** (e.g.
  `Active: Job Default`) and reflects the *currently active* target.
- [ ] **4.4 Subtitle scoping:** Go Back to the action-type list → the `Active:` subtitle is
  **gone** (it only shows on the selector screen).
- [ ] **4.5 Footer (all screens):** every binder screen shows **`Editing: <file>`** for the
  active target, sitting clear to the **left of the Confirm hint** (no overlap, even with
  the longest name `…-LA-AW.xml`).
- [ ] **4.6 Footer updates:** select **Dark Arts** as the target → reopen any screen → the
  footer now reads **`Editing: SCH-RDM-DA.xml`**.

## Phase 5 — Overlay files are created/written (targets 4–7), arts OFF

Do these with **no arts active** to confirm the file is written even when the overlay isn't
loaded. (Delete the target file first if it already exists.)

- [ ] **5.1 Light Arts target** → assign a slot → **`SCH-RDM-LA.xml`** is auto-created with
  the assignment.
- [ ] **5.2 Dark Arts target** → **`SCH-RDM-DA.xml`** created.
- [ ] **5.3 Addendum: White target** → **`SCH-RDM-LA-AW.xml`** created.
- [ ] **5.4 Addendum: Black target** → **`SCH-RDM-DA-AB.xml`** created.
- [ ] **5.5 No duplicate levels:** make 2–3 more edits to the same overlay target → still
  one file, no duplicated entries.
- [ ] **5.6 Expected UX:** with arts **off**, the just-assigned overlay slot may **not stay
  visible** on the bar (the overlay isn't loaded). The **file is still correct** — Phase 6
  confirms it appears when arts is on.

## Phase 6 — Overlays work in-game (Light/Dark Arts + Addenda)

Use the slots seeded in Phase 5 so each overlay shows something recognizable.

- [ ] **6.1 Light Arts:** use Light Arts → the **`SCH-RDM-LA`** slot(s) appear on the bar.
- [ ] **6.2 Switch to Dark Arts:** use Dark Arts → LA slots disappear, **`SCH-RDM-DA`**
  slots appear.
- [ ] **6.3 Addendum stacks:** with Light Arts active, use **Addendum: White** →
  **`SCH-RDM-LA-AW`** slots layer **on top of** the LA slots.
- [ ] **6.4 Switching arts clears the addendum:** from LA + Addendum White, use **Dark
  Arts** → both LA and LA-AW slots clear; DA slots load.
- [ ] **6.5 Addendum: Black:** with Dark Arts active, use **Addendum: Black** →
  **`SCH-RDM-DA-AB`** slots layer on the DA slots.
- [ ] **6.6 Losing arts:** cancel or let Light Arts expire → its overlay **and** any active
  addendum clear back to the base bars.
- [ ] **6.7 Arts already active on reload:** with **Light Arts up**, run
  `//lua r xivcrossbar` → after reload the LA overlay is **loaded** (slots present)
  **without** re-toggling arts.
- [ ] **6.8 Edit while arts active:** with Light Arts active, target = Light Arts, assign a
  slot → it appears immediately and **persists** through a following edit (overlay stays
  loaded).

> If an overlay ever lags one beat behind the arts toggle, that's the known Windower
> `gain/lose buff` timing quirk — a second toggle or `//lua r` settles it. (Reference buff
> ids: Light 358, Dark 359, Addendum: White 401, Addendum: Black 402.)

## Phase 7 — Target resets to Job Default

- [ ] **7.1 On reload:** set target = Dark Arts (footer confirms) → `//lua r xivcrossbar` →
  reopen the selector → **Active: Job Default** (footer back to `…-DEFAULT.xml`).
- [ ] **7.2 On job change:** set target = Light Arts → change job or subjob → target back to
  **Job Default**; arts overlays cleared.

## Phase 8 — New crossbar set (`//xb new`) respects the target

- [ ] **8.1** Target = **Job + Sub Default**, run `//xb new TestSet` → written to
  **`SCH-RDM.xml`**.
- [ ] **8.2** Target = **Light Arts**, `//xb new TestArtsSet` → written to
  **`SCH-RDM-LA.xml`**.

## Phase 9 — Regression / integrity

- [ ] **9.1** Hand-made files you didn't touch are **not** rewritten on load (timestamps
  unchanged).
- [ ] **9.2** Switching characters loads the new character's files; the previous
  character's files are untouched (no cross-character clobber).
- [ ] **9.3** Core binder features unaffected: normal slot assignment, Switch Crossbars,
  Move Crossbar still work.

---

## Sign-off

- [ ] All phases pass
- [ ] No Lua errors in the console during any step
- [ ] Footer position acceptable in your resolution (note if it needs tuning)
