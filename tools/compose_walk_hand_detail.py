"""Enlarge fixed hand regions from an already verified continuous comparison.

Preserves timing, frame order and the recorded engine playback. This is a crop,
not a different animation or camera capture. No frame interpolation is used.
"""
from __future__ import annotations
import argparse
from pathlib import Path
import re
import subprocess
from archive_walk_revision import digest, read, write

FILTER = (
    "[0:v]split=3[top][left][right];"
    "[top]crop=1920:124:0:0[title];"
    "[left]crop=480:400:240:360,scale=960:800[l];"
    "[right]crop=480:400:1200:360,scale=960:800[r];"
    "[l][r]hstack=inputs=2[detail];"
    "[title][detail]vstack=inputs=2,pad=1920:1080:0:0:color=0x09121b,"
    "drawtext=fontfile='C\\:/Windows/Fonts/arial.ttf':"
    "text='ENLARGED HAND DETAIL | fixed crop of the same continuous playback':"
    "fontcolor=white:fontsize=30:x=24:y=970[out]"
)

def main() -> None:
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("folder", type=Path)
    p.add_argument("--ffmpeg", type=Path, required=True)
    args = p.parse_args()
    source = read(args.folder / "media.json")["videos"]["clean"]
    source_path = Path(source["path"])
    if (source["decoded_frames"] != 2880 or source["render"]["errors"]
            or digest(source_path) != source["sha256"]):
        raise ValueError("The original continuous clean comparison must be verified")
    target = args.folder / (source_path.stem.removesuffix("-clean") + "-hand-detail.mp4")
    command = [str(args.ffmpeg), "-hide_banner", "-loglevel", "error", "-y",
        "-i", str(source_path), "-filter_complex", FILTER, "-map", "[out]",
        "-frames:v", "2880", "-an", "-c:v", "libx264", "-threads", "2",
        "-filter_complex_threads", "2", "-preset", "medium", "-crf", "18",
        "-pix_fmt", "yuv420p", "-movflags", "+faststart", str(target)]
    subprocess.run(command, check=True)
    probe = subprocess.run([str(args.ffmpeg), "-hide_banner", "-nostats", "-i", str(target),
        "-map", "0:v:0", "-an", "-f", "null", "-", "-progress", "pipe:1"],
        check=True, capture_output=True, text=True)
    counts = re.findall(r"^frame=(\d+)$", probe.stdout, re.M)
    times = re.findall(r"^out_time_us=(\d+)$", probe.stdout, re.M)
    metadata = [s.strip() for s in probe.stderr.splitlines() if "Video:" in s or "Duration:" in s]
    if (not counts or int(counts[-1]) != 2880 or not times or abs(int(times[-1]) - 48_000_000) > 17_000
            or not any("h264" in s and "1920x1080" in s and "60 fps" in s for s in metadata)):
        raise ValueError("Hand-detail decode count, duration or format mismatch")
    write(args.folder / "hand-detail-media.json", {
        "path": str(target), "sha256": digest(target), "bytes": target.stat().st_size,
        "source_path": str(source_path), "source_sha256": source["sha256"],
        "decoded_frames": int(counts[-1]), "decoded_duration_s": int(times[-1]) / 1_000_000,
        "metadata": metadata, "encode_command": command,
        "description": "Fixed enlarged crops from the verified clean comparison; same continuous playback and timing."})
    print(f"Verified hand detail: {target}, 2880 decoded frames / 48 seconds", flush=True)

if __name__ == "__main__": main()
