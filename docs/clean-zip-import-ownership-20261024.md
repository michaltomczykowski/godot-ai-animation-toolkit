# Clean ZIP import process ownership

CI40071944104 Windows/core4.2.1 job120807138626 stopped at the existing
ci_mcp_route unused8000/9500 gate before it spawned its backend/editor. The
clean ZIP harness explicitly opted into core headless activation during --import.
Core bfc2642 plugin.gd _mcp_disabled_for_headless treats a truthy
GODOT_AI_ALLOW_HEADLESS as permission to start the plugin normally. An import
with core already enabled can therefore create a plugin-owned backend outside
the later route harness ownership boundary. The exact failed listener PID was
not captured; attribution of those particular occupied ports remains inferred.

The minimal fix removes the variable from the copied import/subprocess environment,
including inherited values. Import runs first and must succeed. The unchanged
ci_mcp_route then creates its own environment and explicitly sets ALLOW_HEADLESS=1
for its owned backend/editor, preserving released-core public calls, both plugin
enable orders and selection checks. No alternate port, process kill, retry,
production addon or core modification is introduced. Prior failures are preserved.

Four offline controls pass: inherited/missing environment cases with exact process
order; failed import prevents route; real route startup retains explicit owned
activation; occupied ports still refuse before spawning. No Godot/backend was
launched. Fresh actual clean ZIP CI on both platforms and released core pins is
required; these mocked checks do not qualify installation.
