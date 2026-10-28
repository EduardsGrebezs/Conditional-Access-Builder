BeforeAll {
    $root = Split-Path $PSScriptRoot -Parent
    Import-Module (Join-Path $root 'Modules/Graph.psm1') -Force
    Import-Module (Join-Path $root 'Modules/Policy.psm1') -Force
    $script:catalog = @(Get-Content (Join-Path $root 'Baselines/policy-catalogue.json') -Raw | ConvertFrom-Json -AsHashtable)
    $script:roleNames = @($script:catalog | Where-Object { $_['code'] -eq 'CA009' } | ForEach-Object { $_['sourceFields']['includeRoles'] -split "`n" })
    $script:roles = @($script:roleNames | ForEach-Object { @{ displayName=$_.Trim(); id=[guid]::NewGuid().ToString() } })
    $script:users = @('00000000-0000-0000-0000-00000000a001')
    $script:tenant = @{
        subscribedSkus = @(@{ capabilityStatus='Enabled'; servicePlans=@(@{servicePlanName='AAD_PREMIUM';provisioningStatus='Success'},@{servicePlanName='AAD_PREMIUM_P2';provisioningStatus='Success'}) })
        roleDefinitions = $script:roles
        namedLocations = @(@{id='00000000-0000-0000-0000-00000000a003';displayName='Blocked Countries'})
        existingPolicies = @()
    }
}
Describe 'Baseline shape and safety' {
    It 'preserves 12 selectable policies and 10 Stage 2 policies' {
        @($script:catalog | Where-Object stage -eq 'Stage 1').Count | Should -Be 12
        @($script:catalog | Where-Object stage -eq 'Stage 2').Count | Should -Be 10
    }
    It 'uses sequential unique policy codes across both stages' {
        $allCodes = @($script:catalog | ForEach-Object { $_['code'] })
        @($allCodes | Sort-Object -Unique).Count | Should -Be 22
        @($script:catalog | Where-Object { $_['stage'] -eq 'Stage 1' -and $_['code'] -eq 'CA012' -and $_['displayName'] -match 'guests' }).Count | Should -Be 1
        @($script:catalog | Where-Object { $_['stage'] -eq 'Stage 2' -and $_['code'] -eq 'CA012' }).Count | Should -Be 0
        @($script:catalog | Where-Object { $_['stage'] -eq 'Stage 2' -and $_['code'] -eq 'CA022' }).Count | Should -Be 1
    }
    It 'does not show the Export JSON button or Preview status badge' {
        $gui = Get-Content (Join-Path (Split-Path $PSScriptRoot -Parent) 'GUI/MainWindow.xaml') -Raw
        $start = Get-Content (Join-Path (Split-Path $PSScriptRoot -Parent) 'Start-EntraCABuilder.ps1') -Raw
        $gui | Should -Not -Match 'x:Name="ExportButton"'
        $start | Should -Not -Match 'Gui.ExportButton'
        $gui | Should -Not -Match '●  Report-only'
        $gui | Should -Match 'Text="v1.0.0"'
    }
    It 'contains no 23 placeholder values' {
        foreach ($entry in $script:catalog) {
            foreach ($value in $entry.sourceFields.Values) { [string]$value | Should -Not -BeExactly '23' }
        }
    }
    It 'compiles report-only CA001 with one verified exclusion' {
        $def = @($script:catalog | Where-Object code -eq 'CA001')[0]
        $body = New-CAStage1Policy -Definition $def -Tenant $script:tenant -EmergencyIds $script:users
        $body.state | Should -BeExactly 'enabledForReportingButNotEnforced'
        $body.conditions.users.excludeUsers.Count | Should -Be 1
        $body.conditions.clientAppTypes | Should -Contain 'other'
    }
    It 'preserves CA004 platform exclusions from Excel' {
        $def = @($script:catalog | Where-Object code -eq 'CA004')[0]
        $body = New-CAStage1Policy -Definition $def -Tenant $script:tenant -EmergencyIds $script:users
        $body.conditions.platforms.excludePlatforms | Should -Contain 'macOS'
        $body.conditions.platforms.excludePlatforms | Should -Contain 'iOS'
    }
    It 'preserves CA005 role exclusion and targets ARM' {
        $def = @($script:catalog | Where-Object code -eq 'CA005')[0]
        $body = New-CAStage1Policy -Definition $def -Tenant $script:tenant -EmergencyIds $script:users
        $body.conditions.applications.includeApplications | Should -Contain '797f4846-ba00-4fd7-ba43-dac1f8f63013'
        $body.conditions.users.excludeRoles.Count | Should -Be $script:roles.Count
    }
    It 'preserves CA008 high sign-in risk block' {
        $def = @($script:catalog | Where-Object code -eq 'CA008')[0]
        $body = New-CAStage1Policy -Definition $def -Tenant $script:tenant -EmergencyIds $script:users
        $body.conditions.signInRiskLevels | Should -Contain 'high'
        $body.grantControls.builtInControls | Should -Contain 'block'
    }
    It 'compiles CA009 phishing-resistant MFA for admin roles' {
        $def = @($script:catalog | Where-Object code -eq 'CA009')[0]
        $body = New-CAStage1Policy -Definition $def -Tenant $script:tenant -EmergencyIds $script:users
        $body.conditions.users.includeRoles.Count | Should -Be $script:roles.Count
        $body.grantControls.authenticationStrength.id | Should -Be '00000000-0000-0000-0000-000000000004'
        $body.sessionControls.persistentBrowser.mode | Should -Be 'never'
    }
    It 'compiles CA011 risk remediation' {
        $def = @($script:catalog | Where-Object code -eq 'CA011')[0]
        $body = New-CAStage1Policy -Definition $def -Tenant $script:tenant -EmergencyIds $script:users
        $body.conditions.userRiskLevels | Should -Contain 'high'
        $body.conditions.ContainsKey('clientAppTypes') | Should -BeFalse
        $body.grantControls.operator | Should -Be 'AND'
        $body.grantControls.builtInControls | Should -Contain 'riskRemediation'
        $body.sessionControls.signInFrequency.frequencyInterval | Should -Be 'everyTime'
    }
    It 'shows per-policy status and reasons rather than a separate code column' {
        $gui = Get-Content (Join-Path (Split-Path $PSScriptRoot -Parent) 'GUI/MainWindow.xaml') -Raw
        $start = Get-Content (Join-Path (Split-Path $PSScriptRoot -Parent) 'Start-EntraCABuilder.ps1') -Raw
        # ISO country code remains in Named Locations; the policy grid no longer has CODE.
        ([regex]::Matches($gui, 'Header="CODE"')).Count | Should -Be 1
        $gui | Should -Match 'Header="ID"'
        $gui | Should -Match 'Header="POLICY"'
        $gui | Should -Match 'Header="STATUS"'
        $gui | Should -Match 'Header="DETAILS"'
        $start | Should -Match 'function Update-CAPlanStatus'
        $start | Should -Match 'function Get-CAPlanBlockerMessage'
        $start | Should -Match 'BLOCKED \$\(\$entry.Key\)'
        $start | Should -Match 'Get-CAPolicyLicenseEligibility'
    }
    It 'blocks agent beta CA007' {
        $def = @($script:catalog | Where-Object code -eq 'CA007')[0]
        { New-CAStage1Policy -Definition $def -Tenant $script:tenant -EmergencyIds $script:users } | Should -Throw '*preview*'
    }
    It 'blocks Stage 2 policies in Stage 1 generator' {
        $def = @($script:catalog | Where-Object code -eq 'CA013')[0]
        { New-CAStage1Policy -Definition $def -Tenant $script:tenant -EmergencyIds $script:users } | Should -Throw '*Stage 2*'
    }
    It 'supports two emergency accounts' {
        $def = @($script:catalog | Where-Object code -eq 'CA010')[0]
        $ids = @($script:users[0], '00000000-0000-0000-0000-00000000a002')
        $body = New-CAStage1Policy -Definition $def -Tenant $script:tenant -EmergencyIds $ids
        @($body.conditions.users.excludeUsers).Count | Should -Be 2
    }
    It 'supports no emergency accounts for report-only testing' {
        $def = @($script:catalog | Where-Object code -eq 'CA010')[0]
        $body = New-CAStage1Policy -Definition $def -Tenant $script:tenant -EmergencyIds @()
        @($body.conditions.users.excludeUsers).Count | Should -Be 0
        $body.state | Should -Be 'enabledForReportingButNotEnforced'
    }
    It 'compiles guest MFA scoped only to guest/external identities' {
        $def = @($script:catalog | Where-Object code -eq 'CA012')[0]
        $body = New-CAStage1Policy -Definition $def -Tenant $script:tenant -EmergencyIds $script:users
        $body.conditions.users.includeUsers | Should -Contain 'GuestsOrExternalUsers'
        $body.conditions.users.ContainsKey('includeGuestsOrExternalUsers') | Should -BeFalse
        $body.grantControls.builtInControls | Should -Contain 'mfa'
    }
    It 'previews an unresolved country location but never deploys it unchanged' {
        $def = @($script:catalog | Where-Object code -eq 'CA006')[0]
        $body = New-CAStage1Policy -Definition $def -Tenant $script:tenant -EmergencyIds @() -BlockedLocation 'PENDING-COUNTRY-NAMED-LOCATION'
        $body.conditions.locations.includeLocations | Should -Contain 'PENDING-COUNTRY-NAMED-LOCATION'
        $graphModule = Get-Content (Join-Path (Split-Path $PSScriptRoot -Parent) 'Modules/Graph.psm1') -Raw
        $graphModule | Should -Match 'unresolved location cannot be deployed'
    }
    It 'rejects an accidentally enabled policy' {
        $def = @($script:catalog | Where-Object code -eq 'CA010')[0]
        $body = New-CAStage1Policy -Definition $def -Tenant $script:tenant -EmergencyIds $script:users
        $body.state = 'enabled'
        { Assert-CAPolicySafety -Payload $body -EmergencyIds $script:users } | Should -Throw '*report-only*'
    }
    It 'detects same-name duplicate without writing' {
        $def = @($script:catalog | Where-Object code -eq 'CA010')[0]
        $body = New-CAStage1Policy -Definition $def -Tenant $script:tenant -EmergencyIds $script:users
        $duplicate = Get-CADuplicate -Payload $body -ExistingPolicies @(@{ id='fake'; displayName=$body.displayName })
        $duplicate | Should -Match 'same name'
    }
}

