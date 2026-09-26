# Changelog

## 1.12.0 — prove it

Phase 18. The phase where the question is not "does it work" but "how would we
know". Four items, and the honest summary is that the fixtures found more than the
features did.

### A proportion matrix, and the three defects it found

The motion suite proved everything on one human dummy: adult proportions,
symmetric, and almost exactly the leg length the defaults were written against.
Nothing said what happens to a child's leg or a giant's. `tier1_proportions.gd`
now runs the same walk over rigs differing only in leg length (0.50 / 0.85 /
1.70 m), leg symmetry and orientation, and asserts what must survive the
difference.

Two of its assertions are dimensionless on purpose. The **Froude number**
`v/sqrt(gL)` is how gait speed is compared across body sizes at all, and the
stance fraction is read off published gait (~0.60 of the cycle walking).
Absolute speeds would have asserted the dummy's luck rather than the generator.

It found three real defects, all fixed:

- **The knee-bend crouch was in absolute metres.** `crouch + 0.003 m/deg *
  knee_bend` added its term *after* the handler had scaled `config.crouch`, so
  the same 30 degrees of knee bend bought 9 cm on every rig — 18% of a child's leg
  against 6% of an adult's. It is now scaled, and the ratio is 0.1059 of the leg
  on every proportion, which the matrix asserts directly.
- **That crouch was also why a tall rig could not reach its own targets** — 9 cm
  of extra drop on a 1.7 m leg was 0.041 m more reach than the leg could span.
  Scaling it fixed the reach failure as a side effect, so the lift clamp that
  looked like the cause was left alone and recorded as a latent sub-linearity.
- **The stride came from the left leg while the distances scaled from the
  longest**, so on a rig whose legs differ the two disagreed by the asymmetry.
  Both now come from one leg.

Also removed: a hard-coded 0.35 m fallback for an unmeasurable shin, which was
longer than a whole child's leg, and `jump_config.foot_lift`, which `jump_keys`
never read yet which was being rig-scaled on every run.

The rest map, leg map and rig frame moved into the spec layer, so the handler and
a headless test assemble a context the same way instead of keeping an
editor-only copy that can drift. The golden confirmed the move changed nothing
on the dummy — after a first version that quietly did.

### Four goldens behind one implementation

`tests/golden_digest.gd` quantizes a clip to integers at 1/2048 with quaternion
sign normalized, and compares two digests. Walk, run and idle go through the real
ops in the editor suite; a fourth is spec-level over a synthetic rig in tier-1,
which is the one that runs on **both** platforms. Each fixture carries the engine
that produced it, so a version bump that moves the numbers is explicable from the
log rather than mysterious. Comparison answers with a drift *and* a shape
difference, because a changed track count is a different kind of change from a
drift.

**The cross-OS question was settled by measurement.** The editor suites now run
on Windows as well as Linux — which is how a bash-vs-PowerShell failure in the
steps themselves was found and fixed — and the golden drifts **0 units on
`ubuntu-latest` and `windows-latest` alike**. The float maths is bit-stable
across platforms at this quantization, and the 2-unit tolerance (ten times the
measured same-process floor of 1e-4 rad) is now justified rather than hoped for.
Every fixture was verified in both directions: it passes against its own
recording and fails when perturbed.

### What the goldens were worth

The walk golden caught an intended change at **83 units (2.3°)** — the fixture
measures a 0.797 m leg, not the 0.85 m reference its defaults were written
against — which turned an argument into a number. It also caught a refactor that
was quietly changing a neck bone's rest pose, because it resolved the spine chain
a second time.

Two test fixtures were wrong before the code was, and both are worth recording:
`set_bone_rest` is a **local** rest, so global-looking joint positions compound
down the chain (a 0.5 m leg measured 0.76 m); and a first "asymmetric" rig varied
lateral offset rather than leg length. An assertion that Froude must be constant
across rigs was also wrong physics — a stride built from an angle scales speed
with L, so Fr grows as sqrt(L) — and the matrix now asserts that law instead,
which is a stronger statement: change the speed law and it fails.

