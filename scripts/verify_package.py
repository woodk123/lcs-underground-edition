"""Verify an extracted release against its adjacent ZIP and SHA-256 sidecar."""
import argparse
import json
from pathlib import Path

from release_common import verify_package


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('package', type=Path)
    args = parser.parse_args()
    print(json.dumps(verify_package(args.package), indent=2))
