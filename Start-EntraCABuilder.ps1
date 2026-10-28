#Requires -Version 7.2
<#
.SYNOPSIS
    Conditional Access Builder v1.0.0 (Windows WPF preview build).
.DESCRIPTION
    Reads Stage 1 definitions from a versioned policy catalogue. Assesses
    the connected tenant, previews policy bodies, and allows explicitly approved
    report-only creation. No update/delete/enable operations are implemented.
#>
[CmdletBinding()]
param()
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
if (-not $IsWindows) { throw 'This WPF GUI requires Windows. Run on Windows 10/11 or supported Windows Server desktop.' }
if ([threading.Thread]::CurrentThread.GetApartmentState() -ne 'STA') {
    throw 'WPF requires STA. Run: pwsh.exe -NoProfile -STA -File .\Start-EntraCABuilder.ps1 (or double-click Launch-GUI.cmd)'
}
$script:Root = $PSScriptRoot
# Runtime output belongs to the current Windows user, not the installation folder.
# This also permits read-only / AllUsers PowerShell Gallery installations.
$script:ReportDirectory = Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) 'ConditionalAccessBuilder/Reports'
$script:AppTitle = 'Conditional Access Builder v1.0.0'
Import-Module (Join-Path $script:Root 'Modules/Graph.psm1') -Force
Import-Module (Join-Path $script:Root 'Modules/Policy.psm1') -Force
Add-Type -AssemblyName PresentationFramework,PresentationCore,WindowsBase

[xml]$xaml = Get-Content (Join-Path $script:Root 'GUI/MainWindow.xaml') -Raw
$reader = [System.Xml.XmlNodeReader]::new($xaml)
$window = [Windows.Markup.XamlReader]::Load($reader)
$controls = @{}
foreach ($name in @('TenantText','TierText','Emergency1','Emergency2','OneEmergencyAccount','NoEmergencyAccounts','ExcludeOperator','UseExistingLocation','CreateNewLocation','ExistingLocations','NewLocationName','CountrySearch','CountryGrid','SelectedCountriesText','CA006SelectionText','ExistingLocationSearch','IncludeUnknownCountries','ConnectButton','SignOutButton','RefreshButton','PreviewButton','DeployButton','SelectAllButton','DeselectAllButton','Stage1Grid','PolicySummaryText','PreviewText','LogText','LicenseAck','MainTabs')) {
    $controls[$name] = $window.FindName($name)
    if ($null -eq $controls[$name]) { throw "Missing XAML control: $name" }
}
$script:Win = $window
$script:Gui = $controls
$script:Tenant = $null
$script:Catalog = @(Get-Content (Join-Path $script:Root 'Baselines/policy-catalogue.json') -Raw | ConvertFrom-Json -AsHashtable -Depth 100)
$script:Stage1 = [System.Collections.ObjectModel.ObservableCollection[object]]::new()
$script:Plan = @()
$script:PlanReady = $false
$script:PreviewSignature = $null
$script:LastExclusionIds = @()
$script:PendingLocationMarker = 'PENDING-COUNTRY-NAMED-LOCATION'
$script:Countries = [System.Collections.ObjectModel.ObservableCollection[object]]::new()
$script:AllExistingLocationItems = @()
$script:LastNamedLocationAction = $null

$displayNumber = 0
foreach ($record in @($script:Catalog | Sort-Object { [int]([string]$_['code'] -replace '[^0-9]','') })) {
    if ($record['stage'] -ne 'Stage 1') { continue }
    $displayNumber++
    # CA007 remains documented but is deliberately disabled in this build.
    # It must not block deployment of otherwise valid selected policies.
    $canDeploy = $false # All selections remain locked until refresh confirms tenant licensing.
    $item = [pscustomobject]@{
        Selected = $false
        CanDeploy = $canDeploy
        Number = $displayNumber
        Code = [string]$record['code']
        Name = ([string]$record['displayName'] -replace '^\s*CA\d{3}\s*[-–:]\s*','')
        License = [string]$record['license']
        RequiredLicense = if ([string]$record['code'] -eq 'CA007') { 'P2 + Agent 365' } else { 'Entra ' + [string]$record['license'] }
        Support = [string]$record['deploymentSupport']
        Status = 'CONNECT FIRST'
        StatusReason = 'Connect and refresh to check availability.'
        Raw = $record
    }
    $script:Stage1.Add($item)
}
$script:Gui.Stage1Grid.ItemsSource = $script:Stage1
# Windows/.NET local country catalogue; fixed two-letter codes passed to Graph.
$seenCodes = @{}
foreach ($culture in [System.Globalization.CultureInfo]::GetCultures([System.Globalization.CultureTypes]::SpecificCultures)) {
    try {
        $region = [System.Globalization.RegionInfo]::new($culture.Name)
        $code = [string]$region.TwoLetterISORegionName
        if ($code -cmatch '^[A-Z]{2}$' -and -not $seenCodes.ContainsKey($code)) {
            $seenCodes[$code] = [string]$region.EnglishName
        }
    } catch { continue }
}
foreach ($pair in @($seenCodes.GetEnumerator() | Sort-Object Value)) {
    $script:Countries.Add([pscustomobject]@{ Chosen=$false; Code=[string]$pair.Key; Name=[string]$pair.Value })
}
$script:Gui.CountryGrid.ItemsSource = $script:Countries
$script:Gui.CountrySearch.Add_TextChanged({
    $filter = [string]$script:Gui.CountrySearch.Text
    if ([string]::IsNullOrWhiteSpace($filter)) {
        $script:Gui.CountryGrid.ItemsSource = $script:Countries
    } else {
        # Also keep country search results as IEnumerable when only one country
        # matches (the same WPF ItemsSource issue as the named-location list).
        $matches = [System.Collections.ObjectModel.ObservableCollection[object]]::new()
        foreach ($country in $script:Countries) {
            if ($country.Name -like "*$filter*" -or $country.Code -like "*$filter*") {
                $matches.Add($country)
            }
        }
        $script:Gui.CountryGrid.ItemsSource = $matches
    }
})
# Modes are mutually exclusive. One-account mode requires the first verified UPN.
# Without either checkbox, administrators may enter one or two UPNs manually.
$script:Gui.OneEmergencyAccount.Add_Checked({
    if ($script:Gui.NoEmergencyAccounts.IsChecked) { $script:Gui.NoEmergencyAccounts.IsChecked = $false }
    $script:Gui.Emergency1.IsEnabled = $true
    $script:Gui.Emergency2.Text = ''
    $script:Gui.Emergency2.IsEnabled = $false
})
$script:Gui.OneEmergencyAccount.Add_Unchecked({
    if (-not $script:Gui.NoEmergencyAccounts.IsChecked) { $script:Gui.Emergency2.IsEnabled = $true }
})
$script:Gui.NoEmergencyAccounts.Add_Checked({
    if ($script:Gui.OneEmergencyAccount.IsChecked) { $script:Gui.OneEmergencyAccount.IsChecked = $false }
    $script:Gui.Emergency1.IsEnabled = $false
    $script:Gui.Emergency2.IsEnabled = $false
})
$script:Gui.NoEmergencyAccounts.Add_Unchecked({
    $script:Gui.Emergency1.IsEnabled = $true
    $script:Gui.Emergency2.IsEnabled = -not [bool]$script:Gui.OneEmergencyAccount.IsChecked
})


