# Bounded existing setup source/error/refusal observations

Scope only character_setup source_unchanged, reported_errors and typed_errors.
No valid_effect, visual, new setup writes, product response oracle, engine launch,
primary edits or budget changes. Existing public explicit/auto setup requests and
original returned outputs remain intact.

Existing7phase stored observer already reads full scene stored properties/resource
alias graphs, bone rests/poses, external file hashes, source clips and histories.
Source proof can use an independent fixed mutation mask: new root AnimationTree,
new Skeleton/SetupGrounding child, root Player libraries/root-motion binding only.
Preserve every preexisting node/property/bone/resource/clip/file outside that mask;
check exact expected generated clip-name set, original node identities before save,
and canonical source equality after reload. Do not use setup response fields.

The existing unreachable_setup call (speed8/run_speed10) already expects a real
VALUE_OUT_OF_RANGE reachable-solver refusal. Add only read-only native snapshots
before/after that existing call and bind its exact request/response/order to prove
stored scene/resource/file/history atomicity. Do not duplicate the call or rely on
the later invalid-skeleton request after secondary_motion.

Add a narrow token-owned Logger interval to the existing native observer around
this refusal and around the original dry/write setup calls. Reuse the existing
Stored.Errors class, without touching its shared active state. Close each Logger
at the next matching native boundary; provide a read-only cleanup phase for an
aborted scope. Capture raw error entries and exact begin/end token/phase metadata.
This proves synchronous case-local authoring intervals only; Undo/save/reopen and
future asynchronous/full-editor errors remain outside this error claim.

Preserve the original7phase adapter/history outputs. Additional refusal rows and
error witnesses are required only for these3new channels; old rows lacking them
remain pending for these channels. Wrong/malformed/refused bindings or invariant
corruption fail. Minimal shared driver/test/collector patches will be artifacts
against current primary where needed. Root owns actual parse/public execution.


## Prepared implementation and integration

The adapter retains the original seven-phase derivation and accepts two extra
read-only refusal phases only as a complete pair. Every added native row is
bound to the existing exact public helper test span. The original refusal and
positive dry/write requests are reused; no successful authoring call is added.
Original outputs, process/readiness/native budgets and older raw receipts remain.

`operation_setup_source_checks.py` checks a fixed mutation mask independently of
product response contents. It requires the fresh root Player to have no clips or
libraries, preserves all original stored node/resource/bone/peer data, preserves
original node identities before save, checks the exact generated clip set, and
compares canonical reloaded non-target source plus external/toolkit file hashes.
The expected new AnimationTree and SetupGrounding are authoring targets, not
independent proof of their effect. Imported-instance editable flags are outside
this snapshot and explicitly excluded from this channel's claim.

Logger intervals cover the existing unreachable refusal and original dry/write
calls, plus intervening read observations. They do not claim whole-session error
absence or cover later save/history/asynchronous errors. Missing legacy Logger
or refusal observations remain pending. Malformed scope identities fail; actual
raw errors fail. Original seven-phase evidence is retained without rewriting.

Root integration must also apply the minimal artifact
`docs/patches/setup-three-channel-helper-phases.patch` to the large current
`test_animation_motion.gd`; this worker did not baseline-copy that shared file.
No collector patch is required: its existing setup persisted-event dispatch
already forwards all raw phase rows to the adapter.

Pure verification (venv Python):

```powershell
& G:\godot-ai-dev\godot-ai-v4-animation\.venv\Scripts\python.exe -m unittest discover -s tools -p 'test_operation_setup*checks.py'
```

Actual GDScript parse and released-core public execution remain pending and are
owned by root. This increment prepares three source/error/refusal channels; it
does not qualify current raw receipts, motion effects, native playback or visuals.

## Integration correction before fresh execution

Actual historical stored snapshots name the root Player's default library slot
`libraries/`. The first mask removed `libraries`, so it retained authored target
resources and falsely reported source differences. The corrected mask removes
only the exact default slot and independently requires its native resource alias,
AnimationLibrary class and five-clip set. Other library properties remain outside
the mask and are rejected if changed. A real-shaped control checks wrong alias,
class, extra library and missing clip. Both preserved historical source predicates
now pass; these diagnostic rechecks do not relabel old reports or qualify the new
logger/refusal observer.33 combined source/history/collector controls pass.
