BeforeAll {
    $root = Split-Path $PSScriptRoot -Parent
    Import-Module (Join-Path $root 'Modules/Graph.psm1') -Force
    $script:gui = Get-Content (Join-Path $root 'GUI/MainWindow.xaml') -Raw
    $script:startup = Get-Content (Join-Path $root 'Start-EntraCABuilder.ps1') -Raw
}
Describe 'Tenant switching safeguards' {
    It 'offers Connect and Sign out without explicit tenant switching fields' {
        $script:gui | Should -Match 'x:Name="ConnectButton" Content="Connect"'
        $script:gui | Should -Match 'x:Name="SignOutButton"'
        $script:gui | Should -Not -Match 'x:Name="TargetTenantId"'
        $script:startup | Should -Match '\$script:Gui.SignOutButton.Add_Click'
    }
    It 'clears tenant-specific plans, exclusions and preview on switch' {
        $script:startup | Should -Match 'function Reset-CAConnectionState'
        $script:startup | Should -Match '\$script:LastExclusionIds = @\(\)'
        $script:startup | Should -Match '\$script:Gui.PreviewText.Text = '
        $script:startup | Should -Match '\$script:Gui.LicenseAck.IsChecked = \$false'
    }
    It 'never unlocks CA007 for an E7 tenant before beta support is built' {
        $script:startup | Should -Match 'CA007 not implemented'
        $script:startup | Should -Match '\$row\[0\].CanDeploy = \$false'
    }
}
Describe 'Agent 365 tenant license signals' {
    It 'recognizes Microsoft 365 E7 as bundled Agent 365 and P2' {
        $sku = @{ capabilityStatus='Enabled'; skuPartNumber='MICROSOFT_365_E7'; servicePlans=@() }
        $cap = Get-CAAgentLicenseSignals -Skus @($sku)
        $cap.E7Detected | Should -BeTrue
        $cap.Agent365Detected | Should -BeTrue
        $cap.AgentRiskLicenseCandidate | Should -BeTrue
    }
    It 'recognizes P2 and Agent 365 add-on without E7' {
        $skus = @(
            @{ capabilityStatus='Enabled'; skuPartNumber='AAD_PREMIUM_P2'; servicePlans=@(@{ servicePlanName='AAD_PREMIUM_P2'; provisioningStatus='Success' }) },
            @{ capabilityStatus='Enabled'; skuPartNumber='AGENT_365'; servicePlans=@(@{ servicePlanName='AGENT_365'; provisioningStatus='Success' }) }
        )
        $cap = Get-CAAgentLicenseSignals -Skus $skus
        $cap.E7Detected | Should -BeFalse
        $cap.AgentRiskLicenseCandidate | Should -BeTrue
    }
    It 'does not infer Agent 365 from P2 alone' {
        $sku = @{ capabilityStatus='Enabled'; skuPartNumber='AAD_PREMIUM_P2'; servicePlans=@(@{ servicePlanName='AAD_PREMIUM_P2'; provisioningStatus='Success' }) }
        $cap = Get-CAAgentLicenseSignals -Skus @($sku)
        $cap.Agent365Detected | Should -BeFalse
        $cap.AgentRiskLicenseCandidate | Should -BeFalse
    }
    It 'does not interpret disabled Agent 365 subscription as active' {
        $sku = @{ capabilityStatus='Suspended'; skuPartNumber='AGENT_365'; servicePlans=@(@{ servicePlanName='AGENT_365'; provisioningStatus='Success' }) }
        $cap = Get-CAAgentLicenseSignals -Skus @($sku)
        $cap.Agent365Detected | Should -BeFalse
    }
}
