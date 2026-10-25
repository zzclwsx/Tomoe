param([Parameter(Mandatory = $true)][string]$ConfigPath)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$utf8 = New-Object System.Text.UTF8Encoding($false)
$workspace = [IO.Path]::GetFullPath($PSScriptRoot)
$statusPath = Join-Path $workspace 'status.json'
$logPath = Join-Path $workspace 'update.log'
$changed = New-Object 'System.Collections.Generic.List[object]'
$ready = $false
$committed = $false
$approved = $false
$validWorkspace = $false
$config = $null

function Write-Status([string]$State, [string]$Message) {
    $json = @{ state = $State; message = $Message; log = $logPath } | ConvertTo-Json -Compress
    $pending = Join-Path $workspace 'status.pending'
    [IO.File]::WriteAllText($pending, $json, $utf8)
    Move-Item -LiteralPath $pending -Destination $statusPath -Force
}
function Write-Log([string]$Message) {
    [IO.File]::AppendAllText($logPath, "$(Get-Date -Format o) $Message`r`n", $utf8)
}
function File-Hash([string]$Path) {
    $algorithm = [Security.Cryptography.SHA256]::Create()
    $stream = [IO.File]::OpenRead($Path)
    try { return [BitConverter]::ToString($algorithm.ComputeHash($stream)).Replace('-', '') }
    finally { $stream.Dispose(); $algorithm.Dispose() }
}
function Child-Path([string]$Root, [string]$Relative) {
    $prefix = [IO.Path]::GetFullPath($Root).TrimEnd('\') + '\'
    $resolved = [IO.Path]::GetFullPath((Join-Path $Root $Relative))
    if (!$resolved.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase)) {
        throw 'An update path escapes its intended directory.'
    }
    return $resolved
}
function Assert-NoLinks([string]$Path) {
    $current = [IO.Path]::GetFullPath($Path)
    while ($current) {
        if (Test-Path -LiteralPath $current) {
            $item = Get-Item -LiteralPath $current -Force
            if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
                throw 'Update paths must not contain junctions or symbolic links.'
            }
        }
        $parent = [IO.Directory]::GetParent($current)
        if ($null -eq $parent) { break }
        $current = $parent.FullName
    }
}
function Copy-WithRetry([string]$Source, [string]$Destination) {
    for ($attempt = 0; $attempt -lt 15; $attempt++) {
        try {
            Assert-NoLinks $Destination
            [IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($Destination)) | Out-Null
            Copy-Item -LiteralPath $Source -Destination $Destination -Force
            return
        } catch {
            if ($attempt -eq 14) { throw }
            Start-Sleep -Milliseconds 500
        }
    }
}
function Remove-WorkDirectory([string]$Relative) {
    if (!$validWorkspace) { throw 'The update workspace has not been validated.' }
    # Resolve and check the exact recursive target before deletion.
    $resolved = Child-Path $workspace $Relative
    Assert-NoLinks $resolved
    if (Test-Path -LiteralPath $resolved) { Remove-Item -LiteralPath $resolved -Recurse -Force }
}
function Restart-App([string]$Directory) {
    $start = New-Object Diagnostics.ProcessStartInfo
    $start.FileName = Child-Path $Directory 'tomoe.exe'
    $start.WorkingDirectory = $Directory
    $start.UseShellExecute = $false
    $app = [Diagnostics.Process]::Start($start)
    if ($app.WaitForExit(2000)) { throw 'The updated application exited immediately.' }
    $app.Dispose()
}

