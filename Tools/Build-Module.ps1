#Requires -Version 7.2
<#
.SYNOPSIS
    Stages ConditionalAccessBuilder for PowerShell Gallery validation and publication.
.DESCRIPTION
    Does not publish, authenticate to a tenant, or execute the GUI.
    Copies an explicit list of module files into dist/ConditionalAccessBuilder.
    No ZIP release package, developer tests, tokens, logs or tenant data is included.
#>
[CmdletBinding()]
param(
    [string]$OutputDirectory = (Join-Path (Split-Path $PSScriptRoot -Parent) 'dist')
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$root = Split-Path $PSScriptRoot -Parent
$moduleName = 'ConditionalAccessBuilder'
$destination = Join-Path $OutputDirectory $moduleName
$files = @(
    'Packaging/ConditionalAccessBuilder.psd1',
    'Packaging/ConditionalAccessBuilder.psm1',
    'Start-EntraCABuilder.ps1',
    'GUI/MainWindow.xaml',
    'Modules/Graph.psm1',
    'Modules/Policy.psm1',
    'Baselines/policy-catalogue.json',
    'LICENSE',
    'README.md',
    'SECURITY.md'
)

# Do not copy directories recursively or include files from the working folder.
foreach ($relative in $files) {
    if ($relative -match '^/|(^|/)\.\.(/|$)|(^|/)(?:dist|Reports|Logs|artifacts)(/|$)|\.(?:zip|pfx|p12|pem|key|xlsx|log|jsonl)$') {
        throw "Unsafe module file path: $relative"
    }
    $source = Join-Path $root $relative
    if (-not (Test-Path -LiteralPath $source -PathType Leaf)) {
        throw "Missing module source: $relative"
    }
    if ((Get-Item -LiteralPath $source).Attributes -band [System.IO.FileAttributes]::ReparsePoint) {
        throw "Symlinks are not permitted in the module package: $relative"
    }
}

# Fail closed on malformed manifests before producing a publication directory.
$manifestSource = Join-Path $root 'Packaging/ConditionalAccessBuilder.psd1'
$metadata = Import-PowerShellDataFile -Path $manifestSource -ErrorAction Stop
if ([string]$metadata.ModuleVersion -ne '1.0.0' -or
    [string]$metadata.RootModule -ne 'ConditionalAccessBuilder.psm1' -or
    [string]$metadata.PrivateData.PSData.ProjectUri -ne 'https://github.com/EduardsGrebezs/Conditional-Access-Builder') {
    throw 'Unexpected module metadata. Review the module version, root module and project URL.'
}

New-Item -ItemType Directory -Path $OutputDirectory -Force | Out-Null
if (Test-Path -LiteralPath $destination) {
    Remove-Item -LiteralPath $destination -Recurse -Force
}
New-Item -ItemType Directory -Path $destination -Force | Out-Null

foreach ($relative in $files) {
    $targetRelative = $relative -replace '^Packaging/', ''
    $target = Join-Path $destination $targetRelative
    New-Item -ItemType Directory -Path (Split-Path $target -Parent) -Force | Out-Null
    Copy-Item -LiteralPath (Join-Path $root $relative) -Destination $target -ErrorAction Stop
}
Write-Host "Gallery module staged at: $destination"
Write-Host 'No module was published. Validate with Test-ModuleManifest, Import-Module and the Windows GUI.'
