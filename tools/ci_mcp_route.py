"""Run the external Godot AI MCP registration probe against a live editor.

CI starts a fresh Godot 4.7.2 headless editor with the toolkit and core addons
enabled. The probe crosses the Python attach bridge, backend, WebSocket editor
session, custom-tool registry and toolkit handlers before/after core reload.
"""

from __future__ import annotations

import argparse
import json
import os
from pathlib import Path
import socket
import subprocess
import sys
import time


def port_open(port: int) -> bool:
    try:
        with socket.create_connection(("127.0.0.1", port), timeout=1):
            return True
    except OSError:
        return False


def tail(path: Path, count: int = 50) -> str:
    if not path.exists():
        return "(editor log was not created)"
    return "\n".join(path.read_text(encoding="utf-8", errors="replace").splitlines()[-count:])


def godot_executable(requested: str) -> str:
    if os.name == "nt" and not Path(requested).is_file():
        # setup-godot adds an extensionless hard link named `godot` to PATH.
        # Bash can launch it, but Win32 CreateProcess cannot.
        version = os.environ.get("GODOT_VERSION", "4.7.2")
        installed = Path.home() / "godot" / f"Godot_v{version}-stable_win64.exe"
        if not installed.is_file():
            raise FileNotFoundError(f"setup-godot executable not found: {installed}")
        return str(installed)
    return requested


def probe(args: argparse.Namespace, reload: bool = False) -> subprocess.CompletedProcess[str]:
    cmd = [
        sys.executable, str(Path(__file__).with_name("mcp_probe.py")),
        "--core-root", str(args.core_root),
        "--port", str(args.port), "--ws-port", str(args.ws_port),
        "--activate-auto", "--valid-pulse-scene", "res://repair_mcp_ci/route.tscn",
    ]
    if reload:
        cmd.append("--reload")
    return subprocess.run(cmd, capture_output=True, text=True, timeout=35, check=False)


def motion_gate(args: argparse.Namespace) -> bool:
    """Check saved walk, run and transitions through the external MCP route."""
    ops = ("cycle", "run_cycle", "walk_start", "walk_stop")
    common = [
        "--core-root", str(args.core_root),
        "--session-hint", args.project.name,
        "--port", str(args.port), "--ws-port", str(args.ws_port),
    ]
    create = subprocess.run([
        sys.executable, str(Path(__file__).with_name("mcp_motion_remaining_cycles.py")),
        *common, "--project-root", str(args.project),
        "--ops", *ops,
    ], capture_output=True, text=True, timeout=90, check=False)
    prefix = "MCP_MOTION_REMAINING="
    payload = next((line[len(prefix):] for line in create.stdout.splitlines()
                    if line.startswith(prefix)), "")
    if create.returncode or not payload:
        print("MCP_CI_FAIL=motion_create")
        print((create.stdout + create.stderr)[-2500:])
        return False
    result = json.loads(payload)
    if result.get("failures"):
        print("MCP_CI_FAIL=motion_create: " + json.dumps(result["failures"]))
        return False
    expected_ops = set(ops)
    created_ops = {row.get("op") for row in result.get("operations", [])}
    if created_ops != expected_ops or len(result.get("operations", [])) != len(ops):
        print("MCP_CI_FAIL=motion_create: wrong operation set " + repr(created_ops))
        return False
    audit = subprocess.run([
        sys.executable, str(Path(__file__).with_name("mcp_motion_audit_saved.py")),
        *common, "--run-id", result["run_id"],
        "--ops", *ops, "--max-slide", "0.016",
    ], capture_output=True, text=True, timeout=90, check=False)
    summary = next((line for line in audit.stdout.splitlines()
                    if line.startswith("MCP_MOTION_SAVED_AUDIT_SUMMARY=")), "")
    if audit.returncode or not summary:
        print("MCP_CI_FAIL=motion_playback")
        print((audit.stdout + audit.stderr)[-3500:])
        return False
    audit_prefix = "MCP_MOTION_SAVED_AUDIT="
    audit_payload = next((line[len(audit_prefix):] for line in audit.stdout.splitlines()
                          if line.startswith(audit_prefix)), "")
    if not audit_payload:
        print("MCP_CI_FAIL=motion_playback: missing audit rows")
        return False
    rows = json.loads(audit_payload)
    expected_rows = {(op, fps) for op in expected_ops for fps in (30, 60, 120)}
    actual_rows = {(row.get("op"), row.get("fps")) for row in rows}
    inert = [f"{row.get('op')}@{row.get('fps')}" for row in rows
             if float(row.get("body_travel") or 0.0) <= 0.1]
    if len(rows) != len(expected_rows) or actual_rows != expected_rows or inert:
        print("MCP_CI_FAIL=motion_playback: missing or inert samples "
              + json.dumps({"actual": sorted(actual_rows), "inert": inert}))
        return False
    print("MCP_CI_PASS=motion_playback " + summary, flush=True)
    return True


