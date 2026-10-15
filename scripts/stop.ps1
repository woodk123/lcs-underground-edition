[CmdletBinding()]
param([ValidateRange(1, 65535)][int]$Port = 8765)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'common.ps1')
$root = Get-LcsRoot
$pidFile = Join-Path $root ".local\launcher\server-$Port.pid"
if (-not (Test-Path -LiteralPath $pidFile -PathType Leaf)) {
    Write-Host "No local launcher PID is recorded for port $Port."
    return
}
$serverProcessId = [int](Get-Content -LiteralPath $pidFile -Raw).Trim()
$process = Get-CimInstance Win32_Process -Filter "ProcessId = $serverProcessId"
if ($null -eq $process) { Write-Host 'The local server has already stopped.'; return }
$expectedScript = Join-Path $root 'scripts\serve.py'
if (-not $process.CommandLine -or -not $process.CommandLine.Contains($expectedScript) -or $process.CommandLine -notmatch "--port\s+$Port(\s|$)") {
    throw 'The recorded process no longer matches this launcher. No process was stopped.'
}
Stop-Process -Id $serverProcessId
Remove-Item -LiteralPath $pidFile
Write-Host "Stopped the local game server on port $Port. Browser saves remain available."
