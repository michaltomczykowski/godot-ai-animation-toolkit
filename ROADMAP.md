# Roadmap — from presets to a real animation toolkit

Status: **phases 0-17 done, shipped in v1.11.0**; Phase 18 open
remediation's first half: every doc-ambiguous claim was settled by a failing
test and **all four were true**, so look-at angles are radians now, the audit
survives a blend tree, a retarget target nested in a wrapper is refused instead
of accepted and inert, and spring collision paths resolve through the simulator.
The rule underneath all of it: **no setup reports success it cannot confirm** —
the modifier ops verify their own wiring after the commit and roll the action
back if it did not take. `dry_run` is now side-effect free including file writes
(caught by a table-driven test), the rig family is split so all nine stay
reachable under the server's eight promoted slots, registration is atomic and
survives a Godot AI reload, and a CI run can no longer go green with a test file
that failed to load. The remaining scene-safety pass is also in: nested targets
get correct modifier-relative paths, look-at markers get collision-safe names, a
graph op never borrows another player's tree, a recursive blend tree is wired to
`output`, writes are confined to `res://animation_toolkit/...`, and `rig_chain`
refuses bone names that would corrupt track paths. Phase 16 is finished: the
execution-contract flags (`deferred` / `requires_writable` / `undoable` /
`timeout_ms`) were checked against the core's own documentation and were already
correct, and the tier-1 suite now enforces the two that can drift. Phases 17
(motion quality) and 18 (golden verification) follow.
Last updated: 2026-09-25.

Phase 3 note: the generators landed as their own family, `animation_fx`, instead
of growing the `animation_presets` schema to ~60 params. The "one tool per
family" rule from the decisions section still holds — there is just one more
family than originally planned, and the released presets tool is unchanged.

The addon started as nine one-call presets (`animation_presets`). This is the plan
to grow it into a full, agent-native animation toolkit: declarative clip specs,
clip editing, inspection, animation graphs, a project library, and later rigs.

## Decisions (locked)

- **All phases ship, in order.** Each phase is a release with ops, tests, docs and
  a recorded demo.
- **Four tools by family**, one op registry as the single source of truth:
  `animation_presets` (create), `animation_edit` (mutate), `animation_graph`
  (AnimationTree), `animation_inspect` (read-only).
- **Keyframe/procedural first**; character/rig authoring (Phase 6) comes after.
- Self-contained: public Godot APIs only, no core Godot AI animation internals.
  Godot 4.5–4.7, Godot AI >= 4.1.0.
- Every op: one scene-pinned undo action, typed values via `ValueCodec`, precise
  error codes, headless-testable pure math in tier-1.

## Why (the gap core does not cover)

Core `animation_manage` owns low-level authoring (create player/animation, add
property/method tracks, `create_simple`, list/get/validate, play/stop, autoplay,
plus fade/slide/shake/pulse presets). The toolkit sits above and beside it:

| Layer | Missing before this roadmap |
| --- | --- |
| Spec engine | Keys were built ad hoc; clips were not data |
| Edit | No retime/retarget/reverse/mirror/offset/ease/trim/split/merge |
| Graph | No AnimationTree/state machine/blend space authoring |
| Inspect | Nothing semantic (describe/audit/dry_run) |
| Library | Nothing persisted per project |

## Phase 0 — Foundation (done)

- `spec/clip_spec.gd` — declarative clip data: tracks, typed keys, transitions,
  length, loop mode, markers.
- `spec/spec_builder.gd` — spec → `Animation` (typed keys, named transitions).
- `spec/spec_modifiers.gd` — pure functions over specs (retime/reverse/mirror/…).
- `spec/spec_io.gd` — spec ↔ `Animation` (refuses types it cannot represent).
- `registry/op_registry.gd` — op descriptors (name, family, summary, params,
  example). Drives the tool descriptions, schemas, `docs/op-index.md`, and the
  tier-1 drift checks.
- Handler split: presets live in `handlers/generate.gd`; `handlers/edit.gd` is
  the edit family; both share `handlers/animation_tool_base.gd`.
- Tool split: `plugin.gd` registers one spec per family from the registry.
- CI: the harness runs **all** toolkit suites, not just `animation_presets`.
- Tier-1: 423 spec-engine checks (modifier math, spec ⇄ Animation round-trips,
  registry/schema/docs drift) alongside the 40 existing value-codec checks.

## Phase 1 — `animation_edit` (done)

Operates on any clip in any AnimationPlayer, including hand-authored ones.

| op | What it does |
| --- | --- |
| `retime` | Percent / scale-to / set-length, keys and clip length together |
| `retarget` | Rename one track path, or bulk prefix remap for node renames |
| `reverse` | Play a clip backwards (times mirrored about length) |
| `mirror` | Per-axis negation with optional pivot (typed: position/rotation/scale) |
| `offset` | Shift all keys in time, optionally wrap |
| `ease_range` | Set transition on keys in a time range |
| `set_interp` | Set key interpolation in a time range |
| `trim` | Cut keys outside a time range, keep/rename |
| `split_at` | Two clips at a time (tail keeps the name) |
| `merge` | Concatenate clips (optionally into a new name) |
| `amplitude` | Scale key deltas about a baseline |
| `loop` | Set loop mode / autoplay-safe loop fixups |
| `key_edit` | Add / set / remove individual keys |
| `cleanup` | Drop duplicate/redundant keys, drop empty tracks |

All: one undo action, existing loop mode and autoplay preserved.

## Phase 2 — `animation_inspect` (done)

`describe`, `timeline`, `audit` (broken paths, zero-length, duplicate keys, loop
seams, autoplay conflicts, unused clips, constant tracks), `compare`, `stats`,
`dry_run` (any presets/edit op reports its result without committing), `help`.
Read-only, so it never touches the undo stack; findings carry a `fix` hint naming
the op that resolves them. `dry_run` is also available as a param on the presets
and edit tools themselves.

## Phase 3 — `animation_fx` generators (done)

16 ops across four groups, on the same spec engine:

- feedback: `shake` (seeded, decaying), `zoom_punch`, `hit_flash`, `damage_bar`
- UI: `typewriter`, `progress_fill`, `counter` (method track), `dialog_pop`,
  `transition` (fade/wipe, pivot recentered)
- motion: `wave` (per-target phase), `spring` (damped step response),
  `pendulum`, `path_follow` (Path2D/Path3D sampling)
- sprites/audio: `flipbook`, `sprite_frames` (spritesheet -> SpriteFrames),
  `audio_cue`

## Phase 4 — `animation_graph` (done)

State machine build (states, transitions, xfade, conditions, advance/switch
modes), blend space 1D/2D, recursive blend trees (`blend2`/`blend3`/`add2`/
`add3`/`one_shot`/`time_scale`), `wire` (create/configure the AnimationTree,
set parameters), `graph_get` (dump + missing-clip/inactive-tree issues), plus
`locomotion`, `one_shot_layer` and `additive_lean` setups. Godot's implicit
`Start`/`End`/`output` nodes are filtered from counts and dumps; state machines
report a `start_hint` because the start state is not persisted.

## Phase 5 — `animation_library` (done)

`template_save/apply/list/delete` on `res://animation_toolkit/library.json`
(templates store a presets/fx op + params, applied later with overrides), and
`spec_export/import/apply` for a versioned, typed JSON clip format - including
track remapping so a spec can be applied to another node. File writes stay out
of the undo stack; clip creation is one undo action.

## Phase 6 — rigs (later) → v0.8+

Skeleton2D/Bone2D chains from a node tree, IK (CCDIK/FABRIK/two-bone), spring
bones, pose save/apply/blend, then procedural character recipes (`walk_cycle`,
`idle_breathing`, `blink`).

## Phase 6 - `animation_rig` (done)

The last roadmap item, deliberately split into three releases. **Locked
decisions**: three sub-phases; 3D-first (2D IK is *Experimental* in Godot 4.7);
scope = bone chains + poses + IK + springs + **retargeting** (no automatic
skinning/skin weights); tests and CI run on rigs the toolkit builds itself, with
the committed `Human Character Dummy` pair (`test_project/models/human_dummy/`)
as the real-character fixture for tests and demos.

Why this is not a new engine: Godot stores bone animation as
`TYPE_ROTATION_3D` / `POSITION_3D` / `SCALE_3D` tracks at paths like
`Skeleton3D:B-thigh.R`, with pose rotations as local-to-parent quaternions -
exactly what `ClipSpec` already stores and what `spec_json` round-trips. Bone
clips therefore inherit every existing op (`retime`, `mirror`, `reverse`,
`amplitude`, `spec_export`, templates) from day one.

