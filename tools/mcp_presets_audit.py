"""Exercise preset contracts through a live Godot AI MCP session on Godot 4.7.2.

The dedicated repair_presets_fixture.tscn is force-reloaded before each op.
Successful clips are left saved in that fixture as review evidence.
"""

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
from fastmcp.exceptions import ToolError


SCENE_TEMPLATE = "repair_presets_fixture.tscn"
PLAYER = "/RepairPresetsFixture/AnimationPlayer"
CASES = {
    "pulse": {"target_path": "Target3D", "from_scale": 1.0, "to_scale": 1.2},
    "bounce": {"target_path": "Target2D", "intensity": 0.2},
    "orbit": {"target_path": "Target3D", "radius": 0.7},
    "sweep": {"target_path": "Target2D", "turns": 1.0},
    "drift": {"target_path": "Target3D", "axis": "x", "distance": 0.5},
    "spin": {"target_path": "Target3D", "turns": 1.0},
    "float": {"target_path": "Target3D", "height": 0.35},
    "stagger": {"target_paths": ["Target2D", "Other2D"], "effect": "fade_in"},
    "showcase": {"name": "RepairShowcase"},
}
SHOWCASE_PLAYERS = ["AnimBounce", "AnimOrbit", "AnimSweep", "AnimDrift",
                    "AnimPulse", "AnimFloat", "AnimSpin"]


def payload(result: object) -> dict:
    data = result.structured_content or {}
    if not data and result.content:
        data = json.loads(result.content[0].text)
    return data


async def call(client: Client, name: str, params: dict) -> dict:
    try:
        return payload(await client.call_tool(name, params))
    except ToolError as exc:
        return {"error": str(exc)}


def clip_summary(value: dict) -> dict:
    clips = value.get("clips", [])
    return {
        "error": value.get("error"),
        "clips": [
            {
                "name": c.get("name"),
                "track_count": c.get("track_count"),
                "key_count": c.get("key_count"),
                "tracks": [
                    {"path": t.get("path"), "type": t.get("type"),
                     "node_resolved": t.get("node_resolved")}
                    for t in c.get("tracks", [])
                ],
            }
            for c in clips
        ],
    }


def verify_record(record: dict) -> list[str]:
    op = record["op"]
    failures = []
    for stage in ("open_error", "dry_error", "create_error"):
        if record.get(stage):
            failures.append(f"{op}: {stage}: {record[stage]}")
    if record.get("save", {}).get("error") or record.get("reopen", {}).get("error"):
        failures.append(f"{op}: save/reopen failed")
    if op == "showcase":
        path = "/RepairPresetsFixture/RepairShowcase"
        after_dry = {n.get("path") for n in record.get("after_dry_hierarchy", {}).get("nodes", [])}
        persisted = {n.get("path") for n in record.get("persisted_hierarchy", {}).get("nodes", [])}
        if path in after_dry or path not in persisted:
            failures.append("showcase: dry run mutated scene or saved subtree is absent")
        if record.get("create_payload", {}).get("animations") != 7:
            failures.append("showcase: expected seven authored clips")
        for player in SHOWCASE_PLAYERS:
            clips = record.get("showcase_clips", {}).get(player, {}).get("clips", [])
            if len(clips) != 1 or clips[0].get("track_count", 0) < 1 \
                    or any(not t.get("node_resolved") for t in clips[0].get("tracks", [])):
                failures.append(f"showcase: {player} clip has invalid saved tracks")
        return failures
    if record.get("before", {}).get("clips") or record.get("after_dry", {}).get("clips"):
        failures.append(f"{op}: dry run changed the player")
    for stage in ("created", "persisted"):
        clips = record.get(stage, {}).get("clips", [])
        if len(clips) != 1 or clips[0].get("track_count", 0) < 1 \
                or clips[0].get("key_count", 0) < 2 \
                or any(not t.get("node_resolved") for t in clips[0].get("tracks", [])):
            failures.append(f"{op}: {stage} clip is missing or has invalid tracks")
    return failures


async def inspect(client: Client, op: str) -> dict:
    return clip_summary(await call(client, "custom_animation_inspect", {
        "op": "describe", "player_path": PLAYER,
        "animation_name": "audit_" + op,
    }))


