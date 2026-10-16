# Saved setup continuous recording

Status: source prepared; engine parsing, native skin/signal timing and all
capture/visual qualification pending. No generator or runtime changes.

Create a new immutable schedule with `tools/plan_setup_recording.py --route
ROUTE --condition half_idle_walk|half_walk_run|jump --output NEW.json`. Four
actual saved public rigs are required. Default two3s takes per rig; a longer
saved cycle or jump/fade/recovery requires an explicitly longer take. The jump
request fires after0.25s idle preroll. The route/source scene hashes remain in
the schedule and the saved-scene checker loader validates each scene.

Run `test_project/tools/render_setup_quality.gd` with schedule, NEW frame folder
and clean|diagnostic. The Godot process must start with1920x1080 viewport
settings, using the existing owned `movie_capture_startup.py` wrapper. Runtime
window sizing alone does not configure the MovieMaker writer. This renderer
writes PNGs manually and rejects wrong actual image sizes. Root schedules all
process/capture work.

Each take loads two fresh scene instances into independent front/side worlds.
The shared checker loader admits saved mixer/helper ownership before normalizing
callbacks. It never creates a graph, helper, animation or pose. Trees advance
at60FPS, original extraction deltas are consumed once in owner-parent space,
and the saved modifier is advanced manually. Actual final modifier signals
supply proxy poses, phases and diagnostics. Rendering awaits the skin-update
and post-draw path; unexpected intervening modifier evaluations are fatal.
Priming signals, physical frames and skin-update counts are explicit receipts.
The first captured image follows a real dt, so180frames contain180advances.

Cameras/floor/grid use measured world geometry axes, remain fixed through each
take and cover full expected locomotion displacement. Existing saved skinned
meshes remain untouched. Rigs without meshes use clearly labeled display-only
bone rods. Diagnostic rods are supplementary geometry, never bone writes.
The second take starts with a fresh scene/helper/Tree, visibly labeled TAKE2;
no continuous pause/resume behavior is claimed. Every view has one native Tree
and one root consumer. Engine errors or binding/signal failures fail capture.

Receipts include exact schedule/renderer/loader/runtime/scene hashes, actual
frame/render/window sizes, per-frame native phases/weights/root deltas/travel,
helper diagnostics, final signals and skin witnesses. Source route metadata is
retained. Compare both views' native trajectories and validate decoded PNG/video
counts before the independent temporal/visual assessment. Numerical success
must never be relabeled visual or human approval.

Official timing reference: [Skeleton3D manual modifier advance and signals](https://docs.godotengine.org/en/4.5/classes/class_skeleton3d.html).

Offline scheduler controls:4pass, including immutable input, exact durations,
supported four-rig scope, extracted/in-place controller ownership and truncation
refusals. Engine parse and actual output are pending; no media has been created.

## Strict admission and frame proof follow-up

Renderer now requires a fourth argument: the caller-bound exact schedule SHA256.
It rejects schedule contract/rig IDs/take counts/frame counts/speeds/condition/
OneShot timing mismatches before scene playback. Planner requires actual finite
positive clip lengths, ordered finite gait speeds and scene resource paths with
SHA256. This is schedule admission, not source or visual approval.

Each sample records its rig/take/view/frame/time identity and skin-update count
before physical advance, after advance and after draw. A cumulative old skin
signal cannot satisfy the per-frame increase. Each take must contain its exact
scheduled trace length and prime+frame final-signal count; total frames must
match all eight declared takes. The offline validator checks these identities,
counts, source/schedule hashes, engine-error list and each framing witness.

Camera remains fixed. Its initial conservative extent includes all rest bones,
both full-travel endpoints and vertical clearance. Every physical frame then
projects every final-signaled bone (including fingers) into its actual camera:
no behind-camera point and at least20pixels of margin in the952x900 view.
This provides explicit skeleton/frustum proof across the entire native path;
it does not establish a deformed mesh silhouette, garment/hair bounds or visual
quality. Those remain part of the tiny-capture and temporal assessment. Failure
stops capture; cameras never chase/recenter to conceal cropping.

Offline:5 scheduler tests and2 receipt tests pass; the latter include12 concrete
corruptions (stale skin, truncated trace, wrong view/take, crop/behind, time,
signal count, source/schedule hash and engine errors). GDScript/native/capture
validation remains pending; no process was launched for this follow-up.
