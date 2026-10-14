# Operation evidence and release qualification

Schema v2 preserves all 103 operations and original narratives/checks. Historical status derives from applicable checks. Every exact-candidate qualification remains pending. Human review pauses were waived on 2026-10-14; independent continuous assessment is required. Unviewed media is never human approved.

## Commands

```powershell
& $Godot --headless --path test_project --script res://tools/export_operation_audit.gd
python tools/check_release_audit.py --inventory-only
python tools/test_release_audit.py
python tools/check_release_audit.py --source <commit> --receipt-dir docs/release-qualification
```

Inventory-only success is not release success. Missing qualification fails. A disposable project containing the addon can run the exporter with `-- --docs-root <absolute repo/docs>` and `res://tools/check_operation_policy.gd`. These pure checks do not exercise the public route.

## Portable candidate receipt

`operation-qualification.json` contains schema_version=2, tested_source (full tested commit), production_dependencies (every tracked addons/godot_ai_animation path to its Git blob SHA), compatibility, and operations keyed by all 103 keys. Later receipt/documentation-only commits may be passed as --source: the full addon path set/blobs and referenced test/checker blobs must match tested_source. Changed implementation or validation dependencies block reuse.

Compatibility needs four passing entries: Windows/Linux x released core4.2.1/4.3.0, engine4.7.2, pinned core_commit, tested_source, and hashed raw artifacts. Core main is advisory.

Each operation contains checks and evidence_records. Checks contain status (pass/fail/pending/not_applicable), evidence_refs, and reason. N/A requires a reason and is forbidden for required checks. Pass requires resolvable references. Required checks derive from the operation effect contract.

Candidate records contain scope=candidate, tested_source, engine=4.7.2, route, actual nonempty case_ids, dependencies (repository path to Git blob SHA), and artifacts (receipt-relative path and SHA256). Nonvisual records require a test/checker dependency. Public invocation references must cover all four platform/core pairs with platform/core_version/core_commit and route=public_godot_ai. Every artifact must exist and hash correctly at gate time.

Visual records additionally contain assessment: reviewer_type=independent, continuous_media=true, findings=<actual assessment>, human_approved=false. Discrete/audio effects need progression/audible evidence. Static sheets cannot replace continuous review. Historical human approvals remain separate from waiver/independent assessment.

The gate verifies source/artifact identities and completeness; it does not infer success from filenames. The root reviewer binds actual reports, cases and findings. Never convert documentary selectors into invented candidate case IDs.

## Effect applicability

All effects require public invocation, valid effect, clean errors, source isolation and typed errors.

| Effect | Additional required checks |
| --- | --- |
| scene_write | tracks/types, dry run, scene Undo/Redo, save/reopen, native saved playback, independent visual assessment |
| scene_structure | dry run, scene Undo/Redo, save/reopen, native saved effect evaluation, independent visual assessment |
| file_write | dry run and exact filesystem/byte effect |
| read | accurate data and no mutation; scene Undo/generated playback are N/A |
| render | hashed output and independent assessment; typed rendering-unavailable refusal |

Pose blending includes optional files and is conservatively file_write. Rig/library family batch undo remains false while scene-applying operations retain scene Undo. Inspector dry_run verifies its delegated effect/no mutation under applicable checks.

Valid idempotent edits report changed=false/affected_count=0/undoable=false without replacement/history. Missing targets and unsupported data retain typed errors. Availability is registry-owned; contextual native limitations remain in prewrite handler guards. Missing ledger evidence never disables a working operation.

## Reconciliation and real gaps

Historical matrix records retain suite/operation selectors, source identities and available dependency blobs. Original narratives/checks are unchanged. Raw case IDs/artifact receipts must be bound for candidate qualification. Reliability does not imply character visual approval.

Reuse completed FX64 cases, graph28 states, edit146 states, presets/library126 states, rig pose/chain96 states, rig clip90 states, modifiers828 states/276 references, active bake201 cases/603 states, motion/sequence273 cases/819 states/2457 plays, and setup7 cases/21 runtime states when dependencies match. Do not repeat old investigations solely because the ledger remains partial. Exact candidate full matrix and clean ZIP qualification are still required.

All103 candidate rows remain pending. The following are historical annotation gaps, not instructions to regenerate matrices. Visual gaps may use unchanged saved scenes/media after temporal review; file/read gaps need their proper byte/native-data/no-mutation receipts.

