"""Observe Godot AI tools/list_changed during a live custom-tool dock toggle."""

from __future__ import annotations

import argparse
import asyncio
import json
from functools import partial
from pathlib import Path
import sys

from fastmcp import Client
from fastmcp.client.messages import MessageHandler
from fastmcp.client.transports import StdioTransport
from fastmcp.client.transports import StreamableHttpTransport
from godot_ai.attach.ensure import BackendEnsurer
from godot_ai.attach.proxy import _http_client_factory


class ToolWatch(MessageHandler):
    def __init__(self) -> None:
        self.events: asyncio.Queue[None] = asyncio.Queue()

    async def on_tool_list_changed(self, message) -> None:
        self.events.put_nowait(None)


async def run(args: argparse.Namespace) -> int:
    handler = ToolWatch()
    if args.direct_http:
        ensurer = BackendEnsurer(args.port, args.ws_port)
        transport = StreamableHttpTransport(ensurer.mcp_url,
            httpx_client_factory=partial(_http_client_factory, ensurer.http_capability))
    else:
        transport = StdioTransport(sys.executable, ["-m", "godot_ai", "attach",
            "--port", str(args.port), "--ws-port", str(args.ws_port)],
            cwd=str(args.core_root), keep_alive=False)
    async with Client(transport, message_handler=handler) as client:
        await client.call_tool("session_activate", {"session_id": args.session_hint})
        names = {tool.name for tool in await client.list_tools()}
        print("TOOL_WATCH_READY=" + json.dumps({"visible": "custom_animation_edit" in names}), flush=True)
        for index in range(2):
            try:
                await asyncio.wait_for(handler.events.get(), 40.0)
            except TimeoutError:
                print("TOOL_WATCH_TIMEOUT=" + str(index), flush=True)
                return 1
            names = {tool.name for tool in await client.list_tools()}
            print("TOOL_WATCH_EVENT=" + json.dumps({"index": index + 1,
                "visible": "custom_animation_edit" in names}), flush=True)
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--core-root", type=Path, required=True)
    parser.add_argument("--session-hint", required=True)
    parser.add_argument("--port", type=int, required=True)
    parser.add_argument("--ws-port", type=int, required=True)
    parser.add_argument("--direct-http", action="store_true")
    return asyncio.run(run(parser.parse_args()))


if __name__ == "__main__":
    raise SystemExit(main())
