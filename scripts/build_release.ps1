[CmdletBinding()]
param([switch]$Nightly)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'common.ps1')
$root = Get-LcsRoot
$project = Join-Path $root 'upstream'
$flutter = Get-LcsFlutter
$dart = Join-Path $root '.tools\flutter\bin\dart.bat'
$python = Get-LcsPython
$stamp = [DateTime]::UtcNow.ToString('yyyyMMdd-HHmmss')
$reportDir = Join-Path $root ".local\reports\build-$stamp"
New-Item -ItemType Directory -Path $reportDir -Force | Out-Null
$steps = [System.Collections.Generic.List[object]]::new()
$reportPath = Join-Path $reportDir 'build-info.json'
$sourceCommit = Get-LcsSourceCommit -Root $root

function Write-BuildReport([string]$Status) {
    $report = [ordered]@{
        status = $Status
        timestamp_utc = [DateTime]::UtcNow.ToString('o')
        project = 'LiberalCrimeSquad-NewAge-UndergroundEdition'
        display_name = 'Liberal Crime Squad: New Age ' + [char]0x2014 + ' The Underground Edition'
        source_commit = $sourceCommit
        toolchain = (Get-Content -LiteralPath (Join-Path $root 'scripts\toolchain.json') -Raw | ConvertFrom-Json)
        steps = @($steps.ToArray())
        manual_qa = 'Pending. Automated build success does not establish production readiness; see docs/RELEASE_CHECKLIST.md.'
    }
    $report | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $reportPath -Encoding UTF8
}

function Invoke-BuildStep([string]$Name, [string]$Executable, [string[]]$Arguments) {
    if (-not (Test-Path -LiteralPath $Executable -PathType Leaf)) { throw "Required tool missing: $Executable" }
    Write-Host "`n[$Name]"
    $log = Join-Path $reportDir "$Name.log"
    $watch = [System.Diagnostics.Stopwatch]::StartNew()
    $previousPreference = $ErrorActionPreference
    try {
        # Native tools may write benign diagnostics on stderr; their exit code is authoritative.
        $ErrorActionPreference = 'Continue'
        & $Executable @Arguments 2>&1 | Tee-Object -FilePath $log | Out-Host
        $code = $LASTEXITCODE
    } finally {
        $ErrorActionPreference = $previousPreference
        $watch.Stop()
    }
    $steps.Add([ordered]@{ name = $Name; arguments = $Arguments; exit_code = $code; elapsed_seconds = [Math]::Round($watch.Elapsed.TotalSeconds, 2); log = "$Name.log" })
    Write-BuildReport 'in_progress'
    if ($code -ne 0) { throw "$Name failed with exit $code. See $log." }
}

Push-Location -LiteralPath $project
try {
    Invoke-BuildStep '01-dependencies' $flutter @('--suppress-analytics', 'pub', 'get')
    Invoke-BuildStep '02-serialization' $dart @('run', 'build_runner', 'build')
    Invoke-BuildStep '03-tests' $flutter @('--suppress-analytics', 'test', '--no-pub')
    Invoke-BuildStep '04-focused-analysis' $flutter @(
        '--suppress-analytics', 'analyze', '--no-pub',
        'lib/modern', 'lib/main.dart', 'lib/engine/console.dart',
        'lib/engine/console_widget.dart', 'lib/engine/console_char.dart', 'lib/engine/console_graphic.dart'
    )
    # Keep legacy infos/warnings visible in a separate full-project report. Errors remain fatal.
    Invoke-BuildStep '05-full-analysis' $flutter @('--suppress-analytics', 'analyze', '--no-pub', '--no-fatal-infos', '--no-fatal-warnings')
    Invoke-BuildStep '06-web-release' $flutter @('--suppress-analytics', 'build', 'web', '--release', '--no-pub', '--no-wasm-dry-run', '--base-href', '/')
    # The upstream injector requires a fresh build and must run exactly once per build.
    Invoke-BuildStep '07-offline-manifest' $dart @('run', 'tool/inject_service_worker.dart', 'build/web')
    if ($Nightly) {
        Invoke-BuildStep '08-windows-release' $flutter @('--suppress-analytics', 'build', 'windows', '--release', '--no-pub')
    }
    Write-BuildReport 'automated_checks_passed_manual_qa_pending'
    if ($Nightly) {
        Invoke-BuildStep '09-package-nightly' $python @(
            (Join-Path $root 'scripts\package_nightly.py'), '--root', $root, '--report', $reportDir
        )
    } else {
        Invoke-BuildStep '08-package' $python @(
            (Join-Path $root 'scripts\package_release.py'), '--root', $root, '--report', $reportDir
        )
    }
    Write-BuildReport 'automated_checks_and_packaging_passed_manual_qa_pending'
    Write-Host "`nRelease artifacts are under $root\release. Build evidence: $reportDir"
    Write-Host 'Complete docs/RELEASE_CHECKLIST.md against the package before describing this build as production ready.'
} catch {
    Write-BuildReport 'failed'
    throw
} finally {
    Pop-Location
}
