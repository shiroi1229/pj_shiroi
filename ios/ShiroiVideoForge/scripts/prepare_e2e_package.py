#!/usr/bin/env python3
"""Build a native test executable from unmodified copies of production sources."""
from pathlib import Path
import hashlib
import json
import re
import shutil
import sys

root = Path(__file__).resolve().parents[1]
project = (root / 'project.yml').read_text()
revision = re.search(r'StableDiffusion:\s*url: https://github.com/apple/ml-stable-diffusion.git\s*revision: ([0-9a-f]{40})', project).group(1)
zip_version = re.search(r'ZIPFoundation:\s*url: https://github.com/weichsel/ZIPFoundation.git\s*from: ([\d.]+)', project).group(1)
work = Path(sys.argv[1]); sources = work / 'Sources' / 'ForgeE2E'; sources.mkdir(parents=True, exist_ok=True)
names = ['GenerationRequest.swift', 'DeviceCapabilities.swift', 'KeyframeBackend.swift', 'KeyframeGenerator.swift',
         'ModelManifest.swift', 'ModelManager.swift', 'ArchiveDownloader.swift', 'ArchiveIntegrity.swift',
         'MetalVideoComposer.swift', 'OpticalFlowInterpolator.swift']
hashes = {}
for name in names:
    source = root / 'Sources' / name
    shutil.copy2(source, sources / name)
    hashes[name] = hashlib.sha256(source.read_bytes()).hexdigest()
shutil.copy2(root / 'Tests/AIEndToEndProbe.swift', sources / 'AIEndToEndProbe.swift')
(work / 'source-hashes.json').write_text(json.dumps(hashes, indent=2, sort_keys=True))
(work / 'Package.swift').write_text('''// swift-tools-version: 5.9
import PackageDescription
let package = Package(
    name: "ForgeE2E", platforms: [.macOS("15.0")],
    dependencies: [
        .package(url: "https://github.com/apple/ml-stable-diffusion.git", revision: "REVISION"),
        .package(url: "https://github.com/weichsel/ZIPFoundation.git", from: "ZIP_VERSION")
    ],
    targets: [.executableTarget(name: "ForgeE2E", dependencies: [
        .product(name: "StableDiffusion", package: "ml-stable-diffusion"),
        .product(name: "ZIPFoundation", package: "ZIPFoundation")
    ])], swiftLanguageVersions: [.v5]
)
'''.replace('REVISION', revision).replace('ZIP_VERSION', zip_version))
print('Prepared native E2E executable from', len(hashes), 'production source files; no mocks.')