Verified API surface (Godot 4.7 docs + the dummy import):

| Area | API |
| --- | --- |
| Skeleton3D | `add_bone`, `set_bone_parent` (parent < idx), `set_bone_rest`, `localize_rests`, `find_bone`, bone metadata, `create_skin_from_rest_transforms` |
| Pose | `set/get_bone_pose_rotation` (Quaternion, local to parent), `_position`, `_scale`, `get_bone_global_pose/rest`, `reset_bone_pose(s)`, `set_bone_enabled` |
| Modifiers | `SkeletonModifier3D` is a child of the Skeleton3D; `active` (default true), `influence`; runs after the AnimationMixer; `modifier_callback_mode_process`, `advance(delta)`, `modification_processed` |
| 3D IK | `IKModifier3D` -> `TwoBoneIK3D`, `ChainIK3D`; indexed settings (`setting_count`, `settings/<i>/...`): root/middle/end bone names, `set_target_node`, `set_pole_node`/`set_pole_direction(_vector)`, `set_extend_end_bone`, `set_use_virtual_end` |
| Springs | `SpringBoneSimulator3D` chains (root/end bone, center from, per-joint stiffness/drag/gravity/radius, damping curves, collision lists, `reset()`, `external_force`); docs warn scaled skeletons misbehave |
| Retargeting | `RetargetModifier3D` (child of the *target* skeleton; the source skeleton must be its parent node), `profile` (`SkeletonProfileHumanoid`), `enable` flags, `use_global_pose` |
| 2D rig | `Bone2D` (`rest`, `apply_rest`, `set_bone_angle`, `set_length`, autocalculate), `SkeletonModificationStack2D` + `SkeletonModification2DTwoBoneIK`/`CCDIK`/`FABRIK`/`Jiggle` (**Experimental**) |

### 6a - poses (done, v0.8.0)

| op | What it does |
| --- | --- |
| `pose_save` | Capture a skeleton pose (3D bones / 2D bones) inline and/or to `res://animation_toolkit/poses/<name>.json` |
| `pose_apply` | Write a pose onto a skeleton: `blend` 0-1, `bones` subset, `mirror` (L/R), `reset_first` |
| `pose_blend` | Pure pose math: slerp/lerp between poses, mirror, rest normalisation |
| `pose_to_clip` | Keyframe `[{pose, time, transition?}]` into a clip (one rotation track per bone) |
| `rig_get` | Dump bones/rests/poses, modifier stack, spring chains + issues |

### 6b - rigs, IK, springs, retargeting -> v0.9.0

**Done:** `rig_chain` (bones from a spec or a Node3D/Node2D subtree, on a new or
existing skeleton), `ik_setup` (3D `two_bone`/`ccdik`/`fabrik`/`jacobian`/
`spline`, target marker created at the chain tip, optional pole), `spring_setup`
(SpringBoneSimulator3D, one setting per spring entry, `end_bone` defaults to the
root's leaf), `look_at_setup` (LookAtModifier3D: bone, target, forward axis,
origin, limits, secondary rotation, duration) and `retarget_setup`
(RetargetModifier3D + `auto`/`humanoid`/`res://` profile, target moved under the
modifier, mapped/unmapped bone report). All modifiers are created **inactive**
(opt-in), rig ops warn about scaled skeletons, and the new nodes are committed
in one scene-pinned undo action. Covered by 10 new editor rows (125 total) and
1680 tier-1 checks.

**Done (v0.9.0):** demo scenes (IK reach, spring arm, head look-at), the 0:49
video, and the release with the zip and all eight demo videos. 2D IK/spring/
look-at stay unsupported on purpose: the `SkeletonModificationStack2D` path is
Experimental in Godot 4.7, so those ops refuse 2D skeletons with a clear error
while 2D chains still work through `rig_chain` + poses.

#### 6b verified API (4.7.2 ClassDB, checked before coding)

- `SkeletonModifier3D` (base, Node3D): `active`, `influence`, `bone`,
  `set_bone_name()`; enums `BoneDirection`, `SecondaryDirection`, `RotationAxis`.
- `IKModifier3D` (abstract): `set_setting_count(n)` / `get_setting_count()` /
  `clear_settings()` / `set_mutable_bone_axes(b)` / `reset()` - solvers are
  indexed slots, so `ik_setup` grows one slot per spec entry.
- `TwoBoneIK3D` (instantiable): `set_root_bone_name(i, s)`,
  `set_middle_bone_name(i, s)`, `set_end_bone_name(i, s)`,
  `set_target_node(i, NodePath)`, `set_pole_node(i, NodePath)`,
  `set_pole_direction(i, SecondaryDirection)`, `set_pole_direction_vector(i, v)`,
  `set_use_virtual_end(i, b)`, `set_extend_end_bone(i, b)`,
  `set_end_bone_length(i, f)`, `set_end_bone_direction(i, BoneDirection)`.
  `ChainIK3D` is abstract; its joints derive from root -> end, readable via
  `get_joint_count(i)` / `get_joint_bone_name(i, j)`.
- `SpringBoneSimulator3D`: `set_setting_count(n)`; per setting
  `set_root_bone_name`, `set_end_bone_name`, `set_stiffness/drag/gravity/radius(i, f)`,
  `set_rotation_axis(i, RotationAxis)`, `set_rotation_axis_vector(i, v)`,
  `set_gravity_direction(i, v)`, `set_center_from(i, CenterFrom)`,
  `set_center_node(i, NodePath)`, `set_center_bone_name(i, s)`,
  `set_enable_all_child_collisions(i, b)`, `set_collision_count/path`,
  `set_exclude_collision_*`, per-joint `set_joint_*` (enabled by
  `set_individual_config`), `set_external_force(v)`, `set_mutable_bone_axes(b)`.
- Still to verify before their ops: `LookAtModifier3D`, `RetargetModifier3D`
  (+ profile classes), `SkeletonModificationStack2D` and the 2D modification
  classes, `Skeleton3D`/`Skeleton2D`/`Bone2D` bone-authoring calls for `rig_chain`.

### 6c - procedural recipes -> v1.0.0 (done)

**Done:** `walk_cycle` (thigh swing, knee bend, counter-swinging arms and
a hip bob, roles auto-detected from bone names or given explicitly),
`idle_breathing` (chest/spine breathing, head counter-move, hip bob), `blink`
(scale or rotate, several blinks per clip) and `bake_pose_sequence` (seeks the
player, runs the active modifiers through the skeleton update, keys the final
pose and restores the skeleton afterwards). Covered by 5 editor rows (130
total) and 1770 tier-1 checks.

**Done (v1.0.0):** the demo scenes (`demo_recipe_walk`, `demo_recipe_idle`,
`demo_recipe_bake`), the 0:49 video, and the release with the zip. Recording
the demos surfaced three fixes, all shipped in the same release:

- `walk_cycle` gained `arm_down` - a T-pose rig otherwise walks with its arms
  horizontal.
- `bake_pose_sequence` never actually sampled the source clip: `seek()` on a
  player that was never played does nothing, so every bake was the rest pose.
  It now resolves the source (param/current/assigned), plays it and seeks.
- the same op now captures the *final* pose: modifiers only run in the
  skeleton's deferred update and their result is readable only inside
  `modification_processed`, so each sample nudges
  `NOTIFICATION_UPDATE_SKELETON` and keys what the signal handler captured
  (`Skeleton3D.advance()` does not run modifiers).

One release-blocking find: the rig family's `params_schema` had grown past the
Godot AI server's 8192-byte cap (python `json.dumps` measures ~5% larger than
Godot's compact `JSON.stringify`), and one over-cap definition drops the whole
catalog entry for that session - `animation_rig` was silently absent. The
schema is trimmed under the cap and the tier-1 registry check now measures with
the server's separators.

### Phase 7 - exercise recipes -> v1.1.0 (done)

Requested after 1.0.0, shipped as a small feature release on top of 6c:

- `jumping_jack` — arms from the rest pose to overhead (`amplitude`), thighs
  spread (`stride`), hips rise (`bob`).
- `squat` — the hips drop by `bob` metres while each leg is solved with the law
  of cosines so the ankles stay at their rest positions (planted feet, knee
  forward), arms easing forward.
- `punch` — guard, `cycles` alternating straight punches along the rig's own
  facing direction (ankle -> toe), a per-punch chest/spine twist and a slight
  crouch.

