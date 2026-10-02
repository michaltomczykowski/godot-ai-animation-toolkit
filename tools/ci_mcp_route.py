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


def graph_get_gate(args: argparse.Namespace) -> bool:
    check = subprocess.run([
        sys.executable, str(Path(__file__).with_name("mcp_graph_audit.py")),
        "--core-root", str(args.core_root),
        "--project-root", str(args.project),
        "--session-hint", args.project.name,
        "--port", str(args.port), "--ws-port", str(args.ws_port),
        "--only", "graph_get",
    ], capture_output=True, text=True, timeout=60, check=False)
    prefix = "MCP_GRAPH_AUDIT="
    payload = next((line[len(prefix):] for line in check.stdout.splitlines()
                    if line.startswith(prefix)), "")
    if check.returncode or not payload:
        print("MCP_CI_FAIL=graph_get")
        print((check.stdout + check.stderr)[-2500:])
        return False
    result = json.loads(payload)
    if result.get("failures") or len(result.get("operations", [])) != 1:
        print("MCP_CI_FAIL=graph_get: " + json.dumps(result.get("failures", [])))
        return False
    print("MCP_CI_PASS=graph_get", flush=True)
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
            godot = args.godot
            if os.name == "nt" and not Path(godot).is_file():
                # setup-godot adds an extensionless hard link named `godot`
                # to PATH. Bash can launch it, but Win32 CreateProcess cannot;
                # use the action's installed .exe for a child process.
                version = os.environ.get("GODOT_VERSION", "4.7.2")
                installed = Path.home() / "godot" / f"Godot_v{version}-stable_win64.exe"
                if not installed.is_file():
                    raise FileNotFoundError(f"setup-godot executable not found: {installed}")
                godot = str(installed)
            command = [godot, "--headless", "--editor", "--path", str(args.project)]
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
        if not graph_get_gate(args):
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