function Write-CALog {
    param([string]$Message)
    $stamp = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
    $script:Gui.LogText.AppendText("[$stamp] $Message`r`n")
    $script:Gui.LogText.ScrollToEnd()
}

function Set-CAAllPolicySelections {
    param([Parameter(Mandatory)][bool]$Select)
    $count = 0
    foreach ($row in $script:Stage1) {
        # Ineligible or unimplemented policies (e.g. CA007) cannot be selected.
        if ($row.CanDeploy) {
            $row.Selected = $Select
            $row.Status = 'AVAILABLE'
            $row.StatusReason = ''
            $count++
        } else {
            $row.Selected = $false
        }
    }
    $script:Gui.Stage1Grid.Items.Refresh()
    $script:PlanReady = $false
    $script:Plan = @()
    $script:PreviewSignature = $null
    $script:Gui.PreviewText.Text = ''
    $selectedCount = @($script:Stage1 | Where-Object { $_.Selected }).Count
    $script:Gui.PolicySummaryText.Text = "$selectedCount selected  |  Run Preview to validate"
    Update-CALocationHints
    if ($Select) {
        Write-CALog "Selected $selectedCount eligible policies. Unavailable policies remain unselected. CA006 requires a configured named location."
    } else {
        Write-CALog "Deselected all policies; previous preview invalidated."
    }
}

$script:Gui.SelectAllButton.Add_Click({
    if (-not $script:Tenant) {
        Write-CALog 'Connect and Refresh Data before selecting policies.'
        return
    }
    Set-CAAllPolicySelections -Select $true
})
$script:Gui.DeselectAllButton.Add_Click({ Set-CAAllPolicySelections -Select $false })

function Get-CASelectedCountries {
    # Commit any in-flight checkbox editor before building an immutable preview.
    [void]$script:Gui.CountryGrid.CommitEdit()
    [void]$script:Gui.CountryGrid.CommitEdit()
    return @($script:Countries | Where-Object { $_.Chosen } | ForEach-Object { $_.Code } | Sort-Object -Unique)
}

function Update-CALocationHints {
    $selected = @($script:Stage1 | Where-Object { $_.Code -eq 'CA006' -and $_.Selected }).Count -eq 1
    $script:Gui.CA006SelectionText.Text = if ($selected) {
        'CA006: selected — the selected named location will be used by the policy.'
    } else {
        'CA006: NOT selected — a named location will not be created by this tool without CA006.'
    }
    $count = @(Get-CASelectedCountries).Count
    $script:Gui.SelectedCountriesText.Text = "Selected countries: $count. Search filters the list without clearing checked countries."
}

function Update-CAExistingLocationFilter {
    $term = ([string]$script:Gui.ExistingLocationSearch.Text).Trim()
    $selected = [string]$script:Gui.ExistingLocations.SelectedValue
    # Always assign IEnumerable, even if there is exactly one location. A scalar
    # PSObject causes "Exception setting ItemsSource" on some tenants (including E7).
    $filtered = Get-CAFilteredNamedLocationItems -Locations $script:AllExistingLocationItems -Search $term
    $script:Gui.ExistingLocations.ItemsSource = $filtered
    if ($selected -and @($filtered | Where-Object { $_.Id -eq $selected }).Count -gt 0) {
        $script:Gui.ExistingLocations.SelectedValue = $selected
    } else {
        $script:Gui.ExistingLocations.SelectedIndex = -1
    }
}

$script:Gui.CreateNewLocation.Add_Checked({
    $policy = @($script:Stage1 | Where-Object Code -eq 'CA006')[0]
    if ($policy -and $policy.CanDeploy -and -not $policy.Selected) {
        $policy.Selected = $true
        $script:Gui.Stage1Grid.Items.Refresh()
        Write-CALog 'CA006 selected automatically because a new named location was requested.'
    }
    Update-CALocationHints
})
$script:Gui.Stage1Grid.Add_PreviewMouseUp({
    [void]$script:Win.Dispatcher.BeginInvoke([Action]{ Update-CALocationHints },[System.Windows.Threading.DispatcherPriority]::Background)
})
$script:Gui.CountryGrid.Add_CellEditEnding({
    param($sender,$eventArgs)
    [void]$script:Win.Dispatcher.BeginInvoke([Action]{ Update-CALocationHints },[System.Windows.Threading.DispatcherPriority]::Background)
})
$script:Gui.ExistingLocationSearch.Add_TextChanged({ Update-CAExistingLocationFilter })
Update-CALocationHints

function Invoke-CAGuiOperation {
    param([string]$Title,[scriptblock]$Body)
    $script:Win.Cursor = [System.Windows.Input.Cursors]::Wait
    try { & $Body }
    catch {
        $message = $_.Exception.Message
        Write-CALog "ERROR [$Title]: $message"
        [void][System.Windows.MessageBox]::Show("$Title`n`n$message",$script:AppTitle,'OK','Error')
    }
    finally { $script:Win.Cursor = [System.Windows.Input.Cursors]::Arrow }
}