def graph_playback_gate(args: argparse.Namespace) -> bool:
    playable_graphs = ("state_machine", "blend_space", "blend_space_2d",
                       "blend_tree", "graph_get", "locomotion",
                       "locomotion_state_machine", "one_shot_layer",
                       "additive_lean", "wire_parameter")
    audited_graphs = (*playable_graphs, "wire")
    check = subprocess.run([
        sys.executable, str(Path(__file__).with_name("mcp_graph_audit.py")),
        "--core-root", str(args.core_root),
        "--project-root", str(args.project),
        "--session-hint", args.project.name,
        "--port", str(args.port), "--ws-port", str(args.ws_port),
        "--only", *audited_graphs,
    ], capture_output=True, text=True, timeout=60, check=False)
    prefix = "MCP_GRAPH_AUDIT="
    payload = next((line[len(prefix):] for line in check.stdout.splitlines()
                    if line.startswith(prefix)), "")
    if check.returncode or not payload:
        print("MCP_CI_FAIL=graph_get")
        print((check.stdout + check.stderr)[-2500:])
        return False
    result = json.loads(payload)
    operations = result.get("operations", [])
    expected_graphs = set(audited_graphs)
    if (result.get("failures") or len(operations) != len(expected_graphs)
            or {row.get("op") for row in operations} != expected_graphs):
        print("MCP_CI_FAIL=graph_get: " + json.dumps(result.get("failures", [])))
        return False
    print("MCP_CI_PASS=graph_topology", flush=True)
    for row in operations:
        if row["op"] == "wire":
            continue
        playback = subprocess.run([
            godot_executable(args.godot), "--headless", "--path", str(args.project),
            "--script", "res://tools/verify_saved_graph_playback.gd", "--",
            row["scene"],
        ], capture_output=True, text=True, timeout=30, check=False)
        if playback.returncode or "GRAPH_SAVED_PLAYBACK_PASS:" not in playback.stdout:
            print("MCP_CI_FAIL=graph_saved_playback:" + row["op"])
            print((playback.stdout + playback.stderr)[-2500:])
            return False
        print("MCP_CI_PASS=graph_saved_playback:" + row["op"], flush=True)
    return True


