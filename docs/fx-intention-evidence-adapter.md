# FX fixed-request intention and invariance evidence

Bounded implementation based on inspect worker c9b730a; integration target root
c5c2483. Production addon, historical fixtures, existing fixed FX requests and
runtime checker thresholds are unchanged. No Godot/editor/public endpoint run.

## Evidence design

The existing test_fx_route_history suite still dispatches the same 16 operations
through the actual public test_run inner dispatcher, in new/overwrite/
missing_library/instanced modes. It emits a new fx_intention_history_v1 row.
Legacy fx_history_v1 events retain their original adapter and scope.

New helper fx_intention_probe.gd duplicates the freshly generated fixture and
samples actual node properties with its manual AnimationPlayer at fixed authored
request times. Probe times and expected values are never read from generated
Animation keys. Python independently computes expected values from constants,
fixed requests/defaults and the unchanged authored repair_fx_fixture scene.

Examples: zoom at .075 is (1.08,1.08), .25 settles (1,1); damage value holds80
at .125 then reaches30 at .65; the dialog reaches .85/1.06/1 scales and 0/1
alpha; wipe_left scale0->1 with pivot(640,180); Card1/2/3 wave values follow
independent period1.2/amplitude12/phase.12 sine formulas; spring midpoint uses
frequency2/damping.35 analytic response and endpoint(0,-60); pendulum +/-18deg;
path endpoints(0,0)->(100,80); flipbook0->3 at fixed0/.75; counter actual text50
at .50001. Shake checks finite nonzero decayed amplitude envelope and exact
settling, without copying generator RNG output or claiming exact seeded waveform.

SpriteFrames is separately checked as a stopped SpriteFrames resource containing
four AtlasTexture cells, original source sheet path, exact16x16 regions/size,
fps12/looptrue/duration1. Audio separately requires actual playing event plus
one scheduled audio key at0 referencing the requested cue.wav. Neither proves
pixel rendering or audible output. No visual_review/playback promotion is added.

## Source and error scope

Raw snapshots retain all clip specs, original Player state, Path2D control points,
non-target whitelisted fixture properties and SpriteFrames state. Before/after
probe equality rejects pollution of the original fixture. Instanced cases also
retain exact packed source SHA, peer and pristine source snapshots. Authored
fixture/sheet/cue input file hashes before/after are checked against the actual
source context dependency SHA256s. The collector now includes the FX fixture
and these two binary inputs explicitly. Binary files themselves are unchanged.

Source_unchanged covers those observed inputs, unrelated clips and non-target
properties. It does not claim every engine/resource property is observed. The
case Logger spans fixture creation through actual dispatch/dry/refusal/history/
save/reopen/probe/cleanup. Complete synchronous case errors are checked; future
asynchronous errors and whole-session engine logs remain outside this proof.

The standalone operation_fx_intention_checks adapter first reuses the unchanged
strict history span validator, then enforces exact fixed operation request,
actual scene agreement and assertion timestamp inside the matching real public
test_run span. Dependencies bind driver/helper/adapter/fixture/production specs/
input files. An unknown or changed request refuses rather than guessing intent.
Legacy suite totals never create checks. A failed underlying history check
fails the new checks too, so failed observations cannot be hidden by new hooks.

## Offline validation and remaining work

13 new adapter tests pass, including 64 operation/mode cells and corruption
controls for each intention, wrong request, logger errors, unrelated clip/node/
curve/Player state, probe pollution, peer/packed/pristine source, binary digest,
scene/span, dependency, inert/nonfinite shake, audio stream and SpriteFrames
class/cell/fps/play state. Existing13 history +15 collector tests pass.
Python G:/godot-ai-dev/godot-ai-v4-animation/.venv/Scripts/python.exe (FastMCP3.4.7).
These are offline synthetic controls. Root must parse the GDScript in Godot4.7.2
and execute actual fresh public tests/CI before any candidate qualification.
No live values, error cleanliness or source invariance are claimed observed yet.
