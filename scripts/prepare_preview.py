"""Generate one shared preview version for all platform builds."""

import argparse
import os
from pathlib import Path
import re


def preview_metadata(pubspec: str, run_number: int) -> dict[str, str]:
    if run_number <= 0:
        raise ValueError('run_number must be positive')
    match = re.search(r'^version:\s*(\d+\.\d+\.\d+)(?:\+([0-9]+))?\s*$', pubspec, re.M)
    if not match:
        raise ValueError('pubspec version must be major.minor.patch[+build]')
    base = match.group(1)
    return {
        'version': f'{base}-preview.{run_number}',
        'build_name': base,
        'build_number': str(int(match.group(2) or 0) + run_number),
    }


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--pubspec', type=Path, default=Path('pubspec.yaml'))
    parser.add_argument('--run-number', type=int, required=True)
    args = parser.parse_args()
    values = preview_metadata(args.pubspec.read_text(encoding='utf-8'), args.run_number)
    text = ''.join(f'{key}={value}\n' for key, value in values.items())
    output_path = os.environ.get('GITHUB_OUTPUT')
    if output_path:
        with open(output_path, 'a', encoding='utf-8') as output:
            output.write(text)
    print(text, end='')


if __name__ == '__main__':
    main()
