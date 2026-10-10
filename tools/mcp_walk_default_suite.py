"""Run focused default-integration tests through a live Godot AI MCP session."""
from __future__ import annotations
import argparse
import asyncio
import json
from pathlib import Path
from mcp_presets_audit import call
from mcp_rig_modifier_ui_history import connected_editor


async def run(args: argparse.Namespace) -> int:
    async with connected_editor(args) as (client, connection):
        opened = await call(client, "scene_open", {"path": "res://main.tscn"})
        params = {"suite": "animation_motion", "verbose": True}
        if args.test_name:
            params["test_name"] = args.test_name
        tests = await call(client, "test_run", params)
        report = {"connection": connection, "open": opened, "tests": tests}
        args.output.write_text(json.dumps(report, indent=2), encoding="utf-8")
        print(json.dumps({"output": str(args.output), "summary": {
            key: tests.get(key) for key in ("total", "passed", "failed", "skipped", "load_errors", "error")}}))
        return int(bool(opened.get("error") or tests.get("error") or tests.get("failed", 0)))


if __name__ == "__main__":
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--core-root", type=Path, required=True)
    p.add_argument("--project-root", type=Path, required=True)
    p.add_argument("--port", type=int, default=8000)
    p.add_argument("--ws-port", type=int, default=9500)
    p.add_argument("--output", type=Path, required=True)
    p.add_argument("--test-name", default="", help="Optional exact golden/test filter for deliberate fixture migration")
    raise SystemExit(asyncio.run(run(p.parse_args())))
