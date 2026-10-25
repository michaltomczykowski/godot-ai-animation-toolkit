# Optional official-Linux doc-loader watch control

Design before implementation. Diagnostic only; no engine execution by worker,
CI mutation, readiness workaround, extra public calls, retry or budget changes.
Require Linux + explicit existing GDB mode + exact official ELF SHA256 and exact
instruction bytes at regeneration entry, flag store and vector realloc call.
Reject a different binary before launch. Keep actual Godot command/context exact.

Generate a private GDB Python script under the existing receipt directory. Break
on the identified regeneration-entry FDE and install hardware write watches on
flag0x8fb68c8 and vector storage0x8fb68b8 once memory is mapped. Pointer writes are
reported only after regeneration entry and while actual flagfalse. Record
GDB thread number/PTID and bounded bt12. Track counts independently per writer:
loader events may exhaust their own quota but never disable watch or consume a
new main/other writer's quota. Bound unique-writer count explicitly; emit a
coverage-limit event on overflow rather than silently claiming completeness.
Keep watcher enabled across both active/inactive transitions; summarize counts
at flagtrue and inferior exit. Add bounded pre-realloc snapshots of pointer,
size/capacity and rdi/rsi. GDB errors must emit diagnostic failure, not success.

Integration delivered as minimal optional runner patch, not whole-file baseline.
Use the existing owned GDB process-group cleanup and complete fatal-log gate.
All diagnostic data stays in editor log plus script/hash identity in report.
Offline tests mock GDB API, memory, thread and stack actions to prove active-window
filtering, per-writer quotas, completion and hash/byte/platform refusal.

Separately inspect pinned OS benchmark implementation and EditorHelp bindings.
A native C++ wait helper or a benchmark end record may not be a safe public
readiness API. No help opening or product-flow side effects will be introduced.


## Prepared interface and controls

New helper modules `preview_doc_watch.py` and `preview_doc_watch_gdb.py` plus
six mocked controls. Seven existing GDB ownership controls also pass. Exact
146414384-byte official ELF passed hash/ELF/address/instruction preflight by pure
file read; neither engine nor GDB ran. The copied diagnostic script is created
exclusively and hashed. Existing script artifacts are never overwritten.

Apply `docs/patches/doc-loader-watch-runner.patch` after cherry-pick, then run
only the diagnostic Linux preview with `--native-debugger gdb --doc-loader-watch`
and the existing original arguments/budgets. Workflow changes are root-owned;
none are included here. The Godot `editor_command` and context identity stay
unchanged; the GDB launch receives one Python-script command before its existing
`run`. The existing private process-group cleanup remains in force. All JSON
records and bounded stacks are in the preserved complete editor.log, prefixed
DOC_WATCH=. Script/hash identity and parsed diagnostic counts go in the report.

Three hardware watches: size, storage pointer, flag. Size catches appends that
fit capacity and therefore do not move storage. Only after regeneration entry
and while actual flagfalse are vector writes/pre-realloc states logged. Quotas
are per (kind,writer), loader8 / other4; counts continue after stack suppression,
and watches are never disabled by quota. At most16 distinct writers are admitted;
overflow is explicit incomplete coverage and fails diagnostic validation. A new
other writer is not suppressed by exhausted loader quotas. Flagtrue/exit emit
summaries. Missing arm, malformed events, memory/hardware failure and writer
limit overflow cannot yield a clean diagnostic. No regeneration observed is
reported explicitly and never treated as a successful reproduction.

GDB hardware-stop timing can perturb a race or use the unchanged time budget.
A passing attempt does not fix the earlier corruption; absence of a second
writer does not rule out an earlier overwrite or unobserved memory write.

## Pinned source: completion observability

Source commit ed1daf0bf001b61586d9930840f2f1394092c079, read only:

- `core/os/os.cpp` lines773–789: benchmark begin/end update maps. End does not
  emit a completion line. `benchmark_dump` lines792–829 prints BENCHMARK or
  writes JSON only when requested. `main/main.cpp` calls dump at startup4887
  and shutdown5401. Therefore `--benchmark` is not a streaming documentation
  completion signal; startup output may precede late docs completion, shutdown
  is too late for a before-save readiness barrier. An observed final mark would
  be historical timing evidence, not an exposed synchronization API.
- `editor/doc/editor_help.cpp` line2946: `_wait_for_thread(Thread&)` joins the
  supplied started thread. Header line199 declares it private, defaulting to
  worker_thread. `get_doc_data` calls that default helper; it does not explicitly
  join loader_thread. Regeneration explicitly joins both before starting loader.
- `_finish_regen_script_doc_thread` lines3182–3187 joins loader, processes
  postponed docs, sets `_script_docs_loaded`, then records benchmark end.
- `_bind_methods` lines3421–3428 exposes only UI callbacks/signals, not docs-ready,
  flag polling or `_wait_for_thread`. No public Godot scripting barrier was found.

Consequently no opens-help side effect or public readiness workaround is proposed.
The raw watch/flag diagnostics are the next measurement, not a product change.

Official primary sources:
https://github.com/godotengine/godot/blob/ed1daf0bf001b61586d9930840f2f1394092c079/core/os/os.cpp
https://github.com/godotengine/godot/blob/ed1daf0bf001b61586d9930840f2f1394092c079/editor/doc/editor_help.cpp
https://github.com/godotengine/godot/blob/ed1daf0bf001b61586d9930840f2f1394092c079/editor/doc/editor_help.h
https://github.com/godotengine/godot/blob/ed1daf0bf001b61586d9930840f2f1394092c079/main/main.cpp
