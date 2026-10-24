"""Load the strict Flutter analysis scope shared by CI and standalone builders."""
from __future__ import annotations

import argparse
import json
from pathlib import Path

from release_common import safe_relative


def focused_targets(root: Path) -> list[str]:
    root = root.resolve()
    configuration = root / 'scripts/analysis_targets.json'
    data = json.loads(configuration.read_text(encoding='utf-8'))
    if not isinstance(data, dict) or type(data.get('schema')) is not int or data['schema'] != 1:
        raise ValueError('Expected schema 1 in scripts/analysis_targets.json.')
    targets = data.get('focused')
    if not isinstance(targets, list) or not targets:
        raise ValueError('The focused analysis target list must not be empty.')
    seen = set()
    for name in targets:
        if not isinstance(name, str):
            raise ValueError('Focused analysis targets must be relative path strings.')
        safe_relative(name)
        if not name.startswith('lib/') or name.casefold() in seen:
            raise ValueError(f'Focused analysis targets must be unique paths under upstream/lib/: {name}')
        seen.add(name.casefold())
        target = root / 'upstream' / name
        if not target.resolve().is_relative_to(root / 'upstream/lib'):
            raise ValueError(f'Focused analysis target escapes upstream/lib/: {name}')
        if not target.is_dir() and not (target.is_file() and target.suffix == '.dart'):
            raise ValueError(f'Focused analysis target is missing or is not Dart source: {name}')
    return targets


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--root', type=Path, default=Path(__file__).resolve().parent.parent)
    args = parser.parse_args()
    try:
        print(json.dumps(focused_targets(args.root)))
    except (OSError, ValueError) as error:
        parser.exit(1, f'{error}\n')


if __name__ == '__main__':
    main()
