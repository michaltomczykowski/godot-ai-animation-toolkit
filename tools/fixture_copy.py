"""Copy a Godot scene fixture without duplicating its scene UID."""

from __future__ import annotations

from pathlib import Path
import re


SCENE_UID = re.compile(r' uid="uid://[^\"]+"')


def copy_scene(source: Path, target: Path) -> None:
    text = source.read_text(encoding="utf-8")
    first, separator, rest = text.partition("\n")
    if not first.startswith("[gd_scene "):
        raise ValueError(f"Not a text Godot scene: {source}")
    first = SCENE_UID.sub("", first)
    target.write_text(first + separator + rest, encoding="utf-8")
