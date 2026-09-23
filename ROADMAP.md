# Roadmap — from presets to a real animation toolkit

Status: **Phase 0-5 done** (v0.7.0); **6a poses done** (v0.8.0). Next: 6b (rigs/IK/springs/retargeting).
Last updated: 2026-09-23.

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

## Phase 6 - `animation_rig` (in progress)

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
existing skeleton) and `ik_setup` (3D `two_bone`/`ccdik`/`fabrik`/`jacobian`/
`spline`, target marker created at the chain tip, optional pole, inactive by
default). Covered by 6 new editor rows (121 total).

**Left:** `spring_setup` (SpringBoneSimulator3D), `look_at_setup`
(LookAtModifier3D), `retarget_setup` (RetargetModifier3D + SkeletonProfile /
BoneMap mapping). 2D IK stays unsupported on purpose: the
`SkeletonModificationStack2D` path is Experimental in Godot 4.7, so `ik_setup`
refuses 2D skeletons with a clear error while 2D chains still work through
`rig_chain` + poses. All modifiers are created **inactive** (opt-in), and rig
ops warn about scaled skeletons.

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

### 6c - procedural recipes -> v1.0.0

`walk_cycle` (phase-offset legs/arms + hip bob, explicit role mapping with
name-based auto-detect), `idle_breathing`, `blink`, and `bake_pose_sequence`
(step the skeleton with `advance()` and sample IK results into a clip so IK can
be baked off at runtime).

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
4. Demo recorded (Movie Maker → ffmpeg pipeline) + release notes + tag.
5. CI green on Windows + Linux and both core legs (v4.2.1 and main).
