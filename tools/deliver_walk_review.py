"""Copy verified continuous walk videos into one PC review folder.

This prepares delivery records only. Opening Explorer and confirming its window
are separate steps; this script never grants playback confirmation or approval.
"""
from __future__ import annotations
import argparse
from datetime import datetime, timezone
import json
from pathlib import Path
import shutil
from archive_walk_revision import digest, read, write

def main() -> None:
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("folder", type=Path)
    p.add_argument("--repo", type=Path, required=True)
    p.add_argument("--explorer-verified", action="store_true")
    args = p.parse_args()
    destination = args.folder / "review-videos"
    destination.mkdir(exist_ok=True)
    files = []
    hand_detail = False
    for profile in ("grounded", "responsive"):
        media = read(args.folder / profile / "media.json")
        for mode in ("clean", "diagnostic"):
            video = media["videos"][mode]
            source = Path(video["path"])
            if video["decoded_frames"] != 2880 or video["render"]["errors"] or digest(source) != video["sha256"]:
                raise ValueError(f"Unverified review video: {profile}/{mode}")
            target = destination / source.name
            if not target.exists():
                shutil.copy2(source, target)
            if digest(target) != video["sha256"]:
                raise ValueError(f"Review copy differs: {target}")
            files.append({"profile": profile, "mode": mode, "path": str(target),
                          "sha256": video["sha256"], "bytes": target.stat().st_size})
        detail_path = args.folder / profile / "hand-detail-media.json"
        if detail_path.exists():
            detail = read(detail_path)
            source = Path(detail["path"])
            if (detail["decoded_frames"] != 2880 or abs(detail["decoded_duration_s"] - 48) > 0.017
                    or detail["source_sha256"] != media["videos"]["clean"]["sha256"]
                    or digest(source) != detail["sha256"]):
                raise ValueError(f"Unverified hand-detail video: {profile}")
            target = destination / source.name
            if not target.exists():
                shutil.copy2(source, target)
            if digest(target) != detail["sha256"]:
                raise ValueError(f"Review copy differs: {target}")
            files.append({"profile": profile, "mode": "hand-detail", "path": str(target),
                          "sha256": detail["sha256"], "bytes": target.stat().st_size})
            hand_detail = True
    (destination / "START-HERE.txt").write_text(
        ("Start with grounded hand-detail, then responsive hand-detail; then the clean whole-body comparisons.\n"
         "Hand-detail videos enlarge fixed regions of the same continuous recorded playback.\n" if hand_detail
         else "Start with grounded clean, then responsive clean.\n") +
        "LEFT: previous same-profile walk. RIGHT: new candidate.\n"
        "Each rig: six seconds front, then six seconds side.\n"
        "00:00-00:12 Dummy; 00:12-00:24 X Bot; 00:24-00:36 Short; 00:36-00:48 Tall Z-up.\n" +
        ("Review elbow/wrist follow-through, forearm turn, relaxed hands and fingers, then overall coordination.\n"
         if hand_detail else "Review head bob/nod, torso stiffness, coordination and overall walking.\n") +
        "Diagnostic markers: ankle contacts, hip projection (not COM), root travel.\n"
        "Candidates await human approval; existing defaults remain unchanged.\n", encoding="utf-8")
    delivery = {"method": "PC File Explorer, user views remotely", "files": files,
                "playback_confirmed_by_user": False,
                "explorer_window_verified": args.explorer_verified,
                "explorer_location": destination.as_uri(),
                "updated_utc": datetime.now(timezone.utc).isoformat()}
    write(args.folder / "pc-review-delivery.json", delivery)
    state_path = args.repo / "docs/character-quality-review.json"
    state = read(state_path)
    state["candidate_delivery"] = delivery
    focus = "hand/forearm/wrist" if hand_detail else "head/torso"
    state["next_action"] = (f"Wait for human {state['revision']} {focus} video feedback after PC Explorer was opened. "
                            "Ask about both candidates/all four rigs and stop. No profile/default promotion or next motion."
                            if args.explorer_verified else "Open PC Explorer with the new clean comparison videos; ask for feedback and stop.")
    state["updated_utc"] = delivery["updated_utc"]
    write(state_path, state)
    print(json.dumps({"folder": str(destination), "verified_copies": len(files),
                      "explorer_verified": args.explorer_verified}))

if __name__ == "__main__": main()