Describe 'Connection and deployment wiring (v0.1.5)' {
    It 'requests CA write scope on initial connection' {
        $scopes = @(Get-CARequiredScopes)
        $scopes | Should -Contain 'Policy.Read.All'
        $scopes | Should -Contain 'Policy.ReadWrite.ConditionalAccess'
    }
    It 'no longer has a second consent button or tenant GUID textbox' {
        $root = Split-Path $PSScriptRoot -Parent
        $xaml = Get-Content (Join-Path $root 'GUI/MainWindow.xaml') -Raw
        $xaml | Should -Not -Match 'x:Name="WriteScopeButton"'
        $xaml | Should -Not -Match 'x:Name="ConfirmTenant"'
        $xaml | Should -Match 'x:Name="Emergency2"'
        $xaml | Should -Match 'x:Name="CountryGrid"'
    }
    It 'gates all Graph POSTs behind report-only' {
        $root = Split-Path $PSScriptRoot -Parent
        $graphModule = Get-Content (Join-Path $root 'Modules/Graph.psm1') -Raw
        $graphModule | Should -Match "Body.state -cne 'enabledForReportingButNotEnforced'"
    }
}

Describe 'Named Locations GUI and linked CA006 regression checks (v0.1.5)' {
    BeforeAll {
        $root = Split-Path $PSScriptRoot -Parent
        $script:xml = Get-Content (Join-Path $root 'GUI/MainWindow.xaml') -Raw
        $script:source = Get-Content (Join-Path $root 'Start-EntraCABuilder.ps1') -Raw
    }
    It 'has an ID number and stable workbook code' {
        $script:xml | Should -Match 'Binding="{Binding Number}"'
        $script:xml | Should -Match 'Binding="{Binding Code}"'
    }
    It 'uses clear operator exclusion label' {
        $script:xml | Should -Match 'Content="Exclude my signed-in account"'
        $script:xml | Should -Not -Match 'Also exclude my'
    }
    It 'labels both country and named-location search and pre-fills CA006' {
        $script:xml | Should -Match 'Search existing named locations'
        $script:xml | Should -Match 'Search countries by name / code'
        $script:xml | Should -Match 'CA006 - Blocked countries'
    }
    It 'automatically selects CA006 when create mode is checked' {
        $script:source | Should -Match '\$script:Gui.CreateNewLocation.Add_Checked'
        $script:source | Should -Match '\$policy.Selected = \$true'
    }
    It 'logs a CA006 creation attempt and a failure rather than silent location-only success' {
        $script:source | Should -Match 'Next step: create report-only CA006'
        $script:source | Should -Match 'Deployment failed — attention required'
        $script:source | Should -Match 'Reusing named location for CA006'
    }
}