def modifier_playback_gate(args: argparse.Namespace) -> bool:
    """Exercise every modifier through Godot AI and activate its saved scene."""
    common = [
        "--core-root", str(args.core_root),
        "--project-root", str(args.project),
        "--session-hint", args.project.name,
        "--port", str(args.port), "--ws-port", str(args.ws_port),
    ]
    script_dir = Path(__file__).parent
    cases = (
        ("mcp_rig_modifiers_audit.py", "MCP_RIG_MODIFIERS=",
         "res://tools/check_rig_modifiers_runtime.gd", "RIG_MODIFIER_RUNTIME=",
         {"ik_setup", "spring_setup", "look_at_setup", "twist_setup"}),
        ("mcp_retarget_audit.py", "MCP_RETARGET=",
         "res://tools/check_retarget_runtime.gd", "RETARGET_RUNTIME=",
         {"retarget_setup"}),
    )
    for audit_script, marker, runtime_script, runtime_marker, expected in cases:
        audit = subprocess.run(
            [sys.executable, str(script_dir / audit_script), *common],
            capture_output=True, text=True, timeout=90, check=False,
        )
        payload = next((line[len(marker):] for line in audit.stdout.splitlines()
                        if line.startswith(marker)), "")
        if audit.returncode or not payload:
            print("MCP_CI_FAIL=modifier_route:" + audit_script)
            print((audit.stdout + audit.stderr)[-3000:])
            return False
        result = json.loads(payload)
        rows = result.get("rows", [result["row"]] if "row" in result else [])
        ops = {row.get("op", "retarget_setup") for row in rows}
        if result.get("failures") or len(rows) != len(expected) or ops != expected:
            print("MCP_CI_FAIL=modifier_route:" + audit_script + " "
                  + json.dumps({"failures": result.get("failures"), "ops": sorted(ops)}))
            return False
        for row in rows:
            op = row.get("op", "retarget_setup")
            command = [godot_executable(args.godot), "--headless", "--path",
                       str(args.project), "--script", runtime_script, "--", row["scene"]]
            if op != "retarget_setup":
                command.append(op)
            playback = subprocess.run(command, capture_output=True, text=True,
                                      timeout=30, check=False)
            reported = next((line[len(runtime_marker):]
                             for line in playback.stdout.splitlines()
                             if line.startswith(runtime_marker)), "")
            if playback.returncode or not reported:
                print("MCP_CI_FAIL=modifier_saved_playback:" + op)
                print((playback.stdout + playback.stderr)[-2500:])
                return False
            runtime = json.loads(reported)
            if runtime.get("failures") or float(runtime.get("response",
                    runtime.get("target_head_change", 0.0))) < 0.001:
                print("MCP_CI_FAIL=modifier_saved_playback:" + op + " " + reported)
                return False
            print("MCP_CI_PASS=modifier_saved_playback:" + op, flush=True)
    return True


def fx_playback_gate(args: argparse.Namespace) -> bool:
    """Play every saved FX result after a live Godot AI invocation."""
    expected = {"shake", "zoom_punch", "hit_flash", "damage_bar",
                "typewriter", "progress_fill", "counter", "dialog_pop",
                "transition", "wave", "spring", "pendulum", "path_follow",
                "flipbook", "sprite_frames", "sprite_frames_stopped", "audio_cue"}
    audit = subprocess.run([
        sys.executable, str(Path(__file__).with_name("mcp_fx_audit.py")),
        "--core-root", str(args.core_root),
        "--project-root", str(args.project),
        "--session-hint", args.project.name,
        "--port", str(args.port), "--ws-port", str(args.ws_port),
    ], capture_output=True, text=True, timeout=120, check=False)
    marker = "MCP_FX_AUDIT="
    payload = next((line[len(marker):] for line in audit.stdout.splitlines()
                    if line.startswith(marker)), "")
    if audit.returncode or not payload:
        print("MCP_CI_FAIL=fx_route")
        print((audit.stdout + audit.stderr)[-3000:])
        return False
    result = json.loads(payload)
    rows = result.get("operations", [])
    actual = {row.get("op") for row in rows}
    if result.get("failures") or len(rows) != len(expected) or actual != expected:
        print("MCP_CI_FAIL=fx_route: " + json.dumps({
            "failures": result.get("failures"), "actual": sorted(actual)}))
        return False
    print("MCP_CI_PASS=fx_route", flush=True)
    for row in rows:
        playback = subprocess.run([
            godot_executable(args.godot), "--headless", "--path",
            str(args.project), "--script", "res://tools/check_fx_runtime.gd",
            "--", row["scene"], row["op"],
        ], capture_output=True, text=True, timeout=30, check=False)
        marker = "FX_RUNTIME="
        reported = next((line[len(marker):] for line in playback.stdout.splitlines()
                         if line.startswith(marker)), "")
        if playback.returncode or not reported:
            print("MCP_CI_FAIL=fx_saved_playback:" + row["op"])
            print((playback.stdout + playback.stderr)[-2500:])
            return False
        runtime = json.loads(reported)
        if runtime.get("failures") or not runtime.get("checks"):
            print("MCP_CI_FAIL=fx_saved_playback:" + row["op"] + " " + reported)
            return False
        print("MCP_CI_PASS=fx_saved_playback:" + row["op"], flush=True)
    return True


