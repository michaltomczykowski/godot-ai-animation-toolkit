# Start/stop r002: coordinated body reaction

## Human feedback, 2026-10-13

The r001 movies were delivered and preserved. The user requested changes:
“feels a little bit too stiff, the body needs to react too, not only legs”.
This is not approval of r001. Walk, run and idle remain accepted and unchanged.

## Motion change

1. Add a deterministic reaction only inside the transition's middle window.
   Its value and velocity vanish before the exact idle/walk reference windows.
   Keep the reference sampling, foot schedules and actor travel schedule.
2. Shift the pelvis toward the supporting foot and into acceleration/braking.
   Add modest pelvis pitch/roll, compression and settling. Scale distances to
   leg length and bound reaction strength by speed and transition duration.
3. Carry that response through the connected torso, with delayed chest recoil,
   cervical counterbalance and shoulder/arm/forearm/wrist follow-through.
   Convert rotations through the animated parent and measured rest frames;
   distribute spine/cervical rotation by rest lengths, not bone count.
4. Apply the body layer before reachable-target planning and leg solving.
   Recompute the necessary pelvis reach drop; retain typed nonmutating refusals,
   stable knee poles, the original ground contacts and one translation owner.
   Optional missing upper anatomy must be reported as omitted, not invented.

## Focused review checkpoint

First generate ordinary Responsive start and stop on all four rigs, through
the visible Godot 4.7.2 editor and actual Godot AI custom-tools API. Verify
dry run, pose nonmutation, external Undo/Redo and saved/reopened scenes. Play
both root modes with AnimationPlayer/AnimationTree at 30/60/120 FPS against
the independent accepted walk/idle references. Existing contact, reach and
continuation thresholds stay unchanged.

Measure the played pelvis/chest/head/arms against r001, including endpoint
agreement and unchanged actor travel. These measurements establish that the
body actually reacts; they cannot approve visual quality.

Record two continuous clean r001-versus-r002 MP4s (start and stop): front and
side views, two reset-separated takes per rig, all four rigs, 1080p60. Preserve
the source, scenes, numerical receipts and media hashes in a new folder. Push
the review branch, open PC Explorer and explicitly pause for human feedback.
This early checkpoint avoids recording all styles before the reaction is
reviewed. It is not the final 80-clip/480-playback acceptance or release gate.

## After feedback

If changes are requested, preserve this attempt and revise. If approved,
complete five-style ordinary/timing/sequence/reload/regression and exact-source
Windows/Linux gates, record the complete style/sequence pack and request its
review. Only then close start/stop approval and advance the remaining roadmap.

## Execution ledger

- Planning: r001 delivery remains intact; feedback stored as changes requested.
- Implementation, played checks and continuous movies: pending.
