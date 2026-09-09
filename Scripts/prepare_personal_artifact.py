#!/usr/bin/env python3
"""Archive a verified personal app with source and binary provenance."""
import hashlib
import json
import os
from pathlib import Path
import plistlib
import subprocess


def bundle_metadata(app, commit):
    info = plistlib.loads((app / 'Contents/Info.plist').read_bytes())
    if info.get('CFBundleIdentifier') != 'com.steipete.codexbar':
        raise ValueError('Unexpected application identity')
    if info.get('SUFeedURL') != '' or info.get('SUEnableAutomaticChecks') is not False:
        raise ValueError('Personal builds must disable official updates')
    embedded = info.get('CodexGitCommit', '')
    if len(embedded) < 7 or not commit.startswith(embedded):
        raise ValueError('Packaged commit does not match checked-out source')
    binary = app / 'Contents/MacOS/CodexBar'
    return {
        'commit': commit,
        'version': info['CFBundleShortVersionString'],
        'build': info['CFBundleVersion'],
        'build_timestamp': info['CodexBuildTimestamp'],
        'bundle_id': info['CFBundleIdentifier'],
        'binary_sha256': hashlib.sha256(binary.read_bytes()).hexdigest(),
        'signing': 'adhoc',
        'architecture': 'arm64',
    }


def main():
    root = Path(__file__).resolve().parent.parent
    os.chdir(root)
    commit = subprocess.check_output(['git', 'rev-parse', 'HEAD'], text=True).strip()
    if subprocess.check_output(['git', 'status', '--porcelain', '--untracked-files=no'], text=True).strip():
        raise SystemExit('Tracked source changed during build; refusing to label it with HEAD')
    app = root / 'CodexBar.app'
    subprocess.run(['codesign', '--verify', '--deep', '--strict', str(app)], check=True)
    signature = subprocess.check_output(['codesign', '-d', '--verbose=4', str(app)], stderr=subprocess.STDOUT, text=True)
    if 'Signature=adhoc' not in signature:
        raise SystemExit('Expected ad-hoc signature')
    arches = subprocess.check_output(['lipo', '-archs', str(app / 'Contents/MacOS/CodexBar')], text=True).strip()
    if arches != 'arm64':
        raise SystemExit(f'Expected arm64, found {arches}')
    metadata = bundle_metadata(app, commit)
    metadata['run_url'] = f"{os.environ['GITHUB_SERVER_URL']}/{os.environ['GITHUB_REPOSITORY']}/actions/runs/{os.environ['GITHUB_RUN_ID']}"
    metadata['run_attempt'] = os.environ['GITHUB_RUN_ATTEMPT']
    output = root / 'personal-artifact'
    output.mkdir(exist_ok=False)
    archive = output / 'CodexBar-personal-arm64.zip'
    subprocess.run(['ditto', '-c', '-k', '--sequesterRsrc', '--keepParent', str(app), str(archive)], check=True)
    digest = hashlib.sha256(archive.read_bytes()).hexdigest()
    metadata['archive_sha256'] = digest
    (output / 'SHA256SUMS').write_text(f'{digest}  {archive.name}\n')
    (output / 'build.json').write_text(json.dumps(metadata, indent=2) + '\n')
    print(json.dumps(metadata, indent=2))


if __name__ == '__main__':
    main()