Shared machinery: `_arm_down_delta` grew into a general aim helper (rotate a
bone from its rest direction toward a world direction, clamped so it never
rotates past the target — T-pose and A-pose rests both work), role detection
learned `forearm_`/`toe_`/`spine` and now prefers the upper arm over a shoulder
bone deterministically, and the rig schema was trimmed again to stay under the
server's 8192-byte cap. Audit fixes folded in: `bake_pose_sequence` refuses
bakes past 1200 samples and the rig tool allows 30 s calls; the tool reference
documents the bake side effects.

Covered by 3 editor rows (133 total) and 1815 tier-1 checks; video
`animation_toolkit_exercises_demo.mp4` (0:49) on the v1.1.0 release, plus the
3:12 `animation_toolkit_full_showcase.mp4` compilation for the repo page.

Post-release examples (also on v1.1.0): `demo_menu.tscn` - a living game menu
where every reaction (entry stagger, hover pop via a saved template, press
bounce + flash, page wipe, loading bar + counter, dialog-popped options and
credits cards closed with `animation_edit reverse`, quit shake, outro) is an
ordinary toolkit clip on one of 24 animation players over a procedural aurora
shader and GPU motes, driven by synthetic mouse input from a small script.
Video: `animation_toolkit_menu_demo.mp4` (0:47).

### Phase 8 - motion and clip quality -> v1.2.0 (done)

Requested after v1.1.0: the procedural dummy animations were stiff (every bone
key was linear because `spec_builder` silently dropped per-key transitions on
typed 3D tracks, and the recipes were 2–4 hand-tuned keys per bone). Phase 8
fixes the interpolation foundation and adds a real procedural motion engine plus
clip-quality passes.

**Interpolation foundation (spec engine):**

- `spec_builder` forwards per-key transitions on `POSITION_3D`/`ROTATION_3D`/
  `SCALE_3D` tracks (named transitions included), and `spec_io` reads them back.
- `spec_modifiers.sample_track` honors Godot's `Math::ease` transition shapes and
  delegates cubic/nearest tracks to an engine-backed exact sampler
  (`sample_track_exact` / `build_track_animation` / `sample_built_track`).
- `clip_spec.align_quaternions` + `clip_spec.close_loop` are applied by
  `_commit_procedural_clip`: loops close exactly and consecutive rotation keys
  share a hemisphere.

**`animation_motion` (8th tool, new family):**

- `spec/motion_drivers.gd` (pure, tier-1): periodic seeded noise, channel
  curves with lag, world-space → bone-local rotation conversion, the aim and
  knee solves, smoothstep/smoothing, and the offline spring (`follow_spring`).
- `spec/motion_specs.gd` (pure): walk/run/idle cycle builders + style bundles.
- `handlers/motion.gd`: `walk_cycle`, `run_cycle`, `idle_cycle`, `cycle`,
  `secondary_motion`; dense sampling (24/s), two-bone leg IK with a flat-stance
  foot, pelvis bob/sway/yaw/roll, counter-rotating torso, arm swing with elbow
  lag, head stabilisation, T-pose arm auto-lowering, styles/overrides, optional
  root motion with the implied `speed`.
- `handlers/bone_animation.gd`: shared skeleton/role resolution, aim/knee math
  and the procedural-clip commit path, inherited by `animation_rig` and
  `animation_motion` (rig.gd shrank by ~250 lines).

**Clip-quality passes (`animation_edit`):** `smooth`, `resample`, `add_noise`,
`overlap`, `layer` — seeded micro-motion, per-limb follow-through, additive/mix
layering and engine-exact resampling, all pure spec transforms in
`spec/quality_modifiers.gd`.

**`animation_inspect`:`motion_report`** — per-track key density, peak
speed/acceleration, loop-seam pops, quaternion hemisphere flips and constant
tracks, each finding carrying a `fix` hint (added to `spec/quality_modifiers.gd`
as pure analysis).

**Release:** v1.2.0 ships the zip plus the 0:44
`animation_toolkit_motion_demo.mp4` (walk / run / idle recorded on the dummy).
README and the Discord post now link only three videos: the full 3:12 showcase,
the menu demo and the dummy motion showcase.

**Refinement (v1.2.1, shipped):** the arm chain got a proper **sagittal hinge**
(`motion_drivers.world_delta` conjugates by the *animated* rest basis) - the
elbow now flexes forward instead of curling across the body, which the old
rest-frame conversion caused once `arm_down` had rolled the arm. Walk/run elbow
tuning was reworked (straight at the back, bending at the front), the auto
arm-down is 78°, and `idle_cycle` was rebuilt around a pronounced look-around
and torso twist (`look` / `twist` overrides, defaults 18° / 12°) over the
breathing layer; the jaw-blink player was removed from the idle demo. The
motion showcase video was re-recorded on v1.2.1.

**Coverage:** tier-1 grew from ~1815 to 2138 checks (motion drivers, quality
modifiers, typed-track transitions, sampler); the editor suites gained
`animation_motion` (9 tests) plus quality-pass and motion-report tests
(144 rows). New demos: `demo_motion_walk`, `demo_motion_run`,
`demo_motion_idle`.

### Phase 9 - the motion pack -> v1.3.0 (done)

Goal: more moves, smoother gaits and a motion pipeline that is genuinely useful
for agents generating character animation in Godot - not just one-shot presets.

- **Speed-driven gait.** `walk_cycle` / `run_cycle` / `strafe_cycle` accept a
  target `speed` (m/s) and solve stride from it
  (`stride = asin(speed * stance * duration / (2 * leg_length))`), clamp at a
  safe stride cap, scale foot lift, and return `speed`, `stride_used`,
  `cadence` and `warnings` (with a suggested duration when the speed is
  unreachable at the requested duration).
- **`jump`** - anticipation, launch, air arc, descend, land absorb, recover;
  feet planted before takeoff and after landing; optional `distance` travel;
  `takeoff` / `apex` / `land` markers.
- **`turn_cycle`** - in-place turn (`angle`, direction) with anticipation, a
  stepping foot, stance feet held at their rest orientation, slight overshoot
  settle; `anticipate` / `step` / `settle` markers; optional rotation root
  motion.
- **`walk_start` / `walk_stop`** - short transitions whose end/start pose is
  sampled from the cycle at `phase`, so they blend frame-for-frame into a gait.
- **`strafe_cycle`** - sideways gait (leading foot steps out, trailing closes)
  with the knees still facing forward, pelvis shifting along the travel axis.
- **Toe roll + shoulders.** Ankle pitch curve (heel strike toe-up -> flat ->
  toe-off toe-down) and a world-held toe bone during toe-off; new
  `shoulder_l/r` role with a small clavicle swing synced to the arm.
- **Phase markers.** Cycles emit `contact.L/R`, `toe_off.L/R`, `passing.L/R`;
  new `animation_edit marker` op (add/remove/move/clear) so agents can hook
  gameplay events and phase-sync blends.
- **Root-motion polish.** `root_motion=true` also sets
  `AnimationPlayer.root_motion_track` inside the same undo action and returns
  the apply snippet (`get_root_motion_position/rotation` + accumulators).

Demos: jump, turn, strafe scenes, a re-recorded walk/run with toe+shoulders,
and a new video.

**Done (v1.3.0):** speed-driven gaits with stride solving and warnings, `jump`,
`turn_cycle`, `strafe_cycle`, `walk_start`/`walk_stop`, heel/toe roll with the
toe held through toe-off, a clavicle role, phase markers on every gait, and
root-motion wiring inside the same undo action. 7 new editor rows (152 total),
tier-1 at 2241 checks; demos `demo_motion_jump`/`turn`/`strafe` and the 0:40
`animation_toolkit_motion_pack.mp4` on the release.

### Phase 10 - understand & drive -> v1.4.0 (implemented)

Make agents effective on the *first* try: understand a rig, verify motion
numerically, and get a playable character in one call.

- **`animation_inspect rig_profile`** - detected roles with candidates, T/A
  pose, limb lengths/reach, facing and lateral axes, capabilities (walk, run,
  jump, turn, strafe, blink, secondary, IK, springs), missing roles, warnings
  (scaled skeleton, zero-length bones) and suggested next ops. `save=true`
  writes `res://animation_toolkit/rig_profiles/<name>.json`; rig/motion ops
  accept a `profile` param so role detection is never guessed twice.
- **`animation_motion character_setup`** - one call, one undo: build idle +
  walk + run (optionally jump/turn), wire the locomotion AnimationTree, set
  root-motion tracks, and return the speed parameter path plus a game-side
  apply snippet.
