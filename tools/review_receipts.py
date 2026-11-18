"""Replace a review receipt atomically, preserving its previous complete version."""
from __future__ import annotations
import json
import os
import time
from pathlib import Path
from uuid import uuid4

def write_json(path: Path, value) -> None:
    temporary = path.with_name(path.name + '.' + uuid4().hex + '.tmp')
    data = (json.dumps(value, indent=2, ensure_ascii=False) + '\n').encode('utf-8')
    with temporary.open('wb') as stream:
        stream.write(data)
        stream.flush()
        os.fsync(stream.fileno())
    # Windows readers (including progress viewers and scanners) can briefly
    # deny delete sharing. Retry only this same completed rename, never the
    # operation whose result the receipt records. Keep both old and staged
    # complete files if a persistent failure needs investigation.
    for attempt in range(8):
        try:
            os.replace(temporary, path)
            return
        except PermissionError as error:
            if getattr(error, 'winerror', None) not in (5, 32) or attempt == 7:
                raise
            time.sleep(min(0.025 * 2 ** attempt, 0.2))
