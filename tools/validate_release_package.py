"""Validate addon ZIP bytes against one committed tree; emit manifest and checksum."""
from __future__ import annotations
import argparse
import hashlib
import io
import json
from pathlib import Path, PurePosixPath
import re
import stat
import subprocess
import zipfile

def git(repo: Path, *args: str) -> bytes:
    return subprocess.check_output(['git', '-C', str(repo), *args])

def read_blobs(repo: Path, blobs: list[str]) -> dict[str, bytes]:
    result = subprocess.run(['git', '-C', str(repo), 'cat-file', '--batch'], input=('\n'.join(blobs) + '\n').encode(), capture_output=True, check=True)
    stream = io.BytesIO(result.stdout)
    objects = {}
    for requested in blobs:
        sha, kind, size = stream.readline().decode().strip().split()
        if sha != requested or kind != 'blob':
            raise ValueError('Expected committed Git blob')
        objects[sha] = stream.read(int(size))
        if stream.read(1) != b'\n':
            raise ValueError('Malformed Git blob output')
    return objects

def validate(repo: Path, source: str, archive: Path, version: str | None = None) -> dict:
    sha = git(repo, 'rev-parse', '--verify', source + '^{commit}').decode().strip()
    expected = {}
    for row in git(repo, 'ls-tree', '-rz', sha, '--', 'addons/godot_ai_animation', 'LICENSE').split(b'\0'):
        if not row:
            continue
        meta, name = row.split(b'\t', 1)
        mode, kind, blob = meta.decode().split()
        name = name.decode()
        if kind != 'blob' or mode == '120000':
            raise ValueError('Package source contains a nonregular file: ' + name)
        path = PurePosixPath(name)
        excluded = {'tests', 'models', 'recovery', '.godot', '.git', '__pycache__'}
        if any(part.lower() in excluded for part in path.parts) or path.suffix.lower() in {'.mp4', '.avi', '.mov', '.fbx', '.glb', '.blend', '.pyc'}:
            raise ValueError('Excluded package entry: ' + name)
        expected[name] = blob
    objects = read_blobs(repo, list(expected.values()))
    expected = {name: objects[blob] for name, blob in expected.items()}
    if 'LICENSE' not in expected:
        raise ValueError('LICENSE missing')
    cfg = expected['addons/godot_ai_animation/plugin.cfg'].decode()
    versions = re.findall(r'^version="([0-9]+\.[0-9]+\.[0-9]+)"$', cfg, re.M)
    if len(versions) != 1 or (version and versions[0] != version):
        raise ValueError('Committed package version mismatch')
    actual = {}
    directories = {str(parent) + '/' for name in expected for parent in PurePosixPath(name).parents if str(parent) != '.'}
    seen_casefolded = set()
    with zipfile.ZipFile(archive) as z:
        if z.testzip() is not None:
            raise ValueError('ZIP CRC failure')
        for info in z.infolist():
            name = info.filename
            path = PurePosixPath(name)
            if path.is_absolute() or '..' in path.parts or '\\' in name or ':' in name or stat.S_ISLNK(info.external_attr >> 16):
                raise ValueError('Unsafe ZIP path: ' + name)
            if info.is_dir():
                if name not in directories:
                    raise ValueError('Unexpected ZIP directory: ' + name)
                continue
            if name.casefold() in seen_casefolded:
                raise ValueError('Duplicate ZIP entry: ' + name)
            seen_casefolded.add(name.casefold())
            actual[name] = z.read(info)
    if actual != expected:
        raise ValueError('ZIP entries or bytes differ from committed addon/LICENSE')
    return {'schema_version': 1, 'source': sha, 'version': versions[0],
            'zip_sha256': hashlib.sha256(archive.read_bytes()).hexdigest(),
            'entries': {n: hashlib.sha256(b).hexdigest() for n, b in sorted(actual.items())}}

def main() -> None:
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--repo', type=Path, default=Path('.'))
    p.add_argument('--source', required=True)
    p.add_argument('--zip', type=Path, required=True)
    p.add_argument('--version')
    a = p.parse_args()
    manifest = validate(a.repo, a.source, a.zip, a.version)
    a.zip.with_suffix(a.zip.suffix + '.manifest.json').write_text(json.dumps(manifest, indent=2) + '\n')
    a.zip.with_suffix(a.zip.suffix + '.sha256').write_text(f"{manifest['zip_sha256']}  {a.zip.name}\n")
    print(f"PACKAGE_PASS source={manifest['source']} version={manifest['version']} entries={len(manifest['entries'])}")

if __name__ == '__main__':
    main()
