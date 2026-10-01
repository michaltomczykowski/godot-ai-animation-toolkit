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
        if names:
            try:
                await client.call_tool(
                    "custom_animation_inspect", {"op": "__mcp_probe_unknown__"},
                )
                result["invalid_error"] = ""
            except ToolError as exc:
                result["invalid_error"] = str(exc)
            try:
                await client.call_tool(
                    "custom_manage", {"op": "invoke", "params": {
                        "tool_name": "animation_sequence",
                        "params": {"op": "__mcp_probe_unknown__"},
                    }},
                )
                result["sequence_invalid_error"] = ""
            except ToolError as exc:
                result["sequence_invalid_error"] = str(exc)
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
            or not str(result.get("invalid_error", "")).startswith("VALUE_OUT_OF_RANGE") \
            or not str(result.get("sequence_invalid_error", "")).startswith("VALUE_OUT_OF_RANGE") \
            or (args.player_path and not result.get("inspect_has_data")) else 0


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--core-root", type=Path, required=True)
    parser.add_argument("--port", type=int, required=True)
    parser.add_argument("--ws-port", type=int, required=True)
    parser.add_argument("--player-path", default="")
    parser.add_argument("--activate", default="")
    parser.add_argument("--show-schemas", action="store_true")
    parser.add_argument("--reload", action="store_true")
    args = parser.parse_args()
    if not args.core_root.is_dir():
        parser.error("--core-root must name the Godot AI source checkout")
    return asyncio.run(probe(args))


if __name__ == "__main__":
    raise SystemExit(main())
