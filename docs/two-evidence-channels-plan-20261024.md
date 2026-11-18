# Bounded SpriteFrames and pose_blend refusal evidence

No primary, production, engine, editor, GPU or public calls. New isolated worktree
from596e278. Scope only animation_fx.sprite_frames.track_paths_types and
animation_rig.pose_blend.typed_errors; no broader framework or new valid writes.

1. Existing raw FX intention already observes actual SpriteFrames/AtlasTexture
classes, selected animation, playing state, FPS/loop and exact four atlas regions.
Add the path/type channel from those source-bound observations and fixed request
sprite_path/texture. It means node path plus actual SpriteFrames/AtlasTexture cell
contracts; do not invent Animation tracks or mark the requirement N/A. Original
source/history/input hash/public-span checks remain necessary.
2. Reuse the ONE existing missing_pose call in mcp_rig_pose_crud. Make its intended
output the existing half file with overwrite:true, while from names the missing
pose. Existing handler resolves that missing input before writing and returns
INVALID_PARAMS with a Pose file not found message; normal weight clamping stays
unchanged. Capture exact actual request/response, before/after output and complete
isolated directory bytes/hashes, temporal binding and source/scene identity.
3. A small source-specific helper/validator emits one typed-refusal snapshot case,
bound to the actual public pose_blend call and prior successful half output. No
external operation invocation is inferred from a fixture or generic suite total.
The shared pose CRUD driver is owned by the read worker: provide only a minimal
patch artifact for root to apply after that worker, never edit the shared file.
4. Pure actual-shape controls cover SpriteFrames path/resource/class/region/type
corruptions and pose error/request/source/call/file/directory/timing mutations.
All actual runtime receipts remain pending fresh root-owned execution.

## Prepared integration

Only the SpriteFrames adapter itself changes in the existing source. Its channel
uses the fixed SheetSprite path cast by the source-bound observer to
AnimatedSprite2D plus actual SpriteFrames/AtlasTexture, atlas path, four regions,
frame durations/size/FPS/loop/state and all original source/history checks. No
Animation track is created, inferred or declared inapplicable.

The narrow operation_pose_blend_refusal_checks helper instruments the existing
missing_pose request once, targeting the existing half output with overwrite:true.
It records full directory entries/bytes/hashes around the real returned refusal,
then joins the exact prior successful half producer and actual refusal by source,
scene, request/response, context and chronology. It emits typed_errors only.

The shared pose CRUD driver was not edited. Root must apply
`docs/patches/pose-blend-refusal-driver.patch` after the read worker's0ec6d48 (the
patch was generated directly from that version), then apply the small
`docs/patches/pose-blend-refusal-collector.patch` against current primary. Both
patches compile; source/collector baseline files are not imported into this commit.
Actual public execution and new source-bound receipts remain pending root's slot.

Nine new controls, thirteen existing FX intention controls and sixteen current
collector controls pass (38total) in pure temporary staging with the current
primary collector plus the minimal patch. Tests cover all four SpriteFrames
layouts without a generated Animation clip, resource/path/region/source mutations,
actual one-call refusal observer with real temporary directory bytes, wrong errors,
changed/new output entries, bad hashes, missing/wrong/duplicate actual call/context/
timing/source bindings and end-to-end typed-only collector case. Both patch
artifacts pass read-only git apply --check on current primary. No engine/public
execution occurred, and neither shared driver nor primary file was edited.
