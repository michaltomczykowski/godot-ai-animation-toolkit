"""Assemble numbered Godot Movie Maker frames for local visual review."""

from __future__ import annotations

import argparse
from pathlib import Path

from PIL import Image, ImageDraw


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("frames", type=Path)
    parser.add_argument("output", type=Path)
    parser.add_argument("--indices", type=int, nargs="+", default=[0, 10, 20, 30, 40, 50])
    parser.add_argument("--columns", type=int, default=3)
    args = parser.parse_args()
    images = [Image.open(args.frames / f"frame{index:08d}.png").convert("RGB")
              for index in args.indices]
    thumb_width = images[0].width // 2
    thumb_height = images[0].height // 2
    label_height = 28
    rows = (len(images) + args.columns - 1) // args.columns
    sheet = Image.new("RGB", (thumb_width * args.columns,
                              (thumb_height + label_height) * rows), "#17191d")
    draw = ImageDraw.Draw(sheet)
    for slot, (index, frame) in enumerate(zip(args.indices, images)):
        x = slot % args.columns * thumb_width
        y = slot // args.columns * (thumb_height + label_height)
        sheet.paste(frame.resize((thumb_width, thumb_height)), (x, y))
        draw.text((x + 8, y + thumb_height + 5), f"frame {index:02d}", fill="white")
    args.output.parent.mkdir(parents=True, exist_ok=True)
    sheet.save(args.output)
    print(args.output)


if __name__ == "__main__":
    main()
