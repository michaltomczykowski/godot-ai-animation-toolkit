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
as a locked installation. Fresh public rendered preview remains pending.

## Other completed capture and probe work

- Six saved setup recordings now complete1440frames/24s each: four blend views
  fromr005 at6f00b0f and two jump views fromr006 at5eef8d5. Native/PNG/full-decode
  receipts pass. Original interrupted704frame jump remains. Independent scoped
  temporal/pixel assessment is in progress.
- Showcase replacementr010 passes720actual bounds checks and full12s decode.
  Independent36frame/two-take inspection verifies full DriftLine visibility
  with at least50px right margin. Original crop evidence remains.
- Seven rig playback adapters are integrated, with corrected static probes
  independently replayed against two original saved fixtures and eight corrupt
  copies. See `rig-native-playback-adapters.md`. Fresh CI/public proof is next.

These results are bounded. The full operation audit, broader setup matrix and
remaining family media/candidate gates in `release-completion-plan.md` remain.
