Set-StrictMode -Version Latest

function Get-LcsRoot {
    return [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
}

function Get-LcsSourceCommit([string]$Root = (Get-LcsRoot)) {
    # Release source archives deliberately omit .git. Use their recorded
    # snapshot identity instead of accidentally consulting a parent repository.
    if (Test-Path -LiteralPath (Join-Path $Root '.git')) {
        $revision = git -C $Root rev-parse HEAD
        if ($LASTEXITCODE -ne 0) { throw 'Could not identify the source commit.' }
        return $revision
    }
    $metadataPath = Join-Path $Root 'BUILD_INFO.json'
    if (Test-Path -LiteralPath $metadataPath -PathType Leaf) {
        $metadata = Get-Content -LiteralPath $metadataPath -Raw | ConvertFrom-Json
        foreach ($field in @('packaging_commit', 'source_commit', 'runtime_source_commit')) {
            $property = $metadata.PSObject.Properties[$field]
            if ($null -ne $property -and $property.Value -match '^[0-9a-f]{40}$') {
                return [string]$property.Value
            }
        }
    }
    throw 'Source identity missing. Use a Git checkout or the complete source release with BUILD_INFO.json.'
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
        throw 'Pinned Flutter SDK missing. Follow docs/BUILDING.md; the browser player package requires Python but no Flutter SDK.'
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
