BeforeAll {
    $root = Split-Path $PSScriptRoot -Parent
    Import-Module (Join-Path $root 'Modules/Graph.psm1') -Force
}

Describe 'Named-location filtering for the GUI' {
    It 'returns IEnumerable with no locations' {
        $result = Get-CAFilteredNamedLocationItems -Locations @() -Search ''
        ($result -is [System.Collections.IEnumerable]) | Should -BeTrue
        @($result).Count | Should -Be 0
    }

    It 'returns an enumerable collection even with exactly one location' {
        $inputLocations = @([pscustomobject]@{ Id = '14717268-edd9-4568-bb07-ad4bf44edb73'; Label = 'Blocked Countries [14717268-edd9-4568-bb07-ad4bf44edb73]' })
        $result = Get-CAFilteredNamedLocationItems -Locations $inputLocations -Search 'blocked'
        ($result -is [System.Collections.IEnumerable]) | Should -BeTrue
        $result.Count | Should -Be 1
        $result[0].Id | Should -Be '14717268-edd9-4568-bb07-ad4bf44edb73'
    }

    It 'filters by name and ID without dropping collection semantics' {
        $locations = @(
            [pscustomobject]@{ Id = '11111111-1111-1111-1111-111111111111'; Label = 'Blocked Countries [11111111-1111-1111-1111-111111111111]' },
            [pscustomobject]@{ Id = '22222222-2222-2222-2222-222222222222'; Label = 'Trusted Countries [22222222-2222-2222-2222-222222222222]' }
        )
        $result = Get-CAFilteredNamedLocationItems -Locations $locations -Search '22222222'
        ($result -is [System.Collections.IEnumerable]) | Should -BeTrue
        $result.Count | Should -Be 1
        $result[0].Label | Should -Match 'Trusted Countries'
        (Get-CAFilteredNamedLocationItems -Locations $locations -Search '').Count | Should -Be 2
    }
}
