# Prevent regression: PowerShell executes script-level statements in order.
# A function cannot be called before its defining statement is executed.
Describe 'WPF bootstrap declaration order' {
    It 'declares country selection helper before the initial location hint refresh' {
        $scriptPath = Join-Path $PSScriptRoot '..' 'Start-EntraCABuilder.ps1'
        $tokens = $null
        $errors = $null
        $ast = [System.Management.Automation.Language.Parser]::ParseFile($scriptPath, [ref]$tokens, [ref]$errors)
        $errors | Should -BeNullOrEmpty
        $declaration = $ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq 'Get-CASelectedCountries' }, $true) | Select-Object -First 1
        $declaration | Should -Not -BeNullOrEmpty
        # The first top-level invocation of Update-CALocationHints is what calls Get-CASelectedCountries at startup.
        $calls = @($ast.EndBlock.Statements | Where-Object { $_.Extent.Text -match '^Update-CALocationHints\s*$' })
        $calls.Count | Should -Be 1
        $declaration.Extent.StartOffset | Should -BeLessThan $calls[0].Extent.StartOffset
    }
}
