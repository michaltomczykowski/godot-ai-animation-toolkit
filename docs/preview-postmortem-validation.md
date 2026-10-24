# Optional postmortem preview diagnostics

Base4d99d20; explicit `--native-debugger postmortem` or reusable workflow input `native_debugger: postmortem`. Default `none` and its normal Godot command/public calls are unchanged. The main caller remains `none`; `preview-postmortem-caller.patch` is a minimal optional future diagnostic selection, not applied by this commit. Apply explicitly with `git apply --unidiff-zero --ignore-space-change docs/preview-postmortem-caller.patch` after review.

## Contract

Postmortem mode is restricted to Linux disposable GitHub-hosted runners. It creates a0700private `/tmp/gai-core-*` directory outside the uploaded artifact tree, records/verifies the original kernel core_pattern, sets an absolute owned `core.%p` pattern, and enables inherited RLIMIT_CORE in the editor child only. The backend and original public request sequence are unchanged; no live GDB wrapper, mutating RPC retry, port killing or process discovery is added.

The exact resolved Godot binary is hashed before launch; the owned Popen PID is bound to its `/proc/PID/exe` and actual core-limit line. Only an observed precleanup SIGABRT/SIGSEGV/SIGBUS exit permits analysis. The helper opens only the constructed `core.<ownedPID>` path: fresh regular file, same owner, single link, LinuxELF64x86_64 PRPSINFO processPID and PRSTATUS leaderPID must match. Missing/unsupported/mismatched cores produce unavailable/refused diagnostics, never substituted evidence. A wrong PID's filename is neither inspected nor deleted.

After that verified crash, GNU GDBbatch reads the exact binary/core with init/autoload/debuginfod disabled and emits all-thread bounded `bt full`, shared libraries and loaded file context. `readelf -n` records binary buildID notes if available. GDB is capped at60seconds and5MiBoutput; readelf at10seconds. Actual editor returncode/signal, debugger result and preview qualification remain separate. A successful debugger cannot turn a failed preview intoPASS.

Owned expected core deletion, original kernel-pattern restoration and private-directory removal are attempted after analysis/failure/timeout. Cleanup failures are recorded and fail the gate. No recursive/unrelated deletion occurs. Only diagnostic text/context is under the uploaded directory; raw core memory is never copied or uploaded. External uncatchable job/runner termination can prevent Python finally cleanup; the mode therefore refuses persistent/self-hosted machines, and the private memory file remains outside artifact selection until the disposable runner is destroyed.

## Verification

48preview-related pure/mocked controls passed, including14new postmortem tests: wrong PID filename and ELFnotes, missing core, noabort, unchanged normal launch, nonLinux/non-disposable refusal, exactbinary change, bounded liveprocess wait, debugger timeout text, core deletion, kernel restore after deletion failure, private setup/restore, and runner single launch/single exercise with independent crashstatus. Python compilation and diff whitespace checks pass. Existing none/GDB/PNG/profile/adapter tests remain passing.

No Linux sysctl/rlimit mutation, debugger, core dump, Godot process or public invocation was executed by this worker. Actual Linux core generation, ELF note compatibility and backtrace availability remain pending future CI. Official Godot binaries may lack full symbols; address/library/buildID evidence is retained without claiming source-level causality.

## Primary references checked24October2026

[Linux core(5)](https://www.man7.org/linux/man-pages/man5/core.5.html) specifies core-pattern naming, `%p`, absolute-path behavior and RLIMIT_CORE restrictions. [GNU GDB mode options](https://sourceware.org/gdb/current/onlinedocs/gdb.html/Mode-Options.html) documents batch/no-init behavior; [file selection](https://sourceware.org/gdb/current/onlinedocs/gdb.html/Files.html) and [thread commands](https://www.sourceware.org/gdb/current/onlinedocs/gdb.html/Threads.html) document executable/core and all-thread traces. [GitHub variable reference](https://docs.github.com/en/actions/reference/workflows-and-actions/variables) defines RUNNER_ENVIRONMENT github-hosted/self-hosted identity.
