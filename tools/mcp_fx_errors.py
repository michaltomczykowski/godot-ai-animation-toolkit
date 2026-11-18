"""Check typed failure responses for every FX operation through Godot AI."""

from __future__ import annotations

import argparse
import asyncio
import json
import sys
from pathlib import Path

from fastmcp import Client
from fastmcp.client.transports import StdioTransport

from mcp_fx_audit import CASES
from mcp_presets_audit import call


async def run(args: argparse.Namespace) -> int:
    transport = StdioTransport(sys.executable, ["-m", "godot_ai", "attach",
        "--port", str(args.port), "--ws-port", str(args.ws_port)],
        cwd=str(args.core_root), keep_alive=False)
    rows = []
    async with Client(transport) as client:
        await client.call_tool("session_activate", {"session_id": args.session_hint})
        for op, extras in CASES.items():
            if op == "sprite_frames_stopped":
                continue
            params = {"op": op, "player_path": "/DefinitelyMissingPlayer",
                "animation_name": "error_probe", **extras}
            if op == "sprite_frames":
                params["sprite_path"] = "/DefinitelyMissingSprite"
            result = await call(client, "custom_animation_fx", params)
            rows.append({"op": op, "result": result})
    failures = [row["op"] for row in rows if not any(
        row["result"].get("error", "").startswith(prefix) for prefix in (
            "NODE_NOT_FOUND:", "INVALID_PARAMS:", "MISSING_REQUIRED_PARAM:",
            "WRONG_TYPE:", "VALUE_OUT_OF_RANGE:"))]
    print("MCP_FX_ERRORS=" + json.dumps({"operations": rows,
        "failures": failures}, sort_keys=True))
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