- **`animation_inspect sample`** - FK probe: world positions (and optional
  euler rotations) of requested bones at N times, plus derived foot heights and
  contact windows, so an agent can verify motion without rendering.
- **Library templates for motion/rig** - `template_save/apply` extended to
  `animation_motion` and `animation_rig` calls (save a tuned style or recipe).

Shipped implementation details:

- `spec/rig_analysis.gd` is the new pure core: name-based role detection with
  ranked candidates, arm-pose classification (T/A/arms_down), capability and
  missing-role maps, sample-time/contact-window math and rig-profile
  validation. `bone_animation._resolve_roles` now delegates to it, so the
  recipes, rig_profile and motion share one detection implementation.
- `_resolve_roles` resolves explicit `roles` > saved `profile` > detection;
  profile bones missing on the skeleton fall through to detection.
- Graceful degradation: the `character_setup` blend-space positions are the
  clips' solved speeds; the tree is created inactive like the graph ops; with
  `include_jump` it wraps the blend space in a blend tree and reports
  `parameters/Base/blend_position` / `parameters/OneShot/request`.
- `GraphBuilders.wrap_one_shot` builds the jump layer; `character_setup`
  commits clips + tree + root-motion properties in one scene-pinned action
  (`_stage_animation_changes` was split out of `_commit_animation_changes` so
  clips and nodes bundle into the same undo step).

Coverage: 6 new editor rows (158 total) and tier-1 at 2437 checks
(`tier1_rig_analysis.gd` plus the `wrap_one_shot` checks). Docs regenerated.

**Done (v1.4.0):** demo scene `demo_character_setup.tscn` (the dummy circles the
scene at the blend speed, root motion driving the travel, with jump requests on
a schedule), the 0:31 `animation_toolkit_character_setup.mp4`, and the release
with the zip and the video.

Deferred (candidate v1.5): `crouch_walk`, gesture pack, foot ground-lock for
imported clips, twist dispersion (BoneTwistDisperser3D), gaze baking,
angular-velocity limiting, preview-scene builder.

## Phase 11 — contact authoring and visual verification (v1.5.0, shipped in v1.6.0)

The rejected door/punch demo exposed three authoring gaps, all now filled:

1. **Contact keys** — `pose_to_clip` keys accept `aim: [{chain, target, pole?}]`.
   `spec/pose_solver.gd` solves the three-bone chain analytically (law of
   cosines in the plane spanned by the root-to-target line and the pole hint) and
   the *keys* carry the solution, so a hand or foot holds a world-space contact
   with no modifier and no runtime target node. The live skeleton is only posed
   to solve and is restored. Tier-1: `tier1_pose_solver.gd` (34 checks over FK,
   reach, pole, base-bend and clamping).
2. **Multi-step pivots** — `turn_cycle steps: 2` splits a 180-degree turn into
   two pivots with the opposite foot lifting in each, so it reads as weight
   shifts rather than a spin. `steps: 1` is byte-identical to the old output.
3. **Visual verification** — `animation_inspect preview` renders the posed
   character to PNGs at clip times in a private offscreen viewport (one editor
   frame per image, hence a deferred reply; headless editors report that they
   cannot rasterise). The edited scene is never touched.

Also in this phase: the `animation_rig` schema was trimmed back under the
8192-byte server cap after `aim` was added (323 bytes of headroom), and the
`animation_inspect` spec is registered as deferred-capable so the preview
reply is accepted.

Status: shipped in v1.6.0 — ops, tier-1 checks, editor suites and docs. **No
demo recording**: the showcase was dropped (see below).

**Dropped: the door/punch demo.** It was rebuilt twice on the new chain tooling
and still read as broken on screen, so the scratch scene, its builder suite and
the draft recordings were deleted rather than shipped. What the phase produced is
still useful on its own — contact keys, split pivots and offscreen previews are
verified by tests, not by a film — and `animation_inspect preview` is the tool
for looking at a clip next time. Demo recordings are now optional per phase:
only when a demo earns its keep.

### Risks / mitigations

1. Editor-time modifier processing (the AnimationTree lesson): verify first,
   create inactive by default, document opt-in activation.
2. 2D modification stack is Experimental: 3D-first, graceful errors, stable
   pose/clip path covers 2D needs.
3. Undoing bone-list edits: snapshot bones/parents/rests/poses and restore in
   the undo branch.
4. IK results are only readable via `modification_processed`: capture posed
   (pre-modifier) values in `pose_save`; `bake_pose_sequence` handles IK.
5. Scaled skeletons break springs: warn in `spring_setup`/`rig_get`.
6. Every unverified setter name gets confirmed against the live 4.7 ClassDB
   before it is coded.

## Phase 12 — spine chain and twist distribution (v1.6.0, done)

The door/punch demo's second pass showed the real culprit behind the "spinning
spine" the demos kept showing: every recipe hard-coded its own per-bone twist
multipliers, and a couple of them compounded the *running* total. The fix is a
shared chain plus a shared distributor, so a parameter means the same *total*
rotation on a 3-bone and a 6-bone spine.

1. **Chain detection** — `RigAnalysis.spine_chain(parent_of, roles, max_bones)`
   walks down from the hips through the head's ancestry (with a torso-named-child
   fallback) and returns the torso chain; both families take an explicit
   `spine_chain` when given, validated as one parent chain. Resolution lives in
   `bone_animation.gd: resolve_spine_chain` and reaches `ctx.spine_chain`.
   Tier-1: `tier1_spine_chain.gd` (16 checks).
2. **Twist distributor** — `spec/spine_twist.gd` turns a total in degrees into
   per-bone degrees (`amplitudes`/`distribute`) with weights, a `spread` knob,
   an optional per-bone clamp, and `lags` for the phase ramp. Tier-1:
   `tier1_spine_twist.gd` (59 checks).
3. **Recipes wired through it** — `idle_keys` (the old spine 0.5 + chest 1.0 +
   harmonics, which summed to ~2x the parameter, is now one shared twist with a
   hips weight shift), `gait_keys` (chain-weighted counter-rotation; the
   `chest_yaw` override was dead because a local of the same name shadowed it),
   `turn_keys` (the bounded per-step lead now ramps up the chain and the head
   trails it), `jump_keys` (the lean spreads up the whole chain), and in the rig
   family `idle_breathing` (the whole chain breathes) and `punch` (`amplitude` is
   now the *total* torso twist).
4. **`twist_setup`** — the engine does the distributing: a
   `BoneTwistDisperser3D` over the detected or explicit chain with the `even` /
   `weighted` modes, `weight_position`, `damping` and `twist_from_rest`, created
   inactive like every modifier setup. Godot 4.7 only builds a disperser's joint
   list once the modifier has been in the tree for a frame (and has no bone-name
   setter), so custom per-joint amounts stay in the Inspector; the op reports the
   joint bones it will use.
5. **New params** — `spine_chain` and `twist_spread` (motion), `spine_chain` and
   `disperse` (rig). The rig schema was trimmed to 341 bytes of headroom to fit
   them under the 8192-byte server cap.

Editor suites: 163 tests, including a new regression that a 40-degree idle twist
never puts more than a share on one bone (`test_idle_twist_is_shared_over_the_
spine_chain`), the `twist_setup` op test, and the existing turn-step bound.

### Phase 12 risks / mitigations

1. Godot 4.7 has no `TwistModifier3D`; the disperser's setters are per-setting
   (`set_disperse_mode(index, mode)`) and were confirmed against ClassDB first.
2. A sine channel swings twice its amplitude: "inside the requested twist" means
   peak-to-peak, which the tests state explicitly.
3. Recipe defaults are in the same units as before (the idle's `twist` default
   moved 12 -> 22 so the *total* matches the old summed output).

## Phase 13 — prove the motion, then ship a lighter clip (v1.7.0, done, released 2026-09-24)

The dropped demo made one thing obvious: judging motion by eye costs a whole
recording per attempt. Phase 13 turns the two soft spots into numbers.

