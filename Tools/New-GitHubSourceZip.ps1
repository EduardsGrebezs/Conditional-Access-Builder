#Requires -Version 7.2
<#[.SYNOPSIS
  Builds a source-only release archive using an explicit allowlist.
  No tenant data, private workbook or prior build artifacts are packaged.
#>
[CmdletBinding()]
param(
    [string]$OutputDirectory = (Join-Path (Split-Path $PSScriptRoot -Parent) 'dist')
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$prefix = 'Conditional-Access-Builder'
$version = 'v1.0.0'
$files = @(
    '.gitignore', '.gitattributes',
    '.github/workflows/pester.yml',
    'Start-EntraCABuilder.ps1',
    'GUI/MainWindow.xaml',
    'Modules/Graph.psm1', 'Modules/Policy.psm1',
    'Baselines/policy-catalogue.json',
    'README.md', 'LICENSE', 'SECURITY.md',
    'Tools/New-GitHubSourceZip.ps1',
    'Tools/Build-Module.ps1',
    'Packaging/ConditionalAccessBuilder.psd1', 'Packaging/ConditionalAccessBuilder.psm1'
)
$files += @(Get-ChildItem -LiteralPath (Join-Path $root 'Tests') -Filter '*.Tests.ps1' -File | Sort-Object Name | ForEach-Object { "Tests/$($_.Name)" })

# Explicitly reject any high-risk paths and extensions even if they are later
# accidentally added to the allowlist.
foreach ($relative in $files) {
    $normalized = $relative.Replace('\','/')
    if ($normalized -match '(^/|(^|/)\.\.(?:/|$)|(^|/)(?:\.git|\.env|Secrets|Logs|dist|artifacts)(?:/|$))' -or
        $normalized -match '\.(?:zip|7z|xlsx|xlsm|csv|pfx|p12|pem|key|log|jsonl)$') {
        throw "Unsafe archive entry: $relative"
    }
    $full = Join-Path $root $relative
    if (-not (Test-Path -LiteralPath $full -PathType Leaf)) { throw "Missing release input: $relative" }
    $item = Get-Item -LiteralPath $full -Force
    if (($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) { throw "Symlink not permitted in source archive: $relative" }
}

# Cheap additional fail-closed source review; not a substitute for secret scanning.
$codeFiles = $files | Where-Object { $_ -match '\.(?:ps1|psm1)$' }
foreach ($relative in $codeFiles) {
    $content = Get-Content -LiteralPath (Join-Path $root $relative) -Raw
    if ($content -match '-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----') { throw "Private key material found in $relative" }

}

New-Item -ItemType Directory -Path $OutputDirectory -Force | Out-Null
$archivePath = Join-Path $OutputDirectory "$prefix-$version-github-source.zip"
if (Test-Path -LiteralPath $archivePath) { Remove-Item -LiteralPath $archivePath -Force }
Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem
$zip = [System.IO.Compression.ZipFile]::Open($archivePath,[System.IO.Compression.ZipArchiveMode]::Create)
try {
    foreach ($relative in ($files | Sort-Object -Unique)) {
        $entryName = "$prefix/$($relative.Replace('\','/'))"
        $full = Join-Path $root $relative
        [void][System.IO.Compression.ZipFileExtensions]::CreateEntryFromFile(
            $zip, $full, $entryName, [System.IO.Compression.CompressionLevel]::Optimal
        )
    }
}
finally { $zip.Dispose() }

$hash = (Get-FileHash -LiteralPath $archivePath -Algorithm SHA256).Hash.ToLowerInvariant()
$checksumPath = Join-Path $OutputDirectory "$prefix-$version-SHA256.txt"
"$hash  $(Split-Path $archivePath -Leaf)" | Set-Content -Path $checksumPath -Encoding ascii
Write-Host "Source archive: $archivePath"
Write-Host "SHA256:         $hash"
Write-Host "Entries:        $($files.Count)"
Write-Host "Checksum file:  $checksumPath"
