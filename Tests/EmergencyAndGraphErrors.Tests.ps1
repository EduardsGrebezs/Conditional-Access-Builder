BeforeAll {
    $script:root = Split-Path $PSScriptRoot -Parent
    Import-Module (Join-Path $script:root 'Modules/Graph.psm1') -Force
}
Describe 'Report-only CA deployment safeguards' {
    It 'extracts structured Graph 400 errors without losing the explanation' {
        $e = [System.Exception]::new('BadRequest (Bad Request)')
        $r = [System.Management.Automation.ErrorRecord]::new($e,'BadRequest',[System.Management.Automation.ErrorCategory]::InvalidArgument,$null)
        $r.ErrorDetails = [System.Management.Automation.ErrorDetails]::new('{"error":{"code":"BadRequest","message":"Invalid grant control combination"}}')
        $description = Get-CAGraphErrorDetails -Record $r
        $description | Should -Match 'HTTP 400'
        $description | Should -Match 'Invalid grant control combination'
    }
    It 'includes a real one-emergency-account mode in GUI and resolver' {
        $xaml = Get-Content (Join-Path $script:root 'GUI/MainWindow.xaml') -Raw
        $start = Get-Content (Join-Path $script:root 'Start-EntraCABuilder.ps1') -Raw
        $xaml | Should -Match 'x:Name="OneEmergencyAccount"'
        $start | Should -Match 'Gui.OneEmergencyAccount.IsChecked'
        $start | Should -Match 'Use one emergency account is selected'
        $start | Should -Match 'oneEmergency ='
    }
    It 'does not call a definite Graph 400 outcome unconfirmed' {
        $start = Get-Content (Join-Path $script:root 'Start-EntraCABuilder.ps1') -Raw
        $start | Should -Match "'RejectedByGraph'"
        $start | Should -Match 'Graph rejected the request before policy creation'
    }
    It 'continues enforcing report-only state in Graph POST' {
        $graph = Get-Content (Join-Path $script:root 'Modules/Graph.psm1') -Raw
        $graph | Should -Match "Body.state -cne 'enabledForReportingButNotEnforced'"
    }
}