1. **`animation_inspect motion_audit`** — plays the clip on a Skeleton3D (the
   scene is posed and restored, never saved) and grades it: per foot the
   ground-contact windows and the horizontal slide while planted, plus the hips'
   bob and travel. Every check is pass/fail against a budget (`max_slide` 5 cm,
   `max_hip_bob` 12 cm) with a `fix` hint, and the response carries the foot
   traces so a bad cycle can be read, not guessed. Two definitions matter:
   - **Contact** is "within `contact_threshold` (5 mm) of the foot's *rest*
     height", not "near the lowest sample" — a swing arc dips to the minimum
     twice per cycle, so the old rule graded the swing as contact.
   - **Slide** is the foot's *net* displacement inside a window, not the
     accumulated path: lift, swing and land is a step, creep across the floor is
     a slide. Both the net and the path are reported.
   A clip authored in place is reported as `in_place` (its stance foot travels
   with the body by design) and the check's `fix` points at `root_motion`.
   Pure math: `RigAnalysis.foot_slide(times, positions, threshold, ground)`.
2. **`animation_edit reduce`** — the other half: the procedural cycles ship with
   70+ keys per bone, and there was no way to slim them. `reduce` keeps the
   first/last key, measures the reduced track against every original key through
   the engine's own interpolator, and re-inserts the worst offender until the
   budget holds (`angle` degrees for rotations, `value_tolerance` units for the
   rest, `max_keys` as a cap). Nothing moves onto a new grid, so unlike
   `resample` the curve is preserved; the reply carries the keys removed and the
   worst measured error. Pure math: `QualityModifiers.reduce`.
3. **A real bug the audit found on day one.** A root-motion walk's stance feet
   were sliding backwards at the full body speed: `_foot_trajectory`'s rooted
   branch moved the stance target *with* the body instead of holding it still,
   and both feet shared one target. The leg rotations are aimed at the target
   with the hips already travelled, so holding the target still is exactly what
   plants the foot; the trailing foot now holds the point half a stride behind.
   Measured before: 0.30 m of slide per stance. After: **0.0 m**, asserted by the
   audit test, which also keeps a moonwalk fixture (the same clip with the hips
   pushed 3x faster) failing the budget.

Tier-1: 73 checks in `tier1_quality_modifiers.gd` (reduction budgets, engine-exact
error measurement, `max_keys`, slide definitions) and the registry/docs drift.
Editor suites: 165 tests, including the audit's pass/fail/in-place cases and the
`reduce` round trip with its undo.

### Phase 13 risks / mitigations

1. Contact and slide are only as good as the threshold: both are reported, and
   the traces are in the reply, so a wrong threshold is visible rather than
   silently wrong.
2. The audit poses a live skeleton, so it needs an open scene and a 3D rig; 2D
   and headless readers get the tier-1 math instead.
3. `reduce` is greedy, so a pathological track can stop above the budget when a
   re-insert stops helping; the reply's `worst_error` says so.

## Phase 14 — stable by default (v1.8.0, done)

A read-only audit of the 3D layer found a cluster of **setup ops that report
success and do nothing** (or the wrong thing), plus a CI job that only ran one
of the twelve tier-1 suites. Nothing here changes what a good clip looks like;
it makes the promised result the actual result. Delivered:

1. **CI runs the tests it claims to.** `ci.yml` ran only
   `tier1_value_codec.gd`, so eleven pure suites (motion drivers, pose solver,
   quality modifiers, rig analysis, spine, spec modifiers) never gated a
   release. The tier-1 list is now a matrix axis over the same twelve scripts
   `tools/test_tier1.ps1` runs, on both OSes, `fail-fast: false`.
