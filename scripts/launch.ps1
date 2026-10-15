[CmdletBinding()]
param(
    [ValidateRange(1, 65535)][int]$Port = 8765,
    [switch]$NoBrowser,
    [string]$WebRoot
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'common.ps1')
$root = Get-LcsRoot
if (-not $WebRoot) {
    $packaged = Join-Path $root 'web'
    $WebRoot = if (Test-Path -LiteralPath (Join-Path $packaged 'index.html')) { $packaged } else { Join-Path $root 'upstream\build\web' }
}
$WebRoot = [System.IO.Path]::GetFullPath($WebRoot)
if (-not (Test-Path -LiteralPath (Join-Path $WebRoot 'index.html') -PathType Leaf)) {
    throw "Built game missing at $WebRoot. Run scripts\build_release.ps1 from a source checkout, or extract the complete release archive."
}
$url = "http://127.0.0.1:$Port/"
$healthUrl = "http://127.0.0.1:$Port/__lcs_launcher_health"

function Read-GameHealth {
    try {
        $response = Invoke-RestMethod -Uri $healthUrl -TimeoutSec 2 -UseBasicParsing
        if ($null -ne $response -and $response.PSObject.Properties['application'] -and $response.PSObject.Properties['directory']) { return $response }
        return $null
    } catch { return $null }
}

$health = Read-GameHealth
if ($null -ne $health) {
    if ($health.application -ne 'lcs-modern-local' -or $health.directory -ne $WebRoot) {
        throw "Port $Port is serving another game directory. Close that launcher first or use -Port with a different port. Saves belong to each browser origin."
    }
} else {
    $listener = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Loopback, $Port)
    try { $listener.Start() } catch { throw "Port $Port is occupied. Close the other server or use -Port with a different port." } finally { $listener.Stop() }
    $python = Get-LcsPython
    $logs = Join-Path $root '.local\launcher'
    New-Item -ItemType Directory -Path $logs -Force | Out-Null
    $serverScript = Join-Path $root 'scripts\serve.py'
    $arguments = @(('"' + $serverScript + '"'), '--directory', ('"' + $WebRoot + '"'), '--port', $Port)
    $process = Start-Process -FilePath $python -ArgumentList $arguments -WindowStyle Hidden -PassThru `
        -RedirectStandardOutput (Join-Path $logs "server-$Port.out.log") `
        -RedirectStandardError (Join-Path $logs "server-$Port.err.log")
    $process.Id | Set-Content -LiteralPath (Join-Path $logs "server-$Port.pid")
    for ($attempt = 0; $attempt -lt 40; $attempt++) {
        Start-Sleep -Milliseconds 150
        $health = Read-GameHealth
        if ($null -ne $health) { break }
        $process.Refresh()
        if ($process.HasExited) { throw "The local server exited. See $logs\server-$Port.err.log." }
    }
    if ($null -eq $health) { throw "Local server did not become ready. See $logs\server-$Port.err.log." }
    if ($health.application -ne 'lcs-modern-local' -or $health.directory -ne $WebRoot) {
        throw 'The local server reported an unexpected game directory.'
    }
}
Write-Host "Play Liberal Crime Squad: New Age - The Underground Edition: $url"
Write-Host 'Use the same browser and 127.0.0.1 address to retain your saves. Export a save before clearing browser data.'
if (-not $NoBrowser) { Start-Process $url }
