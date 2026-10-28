BeforeAll {
    $script:projectRoot = Split-Path $PSScriptRoot -Parent
}
Describe 'Public source packaging security' {
    It 'does not bypass execution policy in the public launcher' {
        $cmd = Get-Content (Join-Path $script:projectRoot 'Launch-GUI.cmd') -Raw
        $cmd | Should -Not -Match '(?i)-ExecutionPolicy\s+Bypass'
        $cmd | Should -Match '(?i)pwsh\.exe -NoProfile -STA -File'
    }
    It 'does not contain planning documents or private Excel files' {
        Test-Path (Join-Path $script:projectRoot 'Docs') | Should -BeFalse
        @(Get-ChildItem -Path $script:projectRoot -Filter '*.xlsx' -Recurse -File).Count | Should -Be 0
        $archiveBuilder = Get-Content (Join-Path $script:projectRoot 'Tools/New-GitHubSourceZip.ps1') -Raw
        $archiveBuilder | Should -Not -Match 'Docs/'
        $archiveBuilder | Should -Not -Match "'CHANGELOG.md'"
        $archiveBuilder | Should -Not -Match "'CONTRIBUTING.md'"
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
    It 'keeps GitHub Code Download ZIP limited to runnable files' {
        $git = Get-Command git -ErrorAction Stop
        $zipPath = Join-Path $TestDrive 'download.zip'
        Push-Location $script:projectRoot
        try {
            & $git.Source archive --format=zip "--output=$zipPath" HEAD
            $LASTEXITCODE | Should -Be 0
        }
        finally { Pop-Location }

        Add-Type -AssemblyName System.IO.Compression
        $archive = [System.IO.Compression.ZipFile]::OpenRead($zipPath)
        try {
            $paths = @($archive.Entries | Where-Object { -not $_.FullName.EndsWith('/') } | ForEach-Object { $_.FullName })
            $expected = @(
                'Start-EntraCABuilder.ps1',
                'Launch-GUI.cmd',
                'GUI/MainWindow.xaml',
                'Modules/Graph.psm1',
                'Modules/Policy.psm1',
                'Baselines/policy-catalogue.json',
                'README.md',
                'LICENSE'
            )
            @($paths).Count | Should -Be $expected.Count
            foreach ($file in $expected) { $paths | Should -Contain $file }
            $paths -join ',' | Should -Not -Match 'Tests/|Tools/|Packaging/|\\.github/|SECURITY\\.md'
        }
        finally { $archive.Dispose() }
    }
}
