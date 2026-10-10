"""Probe the toolkit through Godot AI's authenticated MCP attach bridge.

Run with the Python environment bundled with the connected Godot AI checkout:
  python tools/mcp_probe.py --core-root G:/godot-ai-dev/godot-ai-v4-animation

This is intentionally read-only. It verifies what an MCP agent can discover,
then invokes an inspect operation through the public custom_manage route.
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


EXPECTED_PROMOTED = {
    "custom_animation_edit",
    "custom_animation_fx",
    "custom_animation_graph",
    "custom_animation_inspect",
    "custom_animation_library",
    "custom_animation_motion",
    "custom_animation_presets",
    "custom_animation_rig",
}
EXPECTED_CATALOG = {
    name.removeprefix("custom_") for name in EXPECTED_PROMOTED
} | {"animation_rig_modifiers", "animation_sequence"}


def payload(result: object) -> dict:
    data = result.structured_content or {}
    if not data and result.content:
        data = json.loads(result.content[0].text)
    return data


async def probe(args: argparse.Namespace) -> int:
    transport = StdioTransport(
        sys.executable,
        [
            "-m", "godot_ai", "attach", "--port", str(args.port),
            "--ws-port", str(args.ws_port),
        ],
        cwd=str(args.core_root),
        keep_alive=False,
    )
    async with Client(transport) as client:
        if args.activate_auto:
            available = payload(await client.call_tool("session_manage", {"op": "list"}))
            candidates = available.get("sessions", [])
            if len(candidates) != 1:
                print("MCP_ACTIVATE_ERROR=" + json.dumps({
                    "expected_sessions": 1, "found": len(candidates),
                }, sort_keys=True))
                return 1
            args.activate = str(candidates[0].get("session_id", ""))
        if args.activate:
            activated = await client.call_tool("session_activate", {"session_id": args.activate})
            print("MCP_ACTIVATE=" + json.dumps(payload(activated), sort_keys=True))
        tools = {tool.name: tool for tool in await client.list_tools()}
        if args.show_schemas:
            for name in ["scene_open", "scene_save", "editor_undo", "editor_redo", "custom_animation_presets", "custom_animation_inspect"]:
                if name in tools:
                    print("MCP_SCHEMA=" + json.dumps({"name": name, "schema": tools[name].inputSchema}, sort_keys=True))
        promoted = sorted(EXPECTED_PROMOTED & tools.keys())
        missing_promoted = sorted(EXPECTED_PROMOTED - tools.keys())
        wrong_schemas = sorted(
            name for name in promoted
            if "op" not in tools[name].inputSchema.get("properties", {})
        )
        listed = await client.call_tool("custom_manage", {"op": "list", "params": {}})
        catalog = payload(listed)
        sessions_result = await client.call_tool("session_manage", {"op": "list"})
        sessions = payload(sessions_result)
        names = {str(item.get("name", "")) for item in catalog.get("tools", [])}
        missing_catalog = sorted(EXPECTED_CATALOG - names)
        result = {
            "mcp_tool_count": len(tools),
            "promoted": promoted,
            "missing_promoted": missing_promoted,
            "wrong_schemas": wrong_schemas,
            "catalog": sorted(names),
            "missing_catalog": missing_catalog,
            "sessions": sessions,
        }
        family_errors = {}
        for family in sorted(EXPECTED_CATALOG & names):
            try:
                promoted_name = "custom_" + family
                if promoted_name in tools:
                    await client.call_tool(promoted_name, {"op": "__mcp_probe_unknown__"})
                else:
                    await client.call_tool("custom_manage", {"op": "invoke", "params": {
                        "tool_name": family,
                        "params": {"op": "__mcp_probe_unknown__"},
                    }})
                family_errors[family] = ""
            except ToolError as exc:
                family_errors[family] = str(exc)
        result["family_invalid_errors"] = family_errors
        cross_family_errors = {}
        for family, wrong_op in [
            ("animation_rig", "ik_setup"),
            ("animation_rig_modifiers", "pose_save"),
        ]:
            try:
                await client.call_tool("custom_manage", {"op": "invoke", "params": {
                    "tool_name": family, "params": {"op": wrong_op},
                }})
                cross_family_errors[family] = ""
            except ToolError as exc:
                cross_family_errors[family] = str(exc)
        result["cross_family_errors"] = cross_family_errors
        if args.valid_pulse_scene:
            pulse = {
                "op": "pulse", "player_path": "/RouteFixture/Anim",
                "target_path": "Target", "property": "scale",
                "from_scale": 1.0, "to_scale": 1.2, "duration": 0.8,
                "loop_mode": "pingpong", "animation_name": "mcp_route_pulse",
                "overwrite": True,
            }
            opened = payload(await client.call_tool("scene_open", {
                "path": args.valid_pulse_scene, "force_reload": True,
            }))
            async def describe_pulse() -> dict:
                try:
                    return payload(await client.call_tool("custom_animation_inspect", {
                        "op": "describe", "player_path": pulse["player_path"],
                        "animation_name": pulse["animation_name"],
                    }))
                except ToolError as exc:
                    return {"error": str(exc)}
            before_dry = await describe_pulse()
            dry = payload(await client.call_tool("custom_animation_presets", {
                **pulse, "dry_run": True,
            }))
            after_dry = await describe_pulse()
            created = payload(await client.call_tool("custom_animation_presets", pulse))
            saved = payload(await client.call_tool("scene_save", {}))
            reopened = payload(await client.call_tool("scene_open", {
                "path": args.valid_pulse_scene, "force_reload": True,
            }))
            inspected = await describe_pulse()
            clips = inspected.get("clips", [])
            tracks = clips[0].get("tracks", []) if len(clips) == 1 else []
            result["valid_pulse"] = {
                "opened": not opened.get("error"),
                "dry": not dry.get("error") and dry.get("dry_run") is True,
                "dry_unchanged": before_dry == after_dry,
                "created": not created.get("error"),
                "saved": not saved.get("error"),
                "reopened": not reopened.get("error"),
                "clip_count": len(clips),
                "track_count": len(tracks),
                "paths_resolved": bool(tracks) and all(t.get("node_resolved") for t in tracks),
            }
        if args.player_path and "custom_animation_inspect" in tools:
            try:
                inspected = await client.call_tool(
                    "custom_animation_inspect",
                    {"op": "describe", "player_path": args.player_path},
                )
                content = payload(inspected)
                result["inspect_status"] = content.get("status", "ok")
                result["inspect_error_code"] = content.get("error", {}).get("code", "")
                result["inspect_has_data"] = "clip_count" in content and "clips" in content
            except Exception as exc:
                result["inspect_call_error"] = str(exc)
        print("MCP_PROBE=" + json.dumps(result, sort_keys=True))
        if args.reload:
            try:
                reloaded = payload(await client.call_tool("editor_reload_plugin", {}))
                print("MCP_RELOAD=" + json.dumps(reloaded, sort_keys=True))
            except Exception as exc:
                print("MCP_RELOAD_ERROR=" + str(exc))
                return 1
        return 1 if missing_promoted or wrong_schemas or missing_catalog \
            or len(family_errors) != len(EXPECTED_CATALOG) \
            or any(not error.startswith("VALUE_OUT_OF_RANGE")
                   for error in family_errors.values()) \
            or "ik_setup" not in family_errors.get("animation_rig_modifiers", "") \
            or len(cross_family_errors) != 2 \
            or any(not error.startswith("VALUE_OUT_OF_RANGE")
                   for error in cross_family_errors.values()) \
            or (args.valid_pulse_scene and not all(result["valid_pulse"].values())) \
            or (args.player_path and not result.get("inspect_has_data")) else 0


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--core-root", type=Path, required=True)
    parser.add_argument("--port", type=int, required=True)
    parser.add_argument("--ws-port", type=int, required=True)
    parser.add_argument("--player-path", default="")
    parser.add_argument("--activate", default="")
    parser.add_argument("--activate-auto", action="store_true")
    parser.add_argument("--valid-pulse-scene", default="")
    parser.add_argument("--show-schemas", action="store_true")
    parser.add_argument("--reload", action="store_true")
    args = parser.parse_args()
    if not args.core_root.is_dir():
        parser.error("--core-root must name the Godot AI source checkout")
    return asyncio.run(probe(args))


if __name__ == "__main__":
    raise SystemExit(main())
