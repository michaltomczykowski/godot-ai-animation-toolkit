"""Run a small persistent toolkit operation through a connected Godot AI editor.

This operates only on res://repair_toolkit_fixture.tscn in the selected project.
"""

from __future__ import annotations

import argparse
import asyncio
import json
import sys
from pathlib import Path

from fastmcp import Client
from fastmcp.client.transports import StdioTransport
from fastmcp.exceptions import ToolError


def payload(result: object) -> dict:
    data = result.structured_content or {}
    if not data and result.content:
        data = json.loads(result.content[0].text)
    return data


async def run(args: argparse.Namespace) -> int:
    transport = StdioTransport(
        sys.executable,
        ["-m", "godot_ai", "attach", "--port", str(args.port),
         "--ws-port", str(args.ws_port)],
        cwd=str(args.core_root),
        keep_alive=False,
    )
    async with Client(transport) as client:
        result = {}
        result["activate"] = payload(await client.call_tool(
            "session_activate", {"session_id": args.session_hint}))
        result["open"] = payload(await client.call_tool(
            "scene_open", {"path": "res://repair_toolkit_fixture.tscn"}))
        params = {
            "op": "pulse", "player_path": "/RepairFixture/AnimationPlayer",
            "target_path": "Target", "animation_name": "repair_probe_pulse",
            "property": "scale", "from_scale": 1.0, "to_scale": 1.2,
            "duration": 0.8, "loop_mode": "pingpong", "overwrite": True,
        }
        result["dry_run"] = payload(await client.call_tool(
            "custom_animation_presets", {**params, "dry_run": True}))
        try:
            result["before"] = payload(await client.call_tool(
                "custom_animation_inspect", {
                    "op": "describe", "player_path": params["player_path"],
                    "animation_name": params["animation_name"],
                }))
        except ToolError as exc:
            result["before"] = {"error": str(exc)}
        result["create"] = payload(await client.call_tool(
            "custom_animation_presets", params))
        result["after"] = payload(await client.call_tool(
            "custom_animation_inspect", {
                "op": "describe", "player_path": params["player_path"],
                "animation_name": params["animation_name"],
            }))
        result["save"] = payload(await client.call_tool("scene_save", {}))
        result["reopen"] = payload(await client.call_tool(
            "scene_open", {"path": "res://repair_toolkit_fixture.tscn", "force_reload": True}))
        result["persisted"] = payload(await client.call_tool(
            "custom_animation_inspect", {
                "op": "describe", "player_path": params["player_path"],
                "animation_name": params["animation_name"],
            }))
        summary = {}
        for key, data in result.items():
            if key in ("after", "persisted", "before"):
                summary[key] = {
                    "clip_count": data.get("clip_count"),
                    "clips": [{"name": clip.get("name"), "track_count": clip.get("track_count"),
                               "key_count": clip.get("key_count"), "tracks": [
                                   {"path": track.get("path"), "type": track.get("type"),
                                    "node_resolved": track.get("node_resolved")}
                                   for track in clip.get("tracks", [])]}
                              for clip in data.get("clips", [])],
                    "error": data.get("error"),
                }
            else:
                summary[key] = data
        print("MCP_REAL_FIXTURE=" + json.dumps(summary, sort_keys=True))
        clips = summary["persisted"]["clips"]
        return 0 if len(clips) == 1 and clips[0]["track_count"] > 0 \
            and all(track["node_resolved"] for track in clips[0]["tracks"]) else 1


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--core-root", type=Path, required=True)
    parser.add_argument("--session-hint", required=True)
    parser.add_argument("--port", type=int, required=True)
    parser.add_argument("--ws-port", type=int, required=True)
    return asyncio.run(run(parser.parse_args()))


if __name__ == "__main__":
    raise SystemExit(main())
