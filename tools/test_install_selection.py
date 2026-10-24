"""Pure async regression for released attach cache/discovery ordering."""
import json
from pathlib import Path
import tempfile
from types import SimpleNamespace
import unittest

from fastmcp.exceptions import ToolError
from mcp_install_selection import check_selection


class FakeAttachClient:
    def __init__(self, project, disabled_result="typed"):
        self.project = project
        self.disabled_result = disabled_result
        self.enabled = True
        self.cached = False
        self.events = []

    async def list_tools(self):
        self.events.append(("tools_refresh", self.enabled))
        self.cached = self.enabled
        return [SimpleNamespace(name="custom_animation_inspect")] if self.enabled else []

    async def call_tool(self, name, arguments):
        if name == "custom_manage":
            self.enabled = json.loads((self.project / "clean-selection-request.json").read_text())["enabled"]
            self.events.append(("catalog", self.enabled))
            return SimpleNamespace(structured_content={"tools": [{"name": "animation_inspect"}] if self.enabled else []})
        self.events.append(("promoted_call", self.enabled, self.cached))
        if not self.enabled:
            if not self.cached or self.disabled_result == "unknown":
                raise ToolError("Unknown tool: 'custom_animation_inspect'")
            if self.disabled_result == "succeeds":
                return SimpleNamespace(structured_content={"unexpected": "effect"})
            raise ToolError("CUSTOM_TOOL_DISABLED: animation_inspect is disabled")
        return SimpleNamespace(structured_content={"help": "fixture"})


class SelectionOrderingTests(unittest.IsolatedAsyncioTestCase):
    async def test_cached_disabled_call_precedes_discovery_refresh(self):
        with tempfile.TemporaryDirectory() as directory:
            project = Path(directory)
            client = FakeAttachClient(project)
            await check_selection(client, project)
            cached = client.events.index(("promoted_call", False, True))
            refreshed = client.events.index(("tools_refresh", False))
            self.assertLess(cached, refreshed)
            self.assertIn(("promoted_call", True, True), client.events)
            self.assertTrue(json.loads((project / "clean-selection-request.json").read_text())["enabled"])

    async def test_unknown_tool_is_not_accepted_as_typed_refusal(self):
        with tempfile.TemporaryDirectory() as directory:
            project = Path(directory)
            client = FakeAttachClient(project, "unknown")
            with self.assertRaisesRegex(AssertionError, "Unknown tool"):
                await check_selection(client, project)
            self.assertNotIn(("tools_refresh", False), client.events)
            self.assertTrue(json.loads((project / "clean-selection-request.json").read_text())["enabled"])

    async def test_disabled_effectful_success_still_fails(self):
        with tempfile.TemporaryDirectory() as directory:
            project = Path(directory)
            with self.assertRaisesRegex(RuntimeError, "Cached disabled promoted call succeeded"):
                await check_selection(FakeAttachClient(project, "succeeds"), project)
            self.assertTrue(json.loads((project / "clean-selection-request.json").read_text())["enabled"])


if __name__ == "__main__":
    unittest.main()
