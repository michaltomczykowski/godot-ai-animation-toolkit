"""Require character setup history and isolated audits through Godot AI."""
from __future__ import annotations

import argparse
import asyncio
import json
from pathlib import Path
import subprocess
import sys
from fastmcp import Client
from fastmcp.client.transports import StdioTransport
from mcp_presets_audit import call

EXPECTED = {"test_new_setup_history", "test_replaced_setup_history",
            "test_missing_library_setup_history", "test_instanced_setup_history",
            "test_instanced_new_setup_history", "test_root_motion_false_clears_existing_extraction",
            "test_editable_instance_keeps_source_library_isolated"}
AUDIT_EXPECTED = {"test_motion_audit_grades_planted_feet_and_hips",
                  "test_motion_audit_checks_strafe_foot_order",
                  "test_run_motion_audit_reports_flight_and_extension",
                  "test_audit_copy_preserves_live_children_without_script_constructors"}
CASES = ("new_root", "replace_root", "missing_library_root", "instanced_root",
         "instanced_new_root", "instanced_editable_root", "replace_in_place")


async def run(args: argparse.Namespace) -> int:
    transport = StdioTransport(sys.executable, ["-m", "godot_ai", "attach",
        "--port", str(args.port), "--ws-port", str(args.ws_port)],
        cwd=str(args.core_root), keep_alive=False)
    async with Client(transport) as client:
        await client.call_tool("session_activate", {"session_id": args.session_hint})
        await call(client, "scene_open", {"path": "res://main.tscn"})
        result = await call(client, "test_run", {"suite": "character_route_history", "verbose": True})
        audit = await call(client, "test_run", {"suite": "animation_inspect", "verbose": True})
    rows = result.get("results", [])
    passed = (result.get("failed") == 0 and result.get("passed") == len(EXPECTED)
              and result.get("total") == len(EXPECTED) and len(rows) == len(EXPECTED)
              and {row.get("test") for row in rows} == EXPECTED
              and all(row.get("passed") and row.get("assertion_count", 0) > 0 for row in rows))
    audit_rows = audit.get("results", [])
    passed = passed and audit.get("failed") == 0 and AUDIT_EXPECTED.issubset(
        {r.get("test") for r in audit_rows if r.get("passed") and r.get("assertion_count", 0) > 0})
    failures = []
    count = 0
    if passed and args.godot:
        for case in CASES:
            for fps in (30, 60, 120):
                try:
                    runtime = subprocess.run([
                        args.godot, "--headless", "--path", str(args.project_root),
                        "--script", "res://tools/check_character_history_runtime.gd", "--",
                        f"user://character_history_{case}_redo.tscn",
                        "false" if case.endswith("in_place") else "true", str(fps),
                    ], capture_output=True, text=True, timeout=20, check=False)
                except subprocess.TimeoutExpired as exc:
                    failures.append({"case": case, "fps": fps, "error": "playback timeout",
                                     "output": str(exc.stdout or "")[-2200:]})
                    continue
                marker = "CHARACTER_HISTORY_RUNTIME="
                report = next((line[len(marker):] for line in runtime.stdout.splitlines()
                               if line.startswith(marker)), "")
                if runtime.returncode or not report or json.loads(report).get("failures"):
                    failures.append({"case": case, "fps": fps,
                                     "output": (runtime.stdout + runtime.stderr)[-2200:]})
                else:
                    count += 1
    passed = passed and not failures
    print("MCP_CHARACTER_HISTORY=" + json.dumps({"passed": passed, "result": result, "audit": audit,
          "saved_cases": count, "runtime_failures": failures}, sort_keys=True))
    return 0 if passed else 1


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--core-root", type=Path, required=True)
    parser.add_argument("--session-hint", required=True)
    parser.add_argument("--port", type=int, required=True)
    parser.add_argument("--ws-port", type=int, required=True)
    parser.add_argument("--godot")
    parser.add_argument("--project-root", type=Path, default=Path.cwd() / "test_project")
    return asyncio.run(run(parser.parse_args()))


if __name__ == "__main__":
    raise SystemExit(main())
