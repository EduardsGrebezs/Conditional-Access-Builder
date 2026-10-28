#Requires -Version 7.2
Set-StrictMode -Version Latest

function Start-ConditionalAccessBuilder {
    <#
    .SYNOPSIS
    Launches the Windows WPF Conditional Access Builder interface.
    .DESCRIPTION
    Requires Windows and PowerShell 7.2 or later. This command does not create
    tenant policies until the operator connects, previews, and confirms Deploy.
    .EXAMPLE
    Import-Module ConditionalAccessBuilder
    Start-ConditionalAccessBuilder
    #>
    [CmdletBinding()]
    param()

    if (-not $IsWindows) {
        throw 'Conditional Access Builder uses WPF and can run only on Windows.'
    }
    if ([Threading.Thread]::CurrentThread.GetApartmentState() -ne 'STA') {
        throw 'WPF needs STA. Start a new Windows PowerShell 7 session with pwsh.exe -STA, import the module, and run Start-ConditionalAccessBuilder.'
    }
    $guiScript = Join-Path $PSScriptRoot 'Start-EntraCABuilder.ps1'
    if (-not (Test-Path -LiteralPath $guiScript -PathType Leaf)) {
        throw 'The installed ConditionalAccessBuilder package is missing its GUI entrypoint. Reinstall the module.'
    }
    & $guiScript
}

Export-ModuleMember -Function 'Start-ConditionalAccessBuilder'
