"""Probe saved preset playback through Godot AI's core play and node-read tools."""

from __future__ import annotations

import argparse
import asyncio
import json
import sys
from pathlib import Path

from fastmcp import Client
from fastmcp.client.transports import StdioTransport

from mcp_presets_audit import call


TARGETS = {
    "pulse": ("Target3D", "scale"),
    "bounce": ("Target2D", "scale"),
    "orbit": ("Target3D", "position"),
    "sweep": ("Target2D", "rotation"),
    "drift": ("Target3D", "position"),
    # The authored tracks target quaternion/transform. Godot AI's node read
    # tool exposes editor-visible rotation/position, which reflect their play.
    "spin": ("Target3D", "rotation"),
    "float": ("Target3D", "position"),
    "stagger": ("Target2D", "modulate"),
}


async def run(args: argparse.Namespace) -> int:
    transport = StdioTransport(
        sys.executable,
        ["-m", "godot_ai", "attach", "--port", str(args.port),
         "--ws-port", str(args.ws_port)],
        cwd=str(args.core_root), keep_alive=False,
    )
    records = []
    failures = []
    async with Client(transport) as client:
        await client.call_tool("session_activate", {"session_id": args.session_hint})
        for op, (target, field) in TARGETS.items():
            if args.only and op not in args.only:
                continue
            path = f"res://repair_presets_audit/{args.run_id}/{op}.tscn"
            row = {"op": op, "scene": path}
            row["open"] = await call(client, "scene_open", {"path": path, "force_reload": True})
            node = "/RepairPresetsFixture/" + target
            row["before"] = await call(client, "node_get_properties", {
                "path": node, "fields": [field]})
            row["play"] = await call(client, "animation_manage", {
                "op": "play", "params": {
                    "player_path": "/RepairPresetsFixture/AnimationPlayer",
                    "animation_name": "audit_" + op,
                }})
            await asyncio.sleep(0.12 if op in ("bounce", "stagger") else 0.2)
            row["during"] = await call(client, "node_get_properties", {
                "path": node, "fields": [field]})
            row["stop"] = await call(client, "animation_manage", {
                "op": "stop", "params": {
                    "player_path": "/RepairPresetsFixture/AnimationPlayer",
                }})
            if row["play"].get("error") or row["stop"].get("error"):
                failures.append(f"{op}: play/stop error")
            before = row["before"].get("properties", [])
            during = row["during"].get("properties", [])
            if len(before) != 1 or len(during) != 1 \
                    or before[0].get("value") == during[0].get("value"):
                failures.append(f"{op}: played node property stayed inert or unreadable")
            records.append(row)
    print("MCP_PRESETS_PLAYBACK=" + json.dumps({
        "operations": records, "failures": failures,
    }, sort_keys=True))
    return 1 if failures else 0


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--core-root", type=Path, required=True)
    parser.add_argument("--session-hint", required=True)
    parser.add_argument("--port", type=int, required=True)
    parser.add_argument("--ws-port", type=int, required=True)
    parser.add_argument("--run-id", required=True)
    parser.add_argument("--only", nargs="*", default=[])
    return asyncio.run(run(parser.parse_args()))


if __name__ == "__main__":
    raise SystemExit(main())
