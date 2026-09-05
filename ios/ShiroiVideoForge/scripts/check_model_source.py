#!/usr/bin/env python3
"""HEAD-only endpoint regression check. Does not download or execute model weights."""
from pathlib import Path
import re
import urllib.request

source = (Path(__file__).resolve().parents[1] / 'Sources/ModelManifest.swift').read_text()
revision = re.search(r'static let revision = "([0-9a-f]{40})"', source).group(1)
name = re.search(r'static let archiveName = "([^"]+)"', source).group(1)
url = f'https://huggingface.co/apple/coreml-stable-diffusion-v1-5-palettized/resolve/{revision}/{name}'
request = urllib.request.Request(url, method='HEAD', headers={'User-Agent': 'ShiroiVideoForge-build-check'})
with urllib.request.urlopen(request, timeout=45) as response:
    if response.status != 200:
        raise RuntimeError(f'Model source returned HTTP {response.status}')
    print(f'Model source responds HTTP {response.status}; revision {revision}; artifact {name}.')
print('Availability only: full archive download and Core ML inference are NOT verified.')
