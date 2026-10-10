"""Audit read-only inspection operations through live Godot AI MCP."""

from __future__ import annotations

import argparse
import asyncio
import json
import sys
from pathlib import Path

from fastmcp import Client
from fastmcp.client.transports import StdioTransport

from mcp_presets_audit import call


PLAYER = "/RepairGraphFixture/AnimationPlayer"
SCENE = "res://repair_edit_fixture.tscn"
CASES = {
    "describe": {"player_path": PLAYER, "animation_name": "walk"},
    "timeline": {"player_path": PLAYER, "animation_name": "walk"},
    "audit": {"player_path": PLAYER},
    "compare": {"player_path": PLAYER, "animation_name": "walk",
                "other_animation_name": "run"},
    "stats": {"player_path": PLAYER},
    "motion_report": {"player_path": PLAYER, "animation_name": "walk"},
    "dry_run": {"tool": "animation_edit", "forward_op": "retime",
                "player_path": PLAYER, "animation_name": "walk", "factor": 0.5},
    "help": {"tool": "animation_edit"},
}
ERROR_CASES = {
    "describe": {"player_path": "/RepairGraphFixture/Missing", "animation_name": "walk"},
    "timeline": {"player_path": PLAYER, "animation_name": "missing"},
    "audit": {"player_path": "/RepairGraphFixture/Missing"},
    "compare": {"player_path": PLAYER, "animation_name": "walk",
                "other_animation_name": "missing"},
    "stats": {"player_path": "/RepairGraphFixture/Missing"},
    "motion_report": {"player_path": PLAYER, "animation_name": "missing"},
    "dry_run": {"tool": "missing_family", "forward_op": "retime",
                "player_path": PLAYER, "animation_name": "walk"},
    "help": {"tool": "missing_family"},
}


async def run(args: argparse.Namespace) -> int:
    transport = StdioTransport(sys.executable, ["-m", "godot_ai", "attach",
        "--port", str(args.port), "--ws-port", str(args.ws_port)],
        cwd=str(args.core_root), keep_alive=False)
    rows = []
    async with Client(transport) as client:
        await client.call_tool("session_activate", {"session_id": args.session_hint})
        opened = await call(client, "scene_open", {"path": SCENE,
            "force_reload": True})
        if opened.get("error"):
            print("MCP_INSPECT_AUDIT=" + json.dumps({"open": opened,
                "failures": ["scene open failed"]}))
            return 1
        baseline = await call(client, "custom_animation_inspect", {
            "op": "timeline", "player_path": PLAYER, "animation_name": "walk"})
        for op, extras in CASES.items():
            result = await call(client, "custom_animation_inspect",
                                {"op": op, **extras})
            after = await call(client, "custom_animation_inspect", {
                "op": "timeline", "player_path": PLAYER,
                "animation_name": "walk"})
            bad = await call(client, "custom_animation_inspect", {
                "op": op, **ERROR_CASES[op]})
            rows.append({"op": op, "result": result, "typed_error": bad,
                         "source_intact": after == baseline})
    failures = [f"{row['op']}: {row['result'].get('error')}" for row in rows
                if row["result"].get("error")]
    failures += [f"{row['op']}: changed source clip" for row in rows
                 if not row["source_intact"]]
    failures += [f"{row['op']}: invalid call did not return a typed error"
                 for row in rows if not str(row["typed_error"].get("error", "")).split(":", 1)[0].isupper()]
    results = {row["op"]: row["result"] for row in rows}
    if results["describe"].get("clip_count") != 1 or results["describe"].get("clips", [{}])[0].get("key_count") != 2:
        failures.append("describe: expected the saved two-key walk clip")
    timeline = results["timeline"]
    if timeline.get("key_count") != 2 or timeline.get("tracks", [{}])[0].get("keys", [{}])[-1].get("value", {}).get("x") != 100.0:
        failures.append("timeline: expected walk position keys 0→100")
    if results["audit"].get("players_scanned") != 1 or results["audit"].get("clips_scanned") != 5:
        failures.append("audit: wrong player or clip count")
    compare = results["compare"]
    if compare.get("identical") is not False or not compare.get("changed_tracks"):
        failures.append("compare: walk and run should differ")
    if results["stats"].get("totals", {}).get("key_count") != 12:
        failures.append("stats: wrong saved key total")
    if results["motion_report"].get("worst_seam_gap", 0) < 99:
        failures.append("motion_report: missed the planted 100-unit loop seam")
    dry = results["dry_run"]
    if dry.get("dry_run") is not True or dry.get("length_before") != 1.0 or dry.get("length_after") != 0.5:
        failures.append("dry_run: missing predicted retime effect")
    helped = results["help"]
    if helped.get("tool_count") != 1 or len(helped.get("tools", [{}])[0].get("ops", [])) != 20:
        failures.append("help: expected all 20 registered edit operations")
    print("MCP_INSPECT_AUDIT=" + json.dumps({"scene": SCENE,
        "operations": rows, "failures": failures}, sort_keys=True))
    return 1 if failures else 0


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--core-root", type=Path, required=True)
    parser.add_argument("--session-hint", required=True)
    parser.add_argument("--port", type=int, required=True)
    parser.add_argument("--ws-port", type=int, required=True)
    return asyncio.run(run(parser.parse_args()))


if __name__ == "__main__":
    raise SystemExit(main())