function Reset-CAConnectionState {
    # Never reuse tenant-specific policy plans, account exclusions, or location IDs
    # after switching directories or identities.
    $script:Tenant = $null
    $script:Plan = @()
    $script:PlanReady = $false
    $script:PreviewSignature = $null
    $script:LastExclusionIds = @()
    $script:LastNamedLocationAction = $null
    $script:AllExistingLocationItems = @()
    $script:Gui.TenantText.Text = 'Not connected'
    $script:Gui.TierText.Text = 'Not assessed'
    $script:Gui.ExistingLocations.ItemsSource = @()
    $script:Gui.ExistingLocationSearch.Text = ''
    $script:Gui.Emergency1.Text = ''
    $script:Gui.Emergency2.Text = ''
    $script:Gui.OneEmergencyAccount.IsChecked = $false
    $script:Gui.NoEmergencyAccounts.IsChecked = $false
    $script:Gui.ExcludeOperator.IsChecked = $false
    $script:Gui.LicenseAck.IsChecked = $false
    $script:Gui.CountrySearch.Text = ''
    $script:Gui.UseExistingLocation.IsChecked = $true
    $script:Gui.NewLocationName.Text = 'CA006 - Blocked countries'
    $script:Gui.IncludeUnknownCountries.IsChecked = $false
    foreach ($country in $script:Countries) { $country.Chosen = $false }
    $script:Gui.CountryGrid.Items.Refresh()
    foreach ($row in $script:Stage1) {
        $row.Selected = $false
        $row.CanDeploy = $false
        $row.Status = 'CONNECT FIRST'
        $row.StatusReason = 'Connect and refresh to check availability.'
    }
    $script:Gui.Stage1Grid.Items.Refresh()
    $script:Gui.PolicySummaryText.Text = 'Connect, refresh the tenant and select policies.'
    $script:Gui.PolicySummaryText.Foreground = [System.Windows.Media.Brushes]::DarkSlateGray
    $script:Gui.PreviewText.Text = ''
    $script:Gui.MainTabs.SelectedIndex = 0
    Update-CALocationHints
}

function Update-CATenantView {
    if (-not $script:Tenant) { return }
    $script:Gui.TenantText.Text = "$($script:Tenant['tenantId'])  /  $($script:Tenant['account'])"
    $tier = Get-CAEffectiveTier -Skus $script:Tenant['subscribedSkus']
    # Show an actual recognized subscription label, without claiming that all
    # targeted users possess licenses. Policy-level eligibility stays enforced.
    $script:Gui.TierText.Text = Get-CADetectedPlanLabel -Skus $script:Tenant['subscribedSkus']
    $locked = [System.Collections.Generic.List[string]]::new()
    foreach ($row in $script:Stage1) {
        $licenseCheck = Get-CAPolicyLicenseEligibility -Definition $row.Raw -Skus $script:Tenant['subscribedSkus']
        $row.CanDeploy = [bool]$licenseCheck.CanDeploy
        $row.RequiredLicense = [string]$licenseCheck.Required
        $row.Status = [string]$licenseCheck.Status
        $row.StatusReason = [string]$licenseCheck.Reason
        if (-not $row.CanDeploy) {
            $row.Selected = $false
            [void]$locked.Add("$($row.Code): $($row.Status) — $($row.StatusReason)")
        }
    }
    $script:Gui.Stage1Grid.Items.Refresh()
    $eligible = @($script:Stage1 | Where-Object CanDeploy).Count
    $script:Gui.PolicySummaryText.Text = "$eligible available  |  $($locked.Count) unavailable"
    $script:Gui.PolicySummaryText.Foreground = if ($eligible -gt 0) { [System.Windows.Media.Brushes]::DarkGreen } else { [System.Windows.Media.Brushes]::Firebrick }
    Write-CALog "Licensing: tenant P$tier; $eligible available policies; $($locked.Count) locked. Per-user assignments not verified."
    foreach ($reason in @($locked.ToArray())) { Write-CALog "LOCKED $reason" }
}

function Invoke-CATenantRefresh {
    $script:Tenant = Get-CATenantState
    $script:PlanReady = $false
    $script:Plan = @()
    Update-CATenantView
    $selectedId = [string]$script:Gui.ExistingLocations.SelectedValue
    $items = [System.Collections.Generic.List[object]]::new()
    foreach ($loc in @($script:Tenant['namedLocations'])) {
        if ($loc['countriesAndRegions'] -is [array]) {
            [void]$items.Add([pscustomobject]@{
                Id=[string]$loc['id']; Label="$($loc['displayName'])  [$($loc['id'])]"
            })
        }
    }
    $script:AllExistingLocationItems = @($items.ToArray())
    Update-CAExistingLocationFilter
    if ($selectedId -and @($script:AllExistingLocationItems | Where-Object { $_.Id -eq $selectedId }).Count -gt 0) {
        $script:Gui.ExistingLocations.SelectedValue = $selectedId
    } else {
        # Never silently assign a first/previous location from another tenant.
        $script:Gui.ExistingLocations.SelectedIndex = -1
    }
    $defaults = [string]$script:Tenant['securityDefaults']['isEnabled']
    Write-CALog "Tenant refreshed. Existing CA policies: $(@($script:Tenant['existingPolicies']).Count). Security Defaults enabled: $defaults"
}

function Resolve-CAEmergencyAccounts {
    $ids = [System.Collections.Generic.List[string]]::new()
    if (-not $script:Gui.NoEmergencyAccounts.IsChecked) {
        if ($script:Gui.OneEmergencyAccount.IsChecked -and
            [string]::IsNullOrWhiteSpace([string]$script:Gui.Emergency1.Text)) {
            throw 'Use one emergency account is selected. Enter the first emergency account UPN.'
        }
        $upns = if ($script:Gui.OneEmergencyAccount.IsChecked) {
            @(([string]$script:Gui.Emergency1.Text))
        } else {
            @(([string]$script:Gui.Emergency1.Text), ([string]$script:Gui.Emergency2.Text))
        }
        foreach ($upn in $upns) {
            if (-not [string]::IsNullOrWhiteSpace($upn)) {
                $user = Resolve-CAUser -UserPrincipalName $upn.Trim()
                if ([string]$user['id'] -notin $ids) { [void]$ids.Add([string]$user['id']) }
            }
        }
        if ($ids.Count -eq 0 -and -not $script:Gui.ExcludeOperator.IsChecked) {
            throw 'Enter emergency account UPN(s), or select "No Emergency accounts exist", or choose to exclude the signed-in account.'
        }
    }
    if ($script:Gui.ExcludeOperator.IsChecked) {
        # Graph /me resolves the object ID of the actual authenticated operator.
        $me = Invoke-CARequest '/me?$select=id,userPrincipalName,accountEnabled'
        if (-not $me['id'] -or $me['accountEnabled'] -eq $false) { throw 'Unable to verify the signed-in account as active.' }
        if ([string]$me['id'] -notin $ids) { [void]$ids.Add([string]$me['id']) }
    }
    $script:LastExclusionIds = @($ids.ToArray())
    return $ids.ToArray()
}

