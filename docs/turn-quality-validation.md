# R2 turn execution and retained evidence

## Baseline, 2026-10-13

Source `2446bce`: 32 public Responsive calls (90 left/right, two-step 180
left/right; four rigs; both requested root flags) pass dry pose nonmutation,
actual external Undo/Redo, saved-scene reopen and track inspection through
Godot AI 4.2.1 on the visible Godot 4.7.2 editor. Each write ran once. Separate
session attach retries only perform connection/readiness reads.

UUIDs are recorded in each `baseline-r001/<variant>/attempt-*.json`. Independent
checker receipt: `baseline-r001/native-c4d8ee6f81174e4389f267dede725047/matrix.json`.
All 192 Player/Tree/FPS runs complete with zero engine errors and correctly
fail quality checks. Missing contacts/reach metadata, planted-foot rotation,
unfinished foot recovery and played discontinuities are exposed. In the 60 FPS
left-90 Player examples, the unrecovered foot endpoint error is 0.1293 m on
dummy, 0.1298 m on X Bot, 0.0711 m on short and 0.2070 m on tall Z-up.
Planted-foot heading changes exceed 90 degrees. A passing final hip heading
alone does not establish a working turn.

The old turn test applied only one rotation track to a reset skeleton when
measuring torso yaw, ignoring animated parents. Its helper now uses actual
AnimationPlayer seek with all tracks and a rest-relative projected heading.
New checks compare pole directions in the played hip frame, so accumulated
body yaw alone is not a knee flip. Controls corrupt isolated Animation
resources and replay them; original scenes/poses are never edited by checks.

Four continuous baseline clean movies are recording before wiring the new
planner. Partial receipts and raw logs remain in the recovery folder. No
baseline visual approval or turn candidate approval has been requested.

## Repair design refinement

Keep requested `steps` as dominant pivot stages, alternating leading feet.
Add one final catch-up/recovery footfall so both feet settle in the new heading;
report `recovery_steps` and `footfalls` explicitly. A two-stage 180 turn has two
dominant heading transfers and a final stance recovery. During a contact window,
both the ankle target and foot heading remain fixed. Swing yaw and displacement
finish before contact resumes. Torso targets must be converted against played
generation-parent frames instead of keying full accumulated yaw into every
joint. Planning computes reachable pelvis lowering before solving legs; no
silent clamps, inert zero-angle successes or silent step-count truncation.

