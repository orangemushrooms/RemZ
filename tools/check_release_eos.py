"""Verify the shipped EOS config and prevent unrelated secrets from entering a release.

The Peer2Peer game-client credential is intentionally included in eos.cfg. Only
a policy suitable for public game clients belongs here; it is managed in Epic's
portal. This check verifies packaging, not portal permissions. No values are logged.
An optional --published-build compares the config with an already shipped release.
"""
import argparse
import configparser
import hashlib
import json
import mmap
import re
import struct
from pathlib import Path

import eos_config

ROOT = Path(__file__).resolve().parents[1]


def packed_config(pack: Path) -> tuple[dict, int, int]:
    # Godot's unencrypted standalone PCK v3/v4 directory layout.
    with pack.open('rb') as handle:
        magic, version, _, _, _, flags = struct.unpack('<6I', handle.read(24))
        if magic != 0x43504447 or version not in (3, 4) or flags & ~2:
            raise ValueError('Unsupported EOS release pack format')
        base, directory = struct.unpack('<2Q', handle.read(16))
        handle.seek(directory)
        count = struct.unpack('<I', handle.read(4))[0]
        if count > 100000:
            raise ValueError('Invalid pack entry count')
        for _ in range(count):
            length = struct.unpack('<I', handle.read(4))[0]
            if length > 16384:
                raise ValueError('Invalid pack path length')
            name = handle.read(length).rstrip(b'\x00').decode('utf-8')
            offset, size = struct.unpack('<2Q', handle.read(16))
            digest = handle.read(16)
            entry_flags = struct.unpack('<I', handle.read(4))[0]
            if name.removeprefix('res://') != 'eos.cfg':
                continue
            if entry_flags or size > 16384 or base + offset + size > pack.stat().st_size:
                raise ValueError('Invalid EOS config entry')
            handle.seek(base + offset)
            content = handle.read(size)
            if hashlib.md5(content).digest() != digest:
                raise ValueError('EOS config checksum mismatch')
            config = configparser.ConfigParser(interpolation=None)
            config.read_string(content.decode('utf-8'))
            if config.sections() != ['eos']:
                raise ValueError('Unexpected EOS config sections')
            return {key: value.strip('"') for key, value in config['eos'].items()}, base + offset, size
    raise ValueError('EOS configuration is missing from the release pack')


def audit(build: Path, published: Path | None = None) -> dict:
    config, config_offset, config_size = packed_config(build / 'RemZ.pck')
    values = eos_config.load_values()
    if set(config) != set(eos_config.KEYS.values()) | {'product_version'}:
        raise ValueError('Unexpected or missing EOS config fields')
    for env_key, config_key in eos_config.KEYS.items():
        if not values.get(env_key) or config.get(config_key) != values[env_key]:
            raise ValueError('Packaged EOS configuration does not match the local build configuration')
    if config['product_version'] != eos_config._build_constant():
        raise ValueError('Packaged EOS version does not match the game build')
    if published:
        old, _, _ = packed_config(published / 'RemZ.pck')
        if any(old.get(key) != config[key] for key in eos_config.KEYS.values()):
            raise ValueError('EOS credentials differ from the supplied published build')

    needles = []
    for key, value in values.items():
        if re.search(r'SECRET|TOKEN|PASSWORD|API.?KEY', key, re.I) and len(str(value)) >= 8:
            for encoding in ('utf-8', 'utf-16le'):
                needles.append((key, str(value).encode(encoding)))
    runtime = {'RemZ.exe', 'RemZ.pck', 'libeosg.windows.template_release.x86_64.dll',
               'EOSSDK-Win64-Shipping.dll', 'xaudio2_9redist.dll'}
    checked = set()
    for path in build.rglob('*'):
        relative = path.relative_to(build)
        if path.is_dir() or relative.parts[0] == 'logs' or path.suffix in {'.TMP', '.tmp'}:
            continue  # publish-itch.ps1 excludes exactly these files.
        if path.parent != build or not (path.name in runtime | {'BUILD-INFO.json'} or path.suffix in {'.md', '.txt'}):
            raise ValueError(f'Unexpected release file: {relative}')
        if path.stat().st_size:
            with path.open('rb') as handle, mmap.mmap(handle.fileno(), 0, access=mmap.ACCESS_READ) as data:
                for key, needle in needles:
                    position = data.find(needle)
                    while position != -1:
                        intended_client_config = (key == 'EOS_CLIENT_SECRET' and path.name == 'RemZ.pck'
                            and config_offset <= position and position + len(needle) <= config_offset + config_size)
                        if not intended_client_config:
                            raise ValueError(f'A local secret occurs outside the intended EOS pack entry: {relative}')
                        position = data.find(needle, position + len(needle))
        checked.add(path.name)
    if not runtime <= checked:
        raise ValueError('Required EOS runtime files are missing')
    return {'configured': True, 'files_checked': len(checked), 'unrelated_secrets_found': False,
            'matches_published_client_config': True if published else None}


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--build', type=Path, default=ROOT / 'builds/windows')
    parser.add_argument('--published-build', type=Path)
    args = parser.parse_args()
    try:
        print('EOS_RELEASE_AUDIT_OK ' + json.dumps(audit(args.build.resolve(), args.published_build)))
    except (ValueError, OSError, struct.error, configparser.Error) as error:
        # Never print parsing exceptions: malformed config text can contain credentials.
        if isinstance(error, ValueError) and not isinstance(error, UnicodeError):
            message = str(error)
        else:
            message = 'Unable to read the EOS release configuration'
        raise SystemExit('EOS_RELEASE_AUDIT_FAILED: ' + message)
