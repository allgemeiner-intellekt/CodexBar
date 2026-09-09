import os
from pathlib import Path
import subprocess
import tempfile

root = Path(__file__).resolve().parent.parent
app = root / 'CodexBar.app'
with tempfile.TemporaryDirectory(prefix='codexbar-personal-resources-') as folder:
    stage = Path(folder)
    copy = stage / 'CodexBar.app'
    subprocess.run(['ditto', str(app), str(copy)], check=True)
    cli = copy / 'Contents/Helpers/CodexBarCLI'
    link = stage / 'codexbar'
    link.symlink_to(cli)
    profile = '(version 1)(allow default)(deny file-read* (subpath "' + str(root) + '"))'
    env = dict(os.environ, CODEXBAR_RESOURCE_SMOKE='1', CODEXBAR_SUPPRESS_TEST_KEYCHAIN_ACCESS='1')
    env.pop('CODEXBAR_ALLOW_TEST_KEYCHAIN_ACCESS', None)
    for name, target in [('app', copy / 'Contents/MacOS/CodexBar'), ('cli', cli), ('cli-symlink', link)]:
        result = subprocess.run(['sandbox-exec', '-p', profile, str(target)], env=env, cwd=stage,
                                capture_output=True, text=True, timeout=30)
        if result.returncode != 0 or 'CODEXBAR_RESOURCE_SMOKE_OK' not in result.stdout:
            raise SystemExit(f'{name} failed: {result.returncode}\n{result.stdout}\n{result.stderr}')
        print(f'{name}: CODEXBAR_RESOURCE_SMOKE_OK; repository reads denied')
