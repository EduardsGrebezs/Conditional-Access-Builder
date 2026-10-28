BeforeAll {
    $script:root = Split-Path $PSScriptRoot -Parent
    [xml]$script:ui = Get-Content (Join-Path $script:root 'GUI/MainWindow.xaml') -Raw
    $script:xml = $script:ui.OuterXml
    $script:launcher = Get-Content (Join-Path $script:root 'Start-EntraCABuilder.ps1') -Raw
}
Describe 'v0.2.2 GUI cleanup' {
    It 'retains Connect and Sign out buttons without tenant input' {
        $script:xml | Should -Match 'x:Name="ConnectButton" Content="Connect"'
        $script:xml | Should -Match 'x:Name="SignOutButton"'
        $script:xml | Should -Not -Match 'TargetTenantId'
    }
    It 'hides licensing tab and manual license profile while retaining automatic checks' {
        $script:xml | Should -Not -Match 'Header="Licensing"'
        $script:xml | Should -Not -Match 'LicenseCombo'
        $script:xml | Should -Not -Match 'LICENSE PROFILE'
        $script:launcher | Should -Match 'Get-CAPolicyLicenseEligibility'
        $script:launcher | Should -Match 'Get-CAEffectiveTier'
    }
    It 'removes unwanted labels' {
        $script:xml | Should -Not -Match 'IDENTITY SECURITY'
        $script:xml | Should -Not -Match 'TOOLKIT'
        $script:xml | Should -Not -Match 'Optional in report-only testing'
    }
    It 'keeps named locations, policies, preview and logs accessible' {
        $script:xml | Should -Match 'Header="Policies"'
        $script:xml | Should -Match 'Header="Named Locations"'
        $script:xml | Should -Match 'Header="Output"'
        $script:xml | Should -Match 'Header="Activity Log"'
    }
    It 'uses the revised button labels and a uniform action color' {
        foreach ($button in @('Connect','Sign Out','Refresh Data','Preview Run','Deploy')) {
            $script:xml | Should -Match ('Content="' + [regex]::Escape($button) + '"')
        }
        $script:xml | Should -Match 'Property="Background" Value="#2463CA"'
        $script:xml | Should -Not -Match '<Button x:Name="SignOutButton"[^>]*Background='
        $script:xml | Should -Not -Match '<Button x:Name="PreviewButton"[^>]*Background='
        $script:xml | Should -Not -Match '<Button x:Name="DeployButton"[^>]*Background='
    }
    It 'renames licensing and removes long helper labels' {
        $script:xml | Should -Match 'DETECTED LICENSING PLAN'
        $script:xml | Should -Not -Match 'DETECTED CA CAPABILITY'
        $script:xml | Should -Not -Match 'AgentLicenseText'
        $script:xml | Should -Match 'No Emergency accounts exist'
        $script:xml | Should -Match 'Header="DETAILS"'
        $script:xml | Should -Not -Match 'REASON / DETAILS'
    }
    It 'uses the updated preview and log tab positions' {
        $script:launcher | Should -Match 'else \{ 2 \}'
        $script:launcher | Should -Match '\$script:Gui.MainTabs.SelectedIndex = 3'
        $script:launcher | Should -Not -Match '\$script:Gui.MainTabs.SelectedIndex = 4'
    }
}

Describe 'v1.0.0 additional GUI controls and popup consistency' {
    It 'contains select-all and deselect-all buttons with handlers' {
        $script:xml | Should -Match 'x:Name="SelectAllButton" Content="Select All"'
        $script:xml | Should -Match 'x:Name="DeselectAllButton" Content="Deselect All"'
        $script:launcher | Should -Match 'Set-CAAllPolicySelections -Select \$true'
        $script:launcher | Should -Match 'Set-CAAllPolicySelections -Select \$false'
        $script:launcher | Should -Match 'if \(\$row.CanDeploy\)'
    }
    It 'shows uniform application titles and omits unwanted footer text' {
        $script:xml | Should -Match 'Title="Conditional Access Builder v1.0.0"'
        $script:xml | Should -Match 'Text="v1.0.0"'
        $script:xml | Should -Not -Match 'Changes require final confirmation'
        $script:launcher | Should -Match '\$script:AppTitle = ''Conditional Access Builder v1.0.0'''
        $script:launcher | Should -Not -Match "'Refresh discovery','OK','Error'"
    }
    It 'uses collection bindings rather than array pipeline outputs for country filters' {
        $script:launcher | Should -Match 'ObservableCollection\[object\]'
        $script:launcher | Should -Match 'Get-CAFilteredNamedLocationItems'
        $script:launcher | Should -Not -Match 'CountryGrid.ItemsSource = @\('
    }
}
