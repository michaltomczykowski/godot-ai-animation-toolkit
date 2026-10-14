"""Real archive corruption/path/version controls for the release validator."""
from pathlib import Path
import subprocess
import tempfile
import zipfile
from validate_release_package import validate

def main():
    repo = Path(__file__).resolve().parents[1]
    with tempfile.TemporaryDirectory(prefix='toolkit-package-controls-') as temp:
        root = Path(temp)
        archive = root / 'original.zip'
        subprocess.run(['git', '-c', 'core.autocrlf=false', '-C', str(repo), 'archive', '--format=zip', '--output', str(archive), 'HEAD', 'addons/godot_ai_animation', 'LICENSE'], check=True)
        result = validate(repo, 'HEAD', archive)
        checks = 1
        def refused(path, version=None):
            nonlocal checks
            try:
                validate(repo, 'HEAD', path, version)
            except ValueError:
                checks += 1
                return
            raise AssertionError('Corrupted package was accepted')
        refused(archive, '999.0.0')
        with zipfile.ZipFile(archive) as z:
            entries = {item.filename: z.read(item) for item in z.infolist() if not item.is_dir()}
        for index, extra in enumerate(('../escape.gd', 'addons/godot_ai_animation/private.mp4', 'LICENSE')):
            bad = root / f'bad-{index}.zip'
            with zipfile.ZipFile(bad, 'w') as z:
                for name, data in entries.items():
                    z.writestr(name, b'tampered' if extra == name else data)
                if extra not in entries:
                    z.writestr(extra, b'forbidden')
            refused(bad)
        print(f"PACKAGE_CONTROLS_PASS={checks} source={result['source']} entries={len(result['entries'])}")

if __name__ == '__main__':
    main()
