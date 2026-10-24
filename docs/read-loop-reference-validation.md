# Loop reference correction validation

Base18aa059. The original strict public read failures at ecbfdcb remain preserved under private `inspect-public-witness-r001`; no existing receipt or numeric evidence is rewritten.

The independent helper now retains configured `Dummy:position` extraction for both reads. It captures track index20/typePOSITION_3D, rootlocal flag, clip length/linear-loop mode, raw extracted worldbone points, identity basis, and separate engine `Animation.position_track_interpolate` start/current/endpoint vectors. Python requires exact metadata and finite vectors, matching start/end bindings, and reconstructs audit travel by float32 subtraction then addition after FK. Sample positions remain extracted and unchanged. The native clock must equal requested time at every earlier frame and must be0at the exact1second loop endpoint only.

No public request, fixture, addon, physical metric budget or report comparison tolerance changed. The collector uses existing dispatch; no collector or CI file change is needed. The45second eight-read driver cap remains a separately diagnosed runtime issue (actual77.922seconds), for root integration.

Offline validation:9numeric controls and10existing witness/adapter controls pass. New controls cover exact endpoint wrap versus premature/stuck/lag/wrongwrap, wrong root binding/type/index/local/basis/pose source, malformed/nonfinite root vectors, separate hand-calculated .125m root plus .03m local travel, corrupt root endpoint/interior and inert local points. Existing threshold and report corruption controls remain. Python compiles; diff whitespace check passes.

No Godot parse or actual native/public execution was performed. Root must parse the modified GDScript and capture fresh references before admitting either numeric check. In particular, the prior left extension peak-time precision discrepancy is not declared resolved until a fresh extracted-pose-plus-separate-root observation agrees. Private counterfactual arithmetic is diagnosis only, not qualification. No skin, visual or broader native qualification is introduced.
