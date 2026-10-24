"""Real PowerShell probes skip unusable Python candidates without invoking an SDK."""
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch


SCRIPTS = Path(__file__).resolve().parent
POWERSHELL = shutil.which('powershell.exe')


@unittest.skipUnless(os.name == 'nt' and POWERSHELL, 'Windows PowerShell fixtures are required.')
class PythonSelectionTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        temporary = tempfile.TemporaryDirectory(prefix='lcs Python probe compiler ')
        cls.addClassCleanup(temporary.cleanup)
        cls.compiled = Path(temporary.name) / 'probe.exe'
        compiler = Path(temporary.name) / 'compile.ps1'
        compiler.write_text(r'''
param([string]$Output)
$ErrorActionPreference = 'Stop'
Add-Type -OutputAssembly $Output -OutputType ConsoleApplication -TypeDefinition @'
using System;
using System.Diagnostics;
using System.IO;
using System.Reflection;
using System.Threading;
public class PythonProbeFixture {
    public static int Main(string[] args) {
        if (args.Length > 0 && args[0] == "--owned-child") { Thread.Sleep(30000); return 0; }
        string path = Assembly.GetExecutingAssembly().Location;
        File.AppendAllText(path + ".calls", "probe\n");
        File.WriteAllLines(path + ".args", args);
        string[] config = File.ReadAllLines(path + ".probe");
        if (config[0] == "wrapper") {
            ProcessStartInfo start = new ProcessStartInfo(path, "--owned-child");
            start.UseShellExecute = false;
            start.CreateNoWindow = true;
            start.RedirectStandardInput = true;
            start.RedirectStandardOutput = true;
            start.RedirectStandardError = true;
            using (Process child = Process.Start(start)) {
                File.WriteAllText(path + ".parentpid", Process.GetCurrentProcess().Id.ToString());
                File.WriteAllText(path + ".childpid", child.Id.ToString());
                Thread.Sleep(30000);
            }
        }
        if (config[0] == "guard" &&
            (Environment.GetEnvironmentVariable("PYTHON_MANAGER_AUTOMATIC_INSTALL") != "false" ||
             Environment.GetEnvironmentVariable("PYLAUNCHER_ALLOW_INSTALL") != null ||
             Environment.GetEnvironmentVariable("PYLAUNCHER_ALWAYS_INSTALL") != null)) {
            File.WriteAllText(path + ".install-attempt", "Unsafe inherited installation settings");
            return 29;
        }
        if (config[0] == "hang") { Thread.Sleep(30000); }
        if (config[0] == "fail") { Console.Error.WriteLine("Unusable fixture"); return 17; }
        Console.WriteLine(config.Length > 1 ? config[1] : "not JSON");
        return 0;
    }
}
'@
''', encoding='utf-8')
        result = subprocess.run([POWERSHELL, '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File',
                                 str(compiler), '-Output', str(cls.compiled)],
                                capture_output=True, text=True, timeout=30)
        if result.returncode:
            raise AssertionError(result.stdout + result.stderr)

    def setUp(self):
        temporary = tempfile.TemporaryDirectory(prefix='lcs Python selection [fixture] ')
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name).resolve()
        self.common = self.root / 'scripts/common.ps1'
        self.common.parent.mkdir()
        shutil.copyfile(SCRIPTS / 'common.ps1', self.common)
        self.specification = self.root / 'candidates.json'
        self.runner = self.root / 'select.ps1'
        self.runner.write_text(r'''
param([string]$Common, [string]$Specification, [string]$Minimum, [string]$OwnedProbe)
$ErrorActionPreference = 'Stop'
. $Common
$script:pythonCandidates = Get-Content -LiteralPath $Specification -Raw | ConvertFrom-Json
function Get-Command {
    param($Name, [switch]$All, $CommandType, $ErrorAction)
    $entry = $script:pythonCandidates.PSObject.Properties[$Name]
    if ($null -ne $entry) {
        $paths = @($entry.Value)
        if (-not $All) { $paths = @($paths | Select-Object -First 1) }
        foreach ($path in $paths) { [pscustomobject]@{Source = $path} }
    }
}
try {
    $variables = @('PYTHON_MANAGER_AUTOMATIC_INSTALL', 'PYLAUNCHER_ALLOW_INSTALL', 'PYLAUNCHER_ALWAYS_INSTALL')
    $environmentBefore = @{}
    foreach ($name in $variables) { $environmentBefore[$name] = [Environment]::GetEnvironmentVariable($name) }
    try {
        $selected = if ($Minimum) { Get-LcsPython -MinimumVersion ([version]$Minimum) } else { Get-LcsPython }
    } finally {
        foreach ($name in $variables) {
            if ([Environment]::GetEnvironmentVariable($name) -cne $environmentBefore[$name]) {
                throw "Python selection changed caller environment variable $name."
            }
        }
    }
    $result = [ordered]@{ selected = $selected; isString = ($selected -is [string]) }
    if ($OwnedProbe) {
        $result.ownedProcesses = @(foreach ($role in @('parent', 'child')) {
            $ownedId = [int](Get-Content -LiteralPath ($OwnedProbe + ".${role}pid") -Raw)
            $owned = $null
            $alive = $false
            try { $owned = [Diagnostics.Process]::GetProcessById($ownedId); $alive = -not $owned.HasExited }
            catch [ArgumentException] { }
            finally { if ($null -ne $owned) { $owned.Dispose() } }
            @{ role = $role; alive = $alive }
        })
    }
    $result | ConvertTo-Json -Compress
} catch {
    [Console]::Error.WriteLine($_.Exception.Message)
    exit 1
}
''', encoding='utf-8')

    def candidate(self, name, *, version=None, executable=None, mode='ok', output=None):
        path = self.root / 'candidate programs with spaces' / name
        path.parent.mkdir(exist_ok=True)
        shutil.copyfile(self.compiled, path)
        response = output if output is not None else json.dumps({
            'version': list(version or sys.version_info[:3]),
            'executable': str(executable or path),
        })
        Path(str(path) + '.probe').write_text(mode + '\n' + response + '\n', encoding='utf-8')
        return path

    def select(self, candidates, *, minimum=None, owned_probe=None, timeout=20):
        self.specification.write_text(json.dumps({name: list(map(str, paths)) for name, paths in candidates.items()}),
                                      encoding='utf-8')
        command = [POWERSHELL, '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', str(self.runner),
                   '-Common', str(self.common), '-Specification', str(self.specification)]
        if minimum is not None:
            command += ['-Minimum', minimum]
        if owned_probe is not None:
            command += ['-OwnedProbe', str(owned_probe)]
            # An orphan may inherit pipe handles. File-backed capture lets a
            # failed selection return promptly so fixture cleanup can stop it.
            with (self.root / 'selection.out').open('w+') as stdout, (self.root / 'selection.err').open('w+') as stderr:
                result = subprocess.run(command, cwd=self.root.parent, stdout=stdout, stderr=stderr, timeout=timeout)
                stdout.seek(0)
                stderr.seek(0)
                return subprocess.CompletedProcess(command, result.returncode, stdout.read(), stderr.read())
        return subprocess.run(command, cwd=self.root.parent, capture_output=True, text=True, timeout=timeout)

    def cleanup_owned_probe(self, executable):
        cleanup = self.root / 'cleanup-probe.ps1'
        cleanup.write_text(r'''
param([string]$Executable)
$ErrorActionPreference = 'Stop'
foreach ($role in @('child', 'parent')) {
    $record = $Executable + ".${role}pid"
    if (-not (Test-Path -LiteralPath $record)) { continue }
    $owned = $null
    try {
        $ownedId = [int](Get-Content -LiteralPath $record -Raw)
        $owned = [Diagnostics.Process]::GetProcessById($ownedId)
        if (-not $owned.HasExited -and [IO.Path]::GetFullPath($owned.MainModule.FileName) -ieq $Executable) {
            $owned.Kill()
            if (-not $owned.WaitForExit(3000)) { throw 'Owned fixture did not stop.' }
        }
    } catch [ArgumentException] { }
    finally { if ($null -ne $owned) { $owned.Dispose() } }
}
''', encoding='utf-8')
        result = subprocess.run([POWERSHELL, '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File',
                                 str(cleanup), '-Executable', str(executable)],
                                capture_output=True, text=True, timeout=10)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def assert_selected(self, result, expected=None):
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        response = json.loads(result.stdout)
        self.assertTrue(response['isString'], 'Probe chatter must not become part of the executable result.')
        self.assertEqual(Path(response['selected']).resolve(), Path(expected or sys.executable).resolve())
        return response['selected']

    def test_real_interpreter_probe_returns_only_its_actual_executable(self):
        self.assert_selected(self.select({'python.exe': [sys.executable]}))

    def test_old_first_python_falls_through_to_another_name(self):
        old = self.candidate('old-python.exe', version=(3, 8, 20))
        self.assert_selected(self.select({'python.exe': [old], 'python3.exe': [sys.executable]}))

    def test_all_path_candidates_with_the_same_name_are_considered(self):
        old = self.candidate('first-python.exe', version=(3, 8, 20))
        self.assert_selected(self.select({'python.exe': [old, sys.executable]}))

    def test_unusable_and_malformed_candidates_do_not_hide_a_later_interpreter(self):
        failed = self.candidate('nonfunctional.exe', mode='fail')
        malformed = self.candidate('invalid-response.exe', output='startup noise instead of JSON')
        missing = self.candidate('missing-runtime.exe', executable=self.root / 'does-not-exist.exe')
        self.assert_selected(self.select({'python.exe': [failed, malformed, missing],
                                          'python3.exe': [sys.executable]}))

    def test_py_launcher_returns_the_interpreter_instead_of_the_wrapper(self):
        launcher = self.candidate('py.exe', executable=sys.executable)
        selected = self.assert_selected(self.select({'py.exe': [launcher]}))
        self.assertNotEqual(Path(selected), launcher)
        arguments = Path(str(launcher) + '.args').read_text().splitlines()
        self.assertEqual(arguments[0], '-3')
        self.assertTrue({'-I', '-S', '-B', '-c'}.issubset(arguments))

    def test_duplicate_candidate_paths_are_not_probed_repeatedly(self):
        old = self.candidate('duplicated.exe', version=(3, 8, 20))
        self.assert_selected(self.select({'python.exe': [old], 'python3.exe': [old, sys.executable]}))
        self.assertEqual(Path(str(old) + '.calls').read_text().splitlines(), ['probe'])

    def test_probe_disables_launcher_installs_without_changing_parent_settings(self):
        launcher = self.candidate('install-manager.exe', mode='guard', executable=sys.executable)
        variables = {'PYTHON_MANAGER_AUTOMATIC_INSTALL': 'true',
                     'PYLAUNCHER_ALLOW_INSTALL': '1', 'PYLAUNCHER_ALWAYS_INSTALL': '1'}
        with patch.dict(os.environ, variables):
            self.assert_selected(self.select({'py.exe': [launcher]}))
            self.assertTrue(all(os.environ[name] == value for name, value in variables.items()))
        self.assertFalse(Path(str(launcher) + '.install-attempt').exists())

    def test_builder_minimum_skips_python_310_while_player_default_accepts_it(self):
        older = self.candidate('python-310.exe', version=(3, 10, 15))
        self.assert_selected(self.select({'python.exe': [older, sys.executable]}, minimum='3.12'))
        self.assert_selected(self.select({'python.exe': [older]}), expected=older)

    def test_hung_probe_is_bounded_and_later_interpreter_is_selected(self):
        hung = self.candidate('hung-python.exe', mode='hang')
        self.assert_selected(self.select({'python.exe': [hung], 'python3.exe': [sys.executable]}, timeout=15))

    def test_hung_wrapper_and_child_are_gone_before_selector_returns(self):
        wrapper = self.candidate('hung-wrapper.exe', mode='wrapper')
        self.addCleanup(self.cleanup_owned_probe, wrapper)
        result = self.select({'python.exe': [wrapper], 'python3.exe': [sys.executable]}, owned_probe=wrapper)
        self.assert_selected(result)
        processes = json.loads(result.stdout)['ownedProcesses']
        self.assertEqual({item['role'] for item in processes}, {'parent', 'child'})
        self.assertTrue(all(not item['alive'] for item in processes), processes)

    def test_no_supported_interpreter_explains_the_required_version_and_attempt(self):
        old = self.candidate('unsupported.exe', version=(3, 8, 20))
        result = self.select({'python.exe': [old]}, minimum='3.12')
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('3.12', result.stderr)
        self.assertIn('3.8.20', result.stderr)
        self.assertIn(str(old), result.stderr)
        self.assertIn('PATH', result.stderr)
        self.assertEqual(result.stdout, '')
        result = self.select({})
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('3.9', result.stderr)
        self.assertIn('PATH', result.stderr)
        failed = self.candidate('failed.exe', mode='fail')
        result = self.select({'python.exe': [failed]})
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('17', result.stderr)
        self.assertIn('Unusable fixture', result.stderr)
        self.assertEqual(result.stdout, '')

    def test_release_builder_requests_312_before_any_build_or_packaging(self):
        older = self.candidate('python-310.exe', version=(3, 10, 15))
        specification = json.dumps({'python.exe': [str(older)]}).replace("'", "''")
        with self.common.open('a', encoding='utf-8') as common:
            common.write("\nfunction Get-LcsFlutter { throw 'SDK must not be queried before unsupported Python' }\n"
                         f"$script:pythonCandidates = '{specification}' | ConvertFrom-Json\n"
                         'function Get-Command { param($Name, [switch]$All, $CommandType, $ErrorAction)\n'
                         '  $entry = $script:pythonCandidates.PSObject.Properties[$Name]\n'
                         '  if ($null -ne $entry) { foreach ($path in @($entry.Value)) { [pscustomobject]@{Source=$path} } }\n'
                         '}\n')
        (self.root / 'BUILD_INFO.json').write_text(json.dumps({'source_commit': 'a' * 40}), encoding='utf-8')
        builder = self.root / 'scripts/build_release.ps1'
        shutil.copyfile(SCRIPTS / builder.name, builder)
        result = subprocess.run([POWERSHELL, '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', str(builder)],
                                cwd=self.root.parent, capture_output=True, text=True, timeout=20)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('3.12', result.stdout + result.stderr)
        self.assertIn('3.10.15', result.stdout + result.stderr)
        self.assertNotIn('SDK must not be queried', result.stdout + result.stderr)
        self.assertFalse((self.root / '.local').exists(), 'Unsupported Python must fail before a build starts.')
        self.assertFalse((self.root / 'release').exists())


if __name__ == '__main__':
    unittest.main()
