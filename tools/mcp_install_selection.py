"""Check installed-addon discovery and cached-call refusal while toggling a family."""
import argparse
import asyncio
import json
from pathlib import Path
import sys
import time
from fastmcp import Client
from fastmcp.client.transports import StdioTransport
from fastmcp.exceptions import ToolError

async def run(a):
    transport = StdioTransport(sys.executable, ['-m', 'godot_ai', 'attach', '--port', str(a.port), '--ws-port', str(a.ws_port)], cwd=str(a.core_root), keep_alive=False)
    async with Client(transport) as client:
        from mcp_probe import payload
        sessions = payload(await client.call_tool('session_manage', {'op': 'list'}))['sessions']
        assert len(sessions) == 1
        await client.call_tool('session_activate', {'session_id': sessions[0]['session_id']})
        name = 'custom_animation_inspect'
        assert name in {t.name for t in await client.list_tools()}
        request = a.project / 'clean-selection-request.json'
        try:
            for enabled in (False, True):
                request.write_text(json.dumps({'enabled': enabled}))
                deadline = time.monotonic() + 20
                while time.monotonic() < deadline:
                    present = name in {t.name for t in await client.list_tools()}
                    if present == enabled:
                        break
                    await asyncio.sleep(.3)
                else:
                    raise RuntimeError('Discovery did not reflect selection')
                if not enabled:
                    try:
                        await client.call_tool(name, {'op': 'help'})
                    except ToolError as exc:
                        assert 'CUSTOM_TOOL_DISABLED' in str(exc), str(exc)
                    else:
                        raise RuntimeError('Cached disabled promoted call succeeded')
                else:
                    await client.call_tool(name, {'op': 'help'})
            print('MCP_INSTALL_SELECTION_PASS=discovery,disabled-cached-call,reenable')
        finally:
            request.write_text(json.dumps({'enabled': True}))

if __name__ == '__main__':
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--core-root', type=Path, required=True)
    p.add_argument('--project', type=Path, required=True)
    p.add_argument('--port', type=int, default=8000)
    p.add_argument('--ws-port', type=int, default=9500)
    asyncio.run(run(p.parse_args()))