def edit_playback_gate(args: argparse.Namespace) -> bool:
    """Check edited clips through Godot AI and engine interpolation."""
    simple = {"retime", "reverse", "mirror", "trim", "amplitude",
              "resample", "layer", "offset", "loop", "key_edit", "overlap"}
    remaining = {"retarget", "ease_range", "set_interp", "split_at",
                 "merge", "cleanup", "smooth", "reduce", "add_noise"}
    rejected = {"offset_wrap_reject", "overlap_wrap_reject"}
    expected = simple | remaining | rejected
    audit = subprocess.run([
        sys.executable, str(Path(__file__).with_name("mcp_edit_audit.py")),
        "--core-root", str(args.core_root),
        "--project-root", str(args.project),
        "--session-hint", args.project.name,
        "--port", str(args.port), "--ws-port", str(args.ws_port),
    ], capture_output=True, text=True, timeout=120, check=False)
    marker = "MCP_EDIT_AUDIT="
    payload = next((line[len(marker):] for line in audit.stdout.splitlines()
                    if line.startswith(marker)), "")
    if audit.returncode or not payload:
        print("MCP_CI_FAIL=edit_route")
        print((audit.stdout + audit.stderr)[-3000:])
        return False
    result = json.loads(payload)
    rows = result.get("operations", [])
    actual = {row.get("op") for row in rows}
    if result.get("failures") or len(rows) != len(expected) or actual != expected:
        print("MCP_CI_FAIL=edit_route: " + json.dumps({
            "failures": result.get("failures"), "actual": sorted(actual)}))
        return False
    print("MCP_CI_PASS=edit_route", flush=True)
    for row in rows:
        op = row["op"]
        if op in rejected:
            continue
        checker = ("res://tools/check_edit_runtime.gd" if op in simple
                   else "res://tools/check_edit_remaining_runtime.gd")
        marker = "EDIT_RUNTIME=" if op in simple else "EDIT_REMAINING="
        playback = subprocess.run([
            godot_executable(args.godot), "--headless", "--path",
            str(args.project), "--script", checker,
            "--", row["scene"], op,
        ], capture_output=True, text=True, timeout=30, check=False)
        reported = next((line[len(marker):] for line in playback.stdout.splitlines()
                         if line.startswith(marker)), "")
        if playback.returncode or not reported:
            print("MCP_CI_FAIL=edit_saved_playback:" + op)
            print((playback.stdout + playback.stderr)[-2500:])
            return False
        runtime = json.loads(reported)
        if not runtime.get("samples") or float(runtime.get("worst_error", 100.0)) >= 1.0:
            print("MCP_CI_FAIL=edit_saved_playback:" + op + " " + reported)
            return False
        print("MCP_CI_PASS=edit_saved_playback:" + op, flush=True)
    return True


def preset_playback_gate(args: argparse.Namespace) -> bool:
    """Play all saved preset clips, including the seven-clip showcase."""
    expected = {"pulse", "bounce", "orbit", "sweep", "drift", "spin",
                "float", "stagger", "showcase"}
    audit = subprocess.run([
        sys.executable, str(Path(__file__).with_name("mcp_presets_audit.py")),
        "--core-root", str(args.core_root),
        "--project-root", str(args.project),
        "--session-hint", args.project.name,
        "--port", str(args.port), "--ws-port", str(args.ws_port),
    ], capture_output=True, text=True, timeout=120, check=False)
    marker = "MCP_PRESETS_AUDIT="
    payload = next((line[len(marker):] for line in audit.stdout.splitlines()
                    if line.startswith(marker)), "")
    if audit.returncode or not payload:
        print("MCP_CI_FAIL=preset_route")
        print((audit.stdout + audit.stderr)[-3000:])
        return False
    result = json.loads(payload)
    rows = result.get("operations", [])
    actual = {row.get("op") for row in rows}
    if result.get("failures") or len(rows) != len(expected) or actual != expected:
        print("MCP_CI_FAIL=preset_route: " + json.dumps({
            "failures": result.get("failures"), "actual": sorted(actual)}))
        return False
    print("MCP_CI_PASS=preset_route", flush=True)
    for row in rows:
        op = row["op"]
        playback = subprocess.run([
            godot_executable(args.godot), "--headless", "--path",
            str(args.project), "--script",
            "res://tools/check_presets_saved_playback.gd",
            "--", row["scene"], op,
        ], capture_output=True, text=True, timeout=30, check=False)
        marker = ("PRESET_SHOWCASE_PLAYBACK=" if op == "showcase"
                  else "PRESET_SAVED_PLAYBACK=")
        reported = next((line[len(marker):] for line in playback.stdout.splitlines()
                         if line.startswith(marker)), "")
        if playback.returncode or not reported:
            print("MCP_CI_FAIL=preset_saved_playback:" + op)
            print((playback.stdout + playback.stderr)[-2500:])
            return False
        runtime = json.loads(reported)
        if runtime.get("failures") or (op == "showcase" and len(runtime.get("rows", [])) != 7) \
                or (op != "showcase" and float(runtime.get("maximum_change", 0.0)) <= 0.001):
            print("MCP_CI_FAIL=preset_saved_playback:" + op + " " + reported)
            return False
        print("MCP_CI_PASS=preset_saved_playback:" + op, flush=True)
    return True


