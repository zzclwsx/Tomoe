param([string]$ExecutablePath, [string]$ZipSpec, [string]$ZipPath, [string]$LockPath, [string]$LockReady)
$ErrorActionPreference = 'Stop'
if ($ExecutablePath) {
    Add-Type -OutputAssembly $ExecutablePath -OutputType WindowsApplication -TypeDefinition @'
using System;
using System.IO;
using System.Reflection;
using System.Threading;
[assembly: AssemblyProduct("Tomoe")]
[assembly: AssemblyFileVersion("1.0.2.0")]
public class UpdateFixture {
    public static void Main() {
        File.WriteAllText(Path.Combine(AppDomain.CurrentDomain.BaseDirectory, "started.txt"), Directory.GetCurrentDirectory());
        Thread.Sleep(4000);
    }
}
'@
}
if ($ZipSpec) {
    Add-Type -AssemblyName System.IO.Compression, System.IO.Compression.FileSystem
    $entries = [IO.File]::ReadAllText($ZipSpec, [Text.Encoding]::UTF8) | ConvertFrom-Json
    $zip = [IO.Compression.ZipFile]::Open($ZipPath, [IO.Compression.ZipArchiveMode]::Create)
    try {
        foreach ($value in $entries) {
            $entry = $zip.CreateEntry([string]$value.name)
            $stream = $entry.Open()
            try {
                $bytes = [Convert]::FromBase64String($value.base64)
                $stream.Write($bytes, 0, $bytes.Length)
            } finally { $stream.Dispose() }
        }
    } finally { $zip.Dispose() }
}
if ($LockPath) {
    $stream = [IO.File]::Open($LockPath, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::Read)
    try {
        [IO.File]::WriteAllText($LockReady, 'ready')
        Start-Sleep -Seconds 90
    } finally { $stream.Dispose() }
}
