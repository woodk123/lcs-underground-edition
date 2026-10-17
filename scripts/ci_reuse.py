"""Select only complete, same-commit Project checks artifacts for a nightly."""
from __future__ import annotations

import json
import os
from pathlib import Path
import subprocess
import time

from ci_worker import PLATFORMS, SHARDS

POLL_SECONDS = 10


def eligible(run: dict, repository: str, commit: str, branch: str) -> bool:
    return (run.get('head_sha') == commit and run.get('head_branch') == branch and
            run.get('head_repository', {}).get('full_name') == repository and
            run.get('event') == 'push' and run.get('path') == '.github/workflows/checks.yml')


def complete_artifacts(items: list[dict]) -> bool:
    required = {f'build-{target}' for target in PLATFORMS} | {
        f'checks-{target}-{shard}' for target in PLATFORMS for shard in range(SHARDS)}
    available = {item['name'] for item in items if not item.get('expired')}
    return required <= available


def api(path: str) -> dict:
    return json.loads(subprocess.check_output(['gh', 'api', path], text=True))


def select_run(repository: str, commit: str, branch: str, wait_seconds: int = 1200) -> str:
    deadline = time.monotonic() + wait_seconds
    while True:
        runs = api(f'repos/{repository}/actions/workflows/checks.yml/runs?head_sha={commit}&event=push&per_page=100')['workflow_runs']
        candidates = sorted((r for r in runs if eligible(r, repository, commit, branch)),
                            key=lambda r: r['id'], reverse=True)
        for run in candidates:
            if run['status'] == 'completed' and run['conclusion'] == 'success':
                artifacts = api(f"repos/{repository}/actions/runs/{run['id']}/artifacts?per_page=100")['artifacts']
                if complete_artifacts(artifacts):
                    return str(run['id'])
        if not any(r['status'] != 'completed' for r in candidates) or time.monotonic() >= deadline:
            return ''  # No usable evidence: run the complete pipeline, never skip checks.
        print('Waiting for same-commit Project checks; no duplicate build needed.', flush=True)
        time.sleep(min(POLL_SECONDS, max(0, deadline - time.monotonic())))


def main():
    repository = os.environ['GITHUB_REPOSITORY']
    commit = subprocess.check_output(['git', 'rev-parse', 'HEAD'], text=True).strip()
    branch = os.environ['GITHUB_REF_NAME']
    run_id = select_run(repository, commit, branch)
    with Path(os.environ['GITHUB_OUTPUT']).open('a', encoding='utf-8') as output:
        output.write(f'run_id={run_id}\n')
    print(f'Reusing checked artifacts from run {run_id}.' if run_id else 'No reusable run: building and checking all players.')


if __name__ == '__main__':
    main()
