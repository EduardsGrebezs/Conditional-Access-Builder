BeforeAll {
    $script:root = Split-Path $PSScriptRoot -Parent
    Import-Module (Join-Path $script:root 'Modules/Graph.psm1') -Force
}
Describe 'Policy deployment read-back safety' {
    It 'verifies a created policy after an initial Graph 404 without retrying POST' {
        $global:CAReadbackMockCount = 0
        Mock Invoke-CARequest -ModuleName Graph {
            $global:CAReadbackMockCount++
            if ($global:CAReadbackMockCount -eq 1) { throw 'Response status code does not indicate success: NotFound (Not Found).' }
            return @{ id='00000000-0000-0000-0000-000000000001'; displayName='CA001 - Block legacy authentication'; state='enabledForReportingButNotEnforced' }
        }
        $result = Confirm-CACreatedPolicy -PolicyId '00000000-0000-0000-0000-000000000001' -ExpectedName 'CA001 - Block legacy authentication' -Attempts 3 -DelayMilliseconds 0
        $result.Verified | Should -BeTrue
        $result.Id | Should -Be '00000000-0000-0000-0000-000000000001'
        $global:CAReadbackMockCount | Should -Be 2
    }
    It 'preserves the ID and requires review if all read-back attempts return 404' {
        Mock Invoke-CARequest -ModuleName Graph { throw 'NotFound (Not Found)' }
        Mock Get-CACollection -ModuleName Graph { return @() }
        $result = Confirm-CACreatedPolicy -PolicyId '00000000-0000-0000-0000-000000000002' -ExpectedName 'CA002 - Device Code Flow' -Attempts 2 -DelayMilliseconds 0
        $result.Verified | Should -BeFalse
        $result.Id | Should -Be '00000000-0000-0000-0000-000000000002'
        $result.Message | Should -Match 'Do not recreate'
    }
    It 'rejects unexpected non-report-only state during verification' {
        Mock Invoke-CARequest -ModuleName Graph {
            return @{ id='00000000-0000-0000-0000-000000000003'; displayName='CA003'; state='enabled' }
        }
        $result = Confirm-CACreatedPolicy -PolicyId '00000000-0000-0000-0000-000000000003' -ExpectedName 'CA003' -Attempts 1 -DelayMilliseconds 0
        $result.Verified | Should -BeFalse
        $result.Message | Should -Match 'not the requested report-only state'
    }
    It 'writes a journal entry with policy ID before verification' {
        $source = Get-Content (Join-Path $script:root 'Start-EntraCABuilder.ps1') -Raw
        $postIndex = $source.IndexOf("-Event 'PostAcknowledged'")
        $verifyIndex = $source.IndexOf('Confirm-CACreatedPolicy -PolicyId $postedId')
        $postIndex | Should -BeGreaterThan 0
        $verifyIndex | Should -BeGreaterThan $postIndex
        $source | Should -Match 'CreatedPendingVerification'
        $source | Should -Match 'OutcomeUnconfirmed'
    }
}
