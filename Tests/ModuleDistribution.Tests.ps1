BeforeAll {
    $script:root = Split-Path $PSScriptRoot -Parent
}
Describe 'PowerShell Gallery module preparation and runtime safety' {
    It 'exports only the intended command and requires STA on Windows' {
        $impl = Get-Content (Join-Path $script:root 'Packaging/ConditionalAccessBuilder.psm1') -Raw
        $impl | Should -Match 'function Start-ConditionalAccessBuilder'
        $impl | Should -Match "Export-ModuleMember -Function 'Start-ConditionalAccessBuilder'"
        $impl | Should -Match "GetApartmentState\(\)"
        $impl | Should -Not -Match 'ExecutionPolicy\s+Bypass'
    }
    It 'has a stable module identity, Graph dependency, and public project metadata' {
        $manifest = Import-PowerShellDataFile (Join-Path $script:root 'Packaging/ConditionalAccessBuilder.psd1')
        [string]$manifest.ModuleVersion | Should -Be '1.0.0'
        $manifest.RootModule | Should -Be 'ConditionalAccessBuilder.psm1'
        $manifest.PowerShellVersion | Should -Be '7.2'
        @($manifest.RequiredModules).Count | Should -Be 1
        $manifest.PrivateData.PSData.ProjectUri | Should -Be 'https://github.com/EduardsGrebezs/Conditional-Access-Builder'
        @($manifest.FunctionsToExport) | Should -Contain 'Start-ConditionalAccessBuilder'
    }
    It 'stores runtime reports in the current Windows user data directory' {
        $source = Get-Content (Join-Path $script:root 'Start-EntraCABuilder.ps1') -Raw
        $source | Should -Match "GetFolderPath\('LocalApplicationData'\)"
        $source | Should -Not -Match 'Join-Path \$script:Root ''Reports'''
    }
    It 'keeps the report-only deployment success dialog short' {
        $source = Get-Content (Join-Path $script:root 'Start-EntraCABuilder.ps1') -Raw
        $source | Should -Match 'Deployment complete'
        $source | Should -Match 'Details: Activity Log'
    }
    It 'builds only a module and never publishes automatically' {
        $builder = Get-Content (Join-Path $script:root 'Tools/Build-Module.ps1') -Raw
        $builder | Should -Match 'Packaging/ConditionalAccessBuilder.psd1'
        $builder | Should -Match 'Modules/Graph.psm1'
        $builder | Should -Not -Match "'SECURITY\.md'"
        $builder | Should -Not -Match 'Copy-Item\s+-Recurse'
        $builder | Should -Not -Match 'Publish-(Module|PSResource)'
        $builder | Should -Not -Match 'Portable.zip'
    }
    It 'does not reintroduce the obsolete portable distribution script' {
        Test-Path (Join-Path $script:root 'Tools/New-Distributions.ps1') | Should -BeFalse
    }
}
