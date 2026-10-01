"""Exercise all seven toolkit library operations through live Godot AI MCP."""

from __future__ import annotations

import argparse
import asyncio
from datetime import datetime, timezone
import json
from fixture_copy import copy_scene
import sys
from pathlib import Path

from fastmcp import Client
from fastmcp.client.transports import StdioTransport

from mcp_presets_audit import call


PLAYER = "/RepairGraphFixture/AnimationPlayer"


async def run(args: argparse.Namespace) -> int:
    run_id = datetime.now(timezone.utc).strftime("%Y%m%d_%H%M%S")
    folder = args.project_root / "repair_library_audit" / run_id
    folder.mkdir(parents=True, exist_ok=False)
    copy_scene(args.project_root / "repair_edit_fixture.tscn",
                    folder / "library.tscn")
    scene = f"res://repair_library_audit/{run_id}/library.tscn"
    library_path = f"res://animation_toolkit/repair_audit/{run_id}_library.json"
    spec_path = f"res://animation_toolkit/repair_audit/{run_id}_walk.json"
    disk_library = args.project_root / library_path.removeprefix("res://")
    disk_spec = args.project_root / spec_path.removeprefix("res://")
    transport = StdioTransport(sys.executable, ["-m", "godot_ai", "attach",
        "--port", str(args.port), "--ws-port", str(args.ws_port)],
        cwd=str(args.core_root), keep_alive=False)
    rows = {}
    async with Client(transport) as client:
        await client.call_tool("session_activate", {"session_id": args.session_hint})
        rows["open"] = await call(client, "scene_open", {"path": scene,
            "force_reload": True})

        template = {"op": "template_save", "name": "repair_drift",
            "tool": "animation_presets", "forward_op": "drift",
            "player_path": PLAYER, "target_path": "Character",
            "axis": "x", "distance": 60.0, "duration": 1.0,
            "loop_mode": "pingpong", "library_path": library_path}
        rows["template_save_dry"] = await call(client, "custom_animation_library",
                                               {**template, "dry_run": True})
        rows["template_file_after_dry"] = disk_library.exists()
        rows["template_save"] = await call(client, "custom_animation_library", template)
        rows["template_list"] = await call(client, "custom_animation_library",
            {"op": "template_list", "library_path": library_path})
        apply = {"op": "template_apply", "name": "repair_drift",
            "library_path": library_path, "target_path": "OtherCharacter",
            "animation_name": "templated_drift"}
        rows["template_apply_dry"] = await call(client, "custom_animation_library",
                                                 {**apply, "dry_run": True})
        rows["template_apply"] = await call(client, "custom_animation_library", apply)
        rows["template_clip"] = await call(client, "custom_animation_inspect",
            {"op": "describe", "player_path": PLAYER,
             "animation_name": "templated_drift"})
        rows["template_delete_dry"] = await call(client, "custom_animation_library",
            {"op": "template_delete", "name": "repair_drift",
             "library_path": library_path, "dry_run": True})
        rows["template_list_after_dry_delete"] = await call(client,
            "custom_animation_library", {"op": "template_list",
            "library_path": library_path})
        rows["template_delete"] = await call(client, "custom_animation_library",
            {"op": "template_delete", "name": "repair_drift",
             "library_path": library_path})
        rows["template_list_after_delete"] = await call(client,
            "custom_animation_library", {"op": "template_list",
            "library_path": library_path})

        export = {"op": "spec_export", "player_path": PLAYER,
            "animation_name": "walk", "path": spec_path}
        rows["spec_export_dry"] = await call(client, "custom_animation_library",
                                              {**export, "dry_run": True})
        rows["spec_file_after_dry"] = disk_spec.exists()
        rows["spec_export"] = await call(client, "custom_animation_library", export)
        rows["spec_import"] = await call(client, "custom_animation_library",
            {"op": "spec_import", "path": spec_path})
        spec_apply = {"op": "spec_apply", "path": spec_path,
            "player_path": PLAYER, "target_path": "OtherCharacter",
            "animation_name": "imported_walk"}
        rows["spec_apply_dry"] = await call(client, "custom_animation_library",
                                             {**spec_apply, "dry_run": True})
        rows["spec_apply"] = await call(client, "custom_animation_library",
            spec_apply)
        rows["spec_clip"] = await call(client, "custom_animation_inspect",
            {"op": "describe", "player_path": PLAYER,
             "animation_name": "imported_walk"})
        rows["save"] = await call(client, "scene_save", {})
        rows["reopen"] = await call(client, "scene_open", {"path": scene,
            "force_reload": True})
        rows["template_clip_reopened"] = await call(client,
            "custom_animation_inspect", {"op": "describe", "player_path": PLAYER,
            "animation_name": "templated_drift"})
        rows["spec_clip_reopened"] = await call(client,
            "custom_animation_inspect", {"op": "describe", "player_path": PLAYER,
            "animation_name": "imported_walk"})
        rows["typed_errors"] = {}
        invalid = {
            "template_save": {"name": "bad", "tool": "unknown",
                              "forward_op": "drift", "library_path": library_path},
            "template_apply": {"name": "missing", "library_path": library_path},
            "template_list": {"library_path": spec_path},
            "template_delete": {"name": "missing", "library_path": library_path},
            "spec_export": {"player_path": PLAYER, "animation_name": "missing",
                            "path": spec_path},
            "spec_import": {"path": f"res://animation_toolkit/repair_audit/{run_id}_missing.json"},
            "spec_apply": {"player_path": PLAYER,
                           "path": f"res://animation_toolkit/repair_audit/{run_id}_missing.json"},
        }
        for op, extras in invalid.items():
            rows["typed_errors"][op] = await call(client,
                "custom_animation_library", {"op": op, **extras})
    failures = [f"{name}: {result['error']}" for name, result in rows.items()
                if name != "typed_errors" and isinstance(result, dict) and result.get("error")]
    for op, result in rows["typed_errors"].items():
        if not str(result.get("error", "")).split(":", 1)[0].isupper():
            failures.append(f"{op}: invalid call did not return typed error")
    if rows["template_file_after_dry"] or rows["spec_file_after_dry"]:
        failures.append("dry run wrote a file")
    if not disk_library.is_file() or not disk_spec.is_file():
        failures.append("library or exported spec file absent")
    else:
        stored_library = json.loads(disk_library.read_text(encoding="utf-8"))
        stored_spec = json.loads(disk_spec.read_text(encoding="utf-8"))
        if stored_library.get("format") != "godot-ai-animation-library" or stored_library.get("templates") != {}:
            failures.append("deleted template remains in the library file")
        if stored_spec.get("format") != "godot-ai-animation-clip" or len(stored_spec.get("tracks", [])) != 1:
            failures.append("exported clip spec has an invalid shape")
    for name, count in (("template_list", 1),
                        ("template_list_after_dry_delete", 1),
                        ("template_list_after_delete", 0)):
        if rows[name].get("template_count") != count:
            failures.append(f"{name}: expected {count} templates")
    if rows["spec_import"].get("key_count") != 2:
        failures.append("spec_import: expected two source keys")
    for name in ("template_clip", "spec_clip", "template_clip_reopened",
                 "spec_clip_reopened"):
        clips = rows[name].get("clips", [])
        if len(clips) != 1 or clips[0].get("tracks", [{}])[0].get("path") != "OtherCharacter:position":
            failures.append(f"{name}: expected a resolved remapped clip")
    print("MCP_LIBRARY_AUDIT=" + json.dumps({"run_id": run_id,
        "scene": scene, "library_path": library_path, "spec_path": spec_path,
        "rows": rows, "failures": failures}, sort_keys=True))
    return 1 if failures else 0


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--core-root", type=Path, required=True)
    parser.add_argument("--project-root", type=Path, default=Path.cwd() / "test_project")
    parser.add_argument("--session-hint", required=True)
    parser.add_argument("--port", type=int, required=True)
    parser.add_argument("--ws-port", type=int, required=True)
    return asyncio.run(run(parser.parse_args()))


if __name__ == "__main__":
    raise SystemExit(main())
