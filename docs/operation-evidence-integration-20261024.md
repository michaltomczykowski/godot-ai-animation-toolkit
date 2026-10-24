# Operation evidence integration, 24 October 2026

## Scope and status

Combined the prepared rig scene history (93 cases), motion/sequence history
(273 cases), authored rig clip playback, twenty clip edits, sixteen UI/FX
intentions, five bounded reads and saved graph/rig capture guards. These extend
observations and strict evidence collection around the existing public Godot AI
tests. They do not change production animation generation or approved fixtures.

The combined Python corruption controls pass: 82 unittest methods, including
missing source/hash/clock/value/path, disabled track and false exit-code cases.
This is offline checker verification. Actual GDScript parsing, public/native
execution and fresh Windows/Linux CI remain required before qualification.

## Native arithmetic correction

A separate Godot 4.7.2 official standard-build process emitted 100 vector and
100 quaternion metric samples. Python double arithmetic disagreed with the
native error by more than 1e-12 in 46 vector and all 100 quaternion samples.
Maximum differences were 3.76e-12 m and 4.16e-8 rad respectively. The new adapter
reproduces native float32 intermediate rounding and expression order; all 200
errors now agree exactly. The 1e-12 reported-error check and the original
0.0001 position/scale/root and 0.001 rad rotation gates remain unchanged.

Private diagnostic: `native-metric-probe-r001/independent-validation.json` under
the local release evidence directory. Observation SHA256:
`2211ff994f6f1d3310ec98681d6486c437fcd96f5a90b68854c7b9d54cd4d248`.
Recorded witnesses and deliberate corruptions are retained as regression tests.
This arithmetic diagnostic is not an animation quality or public route proof.

## Limits retained

- Motion references duplicate the output and qualify playback/path/type only;
  they cannot independently establish intended physical motion.
- Sequence/secondary references derive from saved source/rest and require a
  noninert reference. Manual native sampling does not establish artistic quality.
- Read sampling and motion audit still need independent numerical effect proof.
- Saved rig framing currently covers the staged unskinned synthetic fixtures;
  mesh/skin capture is explicitly refused by that capture contract.
- Continuous media review and final candidate/package qualification remain open.

## Next steps

Merge this integration into the repair branch, parse the changed scripts in
Godot 4.7.2, run fresh CI and freeze the validated checkpoint. Replay all 30
setup groups (1,800 plays) from the exact preserved public scenes, retaining
their original public source and dependency hashes separately. Continue the
remaining family media and operation ledger work after this checkpoint.