Reference contracts: [AnimationMixer](https://docs.godotengine.org/en/4.7/classes/class_animationmixer.html)
for manual Player/Tree evaluation and separate rotation/translation extraction;
[Animation](https://docs.godotengine.org/en/4.7/classes/class_animation.html)
for saved native bone track paths and interpolation. Actual turns currently own
skeletal heading; they do not extract actor yaw. Requested root flags must be
reported separately from effective ownership.

## Pending gates

Wire and measure the turn-local repair, preserve failures, validate controls,
complete style/timing/alias/setup/reload/regression and source CI as required.
Record continuous candidate footage and pause for explicit user feedback.
R2 turn is not yet approved; remaining R2/R3-R5 release gates still apply.

## Focused repaired candidate, 2026-10-14

Animation/checker source `ac309b7`, candidate `candidate-r004`: **32/32** public
Responsive clips and **192/192** native Player/Tree/30/60/120 plays pass. Each
direction has 90 and two-stage 180 cases on four rigs and both requested root
flags. Effective heading ownership is skeletal, with no extracted actor yaw.
Original caller bindings, dry poses, actual external Undo/Redo, save/forced
reopen and saved track/marker counts pass. Metadata now reports actual evaluated
reach, contacts and the extra recovery footfall. Both final feet, chest/head
heading and the intermediate 180 pivot settle correctly. Source contract docs
and operation inventory are updated; inventory remains 103 partial rows, zero
release-wide verified rows.

Native matrix: `candidate-r004/native-ce47e422f4bf4da2a5dcb1438e8e4c86/matrix.json`.
Controls: `controls-r004/summary.json`, **24 positive** plus **120 negative**
plays. Missing contacts, inert output, incorrect final heading, stance slide and
double actor yaw are each detected on every rig/FPS/mixer combination, without
engine errors or saved-scene mutation. Public motion regression **74/74** passes
on a fresh editor. Continuous clean/diagnostic movies are recording.

### Retained failed attempts and corrections

- Original baseline: 192 completed runs fail quality; four 24-second continuous
  MP4s are complete and decode-verified before wiring the repair.
- Candidate r001: eight left-90 public clips and 48 native plays pass the initial
  checks; no visual approval. Later checks add saved marker/actor/torso coverage.
- Candidate r002: 16 successful 90-degree public clips; first 180 request returns
  a typed nonmutating reach refusal. The initial client then tried a history
  witness on the absent clip; its failure is preserved. Client now stops on the
  actual refusal before invoking history.
- Reach planning now computes base correction across every pivot boundary
  before dividing interior corrections by a phase envelope. Candidate r003 has
  32 public passes and 192 native runs, which correctly fail for dropped markers
  and over-fast 180 foot recovery. Its failed positive control remains preserved.
- Godot's actual saved clip retained one marker at coincident event times, losing
  one initial/final foot event and a coincident settle/contact event. Turn now
  groups same-instant events, preserves phase marker names, and returns the real
  `start_marker`/`end_marker` names on each contact window. No event time shifts.
- Omitted turn timing now allows 0.7 seconds per pivot stage, adjusted for angle
  and with a one-second minimum. Explicit timing is unchanged; insufficient
  timing receives a typed refusal. Default two-stage 180 takes 1.4 seconds.
- `aa85243` failed CI on the original multi-pivot refusal; its failed logs are
  preserved. `ac309b7` editor tests pass on Linux, but generated operation-audit
  text was stale after registry wording changed. `8a0f9bc` refreshes that text
  without changing addon/checker/renderer code. Final exact-source CI is pending.

### Remaining after the focused review

Record and deliver eight Responsive clean/diagnostic movies; archive source,
scenes, rig dependencies, checks and failures; finish local full editor/headless
and exact-source Windows/Linux CI. Open Explorer and pause for focused turn
feedback. Complete other styles, timing, alias/setup/reload and full 160-clip /
960-play closure after that feedback. Skeletal heading does not imply an actor
yaw consumer or guaranteed heading retention when blending into an unrelated
idle; controller/graph ownership and actor-wrapper contracts remain explicit
R3 integration gates. Broader same-time marker handling also needs release-wide
audit; this turn repair does not prove every other family's marker contract.

## Delivery and manual pause, 2026-10-14

Eight candidate and four baseline continuous 24s MP4s are complete and
decode-verified (1080p60 /1440 frames each). PC Explorer shows all twelve
plus START-HERE, repaired left90 clean selected. No video playback or
visual approval is inferred. The review is focused Responsive only.

Local400/400 editor,74/74 public motion,14/14 headless and both registry
probes pass. Exact-source CI8a0f9bc /38475599599 is green: 28 headless
jobs, four editors398/400 with only two named private-rig skips, both
live routes118/118. Six raw logs/source identities archived; current
generator/checker/renderer dependencies are identical. Protected eleven
fixtures unchanged, accepted gait digest drift zero.

Six ZIP CRC/hash checks,121 attempted scene entries and12 movie copies
pass independent verification. Four source ZIPs match all44 protected
Git blobs. The first archive attempt used Windows autocrlf exports and
failed the exact-blob gate; preserve its partial ZIP/copies. New delivery
is candidate-r004/delivery-r002 using canonical archive configuration.
Collector setup initially lacked its output folder; the local receipt
parser initially expected an equals sign instead of the actual colon
in probe markers. Both were corrected without rerunning or weakening
tests. First scripts/errors remain preserved. Receipt ZIP snapshots
precede final delivery/PC/independent/human receipts, which are saved
separately and documented on Git. Pause for focused user feedback.

## Focused feedback and closure continuation, 2026-10-14

User says “let's say they do, do next” about the presented Responsive turn
videos: qualified acceptance of that focused set; watched files/rigs unspecified.
Receipt: release_r2_turn_20261013/approved-responsive-r004-feedback.json.
Preserve source ac309b7, all 32 clips/192 plays and twelve delivered movies.
Full turn/style approval and release approval remain pending. Follow
docs/turn-quality-closure-plan.md: remaining 128 public clips/768 native plays,
timing/alias/setup/reload checks, continuous full-style videos, then manual pause.
Work alone with Godot4.7.2 through the separate Godot AI public tools API.
Keep approved motions/eleven fixtures unchanged. R2/R3-R5 still remain.


## Full ordinary turn matrix green — closure checks/recording active (2026-10-14)

Qualified Responsive acceptance is preserved. Remaining four styles now have
128 public saved/history passes and 768 native passes; combined ordinary set
is 160 clips/960 Player/Tree/FPS plays. Addon unchanged from accepted ac309b7;
new clip source d177383. Eleven protected fixtures and twelve prior movies exact.
New contract/setup-history/reload probes are committed at b5ae31d and pushed;
CI38536815930 pending. Public timing/alias/setup/refusal/reload and local regression
run in release_r2_turn_20261013/closure-r001; inspect their receipts before retry.
Existing client gained a cycle entry option and history witness a setup branch
during the ordinary batch; neither branch was used by those calls. Per-route
client hashes are retained. Production addon stayed clean and unchanged.

32 new movies are recording, three styles on G:/godot-ai-dev/toolkit-turn-closure-capture-20261014
and Sneaky on closure-r001/capture-sneaky to distribute frame storage. Read
recording-progress.json before retry; preserve frames and receipts. Playback
uses saved native clips, one bone writer, no actor-yaw consumer. Source b5ae31d
adds exact saved-key/interpolation/marker and played alias/setup comparisons,
typed nonmutating refusals and an actual before/after core reload matrix.
No other-style or full-turn approval yet. Finish gates/media/archive and pause
for new style video feedback. R2 remaining motions, R3-R5 still pending.


## Turn alias discovery repaired — fresh setup retry active (2026-10-14)

The cycle handler supported turn but its preset enum/docs omitted it. Schema
5dc849a now exposes turn and angle/direction/steps; still ten families/103 ops.
Generation/playback code remains exact ac309b7; only the registry schema differs.
CI c5c1540 /38538308917 is pending. New current editor PID28400, source c5c1540,
Godot4.7.2 visible; previous PID27508 quit through the public API.

Preserve closure-r001 failures: schema commit briefly interrupted the next
reference batch at the clean-source guard, before writes. All six timing/eight
alias clips and twenty completed setup references were reused after hash/code
checks. A setup history witness then assumed an empty initial binding: X Bot
actually has XBot:position. Client now reads the fixture binding and confirms
it through public node properties before testing exact Undo restoration.
Failed two-scene setup attempt remains in contracts-r001/setup; fresh setup-r002
is running. Active launcher run-closure-after-setup-r002.ps1 then performs
refusals, core reload, public motion/full editor/headless regression.

Docs generator was initially invoked from the nested validation project and
resolved the wrong output/evidence directory; its generated file is retained
as closure-r001/incorrect-project-root-op-index.md. Correct repository-project
exports pass: 103 partial rows, zero release-wide verified. Updated docs/audit
are committed. Capture continues independently; inspect both progress receipts.
No new visual approval, no release. Finish closure delivery and pause for review.


## Active turn setup/checker retry r003 (2026-10-14)

Current launcher: release_r2_turn_20261013/run-closure-after-setup-r003.ps1.
Current visible editor PID28400. Setup-r002's four public/history calls passed,
but three dummy Tree comparisons exceeded the initial 1e-6 rad tolerance by
~0.087e-6 rad. Saved channels/interpolation/markers are exact, positions/root
identical, other rigs pass, and no engine error. Retain that failed parity.
New checker reports an explicit 1e-5 rad played rotation tolerance (~0.00057 deg)
for float32 mixer/basis evaluation; exact authored data and 1e-6 m position/root
gates remain mandatory. Contact/heading/reach/discontinuity checker is unchanged.
Reuse the four completed public scenes; generate other setup groups fresh in
setup-r003. First Responsive and subsequent style groups are passing.
Source03df031 /CI38538734146 in progress. No generation code changed.
Capture remains active. Finish setup/refusal/reload/regression/CI/media and pause.


## All turn closure checks green — complete videos, then pause (2026-10-14)

Full ordinary set: 160 public clips/960 native Player/Tree/FPS plays. Additional
24 timing clips/144 plays; eight aliases/48 plays+48 parity comparisons; 24
setup turns/144 plays+144 parity comparisons; 28 typed nonmutating refusal pairs;
320 dry calls across an actual released-core reload. Both schemas expose turn.
Local400/400 editor,74/74 public motion,14/14 headless and two registry probes
pass; all eleven fixtures exact, walk/run/idle golden drift zero. Contact checker
unchanged from its 24 positive/120 corruption controls. Animation code remains
ac309b7; registry-only schema repair at5dc849a. Source03df031 /CI38538734146 is
fully green: 28 headless jobs, four editors398/400 with only the two named local
private-rig skips, both live routes118/118. Six raw logs and source/tree identities
archived. This does not approve visuals or close broader R2/R3-R5 gates.

Receipts: release_r2_turn_20261013/closure-r001/local-gates.json,
source-ci-03df031/ci-receipt.json. Native backup independently verifies534 new
saved scenes plus working notes. Existing focused delivery and qualified human
acceptance remain intact. Pure headless checks initially used the nested clean
project; the docs-location test failed. All14 pass in canonical test_project;
retain original two logs and headless-r002 retry. Other setup/source/precision
failures are retained as documented below. No full regression was discarded.

Visible editor is closed. Capture roots: G:/godot-ai-dev/toolkit-turn-closure-capture-20261014
(Grounded/Relaxed/Heavy,24 movies), closure-r001/capture-sneaky (eight movies).
Sneaky runs separately after editor shutdown and RAM preflight; parent later
verifies/reuses that completed stage, never regenerates it. Read each
recording-progress.json; preserve all frames and receipts. Finish32 new movies,
combine with12 preserved movies, run archive_turn_closure.py, independently
verify delivery, open Explorer and STOP for remaining-style feedback. No release.
Next strafe plan is prepared in docs/strafe-quality-review-plan.md; implementation
waits for this turn review. Setup coverage here is single-stage90-degree turns,
all styles plus explicit right duration; broader setup/controller contracts stay R3.

