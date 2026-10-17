"""Deterministic test shards, balanced using reviewed per-file CI timings."""
from __future__ import annotations

import argparse
import json
import math
from pathlib import Path
import statistics

SHARDS = 4


def test_files(root: Path, shard: int, target: str = 'windows') -> list[str]:
    if shard not in range(SHARDS):
        raise ValueError('Invalid test shard.')
    files = sorted(p.relative_to(root / 'upstream').as_posix()
                   for p in (root / 'upstream/test').rglob('*_test.dart'))
    profile_path = root / 'scripts/ci_test_weights.json'
    if not profile_path.exists():
        return files[shard::SHARDS]
    profile = json.loads(profile_path.read_text(encoding='utf-8'))
    if profile.get('schema') != 1 or target not in profile.get('platforms', {}):
        raise ValueError('Invalid test timing profile.')
    platform_profile = profile['platforms'][target]
    weights = platform_profile['files']
    extra = platform_profile['extra_seconds']
    if (len(extra) != SHARDS or not weights or
            any(not math.isfinite(v) or v <= 0 for v in weights.values()) or
            any(not math.isfinite(v) or v < 0 for v in extra)):
        raise ValueError('Invalid test timing weights.')
    # New tests receive a median estimate until a later reviewed profile update.
    default = statistics.median(weights.values())
    costs = {name: weights.get(name, default) for name in files}
    totals = list(extra)
    groups: list[list[str]] = [[] for _ in range(SHARDS)]
    ordered = sorted(files, key=lambda name: (-costs[name], name))
    for index, name in enumerate(ordered):
        empty = [i for i, group in enumerate(groups) if not group]
        candidates = empty if len(ordered) - index == len(empty) else range(SHARDS)
        selected = min(candidates, key=lambda i: (totals[i], i))
        groups[selected].append(name)
        totals[selected] += costs[name]
    return sorted(groups[shard])


def suite_seconds(path: Path, expected: list[str]) -> dict[str, float]:
    """Measure each suite's loading/execution span, including hidden setup tests."""
    suites = {}
    tests = {}
    starts: dict[str, float] = {}
    ends: dict[str, float] = {}
    succeeded = False
    for line in path.read_text(encoding='utf-8-sig').splitlines():
        event = json.loads(line)
        kind = event.get('type')
        if kind == 'suite':
            suite = event['suite']
            suite_path = (suite.get('path') or '').replace('\\', '/')
            relative = next((name for name in expected
                             if suite_path == name or suite_path.endswith('/' + name)), None)
            if relative is not None:
                suites[suite['id']] = relative
        elif kind == 'testStart':
            test = event['test']
            name = suites.get(test['suiteID'])
            if name is not None:
                tests[test['id']] = name
                starts[name] = min(starts.get(name, event['time']), event['time'])
        elif kind == 'testDone' and event['testID'] in tests:
            name = tests[event['testID']]
            ends[name] = max(ends.get(name, event['time']), event['time'])
        elif kind == 'done':
            succeeded = event.get('success') is True
    if not succeeded or set(starts) != set(expected) or set(ends) != set(expected):
        raise ValueError(f'Incomplete or unsuccessful test timing report: {path}')
    return {name: max(0.001, (ends[name] - starts[name]) / 1000) for name in expected}


def timing_profile(artifacts: Path) -> dict:
    platforms = {}
    identities = set()
    for target in ('linux', 'windows'):
        files = {}
        extra = []
        for shard in range(SHARDS):
            folder = artifacts / f'checks-{target}-{shard}'
            report = json.loads((folder / 'report.json').read_text())
            if (report.get('status') != 'passed' or report.get('platform') != target or
                    report.get('shard') != shard or report.get('shards') != SHARDS or
                    any(step['exit_code'] != 0 for step in report['steps'])):
                raise ValueError('Timing weights require successful matching CI shards.')
            identities.add((report['source_commit'], report['run_id']))
            spans = suite_seconds(folder / 'tests.jsonl', report['test_files'])
            if set(files) & set(spans):
                raise ValueError('Timing shards overlap.')
            elapsed = next(s['elapsed_seconds'] for s in report['steps'] if s['name'] == 'tests')
            # Suites overlap inside Flutter's concurrent runner. Normalize their
            # relative weights to this shard's actual test-process wall time.
            scale = elapsed / sum(spans.values())
            files.update({name: max(0.0001, round(value * scale, 4)) for name, value in spans.items()})
            extra.append(round(sum(s['elapsed_seconds'] for s in report['steps']
                                   if s['name'] in {'tooling', 'assets', 'focused-analysis', 'full-analysis'}), 3))
        platforms[target] = {'extra_seconds': extra, 'files': dict(sorted(files.items()))}
    if len(identities) != 1 or set(platforms['linux']['files']) != set(platforms['windows']['files']):
        raise ValueError('Timing profiles must cover the same tests from the same CI run.')
    commit, run_id = identities.pop()
    return {'schema': 1, 'source_commit': commit, 'source_run_id': run_id,
            'method': 'Per-suite loading/execution spans, normalized to shard wall time; includes extra check budgets.',
            'platforms': platforms}


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--reports', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    profile = timing_profile(args.reports)
    args.output.write_text(json.dumps(profile, indent=2) + '\n', encoding='utf-8')


if __name__ == '__main__':
    main()
