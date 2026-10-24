# Windows preview execution checkpoint

Private evidence root: `E:/GodotAI-toolkit-release-2.0.0/20261014`.
No merge, tag or release is implied by local preparation.

## Preserved first attempt

`windows-previews-5eef8d5` contains two real extracted ZIP projects, exact
released cores4.2.1/4.3.0, without addon links. ZIP5eef8d5 validates94entries.
Core4.2.1 import succeeds, but the preview attempt never launches Godot: the
chosen development Python has FastMCP3.4.7 and other dependencies that the
released core explicitly rejects. Its exact backend traceback is retained.
The empty editor log causes secondary renderer validation to overwrite the
primary startup error. The runner now preserves the original error and records
secondary log failures separately. A regression exercises this actual run/finally
path, requiring startup failure to survive empty-log validation.

## Runtime preparation

Separate disposable Python3.11.15 environments are prepared under
`runtime-released-4.2.1` and `runtime-released-4.3.0`, from each exact released
core's pyproject requirements, plus Pillow12.3.0 for independent PNG decoding.
Both actual `verify_runtime_dependencies()` checks pass. Core4.2.1 requires
FastMCP4.0.5, while4.3.0 requires4.0.10; one shared environment is inappropriate.
The release checkouts and existing user backend are unchanged. Neither checkout
contains a uv.lock, so the failed initial locked-sync attempt is not described
as a locked installation. A second preserved attempt launches the NVIDIA editor
but the attach subprocess cannot import the core: PYTHONPATH is not its package
installation contract. Each disposable environment now installs its exact core
editable, without changing pinned dependencies. Import/version/runtime preflights
pass independently of PYTHONPATH.

## Actual two-core Windows success

Fresh `windows-previews-3dcb7f8-r003` completes both released cores at actual
toolkit3dcb7f849f2acd2e1f809c1f4d3d9d347f84e45e, Godot4.7.2.ed1daf0bf,
native OpenGL3.3/NVIDIA581.80/GTX1070Ti. Addons come from the validated94-entry
ZIP and exact core archives, without addon links. Separate ports/settings and
runtime environments preserve the user's existing backend.

Both actual public preview calls produce four nonblank, pairwise-distinct,
decoded320x240PNGs at requested0.05/0.23/0.47/0.71s. The strict independent
adapter verifies raw call identities, helper/source/core/platform/complete-log
renderer bindings, five source/timeline checkpoints, typed dry/missing/overwrite
refusals, and error-free complete editor logs. Original scenes/timelines remain
byte-identical. The two original failed attempts remain untouched.

Execution receipt SHA256:
`bc949d70567f5d94541b85d6b8e14f375846581ba3aecfd8c8604b0f4c58603c`.
Context421 SHA256:
`6651cc42c65d18f15042f8b080551f2d3f56c959412fe5bfb99ba97acc713cdd`;
context430:
`d43d73a4553c1639e82619e316c91a451a1a59a27b4650058d4ace4c069c97f1`.

Root independently views all eight original PNGs in a labelled derived contact
sheet: whole dummy remains visible including head/hands/feet, poses change with
time, and no crop/blank/corruption is seen. This is static preview assessment,
not continuous animation/contact/all-rig quality or human approval. Private
`independent-image-assessment.json` records exact original hashes and limits.
Linux two-core CI remains a separate required profile/matrix.

## Other completed capture and probe work

- Six saved setup recordings now complete1440frames/24s each: four blend views
  fromr005 at6f00b0f and two jump views fromr006 at5eef8d5. Native/PNG/full-decode
  receipts pass. Original interrupted704frame jump remains. Independent scoped
  temporal/pixel assessment now qualifies these six specified recordings; all8640
  PNG hashes, six fresh full decodes and all-frame skin/signal/framing traces pass.
  The reviewer examines896 distinct ordered frames across both views/takes/rigs,
  plus96 decoded endpoints and dense dummy jump details. No visible new crossing
  or abrupt knee flip; narrow inward squat and stiff/open hands are documented
  stylized limitations. No broader style/controller/turn matrix approval follows.
  Durable private evidence: `setup/independent-assessment-r001`.
- Showcase replacementr010 passes720actual bounds checks and full12s decode.
  Independent36frame/two-take inspection verifies full DriftLine visibility
  with at least50px right margin. Original crop evidence remains.
- Seven rig playback adapters are integrated, with corrected static probes
  independently replayed against two original saved fixtures and eight corrupt
  copies. See `rig-native-playback-adapters.md`. Fresh CI/public proof is next.

These results are bounded. The full operation audit, broader setup matrix and
remaining family media/candidate gates in `release-completion-plan.md` remain.
