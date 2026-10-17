"""Require four exact-source, released-core clean ZIP receipts and their logs."""
import argparse
import hashlib
import json
from pathlib import Path
import sys

def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--source', required=True)
    p.add_argument('--receipts', type=Path, required=True)
    p.add_argument('--package', type=Path, required=True)
    a = p.parse_args()
    package = json.loads(a.package.read_text())
    if package['source'] != a.source:
        raise ValueError('Package source mismatch')
    expected = {(os, core) for os in ('windows', 'linux') for core in ('4.2.1', '4.3.0')}
    cores = {'4.2.1': 'bfc264200584ea5823f18356acb164781f57796d', '4.3.0': 'b82b5c519b1b17228f70d8effce1626f391bd1dd'}
    seen = set()
    for path in a.receipts.rglob('clean-install-receipt.json'):
        r = json.loads(path.read_text())
        platform = {'win32': 'windows', 'linux': 'linux'}.get(r['platform'])
        cell = (platform, r['core'])
        if cell not in expected or cell in seen:
            raise ValueError('Unexpected/duplicate matrix cell')
        if r['source'] != a.source or r['engine'] != '4.7.2' or r['core_source'] != cores[r['core']] or r['zip_sha256'] != package['zip_sha256']:
            raise ValueError('Stale/incompatible install receipt')
        if {c['order'] for c in r['cases']} != {'core-first', 'toolkit-first'} or len(r['cases']) != 2:
            raise ValueError('Both enable orders required')
        for case in r['cases']:
            log = path.parent / (case['order'] + '-editor.log')
            if case['status'] != 'pass' or hashlib.sha256(log.read_bytes()).hexdigest() != case['log_sha256']:
                raise ValueError('Missing/corrupt passing log')
        seen.add(cell)
    if seen != expected:
        raise ValueError('Missing required installation cells: ' + str(expected - seen))
    print('INSTALL_MATRIX_PASS=4')

if __name__ == '__main__':
    main()