function Get-CAChosenLocation {
    if ($script:Gui.UseExistingLocation.IsChecked) {
        $value = [string]$script:Gui.ExistingLocations.SelectedValue
        if (-not $value) { throw 'Select an existing country named location from the Named Locations tab.' }
        return [ordered]@{ mode='existing'; id=$value; name=$null; countries=@(); includeUnknown=$false }
    }
    $name = ([string]$script:Gui.NewLocationName.Text).Trim()
    $countries = @(Get-CASelectedCountries)
    if ($name.Length -lt 3 -or $name.Length -gt 128) { throw 'New location name must contain 3–128 characters.' }
    if ($countries.Count -eq 0) { throw 'Select at least one country in Named Locations.' }
    return [ordered]@{ mode='new'; id=$script:PendingLocationMarker; name=$name; countries=$countries; includeUnknown=[bool]$script:Gui.IncludeUnknownCountries.IsChecked }
}

function Get-CAInputSignature {
    [void]$script:Gui.Stage1Grid.CommitEdit()
    [void]$script:Gui.Stage1Grid.CommitEdit()
    $data = [ordered]@{
        policies = @($script:Stage1 | Where-Object { $_.Selected } | ForEach-Object Code | Sort-Object)
        emergency1 = ([string]$script:Gui.Emergency1.Text).Trim().ToLowerInvariant()
        emergency2 = ([string]$script:Gui.Emergency2.Text).Trim().ToLowerInvariant()
        oneEmergency = [bool]$script:Gui.OneEmergencyAccount.IsChecked
        skipEmergency = [bool]$script:Gui.NoEmergencyAccounts.IsChecked
        excludeOperator = [bool]$script:Gui.ExcludeOperator.IsChecked
        mode = [bool]$script:Gui.CreateNewLocation.IsChecked
        existingLocation = [string]$script:Gui.ExistingLocations.SelectedValue
        newLocation = ([string]$script:Gui.NewLocationName.Text).Trim()
        countryCodes = @(Get-CASelectedCountries)
        includeUnknown = [bool]$script:Gui.IncludeUnknownCountries.IsChecked
    }
    return ConvertTo-Json -InputObject $data -Compress -Depth 12
}

function Get-CAReusableLocation {
    param([hashtable]$Tenant,[Parameter(Mandatory)]$Selection)
    $locations = @($Tenant['namedLocations'])
    $sameName = @($locations | Where-Object { [string]$_['displayName'] -ieq [string]$Selection['name'] })
    if ($sameName.Count -gt 1) { throw 'Multiple named locations use the requested name. Select an existing location explicitly.' }

    $wanted = @($Selection['countries'] | ForEach-Object { ([string]$_).ToUpperInvariant() } | Sort-Object -Unique)
    $matches = @($locations | Where-Object {
        # Reuse identical country configurations, including an older name created by
        # this builder, rather than accidentally creating a second location.
        # Do not repurpose trusted named locations.
        $current = @($_['countriesAndRegions'] | ForEach-Object { ([string]$_).ToUpperInvariant() } | Sort-Object -Unique)
        (-not [bool]$_['isTrusted']) -and
        ($current.Count -gt 0) -and
        (($current -join ',') -ceq ($wanted -join ',')) -and
        ([bool]$_['includeUnknownCountriesAndRegions'] -eq [bool]$Selection['includeUnknown']) -and
        ([string]$_['countryLookupMethod'] -in @('clientIpAddress',''))
    })
    if ($sameName.Count -eq 1) {
        if (@($matches | Where-Object { [string]$_['id'] -eq [string]$sameName[0]['id'] }).Count -lt 1) {
            throw "A named location '$($Selection['name'])' exists with different settings. Choose it explicitly or choose another name."
        }
        return [string]$sameName[0]['id']
    }
    if ($matches.Count -eq 1) { return [string]$matches[0]['id'] }
    if ($matches.Count -gt 1) {
        throw 'Multiple existing named locations have exactly the chosen country settings. Select the intended one in Use existing instead.'
    }
    return $null
}

function Update-CAPlanStatus {
    param([object[]]$Entries)
    $readyCount = @($Entries | Where-Object Status -eq 'READY').Count
    $skipCount = @($Entries | Where-Object Status -eq 'SKIP').Count
    $blockedCount = @($Entries | Where-Object Status -eq 'BLOCKED').Count
    foreach ($row in $script:Stage1) {
        if (-not $row.CanDeploy) {
            $row.Selected = $false
            # Preserve the precise licensing/implementation status from refresh.
            continue
        }
        $matches = @($Entries | Where-Object { $_.Key -eq $row.Code })
        if ($matches.Count -eq 0) {
            $row.Status = 'Not selected'
            $row.StatusReason = ''
        } else {
            $entry = $matches[0]
            $row.Status = switch ($entry.Status) { 'READY' { 'READY' } 'SKIP' { 'EXISTS / SKIP' } 'BLOCKED' { 'BLOCKED' } default { [string]$entry.Status } }
            $row.StatusReason = switch ($entry.Status) {
                'READY' { 'Validation passed' }
                'SKIP' { [string]$entry.Reason }
                'BLOCKED' { [string]$entry.Reason }
                default { [string]$entry.Reason }
            }
        }
    }
    $script:Gui.Stage1Grid.Items.Refresh()
    $script:Gui.PolicySummaryText.Text = "$readyCount ready   |   $skipCount existing / skip   |   $blockedCount blocked"
    $script:Gui.PolicySummaryText.Foreground = if ($blockedCount) {
        [System.Windows.Media.Brushes]::Firebrick
    } else {
        [System.Windows.Media.Brushes]::DarkGreen
    }
}

function Get-CAPlanBlockerMessage {
    param([object[]]$Entries)
    $blocked = @($Entries | Where-Object { $_.Status -eq 'BLOCKED' })
    if ($blocked.Count -eq 0) { return '' }
    $lines = @($blocked | ForEach-Object { "  $($_.Key) — $($_.Name): $($_.Reason)" }) -join "`n"
    return "Deployment blocked by $($blocked.Count) selected policy/policies:`n$lines`n`nFix or deselect the blocked policy, then run Preview again. See the Policies tab for details."
}

