"""Windows launcher path/ownership checks without touching persistent servers."""
import json
import os
from pathlib import Path
import shutil
import socket
import subprocess
import sys
import tempfile
import unittest


SCRIPTS = Path(__file__).resolve().parent
POWERSHELL = shutil.which('powershell.exe')


@unittest.skipUnless(os.name == 'nt' and POWERSHELL, 'Windows PowerShell is required.')
class LauncherTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory(prefix='lcs launcher ')
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name).resolve()
        for name in ('launch.ps1', 'stop.ps1'):
            target = self.root / 'scripts' / name
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(SCRIPTS / name, target)
        python = sys.executable.replace("'", "''")
        self.put('scripts/common.ps1',
                 'Set-StrictMode -Version Latest\n'
                 'function Get-LcsRoot { return [IO.Path]::GetFullPath((Join-Path $PSScriptRoot "..")) }\n'
                 f"function Get-LcsPython {{ return '{python}' }}\n")
        self.web = self.root / "web's [build] \u754c"
        self.web.mkdir()
        (self.web / 'index.html').write_text('<!doctype html><title>fixture</title>', encoding='utf-8')
        self.pid_file = self.root / '.local/launcher/server-18879.pid'

    def put(self, name, contents):
        path = self.root / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(contents, encoding='utf-8')
        return path

    def run_powershell(self, body, data):
        self.put('case.json', json.dumps(data))
        script = self.put('case.ps1', r'''
param([string]$Fixture)
$ErrorActionPreference = 'Stop'
$global:lcsLauncherTestData = Get-Content -LiteralPath (Join-Path $Fixture 'case.json') -Raw | ConvertFrom-Json
''' + body)
        return subprocess.run([POWERSHELL, '-NoProfile', '-ExecutionPolicy', 'Bypass',
                               '-File', str(script), '-Fixture', str(self.root)],
                              cwd=self.root, capture_output=True, text=True,
                              encoding='utf-8', errors='replace', timeout=20)

    def run_with_health(self, web, *, directory=None, application='lcs-modern-local', prepare=''):
        return self.run_powershell(prepare + r'''
function Invoke-RestMethod {
    param($Uri, $TimeoutSec, [switch]$UseBasicParsing)
    return [pscustomobject]@{
        application=$global:lcsLauncherTestData.application
        directory=$global:lcsLauncherTestData.directory
    }
}
function Start-Process { throw 'Test must not start a process when a server is already present.' }
& (Join-Path $Fixture 'scripts/launch.ps1') -NoBrowser -Port 18879 -WebRoot $global:lcsLauncherTestData.web
''', {'web': str(web), 'directory': str(directory or self.web.resolve()),
      'application': application})

    def test_existing_health_accepts_spaces_unicode_and_trailing_separator(self):
        result = self.run_with_health(str(self.web) + '\\')
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn('http://127.0.0.1:18879/', result.stdout)
        self.assertFalse(self.pid_file.exists(), 'Reusing a server must not claim its PID.')

    def test_existing_health_accepts_a_junction_alias(self):
        alias = self.root / 'alias web'
        result = self.run_with_health(alias, prepare=r'''
New-Item -ItemType Junction -Path $global:lcsLauncherTestData.web -Target ([Management.Automation.WildcardPattern]::Escape($global:lcsLauncherTestData.directory)) | Out-Null
''')
        # Directory junctions do not need Developer Mode or symlink privilege.
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(alias.resolve(), self.web.resolve())
        self.assertFalse(self.pid_file.exists())

    def test_foreign_health_refuses_without_replacing_a_recorded_pid(self):
        self.put('.local/launcher/server-18879.pid', '45678\n')
        for application, directory in (
                ('foreign-service', self.web),
                ('lcs-modern-local', self.root / 'another build')):
            with self.subTest(application=application, directory=directory):
                result = self.run_with_health(self.web, directory=directory, application=application)
                self.assertNotEqual(result.returncode, 0)
                self.assertIn('serving another game directory', result.stderr)
                self.assertEqual(self.pid_file.read_text(), '45678\n')

    def test_missing_build_fails_before_python_health_or_startup(self):
        self.put('scripts/common.ps1', r'''
Set-StrictMode -Version Latest
function Get-LcsRoot { return [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..')) }
function Get-LcsPython { throw 'Unexpected Python selection.' }
''')
        result = self.run_with_health(self.root / 'missing')
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('Built game missing', result.stderr)
        self.assertNotIn('Unexpected Python selection', result.stderr)
        self.assertFalse(self.pid_file.exists())

    def test_startup_passes_real_python_the_canonical_directory_and_selected_port(self):
        # Exercise Windows Start-Process argument joining with a harmless child.
        # Its script parses/records argv and exits; it never opens a server.
        self.put('scripts/serve.py', r'''
import argparse
import ctypes
import json
from pathlib import Path
import sys
parser = argparse.ArgumentParser()
parser.add_argument('--directory', required=True)
parser.add_argument('--port', required=True, type=int)
args = parser.parse_args()
ctypes.windll.kernel32.GetCommandLineW.restype = ctypes.c_wchar_p
Path(__file__).resolve().parent.parent.joinpath('spawn.json').write_text(
    json.dumps({'argv': sys.argv[1:], 'directory': args.directory, 'port': args.port,
                'command_line': ctypes.windll.kernel32.GetCommandLineW()}), encoding='utf-8')
''')
        with socket.socket() as probe:
            probe.bind(('127.0.0.1', 0))
            port = probe.getsockname()[1]
        self.assertNotIn(port, (8765, 18879))
        result = self.run_powershell(r'''
$global:lcsLauncherHealthCalls = 0
function Invoke-RestMethod {
    param($Uri, $TimeoutSec, [switch]$UseBasicParsing)
    $global:lcsLauncherHealthCalls += 1
    if ($global:lcsLauncherHealthCalls -eq 1) { return $null }
    return [pscustomobject]@{ application='lcs-modern-local'; directory=$global:lcsLauncherTestData.directory }
}
function Start-Process {
    param($FilePath, $ArgumentList, $WindowStyle, [switch]$PassThru,
          $RedirectStandardOutput, $RedirectStandardError)
    return Microsoft.PowerShell.Management\Start-Process @PSBoundParameters -Wait
}
& (Join-Path $Fixture 'scripts/launch.ps1') -NoBrowser -Port $global:lcsLauncherTestData.port -WebRoot $global:lcsLauncherTestData.web
''', {'web': str(self.web) + '\\', 'directory': str(self.web.resolve()), 'port': port})
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        spawned = json.loads((self.root / 'spawn.json').read_text(encoding='utf-8'))
        command_line = spawned.pop('command_line')
        self.assertEqual(spawned, {
            'argv': ['--directory', str(self.web.resolve()), '--port', str(port)],
            'directory': str(self.web.resolve()), 'port': port})
        self.assertTrue((self.root / f'.local/launcher/server-{port}.pid').is_file())
        # The ownership guard also accepts the exact command line Windows
        # created, rather than only a command assembled by the test itself.
        result = self.run_stop(command_line, port=port)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(json.loads((self.root / 'stopped.json').read_text(encoding='utf-8-sig')), 12345)
        self.assertFalse((self.root / f'.local/launcher/server-{port}.pid').exists())

    def launcher_command(self, *, script=None, port=18879, executable=None):
        return (f'"{executable or sys.executable}" "{script or self.root / "scripts/serve.py"}" '
                f'--directory "{self.web}" --port {port}')

    def run_stop(self, command, *, process_exists=True, port=18879):
        self.put(f'.local/launcher/server-{port}.pid', '12345\n')
        marker = self.root / 'stopped.json'
        if marker.exists():
            marker.unlink()
        return self.run_powershell(r'''
function Get-CimInstance {
    param($ClassName, $Filter)
    if (-not $global:lcsLauncherTestData.process_exists) { return $null }
    return [pscustomobject]@{CommandLine=$global:lcsLauncherTestData.command}
}
function Stop-Process {
    param([int]$Id)
    $Id | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $global:lcsLauncherTestData.fixture 'stopped.json') -Encoding UTF8
}
& (Join-Path $Fixture 'scripts/stop.ps1') -Port $global:lcsLauncherTestData.port
''', {'command': command, 'process_exists': process_exists, 'fixture': str(self.root), 'port': port})

    def test_stop_accepts_only_the_owned_launcher_shape(self):
        for command in (self.launcher_command(),
                        self.launcher_command().replace(f'"{sys.executable}"', sys.executable, 1)):
            with self.subTest(command=command):
                result = self.run_stop(command)
                self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
                self.assertEqual(json.loads((self.root / 'stopped.json').read_text(encoding='utf-8-sig')), 12345)
                self.assertFalse(self.pid_file.exists())

    def test_stop_refuses_foreign_invocations_and_preserves_their_pid_record(self):
        expected_script = self.root / 'scripts/serve.py'
        for command in (
                self.launcher_command(script=str(expected_script) + '.backup'),
                f'"{sys.executable}" foreign.py --note "{expected_script}" --port 18879',
                self.launcher_command(port=8765),
                self.launcher_command(script=self.root / 'other checkout/scripts/serve.py'),
                self.launcher_command() + ' --note extra',
                self.launcher_command(executable=self.root / 'foreign.exe'),
                self.launcher_command().replace(' --directory ', ' --note ', 1)):
            with self.subTest(command=command):
                result = self.run_stop(command)
                self.assertNotEqual(result.returncode, 0)
                self.assertIn('No process was stopped', result.stderr)
                self.assertEqual(self.pid_file.read_text(), '12345\n')
                self.assertFalse((self.root / 'stopped.json').exists())

    def test_stop_does_not_touch_an_exited_process(self):
        result = self.run_stop(self.launcher_command(), process_exists=False)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn('already stopped', result.stdout)
        self.assertFalse((self.root / 'stopped.json').exists())


if __name__ == '__main__':
    unittest.main()
