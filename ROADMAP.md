# Roadmap — from presets to a real animation toolkit

Status: **Phase 0, 1 and 2 done** (v0.4.0). Phase 3 (more generators) next.
Last updated: 2026-09-22.

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

## Phase 3 — more generators → v0.5.0

`shake` (2D/3D, decay, seeded), `zoom_punch`, `hit_flash`, `typewriter`,
`progress_fill`, `counter`, `wave`, `spring`, `pendulum`, `path_follow`,
`flipbook`, `sprite_frames`, `audio_cue`, `transition`, `dialog_pop`,
`damage_bar`.

## Phase 4 — `animation_graph` → v0.6.0

State machine build (states, transitions, xfade, conditions, advance modes),
blend space 1D/2D, blend tree (`blend2` / `one_shot` / `time_scale`), `wire`
(AnimationTree → player), `graph_get` dump, plus `locomotion`, `one_shot_layer`,
`additive_lean` presets.

## Phase 5 — project library → v0.7.0

`template save/apply/list/delete` on `res://animation_toolkit/library.json`,
`spec_export/import`, `spec_apply` (build a clip from a spec file — the general
escape hatch).

## Phase 6 — rigs (later) → v0.8+

Skeleton2D/Bone2D chains from a node tree, IK (CCDIK/FABRIK/two-bone), spring
bones, pose save/apply/blend, then procedural character recipes (`walk_cycle`,
`idle_breathing`, `blink`).

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
