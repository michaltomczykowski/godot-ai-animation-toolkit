# Historical motion/sequence derived-evidence audit

Prepared in a new isolated E: worktree at a9dc865; no engine, root checkout, historical bundle or producer changes.

## Confirmed oracle mismatches

1. Saved snapshots store Animation track key times in packed float32. Actual authored0.008 reopens as0.00800000037997961; authored1.2 reopens as1.20000004768372. Existing native snapshot matches_expected is true. The Python adapter required exact double equality. Only scalar track/keys/key-index/time-index0 slots now compare equal float32 representations. Adjacent float32 values, changed key values and unrelated resource fields still fail. Typed geometry rules and all original native error bounds are unchanged.
2. Existing native schedule is the union of0,length,FPS ticks,all track keys and their midpoints. Packed terminal keys may exceed animation.length within the existing length+1e-6 track bound. The adapter incorrectly required times[-1]==length. It now verifies both directions of the exact original schedule union, including the declared length; missing terminal keys, unexplained extra samples and keys beyond the original bound fail. No interval or numeric motion tolerance is relaxed.

Actual first Linux421 direct native derivation showed all track/path checks passed already; history save failures propagated failures into otherwise sound native checks. Before the schedule correction, direct native playback60/effect45 also failed independently. Both measured issues are adapter contracts, not demonstrated production animation failures.

## Validation and scope

Five history unittest methods and six native methods pass, including actual-shaped packed-time values and terminal schedules plus adjacent-ULP/value/path/extra/missing/bound controls. Existing thresholds, references, requests and fixtures remain untouched. New read-only recollection utility verifies every original raw artifact SHA, binds all273 actual public rows/native cases and preserves original tested_source/context. Its result kind is historical_operation_recollection with explicit auditor byte hashes, never present-source qualification.

Linux421 recollection:2002 original cases,273 motion/sequence cases reinterpreted;801 original motion/sequence failed derived checks clear, only the four unrelated FX valid_effect failures remain. Original tested source is fef33a779d7898f801527dfb0e6975ebad13059c, not the current audit worktree. Output private E:/GodotAI-toolkit-release-2.0.0/20261014/independent-motion-evidence-audit-r001/linux421/recollection.json SHA25686b7c265812267bc11b2db8889ab8bef2cd48a769d6e91b998d30642d700465c. Linux430 repetition is pending completion when this note is prepared; report its immutable result separately.

No source label, aggregate human/visual claim or original failed report was replaced. Native motion valid_effect remains out of scope for the output-duplicate reference. The strict CI gate proposal is a separate increment after these adapter corrections.