| Operation | Historical applicable checks pending |
| --- | --- |
| `animation_presets.pulse` | visual_review |
| `animation_presets.bounce` | visual_review |
| `animation_presets.orbit` | visual_review |
| `animation_presets.sweep` | visual_review |
| `animation_presets.drift` | visual_review |
| `animation_presets.spin` | visual_review |
| `animation_presets.float` | visual_review |
| `animation_presets.stagger` | visual_review |
| `animation_presets.showcase` | visual_review |
| `animation_fx.shake` | visual_review |
| `animation_fx.zoom_punch` | visual_review |
| `animation_fx.hit_flash` | visual_review |
| `animation_fx.damage_bar` | visual_review |
| `animation_fx.typewriter` | visual_review |
| `animation_fx.progress_fill` | visual_review |
| `animation_fx.counter` | visual_review |
| `animation_fx.dialog_pop` | visual_review |
| `animation_fx.transition` | visual_review |
| `animation_fx.wave` | visual_review |
| `animation_fx.spring` | visual_review |
| `animation_fx.pendulum` | visual_review |
| `animation_fx.path_follow` | visual_review |
| `animation_fx.flipbook` | visual_review |
| `animation_fx.sprite_frames` | visual_review |
| `animation_fx.audio_cue` | visual_review |
| `animation_graph.state_machine` | visual_review |
| `animation_graph.blend_space` | visual_review |
| `animation_graph.blend_tree` | visual_review |
| `animation_graph.wire` | visual_review |
| `animation_graph.graph_get` | None; candidate pending |
| `animation_graph.locomotion` | visual_review |
| `animation_graph.one_shot_layer` | visual_review |
| `animation_graph.additive_lean` | visual_review |
| `animation_edit.retime` | visual_review |
| `animation_edit.retarget` | visual_review |
| `animation_edit.reverse` | visual_review |
| `animation_edit.mirror` | visual_review |
| `animation_edit.offset` | visual_review |
| `animation_edit.ease_range` | visual_review |
| `animation_edit.set_interp` | visual_review |
| `animation_edit.trim` | visual_review |
| `animation_edit.split_at` | visual_review |
| `animation_edit.merge` | visual_review |
| `animation_edit.amplitude` | visual_review |
| `animation_edit.loop` | visual_review |
| `animation_edit.key_edit` | visual_review |
| `animation_edit.cleanup` | visual_review |
| `animation_edit.smooth` | visual_review |
| `animation_edit.resample` | visual_review |
| `animation_edit.reduce` | visual_review |
| `animation_edit.add_noise` | visual_review |
| `animation_edit.overlap` | visual_review |
| `animation_edit.layer` | visual_review |
| `animation_inspect.describe` | reported_errors |
| `animation_inspect.timeline` | reported_errors |
| `animation_inspect.audit` | reported_errors |
| `animation_inspect.compare` | reported_errors |
| `animation_inspect.stats` | reported_errors |
| `animation_inspect.motion_report` | reported_errors |
| `animation_inspect.motion_audit` | source_unchanged |
| `animation_inspect.rig_profile` | reported_errors, source_unchanged |
| `animation_inspect.sample` | reported_errors, source_unchanged |
| `animation_inspect.preview` | file_effect, reported_errors, source_unchanged, visual_review |
| `animation_inspect.dry_run` | reported_errors |
| `animation_inspect.help` | reported_errors |
| `animation_library.template_save` | file_effect |
| `animation_library.template_apply` | visual_review |
| `animation_library.template_list` | None; candidate pending |
| `animation_library.template_delete` | file_effect |
| `animation_library.spec_export` | file_effect |
| `animation_library.spec_import` | None; candidate pending |
| `animation_library.spec_apply` | visual_review |
| `animation_rig.pose_save` | file_effect |
| `animation_rig.pose_apply` | visual_review |
| `animation_rig.pose_blend` | file_effect |
| `animation_rig.pose_to_clip` | visual_review |
| `animation_rig.pose_list` | None; candidate pending |
| `animation_rig.rig_get` | None; candidate pending |
| `animation_rig.rig_chain` | visual_review |
| `animation_rig.walk_cycle` | visual_review |
| `animation_rig.idle_breathing` | visual_review |
| `animation_rig.blink` | visual_review |
| `animation_rig.jumping_jack` | visual_review |
| `animation_rig.squat` | visual_review |
| `animation_rig.punch` | visual_review |
| `animation_rig.bake_pose_sequence` | visual_review |
| `animation_motion.walk_cycle` | visual_review |
| `animation_motion.run_cycle` | visual_review |
| `animation_motion.idle_cycle` | visual_review |
| `animation_motion.cycle` | visual_review |
| `animation_motion.character_setup` | visual_review |
| `animation_motion.secondary_motion` | visual_review |
| `animation_motion.jump` | visual_review |
| `animation_motion.turn_cycle` | visual_review |
| `animation_motion.strafe_cycle` | visual_review |
| `animation_motion.walk_start` | visual_review |
| `animation_motion.walk_stop` | visual_review |
| `animation_rig_modifiers.ik_setup` | visual_review |
| `animation_rig_modifiers.spring_setup` | visual_review |
| `animation_rig_modifiers.look_at_setup` | visual_review |
| `animation_rig_modifiers.retarget_setup` | visual_review |
| `animation_rig_modifiers.twist_setup` | visual_review |
| `animation_sequence.compose` | visual_review |

## Implementation verification (2026-10-14)

Isolated Godot4.7.2 headless project compiles all guarded handlers and passes the103-operation registry/preflight/schema-budget/idempotent-edit probe. V2 exporter and inventory validation pass; Python10 structural/corruption tests pass, including complete synthetic receipt acceptance, artifact/dependency corruption, false human approval, inappropriate N/A and historical-proof refusal. Synthetic test receipts are ephemeral fixtures and are never release evidence.

The first pure export attempt failed because a broad text replacement inserted descriptor-only code into the parameter documentation loop. The failed output is preserved in the task tool log; the scope was corrected and exporter/docs/policy reruns pass. This failed attempt did not generate clips, launch an editor or mutate fixtures. Exact candidate/public-route/platform/visual qualification is still pending.
