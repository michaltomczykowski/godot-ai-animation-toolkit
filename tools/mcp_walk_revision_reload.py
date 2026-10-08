"""Check both saved walk candidate recipes through Godot AI before/after reload."""
from __future__ import annotations
import argparse
import asyncio
import json
from pathlib import Path
from mcp_motion_remaining_cycles import inspect
from mcp_presets_audit import call
from mcp_rig_modifier_ui_history import connected_editor

async def run(args: argparse.Namespace) -> int:
    record = args.output / "core-reload.json"
    report = {"phases": [], "passed": False}
    def save() -> None:
        record.write_text(json.dumps(report, indent=2), encoding="utf-8")
    for phase in ("before_reload", "after_reload"):
        async with connected_editor(args) as (client, connection):
            rows = []
            section = {"phase": phase, "connection": connection, "rows": rows}
            report["phases"].append(section)
            save()
            for profile in ("grounded", "responsive"):
                route = json.loads((args.output / profile / "route.json").read_text())
                for row in route["cases"]:
                    opened = await call(client, "scene_open", {"path": row["scene"], "force_reload": True})
                    params = {**row["params"], "overwrite": True, "dry_run": True}
                    before = await inspect(client, params["animation_name"], params["player_path"])
                    dry = await call(client, "custom_manage", {"op": "invoke", "params": {
                        "tool_name": "animation_motion", "params": params}})
                    after = await inspect(client, params["animation_name"], params["player_path"])
                    ok = not any(result.get("error") for result in (opened, dry, before, after))
                    ok = ok and dry.get("dry_run") is True and bool(dry.get("roles")) and before == after
                    rows.append({"profile": profile, "id": row["id"], "params": params,
                        "open": opened, "dry": dry, "before": before, "after": after, "passed": ok})
                    save()
            print(f"{phase}: {sum(row['passed'] for row in rows)}/8 candidate routes", flush=True)
            if phase == "before_reload":
                report["reload"] = await call(client, "editor_reload_plugin", {})
                save()
    report["passed"] = not report["reload"].get("error") and all(len(phase["rows"]) == 8 and all(row["passed"] for row in phase["rows"]) for phase in report["phases"])
    save()
    print(json.dumps({"passed": report["passed"], "record": str(record)}))
    return 0 if report["passed"] else 1

if __name__ == "__main__":
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--core-root", type=Path, required=True)
    p.add_argument("--project-root", type=Path, required=True)
    p.add_argument("--output", type=Path, required=True)
    p.add_argument("--port", type=int, default=18131)
    p.add_argument("--ws-port", type=int, default=18132)
    raise SystemExit(asyncio.run(run(p.parse_args())))
