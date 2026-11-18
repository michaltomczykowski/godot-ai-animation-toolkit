"""Canonical Git dependency scope for operation trace production and validation."""
from pathlib import PurePosixPath
import subprocess


SCENE_FIXTURES = tuple(f'test_project/repair_{kind}_fixture.tscn'
                       for kind in ('graph', 'edit', 'fx', 'motion', 'rig'))
DUMMY_MODEL = 'test_project/models/human_dummy/HumanCharacterDummy_F.fbx'
BINARY_FIXTURES = frozenset((DUMMY_MODEL, 'test_project/tests/fixtures/sheet.png',
                            'test_project/tests/fixtures/cue.wav'))
SCOPES = ('addons/godot_ai_animation', 'tools', 'test_project/tests',
          'test_project/tools', *SCENE_FIXTURES, DUMMY_MODEL)
SOURCE_SUFFIXES = frozenset(('.gd', '.py', '.json', '.tscn', '.tres', '.cfg', '.godot'))


def source_blobs(repo, source):
    output = subprocess.check_output(
        ['git', 'ls-tree', '-rz', source, '--', *SCOPES], cwd=repo)
    blobs = {}
    for row in output.split(b'\0'):
        if not row:
            continue
        metadata, path = row.split(b'\t', 1)
        rel = path.decode('utf-8')
        if rel not in BINARY_FIXTURES and PurePosixPath(rel).suffix not in SOURCE_SUFFIXES:
            continue
        mode, kind, blob = metadata.decode('ascii').split()
        if kind != 'blob' or mode == '120000':
            raise ValueError('nonregular dependency ' + rel)
        blobs[rel] = blob
    return blobs
