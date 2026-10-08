"""Encode and decode-check a continuous native four-rig video review pack."""
from __future__ import annotations
import argparse
import hashlib
import json
from pathlib import Path
import re
import subprocess
from PIL import Image

def digest(path: Path) -> str:
    with path.open("rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest()

def compose(folder: Path, mode: str, ffmpeg: Path) -> dict:
    frames_dir = folder / f"{mode}_frames"
    render = json.loads((frames_dir / "render.json").read_text(encoding="utf-8"))
    comparison = render.get("comparison", False)
    frame_total = 2880 if comparison else 1440
    if render["errors"] or render["frames"] != frame_total or render["fps"] != 60 or render["size"] != [1920, 1080]:
        raise ValueError(f"Incomplete or failed native capture: {mode}")
    required = [rig for rig in ("dummy", "xbot", "short", "zup_tall") for _ in range(2 if comparison else 1)]
    if [r["id"] for r in render["cases"]] != required or any(r["frames"] != 360 for r in render["cases"]):
        raise ValueError("All four rigs require six seconds of continuous playback")
    if comparison and [r["angle"] for r in render["cases"]] != ["FRONT", "SIDE"] * 4:
        raise ValueError("Comparison requires front and side playback on every rig")
    frames = sorted(frames_dir.glob("[0-9]*.png"))
    if len(frames) != frame_total or [p.name for p in frames] != [f"{i:06d}.png" for i in range(frame_total)]:
        raise ValueError("Missing, duplicated or out-of-order capture frames")
    for frame in frames:
        with Image.open(frame) as img:
            if img.size != (1920, 1080): raise ValueError("Incorrect native frame size")
    revision = render["revision"]
    video = folder / f"{revision}-{mode}.mp4"
    command = [str(ffmpeg), "-hide_banner", "-loglevel", "error", "-y", "-framerate", "60",
               "-i", str(frames_dir / "%06d.png"), "-frames:v", str(frame_total), "-an",
               "-c:v", "libx264", "-threads", "2", "-preset", "medium", "-crf", "18", "-pix_fmt", "yuv420p",
               "-movflags", "+faststart", str(video)]
    subprocess.run(command, check=True)
    # Independently decode the produced MP4, not just the encoder's return code.
    probe = subprocess.run([str(ffmpeg), "-hide_banner", "-nostats", "-i", str(video),
                            "-map", "0:v:0", "-an", "-f", "null", "-", "-progress", "pipe:1"],
                           check=True, capture_output=True, text=True)
    metadata = [line.strip() for line in probe.stderr.splitlines() if "Video:" in line or "Duration:" in line]
    frame_counts = re.findall(r"^frame=(\d+)$", probe.stdout, re.M)
    times = re.findall(r"^out_time_us=(\d+)$", probe.stdout, re.M)
    if not frame_counts or int(frame_counts[-1]) != frame_total or not times or abs(int(times[-1]) - frame_total / 60 * 1_000_000) > 17_000:
        raise ValueError("Decoded video count/duration mismatch")
    if not any("h264" in line and "1920x1080" in line and "60 fps" in line for line in metadata):
        raise ValueError("MP4 is not 1080p60 H.264")
    samples = []
    for index, row in enumerate(render["cases"]):
        for phase_index, phase in enumerate((30, 150)):
            path = frames[index * 360 + phase]
            with Image.open(path) as img:
                img.load()
            # The contact sheet is deliberately supplemental; preserve native QA
            # frames separately so text and fine contact detail remain readable.
            samples.append({"frame": path.name, "sha256": digest(path)})
    # A readable 2x2 overview: one native front+side frame per rig.
    sheet = Image.new("RGB", (1920, 1080), "#09121b")
    for i in range(4):
        with Image.open(frames[i * (720 if comparison else 360) + 30]) as img:
            sheet.paste(img.resize((960, 540)), ((i % 2) * 960, (i // 2) * 540))
    contact_sheet = folder / f"{revision}-{mode}-overview.png"
    sheet.save(contact_sheet)
    return {"mode": mode, "path": str(video), "sha256": digest(video), "bytes": video.stat().st_size,
            "decoded_frames": int(frame_counts[-1]), "decoded_duration_s": int(times[-1]) / 1_000_000,
            "metadata": metadata, "encode_command": command, "render": render,
            "contact_sheet": str(contact_sheet), "qa_samples": samples}

def main() -> None:
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("folder", type=Path)
    p.add_argument("--ffmpeg", type=Path, required=True)
    p.add_argument("--mode", choices=("clean", "diagnostic", "both"), default="both")
    args = p.parse_args()
    report_path = args.folder / "media.json"
    report = json.loads(report_path.read_text()) if report_path.exists() else {"videos": {}}
    for mode in (("clean", "diagnostic") if args.mode == "both" else (args.mode,)):
        report["videos"][mode] = compose(args.folder, mode, args.ffmpeg)
        report_path.write_text(json.dumps(report, indent=2), encoding="utf-8")
        video = report["videos"][mode]
        print(f"Verified {mode}: 1920x1080 H.264 60 FPS, {video['decoded_frames']} decoded frames / {video['decoded_duration_s']} seconds", flush=True)
if __name__ == "__main__": main()
