BeforeAll {
    $script:projectRoot = Split-Path $PSScriptRoot -Parent
}
Describe 'Public source packaging security' {
    It 'does not bypass execution policy in the public launcher' {
        $cmd = Get-Content (Join-Path $script:projectRoot 'Launch-GUI.cmd') -Raw
        $cmd | Should -Not -Match '(?i)-ExecutionPolicy\s+Bypass'
        $cmd | Should -Match '(?i)pwsh\.exe -NoProfile -STA -File'
    }
    It 'does not contain a bundled private Excel workbook' {
        Test-Path (Join-Path $script:projectRoot 'Docs/CA-policy-design-baseline.xlsx') | Should -BeFalse
    }
    It 'gitignores archives, private keys, and output reports' {
        $ignore = Get-Content (Join-Path $script:projectRoot '.gitignore') -Raw
        $ignore | Should -Match '\*\.zip'
        $ignore | Should -Match '\*\.pfx'
        $ignore | Should -Match '/Reports/\*'
    }
    It 'uses read-only GitHub token permissions in CI' {
        $ci = Get-Content (Join-Path $script:projectRoot '.github/workflows/pester.yml') -Raw
        $ci | Should -Match 'contents: read'
    }
    It 'maintains CA007 as not deployable even when E7 is present' {
        $source = Get-Content (Join-Path $script:projectRoot 'Modules/Graph.psm1') -Raw
        $source | Should -Match "Status='NOT IMPLEMENTED'"
    }
}
