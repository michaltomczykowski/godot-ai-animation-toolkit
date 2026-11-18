# Live FX contrast repair checkpoint (2026-10-16)

Tested addon source: `05cc8e7a3c18ec1a20d67cc20575f30c463bc9ad`.
Godot4.7.2 `ed1daf0bf`, released Godot AI4.2.1
`bfc264200584ea5823f18356acb164781f57796d`, Windows.

The visible editor was launched after the source change and observed with Godot
AI connected. Public requests used the actual addon connection; no clips were
hand-authored for this repair. Separate APPDATA under the new phase directory
preserves all earlier `user://` history scenes and failed media.

## Actual checks

- Pure FX suite:164 checks pass.
- Public regression: four default/explicit contrast cases,64 assertions pass;
  typed no-change/transparent refusals,40 assertions pass.
- Public FX history: all five selected tests pass, covering64 existing cases.
- Direct public FX:17 cases across16 operation keys pass dry/write/save/reopen.
- Public edit history: four tests covering72 cases and three contract tests pass.
- After public editor quit:64 fresh-process saved FX checks and146 saved edit
  states pass (three48-state layouts plus two3D contract states).

Raw private evidence: `E:/GodotAI-toolkit-release-2.0.0/20261014/effects/public-r007/`:
`operation-context.json`, original `public-calls/`, `public-result.json`,
`edit-public-result.json`, complete editor/public logs and `saved-native-r002.json`.

## Preserved evidence failures

The temporary in-process driver imported the FX audit, so its recorded snapshot
driver was `run_public.py`, rather than the supported source-bound audit CLI.
The full collector correctly rejected those snapshot assertions. This checkpoint
does **not** claim a qualified full collector bundle; rerun through supported
drivers for that gate. Actual public responses and all raw traces are retained.

An independent inner-history reanalysis found a separate adapter defect: signed
RefCounted instance IDs were incorrectly required to be positive. The old
derivation rejects72 edit dry/history rows despite exact preserved identities.
The nonzero/equality repair at95663c8 passes13 focused controls. Reanalysis of
the original136 FX/edit rows passes; its receipt identifies both the original
tested source and the newer analysis adapter. This is not a fresh candidate run.

The first temporary native wrapper also expected an `engine_errors` field that
the existing FX checker does not emit. Its failed wrapper result is preserved.
The corrected wrapper validates complete native stdout/stderr for engine errors
and the real checker schema; the successful second attempt does not replace it.

## Actual before/after output

The old default hit-flash capture has constant white modulation and no effect.
Its complete720-frame failed capture is retained and encoded separately as
`effects/before-inert-hit-flash-r006.mp4` (failed baseline, never qualification).
The fresh default pulse darkens the baseline modulation and restores it, with
intrinsic ColorRect color unchanged. Its complete12-second movie contains two
fresh takes,720 independently decoded1400x800/60FPS frames:

`effects/media-r007/case02/native-comparison.mp4` SHA256
`e0aed4ff8963db78f1573987ce67a216bece4a6df21fb2f797e267e381febf76`.

Independent temporal review inspected every60FPS frame in the first half-second
of each take and ordered two-per-second checkpoints through the complete movie.
All720 native frame target pixels were also checked: the unchanged left reference
is RGB76/51/51, the right pulse reaches23/15/15 around0.083s, and both sides are
exactly equal again by0.183s. The second take repeats that pulse and restoration;
every later target sample matches the reference. Full target framing and the
steady hold are readable. This is a scoped independent pass for this default
contrast fixture, not human approval or a claim about emissive white flashes,
other materials or the remaining effects.

The new immutable49-case plan uses36 fresh FX/edit operation scenes and honest
historical preset/library references. Queue/media receipts keep all broader
visual and release qualification pending. No merge, tag or release yet.
