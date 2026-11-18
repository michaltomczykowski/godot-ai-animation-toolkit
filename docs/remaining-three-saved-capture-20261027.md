# Remaining secondary and static chain: bounded native/render handoff

27 October 2026. New tools only; no engine, renderer or media tool was launched
by this worker. Native parse/playback, GPU framing, composition, full decode and
independent assessment are **pending**. This handoff covers exactly:

| Case | Native admission | Presentation per fresh take |
| --- | --- | --- |
| `secondary_branches_local_60` | Persisted reference versus saved redo; 30/60/120 FPS, two fresh loads each | Complete finite 1 s clip, then 5 s held endpoint; two fixed views |
| `3d_local_create` | Original public before/after snapshots; two fresh loads each; zero animation time | 2 s before, 2 s after; two fixed views |
| `3d_local_append` | Original public before/after snapshots; two fresh loads each; zero animation time | 2 s before, 2 s after; two fixed views |

The native matrix is 12 secondary plays plus eight zero-clock static loads.
The render matrix repeats the four 60 FPS secondary runs and eight static loads
with exact native trace equality. The planned presentation remains 1,680 frames /
28 s at 60 FPS. Display holds add no simulation steps. Static left remains before;
the right pane changes from before to after after two seconds. These are saved
state comparisons, not a filmed public operation or new generation.

## Inputs and predicates

Input inventory:
`E:/GodotAI-toolkit-release-2.0.0/20261014/sequence-secondary-static-inputs-r001/manifest.json`,
SHA256 `21a299f359d98a5fb2b5ec1ab88af31a57f9e13f59ceee548e2e02f7ea2de864`.
The runner re-verifies the pinned original archive, original public context and
raw event joins, fixed requests, exact snapshots and all staged file bytes.
Historical producers remain secondary `751370894a2959ade6278ad972623e45813aa066`
and chain `3d91adef459558f28a76b9537dfb4b6b5205d9bd`. Candidate helper and
operative source identities are separate. Whole motion/bone writer differences
remain disclosed; this does not approve current generation or all variants.

The copied project contains eight exact `.tscn` files and one exact reference
`.tres`, plus independent helper scripts, with no production addon, private model,
skin or scene generation. Git blobs and runtime SHA256 are recorded separately
for newline-sensitive helpers. The secondary reference is loaded from its saved
resource; no `Reference.build`, solver or key generation runs. All five tracks /
131 keys, paths, types, interpolation, transitions, markers, key times, key values,
midpoints and complete native FPS schedules are checked with original
0.0001 m / 0.001 rad / 0.0001 scale limits. Saved player speed 0.8 is recorded;
manual evaluation explicitly uses speed 1 and exactly one active player.

Every original/new bone name, parent, rest, pose matrix, enabled flag, metadata,
owner and transform in each static fixture is compared against its original
public snapshot. All bone pose components and world geometry are recorded.
There are no pose setters, animation advances or solves in the static path.
The inherited renderer uses local-Y cylinder scaling, actual mesh AABB/fringe
bounds and synchronous `force_draw(false, 0)` / `force_sync`. Whole original
scene roots stay together under the viewport. State, process/physics counters
and fixed cameras must remain unchanged across each draw.

## Root commands after integration

Run from `G:/godot-ai-dev/godot-ai-animation-toolkit`. Output directories are
exclusive; preserve any failed attempt and increment its suffix. Root owns the
engine queue. These commands do not compose or decode a movie:

```powershell
$py = 'G:/godot-ai-dev/godot-ai-v4-animation/.venv/Scripts/python.exe'
$engine = 'F:/GODOTAITESTING/Godot_v4.7.2-stable_win64/Godot_v4.7.2-stable_win64.exe'
$base = 'E:/GodotAI-toolkit-release-2.0.0/20261014'
& $py tools/run_remaining_saved_capture.py prepare --repo 'G:/godot-ai-dev/godot-ai-animation-toolkit' --inputs "$base/sequence-secondary-static-inputs-r001/manifest.json" --output "$base/remaining-three-native-r001"
& $py tools/run_remaining_saved_capture.py native --output "$base/remaining-three-native-r001" --godot $engine
& $py tools/run_remaining_saved_capture.py prepare-render --native "$base/remaining-three-native-r001" --output "$base/remaining-three-render-r001"
& $py tools/run_remaining_saved_capture.py render --output "$base/remaining-three-render-r001" --godot $engine
& $py tools/run_remaining_saved_capture.py presentation --output "$base/remaining-three-render-r001"
```

Each engine attempt records the exact executable hash, command, exclusive
streamed log, owned PID, bounded 900 s wait and actual exit. On timeout, only
that owned child is killed. Render startup uses the existing exclusive viewport
override and cleanup receipt. `admit --output DIR [--rendered]` is read-only;
it requires actual exit 0, official 4.7.2 banner, clean logs, frozen inputs and
all raw observations, retaining original execution failure fields.

The final `presentation-schedule.json` binds every pane PNG, frame, take, phase
and native time. Root can compose its 28 s schedule using existing media tools.
Fit complete panes below a header preserving aspect; do not crop or cover native
geometry. Show case/take/native time and the static bone names, parents, rest and
scale/enabled metadata. Then full-decode the encoded bytes and provide ordered
actual-video frames, endpoints and both resets for independent review. No visual
approval follows from numeric passes alone.

## Offline checks

From `tools`, run `python -m unittest -v test_run_remaining_saved_capture` with
the `$py` interpreter above. Seven tests include actual preserved archive/public
trace verification, float32 reference parsing, committed copied-project staging,
exclusive outputs and corruption of request/group/source/scene, keys, clocks,
speed, ownership, endpoint hold, bone state, static metadata, PNG bytes/framing
and inert draw guards. Synthetic report fixtures exercise rejection only;
they are not represented as real native output. Actual engine parsing remains
root's next gate. Existing full sequence footage and its fixed-camera supplement
are a separate root-owned admission/assessment queue.
