"""Run the external Godot AI MCP registration probe against a live editor.

CI starts a fresh Godot 4.7.2 headless editor with the toolkit and core addons
enabled. The probe crosses the Python attach bridge, backend, WebSocket editor
session, custom-tool registry and toolkit handlers before/after core reload.
"""

from __future__ import annotations

import argparse
import os
from pathlib import Path
import shlex
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
        "--activate-auto",
    ]
    if reload:
        cmd.append("--reload")
    return subprocess.run(cmd, capture_output=True, text=True, timeout=35, check=False)


def run(args: argparse.Namespace) -> int:
    editor: subprocess.Popen[bytes] | None = None
    log_stream = None
    log_path = Path(args.log).resolve()
    try:
        if not args.existing:
            env = os.environ.copy()
            env["GODOT_AI_ALLOW_HEADLESS"] = "1"
            env["GODOT_AI_DISABLE_TELEMETRY"] = "true"
            env["GODOT_AI_VENV_PYTHON"] = sys.executable
            source = str((args.core_root / "src").resolve())
            env["PYTHONPATH"] = os.pathsep.join(filter(None, [source, env.get("PYTHONPATH", "")]))
            log_path.parent.mkdir(parents=True, exist_ok=True)
            log_stream = log_path.open("wb")
            command = [args.godot, "--headless", "--editor", "--path", str(args.project)]
            if os.name == "nt" and not Path(args.godot).is_file():
                # setup-godot exposes an extensionless Bash launcher on Windows.
                # Git Bash resolves it, while Win32 CreateProcess("godot") does not.
                command = ["bash", "-c", "exec " + " ".join(map(shlex.quote,
                    [args.godot, "--headless", "--editor", "--path", args.project.as_posix()]))]
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
