"""Replace a review receipt atomically, preserving its previous complete version."""
from __future__ import annotations
import json
import os
from pathlib import Path
from uuid import uuid4

def write_json(path: Path, value) -> None:
    temporary = path.with_name(path.name + '.' + uuid4().hex + '.tmp')
    data = (json.dumps(value, indent=2, ensure_ascii=False) + '\n').encode('utf-8')
    with temporary.open('wb') as stream:
        stream.write(data)
        stream.flush()
        os.fsync(stream.fileno())
    os.replace(temporary, path)
