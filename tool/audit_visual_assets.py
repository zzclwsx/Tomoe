"""Guard against accidentally restoring replaced visual assets during migration.

Uses file hashes and a fixed font source; it is not a general legal audit.
"""
import hashlib
import json
from pathlib import Path

root = Path(__file__).resolve().parent.parent
legacy = json.loads((root / 'tool/legacy_visual_hashes.json').read_text())['sha256']
blocked = set(legacy.values())
errors = []
checked = 0
for folder in ['assets', 'windows/runner/resources', 'android/app/src/main/res',
               'ios/Runner/Assets.xcassets', 'macos/Runner/Assets.xcassets', 'web']:
    for file in (root / folder).rglob('*'):
        if not file.is_file() or file.suffix.lower() not in {'.png', '.ico', '.jpeg', '.jpg', '.svg', '.ttf'}:
            continue
        checked += 1
        if hashlib.sha256(file.read_bytes()).hexdigest() in blocked:
            errors.append('Replaced legacy asset restored: ' + str(file.relative_to(root)))
for path in ['assets/fonts/MiSans-Regular.ttf', 'assets/images/noface.jpeg',
             'assets/images/loading.png', 'assets/images/forward_80.png',
             'assets/images/danmaku_off.svg', 'assets/images/danmaku_setting.svg']:
    if (root / path).exists(): errors.append('Legacy asset path restored: ' + path)
font = root / 'assets/fonts/NotoSansSC.ttf'
if hashlib.sha256(font.read_bytes()).hexdigest() != 'a3041811a78c361b1de50f953c805e0244951c21c5bd412f7232ef0d899af0da':
    errors.append('Noto Sans SC differs from the recorded, unmodified official file')
for path in ['licenses/fonts/OFL-NotoSansSC.txt', 'licenses/material-icons/LICENSE',
             'licenses/tomoe-art/LICENSE', 'assets/brand/tomoe-mark.svg']:
    if not (root / path).is_file(): errors.append('Missing asset source/license: ' + path)
if errors:
    raise SystemExit('\n'.join(errors))
print(f'Visual asset audit passed: {checked} current files; no recorded legacy images; official font verified.')
