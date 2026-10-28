BeforeAll {
    $script:root = Split-Path $PSScriptRoot -Parent
    Import-Module (Join-Path $script:root 'Modules/Graph.psm1') -Force
    Import-Module (Join-Path $script:root 'Modules/Policy.psm1') -Force
}
Describe 'Graph API routing and safety' {
    It 'routes only CA011 risk remediation through Graph beta' {
        $source = Get-Content (Join-Path $script:root 'Start-EntraCABuilder.ps1') -Raw
        $source | Should -Match 'if \(\$entry\.Key -eq ''CA011''\) \{ ''beta'' \} else \{ ''v1.0'' \}'
        $source | Should -Match 'Confirm-CACreatedPolicy .* -ApiVersion \$policyApi'
    }
    It 'retains Graph pagination support via absolute nextLinks and correct API version' {
        $graphText = Get-Content (Join-Path $script:root 'Modules/Graph.psm1') -Raw
        $graphText | Should -Match '@odata.nextLink'
        $graphText | Should -Match 'graph\.microsoft'
        $graphText | Should -Match 'Get-CACollection -Path.* -ApiVersion'
    }
    It 'checks beta inventory for CA011 duplicates before POST' {
        $app = Get-Content (Join-Path $script:root 'Start-EntraCABuilder.ps1') -Raw
        $app | Should -Match 'betaInventory = @\(Get-CACollection -Path .* -ApiVersion beta'
    }
    It 'blocks non-CA011 POST requests to beta before contacting Graph' {
        $bad = @{ displayName='CA010 - Test'; state='enabledForReportingButNotEnforced'; grantControls=@{ builtInControls=@('mfa') } }
        { Invoke-CARequest -Path '/identity/conditionalAccess/policies' -Method POST -ApiVersion beta -Body $bad } | Should -Throw '*only for CA011*'
    }
    It 'blocks enforced policy POST requests to beta before contacting Graph' {
        $bad = @{ displayName='CA011 - Test'; state='enabled'; grantControls=@{ builtInControls=@('riskRemediation') } }
        { Invoke-CARequest -Path '/identity/conditionalAccess/policies' -Method POST -ApiVersion beta -Body $bad } | Should -Throw '*report-only*'
    }
    It 'uses the v1.0 all-guest special scope without extra subtype restrictions for CA012' {
        $defs = Get-Content (Join-Path $script:root 'Baselines/policy-catalogue.json') -Raw | ConvertFrom-Json -AsHashtable
        $def = @($defs | Where-Object { $_.code -eq 'CA012' })[0]
        $tenant = @{ subscribedSkus=@(@{capabilityStatus='Enabled';servicePlans=@(@{servicePlanName='AAD_PREMIUM';provisioningStatus='Success'})});roleDefinitions=@(); namedLocations=@();existingPolicies=@() }
        $payload = New-CAStage1Policy -Definition $def -Tenant $tenant -EmergencyIds @()
        $payload.conditions.users.includeUsers | Should -Contain 'GuestsOrExternalUsers'
        $payload.conditions.users.ContainsKey('includeGuestsOrExternalUsers') | Should -BeFalse
    }
}