One more from the survey: `turn_config.turn_angle` was reported as not accepted
as an override. It is, and is read. Recorded so it is not "fixed" twice.

202 editor tests, 14 tier-1 suites (2 platforms each), 32 CI jobs.

## 1.11.0 — the shapes, and what the engine actually does

Twelve commits past v1.9.0, covering the close of **Phase 16** (contract flags
verified against the registry, canonical doc examples) and all of **Phase 17** —
the seven items that decide whether a generated clip *looks* like animation. Two
early Phase 18 pieces are in as well: the generator contract test and a real
playback test.

### Phase 17 - the shapes were wrong, not the arithmetic

- **A swing is an arc, not a step.** Foot lift was 0 or 1 across the whole swing,
  so the ankle teleported up at toe-off and dropped at heel strike. It is now a
  hump: exactly 0 at both contacts, peaking just before mid-swing, with zero
  slope at the contacts and the apex so neither end of the arc pops.
- **Idle keeps its feet.** Idle bobbed and swayed the pelvis and never re-solved
  the legs. It now defaults to `planted: true` and solves both legs against their
  rest ankles.
- **Honest reach, with the rig's own knee.** A target the leg cannot reach is now
  shortened to what it *can* reach, and the reply says so: `clamped` and
  `clamp_shortfall_m`. The knee pole is the rig's own measured rest bend rather
  than a guess, so it works on a rig the toolkit has never seen.
- **Defaults scale with the rig.** Default bob, sway, lift, crouch, jump height
  and lean are derived from the measured leg length, so the same numbers read the
  same way on a short or a tall rig. Explicit metre values are still honoured
  exactly.
- **A real rig frame.** `RigAnalysis.rig_frame()` builds up/forward/lateral from
  rest geometry and the generator *and* the audit both take it, so "planted"
  means the same thing on both sides. `up` is the spine bone's axis - local +Y is
  a bone's head-to-tail direction - signed by the hips-to-head chain. A bone axis
  carries the rig's *pose* as well as its convention, and the fixture's spine
  rests 1.5 degrees off vertical, so the axis is read for the convention and
  snapped within 10 degrees: the golden walk is unchanged, which is the proof that
  this is a no-op for Y-up rigs and a real frame for genuinely rotated ones. The
  rest map also covers the spine chain now, so a detected neck or upper chest is no
  longer keyed against an identity fallback.
- **Lean is shared, not repeated.** Every torso bone took the *full* lean, so the
  requested 20 degrees read as 60. The total is distributed by chain weights.
- **The root-motion contract, settled by measurement.** Extraction cancels the
  hips track from the pose, which shifts the whole chain back by the travel, and
  the caller applies the same travel to the node - so `world == authored` and a
  planted foot has to be authored still in clip space, which is what the recipe
  already did. Two plausible-sounding alternatives were implemented, measured
  (0.61 m of slide each, the moonwalk) and reverted. `root_motion_local` is now
  set explicitly instead of being left at the engine's global default.

### Fixtures that make drift visible

- **A golden walk** (`test_project/tests/fixtures/golden_walk.json`): a quantized
  digest of one 8-sample walk, every key an integer at 1/2048, so a generator
  change shows up as a number. Verified in both directions - it passes against its
  own recording and *fails* when perturbed. It earned its keep immediately by
  measuring 4.8 degrees of shin change that no behavioural test noticed.
- **An engine-behaviour harness** (`tier1_root_motion.gd`), written because a
  conclusion had been drawn from a harness that was not animating. It establishes
  what the engine does with a root-motion track against a live control, and
  deliberately does not assert the one thing it cannot observe there.

## 1.9.0 — audit remediation

Phase 15. Every item below was reproduced by a failing test first, then fixed,
then re-verified. The theme: no tool may report success it cannot confirm, and
`dry_run` may not touch anything.

### No setup reports success it cannot confirm

- `*_setup` ops now verify their own wiring **after** the undo action commits
  and **roll it back** if it did not take (`_undo_and_fail` in the shared
  handler base). `ik_setup` reads the modifier's target/pole settings back and
  resolves them; `retarget_setup` confirms the target became a child of the
  modifier and that every mapped bone resolves on both skeletons; spline IK
  additionally requires the `Path3D` to have curve points.
