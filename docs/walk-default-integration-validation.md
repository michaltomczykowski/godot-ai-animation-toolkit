# R1: accepted walk default integration (in progress)

2026-10-10. Responsive/default use the exact r004 recipe through one resolver.
Grounded uses its separate recipe; relaxed/heavy/sneaky now decorate Responsive.
Configuration is resolved before measured arm axes. Missing implicit head/hand/
finger features are omitted with reasons; explicit unsupported controls still
fail before writes. Setup returns per-clip style/capability/sampling metadata.

Default density is 60/s. Jump, turn and start/stop report their authored 120/s
minimum and enforce the real interval budget. Cycles now default to linear loops
as documented (previously the inherited bone handler chose none and appended a
terminal hold to a normal rooted walk). Explicit loop/root flags remain honored.

## Fresh supported-core checks

Separate released Godot AI v4.2.1 checkout:
`bfc264200584ea5823f18356acb164781f57796d`, original custom 4.1.0 untouched.
Fresh visible Godot 4.7.2 runs the isolated project
`test_project/repair_r1_validation_20261010` on ports 8000/9500, with isolated
APPDATA under the recovery folder. Public authenticated attach/MCP probe finds
all ten families/eight promoted tools, typed family errors and no missing schemas.

Fresh motion suite: **57/58 passed, zero skips**. New checks cover four-rig
default/explicit/alias/setup equivalence, optional anatomy, explicit typed
refusals, precedence/metre preservation and actual one-shot density/budget.
All existing contact, hand variation, articulation, history, and run/idle goldens
in this suite pass. The one failure is the intentionally preserved pre-v2 walk
golden (20 tracks, versus 38 with the accepted hands/fingers). A separate pure
proportions golden also differs after the intended profile change. Do not hide
these failures or overwrite either historical fixture before review. Final
green regression remains an R1 exit gate after visual approval.

First attempts are archived: a missing test-local type annotation, old sample
expectation and test anatomy aliases were corrected. Test-renamed skin bones are
restored before teardown; the fresh second run has no engine errors.

## Remaining before feedback pause

- Save/reopen normal calls for all five styles on four rigs through public MCP.
- Compare matched-input default playback with original r004 at 30/60/120 FPS.
- Contact-check all styles at actual 30/60/120 FPS; core reload discovery/calls.
- Capture clean/diagnostic front/side continuous videos, decode/hash/archive.
- Open PC Explorer and pause for explicit default/Grounded/variant feedback.

These are candidate defaults on the review branch, not a release or approval of
other motions. Non-walk profile tables still have their own previous baselines;
R2 authors/reviews them separately rather than copying walk controls into them.

Recovery root:
`F:\GODOTAITESTING\toolkit_repair_snapshot_2026-09-30\release_r1_20261010`.
