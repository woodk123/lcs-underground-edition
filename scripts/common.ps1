Set-StrictMode -Version Latest

function Get-LcsRoot {
    return [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
}

function Get-LcsPython {
    $installed = 'C:\Users\sheer\AppData\Local\Programs\Python\Python312\python.exe'
    if (Test-Path -LiteralPath $installed -PathType Leaf) { return $installed }
    $found = Get-Command python.exe -ErrorAction SilentlyContinue
    if ($null -ne $found) { return $found.Source }
    throw 'Python 3 is required for the local launcher and packaging. Install Python, then reopen the launcher.'
}

function Get-LcsFlutter {
    $root = Get-LcsRoot
    $flutter = Join-Path $root '.tools\flutter\bin\flutter.bat'
    if (-not (Test-Path -LiteralPath $flutter -PathType Leaf)) {
        throw 'Pinned Flutter SDK missing. Follow README.md development setup; playing a packaged release only requires Python.'
    }
    $pin = Get-Content -LiteralPath (Join-Path $root 'scripts\toolchain.json') -Raw | ConvertFrom-Json
    $raw = & $flutter --suppress-analytics --version --machine
    if ($LASTEXITCODE -ne 0) { throw 'Could not query the local Flutter SDK.' }
    $version = ($raw -join "`n") | ConvertFrom-Json
    if ($version.frameworkVersion -ne $pin.flutter_version -or $version.frameworkRevision -ne $pin.flutter_revision) {
        throw "Flutter pin mismatch. Expected $($pin.flutter_version) at $($pin.flutter_revision); got $($version.frameworkVersion) at $($version.frameworkRevision)."
    }
    return $flutter
}
