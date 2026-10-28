@{
    RootModule = 'ConditionalAccessBuilder.psm1'
    ModuleVersion = '1.0.0'
    GUID = 'da81bf68-91d0-4aab-a7bf-10d62b617321'
    Author = 'EduardsGrebezs'
    CompanyName = 'Community Project'
    Copyright = '(c) 2026 Conditional Access Builder Contributors. MIT license.'
    Description = 'Windows PowerShell 7 WPF GUI for planning and deploying report-only Microsoft Entra Conditional Access baselines.'
    PowerShellVersion = '7.2'
    CompatiblePSEditions = @('Core')
    RequiredModules = @(@{ ModuleName = 'Microsoft.Graph.Authentication'; ModuleVersion = '2.0.0' })
    FunctionsToExport = @('Start-ConditionalAccessBuilder')
    CmdletsToExport = @()
    VariablesToExport = @()
    AliasesToExport = @()
    PrivateData = @{
        PSData = @{
            Tags = @('ConditionalAccess','MicrosoftEntra','Security','Graph','WPF','Windows')
            ProjectUri = 'https://github.com/EduardsGrebezs/Conditional-Access-Builder'
            LicenseUri = 'https://opensource.org/licenses/MIT'
            ReleaseNotes = 'Stage 1 report-only policies; CA007 agent-risk is not implemented. CA011 uses Graph beta.'
        }
    }
}
