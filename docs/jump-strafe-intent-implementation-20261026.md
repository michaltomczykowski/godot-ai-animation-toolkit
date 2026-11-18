# Jump and strafe intent implementation, 26 October

Prepared offline only. This change does not claim either operation qualified;
root must parse both native scripts and execute fresh public/native attempts.
No production motion, fixture, recipe or physical-input helper changes.

The ordinary dedicated dummy Responsive extracted requests are stationary jump
`height: 0.2` (distance omitted) and left strafe `speed: 0.1`. The driver accepts
these explicit metric inputs and preserves omitted defaults and the default
four-rig matrix. Dummy selection also supports walk_start/walk_stop for root's
separate transition observer. Public dry-run reach refusals remain failures.

Both existing native checkers attest request, scene bytes before/after, loaded
rig/rest, roles and clip through the unchanged read-only identity helper.
`case_id=dummy` selects six Player/Tree 30/60/120 runs; default counts remain24.
All existing native physical predicates and thresholds remain.

The existing `idle_turn_physical_v1` join now accepts these two additional fixed
cases. Jump adds actual hip world positions, saved hips-key timestamps, clip
length and event-marker observations. The adapter independently computes
flight `2*sqrt(2*0.2/9.81)`, ordinary one-second action, takeoff0.22s,
apex0.4219275s and landing0.623855s. It checks actual ballistic hip samples,
bilateral raw ankle flight, peak and recovery with the existing tolerance
formula recomputed from actual replay/key clocks. Sparse/missing authoring
clocks fail closed. Response height/apex/sample counts and report tolerance
fields do not supply expected effects.

Strafe adds the measured world frame and anatomical rest-foot positions.
The adapter checks signed world displacement0.1m per ordinary one-second cycle
and0.6m over six seconds, forward/up drift, monotonic continuous travel,
per-frame speed envelope and movement coverage in every cycle. Existing native
fractional-phase interpolation, contact, reach, ownership, foot gap, knee,
ordinary arm follow-through and continuity checks remain required. No output
key interpolation or reported speed supplies independent expected travel.

Strict source/context/public/save/forced-reload/native-event joins are reused.
Jump also requires its inherited checker hash. Native corruption-control runs
cannot qualify. Existing idle/turn scoped requests and clocks are unchanged.

Offline verification (workdir `tools`, prescribed Windows Python):

36 tests PASS, including both available private historical raw controls;
`git diff --check` PASS. No native parse or engine run was performed here.

```powershell
& 'G:/godot-ai-dev/godot-ai-v4-animation/.venv/Scripts/python.exe' -m unittest -v test_operation_idle_turn_intent_checks test_selected_motion_intent_runner test_operation_jump_strafe_intent_checks test_operation_case_collector
```

Controls cover fixed metric requests, all six clocks, missing feet/hips/keys,
wrong height/speed/sign, tiny hop, delayed apex, truncated/no flight, inert
playback, doubled travel, teleports, intermediate reversal, drift, contact,
arms, recovery, clamp, changed scene bytes and inherited checker source.
Output expectation/tolerance mutations cannot change a valid physical result.
Two immutable real historical reports supply local raw clock/ankle controls;
their different default requests and missing new identity observations are
explicitly refused. Those private paths are optional outside this host.

Root execution after integration, with root-owned engine/context variables
and fresh output directory `$attempt`:

```powershell
& $godot --headless --path $project --check-only --script res://tools/check_jump_quality.gd
& $godot --headless --path $project --check-only --script res://tools/check_strafe_quality.gd
& $python tools/mcp_run_quality_review.py --repo $repo --core-root $core --project-root $project --output "$attempt/jump-public" --operation jump --phase candidate --rig-id dummy --height 0.2 --styles responsive --root-modes extracted --revision motion-intent-jump
& $python tools/mcp_run_quality_review.py --repo $repo --core-root $core --project-root $project --output "$attempt/strafe-public" --operation strafe_cycle --phase candidate --rig-id dummy --direction left --speed 0.1 --styles responsive --root-modes extracted --revision motion-intent-strafe
& $python tools/check_selected_motion_intent.py --godot $godot --project-root $project --route "$attempt/jump-public/responsive/route.json" --output "$attempt/jump-native"
& $python tools/check_selected_motion_intent.py --godot $godot --project-root $project --route "$attempt/strafe-public/responsive/route.json" --output "$attempt/strafe-native"
& $python tools/operation_case_collector.py collect --context $env:TOOLKIT_OPERATION_CONTEXT --trace-dir $env:TOOLKIT_OPERATION_TRACE_DIR --root $repo --output "$attempt/operation-case-results.json" --allow-partial
```

Use root's existing serialized public editor lifecycle and source-context
preparation. No worker launched Godot, server, ffmpeg or pushed this branch.
Actual runtime field/timing behavior remains to be verified by root. Only these
fixed dummy cases are in scope; no all-rig/style, visual or Linux claim.
