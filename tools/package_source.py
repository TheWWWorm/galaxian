#!/usr/bin/env python3
"""Package only explicitly allowlisted engine source, never private game content."""
import argparse
import json
import pathlib
import zipfile

ROOT = pathlib.Path(__file__).resolve().parents[1]

def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument('output', type=pathlib.Path)
    args = ap.parse_args()
    output = args.output.resolve()
    if output.is_relative_to(ROOT):
        ap.error('Choose an output outside the source repository')
    names = json.loads((ROOT/'source-manifest.json').read_text())['files']
    if len(names) != len(set(names)):
        raise ValueError('Duplicate source entries')
    output.parent.mkdir(parents=True, exist_ok=True)
    for name in names:
        path = ROOT/name
        if not path.resolve().is_relative_to(ROOT) or path.is_symlink() or not path.is_file():
            raise ValueError(f'Invalid source entry: {name}')
        if path.suffix.lower() in ('.ipa', '.jar', '.aem', '.aei', '.mp3', '.wav', '.class', '.pck'):
            raise ValueError(f'Game content or binary in source manifest: {name}')
    with zipfile.ZipFile(output, 'w', compression=zipfile.ZIP_DEFLATED) as z:
        for name in names:
            z.write(ROOT/name, 'gof1-remake/'+name)
    print(f'{output}: {len(names)} source files')

if __name__ == '__main__':
    main()
