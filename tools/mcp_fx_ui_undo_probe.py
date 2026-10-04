"""Set up and inspect one unsaved FX action for Godot editor undo/redo."""

from __future__ import annotations

import argparse
import asyncio
from datetime import datetime, timezone
import json
from fixture_copy import copy_scene
import sys
from pathlib import Path

from fastmcp import Client
from fastmcp.client.transports import StdioTransport

from mcp_presets_audit import call


async def run(args: argparse.Namespace) -> int:
    transport = StdioTransport(sys.executable, ["-m", "godot_ai", "attach",
        "--port", str(args.port), "--ws-port", str(args.ws_port)],
        cwd=str(args.core_root), keep_alive=False)
    row = {"mode": args.mode}
    async with Client(transport) as client:
        await client.call_tool("session_activate", {"session_id": args.session_hint})
        if args.mode == "setup":
            run_id = datetime.now(timezone.utc).strftime("%Y%m%d_%H%M%S")
            folder = args.project_root / "repair_ui_undo"
            folder.mkdir(parents=True, exist_ok=True)
            target = folder / f"fx_{args.op}_{run_id}.tscn"
            copy_scene(args.project_root / "repair_fx_fixture.tscn", target)
            row["scene"] = "res://repair_ui_undo/" + target.name
            row["open"] = await call(client, "scene_open", {"path": row["scene"]})
            params = {"op": args.op, "player_path": "/RepairFxFixture/AnimationPlayer",
                      "animation_name": "ui_undo_" + args.op}
            if args.op == "wave":
                params["target_paths"] = ["Card1", "Card2", "Card3"]
            elif args.op == "transition":
                params.update(target_path="FadeOverlay", mode="wipe_left")
            else:
                params.update(sprite_path="/RepairFxFixture/SheetSprite",
                              texture="res://tests/fixtures/sheet.png",
                              hframes=4, vframes=1, play=False)
            row["create"] = await call(client, "custom_animation_fx", params)
        if args.op != "sprite_frames":
            row["inspect"] = await call(client, "custom_animation_inspect", {
                "op": "describe", "player_path": "/RepairFxFixture/AnimationPlayer",
                "animation_name": "ui_undo_" + args.op})
        if args.op != "wave":
            row["properties"] = await call(client, "node_get_properties", {
                "path": "/RepairFxFixture/" + ("SheetSprite" if args.op == "sprite_frames" else "FadeOverlay")})
    print("MCP_FX_UI_UNDO=" + json.dumps(row, sort_keys=True))
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--core-root", type=Path, required=True)
    parser.add_argument("--project-root", type=Path,
                        default=Path.cwd() / "test_project")
    parser.add_argument("--session-hint", required=True)
    parser.add_argument("--port", type=int, required=True)
    parser.add_argument("--ws-port", type=int, required=True)
    parser.add_argument("--mode", choices=["setup", "inspect"], required=True)
    parser.add_argument("--op", choices=["wave", "transition", "sprite_frames"], default="wave")
    return asyncio.run(run(parser.parse_args()))


if __name__ == "__main__":
    raise SystemExit(main())
