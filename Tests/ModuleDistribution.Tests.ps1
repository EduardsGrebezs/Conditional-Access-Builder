BeforeAll {
    $script:root = Split-Path $PSScriptRoot -Parent
}
Describe 'PowerShell Gallery preparation and runtime safety' {
    It 'exposes only the intended module entrypoint' {
        $impl = Get-Content (Join-Path $script:root 'Packaging/ConditionalAccessBuilder.psm1') -Raw
        $impl | Should -Match 'function Start-ConditionalAccessBuilder'
        $impl | Should -Match 'Export-ModuleMember -Function'
        $impl | Should -Not -Match 'ExecutionPolicy\s+Bypass'
    }
    It 'requires Graph authentication and PowerShell 7 in the module manifest' {
        $manifest = Get-Content (Join-Path $script:root 'Packaging/ConditionalAccessBuilder.psd1') -Raw
        $manifest | Should -Match "ModuleVersion = '1.0.0'"
        $manifest | Should -Match 'Microsoft.Graph.Authentication'
        $manifest | Should -Match 'PowerShellVersion'
    }
    It 'writes runtime reports under local application data rather than installed code' {
        $source = Get-Content (Join-Path $script:root 'Start-EntraCABuilder.ps1') -Raw
        $source | Should -Match "GetFolderPath\('LocalApplicationData'\)"
        $source | Should -Not -Match 'Join-Path \$script:Root ''Reports'''
    }
    It 'keeps the success dialog short and puts report paths in Activity Log' {
        $source = Get-Content (Join-Path $script:root 'Start-EntraCABuilder.ps1') -Raw
        $source | Should -Match 'Deployment complete'
        $source | Should -Match 'Details: Activity Log'
    }
    It 'only builds packages from named runtime files' {
        $source = Get-Content (Join-Path $script:root 'Tools/New-Distributions.ps1') -Raw
        $source | Should -Match 'Modules/Graph.psm1'
        $source | Should -Not -Match 'Copy-Item\s+-Recurse'
    }
}