function Build-CAPlan {
    param([switch]$RequireNoErrors)
    if (-not $script:Tenant) { throw 'Connect and refresh the tenant first.' }
    $ctx = Get-MgContext
    if (-not $ctx -or [string]$ctx.TenantId -ne [string]$script:Tenant['tenantId']) { throw 'Graph session has changed. Refresh tenant discovery.' }
    if ($script:Tenant['securityDefaults']['isEnabled'] -ne $false) { throw 'Security Defaults must be verifiably disabled for CA deployment. This tool will never change it automatically.' }
    [void]$script:Gui.Stage1Grid.CommitEdit()
    [void]$script:Gui.Stage1Grid.CommitEdit()
    $stage = @($script:Stage1 | Where-Object { $_.Selected })
    Update-CALocationHints
    if ($stage.Count -lt 1) { throw 'Select at least one policy.' }
    $ids = @(Resolve-CAEmergencyAccounts)
    $location = $null
    if (@($stage | Where-Object Code -eq 'CA006').Count -gt 0) { $location = Get-CAChosenLocation }
    $tier = Get-CAEffectiveTier -Skus $script:Tenant['subscribedSkus']
    if ($tier -lt 1) { throw 'No qualifying P1 or P2 subscription found. Entra Free is not supported for deployment.' }
    $entries = [System.Collections.Generic.List[object]]::new()
    foreach ($row in $stage) {
        try {
            # Never trust stale or manually altered GUI selections for authorization.
            $eligibility = Get-CAPolicyLicenseEligibility -Definition $row.Raw -Skus $script:Tenant['subscribedSkus']
            if (-not $eligibility.CanDeploy) { throw "$($eligibility.Status): $($eligibility.Reason)" }
            $locationId = ''
            if ($row.Code -eq 'CA006') {
                if ($location['mode'] -eq 'new') {
                    $reuse = Get-CAReusableLocation -Tenant $script:Tenant -Selection $location
                    $locationId = if ($reuse) { $reuse } else { $script:PendingLocationMarker }
                } else { $locationId = [string]$location['id'] }
            }
            $payload = New-CAStage1Policy -Definition $row.Raw -Tenant $script:Tenant -EmergencyIds $ids -BlockedLocation $locationId
            $duplicate = Get-CADuplicate -Payload $payload -ExistingPolicies $script:Tenant['existingPolicies']
            [void]$entries.Add([pscustomobject]@{ Kind='Stage1'; Key=$row.Code; Name=$row.Name; Status= if ($duplicate) {'SKIP'} else {'READY'}; Reason=$duplicate; Payload=$payload })
        } catch {
            [void]$entries.Add([pscustomobject]@{ Kind='Stage1'; Key=$row.Code; Name=$row.Name; Status='BLOCKED'; Reason=$_.Exception.Message; Payload=$null })
        }
    }
    $plan = @($entries.ToArray())
    Update-CAPlanStatus -Entries $plan
    $blockedMessage = Get-CAPlanBlockerMessage -Entries $plan
    if ($RequireNoErrors -and $blockedMessage) {
        $script:Gui.MainTabs.SelectedIndex = 0
        foreach ($blocked in @($plan | Where-Object Status -eq 'BLOCKED')) {
            Write-CALog "BLOCKED $($blocked.Key) ($($blocked.Name)): $($blocked.Reason)"
        }
        throw $blockedMessage
    }
    return $plan
}

function ConvertTo-CAStableFingerprintValue {
    param($Value)
    if ($null -eq $Value) { return $null }
    if ($Value -is [System.Collections.IDictionary]) {
        $ordered = [ordered]@{}
        foreach ($key in @($Value.Keys | Sort-Object)) {
            $ordered[[string]$key] = ConvertTo-CAStableFingerprintValue -Value $Value[$key]
        }
        return $ordered
    }
    if ($Value -is [array]) {
        $items = [System.Collections.Generic.List[object]]::new()
        foreach ($item in $Value) {
            [void]$items.Add((ConvertTo-CAStableFingerprintValue -Value $item))
        }
        return ,$items.ToArray()
    }
    return $Value
}

function Get-CAPlanFingerprint {
    param([object[]]$Entries)
    # Deterministic comparison of policy contents, irrespective of hashtable key ordering.
    $items = @($Entries | Sort-Object Key | ForEach-Object {
        [ordered]@{
            key = [string]$_.Key
            status = [string]$_.Status
            payload = ConvertTo-CAStableFingerprintValue -Value $_.Payload
        }
    })
    return ConvertTo-Json -InputObject $items -Depth 100 -Compress
}

function Show-CAPlan {
    param([object[]]$Entries)
    $summary = [System.Collections.Generic.List[object]]::new()
    foreach ($entry in $Entries) {
        [void]$summary.Add([ordered]@{ policy=$entry.Key; name=$entry.Name; status=$entry.Status; reason=$entry.Reason; payload=$entry.Payload })
    }
    $preview = [ordered]@{
        warning = 'Report-only preview; policies are not enforced. Microsoft recommends two emergency access accounts. Skipping emergency exclusions can be dangerous if policies are later enabled. User licensing coverage must be separately confirmed.'
        tenantId = $script:Tenant['tenantId']
        operator = $script:Tenant['account']
        generatedAt = (Get-Date).ToUniversalTime().ToString('o')
        exclusions = @($script:LastExclusionIds)
        location = if (@($Entries | Where-Object Key -eq 'CA006').Count -gt 0) { Get-CAChosenLocation } else { $null }
        policies = $summary.ToArray()
    }
    $script:Gui.PreviewText.Text = ConvertTo-Json -InputObject $preview -Depth 100
    $blockers = @($Entries | Where-Object Status -eq 'BLOCKED')
    $script:Gui.MainTabs.SelectedIndex = if ($blockers.Count -gt 0) { 0 } else { 2 }
    Write-CALog "Plan: $(@($Entries | Where-Object Status -eq 'READY').Count) ready; $(@($Entries | Where-Object Status -eq 'SKIP').Count) existing/skip; $($blockers.Count) blocked."
    foreach ($entry in $blockers) {
        Write-CALog "BLOCKED $($entry.Key) ($($entry.Name)): $($entry.Reason)"
    }
    foreach ($entry in @($Entries | Where-Object Status -eq 'SKIP')) {
        Write-CALog "SKIPPED $($entry.Key) ($($entry.Name)): $($entry.Reason)"
    }
}

