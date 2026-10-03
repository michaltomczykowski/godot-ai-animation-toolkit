"""Probe 3D inspection, playback audit and preview through live Godot AI."""

from __future__ import annotations

import argparse
import asyncio
import json
import sys
from pathlib import Path

from fastmcp import Client
from fastmcp.client.transports import StdioTransport

from mcp_presets_audit import call


SCENE = "res://repair_motion_fixture.tscn"
PLAYER = "/MotionWalk/WalkAnim"
SKELETON = "/MotionWalk/Dummy/Skeleton3D"
CLIP = "repair_probe_walk"


async def run(args: argparse.Namespace) -> int:
    transport = StdioTransport(sys.executable, ["-m", "godot_ai", "attach",
        "--port", str(args.port), "--ws-port", str(args.ws_port)],
        cwd=str(args.core_root), keep_alive=False)
    async with Client(transport) as client:
        await client.call_tool("session_activate", {"session_id": args.session_hint})
        opened = await call(client, "scene_open", {"path": SCENE,
            "force_reload": True})
        base = {"player_path": PLAYER, "skeleton_path": SKELETON,
                "animation_name": CLIP}
        before = await call(client, "custom_animation_inspect", {
            "op": "describe", "player_path": PLAYER, "animation_name": CLIP})
        profile = await call(client, "custom_animation_inspect", {
            "op": "rig_profile", "skeleton_path": SKELETON, "save": False})
        sample = await call(client, "custom_animation_inspect", {
            "op": "sample", **base, "samples": 8,
            "bones": ["B-foot.L", "B-foot.R"]})
        audit = await call(client, "custom_animation_inspect", {
            "op": "motion_audit", **base, "samples": 120})
        preview = await call(client, "custom_animation_inspect", {
            "op": "preview", **base, "times": [0.0, 0.25, 0.5, 0.75],
            "output_dir": "res://animation_toolkit/previews/repair_inspect",
            "basename": "walk", "overwrite": True})
        typed_errors = {}
        for op in ("rig_profile", "sample", "motion_audit", "preview"):
            typed_errors[op] = await call(client, "custom_animation_inspect", {
                "op": op, **base, "skeleton_path": "/MotionWalk/Missing"})
        after = await call(client, "custom_animation_inspect", {
            "op": "describe", "player_path": PLAYER, "animation_name": CLIP})
    failures = []
    for name, result in (("open", opened), ("rig_profile", profile),
                         ("sample", sample), ("motion_audit", audit)):
        if result.get("error"):
            failures.append(f"{name}: {result['error']}")
    if args.expect_headless_preview:
        error = str(preview.get("error", ""))
        if not error.startswith("INVALID_PARAMS:") or "headless" not in error:
            failures.append("preview: headless editor did not return typed rendering error")
    elif preview.get("error"):
        failures.append(f"preview: {preview['error']}")
    for op, result in typed_errors.items():
        if not str(result.get("error", "")).split(":", 1)[0].isupper():
            failures.append(f"{op}: invalid skeleton did not return a typed error")
    if before != after:
        failures.append("3D inspection changed the source clip")
    if profile.get("bone_count") != 56 or not all(
            profile.get("roles", {}).get(name) for name in
            ("hips", "foot_l", "foot_r", "thigh_l", "thigh_r")):
        failures.append("rig_profile: missing expected 56-bone dummy roles")
    if profile.get("saved"):
        failures.append("rig_profile: save=false wrote a profile")
    if sample.get("sample_count") != 8 or sample.get("missing_bones"):
        failures.append("sample: missing the requested eight paired-foot samples")
    if audit.get("passed") is not True or audit.get("failed_checks") != 0:
        failures.append("motion_audit: saved walk did not pass contact grading")
    paths = preview.get("paths", [])
    if args.expect_headless_preview:
        if paths:
            failures.append("preview: headless error also claimed PNG output")
    else:
        if len(paths) != 4:
            failures.append("preview: expected four saved PNGs")
        for path in paths:
            image = args.project_root / path.removeprefix("res://")
            if not image.is_file() or image.stat().st_size < 1000:
                failures.append(f"preview: missing or empty PNG {path}")
    summary = {"scene": SCENE, "profile": profile, "sample": sample,
               "audit": {key: audit.get(key) for key in
                         ("passed", "failed_checks", "body_travel", "feet")},
               "preview": preview, "typed_errors": typed_errors,
               "failures": failures}
    print("MCP_INSPECT_3D=" + json.dumps(summary, sort_keys=True))
    return 1 if failures else 0


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--core-root", type=Path, required=True)
    parser.add_argument("--project-root", type=Path,
                        default=Path.cwd() / "test_project")
    parser.add_argument("--session-hint", required=True)
    parser.add_argument("--port", type=int, required=True)
    parser.add_argument("--ws-port", type=int, required=True)
    parser.add_argument("--expect-headless-preview", action="store_true",
                        help="require typed rendering error instead of PNGs")
    return asyncio.run(run(parser.parse_args()))


if __name__ == "__main__":
    raise SystemExit(main())
