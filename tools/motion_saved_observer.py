"""Source-bound file witnesses around existing saved motion public calls."""
import hashlib
import json
import os
import sys
from pathlib import Path
from operation_case_collector import _emit


def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def saved_witness(path, scene, request, save_response):
    context_path = os.environ.get('TOOLKIT_OPERATION_CONTEXT')
    if not str(Path(path).resolve().as_posix()).endswith('/'+scene.removeprefix('res://')):
        raise ValueError('Saved local path does not resolve declared scene')
    target = Path(str(path)+'.motion-witness.json')
    if target.exists():
        raise FileExistsError(str(target))
    witness = dict(scene=scene, scene_sha256=sha(path), request=request,
                   save_response=save_response, save_command=[sys.executable, *sys.argv],
                   context_sha256=sha(context_path) if context_path else None)
    witness['save_witness_id'] = _emit('operation_snapshot_assertions', dict(
        operation='animation_motion.'+request['op'], validator='motion_saved_file_v1',
        row=witness.copy(), route='public_godot_ai'))
    with target.open('x', encoding='utf-8') as stream:
        json.dump(witness, stream, sort_keys=True)
    return witness


def read_witness(path):
    return json.loads(Path(str(path)+'.motion-witness.json').read_text(encoding='utf-8'))


def audit_witness(witness, before, after, opened, params, response, navigation=None):
    row = dict(saved=witness, before_sha256=before, after_sha256=after,
               opened=opened, navigation=navigation, audit_request=params, audit_response=response,
               audit_command=[sys.executable, *sys.argv])
    _emit('operation_snapshot_assertions', dict(operation='animation_motion.'+witness['request']['op'],
        validator='motion_saved_audit_v1', row=row, route='public_godot_ai'))
    return row


async def open_saved(call, client, scene):
    """Core421 only reloads an already-current tab. No error/unknown retry."""
    first = await call(client, 'scene_open', {'path': scene, 'force_reload': True})
    if first.get('error') or first.get('path') != scene:
        raise ValueError('Saved scene navigation failed: '+str(first))
    if first.get('reloaded_from_disk') is True:
        return first, None
    if first.get('reloaded_from_disk') is not False:
        raise ValueError('Saved scene navigation has unknown reload state')
    loaded = await call(client, 'scene_open', {'path': scene, 'force_reload': True})
    if loaded.get('error') or loaded.get('path') != scene or loaded.get('reloaded_from_disk') is not True:
        raise ValueError('Current saved scene forced reload failed: '+str(loaded))
    return loaded, first
