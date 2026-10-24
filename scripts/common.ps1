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
    param([version]$MinimumVersion = [version]'3.9')

    if ($null -eq $MinimumVersion -or $MinimumVersion -lt [version]'3.9') {
        throw 'The minimum supported Python version cannot be earlier than 3.9.'
    }
    $attempts = [Collections.Generic.List[string]]::new()
    $seen = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    # Isolated, site-free and bytecode-free: probing must not run user startup
    # hooks or create files in an interpreter, project or SDK directory.
    $probeCode = "import json,sys;print(json.dumps({'version':list(sys.version_info[:3]),'executable':sys.executable}))"
    foreach ($name in @('python.exe', 'python3.exe', 'py.exe')) {
        $commands = @(Get-Command $name -All -CommandType Application -ErrorAction SilentlyContinue)
        foreach ($command in $commands) {
            $candidate = [string]$command.Source
            if (-not $candidate -or -not $seen.Add($candidate)) { continue }
            $process = $null
            $started = $false
            try {
                $start = [Diagnostics.ProcessStartInfo]::new()
                $start.FileName = $candidate
                $start.Arguments = '-I -S -B -c "' + $probeCode + '"'
                if ($name -eq 'py.exe') { $start.Arguments = '-3 ' + $start.Arguments }
                $start.UseShellExecute = $false
                $start.CreateNoWindow = $true
                $start.RedirectStandardOutput = $true
                $start.RedirectStandardError = $true
                # Both modern install-manager aliases and the legacy launcher
                # must only inspect installed runtimes, never acquire one.
                $start.EnvironmentVariables['PYTHON_MANAGER_AUTOMATIC_INSTALL'] = 'false'
                $start.EnvironmentVariables.Remove('PYLAUNCHER_ALLOW_INSTALL')
                $start.EnvironmentVariables.Remove('PYLAUNCHER_ALWAYS_INSTALL')
                $process = [Diagnostics.Process]::new()
                $process.StartInfo = $start
                $started = $process.Start()
                if (-not $started) { throw 'Probe could not start.' }
                $stdout = $process.StandardOutput.ReadToEndAsync()
                $stderr = $process.StandardError.ReadToEndAsync()
                if (-not $process.WaitForExit(5000)) { throw 'Probe timed out after 5 seconds.' }
                if (-not $stdout.Wait(1000) -or -not $stderr.Wait(1000)) { throw 'Probe output did not close.' }
                if ($process.ExitCode -ne 0) {
                    $failure = ($stderr.Result -replace '\s+', ' ').Trim()
                    if ($failure.Length -gt 160) { $failure = $failure.Substring(0, 160) }
                    throw "Probe exited with code $($process.ExitCode). $failure"
                }
                $probe = $stdout.Result | ConvertFrom-Json -ErrorAction Stop
                if ($null -eq $probe -or $null -eq $probe.PSObject.Properties['version'] -or
                    $null -eq $probe.PSObject.Properties['executable']) { throw 'Invalid interpreter probe response.' }
                $parts = @($probe.version)
                if ($parts.Count -ne 3 -or @($parts | Where-Object { $_ -isnot [int] -and $_ -isnot [long] }).Count) {
                    throw 'Invalid interpreter version.'
                }
                $detected = [version]($parts -join '.')
                if ($detected -lt $MinimumVersion) { throw "Python $detected is below required $MinimumVersion." }
                $executable = $probe.executable
                if ($executable -isnot [string] -or -not [IO.Path]::IsPathRooted($executable) -or
                    -not (Test-Path -LiteralPath $executable -PathType Leaf)) { throw 'Interpreter executable is missing or not absolute.' }
                return [IO.Path]::GetFullPath($executable)
            } catch {
                $reason = ($_.Exception.Message -replace '\s+', ' ').Trim()
                if ($reason.Length -gt 240) { $reason = $reason.Substring(0, 240) }
                $attempts.Add("$candidate ($reason)")
            } finally {
                if ($null -ne $process) {
                    if ($started -and -not $process.HasExited) {
                        try {
                            if ($null -ne $process.GetType().GetMethod('Kill', [type[]]@([bool]))) { $process.Kill($true) }
                            else {
                                # Windows PowerShell's .NET Framework cannot kill
                                # descendants. Target only this still-live owned
                                # probe; a py.exe wrapper may have started Python.
                                $cleanup = [Diagnostics.Process]::new()
                                $cleanupStarted = $false
                                try {
                                    $cleanup.StartInfo.FileName = Join-Path ([Environment]::SystemDirectory) 'taskkill.exe'
                                    $cleanup.StartInfo.Arguments = "/PID $($process.Id) /T /F"
                                    $cleanup.StartInfo.UseShellExecute = $false
                                    $cleanup.StartInfo.CreateNoWindow = $true
                                    $cleanup.StartInfo.RedirectStandardOutput = $true
                                    $cleanup.StartInfo.RedirectStandardError = $true
                                    $cleanupStarted = $cleanup.Start()
                                    if ($cleanupStarted) {
                                        $cleanupOut = $cleanup.StandardOutput.ReadToEndAsync()
                                        $cleanupError = $cleanup.StandardError.ReadToEndAsync()
                                        if (-not $cleanup.WaitForExit(3000)) { $cleanup.Kill() }
                                        [void]$cleanupOut.Wait(500)
                                        [void]$cleanupError.Wait(500)
                                    }
                                } finally {
                                    if ($cleanupStarted -and -not $cleanup.HasExited) {
                                        try { $cleanup.Kill() } catch { }
                                    }
                                    $cleanup.Dispose()
                                }
                            }
                        } catch { }
                        try {
                            if (-not $process.HasExited) { $process.Kill() }
                            [void]$process.WaitForExit(1000)
                        } catch { }
                    }
                    $process.Dispose()
                }
            }
        }
    }
    $detail = if ($attempts.Count) { ' Tried: ' + ($attempts -join '; ') } else { ' No Python executables were found on PATH.' }
    throw "Python $MinimumVersion or newer is required. Install a supported Python or correct PATH, then reopen the launcher.$detail"
}

