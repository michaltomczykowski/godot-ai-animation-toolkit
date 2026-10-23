# Setup matrix recovery, 23 October

The interrupted `production-r007` run completed all 30 public setup groups:
120 saved rig cases across five styles, three ownership variants and both turn
choices. Fifteen prior rows were reused after exact production dependency,
request and scene hash checks. The other 105 rows ran through Godot AI.
Source: `233562a776bf8deac6177cf9b67cbe2ae1efdedf`, released core 4.2.1,
Windows, Godot 4.7.2. The original route receipts remain unchanged.

CI run [39118728182](https://github.com/michaltomczykowski/godot-ai-animation-toolkit/actions/runs/39118728182)
completed successfully, including the released core/platform and clean ZIP jobs.
That result belongs to its actual tested merge checkout; it does not qualify
later source changes.

## Native playback failure and measurement correction

Saved playback passed the first two groups, 60 plays each. The third group,
Responsive stationary in-place without turn, failed only its 12 jump endpoint
checks. All four rigs and three frame rates showed 3.39–10.14mm horizontal
differences. There were no engine errors. The old measurement subtracted initial
hips at idle phase zero from final hips at a later idle phase, counting normal
idle sway as character travel.

The checker now loads the original saved scene independently and plays its idle
clip at the actual final idle phase reported by the Tree. It subtracts the two
hips points in world space. Rig/ancestor translation remains detectable. The
reference clip, phase, finite points and native skeleton refresh are explicit;
missing or invalid references fail with an unavailable measurement sentinel.
The independent all-bone recovery and ownership checks remain in place.

No generated animation, production addon, scene, request or physical threshold
changed. The endpoint tolerance is still 0.1mm. This correction was independently
reviewed before replay.

## Executed controls

The original failed group now passes all 60 plays. Its 12 jump endpoint errors
are zero at report precision. The native corruption harness then passes all 12
positive controls and rejects all 72 deliberate negative plays, across four rigs
and 30/60/120 FPS:

- 0.2mm horizontal pelvis residual, rig drift and ancestor drift;
- wrong reference clip or phase;
- requested 0.2mm displacement that the scene does not retain.

Both actual engine logs contain no engine/script errors. Private evidence:
`E:/GodotAI-toolkit-release-2.0.0/20261014/setup/native-endpoint-recovery-r001`.
`independent-validation.json` binds every report/log and both checker sources.

The first corruption attempt is also retained: its Z-up pelvis offset was
accidentally vertical because it used skeleton space instead of the bone parent's
world basis. Only the control's conversion changed for the second attempt. No
old report was rewritten as a pass.

Next: replay all 30 already saved groups serially with this checker. Broader
native matrix completion, remaining operation evidence and continuous media
qualification are still required before release.
