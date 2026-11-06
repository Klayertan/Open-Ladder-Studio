#!/usr/bin/env python3
"""Build, verify, and deliver a dated macOS installer disk image."""
from datetime import datetime
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
from zoneinfo import ZoneInfo

root = Path(__file__).resolve().parent.parent
subprocess.run([sys.executable, str(root / 'Scripts/build_native.py')], cwd=root, check=True)
app = root / 'build/Native/Open Ladder Studio.app'
subprocess.run(['codesign', '--verify', '--deep', '--strict', str(app)], check=True)
stamp = datetime.now(ZoneInfo('Asia/Tokyo')).strftime('%Y%m%d-%H%M%S')
output = root / 'build' / f'Open-Ladder-Studio-{stamp}.dmg'
with tempfile.TemporaryDirectory(prefix='open-ladder-dmg-') as temporary:
    staging = Path(temporary) / 'Open Ladder Studio'
    staging.mkdir()
    subprocess.run(['ditto', str(app), str(staging / app.name)], check=True)
    (staging / 'Applications').symlink_to('/Applications', target_is_directory=True)
    (staging / 'Install.txt').write_text(
        'Drag Open Ladder Studio to Applications.\n'
        'Requires Apple Silicon and macOS 14 or later.\n'
        'This build is locally signed and is not notarized.\n'
    )
    subprocess.run([
        'hdiutil', 'create', '-volname', 'Open Ladder Studio', '-srcfolder',
        str(staging), '-format', 'UDZO', str(output),
    ], check=True)
subprocess.run(['hdiutil', 'verify', str(output)], check=True)
downloads = Path.home() / 'Downloads'
downloads.mkdir(exist_ok=True)
delivery = downloads / output.name
shutil.copy2(output, delivery)
print(f'DMG: {delivery}', flush=True)