$script:Gui.ConnectButton.Add_Click({
    Invoke-CAGuiOperation 'Graph sign-in' {
        # Signing in always begins with a clean process-scoped Graph context.
        Reset-CAConnectionState
        $c = Connect-CADiscovery
        $script:Gui.TenantText.Text = "$($c.TenantId)  /  $($c.Account)"
        Write-CALog "Connected to tenant $($c.TenantId) as $($c.Account). Refresh tenant before Preview."
    }
})
$script:Gui.SignOutButton.Add_Click({
    Invoke-CAGuiOperation 'Graph sign-out' {
        # Clear tenant-specific GUI state even if Graph disconnect raises an error.
        try { Disconnect-CADiscovery }
        finally { Reset-CAConnectionState }
        Write-CALog 'Signed out. Tenant-specific policy selections, exclusions, and previews cleared. Click Connect to sign in again.'
    }
})
$script:Gui.RefreshButton.Add_Click({ Invoke-CAGuiOperation 'Refresh discovery' { Invoke-CATenantRefresh } })
$script:Gui.PreviewButton.Add_Click({
    Invoke-CAGuiOperation 'Policy preview' {
        $script:PlanReady = $false
        $script:Plan = @(Build-CAPlan)
        Show-CAPlan -Entries $script:Plan
        $script:PreviewSignature = Get-CAInputSignature
        $script:PlanReady = $true
    }
})
function Write-CADeploymentJournal {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$File,
        [Parameter(Mandatory)][string]$Code,
        [Parameter(Mandatory)][string]$Event,
        [string]$PolicyId = '',
        [string]$Message = ''
    )
    # Record successful POST acknowledgement BEFORE any Graph read-back. Prevents
    # a missing ID in a failure report when GET returns a transient 404.
    $row = [ordered]@{
        utc = (Get-Date).ToUniversalTime().ToString('o')
        tenantId = [string]$script:Tenant['tenantId']
        code = $Code
        event = $Event
        id = $PolicyId
        message = $Message
    }
    Add-Content -LiteralPath $File -Value (ConvertTo-Json -InputObject $row -Depth 10 -Compress) -Encoding utf8
}