async def run(args: argparse.Namespace) -> int:
    transport = StdioTransport(
        sys.executable,
        ["-m", "godot_ai", "attach", "--port", str(args.port),
         "--ws-port", str(args.ws_port)],
        cwd=str(args.core_root), keep_alive=False,
    )
    records = []
    run_id = datetime.now(timezone.utc).strftime("%Y%m%d_%H%M%S")
    run_dir = args.project_root / "repair_presets_audit" / run_id
    run_dir.mkdir(parents=True, exist_ok=False)
    async with Client(transport) as client:
        await client.call_tool("session_activate", {"session_id": args.session_hint})
        tools = {tool.name: tool for tool in await client.list_tools()}
        required = tools["custom_animation_presets"].inputSchema.get("required", [])
        if required != ["op"]:
            raise RuntimeError(f"preset schema still blocks showcase: {required}")
        for op, extras in CASES.items():
            if args.only and op not in args.only:
                continue
            record = {"op": op}
            scene_name = f"{op}.tscn"
            copy_scene(args.project_root / SCENE_TEMPLATE, run_dir / scene_name)
            scene_path = f"res://repair_presets_audit/{run_id}/{scene_name}"
            record["scene"] = scene_path
            opened = await call(client, "scene_open", {"path": scene_path, "force_reload": True})
            record["open_error"] = opened.get("error")
            if opened.get("error"):
                records.append(record)
                continue
            params = {"op": op, **extras}
            if op != "showcase":
                params.update({"player_path": PLAYER, "animation_name": "audit_" + op})
                record["before"] = await inspect(client, op)
            dry = await call(client, "custom_animation_presets", {**params, "dry_run": True})
            record["dry_error"] = dry.get("error")
            record["dry_payload"] = dry if op == "showcase" else dry.get("data")
            if op != "showcase":
                record["after_dry"] = await inspect(client, op)
            else:
                record["after_dry_hierarchy"] = await call(client, "scene_get_hierarchy", {"depth": 2})
            created = await call(client, "custom_animation_presets", params)
            record["create_error"] = created.get("error")
            record["create_payload"] = created if op == "showcase" else created.get("data")
            if created.get("error"):
                records.append(record)
                continue
            if op != "showcase":
                record["created"] = await inspect(client, op)
            else:
                record["created_hierarchy"] = await call(client, "scene_get_hierarchy", {"depth": 2})
            # Godot AI exposes undo in the editor UI, but no MCP undo/redo
            # tool. Editor suite tests cover the history until a UI bridge is
            # available; do not mislabel those as MCP checks.
            record["mcp_undo_redo"] = "unavailable"
            record["save"] = await call(client, "scene_save", {})
            record["reopen"] = await call(client, "scene_open", {
                "path": scene_path, "force_reload": True})
            if op != "showcase":
                record["persisted"] = await inspect(client, op)
            else:
                record["persisted_hierarchy"] = await call(client, "scene_get_hierarchy", {"depth": 2})
                record["showcase_clips"] = {}
                for player in SHOWCASE_PLAYERS:
                    clip = player.removeprefix("Anim").lower()
                    record["showcase_clips"][player] = clip_summary(await call(
                        client, "custom_animation_inspect", {
                            "op": "describe",
                            "player_path": f"/RepairPresetsFixture/RepairShowcase/{player}",
                            "animation_name": clip,
                        }))
            records.append(record)
    failures = [message for record in records for message in verify_record(record)]
    print("MCP_PRESETS_AUDIT=" + json.dumps({
        "run_id": run_id, "schema_required": required,
        "operations": records, "failures": failures,
    }, sort_keys=True))
    return 1 if failures else 0


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--core-root", type=Path, required=True)
    parser.add_argument("--project-root", type=Path, default=Path.cwd() / "test_project")
    parser.add_argument("--session-hint", required=True)
    parser.add_argument("--port", type=int, required=True)
    parser.add_argument("--ws-port", type=int, required=True)
    parser.add_argument("--only", nargs="*", default=[])
    return asyncio.run(run(parser.parse_args()))


if __name__ == "__main__":
    raise SystemExit(main())
