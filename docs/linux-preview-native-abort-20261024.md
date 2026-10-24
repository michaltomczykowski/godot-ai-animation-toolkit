# Linux rendered-preview native allocator abort

## Observed evidence (not a repaired failure)

CI40071944104, job120807083777, released core4.2.1 bfc2642, actual tested
PR merge fef33a779d7898f801527dfb0e6975ebad13059c (head54744b1),
Godot4.7.2 official ed1daf0bf, Linux Mesa25.2.8 llvmpipe LLVM20.1.2.
Immutable downloaded editor.log ends with receipt of save_scene({}) then
`double free or corruption (!prev)`; there is no save response. Public generation
and timeline succeeded; preview was never invoked and no PNGs/restoration baseline
were produced. The backend disconnect/TRANSPORT_OUTCOME_UNKNOWN follows the native
allocator abort. It is not evidence of ordinary transport instability.

The exact fixture is a real imported HumanCharacterDummy_F.fbx rig plus a new
scene-owned AnimationPlayer. The generator reports2318keys; the following timeline
is a paginated/truncated inspection (4tracks/200returnedkeys), not a conflicting
244-key replacement of that full animation. No addon production diff exists from
238349d to54744b1. Core4.2.1 and4.3.0 scene_handler.gd, connection.gd and
dispatcher.gd have no diff; a passing4.3.0 cell does not isolate a4.2.1 save-code bug.

The released core already depth-pauses WebSocket processing around the real
EditorInterface.save_scene call. Both normal process polling and exclusive-run
transport service honor that pause. This makes a missing ordinary re-entry guard
an unsupported proposed fix, though it cannot disprove another re-entry source.

Exact [Godot engine source](https://github.com/godotengine/godot/blob/ed1daf0bf/editor/editor_node.cpp#L2087)
shows the editor save path reads the3D viewport image, duplicates/processes a
thumbnail, then saves the scene/resources. Thus framebuffer/thumbnail processing,
scene serialization and prior heap corruption are distinct concrete candidates.
The allocator message only identifies detection of heap damage; no existing stack
locates the original invalid write/free. No product/core change is justified yet.

## Optional diagnostic increment

`ci_rendered_preview.py --native-debugger gdb` is explicit and Linux-only. The
actual Godot executable, version/context preparation, Godot argument vector,
released core, public requests, save, real rig, pixel/restoration/error gates stay
unchanged. The report retains actual `editor_command` and separately records
`editor_launch_command` plus debugger-owned private process group/cleanup. GDB
batch uses --return-child-result, run, all-thread full backtrace and shared-library
listing. Debugger stdout/stderr shares the retained complete editor.log; debuginfod
network fetching is disabled. Known native allocator/signal failures now fail the
log gate even if they appear after the last successful RPC.

The debugger+inferior use start_new_session. Cleanup allows a bounded3seconds for
an abort backtrace, then signals only that private group; it reaps GDB and removes
surviving inferior children even if GDB already exited. No generic process scan,
port change, RPC retry or source edit is introduced. A long backtrace may still
be interrupted by bounded cleanup; partial output remains preserved. GDB can
alter timing and the official executable may lack full symbols. An instrumented
success does not repair or erase the observed abort.

Reusable rendered-preview workflow installs gdb only for explicit Linux input
native_debugger=gdb. Both ordinary reusable and manual defaults remain none.
Root can request one manual diagnostic run after integrating this tooling:

```text
gh workflow run rendered-preview.yml --ref <integrated-branch> -f native_debugger=gdb
```

Preserve new artifacts separately. First inspect actual native stop stack/library
mapping. If it points into thumbnail/readback, reduce only that suspected engine
boundary in a separate diagnostic control while keeping the unmodified full save
route as the release gate. If it points into serialization or animation/resource
lifetime, compare the exact offending objects under matching symbols. Do not
replace real save with ResourceSaver or remove the rig to manufacture a green gate.

Seven new mocked controls plus10existing runner,10adapter,6profile controls pass.
They verify argument/context identity, one exercise attempt, Linux-only opt-in,
private group ownership including orphan/hung cases, and native fatal rejection.
No Godot, GDB, backend, GPU or editor process was launched locally.
