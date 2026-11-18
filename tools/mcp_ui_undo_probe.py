"""Set up and inspect one unsaved preset action for a Godot editor UI undo check."""

from __future__ import annotations

import argparse
import asyncio
import json
from fixture_copy import copy_scene
import sys
from datetime import datetime, timezone
from pathlib import Path

from fastmcp import Client
from fastmcp.client.transports import StdioTransport

from mcp_presets_audit import call, clip_summary


async def run(args: argparse.Namespace) -> int:
    transport = StdioTransport(
        sys.executable,
        ["-m", "godot_ai", "attach", "--port", str(args.port),
         "--ws-port", str(args.ws_port)],
        cwd=str(args.core_root), keep_alive=False,
    )
    result = {"mode": args.mode}
    async with Client(transport) as client:
        await client.call_tool("session_activate", {"session_id": args.session_hint})
        if args.mode == "setup":
            run_id = datetime.now(timezone.utc).strftime("%Y%m%d_%H%M%S")
            target = args.project_root / "repair_ui_undo" / f"{run_id}.tscn"
            target.parent.mkdir(parents=True, exist_ok=True)
            copy_scene(args.project_root / "repair_presets_fixture.tscn", target)
            result["scene"] = "res://repair_ui_undo/" + target.name
            result["open"] = await call(client, "scene_open", {"path": result["scene"]})
            result["create"] = await call(client, "custom_animation_presets", {
                "op": "pulse", "player_path": "/RepairPresetsFixture/AnimationPlayer",
                "target_path": "Target3D", "animation_name": "ui_undo_pulse",
                "from_scale": 1.0, "to_scale": 1.2,
            })
        result["inspect"] = clip_summary(await call(client, "custom_animation_inspect", {
            "op": "describe", "player_path": "/RepairPresetsFixture/AnimationPlayer",
            "animation_name": "ui_undo_pulse",
        }))
    print("MCP_UI_UNDO=" + json.dumps(result, sort_keys=True))
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--core-root", type=Path, required=True)
    parser.add_argument("--project-root", type=Path, default=Path.cwd() / "test_project")
    parser.add_argument("--session-hint", required=True)
    parser.add_argument("--port", type=int, required=True)
    parser.add_argument("--ws-port", type=int, required=True)
    parser.add_argument("--mode", choices=["setup", "inspect"], required=True)
    return asyncio.run(run(parser.parse_args()))


if __name__ == "__main__":
    raise SystemExit(main())
