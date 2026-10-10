"""Create and inspect clip edits for visible Godot scene Undo/Redo checks."""
from __future__ import annotations
import argparse
import asyncio
from datetime import datetime, timezone
import json
from pathlib import Path
import sys
from fastmcp import Client
from fastmcp.client.transports import StdioTransport
from fixture_copy import copy_scene
from mcp_presets_audit import call
from mcp_edit_audit import equivalent

PLAYER = "/RepairGraphFixture/AnimationPlayer"


async def snapshot(client: Client) -> dict:
    result = {}
    for name in ("walk", "run", "walk_head", "walk_run"):
        data = await call(client, "custom_animation_inspect", {"op": "timeline",
            "player_path": PLAYER, "animation_name": name, "max_keys": 1000})
        result[name] = data
    return result


async def run(args: argparse.Namespace) -> int:
    transport = StdioTransport(sys.executable, ["-m", "godot_ai", "attach", "--port", str(args.port),
        "--ws-port", str(args.ws_port)], cwd=str(args.core_root), keep_alive=False)
    async with Client(transport) as client:
        await client.call_tool("session_activate", {"session_id": args.session_hint})
        if args.mode == "setup":
            folder = args.project_root / "repair_ui_undo"
            folder.mkdir(parents=True, exist_ok=True)
            stamp = datetime.now(timezone.utc).strftime("%Y%m%d_%H%M%S")
            target = folder / f"edit_{args.op}_{stamp}.tscn"
            copy_scene(args.project_root / "repair_edit_fixture.tscn", target)
            source = target.read_text(encoding="utf-8")
            source = source.replace('&"lean": SubResource("Lean")}',
                '&"lean": SubResource("Lean"), &"walk_head": SubResource("Run"), &"walk_run": SubResource("Jump")}')
            target.write_text(source, encoding="utf-8")
            scene = "res://repair_ui_undo/" + target.name
            opened = await call(client, "scene_open", {"path": scene})
            baseline = await snapshot(client)
            extras = {"retime": {"factor": 0.5},
                      "split_at": {"time": 0.5, "head_name": "walk_head", "overwrite": True},
                      "merge": {"sources": [{"animation_name": "walk"}, {"animation_name": "run"}],
                                "new_name": "walk_run", "overwrite": True}}[args.op]
            made = await call(client, "custom_animation_edit", {"op": args.op, "player_path": PLAYER,
                "animation_name": "walk", **extras})
            generated = await snapshot(client)
            record = {"op": args.op, "scene": scene, "open": opened, "made": made,
                      "baseline": baseline, "generated": generated}
            args.record.write_text(json.dumps(record, indent=2), encoding="utf-8")
            passed = not opened.get("error") and not made.get("error") and not equivalent(baseline, generated)
            result = {"passed": passed, "scene": scene, "op": args.op, "record": str(args.record)}
        else:
            record = json.loads(args.record.read_text(encoding="utf-8"))
            if args.mode == "open":
                await call(client, "scene_open", {"path": record["scene"]})
            actual = await snapshot(client)
            passed = equivalent(actual, record[args.expect])
            result = {"passed": passed, "scene": record["scene"], "expected": args.expect,
                      "actual": actual}
    print("MCP_EDIT_UI_HISTORY=" + json.dumps(result, sort_keys=True))
    return 0 if passed else 1


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--core-root", type=Path, required=True)
    parser.add_argument("--project-root", type=Path, required=True)
    parser.add_argument("--session-hint", required=True)
    parser.add_argument("--port", type=int, required=True)
    parser.add_argument("--ws-port", type=int, required=True)
    parser.add_argument("--mode", choices=("setup", "inspect", "open"), required=True)
    parser.add_argument("--op", choices=("retime", "split_at", "merge"), default="retime")
    parser.add_argument("--expect", choices=("baseline", "generated"), default="generated")
    parser.add_argument("--record", type=Path, required=True)
    return asyncio.run(run(parser.parse_args()))


if __name__ == "__main__":
    raise SystemExit(main())