try {
    if (![IO.Path]::GetFileName($workspace).StartsWith('tomoe-update-')) { throw 'Invalid update workspace.' }
    Assert-NoLinks $workspace
    $validWorkspace = $true
    if ([IO.Path]::GetFullPath($ConfigPath) -ne (Join-Path $workspace 'config.json')) { throw 'Invalid update configuration path.' }
    $config = [IO.File]::ReadAllText($ConfigPath, $utf8) | ConvertFrom-Json
    $originalExecutable = [IO.Path]::GetFullPath([string]$config.originalExecutable)
    if ([IO.Path]::GetFileName($originalExecutable) -ne 'tomoe.exe' -or
        [Diagnostics.FileVersionInfo]::GetVersionInfo($originalExecutable).ProductName -ne 'Tomoe') {
        throw 'The running application is not a Tomoe installation.'
    }
    $target = [IO.Path]::GetFullPath([string]$config.targetDirectory).TrimEnd('\')
    if ($target -eq [IO.Path]::GetPathRoot($target).TrimEnd('\')) { throw 'Cannot update a drive root.' }
    Assert-NoLinks $target
    $targetPrefix = $target + '\'
    if ($workspace.StartsWith($targetPrefix, [StringComparison]::OrdinalIgnoreCase) -or
        $target.StartsWith($workspace + '\', [StringComparison]::OrdinalIgnoreCase) -or $target -eq $workspace) {
        throw 'The installation and update workspace must be separate.'
    }
    if (!(Test-Path -LiteralPath $target -PathType Container)) { throw 'The installation directory does not exist.' }
    $existingFiles = @(Get-ChildItem -LiteralPath $target -Force)
    $oldExecutable = Child-Path $target 'tomoe.exe'
    if ($existingFiles.Count -gt 0) {
        if (!(Test-Path -LiteralPath $oldExecutable -PathType Leaf) -or
            [Diagnostics.FileVersionInfo]::GetVersionInfo($oldExecutable).ProductName -ne 'Tomoe') {
            throw 'Choose an empty directory or an existing Tomoe installation.'
        }
    }
    $archivePath = [IO.Path]::GetFullPath([string]$config.archivePath)
    if ([string]$config.expectedHash -notmatch '^[a-fA-F0-9]{64}$') { throw 'Missing SHA-256 checksum.' }
    if ((File-Hash $archivePath) -ne $config.expectedHash) {
        throw 'The downloaded package failed SHA-256 verification.'
    }
    $stage = Child-Path $workspace 'stage'
    $backup = Child-Path $workspace 'backup'
    [IO.Directory]::CreateDirectory($stage) | Out-Null
    [IO.Directory]::CreateDirectory($backup) | Out-Null
    Add-Type -AssemblyName System.IO.Compression, System.IO.Compression.FileSystem
    $archive = [IO.Compression.ZipFile]::OpenRead($archivePath)
    $seen = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
    $files = New-Object 'System.Collections.Generic.List[string]'
    $expandedBytes = 0L
    try {
        foreach ($entry in $archive.Entries) {
            $relative = $entry.FullName.Replace('/', '\').TrimEnd('\')
            if (!$relative -or [IO.Path]::IsPathRooted($relative) -or $relative.Contains(':') -or $relative.Contains([char]0)) {
                throw 'The package contains an invalid file path.'
            }
            foreach ($segment in $relative.Split('\')) {
                if (!$segment -or $segment -eq '.' -or $segment -eq '..' -or $segment.EndsWith('.') -or $segment.EndsWith(' ') -or
                    $segment -match '[<>"|?*\x00-\x1f]' -or $segment -match '^(CON|PRN|AUX|NUL|COM[1-9]|LPT[1-9])(\.|$)') {
                    throw 'The package contains an unsafe Windows file name.'
                }
            }
            if ((($entry.ExternalAttributes -shr 16) -band 0xf000) -eq 0xa000) { throw 'Package symbolic links are not supported.' }
            $destination = Child-Path $stage $relative
            $null = Child-Path $target $relative
            if (!$seen.Add($relative)) { throw 'The package contains duplicate paths.' }
            if ($entry.FullName.EndsWith('/') -or $entry.FullName.EndsWith('\')) {
                [IO.Directory]::CreateDirectory($destination) | Out-Null
                continue
            }
            $expandedBytes += $entry.Length
            if ($expandedBytes -gt 2147483648L -or $files.Count -ge 20000) { throw 'The package is unexpectedly large.' }
            [IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($destination)) | Out-Null
            [IO.Compression.ZipFileExtensions]::ExtractToFile($entry, $destination, $false)
            $files.Add($relative)
        }
    } finally { $archive.Dispose() }
    foreach ($required in @('tomoe.exe', 'flutter_windows.dll', 'data\app.so')) {
        if (!(Test-Path -LiteralPath (Child-Path $stage $required) -PathType Leaf)) { throw 'The package is missing application files.' }
    }
    if ([Diagnostics.FileVersionInfo]::GetVersionInfo((Child-Path $stage 'tomoe.exe')).ProductName -ne 'Tomoe') {
        throw 'The package is not a Tomoe application.'
    }
    # Check every destination before notifying the application to exit.
    foreach ($relative in $files) {
        $destination = Child-Path $target $relative
        Assert-NoLinks $destination
        if (Test-Path -LiteralPath $destination -PathType Container) { throw 'An update file conflicts with an existing directory.' }
        $parentDirectory = [IO.Path]::GetDirectoryName($destination)
        while ($parentDirectory.StartsWith($targetPrefix, [StringComparison]::OrdinalIgnoreCase)) {
            if ([IO.File]::Exists($parentDirectory)) { throw 'An update directory conflicts with an existing file.' }
            $parentDirectory = [IO.Path]::GetDirectoryName($parentDirectory)
        }
    }
    $probe = Child-Path $target ('.tomoe-write-' + [Guid]::NewGuid().ToString('N'))
    [IO.File]::WriteAllText($probe, 'ok')
    Remove-Item -LiteralPath $probe -Force
    $parentProcess = [Diagnostics.Process]::GetProcessById([int]$config.parentPid)
    Write-Log "Prepared update for $target"
    Write-Status 'ready' 'The application can now exit.'
    $ready = $true
    if (!$parentProcess.WaitForExit(90000)) { throw 'The application did not exit; no files were changed.' }
    $parentProcess.Dispose()
    # Closing/cancelling preparation must not install an update on a later exit.
    $request = Join-Path $workspace 'install.request'
    if (!(Test-Path -LiteralPath $request) -or [IO.File]::ReadAllText($request) -ne 'install') {
        throw 'The update was cancelled; no files were changed.'
    }
    $approved = $true
    # Snapshot all overwritten files before touching the installation.
    foreach ($relative in $files) {
        $destination = Child-Path $target $relative
        $existed = Test-Path -LiteralPath $destination -PathType Leaf
        if ($existed) { Copy-WithRetry $destination (Child-Path $backup $relative) }
        $changed.Add(@{ path = $relative; existed = $existed })
    }
    [IO.File]::WriteAllText((Join-Path $workspace 'backup.json'), ($changed | ConvertTo-Json), $utf8)
    foreach ($relative in $files) {
        Copy-WithRetry (Child-Path $stage $relative) (Child-Path $target $relative)
    }
    if ($config.restart) { Restart-App $target }
    $committed = $true
    Write-Status 'success' 'The update was installed.'
    Write-Log 'Update installed successfully.'
    Remove-WorkDirectory 'stage'
    Remove-WorkDirectory 'backup'
    # Only remove a downloaded package from our dedicated temporary download directory.
    $downloadRoot = [IO.Path]::GetFullPath((Join-Path ([IO.Path]::GetTempPath()) 'Tomoe\updates')).TrimEnd('\') + '\'
    if ($archivePath.StartsWith($downloadRoot, [StringComparison]::OrdinalIgnoreCase)) {
        Assert-NoLinks $archivePath
        Remove-Item -LiteralPath $archivePath -Force
    }
    exit 0
} catch {
    $failure = $_.Exception.Message
    Write-Log $failure
    if ($committed) { exit 0 } # Cleanup failure must not undo an installed update.
    $restored = $true
    for ($index = $changed.Count - 1; $index -ge 0; $index--) {
        $entry = $changed[$index]
        try {
            $destination = Child-Path $target $entry.path
            Assert-NoLinks $destination
            if ($entry.existed) {
                $original = Child-Path $backup $entry.path
                if (!(Test-Path -LiteralPath $destination -PathType Leaf) -or
                    (File-Hash $destination) -ne (File-Hash $original)) {
                    Copy-WithRetry $original $destination
                }
            } elseif (Test-Path -LiteralPath $destination -PathType Leaf) {
                Remove-Item -LiteralPath $destination -Force
            }
        } catch { $restored = $false; Write-Log $_.Exception.Message }
    }
    $state = if ($changed.Count -gt 0 -and $restored) { 'rolledBack' } elseif (!$restored) { 'recoveryRequired' } else { 'failed' }
    if ($changed.Count -eq 0) {
        try { Remove-WorkDirectory 'stage'; Remove-WorkDirectory 'backup' }
        catch { Write-Log $_.Exception.Message }
    }
    Write-Status $state $failure
    if ($approved -and $null -ne $config -and $config.showError) {
        Add-Type -AssemblyName System.Windows.Forms
        $recovery = if ($restored) { '已保留或恢复旧版文件。' } else { '自动恢复未完成，请保留备份并联系维护者。' }
        $message = "更新失败，$recovery`r`n错误：$failure`r`n日志和备份：$workspace"
        [Windows.Forms.MessageBox]::Show($message, '同映更新', 'OK', 'Error') | Out-Null
    }
    if ($changed.Count -gt 0 -and $restored -and $config.restart -and (Test-Path -LiteralPath $originalExecutable)) {
        try { Restart-App ([IO.Path]::GetDirectoryName($originalExecutable)) } catch { Write-Log $_.Exception.Message }
    }
    exit 1
}