function Get-LcsFlutter {
    $root = Get-LcsRoot
    $flutter = Join-Path $root '.tools\flutter\bin\flutter.bat'
    if (-not (Test-Path -LiteralPath $flutter -PathType Leaf)) {
        throw 'Pinned Flutter SDK missing. Follow docs/BUILDING.md; the browser player package requires Python but no Flutter SDK.'
    }
    $pin = Get-Content -LiteralPath (Join-Path $root 'scripts\toolchain.json') -Raw | ConvertFrom-Json
    # A cold SDK can print bootstrap progress before --machine JSON. Capture
    # both streams so this function still returns only the verified tool path.
    $previousPreference = $ErrorActionPreference
    try {
        $ErrorActionPreference = 'Continue'
        $bootstrapOutput = & $flutter --suppress-analytics --version 2>&1
        $bootstrapCode = $LASTEXITCODE
    } finally {
        $ErrorActionPreference = $previousPreference
    }
    if ($bootstrapCode -ne 0) {
        throw "Flutter SDK bootstrap failed ($bootstrapCode). $($bootstrapOutput -join "`n")"
    }
    $raw = & $flutter --suppress-analytics --version --machine
    if ($LASTEXITCODE -ne 0) { throw 'Could not query the local Flutter SDK.' }
    $version = ($raw -join "`n") | ConvertFrom-Json
    if ($version.frameworkVersion -ne $pin.flutter_version -or $version.frameworkRevision -ne $pin.flutter_revision) {
        throw "Flutter pin mismatch. Expected $($pin.flutter_version) at $($pin.flutter_revision); got $($version.frameworkVersion) at $($version.frameworkRevision)."
    }
    return $flutter
}
