# Setup evidence and native-save investigation checkpoint

The setup-only observer now runs through the actual Godot AI route before the
existing `secondary_motion` write. Both original explicit/omitted walk-speed
drivers pass at `b0de2168724ba7ea005968109a10581a7e615e2d` in23.172/21.578seconds.
Seven raw native observations retain one action's dry state, Undo/Redo, complete
saved reload and track targets/types. An exclusive setup-only scene copy preserves
the result separately from the later secondary edit.

The first strict report correctly preserved two path-check failures: the adapter
required TYPE_VALUE for the carrier, while the actual saved clips and production
builder use TYPE_POSITION_3D. The correction admits only the observed type1.
Reanalysis of both original raw rows passes all four scoped channels; all28
actual-row type/path/value corruption controls reject. Source/error, typed-error,
effect, playback and visual claims remain separate. Neither the original failed
report nor its tested source is rewritten. Private evidence:
`setup-public-history-witness-r001` and
`setup-public-history-carrier-controls-r001` under the release evidence root.

CI40099634465 Linux/core4.3.0 reproduced the allocator abort at the first public
scene-save call, before preview capture. The actual tested merge is
`621bbe49cd74b0b1af9515cf63bb28b021e54b18`; PR head4d99d20 remains distinct.
The failure is preserved in `ci-4d99d20-rendered-failure-r001`. Its cause is open.

An opt-in postmortem diagnostic keeps the ordinary Godot launch and public call
sequence. After a crash it binds the exact owned PID, ELF notes and binary before
bounded GDB analysis. Core memory stays outside uploaded artifacts; cleanup
deletes the owned core and restores the disposable runner's kernel setting.
Only diagnostic text/context can become artifacts. The CI caller temporarily
requests this mode; restore `none` before final normal release qualification.
See `preview-postmortem-plan.md` and `preview-postmortem-validation.md`.

The combined96 focused controls pass, including integration gates, raw inspection
references, setup corruption checks and preview diagnostics. Actual Linux core
generation/backtrace capture still requires CI. No native-crash fix is claimed.
