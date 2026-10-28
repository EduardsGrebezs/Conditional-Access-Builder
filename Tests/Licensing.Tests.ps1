BeforeAll {
    $root = Split-Path $PSScriptRoot -Parent
    Import-Module (Join-Path $root 'Modules/Graph.psm1') -Force
    $script:catalog = @(Get-Content (Join-Path $root 'Baselines/policy-catalogue.json') -Raw | ConvertFrom-Json -AsHashtable)
    $script:p1 = @(@{ capabilityStatus='Enabled'; skuPartNumber='SPE_E3'; servicePlans=@(@{servicePlanName='AAD_PREMIUM';provisioningStatus='Success'}) })
    $script:p2 = @(@{ capabilityStatus='Enabled'; skuPartNumber='SPE_E5'; servicePlans=@(@{servicePlanName='AAD_PREMIUM_P2';provisioningStatus='Success'}) })
    $script:free = @(@{ capabilityStatus='Enabled'; skuPartNumber='O365_BUSINESS'; servicePlans=@() })
}
Describe 'Tenant-based per-policy licensing' {
    It 'blocks every user CA policy without P1/P2 even when a tenant has a nonqualifying subscription' {
        $p = @($script:catalog | Where-Object code -eq 'CA001')[0]
        $result = Get-CAPolicyLicenseEligibility -Definition $p -Skus $script:free
        $result.CanDeploy | Should -BeFalse
        $result.Status | Should -Be 'NOT AVAILABLE'
    }
    It 'handles tenants returning zero subscribed SKUs' {
        (Get-CAEffectiveTier -Skus @()) | Should -Be 0
    }
    It 'enables ordinary P1 policies on P1' {
        $p = @($script:catalog | Where-Object code -eq 'CA012')[0]
        $result = Get-CAPolicyLicenseEligibility -Definition $p -Skus $script:p1
        $result.CanDeploy | Should -BeTrue
    }
    It 'does not enable P2 CA008 on P1' {
        $p = @($script:catalog | Where-Object code -eq 'CA008')[0]
        $result = Get-CAPolicyLicenseEligibility -Definition $p -Skus $script:p1
        $result.CanDeploy | Should -BeFalse
        $result.Status | Should -Be 'NOT AVAILABLE'
    }
    It 'does not enable P2 CA011 on P1' {
        $p = @($script:catalog | Where-Object code -eq 'CA011')[0]
        (Get-CAPolicyLicenseEligibility -Definition $p -Skus $script:p1).CanDeploy | Should -BeFalse
    }
    It 'enables CA008 and CA011 on P2 for compilation' {
        foreach ($code in @('CA008','CA011')) {
            $p = @($script:catalog | Where-Object code -eq $code)[0]
            (Get-CAPolicyLicenseEligibility -Definition $p -Skus $script:p2).CanDeploy | Should -BeTrue
        }
    }
    It 'does not count suspended SKUs or disabled service plans' {
        $bad = @(
            @{ capabilityStatus='Suspended';skuPartNumber='AAD_PREMIUM_P2';servicePlans=@(@{servicePlanName='AAD_PREMIUM_P2';provisioningStatus='Success'}) },
            @{ capabilityStatus='Enabled';skuPartNumber='TEST';servicePlans=@(@{servicePlanName='AAD_PREMIUM';provisioningStatus='Disabled'}) }
        )
        (Get-CAEffectiveTier -Skus $bad) | Should -Be 0
    }
    It 'does not enable agent-risk CA007 even on E7' {
        $p = @($script:catalog | Where-Object code -eq 'CA007')[0]
        $skus = @(@{capabilityStatus='Enabled';skuPartNumber='MICROSOFT_365_E7';servicePlans=@()})
        $result = Get-CAPolicyLicenseEligibility -Definition $p -Skus $skus
        $result.CanDeploy | Should -BeFalse
        $result.Status | Should -Be 'NOT IMPLEMENTED'
    }
    It 'shows not available for agent policy when its required licenses are missing' {
        $p = @($script:catalog | Where-Object code -eq 'CA007')[0]
        $result = Get-CAPolicyLicenseEligibility -Definition $p -Skus $script:p2
        $result.CanDeploy | Should -BeFalse
        $result.Status | Should -Be 'NOT AVAILABLE'
        $result.Reason | Should -Match 'Agent 365'
    }
    It 'keeps available policy reasons empty and unavailable reasons brief' {
        $p1policy = @($script:catalog | Where-Object code -eq 'CA001')[0]
        $valid = Get-CAPolicyLicenseEligibility -Definition $p1policy -Skus $script:p1
        $missing = Get-CAPolicyLicenseEligibility -Definition $p1policy -Skus $script:free
        $valid.Reason | Should -Be ''
        $missing.Reason.Length | Should -BeLessThan 55
    }
    It 'displays a friendly license plan label without tenant capability suffix' {
        (Get-CADetectedPlanLabel -Skus $script:p2) | Should -Be 'Microsoft 365 E5'
        (Get-CADetectedPlanLabel -Skus $script:free) | Should -Be 'No Entra P1/P2 license detected'
        $e7 = @(@{capabilityStatus='Enabled';skuPartNumber='MICROSOFT_365_E7';servicePlans=@()})
        (Get-CADetectedPlanLabel -Skus $e7) | Should -Be 'Microsoft 365 E7'
    }
    It 'never makes Stage 2 eligible' {
        $p = @($script:catalog | Where-Object code -eq 'CA013')[0]
        (Get-CAPolicyLicenseEligibility -Definition $p -Skus $script:p2).CanDeploy | Should -BeFalse
    }
    It 'reports license inventory without claiming per-user assignment' {
        $sku = @(@{ capabilityStatus='Enabled';skuPartNumber='SPE_E5';consumedUnits=3;prepaidUnits=@{enabled=10};servicePlans=@(@{servicePlanName='AAD_PREMIUM_P2';provisioningStatus='Success'}) })
        $rows = @(Get-CALicenseInventoryRows -Skus $sku)
        $rows.Count | Should -Be 1
        $rows[0].ConsumedUnits | Should -Be '3'
        $rows[0].Signals | Should -Match 'P2'
    }
    It 'hides license tab and retains policy-level guardrails' {
        $root = Split-Path $PSScriptRoot -Parent
        $startup = Get-Content (Join-Path $root 'Start-EntraCABuilder.ps1') -Raw
        $gui = Get-Content (Join-Path $root 'GUI/MainWindow.xaml') -Raw
        $startup | Should -Match 'Get-CAPolicyLicenseEligibility -Definition \$row.Raw'
        $startup | Should -Match '\$row.Selected = \$false'
        $gui | Should -Not -Match 'x:Name="LicenseGrid"'
        $gui | Should -Match 'Header="REQUIRES"'
    }
}