$script:Gui.DeployButton.Add_Click({
    Invoke-CAGuiOperation 'Report-only deployment' {
        if (-not $script:PlanReady) { throw 'Preview is required before deployment.' }
        if ((Get-CAInputSignature) -cne $script:PreviewSignature) { throw 'Inputs changed since Preview. Run Preview again before deploying.' }
        $blockers = Get-CAPlanBlockerMessage -Entries $script:Plan
        if ($blockers) {
            $script:Gui.MainTabs.SelectedIndex = 0
            Write-CALog $blockers
            throw $blockers
        }
        # Requested on initial Graph connection; still check immediately before write.
        Assert-CAWritePermission

        if (-not $script:Gui.LicenseAck.IsChecked) { throw 'Confirm that targeted users are appropriately licensed.' }
        $ctx = Get-MgContext
        if ([string]$ctx.TenantId -ne [string]$script:Tenant['tenantId']) { throw 'Connected tenant changed since preview.' }
        # Always re-read tenant state and reconstruct the deployment plan.
        # If anything changed since the last approved Preview, force a new preview.
        $approvedPlanFingerprint = Get-CAPlanFingerprint -Entries $script:Plan
        Invoke-CATenantRefresh
        $rechecked = @(Build-CAPlan -RequireNoErrors)
        if ((Get-CAPlanFingerprint -Entries $rechecked) -cne $approvedPlanFingerprint) {
            $script:Plan = $rechecked
            Show-CAPlan -Entries $rechecked
            throw 'Policy plan changed after the last preview (for example, another administrator created a policy). Review the new preview and click Preview again before deploying.'
        }
        $ready = @($rechecked | Where-Object Status -eq 'READY')
        if ($ready.Count -eq 0) { throw 'No new policies require creation.' }
        $policyLines = ($ready | ForEach-Object { "  - $($_.Key): $($_.Name)" }) -join "`n"
        $locationPlan = $null
        $needsLocationCreation = $false
        if (@($ready | Where-Object Key -eq 'CA006').Count -gt 0) {
            $locationPlan = Get-CAChosenLocation
            if ($locationPlan['mode'] -eq 'new') {
                $existingId = Get-CAReusableLocation -Tenant $script:Tenant -Selection $locationPlan
                $needsLocationCreation = -not [bool]$existingId
            }
        }
        $locationInfo = if ($needsLocationCreation) { "`nADDITIONAL CHANGE: Create country-based named location '$($locationPlan['name'])' ($(@($locationPlan['countries']).Count) countries)." } else { '' }
        $exclusionInfo = if ($script:LastExclusionIds.Count -eq 0) { "`nWARNING: NO USER EXCLUSIONS configured. These report-only policies may affect access if enabled later!" } else { "`nExcluded user IDs: $($script:LastExclusionIds -join ', ')" }
        $betaNotice = if (@($ready | Where-Object { $_.Key -eq 'CA011' }).Count -gt 0) {
            "`n`nCA011 uses Microsoft Graph BETA because its risk-remediation grant control is a preview feature. Preview APIs may change."
        } else { '' }
        $message = "TARGET TENANT: $($ctx.TenantId)`nSIGNED IN: $($ctx.Account)`n`nCREATE $($ready.Count) REPORT-ONLY policies:`n$policyLines$locationInfo$exclusionInfo$betaNotice`n`nNo existing policies will be changed or enabled.`n`nDo you confirm deployment to THIS tenant?"
        $answer = [System.Windows.MessageBox]::Show($message,$script:AppTitle,'YesNo','Warning')
        if ($answer -ne 'Yes') { Write-CALog 'Deployment canceled by administrator.'; return }
        $report = [System.Collections.Generic.List[object]]::new()
        $script:LastNamedLocationAction = $null
        if ($needsLocationCreation) {
            try {
                # Recheck before creating to avoid duplicates (or silent modification).
                $currentLocations = @(Get-CACollection '/identity/conditionalAccess/namedLocations')
                $locationState = @{ namedLocations = $currentLocations }
                $reuseId = Get-CAReusableLocation -Tenant $locationState -Selection $locationPlan
                if ($reuseId) {
                    $createdLocationId = $reuseId
                    $script:LastNamedLocationAction = [ordered]@{ action='Reused'; id=$createdLocationId; name=$locationPlan['name'] }
                    Write-CALog "Existing named location reused for CA006: $($locationPlan['name']) [$createdLocationId]"
                } else {
                    $newLoc = New-CACountryNamedLocation -Name $locationPlan['name'] -Countries $locationPlan['countries'] -IncludeUnknown $locationPlan['includeUnknown']
                    $createdLocationId = [string]$newLoc['id']
                    # Verify the resulting named location ID and contents before using it.
                    # Graph can be eventually consistent immediately after a successful create.
                    $verifiedLoc = $null
                    for ($readAttempt = 1; $readAttempt -le 5; $readAttempt++) {
                        try {
                            $verifiedLoc = Invoke-CARequest "/identity/conditionalAccess/namedLocations/$createdLocationId"
                            break
                        } catch {
                            if ($readAttempt -eq 5) { throw "Named location was created [$createdLocationId], but Graph read-back failed: $($_.Exception.Message). CA006 has NOT been posted." }
                            Start-Sleep -Milliseconds (500 * $readAttempt)
                        }
                    }
                    $verifiedCodes = @($verifiedLoc['countriesAndRegions'] | Sort-Object -Unique)
                    $expectedCodes = @($locationPlan['countries'] | Sort-Object -Unique)
                    if (($verifiedCodes -join ',') -cne ($expectedCodes -join ',') -or
                        [string]$verifiedLoc['displayName'] -cne [string]$locationPlan['name'] -or
                        [bool]$verifiedLoc['includeUnknownCountriesAndRegions'] -ne [bool]$locationPlan['includeUnknown']) {
                        throw 'Named location read-back verification failed; inspect before retrying.'
                    }
                    $script:LastNamedLocationAction = [ordered]@{ action='Created'; id=$createdLocationId; name=$locationPlan['name'] }
                    Write-CALog "Created country named location: $($locationPlan['name']) [$createdLocationId]. Next step: create report-only CA006."
                }
                foreach ($entry in $ready) {
                    if ($entry.Key -eq 'CA006') { $entry.Payload['conditions']['locations']['includeLocations'] = @($createdLocationId) }
                }
            } catch {
                Write-CALog "Named location creation/reuse failed: $($_.Exception.Message). No CA policies were posted."
                throw
            }
        }
        elseif ($locationPlan -and $locationPlan['mode'] -eq 'new') {
            $reusedId = Get-CAReusableLocation -Tenant $script:Tenant -Selection $locationPlan
            if (-not $reusedId) { throw 'CA006 requires a named location but the existing location could not be resolved.' }
            $script:LastNamedLocationAction = [ordered]@{ action='Reused'; id=$reusedId; name=$locationPlan['name'] }
            Write-CALog "Reusing named location for CA006: $($locationPlan['name']) [$reusedId]"
            foreach ($entry in $ready) {
                if ($entry.Key -eq 'CA006') { $entry.Payload['conditions']['locations']['includeLocations'] = @($reusedId) }
            }
        }
        # Never send a placeholder location ID to Graph.
        foreach ($entry in $ready) {
            $bodyText = ConvertTo-Json -InputObject $entry.Payload -Depth 100 -Compress
            if ($bodyText.Contains($script:PendingLocationMarker)) { throw "Unresolved location ID for $($entry.Key). No policy writes attempted." }
        }
        $reportFolder = $script:ReportDirectory
        if (-not (Test-Path -LiteralPath $reportFolder -PathType Container)) {
            [void](New-Item -ItemType Directory -Path $reportFolder -Force)
        }
        $runStamp = (Get-Date -Format 'yyyyMMdd-HHmmss-fff')
        $journalFile = Join-Path $reportFolder ("deployment-$runStamp.journal.jsonl")
        foreach ($entry in $ready) {
            $phase = 'Preflight'
            $postedId = ''
            try {
                Write-CALog "Checking $($entry.Key) before report-only creation..."
                if ($entry.Payload['state'] -cne 'enabledForReportingButNotEnforced') {
                    throw 'Payload state differs from report-only.'
                }
                # Recheck existence. A previous run might have created a policy
                # even if its immediate GET failed with 404.
                $live = @(Get-CACollection '/identity/conditionalAccess/policies')
                $found = Get-CADuplicate -Payload $entry.Payload -ExistingPolicies $live
                if (-not $found -and $entry.Key -eq 'CA011') {
                    # Risk-remediation policies can contain preview-only data.
                    # Check the beta inventory as well so a prior beta-created
                    # CA011 cannot be silently duplicated after an uncertain run.
                    $betaInventory = @(Get-CACollection -Path '/identity/conditionalAccess/policies' -ApiVersion beta)
                    $found = Get-CADuplicate -Payload $entry.Payload -ExistingPolicies $betaInventory
                }
                if ($found) {
                    [void]$report.Add([ordered]@{ code=$entry.Key; id=$null; status='SkippedExisting'; message=$found })
                    Write-CADeploymentJournal -File $journalFile -Code $entry.Key -Event 'SkippedExisting' -Message $found
                    Write-CALog "SKIPPED $($entry.Key): $found"
                    continue
                }
                if ($entry.Key -eq 'CA006') {
                    $targetLocationId = [string]$entry.Payload['conditions']['locations']['includeLocations'][0]
                    $locationCheck = Invoke-CARequest "/identity/conditionalAccess/namedLocations/$targetLocationId"
                    if (-not $locationCheck['id']) { throw "CA006 named location $targetLocationId did not resolve; policy was NOT posted." }
                }
                # This is the only policy-creation POST. Never retry automatically.
                $phase = 'Post'
                Write-CADeploymentJournal -File $journalFile -Code $entry.Key -Event 'PostStarted' -Message 'Submitting report-only policy; do not automatically retry on an uncertain response.'
                Write-CALog "POST report-only $($entry.Key) ($($entry.Name))..."
                # CA011 riskRemediation requires Graph beta in the tested tenant
                # (Graph error 1038); all other policy POSTs use Graph v1.0.
                $policyApi = if ($entry.Key -eq 'CA011') { 'beta' } else { 'v1.0' }
                $created = Invoke-CARequest -Path '/identity/conditionalAccess/policies' -Method POST -ApiVersion $policyApi -Body $entry.Payload
                $postedId = [string]$created['id']
                if ([string]::IsNullOrWhiteSpace($postedId)) {
                    throw 'POST response did not include a policy ID. Creation outcome unknown; inspect tenant before retrying.'
                }
                # Must persist acknowledgement before read-back, even if verification fails.
                Write-CADeploymentJournal -File $journalFile -Code $entry.Key -Event 'PostAcknowledged' -PolicyId $postedId
                Write-CALog "Graph accepted $($entry.Key) and returned policy ID $postedId; verifying..."
                $phase = 'Verify'
                $check = Confirm-CACreatedPolicy -PolicyId $postedId -ExpectedName ([string]$entry.Payload['displayName']) -ApiVersion $policyApi
                if (-not $check.Verified) {
                    $message = [string]$check.Message
                    [void]$report.Add([ordered]@{ code=$entry.Key; id=$postedId; status='CreatedPendingVerification'; message=$message })
                    Write-CADeploymentJournal -File $journalFile -Code $entry.Key -Event 'PendingVerification' -PolicyId $postedId -Message $message
                    Write-CALog "PENDING VERIFICATION $($entry.Key), ID=$postedId. $message Remaining writes stopped; do NOT create this policy again."
                    $script:Gui.MainTabs.SelectedIndex = 3
                    break
                }
                [void]$report.Add([ordered]@{ code=$entry.Key; id=$postedId; status='CreatedAndVerified'; state='enabledForReportingButNotEnforced'; verifiedVia=$check.Via })
                Write-CADeploymentJournal -File $journalFile -Code $entry.Key -Event 'Verified' -PolicyId $postedId -Message $check.Via
                Write-CALog "CREATED + VERIFIED $($entry.Key), ID=$postedId ($($check.Via))"
            } catch {
                $message = $_.Exception.Message
                # A well-formed HTTP 400 is a definitive Graph rejection, not
                # an ambiguous timeout. Never present it as possibly created.
                $status = if ($postedId) { 'CreatedPendingVerification' } elseif ($phase -eq 'Post' -and $message -match '(?i)\bHTTP (?:400|401|403|422)\b') { 'RejectedByGraph' } elseif ($phase -eq 'Post') { 'OutcomeUnconfirmed' } else { 'PreflightFailed' }
                [void]$report.Add([ordered]@{ code=$entry.Key; id=$postedId; status=$status; phase=$phase; message=$message })
                Write-CADeploymentJournal -File $journalFile -Code $entry.Key -Event $status -PolicyId $postedId -Message "${phase}: $message"
                Write-CALog "$status on $($entry.Key) at $phase phase, policy ID='$postedId': $message. Further policy writes stopped. Refresh and reconcile tenant state before retrying."
                $script:Gui.MainTabs.SelectedIndex = 3
                break
            }
        }
        $file = Join-Path $reportFolder ("deployment-$runStamp.json")
        [ordered]@{ tenantId=$ctx.TenantId; operator=$ctx.Account; utc=(Get-Date).ToUniversalTime().ToString('o'); namedLocation=$script:LastNamedLocationAction; results=$report.ToArray() } | ConvertTo-Json -Depth 100 | Set-Content -Path $file -Encoding utf8
        $script:PlanReady = $false
        $createdCount = @($report.ToArray() | Where-Object { $_['status'] -eq 'CreatedAndVerified' }).Count
        $skipped = @($report.ToArray() | Where-Object { $_['status'] -eq 'SkippedExisting' })
        $pending = @($report.ToArray() | Where-Object { $_['status'] -eq 'CreatedPendingVerification' })
        $unknown = @($report.ToArray() | Where-Object { $_['status'] -eq 'OutcomeUnconfirmed' })
        $rejected = @($report.ToArray() | Where-Object { $_['status'] -eq 'RejectedByGraph' })
        $failed = @($report.ToArray() | Where-Object { $_['status'] -eq 'PreflightFailed' })
        Write-CALog "Deployment summary: $createdCount verified; $($skipped.Count) existing/skipped; $($pending.Count) created/pending; $($unknown.Count) uncertain outcome; $($rejected.Count) Graph rejections; $($failed.Count) preflight failures. Report: $file. Journal: $journalFile"
        $script:Gui.MainTabs.SelectedIndex = 3
        if ($pending.Count -gt 0 -or $unknown.Count -gt 0 -or $rejected.Count -gt 0 -or $failed.Count -gt 0) {
            $problem = @($pending + $unknown + $rejected + $failed)[0]
            $locNotice = if ($script:LastNamedLocationAction) {
                "`n`nNamed location $($script:LastNamedLocationAction['action'].ToLowerInvariant()): $($script:LastNamedLocationAction['name']) [$($script:LastNamedLocationAction['id'])]."
            } else { '' }
            $idNotice = if ($problem['id']) { "`nPolicy ID: $($problem['id'])" } elseif ($problem['status'] -eq 'RejectedByGraph') { "`nGraph rejected the request before policy creation." } else { "`nPolicy ID unavailable; creation cannot be ruled out." }
            $failureMessage = "Deployment needs review.`n`nVerified: $createdCount | Skipped: $($skipped.Count) | Pending: $($pending.Count) | Unconfirmed: $($unknown.Count) | Rejected: $($rejected.Count) | Invalid: $($failed.Count)`n`n$($problem['code']): $($problem['status'])$idNotice`n$($problem['message'])$locNotice`n`nDo not retry until you refresh and inspect the tenant. See Activity Log for report location."
            [void][System.Windows.MessageBox]::Show($failureMessage,$script:AppTitle,'OK','Warning')
        } else {
            [void][System.Windows.MessageBox]::Show("Deployment complete.`n`nCreated and verified: $createdCount`nAlready existed: $($skipped.Count)`n`nAll created policies are report-only.`nDetails: Activity Log",$script:AppTitle,'OK','Information')
        }
    }
})

Write-CALog 'Ready. Connect, refresh tenant, select policies, and Preview. Sign out clears tenant-specific data.'
Write-CALog 'One or two emergency accounts are supported; a dedicated checkbox uses one account only. Skipping emergency exclusions is allowed for report-only testing with a safety warning. CA007 is visibly unavailable and cannot be selected. Stage 2 is hidden. Country-location creation is tied to CA006.'
[void]$script:Win.ShowDialog()