2. **`spline` IK, implemented properly.** The advertised kind was configured
   like a target solver (`set_target_node`), which `SplineIK3D` does not have
   anywhere in its class chain — the op returned a valid path for a modifier
   that cannot move. It gets its own branch: a `Path3D` (created at the end bone
   when omitted), the real `set_path_3d(index, path)` setter, no marker target,
   no pole. The existing `target_path` param is reused, because the rig schema
   is within a few hundred bytes of the 8192-byte cap, and the Godot 4.7 API
   was confirmed against ClassDB first (the path setter is indexed, unlike the
   other solvers').
3. **IK chains and markers stop lying.** A newly added `IKTarget`/`IKPole` is
   renamed by Godot on a name clash while the stored `NodePath` keeps the old
   one, so the *second* leg or arm pointed at nothing; names are now allocated
   uniquely, and the markers are added before the modifier that references them
   (the old order made Godot warn "Pole node not found"). Chains are validated
   as chains: unique, ancestor-ordered, exactly three bones for `two_bone`,
   `[root, end]` for the chain solvers — a four-bone list used to build the
   target from the fourth bone and solve on the third. Default targets/poles
   come from the global **rest** frame, not whatever the editor was playing.
4. **Retarget fail-safes.** A zero-bone (or core-incomplete) map is an error,
   not a modifier that moves nothing; the reply lists bones unique to each side
   and mapped-parent mismatches; `move_target=false` configures the modifier
   that is already there instead of adding an inert second one (a pre-existing
   check made that path unreachable, which is why it was never noticed); a
   target that is an ancestor of the source is rejected; both skeletons' scale
   is reported, and global-pose mode says the per-transform flags are ignored.
5. **`bake_pose_sequence` became deterministic.** Each sample advances the
   skeleton by exactly the fps step — `advance()` accumulates and the deferred
   update consumes it, so springs integrate the same way twice — and stateful
   modifiers are reset first (two bakes of the same clip are now key-identical,
   asserted). It captures and restores *both* skeletons of a retarget and the
   player's animation, time and play state, and refuses to write a clip when no
   modifier reported in, instead of silently baking pre-modifier poses.
6. **Twist, chains, noise, loops, inputs.** Rejected the `damping` value that
   only exists in custom mode, `weight_position` outside weighted mode, and
   `twist_from_rest=false` with no reference quaternion; a two-joint range now
   sets `extend_end_bone` and warns instead of silently applying the twist
   whole, and `rig_get` reports the real joint list (`joints_pending` until
   Godot builds it a frame later). The explicit `spine_chain` is honoured
   instead of being replaced by a role-derived one. `pose_to_clip` converts the
   pole with the same full affine inverse as the target. `add_noise` uses one
   seeded axis per track instead of one per key. Loop closure applies to cyclic
   recipes only, so a one-shot turn, jump or `walk_start` keeps the endpoint the
   next clip continues from. Generation rejects non-finite parameters
   (including nested overrides) before anything is written.

### Phase 14 risks / mitigations

1. `SplineIK3D`'s 4.7 API was unverified until the editor was live; it is
   confirmed (`set_path_3d(index, path)`, and no target setter anywhere in
   `SplineIK3D -> ChainIK3D -> IKModifier3D`), and every queued setup call is
   now checked against ClassDB before the undo action commits, so a future
   engine rename fails as a typed error instead of inside the action.
2. The schema cap is the real constraint on new params, so Phase 14 reuses
   params (`target_path` doubles as the spline path) and documents the rest in
   the descriptor instead of growing the rig schema.
3. The bake's determinism claim is asserted, not assumed: two bakes of the same
   clip with a live spring must be key-identical, and the test runs in CI.
4. Godot resolves a disperser's joint list on a deferred frame, so the response
   labels its list as predicted and `rig_get` reports the real one with
   `joints_pending` rather than pretending a synchronous op can know it.

## Phase 15 — audit remediation: evidence, then correctness (v1.9.0, done)

**Batch 0 answered all four questions, and every claim was true:**

1. `AnimationNode` has no `get_child_count()` — `Invalid call` on any blend tree.
2. `look_at_setup` wrote `primary_limit_angle = 45.0` where the modifier wants
   0.7854 (radians).
3. A wrapped retarget target received **nothing** (`angle=0.000` inside
   `modification_processed`), while a bare direct child got `angle=0.700` — the
   arrangement was the problem, not the op. So: **refuse wrapped targets**.
4. `../../SpringCenter` did not resolve through the simulator; the collision path
   was empty.

**The failsafe is unconditional**, which is why the wrapped-target question could
not change user-visible behaviour: `ik_setup`, `retarget_setup` and spline IK
verify their own wiring after the commit and roll it back on failure, so a setup
either works or returns a typed error.

Everything in Batch 1 landed with coverage: the `SpineTwist` divisor (signs
preserved, scale honest), symmetric contact and honest `contact_time`,
detected-first `_torso_chain`, quaternion `scale_delta` from the baseline,
angular quaternion tolerance, the reducer's final re-measure and
`cap_below_endpoints`, engine-sampled walk transitions, refused-but-never-ignored
`jump`/`turn` override keys, `character_setup` blend points at solved speeds, the
noise cycle rounding, the right-foot passing marker — plus the repaired tests
(spline curve-less path, instanced retarget bake, impossible contact time, the
punch per-bone magnitude). The 1.5 s contact expectation and the identity
right-arm mirror case were rewritten rather than satisfied.

The post-commit verification and the first engine-doc fixes shipped in the same
release (below); see `CHANGELOG.md` for the itemised list.

### Phase 15 risks / mitigations

A second read-only audit (four passes, every engine claim adjudicated against
the Godot 4.7 class reference and the Godot AI core at
`src/godot_ai/services/promoted_tools.py`) found more defects in shipped
behaviour. Two of them are **doc-ambiguous**, so they are settled by evidence
before any code changes; everything else is verified with a file:line.

**Batch 0 - evidence first, no behaviour change.** Each test must fail before its
fix lands:
1. **Wrapped retarget target.** The docs say `RetargetModifier3D` transfers to
   "the child Skeleton" without saying whether that means a *direct* child, and
   `retarget_setup` moves the target's **scene root** so a skinned mesh keeps
   its binding. Test: wrap a target as `Node3D -> Skeleton3D` (the human-dummy
   shape), rotate a mapped source bone, capture inside
   `modification_processed`, and assert whether the target pose changed.
2. **Spring paths.** `center_node` and the collision/exclude paths are built
   relative to the `Skeleton3D`; the docs say a collision must be a child of the
   `SpringBoneSimulator3D` or "it has no effect". Test resolution *through the
   simulator*.
3. **Look-at limit units.** The docs say `primary/secondary_limit_angle` are in
   **radians**; the registry advertises **degrees** and the value passes through
   unchanged. Test the converted value on the modifier.
4. **AnimationTree walk.** `AnimationNode` is a Resource with no
   `get_child_count()`/`get_child()`, so `audit` dies on any scene with a blend
   tree. Test the audit against such a scene.

**The failsafe that answers the first risk.** Whether or not the evidence comes
out either way, no setup op may report success it cannot confirm: the
modifier-creating ops get a **post-commit verification** that checks the wiring
they just created (the target the setting resolves to, the bones that resolved,
the rows the keyframes landed in) and, when the check fails, **rolls the undo
action back and returns a typed error naming the fix**. A wrapped retarget
target therefore never yields "done, just inert": either the evidence shows it
works and the op keeps today's arrangement, or the op refuses it with an
actionable message.

**Batch 1 - pure-math correctness**, each with tier-1 or editor coverage:
1. `SpineTwist.amplitudes` guards its divisor with `divisor < 0.000001`, which
   fires for **negative** signed sums, so counter-rotation profiles are scaled
   by 1.0 instead of their own sum (`spec/spine_twist.gd:57-59`).
2. `RigAnalysis.foot_slide` treats a foot *below* the floor as contact
   (`y <= floor + threshold`, `spec/rig_analysis.gd:416`) and reports
   `contact_time = planted * period`, which over-counts by up to one period and
   skews `mean` (`:444-455`).
3. `_torso_chain` still prefers the scalar-role chain over the detected one, so
   a detected neck/intermediate is dropped by `idle_breathing`, `punch` and
   `twist_setup` (`handlers/rig.gd:1728-1744`).
4. `ClipSpec.scale_delta` scales quaternions from identity, ignoring the
   baseline every other branch honours, so `amplitude(factor=0)` snaps a
   non-neutral pose to rest (`spec/clip_spec.gd:387-388`).
5. Quaternion equality uses a cosine threshold, which is quadratic near
   identity, so `cleanup` flattens real sub-degree motion
   (`spec/clip_spec.gd:280-303`).
6. `QualityModifiers.reduce` returns two keys for `max_keys=1` (the endpoints
   are seeded before the cap) and can report a stale `worst_error`
   (`spec/quality_modifiers.gd:235-256`).
7. `walk_start`/`walk_stop` sample the gait with nearest-key lookup, so they are
   not frame-accurate at low `samples` (`spec/motion_specs.gd:702-764`).
8. `jump`/`turn` accept `foot_lift`, `knee_bend`, `lean` and `toe_roll` and
   ignore them; `character_setup` places blend points at requested rather than
   solved speeds; the right-foot passing marker lands in the previous stance
   (`spec/motion_specs.gd:409-423, 475-694`, `handlers/motion.gd:325-363`).
9. `add_noise` with a fractional frequency still breaks loop seams.
10. **Repair the tests that encode the bugs**: a spline test that hands in a
    curve-less `Path3D`, a retarget bake test that passes because the target is
    never driven, a foot-slide expectation of 1.5 s for a 1 s interval, a
    `_expect(true, ...)` that cannot fail, and a mirror test that never gives
    the right arm a distinct value.

### Phase 15 risks / mitigations

1. Batch 0 can change a decision: if a wrapped target *does* receive poses, the
   "refuse it" rule is dropped and only the test is kept. The post-commit
   verification above is unconditional either way, so no user ever gets a
   silently inert setup.
2. These fixes change generated output (twist scaling, contact metrics, `cleanup`,
   `reduce` caps). At the time this batch was written there were no golden
   fixtures, so it added explicit numeric assertions first - and the goldens have
   since landed (`test_project/tests/fixtures/golden_walk.json`), so a change like
   this now shows up as a number instead of "it looks a bit different".

## Phase 16 — audit remediation: engine and contract correctness (v1.10.0, in progress)

**Batch 2 - what the docs say the code does not do — DONE (shipped in v1.9.0):**
- Look-at limit angles are converted from the documented degrees to radians, and
  the unit is echoed in the reply.
- The `AnimationNode` walk uses the real per-type accessors instead of node
  methods, so a blend tree no longer crashes the audit.
- `Resource`s stop going into `add_do_reference`/`add_undo_reference`; the docs
  say "Do not use for resources". `Node` references (the documented use) stay.
- `AnimationNodeBlendSpace1D/2D.set_use_sync()` is deprecated in 4.7, so `sync`
  now lands on `sync_mode` (`SYNC_MODE_INDEPENDENT` / `SYNC_MODE_NONE`).
- Spring collision nodes are simulator children (reparented undoably) and the
  paths are built from the simulator, which is what Batch 0 proved.
- Retarget reconfiguration requires the existing modifier's parent to be the same
  source, so another skeleton's modifier is never hijacked.
- `graph wire` honours `create=false` instead of creating the tree the caller
  was checking for.

**Batch 3 - the Godot AI contract and scene safety — MOSTLY DONE (v1.9.0):**
- **Atomic registration and reload survival — DONE.** One `batch_register()` call
  (validate all, then commit, then notify once), a poll that notices the core
  replaced its singleton and re-registers, and an error naming the family when a
  registration is rejected. The old per-family loop could leave earlier families
  committed and dispatchable while the server's list never heard about them.
- **Schemas that match reality — DONE where it is expressible.** The registry
  check now validates every op's `params` **and** its `example` keys against that
  family's own schema (forwarder ops may use their target op's keys, and those
  are checked against the target), which caught three drifted examples. Per-op
  *required* lists are not expressible in one family schema; the handlers enforce
  them with typed `MISSING_REQUIRED_PARAM` errors, and the family-level
  `required` stays accurate for the family envelope (`op`).
