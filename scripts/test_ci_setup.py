"""SDK profiles must contain the right artifacts without weakening pin checks."""
import json
import os
from pathlib import Path
import tempfile
import unittest
from unittest.mock import call, patch

import ci_setup


class SetupTests(unittest.TestCase):
    def setUp(self):
        # A cold platform.system() can run `ver` through subprocess on Windows.
        # Keep OS discovery out of the SDK subprocess mocks below.
        host = patch.object(ci_setup.platform, 'system', return_value='Windows' if os.name == 'nt' else 'Linux')
        host.start()
        self.addCleanup(host.stop)
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name)
        (self.root / '.tools/flutter').mkdir(parents=True)
        (self.root / 'scripts').mkdir()
        self.pin = {'flutter_version': '1.2.3', 'flutter_revision': 'a' * 40}
        (self.root / 'scripts/toolchain.json').write_text(json.dumps(self.pin))
        self.version = json.dumps({'frameworkVersion': self.pin['flutter_version'],
                                   'frameworkRevision': self.pin['flutter_revision']})

    def test_profiles_only_precache_universal_and_their_target(self):
        for host, target in [('Windows', 'tests'), ('Linux', 'tests'),
                             ('Windows', 'windows'), ('Linux', 'linux'), ('Linux', 'web')]:
            with self.subTest(host=host, target=target), \
                    patch.object(ci_setup.platform, 'system', return_value=host), \
                    patch.object(ci_setup.subprocess, 'run') as run, \
                    patch.object(ci_setup.subprocess, 'check_output', return_value=self.version):
                ci_setup.setup(self.root, target)
                flutter = str(self.root / ('.tools/flutter/bin/flutter.bat' if host == 'Windows'
                                          else '.tools/flutter/bin/flutter'))
                precache = [flutter, 'precache', '--universal']
                if target != 'tests':
                    precache.append(f'--{target}')
                self.assertEqual(run.call_args_list[1], call(precache, check=True))
                self.assertEqual(run.call_args_list[2], call([flutter, 'pub', 'get'],
                                                            cwd=self.root / 'upstream', check=True))

    def test_bootstrap_precedes_version_query_and_mismatched_pin_stops_setup(self):
        with patch.object(ci_setup.subprocess, 'run') as run, \
                patch.object(ci_setup.subprocess, 'check_output') as version:
            def query(*args, **kwargs):
                self.assertEqual(run.call_count, 1)
                self.assertIn('config', run.call_args.args[0])
                return json.dumps({'frameworkVersion': 'wrong', 'frameworkRevision': 'wrong'})
            version.side_effect = query
            with self.assertRaisesRegex(ValueError, 'pinned toolchain'):
                ci_setup.setup(self.root, 'tests')
            self.assertEqual(run.call_count, 1)

    def test_wrong_native_host_rejected_before_downloading(self):
        with patch.object(ci_setup.platform, 'system', return_value='Linux'), \
                patch.object(ci_setup.subprocess, 'run') as run:
            with self.assertRaisesRegex(ValueError, 'host'):
                ci_setup.setup(self.root, 'windows')
            run.assert_not_called()


if __name__ == '__main__':
    unittest.main()
