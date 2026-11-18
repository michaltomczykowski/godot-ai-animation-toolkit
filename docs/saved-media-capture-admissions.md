# Saved graph and rig capture admissions

## Read-only findings

The staged graph-media-r001 has7self-contained graph scenes; rig-media-r001 has
9self-contained synthetic rig representatives. None contains a MeshInstance3D or
Skin. Existing renderers checked1920x1080logical/texture sizes but did not admit
actual projected target/body bounds, title/caption clearance, or startup viewport
settings. The rig helper read global bones without an explicit update/freshness
predicate. These guards address capture input/presentation only.

## Integration

Cherry-pick this commit, then apply `docs/saved-media-framing-integration.patch`:

```powershell
git apply --check --ignore-space-change docs/saved-media-framing-integration.patch
git apply --ignore-space-change docs/saved-media-framing-integration.patch
```

Install/copy the updated three existing scripts plus `saved_media_framing.gd`
into the isolated capture project's existing `res://tools` layout. No scene,
addon, animation keys, graph, target pose, camera animation, or fixture changes.
Run the existing graph/rig native positive+negative gates anew first. Their
positive.json/positive.log must match the exact new renderer/helper hashes and
manifest. Actual Godot parsing/native/GPU execution remains pending, root-owned.

## Per-frame framing and freshness

The fixed cameras remain fixed. Graph admits all six actual Polygon2D vertices
through its current canvas transform. Rig admits conservative projected corners
of every displayed joint sphere and every local-axis rod endpoint, with native
near/far/behind-camera checks. Parent-link segments lie inside endpoint bounds.
Every projected point must fit logical bodyRect(24,100,1872,760), excluding title
and caption areas, with at least2px extent. Projected raw points and recomputed
bounds are retained, not merely a `fits` pass flag. The calibration grid is
background and is not required to fit this body rectangle.

The rig helper requests the same native skeleton update notification already
used by the existing native checker. It compares actual global bones with a
parent/local hierarchy reference. Godot4local bone poses already include rest;
rest is not multiplied twice. It never corrects a pose. Saved mesh/skin inputs
are refused by this unskinned-joint capture contract. This does not disable any
toolkit operation; it avoids claiming fresh skin proof from a skeleton-only
representation. A skin/body-aware renderer is a separate future input contract.

The official [Skeleton3D contract](https://docs.godotengine.org/en/4.5/classes/class_skeleton3d.html)
distinguishes final skeleton/skin updates; its force-update method is deprecated
for internal use, so this change uses the existing native notification path and
an independently checked hierarchy result rather than that deprecated API.

## Thin serial capture wrapper

Use a NEW private output directory. Supplying both manifests captures graph then
rig serially. For example (fill actual existing paths):

```powershell
python tools/saved_scene_media_capture.py --project E:/capture-project --godot GODOT_CONSOLE --ffmpeg FFMPEG --ffprobe FFPROBE --output E:/new-private-capture --graph-manifest E:/graph-media-r001/manifest.json --graph-native-report E:/fresh-graph-check/positive.json --rig-manifest E:/rig-media-r001/manifest.json --rig-native-report E:/fresh-rig-check/positive.json
```

The wrapper reuses movie_capture_startup.run_capture for exclusive startup
1920x1080viewport/stretch override and durable cleanup receipts. It reuses the
existing FX queue's durable checkpoint/hash/full-decode progress utilities.
Before each child, receipt state is flushed. Failed/partial output is preserved;
no automatic regeneration/retry or reuse by filename. All source scene hashes,
producer/helper hashes, actual Godot4.7.2startup logs, exact commands, native
report, complete sequential PNGs and dimensions/hashes are recorded. Existing
public scenes retain their historical identity; current tool hashes are not a
claim those scenes qualify the current source.

Graph admits14runs ×120actual movie frames=1680; rig18×240=4320. Each trace also
has one explicitly non-movie end-boundary native sample; those extra samples are
not counted as PNGframes. Native ownership, authored rig channel checks,
per-case resets and original graph walk/run/OneShot/additive/idle contracts stay
required. The wrapper encodes without invented audio, then independently decodes
the entire MP4 with error rejection and checks1920x1080/60FPS stream metadata.

## Limits

No code here claims aesthetics, continuous human watching, source qualification,
skin deformation, pixel occlusion freedom or readable individual overlapping
joints. Actual independent temporal/pixel assessment follows successful capture.
Offline controls are synthetic schema/process controls, not native positive
proof. Root must run parse, real native controls, then the singleGPUqueue.


## Admission hardening follow-up

Rig samples now report the actual assigned animation, clip length, loop mode
and playing state. The offline admission reopens the exact hashed historical
scene and resolves its unique named Animation resource. Every 60 FPS sample
must match that source clip and expected native phase. Non-looping clips retain
the native finite-stop convention (zero position after stopping); exact endpoint
and linear wrap boundaries allow only zero or the endpoint within 10 microseconds.
Pingpong uses the reflected phase. Static saved pairs require no selected clip
or playing clock. Constant, lagged, skipped or changed-clip samples fail.
These conventions still require actual engine execution; offline controls do
not establish Godot execution or visual approval.

Projected geometry must stay one pixel inside every body edge to account for
raster fringe on the actual PRIMITIVE_LINES rods and displayed joint bounds.
Fixed cameras and saved transforms are unchanged. Both native preflight and
render receipts include the actual imported graph clip-digest helper hash,
read from its Script.resource_path in the running project, and compare it to
the declared producer dependency. Native preflight requires explicit empty
failures and engine_errors arrays; absent or null fields cannot pass.
