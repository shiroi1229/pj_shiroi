#!/usr/bin/env python3
"""Verify the complete pinned model on a CI host, never execute pickle files."""
import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import re
import stat
import sys
import urllib.request
import zipfile

root = Path(__file__).resolve().parents[1]
manifest = (root / 'Sources/ModelManifest.swift').read_text()
revision = re.search(r'static let revision = "([0-9a-f]{40})"', manifest).group(1)
name = re.search(r'static let archiveName = "([^"]+)"', manifest).group(1)
repo = 'apple/coreml-stable-diffusion-v1-5-palettized'
work = Path(sys.argv[1]); work.mkdir(parents=True, exist_ok=True)
report_path = Path(sys.argv[2]); report_path.parent.mkdir(parents=True, exist_ok=True)
with urllib.request.urlopen(f'https://huggingface.co/api/models/{repo}/tree/{revision}', timeout=60) as r:
    entries = json.load(r)
entry = next(e for e in entries if e.get('path') == name)
expected_size = entry['size']
expected_hash = entry['lfs']['oid']
if not re.fullmatch('[0-9a-f]{64}', expected_hash): raise RuntimeError('No valid LFS SHA-256')
archive = work / name
sha = hashlib.sha256(); written = 0
with urllib.request.urlopen(f'https://huggingface.co/{repo}/resolve/{revision}/{name}', timeout=120) as r, archive.open('wb') as out:
    while chunk := r.read(4 * 1024 * 1024):
        out.write(chunk); sha.update(chunk); written += len(chunk)
        if written > expected_size: raise RuntimeError('Archive exceeds advertised size')
if written != expected_size or sha.hexdigest() != expected_hash:
    raise RuntimeError('Archive size or SHA-256 mismatch')
extract = work / 'resources'; extract.mkdir(exist_ok=True)
with zipfile.ZipFile(archive) as z:
    if sum(i.file_size for i in z.infolist()) > 8_000_000_000: raise RuntimeError('Archive expands beyond budget')
    for i in z.infolist():
        p = PurePosixPath(i.filename)
        if p.is_absolute() or '..' in p.parts or '\\' in i.filename or stat.S_ISLNK(i.external_attr >> 16):
            raise RuntimeError('Unsafe ZIP member')
    bad = z.testzip()
    if bad: raise RuntimeError('ZIP CRC failure')
    z.extractall(extract)
resource_dirs = sorted(str(p.parent) for p in extract.rglob('TextEncoder.mlmodelc'))
if len(resource_dirs) != 1: raise RuntimeError('Ambiguous Core ML resource root')
resource = Path(resource_dirs[0])
report = {'revision': revision, 'archive': name, 'bytes': written, 'expected_sha256': expected_hash,
          'actual_sha256': sha.hexdigest(), 'crc': 'passed',
          'resource_names': sorted(p.name for p in resource.iterdir()),
          'host': 'GitHub Actions, not user iPad', 'inference': 'not_tested'}
report_path.write_text(json.dumps(report, indent=2))
(work / 'resource-path.txt').write_text(str(resource))
print(json.dumps(report, indent=2))
