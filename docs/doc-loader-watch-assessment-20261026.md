# Independent documentation-loader watch assessment

## Bound source and outcome

CI40243257753, PR head abf8ea20beba2d37cf3b5d63a82b5fdea738f854; both actual checkouts daa9c443151acbc2038da9f3addc4529024fc51b. Official4.7.2 ELF146414384bytes SHA2568d106cbe6144c2dc7e881d61d2429c1a8a76e6b22ef48bd5e48dcf934953f71e; source ed1daf0bf001b61586d9930840f2f1394092c079. Exact copied watcher SHA84941302941972e3e92146d1fd3877480d2660705bdfde439055205bbec8e62f. Private assessment.json preserves both complete parsed DOC_WATCH event sets, log line order, contexts and raw artifact hashes. Pure ELF decoding only; no engine/GDB execution, build, upload or source change by this assessment.

## Measured430 sequence

- Log80: regeneration entry on loader GDB39/LWP4408, process4229. Watches cover size0x8fb68b0,capacity0x8fb68b4 (snapshot only),storage0x8fb68b8 and flag0x8fb68c8.
- Recorded first8 loader pre-realloc snapshots start size0/capacity2/storage0/request560bytes; subsequent sizes2,3,5,8,12,18,27 and capacities3,5,8,12,18,27,41 request840,1400,2240,3360,5040,7560,11480bytes. Element width0x118=280bytes. Capacity is updated before realloc in these snapshots, so it is not proof of already allocated capacity. Later loader snapshots/stacks are suppressed by per-writer quota, counts continue.
- Public save_scene is received at136. At137 allocator prints `malloc(): mismatching next->prev_size (unsorted)`.
- At138 main GDB1/LWP4229 reports storage-pointer write; snapshot size315,capacity473,storage0x7fff47c5be20,flag0. At139 same main thread reports size316 with same capacity/storage/flag. Stack top PCs0x1cb7e29 and0x1cb7beb; caller0x1e6938d. These are actual stores to the same globals the loader writes, within the same flagfalse regeneration window.
- At141 loader39 receives SIGABRT. Its native stack detects allocator failure in realloc_static during the previously identified recursive script-doc buffer growth. No flagtrue/window_complete occurred. Exit summary counts loader13before_realloc,12pointer_write,315size_write plus main1pointer_write/1size_write; writer_limit_exceeded=false. These counts include writes without retained detailed snapshots.

Two metadata writers in the same incomplete-load window are confirmed. Exact simultaneous machine-instruction execution is not required for an interleaving race and is not measured here. Crucially, allocator error text precedes recorded main stores in the combined log. Hardware stops and separate output buffering do not give a precise cross-thread happens-before history. Do not claim the observed main stores caused the already-reported corruption.

## What421 establishes

421 completes preview. Loader39/LWP4411 performs14pre-realloc,13pointer writes,427size writes; thread40/LWP4415 then writes size0 (capacity473,storage0x7fff48ab6250,flag0), sets flag1 and emits window_complete. Its PCs0x1c9b68b/0x1c9b725 map by bytes/source to postponed-doc processing and finish helper: pinned finish explicitly waits for loader before processing. This second writer is consistent with intended sequential handoff, not evidence of a race by itself. No main-thread vector write was recorded in421. The GDB process is intentionally terminated during owned cleanup; debugger255 is not a normal editor exit or allocator abort. Green421 neither fixes nor disproves430.

## Exact bytes versus source names

No DWARF or matching official debug symbols were available; names below are strong aligned control/data matches, not symbolic backtraces. New inspection.json decodes five exact FDE ranges from the hashed non-PIE ELF.

Both main top PCs lie in FDE0x1cb7bb0..0x1cb7e6c,700bytes. It compares shared count/capacity, grows by1.5, multiplies allocation by0x118, calls0x4410780 realloc wrapper, stores result to0x8fb68b8 at0x1cb7e22, then increments shared count at0x1cb7be5 before element writes. This is the shared LocalVector<ClassDoc> append implementation, not independently identifiable as a named EditorHelp function.

Caller FDE0x1e68890..0x1e696ee references `Updating scripts documentation` and `update_script_paths_documentation`. At0x1e6937a it loads flag0x8fb68c8; false branch0x1e69388 calls0x1cb7bb0; true branch calls the doc-store path. Official EditorFileSystem source lines2246/2273 calls EditorHelp::add_doc; pinned EditorHelp lines2978–2985 branches on _script_docs_loaded and appends to _docs_to_add. The observed main path is therefore strongly identified as an inlined EditorHelp::add_doc called by script documentation update; stripped addresses alone would not justify the name.

Pinned loader lines3192–3226 clears the same queue, flagfalse, recursively loads scripts and appends their docs without a queue mutex. LocalVector push_back lines97–103 uses unsynchronized count/capacity/data. This source+byte+watch combination establishes conflicting unsynchronized access to the same queue metadata. It does not identify a particular overwritten heap byte, double-free pointer, lost element or corrupting instruction. Loader rdi/rsi at the final crashing realloc were not captured under the exhausted detailed-event quota. No payload/allocator metadata watch was installed.

## Minimum causal control and candidate fix

Next bounded engine-side control: exact pinned4.7.2 source, same public fixture/request/single save and all unchanged assertions, with one explicit queue-synchronization patch plus diagnostic symbols. Protect the flag check/queue push in add_doc and the loader's clear/push with a single shared mutex; include remove/remove_by_path queues and drain/flag transition in the same ownership design, not merely the pointer assignment. Acquire only around queue mutation or queue swap and state transition. Release before ResourceLoader::load, doc processing/callbacks, and every thread join. Source explicitly warns that loader load tasks can require main-thread dispatch, so a main-thread `wait for loader` barrier or a lock held across loading is an unsafe proposed shortcut.

A positive control should retain the same independently identified main/loader call paths and requests while recording serialized queue ownership, then verify original save/preview/source/error gates. A negative control should deliberately exercise concurrent append/growth in an isolated native queue test (or ThreadSanitizer build) to demonstrate the synchronization detects/removes this conflict. A single no-crash patched run remains insufficient to prove all memory-corruption causes removed. An alternative cleaner ownership design is loader-private output merged after completion, but it is larger than the minimal mutex control.

For the unchanged official4.7.2 public API, no exposed docs-ready/join primitive has been established. No defensible toolkit-only fix follows from these traces. Do not use timed waits, prewarming, public RPC retries, opening Help, or gate relaxation. An upstream engine patch/build remains a distinct tested engine identity; do not promote it as evidence for the unmodified official binary. Preserve failing430 receipt and restore ordinary none/false diagnostics separately under root ownership.

## Primary source references

- https://github.com/godotengine/godot/blob/ed1daf0bf001b61586d9930840f2f1394092c079/editor/doc/editor_help.cpp
- https://github.com/godotengine/godot/blob/ed1daf0bf001b61586d9930840f2f1394092c079/editor/file_system/editor_file_system.cpp
- https://github.com/godotengine/godot/blob/ed1daf0bf001b61586d9930840f2f1394092c079/core/templates/local_vector.h