def library_playback_gate(args: argparse.Namespace) -> bool:
    """Check library file operations and play both imported saved clips."""
    audit = subprocess.run([
        sys.executable, str(Path(__file__).with_name("mcp_library_audit.py")),
        "--core-root", str(args.core_root),
        "--project-root", str(args.project),
        "--session-hint", args.project.name,
        "--port", str(args.port), "--ws-port", str(args.ws_port),
    ], capture_output=True, text=True, timeout=90, check=False)
    marker = "MCP_LIBRARY_AUDIT="
    payload = next((line[len(marker):] for line in audit.stdout.splitlines()
                    if line.startswith(marker)), "")
    if audit.returncode or not payload:
        print("MCP_CI_FAIL=library_route")
        print((audit.stdout + audit.stderr)[-3000:])
        return False
    result = json.loads(payload)
    rows = result.get("rows", {})
    required = {"template_save", "template_list", "template_apply",
                "template_delete", "spec_export", "spec_import", "spec_apply",
                "typed_errors", "save", "reopen"}
    if result.get("failures") or not required.issubset(rows):
        print("MCP_CI_FAIL=library_route: " + json.dumps({
            "failures": result.get("failures"),
            "missing": sorted(required - rows.keys())}))
        return False
    print("MCP_CI_PASS=library_route", flush=True)
    playback = subprocess.run([
        godot_executable(args.godot), "--headless", "--path",
        str(args.project), "--script", "res://tools/check_library_runtime.gd",
        "--", result["scene"],
    ], capture_output=True, text=True, timeout=30, check=False)
    marker = "LIBRARY_RUNTIME="
    reported = next((line[len(marker):] for line in playback.stdout.splitlines()
                     if line.startswith(marker)), "")
    if playback.returncode or not reported:
        print("MCP_CI_FAIL=library_saved_playback")
        print((playback.stdout + playback.stderr)[-2500:])
        return False
    runtime = json.loads(reported)
    if len(runtime.get("samples", [])) != 2 or float(runtime.get("worst_error", 100.0)) >= 0.1:
        print("MCP_CI_FAIL=library_saved_playback: " + reported)
        return False
    print("MCP_CI_PASS=library_saved_playback", flush=True)
    return True


def inspect_gate(args: argparse.Namespace) -> bool:
    """Assert every read-only inspector operation and its typed error."""
    expected = {"describe", "timeline", "audit", "compare", "stats",
                "motion_report", "dry_run", "help"}
    audit = subprocess.run([
        sys.executable, str(Path(__file__).with_name("mcp_inspect_audit.py")),
        "--core-root", str(args.core_root),
        "--session-hint", args.project.name,
        "--port", str(args.port), "--ws-port", str(args.ws_port),
    ], capture_output=True, text=True, timeout=45, check=False)
    marker = "MCP_INSPECT_AUDIT="
    payload = next((line[len(marker):] for line in audit.stdout.splitlines()
                    if line.startswith(marker)), "")
    if audit.returncode or not payload:
        print("MCP_CI_FAIL=inspect_route")
        print((audit.stdout + audit.stderr)[-3000:])
        return False
    result = json.loads(payload)
    rows = result.get("operations", [])
    actual = {row.get("op") for row in rows}
    if result.get("failures") or len(rows) != len(expected) or actual != expected:
        print("MCP_CI_FAIL=inspect_route: " + json.dumps({
            "failures": result.get("failures"), "actual": sorted(actual)}))
        return False
    print("MCP_CI_PASS=inspect_route", flush=True)
    return True


