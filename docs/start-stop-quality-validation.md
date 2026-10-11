# R2 start/stop: execution evidence

## Baseline tooling (2026-10-11)

Idle is closed on fixture source `b935cff`, Actions `38157142049`. The user
authorized this next phase with “then do it.” Follow
[the phase plan](start-stop-quality-review-plan.md); work alone on Godot 4.7.2
through the separate released core and public custom-tools API.

The existing capture client now accepts `walk_start` and `walk_stop`. Every
transition baseline and candidate uses a plain scene marker and an external
history witness. That witness undoes/redoes the single public write already
made, without creating another clip. It compares the restored animation digest,
root extraction binding, marker names and times, and the ordinary one-shot mode.
Normal editor-suite runs exercise the same witness with an ordinary dummy fixture.

Capture receipts now also compare the authored pose immediately after dry run.
Timing, phase, speed, sampling, recipe and loop overrides remain absent from
ordinary calls. This checkpoint changes tooling/tests only; accepted motion
generators and golden fixtures are preserved. Baseline playback and continuation
measurements are pending, and no start/stop visual approval exists.

Recovery: `release_r2_start_stop_20261011` beneath the existing PC snapshot root.
Never overwrite a completed route, source archive or review receipt. Preserve
partial attempts after interruption; new generation attempts use new UUIDs.
