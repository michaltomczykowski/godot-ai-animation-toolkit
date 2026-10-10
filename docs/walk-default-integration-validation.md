# R1: accepted walk default integration (video review pending)

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

## Public routes and native playback

Saved public routes now pass for **20 normal style clips** plus eight matched-
input clips. Sixty four-rig contact/loop runs pass at 30/60/120 FPS. Twenty-four
native matched-input comparisons pass against the original saved r004 output
(position/root <=10 micrometres, rotation <=0.0001 rad). Forty style dry calls
before/after core reload preserve inspected clips. All ten families remain
registered on the released core. The fresh headless check is **13/14 suites**;
only the preserved pre-v2 proportions golden differs. A docs-root failure in
the isolated fixture was corrected by running that filesystem-specific suite
from the canonical test project, where it passes 2012 checks.

Animation source `056cc8d19d9821086346816345e1c4feab0041dd` is pushed. Later
checkpoints change documentation and review tooling; addon animation code is
unchanged from that exact source. All ten captures are complete.

Across each style's twelve native runs, the measured maxima are:

| Style | Declared stance slide (mm) | Rest ankle plane penetration (mm) | Knee flips | Generation reach clamps |
| --- | ---: | ---: | ---: | ---: |
| Responsive/default | 0.115 | 0.689 | 0 | 0 |
| Grounded | 0.115 | 0.599 | 0 | 0 |
| Relaxed | 0.080 | 0.393 | 0 | 0 |
| Heavy | 0.107 | 0.513 | 0 | 0 |
| Sneaky | 0.057 | 0.191 | 0 | 0 |

These are independent played world-space ankle measurements with declared contact
markers. They do not establish skinned sole collision or a center of mass, and
do not grant visual approval.

## Continuous review delivery

All five styles have clean and diagnostic **48s 1080p60 H.264 MP4s**, independently
decoded to 2,880 frames each. All ten render error logs are empty. Each video has
six continuous seconds front and six side for dummy, X Bot, short and tall Z-up.
The original accepted r004 Responsive clip is on the left (r004 Grounded for
Grounded); the actual normal-call candidate is on the right. Style-selected
implicit speeds differ, so captions report ground travel rather than claiming
matched speeds. The default candidate uses no style, recipe or sampling override.

The strict R1 archive checks all public/native/reload/media receipts, original
r004 comparison provenance, scene hashes and single-owner travel. It preserves
28 new scenes plus eight reference scenes, local rig assets, animation source,
current documentation/tooling, ten review copies and SHA256 receipts. Private
media/assets remain local. Rerunning the archive retains previous delivery
history and Explorer metadata; recorded feedback cannot be reset by rerunning it.

PC File Explorer is open to `review-videos` with
`walk-default-responsive-r005-clean.mp4` selected; the folder and selection were
verified through Windows Shell. `START-HERE.txt` describes the chapters and review
checklist. Playback by the user has **not** been inferred from opening Explorer.
Review state is `awaiting_promoted_walk_styles_feedback`, with all five new
approval fields null. Top-level baseline fields are preserved history; current
source/evidence/media are in `promoted_walk_review`.

**Pause here for explicit Responsive/default, Grounded, relaxed, heavy and sneaky
feedback covering all four rigs.** Then migrate the two historical goldens and
run full green regression as the remaining R1 exit gate. R2-R5 and release remain
pending. Numerical success and completed media do not grant visual approval.

These are candidate defaults on the review branch, not a release or approval of
other motions. Non-walk profile tables still have their own previous baselines;
R2 authors/reviews them separately rather than copying walk controls into them.

Recovery root:
`F:\GODOTAITESTING\toolkit_repair_snapshot_2026-09-30\release_r1_20261010`.