def run(args: argparse.Namespace) -> int:
    editor: subprocess.Popen[bytes] | None = None
    log_stream = None
    log_path = Path(args.log).resolve()
    try:
        fixture = args.project / "repair_mcp_ci" / "route.tscn"
        fixture.parent.mkdir(parents=True, exist_ok=True)
        fixture.write_text(
            '[gd_scene format=3]\n\n'
            '[node name="RouteFixture" type="Node2D"]\n\n'
            '[node name="Anim" type="AnimationPlayer" parent="."]\n\n'
            '[node name="Target" type="Node2D" parent="."]\n',
            encoding="utf-8",
        )
        if not args.existing:
            env = os.environ.copy()
            env["GODOT_AI_ALLOW_HEADLESS"] = "1"
            env["GODOT_AI_DISABLE_TELEMETRY"] = "true"
            env["GODOT_AI_VENV_PYTHON"] = sys.executable
            source = str((args.core_root / "src").resolve())
            env["PYTHONPATH"] = os.pathsep.join(filter(None, [source, env.get("PYTHONPATH", "")]))
            log_path.parent.mkdir(parents=True, exist_ok=True)
            log_stream = log_path.open("wb")
            command = [godot_executable(args.godot), "--headless", "--editor", "--path", str(args.project)]
            editor = subprocess.Popen(
                command,
                stdout=log_stream, stderr=subprocess.STDOUT, env=env,
            )
            print(f"MCP_CI_EDITOR_PID={editor.pid}", flush=True)

        deadline = time.monotonic() + args.timeout
        while time.monotonic() < deadline:
            if editor is not None and editor.poll() is not None:
                print(f"MCP_CI_EDITOR_EXIT={editor.returncode}")
                print(tail(log_path))
                return 1
            if port_open(args.port):
                break
            time.sleep(1)
        else:
            print("MCP_CI_FAIL: Godot AI backend port did not open")
            print(tail(log_path))
            return 1

        for stage in ("before_reload", "reload", "after_reload"):
            while time.monotonic() < deadline:
                try:
                    result = probe(args, reload=stage == "reload")
                except subprocess.TimeoutExpired:
                    print(f"MCP_CI_RETRY={stage}: probe timeout", flush=True)
                    time.sleep(2)
                    continue
                if result.returncode == 0:
                    print(f"MCP_CI_PASS={stage}", flush=True)
                    print(result.stdout, flush=True)
                    break
                print(f"MCP_CI_RETRY={stage}: exit {result.returncode}", flush=True)
                print(result.stdout[-1200:], flush=True)
                print(result.stderr[-1200:], flush=True)
                time.sleep(2)
            else:
                print(f"MCP_CI_FAIL={stage}")
                print(tail(log_path))
                return 1
        if not motion_gate(args):
            print(tail(log_path))
            return 1
        if not graph_playback_gate(args):
            print(tail(log_path))
            return 1
        if not modifier_playback_gate(args):
            print(tail(log_path))
            return 1
        if not fx_playback_gate(args):
            print(tail(log_path))
            return 1
        if not edit_playback_gate(args):
            print(tail(log_path))
            return 1
        if not preset_playback_gate(args):
            print(tail(log_path))
            return 1
        if not library_playback_gate(args):
            print(tail(log_path))
            return 1
        if not inspect_gate(args):
            print(tail(log_path))
            return 1
        return 0
    finally:
        if editor is not None and editor.poll() is None:
            editor.terminate()
            try:
                editor.wait(timeout=10)
            except subprocess.TimeoutExpired:
                editor.kill()
                editor.wait(timeout=5)
        if log_stream is not None:
            log_stream.close()


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--core-root", type=Path, required=True)
    parser.add_argument("--project", type=Path, default=Path("test_project"))
    parser.add_argument("--godot", default="godot")
    parser.add_argument("--port", type=int, default=8000)
    parser.add_argument("--ws-port", type=int, default=9500)
    parser.add_argument("--timeout", type=int, default=150)
    parser.add_argument("--log", default="mcp-editor.log")
    parser.add_argument("--existing", action="store_true", help="Probe an already-running editor")
    args = parser.parse_args()
    args.core_root = args.core_root.resolve()
    args.project = args.project.resolve()
    return run(args)


if __name__ == "__main__":
    raise SystemExit(main())
