"""Prepare and inspect preset/library actions for visible Ctrl+Z verification."""
from __future__ import annotations
import argparse
import asyncio
from datetime import datetime, timezone
import json
from pathlib import Path
import sys
from fastmcp import Client
from fastmcp.client.transports import StdioTransport
from mcp_presets_audit import call
from mcp_edit_audit import equivalent


async def snapshot(client: Client, op: str) -> dict:
    result = {}
    names = ["bounce", "orbit", "sweep", "drift", "pulse", "float", "spin"] if op == "showcase" else ["generated"]
    for name in names:
        player = ("/PresetUI/ReviewShowcase/Anim" + name.title()) if op == "showcase" else "/PresetUI/AnimationPlayer"
        clip = await call(client, "custom_animation_inspect", {"op": "timeline", "player_path": player,
            "animation_name": name, "max_keys": 1000})
        result[name] = {"absent": True} if clip.get("error") else clip
    widget = await call(client, "node_get_properties", {"path": "/PresetUI/Widget", "fields": ["pivot_offset", "scale"]})
    result["widget"] = widget.get("properties", [])
    return result


async def run(args: argparse.Namespace) -> int:
    transport = StdioTransport(sys.executable, ["-m", "godot_ai", "attach", "--port", str(args.port),
        "--ws-port", str(args.ws_port)], cwd=str(args.core_root), keep_alive=False)
    async with Client(transport) as client:
        await client.call_tool("session_activate", {"session_id": args.session_hint})
        if args.mode == "setup":
            folder = args.project_root / "repair_ui_undo"
            folder.mkdir(parents=True, exist_ok=True)
            target = folder / f"preset_library_{args.op}_{datetime.now(timezone.utc):%Y%m%d_%H%M%S}.tscn"
            target.write_text('''[gd_scene load_steps=2 format=3]
[sub_resource type="AnimationLibrary" id="Library"]
[node name="PresetUI" type="Node2D"]
[node name="Widget" type="Control" parent="."]
offset_left = 100.0
offset_top = 100.0
offset_right = 220.0
offset_bottom = 160.0
pivot_offset = Vector2(7, 9)
[node name="AnimationPlayer" type="AnimationPlayer" parent="."]
libraries = {&"": SubResource("Library")}
''', encoding="utf-8")
            scene = "res://repair_ui_undo/" + target.name
            opened = await call(client, "scene_open", {"path": scene})
            baseline = await snapshot(client, args.op)
            if args.op == "template":
				path = "res://animation_toolkit/" + target.stem + "_recipe.json"
                saved = await call(client, "custom_animation_library", {"op": "template_save", "name": "ui_bounce",
                    "tool": "animation_presets", "forward_op": "bounce", "library_path": path, "overwrite": True, "intensity": 0.25})
                if saved.get("error"): raise RuntimeError(saved)
                made = await call(client, "custom_animation_library", {"op": "template_apply", "name": "ui_bounce",
                    "library_path": path, "player_path": "/PresetUI/AnimationPlayer", "target_path": "Widget", "animation_name": "generated"})
            elif args.op == "showcase":
                made = await call(client, "custom_animation_presets", {"op": "showcase", "name": "ReviewShowcase"})
            else:
                made = await call(client, "custom_animation_presets", {"op": "bounce", "player_path": "/PresetUI/AnimationPlayer",
                    "target_path": "Widget", "animation_name": "generated", "intensity": 0.25})
            generated = await snapshot(client, args.op)
            record = {"op": args.op, "scene": scene, "open": opened, "made": made, "baseline": baseline, "generated": generated}
            args.record.write_text(json.dumps(record, indent=2), encoding="utf-8")
            passed = not opened.get("error") and not made.get("error") and not equivalent(baseline, generated)
            result = {"passed": passed, "scene": scene, "op": args.op}
        else:
            record = json.loads(args.record.read_text(encoding="utf-8"))
            actual = await snapshot(client, record["op"])
            result = {"passed": equivalent(actual, record[args.expect]), "scene": record["scene"], "expected": args.expect, "actual": actual}
    print("MCP_PRESET_LIBRARY_UI_HISTORY=" + json.dumps(result, sort_keys=True))
    return 0 if result["passed"] else 1


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--core-root", type=Path, required=True)
    parser.add_argument("--project-root", type=Path, required=True)
    parser.add_argument("--session-hint", required=True)
    parser.add_argument("--port", type=int, required=True)
    parser.add_argument("--ws-port", type=int, required=True)
    parser.add_argument("--mode", choices=("setup", "inspect"), required=True)
    parser.add_argument("--op", choices=("bounce", "template", "showcase"), default="bounce")
    parser.add_argument("--expect", choices=("baseline", "generated"), default="generated")
    parser.add_argument("--record", type=Path, required=True)
    return asyncio.run(run(parser.parse_args()))


if __name__ == "__main__":
    raise SystemExit(main())