- A retarget target that ends up nested in another node is **refused** with an
  explanation. `RetargetModifier3D` only drives its own children, so such a
  target was accepted, reported as set up, and then never moved.
- `move_target=false` reconfigures an existing modifier only for the source it
  was built for; another skeleton's profile against a different source is
  refused rather than silently applied to bones that do not exist.
- Spring `centre_path` and collision shapes resolve **relative to the
  `SpringBoneSimulator3D`**, not the edited-scene root, and collision nodes are
  reparented under the simulator (undoably; reported as `collisions_moved`).
- `graph wire` honours `create=false`: the "is this already wired?" check no
  longer creates the tree it was checking for.

### `dry_run` is side-effect free

- A table-driven test runs one op per family with its own `dry_run: true` and
  asserts the node tree, every clip, the undo history version and the filesystem
  are unchanged. It found two real leaks, now fixed:
  - `template_save` / `template_delete` wrote (or deleted) the library file.
  - `inspect rig_profile` wrote a profile file.
- `pose_save` and `rig_profile` now advertise `dry_run`, and every file write in
  the library and rig handlers goes through a single guarded choke point.

### Correctness fixes found by the audit

- `look_at_setup` passes its limit angles in **degrees** where the modifier wants
  radians (`primary=45.0` for a 45° limit).
- `animation_inspect` walks `AnimationNode` sub-nodes by type instead of calling
  a method that does not exist — an animation tree made the audit crash.
- `SpineTwist` divided by a **signed** sum, so a hips-leads/chest-counters
  profile (negative sum) fell back to a divisor of 1.0 and came out with several
  times the requested twist. Signs are now preserved and the scale is honest.
- `foot_slide` counts contact from both feet (a one-sided test sank the planted
  foot) and no longer claims more contact time than the clip contains.
- Torso twist/lean uses the **detected** spine chain (the neck participates)
  before falling back to the role chain.
- Quaternion `scale_delta` is measured from the track's baseline, so
  `amplitude(0)` no longer snaps to rest; quaternion equality uses an angular
  tolerance, so `cleanup` no longer flattens half a degree of motion.
- The clip reducer re-measures after its last pass, and `max_keys` below the
  endpoint count is refused-and-flagged (`cap_below_endpoints`) instead of
  quietly returning the endpoints.
- `add_noise` rounds a fractional frequency up to a whole cycle, so the noise
  has no seam at the clip's end.
- `character_setup` puts its blend points at the **solved** speed and lists any
  speed it could not reach in `speed_warnings`.
- `walk_start` / `walk_stop` sample the cycle through a real `Animation` track,
  so a transition meets the cycle at the phase you asked for (nearest-key
  sampling snapped to whichever key was closer).
- The right foot's passing marker was parenthesised wrongly.
- `jump` no longer accepts a `foot_lift` override and `turn` no longer accepts
  `lean` / `toe_roll`: none of them were read, so they were accepted, reported
  as success, and did nothing. They are now refused with the valid key list.
- `sync` on blend spaces now lands on `sync_mode` (`SYNC_MODE_INDEPENDENT` /
  `SYNC_MODE_NONE`); the boolean property's setter is deprecated in 4.7.
- Resources are no longer passed to `EditorUndoRedoManager.add_do_reference` /
  `add_undo_reference` ("Do not use for resources" in the Godot docs). Node
  references — the documented use — are unchanged.

### Catalog and contract

- The rig family is split in two: `animation_rig` (promoted) and
  `animation_rig_modifiers` (the five `*_setup` ops, **not** promoted, because
  the Godot AI server promotes at most eight tools). Each half's schema is
  derived from the ops it owns, so neither advertises the other's parameters and
  each has headroom under the 8192-byte cap.
- Registration is **atomic** (`batch_register`): a rejected family no longer
  leaves earlier families committed and dispatchable while the server's tool list
  never hears about them, and a Godot AI reload re-registers automatically
  instead of dropping every tool until the editor restarts.
