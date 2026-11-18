# CI26a35eb raw evidence audit

Run40173858488: success;58 successful jobs,2 skipped. PR head `26a35eb2dc7106cdd951b4771f9ec8c3971861bc`; actual tested checkout `86661e7b31e4043ce520ccb82eff5f80be067f45`; base `5e13a6c0099b1a0f9255d661f5c5ac17fc9c9082`.

Event context retains pr_merge_sha6c5150507cb09ffd5670d818e4fd2420982bbd95, distinct from actual checkout86661e7b31e4043ce520ccb82eff5f80be067f45. Do not substitute the event merge field for tested source. Each cell raw event-payload hash is retained separately.

## Actual four-cell evidence

- mcp-editor-ubuntu-latest-4.2.1: 2049 cases;102 successful public operations;835 raw artifact bindings verified;0 mismatches;0 non-invocation derived failures;217 refused/failed observations remain unadjudicated.
- mcp-editor-ubuntu-latest-4.3.0: 2049 cases;102 successful public operations;835 raw artifact bindings verified;0 mismatches;0 non-invocation derived failures;217 refused/failed observations remain unadjudicated.
- mcp-editor-windows-latest-4.2.1: 2049 cases;102 successful public operations;835 raw artifact bindings verified;0 mismatches;0 non-invocation derived failures;217 refused/failed observations remain unadjudicated.
- mcp-editor-windows-latest-4.3.0: 2049 cases;102 successful public operations;835 raw artifact bindings verified;0 mismatches;0 non-invocation derived failures;217 refused/failed observations remain unadjudicated.

Each cell has21 operations with all required checks represented by actual passing cases. Presence is not a whole-operation qualification. Missing main-bundle operation:animation_inspect.preview. No cell/context folding.

## Required gaps per cell

82 visual_review gaps (exact operation list in audit.json). Preview also lacks main-bundle mcp_invocation/file_effect/source_unchanged/reported_errors/typed_errors. valid_effect missing for preview and motion idle_cycle,character_setup,jump,turn_cycle,strafe_cycle,walk_start,walk_stop. Other required check categories have at least one passing bound case per operation.

## Separate preview and ZIP evidence

Both Linux released-core rendered preview reports passed with4 images each, exact context/log and scene/timeline checkpoint/restoration hashes verified. Postmortem mode records no_observed_native_crash and editor_returncode_before_cleanup=null (alive at diagnostic checkpoint), matching official binary SHA8d106cbe6144c2dc7e881d61d2429c1a8a76e6b22ef48bd5e48dcf934953f71e. Kernel restored, private core directory removed, owned_core_deleted=true; no backtrace collected. No core file was uploaded. This is not proof that a core existed, a normal editor exit, or an intermittent native race was fixed.

All4 clean ZIP receipts bind actual86661e7 source and same package SHA b295b5b17dc09888d3c615bd2238292a7f4491ef2326fe5775dcbe667af522b0; both install orders pass in each. All8 receipt log hashes match actual corresponding editor logs (not route logs).

## Previous eacc767 run

Run40172842884 failed4 live jobs; actual tested merge6c5150507cb09ffd5670d818e4fd2420982bbd95. Each raw report contains exactly1 derived animation_motion.character_setup.source_unchanged failure; dry/history/save/path/error/type in that same row pass. Linux421 additionally hit actual60-second mcp_inspect_3d timeout and only86 successful operations; other3 cells102. Exact raw reports, source contexts, hashes and failed-job logs retained in ci-eacc767-r001. Both separate Linux rendered previews passed. Do not attribute this run failure to the earlier preview native abort.

## Limits / next gaps

No engine, source mutation, public invocation, upload, native/visual promotion or adjudication of216/217-style expected refusal observations performed. Current217 each is retained. Fresh local motion/rig intent and source-bound independent media are separate evidence channels and must be joined explicitly before candidate qualification. Historical private media cannot be relabeled current. Source-side checkpoint guard correction is consistent with the green case outcome; raw results alone do not prove a native memory defect is fixed.

## Strict preview join and residual technical gaps

Re-executed verify_preview_bundle offline from exact tested-source operation_preview_adapter.py, preview_renderer_profile.py, operation_case_collector.py and check_release_audit.py downloaded from86661e7. Both Linux cores pass valid_effect/file_effect/source_unchanged/typed_errors/reported_errors, with bound actual public IDs. This joins those five proof categories only within the exact Linux/core context; Windows preview invocation remains absent. Source/type/track required-check residual operation gaps are zero when the separate Linux preview proof is included as an operation-level evidence channel (not four-cell coverage). Residual valid_effect operations are exactly7: animation_motion.idle_cycle,character_setup,jump,turn_cycle,strafe_cycle,walk_start,walk_stop.82 independent visual reviews remain absent from CI case reports. No native/visual or release qualification is inferred.

Later abf8ea2 diagnostic run40243257753 is queued/running separately and supplies no evidence to this completed26a audit.
