# Optional postmortem preview diagnostics plan

Base4d99d20, isolated E: worktree. No primary or engine execution.

1. Preserve debuggernone behavior and exact Godot argv/public sequence. Explicit Linux/github-hosted-only postmortem mode creates a0700owned temporary directory outside uploaded artifacts, records/restores kernel core_pattern, and enables inherited RLIMIT_CORE only for the owned editor child.
2. Resolve/hash exact engine binary before launch, bind owned editorPID and /proc executable identity, and retain actual precleanup returncode. Only observed SIGABRT/SIGSEGV/SIGBUS exits admit analysis; no RPC retry or port/process searches.
3. Open only core.<ownedPID>, require regular owned singlelink fresh ELF64x86_64core with matching Linux PRPSINFO/PRSTATUS PID notes; no glob/unrelated core lookup. Missing/wrongPID/core leaves diagnosis unavailable, never passes qualification.
4. After crash only, run bounded GNU GDBbatch on exactbinary/core for allthread btfull/sharedlibs/files, plus readelf buildID when available. Disable auto-load/init/debuginfod; keep diagnostictext only. Delete expected ownedcore and restorekernelpattern even on failure/timeout; refuse unsafe paths/symlinks. Never upload core.
5. Extend reusableworkflow opt-in/install controls and mocked negative tests. Supply minimal callerpatch only; defaultnone unchanged. Root reviews and executes futureCI.

Primary references checked24October2026:
- https://www.man7.org/linux/man-pages/man5/core.5.html — RLIMIT_CORE and absolute core_pattern/%p semantics.
- https://sourceware.org/gdb/current/onlinedocs/gdb.html/Mode-Options.html — --nx/--batch behavior.
- https://sourceware.org/gdb/current/onlinedocs/gdb.html/Files.html — executable/core file selection.
- https://www.sourceware.org/gdb/current/onlinedocs/gdb.html/Threads.html — thread apply all bt full.