- **Strict `dry_run` — DONE for the mutation points that matter, with a test
  that keeps it that way.** A table-driven test runs one op per family with its
  own `dry_run: true` and asserts the node tree, every clip, the undo-history
  version and the filesystem are untouched. It found two real leaks (the library
  file write and `rig_profile`'s profile write); both are fixed, and every file
  write in the library/rig/inspect handlers now goes through a guarded choke
  point. `preview` remains the one intentional writer and says so in its own
  error text.
- **Nine families — DONE.** `animation_rig` keeps poses, `rig_chain`, `rig_get`,
  the recipes and `bake_pose_sequence`; **`animation_rig_modifiers`** takes the
  five `*_setup` ops and is registered `promoted: false` (the server promotes the
  first `MAX_PROMOTED_TOOLS = 8` names, so one family has to give up its slot).
  Each half's schema is derived from the ops it owns, so neither advertises the
  other's parameters and each has headroom under the 8192-byte cap.
- **A green run no longer hides a dead suite — DONE.** The CI harness reports a
  `test_*.gd` that fails to load or instantiate instead of skipping it; a parse
  error in one file used to leave the run green with 25 tests missing.
- **Truthful batch metadata — VERIFIED CORRECT, now enforced.** The core's
  `McpCustomToolSpec` documents what each flag means, and all three are true
  here: `deferred` is a *capability* declaration (the handler may answer
  `{"_deferred": true}` and push the payload later, and `custom_tool_wrapper.gd`
  errors at call time if a handler defers without it) — only
  `inspect preview` defers, and `animation_inspect` is the one family with the
  flag; `requires_writable` is a readiness gate both sides honour (inspect is
  `false` correctly even though `rig_profile` writes a file, because the gate is
  about the *scene*); `undoable` gates participation in `undo=true`
  `batch_execute` and only inspect is `false`, which the new `_require_undo`
  guard now backs. `timeout_ms` is honoured on *every* call
  (`ctx.deadline_msec`) and is the server's own budget plus a 2 s margin, so the
  30 s on the rig/motion/inspect families is what a bake or a dense sample
  actually needs. The tier-1 suite now asserts `deferred` matches the ops
  marked `"defers": true` and that every `timeout_ms` is inside the core's
  500-120000 range, so the flags cannot drift from behaviour.
- **Scene safety — DONE.** `create=false` is honoured; nested targets get
  correct modifier-relative `NodePath`s (derived from the skeleton to the real
  target, or to the parent a marker is about to join, instead of from the target's
  bare name); look-at markers get collision-safe names like the IK markers
  already had; a graph op never falls back to an unrelated `AnimationTree` (it
  gives the named player its own tree, or names the existing ones); a recursive
  blend tree is wired to `output` and the reply says which node it wired; file
  writes are confined to `res://animation_toolkit/...` with plain file names; and
  `rig_chain` refuses `:` or `/` in a bone name before committing anything.
  `pose_apply` and the six setup ops now refuse outright when there is no undo
  history instead of promising `undoable: true`.

**Batch 4 - hygiene — DONE (v1.9.0):** the CI gate reports a suite that
fails to load (a green run can no longer hide a dead test file);
`tools/test_tier1.ps1` imports the project first, so a fresh local clone works;
the release zip ships the MIT `LICENSE`; `CHANGELOG.md` is rewritten for 1.9.0;
the tool reference documents the nine families, the non-promoted modifier half,
the dry-run guarantee and the self-verifying setup ops, and all 43 of its call
examples now use the canonical `{"tool": "custom_<family>", "params": {...}}`
envelope the README uses (they were `{"op": "<op or family>", ...}`, a shape
nothing accepts). That file is hand-written, so the tier-1 suite now checks its
examples name a real promoted tool. **Still open:** the test-project CI plugin
description.

### Phase 16 risks / mitigations

1. The split changes the public surface: one family stops being first-class, so
   the README and tool reference say so plainly and agents use `custom_manage`
   for modifier ops. **Mitigated** - the split, its docs and the tier-1
   assertions (8 promoted + 1 opted out) are in place.
2. Strict `dry_run` changes what some ops return; each path gets a test asserting
   the scene, the files and the sprite are untouched. **Mitigated** - the
   table-driven test covers all six mutating families plus the file writes.
3. Relaxing the `deferred` flag widens what `batch_execute` admits, so the
   rollback-on-error path is exercised for the newly admitted read-only ops.

## Phase 17 — looks like animation, not maths (v1.11.0, in progress)

The generator's arithmetic is sound; its *shapes* are the problem. This phase
changes what the clips look like, in the order of how much a viewer notices.
**Six of the seven are done.** The seventh is recorded below with what was
measured about it, which is the most useful part of having tried.

**Done so far:**

1. **A swing is an arc, not a step — DONE.** `_foot_trajectory` returned
   `height: 1.0` for the *whole* swing phase, so the ankle sat on a flat plateau
   `foot_lift` metres up and the foot teleported at toe-off and heel strike. The
   lift is now a hump that is exactly 0 at both contacts, peaks just before
   mid-swing, and has zero slope at the contacts and the apex. Tier-1 checks the
   profile per sample: 0 through stance, 0 again at the wrap, one rise and one
   fall, no flat run, and soft landings. (The *`samples`-does-nothing-for-jump-
   and-turn* half of this item is deliberately NOT done: those two are built from
   hand-authored phase tables with anticipation/launch/air/land shaping, and
   resampling them linearly would make them worse. The tool reference now says
   which families `samples` governs.)
2. **Idle keeps its feet — DONE.** The idle moved the pelvis (bob, sway, twist,
   lean) and never re-solved the legs, so both feet travelled with the hips and
   the character skated. Both legs are now solved against their rest ankle
   targets every sample, behind a new `planted` param that defaults to **true**;
   `planted: false` keeps the old pelvis-only clip for callers who key the feet
   themselves. The test measures the property, not a proxy: the foot bone's
   **world** position across the clip stays within 2 cm of its rest spot and
   never lifts (a foot pinned to its world orientation still rotates *locally*
   as the shin moves under it, so the local delta is the wrong measure).
   `planted` is also the first boolean override, so the coercion no longer turns
   it into a float.

**Also done in this pass:**

3. **Knees keep their mind — DONE.** The two-bone solve now returns the knee
   *and the effective ankle* - the closest point the leg can reach - so both
   bones aim at one reachable target. The shin used to aim at the *requested*
   ankle even after the knee had been computed from a clamped distance, which
   left the foot floating in any pose deeper than the leg's reach. The pole comes
   from the rig's **own measured rest bend** (the shin's rest origin, which is the
   knee) instead of a cross product against `UP`, which is zero exactly when the
   leg is straight up. `clamped` and `clamp_shortfall_m` are reported in the
   gait's meta, so a clipped step is visible rather than silent.
4. **Motion scales with the rig — DONE.** `bob`, `sway`, `foot_lift`,
   `jump_crouch` and `jump_height` defaulted to fixed metres, so a 1.2 m child
   got the same five centimetres of lift as a 2.4 m giant. Untouched defaults are
   now fractions of the rig's **measured** leg (calibrated so the human dummy is
   unchanged), the turn's phase-table bob scales with the same factor, and an
   explicit value still means metres. The test makes the dummy's bones twice as
   long — which is the only way to change a rig's height for the solver, since
   `get_bone_global_rest` is in skeleton space and unaffected by node scale - and
   checks the bob follows.
6. **Lean is distributed like twist — DONE.** Every torso bone took the *full*
   lean, so a seven-bone spine folded seven times as much as a three-bone one and
   `lean` meant something different on every rig. The shares now sum to 1.0 over
   the torso (a three-bone spine is unchanged, which is what the presets were
   tuned against) while the head keeps its counter-lean. Measured end to end by
   differencing against a `lean: 0` clip, because the lean shares bones with sway
   and twist and cannot be read off the peak-to-peak alone.

**Still open, and why:**

