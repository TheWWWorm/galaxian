#!/usr/bin/env python3
"""Create a standalone Cloudflare Workers bundle from an engine-only Web export.

The numbered-part approach follows the Apache-2.0 DEEP remake. Original game
archives and imported resources must never be placed in the exported directory.
"""
import argparse
import hashlib
import json
from pathlib import Path
import shutil

ROOT = Path(__file__).resolve().parents[1]
LIMIT = 25 * 1024 * 1024
CHUNK = 20 * 1024 * 1024
FILES = ('index.html', 'index.js', 'index.wasm', 'index.pck',
         'index.audio.worklet.js', 'index.audio.position.worklet.js',
         'index.icon.png', 'index.apple-touch-icon.png', 'index.png')
HEADERS = '''/*
  Cross-Origin-Opener-Policy: same-origin
  Cross-Origin-Embedder-Policy: require-corp
  Cross-Origin-Resource-Policy: same-origin
  X-Content-Type-Options: nosniff
  Referrer-Policy: no-referrer
  Cache-Control: no-cache
'''

def prepare(source, output):
    source, output = Path(source).resolve(), Path(output).resolve()
    if output.exists():
        raise ValueError('Choose a new output directory; existing bundles are preserved')
    if source == output or output.is_relative_to(source):
        raise ValueError('Output must be separate from the export')
    for name in FILES:
        path = source / name
        if not path.is_file() or path.is_symlink():
            raise ValueError(f'Missing or unsafe Web export file: {name}')
    public = output / 'public'
    public.mkdir(parents=True)
    parts, hashes = {}, {}
    for name in FILES:
        raw = (source / name).read_bytes()
        hashes[name] = hashlib.sha256(raw).hexdigest()
        if len(raw) > LIMIT:
            count = (len(raw) + CHUNK - 1) // CHUNK
            parts['/' + name] = {'count': count, 'size': len(raw)}
            for index in range(count):
                (public / f'{name}.part{index}').write_bytes(raw[index*CHUNK:(index+1)*CHUNK])
        else:
            (public / name).write_bytes(raw)
    (public / '_headers').write_text(HEADERS)
    (output / 'parts.json').write_text(json.dumps(parts, indent=2)+'\n')
    (output / 'export-hashes.json').write_text(json.dumps(hashes, indent=2)+'\n')
    for name in ('worker.js', 'wrangler.toml'):
        shutil.copyfile(ROOT / name, output / name)
    (output / 'README.txt').write_text('Galaxy on Fire native remake Web hosting bundle\n\nRun npx wrangler dev for local testing; npx wrangler deploy publishes it.\nThe configured domain is https://galaxian.wwworm.com/. Deploy using the\nCloudflare account owning wwworm.com. For a fork, change the worker name\nand domain in wrangler.toml and the HTTP redirect hostname in worker.js.\nNo game assets are included. Keep public/, parts.json and export-hashes.json\ntogether from the same build.\n')
    print(f'{output}: {len(FILES)} engine files, {len(parts)} split for the host limit')

if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--source', required=True, type=Path)
    parser.add_argument('--output', required=True, type=Path)
    args = parser.parse_args()
    prepare(args.source, args.output)
