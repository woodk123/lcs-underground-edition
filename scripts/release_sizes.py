"""Account for actual ZIP contents and enforce player download/install budgets."""
from __future__ import annotations

import json
from pathlib import Path
import zipfile

from release_common import write_json


PLAYER_BUDGETS = {
    'windows-x64': {'archive_bytes': 48_000_000, 'extracted_bytes': 80_000_000},
    'web': {'archive_bytes': 40_000_000, 'extracted_bytes': 60_000_000},
}


def group_for(name: str) -> str:
    if '/assets/modern/portraits_v2/' in name:
        return 'portraits'
    if '/assets/modern/' in name:
        return 'other_artwork'
    if '/canvaskit/' in name:
        return 'web_renderers'
    if name.endswith(('.exe', '.dll', '.so', '.js', '.wasm')):
        return 'code_and_runtime'
    return 'data_fonts_and_notices'


def measure_archive(path: Path) -> dict:
    groups = {}
    with zipfile.ZipFile(path) as archive:
        for entry in archive.infolist():
            if entry.is_dir():
                continue
            name = entry.filename.split('/', 1)[-1]
            group = groups.setdefault(group_for(name), {'files': 0, 'archive_bytes': 0, 'extracted_bytes': 0})
            group['files'] += 1
            group['archive_bytes'] += entry.compress_size
            group['extracted_bytes'] += entry.file_size
    return {'archive': path.name, 'archive_bytes': path.stat().st_size,
            'extracted_bytes': sum(group['extracted_bytes'] for group in groups.values()),
            'groups': groups}


def check_budget(target: str, measurement: dict) -> list[str]:
    return [f"{target} {field}: {measurement[field]:,} bytes exceeds {limit:,} byte budget"
            for field, limit in PLAYER_BUDGETS.get(target, {}).items()
            if measurement[field] > limit]


def report_sizes(output: Path, packages: list[dict], evidence: Path) -> dict:
    measured = {}
    errors = []
    for package in packages:
        archive = Path(package['archive'])
        info_path = Path(package['package']) / 'BUILD_INFO.json'
        target = json.loads(info_path.read_text(encoding='utf-8'))['target']
        measurement = measure_archive(archive)
        measurement['budgets'] = PLAYER_BUDGETS.get(target, {})
        measured[target] = measurement
        errors.extend(check_budget(target, measurement))
        print(f"{target}: {measurement['archive_bytes'] / 1_000_000:.1f} MB ZIP, "
              f"{measurement['extracted_bytes'] / 1_000_000:.1f} MB extracted")
    result = {'status': 'failed' if errors else 'passed', 'packages': measured, 'errors': errors}
    write_json(output / 'size-report.json', result)
    write_json(evidence / 'release-sizes.json', result)
    if errors:
        raise ValueError('Release size budget exceeded: ' + '; '.join(errors))
    return result