- A rejected registration now pushes an error naming the family, instead of a
  retry that ends in a warning about two tools that do not exist.
- The execution-contract flags were checked against the core's own documentation
  and were already correct — `deferred` is a capability declaration (only
  `inspect preview` defers, and the wrapper errors if a handler defers without
  the flag), `requires_writable` is a readiness gate, `undoable` gates
  `undo=true` `batch_execute`, and `timeout_ms` is the deadline on *every* call.
  They are now enforced too: tier-1 asserts `deferred` matches the ops marked
  `"defers": true` and that every `timeout_ms` is inside the core's range, so a
  flag cannot drift away from behaviour.
- The tier-1 registry check grew teeth: every op's `params` **and** its
  `example` keys must be declared in that family's schema (forwarder ops may use
  their target op's keys, and those are checked against the target). It caught
  three examples that had drifted.
- A new CI gate reports a suite that fails to load instead of skipping it: a
  parse error in one test file used to leave the run green with 25 tests missing.

### Tooling

- `tools/test_tier1.ps1` imports the project first, so a fresh checkout no longer
  fails the audio-fixture suite on an unimported resource (the failure CI hit on
  Linux).
- The release zip includes `LICENSE`.
- All 43 call examples in `docs/tool-reference.md` used the envelope
  `{"op": "<op or family>", "params": {...}}`, which nothing accepts — the
  promoted tools are called by name in a `tool` field, as the README shows. They
  now use the canonical shape, and since that file is hand-written, tier-1 checks
  that every example names a real promoted tool.
- Docs, `CHANGELOG.md` and the ROADMAP are current; `docs/op-index.md` is
  generated from the registry and checked by tier-1.

### Scene safety (the second half of the audit)

- A nested target now gets a correct modifier-relative `NodePath`. The path was
  built from the target's bare *name*, which only resolved for a target sitting
  directly under the scene root — one at `Rig/Targets/HandTarget` produced a path
  to some other node. It is now derived from the skeleton to the real target, or
  to the parent a marker is about to join.
- `look_at_setup` markers get collision-safe names like the IK markers already
  did. Two look-ats asking for `LookAtTarget` used to collide: Godot renamed the
  second marker while the modifier's target path still said the original name,
  so the second look-at drove the **first** target.
- A graph op no longer falls back to an unrelated `AnimationTree`. With a player
  named and no tree of its own, the lookup returned the first tree in the scene,
  so `state_machine` / `blend_space` / `wire` built the graph on somebody else's
  player and reported success. The named player now gets its own tree, and
  `graph_get` names the existing trees so the caller can pick one.
- A recursive `blend_tree` spec is wired to its `output` node (and the reply
  reports which node it wired). An unconnected `output` builds cleanly, reports
  no issue, and then evaluates to nothing.
- Every file the toolkit writes is confined to `res://animation_toolkit/…` with a
  plain file name. `res://`, `user://`, absolute paths, `..` escapes and a
  project file like `res://project.godot` are refused with a message naming the
  allowed root.
- `rig_chain` refuses a bone name containing `/` or `:` before committing
  anything: such a name breaks every `Skeleton3D:<bone>:<property>` track path
  built from it. Dots are unaffected (`B-upperArm.L`).
- `pose_apply` and the six setup ops refuse outright when there is no editor undo
  history, instead of applying and reporting `undoable: true`. The rollback
  helper never claims a rollback it could not perform.
- Fixed the rollback helper itself: `EditorUndoRedoManager` has no `undo()` (that
  is on the history's `UndoRedo`), so a failing verification used to crash
  instead of returning its error.

### Tests
191 editor tests (8 suites) and 12 tier-1 suites, all passing. Four tests that
encoded a bug were repaired rather than the bug: a curve-less `Path3D` was
accepted for spline IK, a wrapped instanced retarget target was expected to
work, a 1.5 s contact time was expected inside a 1 s clip, and the punch test
asserted a per-bone twist magnitude that the detected-chain fix legitimately
changed. The suite's own temp files moved under `res://animation_toolkit/`,
which is where the write confinement now requires them to live.