5. **A real rig frame** - **DONE.** `RigAnalysis.rig_frame()` builds up/forward/
   lateral from rest geometry, and both the generator and the audit take it, so
   "planted" means the same thing on both sides. `up` is the spine bone's axis
   (local +Y is a bone's head->tail direction), signed by the hips->head chain
   because a bone axis cannot know its own sign; forward is heel to toe and
   lateral across the hips, each made perpendicular to the others.
   `foot_slide()` takes `up` and measures height along it and sliding across it.
   Two things the work turned up, both in the code as comments:
   - A bone axis carries the rig's **pose** as well as its convention, and the
     fixture's spine rests 1.5 degrees off vertical. The golden walk measured
     that leak as **173 units (4.8 degrees) of shin change** before any test
     complained. So the axis is read for the convention and snapped to the
     nearest world axis within 10 degrees - the conventions that matter are 90
     apart, so anything closer is a lean. With that the golden walk is
     **unchanged**, which is the proof worth having: a verified no-op for Y-up
     rigs, and a real frame for genuinely rotated ones. A synthetic Z-up rig is
     the other half of the test: a foot rising 0.3 m in Z that world Y calls
     "never off the ground" (all 9 samples planted) is read correctly as
     swing-then-plant by the rig's own floor.
7. **The root-motion contract** - **DONE, and the frame question is settled by
   measurement rather than argument.** The engine half is now pinned by
   `tests/tier1_root_motion.gd`, which was written because a conclusion here had
   been drawn from a harness that was not animating: `seek()` + `advance(0)` read
   a still pose for *any* clip, so "the character moved 0.0000 m" was recorded as
   "extraction does not run". It does not - the engine never moves the character
   for you, and a still character is what a working setup looks like. What the
   harness does establish, against a live control: the character is never moved by
   the engine, no delta is exposed without a track, and the deltas sum to exactly
   the distance the clip travelled. The cancellation itself is documented
   ("the transformation will be canceled visually, and the animation will appear
   to stay in place", AnimationMixer) but is deliberately **not** asserted from a
   skeleton pose, because a bare headless `--script` tree does not apply the
   mixer's blend and reads stale - a rig that is cancelled and a rig that is not
   animating look identical there.

   **The arithmetic, which is the whole contract:** cancellation shifts the entire
   chain back by the travel `T(t)` - the rotations are unchanged, so every bone
   downstream of the hips translates by the same amount - and the caller then
   applies `T(t)` to the character node. So for any bone
   `world = (authored - T(t)) + T(t) = authored`. The world position **is** the
   authored position. Two consequences:
   - a planted foot has to be authored **still in the clip's own space**, which is
     what the recipe already did;
   - which hip the leg solve aims from **cannot** change where the foot lands. It
     can only change whether the leg can *reach* the target.

   That second point is what the item was really about, and it was got wrong twice
   before being measured. The "in-place" authoring - stance sliding backwards by
   the travel, the textbook form - was implemented and it is **wrong here**: it
   makes the world foot slide back with the clip, the moonwalk (0.61 m of slide
   over one stance, against a cycle's total travel of 1.05 m). Aiming the solve
   from the *cancelled* hips instead of the authored ones is also wrong, for the
   same reason in mirror image (0.61 m the other way). Both were reverted; the
   measurement is in `docs`-adjacent comments in `_foot_trajectory` and
   `_solve_leg` so the next person does not re-run either experiment.

   What landed: the contract is now **tested** rather than assumed -
   `test_a_rooted_stance_is_still_in_the_clip_so_the_travel_cancels` measures the
   authored stance at **0.0000 m of slide over a 14-sample stance**, asserts the
   ankle is pure FK (a position track on the foot bone would quietly become the
   thing that moves the foot, and every conclusion above would be about the wrong
   track), and `root_motion_local` is set explicitly, since a rig facing +X would
   otherwise have its walk applied along world axes.

   The "crouch reach tax" that came out of the same investigation - `crouch` is
   `config.crouch + 0.003 * knee_bend`, a flat 9 cm for a walk - was checked and is
   **not a tax**: it lowers the hips *towards* a target that stays at rest height,
   so it shortens the demanded reach rather than lengthening it. Recorded here so
   it is not "fixed" a second time. What genuinely can make a stance ride the hips
   is the reach clamp when the demanded span passes `upper + lower - 1 mm`; that
   shows up in the reply as `clamped` / `clamp_shortfall_m`, and a stride or
   ground speed that puts the fixed stance point out of reach will trigger it.



1. **A swing is an arc, not a step.** Foot height is currently 0 or 1 across
   the whole swing, so the foot teleports up at toe-off and back down at heel
   strike on a flat plateau; it becomes a hump that is exactly zero at both
   contacts. Jump and turn sample their phase tables at the requested key
   density (today `samples` does nothing for them), use the `lean`, `foot_lift`
   and `knee_bend` they already accept, and keep the air target airborne until
   the body has actually landed.
2. **Idle keeps its feet.** Idle bobs and sways the pelvis and never re-solves
   the legs, so the feet drift with the weight shift. Both behaviours ship
   behind a new `planted` param: `true` (the default; the current drift is a
   defect) solves both legs against fixed rest ankle targets, `false` preserves
   today's pelvis-only clip for callers who key the feet themselves.
3. **Knees keep their mind.** Reach clamping becomes honest — both bones solve
   against one clamped effective target and the reply says `clamped` — and the
   pole comes from the measured rest bend plus a per-leg sign, so the knee side
   is preserved through singular targets instead of being re-guessed from a
   cross product that can be zero.
4. **Motion scales with the rig.** Default bob, lift, crouch, jump height and
   turn bob are fractions of measured leg length and hip height rather than
   fixed metres (explicit metre values keep their meaning); blend-space
   positions use each clip's *actual* solved speed, and the reply reports the
   gap when the stride cap had to clamp it.
5. **A real rig frame.** Up, forward and lateral are built from rest geometry
   and orthogonalised, replacing the hard-coded `Vector3.UP` that mis-bobs any
   non-Y-up rig; the contact/slide metrics use the same frame, so they are
   invariant under a rotated, scaled or mirrored root. The rest map becomes the
   union of roles, spine chain and solve bones, so a detected neck or upper
   chest is no longer keyed against an identity fallback.
6. **Lean is distributed like twist.** Every torso bone currently receives the
   full lean, so a seven-bone spine folds seven times as much as a three-bone
   one; the sum stays the same instead.
7. **The root-motion contract, settled last.** The legs are solved in the frame
   the viewer sees — the root-motion-canceled one — with the extracted motion
   supplying world travel, and `root_motion_local` is set explicitly. Today's
   audit only applies the spec locally, so a real `AnimationTree` playback test
   (Phase 18) is the gate for this change.

## Phase 18 — prove it (v1.12.0, in progress)

1. **Direct `MotionSpecs` contract tests — DONE.** The generator had none:
   everything was asserted through one pose at a time. There is now one
   table-driven test that runs every recipe (walk, run, idle, strafe, jump, turn)
   and checks the promises each one makes: key times ascend and stay inside the
   clip, every keyed value is finite, the reported speed/stride/duration are
   sane, the committed markers match the reported count and sit inside the clip,
   looping recipes close at the seam in value *and* velocity, and the same call
   twice produces the same clip. It is ~4000 assertions and it found two real
   things while being written (below).
2. **A synthetic proportion matrix in tier-1** — the first tier-1 to build
   `Skeleton3D` chains: short legs, long legs, asymmetric legs, a child-sized
   rig, a rotated/mirrored root. Normalized stride, lift, symmetry, a
   leg-scaled slide budget, and loop value *and* velocity closure. **Open.**
3. **Real playback tests — DONE.** Every other test in the motion suite applies
   the *nearest key* to the skeleton by hand, so nothing had ever checked what
   the engine plays: the interpolation between keys, the wrap at the end of a
   looping clip, or that the pose on screen is the pose the data describes. The
   new test lets the real `AnimationPlayer` do the work (`play()` + `seek(t, true)`
   + `advance(0)`, with the playback blend zeroed so the first evaluation is not
   a partial weight) and asserts: a mid-key time gives a value genuinely *between*
   its two keys (not snapped), the played pose equals the clip's own
   `rotation_track_interpolate` at nine times across the clip, seeking past the
   end of a looping clip *wraps* rather than clamps, and the seam step is no
   bigger than the biggest step inside the clip. **What plays is now verified to
   be what the data says**, to 2e-3 rad — the played value comes back through the
   skeleton's pose application, which normalises the local rotation, so bit
   equality is not the engine's contract and the measured gap is ~7e-4 rad.
4. **Golden clips** — normalized walk/run/idle fixtures in the existing
   `godot-ai-animation-clip` JSON, with quaternion-sign normalization and
   tolerances, plus a "generate twice, identical" determinism test. The goldens
   are recorded once Phase 17 has settled, then gate drift. **Open** (the
   determinism half is done, in item 1, and the playback tolerance above is
   measured rather than assumed).

### What the contract test found

- **`close_loop` could append a duplicate final key.** A track that already
  arrived at its first value one key early (a hold at the end of a phase table)
  got a closing key equal to the one before it: a zero-length step at the seam.
  The closing key now moves that last key to the clip end instead.
- **The strafe's foot seam is asymmetric**: it starts moving immediately and
  arrives early, so its seam step is 0.54 rad into and 0.0 out. It is a *held*
  (planted) foot rather than a pop, so the velocity assertion skips a held seam
  rather than pretending it is one. Worth watching when the golden fixtures land.

## Phase 17 item 7 (root-motion contract) and 5 (rig frame) — DONE

Both closed in v1.11.0. Item 5's rig frame, the rest-map union and the
frame-aware contact metrics are above under item 5; item 7's arithmetic and the
two wrong answers that were implemented, measured and reverted are above under
item 7. The engine half is pinned by `tests/tier1_root_motion.gd`.

## Risks / notes

- `mirror` needs per-value-type negation (2D vs 3D, position/rotation/scale).
- `retime` interacts with loop modes: ping-pong lengths must stay exact.
- Graph ops must create nodes and set `tree_root` inside one undo action.
- `sprite_frames` depends on import-side slicing.
- Descriptions stay registry-generated and under the 600-char custom-tool cap.

## Per-phase checklist

1. Ops implemented (single undo, typed errors).
2. Tier-1 pure checks + editor suite rows, golden fixtures where useful.
3. `docs/tool-reference.md` regenerated; README table updated.
4. Release notes + tag; a recorded demo when the phase has one worth showing
   (optional — phases 11 and 12 shipped without one).
5. CI green on Windows + Linux and both core legs (v4.2.1 and main).
