#Requires -Version 7.2
<#
.SYNOPSIS
    Builds portable and PowerShell Gallery packages from an explicit runtime allowlist.
.DESCRIPTION
    Safe to run without network access. Does not publish to the Gallery or GitHub.
    Reports and user secrets are not packaged. Requires Windows for launch/testing,
    but packaging itself is platform-neutral under PowerShell 7.
#>
[CmdletBinding()]
param([string]$OutputDirectory = (Join-Path (Split-Path $PSScriptRoot -Parent) 'dist'))
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$runtime = @(
    'Start-EntraCABuilder.ps1', 'GUI/MainWindow.xaml',
    'Modules/Graph.psm1', 'Modules/Policy.psm1',
    'Baselines/policy-catalogue.json', 'LICENSE'
)
$portable = @($runtime) + @('README.md')
$module = @($runtime) + @('Packaging/ConditionalAccessBuilder.psd1', 'Packaging/ConditionalAccessBuilder.psm1')

foreach ($rel in @($portable + $module | Sort-Object -Unique)) {
    if ($rel.Contains('\') -or $rel.StartsWith('/') -or
        $rel -match '(^|/)\.\.(/|$)|(^|/)(?:Reports|Logs|dist|artifacts)(/|$)|\.(?:zip|jsonl|pfx|pem|xlsx|log)$') {
        throw "Unsafe release path: $rel"
    }
    $file = Join-Path $root $rel
    if (-not (Test-Path -LiteralPath $file -PathType Leaf)) { throw "Missing distribution file: $rel" }
    if ((Get-Item -LiteralPath $file).Attributes -band [System.IO.FileAttributes]::ReparsePoint) {
        throw "Refusing symlink in distribution: $rel"
    }
}

New-Item -ItemType Directory -Path $OutputDirectory -Force | Out-Null
$staging = Join-Path $OutputDirectory 'staging'
if (Test-Path $staging) { Remove-Item -LiteralPath $staging -Recurse -Force }
$portableRoot = Join-Path $staging 'Conditional-Access-Builder'
$moduleRoot = Join-Path $staging 'ConditionalAccessBuilder'
foreach ($path in @($portableRoot,$moduleRoot)) { New-Item -ItemType Directory -Path $path -Force | Out-Null }

foreach ($rel in $portable) {
    $target = Join-Path $portableRoot $rel
    New-Item -ItemType Directory -Path (Split-Path $target -Parent) -Force | Out-Null
    Copy-Item -LiteralPath (Join-Path $root $rel) -Destination $target
}
foreach ($rel in $module) {
    $targetRel = $rel -replace '^Packaging/', ''
    $target = Join-Path $moduleRoot $targetRel
    New-Item -ItemType Directory -Path (Split-Path $target -Parent) -Force | Out-Null
    Copy-Item -LiteralPath (Join-Path $root $rel) -Destination $target
}

$packagePaths = @(
    @{Path=$portableRoot; Name='Conditional-Access-Builder-v1.0.0-Portable.zip'},
    @{Path=$moduleRoot; Name='ConditionalAccessBuilder-v1.0.0-PSGallery-review.zip'}
)
foreach ($item in $packagePaths) {
    $zip = Join-Path $OutputDirectory $item.Name
    if (Test-Path -LiteralPath $zip) { Remove-Item -LiteralPath $zip -Force }
    Compress-Archive -LiteralPath $item.Path -DestinationPath $zip -CompressionLevel Optimal
    $hash = (Get-FileHash -LiteralPath $zip -Algorithm SHA256).Hash.ToLowerInvariant()
    "$hash  $($item.Name)" | Set-Content -LiteralPath (Join-Path $OutputDirectory ($item.Name + '.sha256')) -Encoding ascii
    Write-Host "Built: $zip"
}
Write-Host "PowerShell Gallery module folder for Publish-Module: $moduleRoot"
Write-Host 'No publishing action has been performed.'
