"""Verify ordinary saved run routes and all families before/after core reload."""
from __future__ import annotations
import argparse
import asyncio
import json
from pathlib import Path
from mcp_motion_remaining_cycles import inspect
from mcp_presets_audit import call
from mcp_probe import EXPECTED_CATALOG, EXPECTED_PROMOTED
from mcp_rig_modifier_ui_history import connected_editor


async def run(args: argparse.Namespace) -> int:
    path = args.output / "core-reload.json"
    if path.exists():
        raise FileExistsError("Preserve prior reload receipt before a new attempt")
    report = {"phases": [], "passed": False}
    def save() -> None:
        path.write_text(json.dumps(report, indent=2), encoding="utf-8")
    old_session = ""
    for phase in ("before_reload", "after_reload"):
        async with connected_editor(args, old_session) as (client, connection):
            catalog = await call(client, "custom_manage", {"op": "list"})
            names = {x["name"] for x in catalog.get("tools", [])}
            promoted = {x.name for x in await client.list_tools()}
            rows = []
            section = {"phase": phase, "connection": connection,
                       "catalog": sorted(names & EXPECTED_CATALOG),
                       "promoted": sorted(promoted & EXPECTED_PROMOTED), "rows": rows}
            report["phases"].append(section)
            save()
            if EXPECTED_CATALOG - names or EXPECTED_PROMOTED - promoted:
                raise RuntimeError("A toolkit family disappeared from the public route")
            for style in ("responsive", "grounded", "relaxed", "heavy", "sneaky"):
                route = json.loads((args.output / style / "route.json").read_text(encoding="utf-8"))
                for row in route["cases"]:
                    opened = await call(client, "scene_open", {"path": row["scene"], "force_reload": True})
                    params = {**row["params"], "overwrite": True, "dry_run": True}
                    before = await inspect(client, params["animation_name"], params["player_path"])
                    dry = await call(client, "custom_manage", {"op": "invoke", "params": {
                        "tool_name": "animation_motion", "params": params}})
                    after = await inspect(client, params["animation_name"], params["player_path"])
                    passed = (not any(x.get("error") for x in (opened, before, dry, after))
                              and dry.get("dry_run") is True and bool(dry.get("roles"))
                              and before == after == row["persisted"])
                    rows.append({"style": style, "id": row["id"], "params": params,
                                 "open": opened, "before": before, "dry": dry,
                                 "after": after, "passed": passed})
                    save()
            print(f"{phase}: {sum(x['passed'] for x in rows)}/20 run routes, 10 families", flush=True)
            if phase == "before_reload":
                old_session = connection["session_id"]
                report["reload"] = await call(client, "editor_reload_plugin", {})
                save()
    report["passed"] = (not report["reload"].get("error") and len(report["phases"]) == 2
                        and all(len(x["rows"]) == 20 and all(y["passed"] for y in x["rows"])
                                for x in report["phases"]))
    save()
    return int(not report["passed"])


if __name__ == "__main__":
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--core-root", type=Path, required=True)
    p.add_argument("--project-root", type=Path, required=True)
    p.add_argument("--output", type=Path, required=True)
    p.add_argument("--port", type=int, default=8000)
    p.add_argument("--ws-port", type=int, default=9500)
    raise SystemExit(asyncio.run(run(p.parse_args())))
