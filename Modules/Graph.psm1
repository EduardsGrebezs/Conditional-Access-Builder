Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function ConvertTo-CAHash {
    param([Parameter(Mandatory)]$Value)
    return ($Value | ConvertTo-Json -Depth 100 -Compress | ConvertFrom-Json -AsHashtable -Depth 100)
}

function Get-CAGraphErrorDetails {
    <#
      Extract only the Graph error code/message and status. Do not log tokens,
      authorization headers, complete HTTP requests or submitted policy JSON.
      The administrator's local Reports folder may still hold tenant metadata.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Record)
    $status = 0
    try { $status = [int]$Record.Exception.Response.StatusCode } catch {}
    $raw = ''
    try { $raw = [string]$Record.ErrorDetails.Message } catch {}
    if ([string]::IsNullOrWhiteSpace($raw)) {
        try {
            if ($Record.Exception.Response.Content) {
                $raw = [string]$Record.Exception.Response.Content.ReadAsStringAsync().GetAwaiter().GetResult()
            }
        } catch {}
    }
    $code = ''
    $message = ''
    if (-not [string]::IsNullOrWhiteSpace($raw)) {
        # PowerShell Graph exceptions sometimes prefix the JSON body with a
        # full HTTP response. Prefer the actual Graph error code/message.
        $jsonStart = $raw.IndexOf('{"error"', [System.StringComparison]::OrdinalIgnoreCase)
        if ($jsonStart -ge 0) { $raw = $raw.Substring($jsonStart).Trim() }
        try {
            $parsed = ConvertFrom-Json -InputObject $raw -AsHashtable -ErrorAction Stop
            if ($parsed['error']) {
                $code = [string]$parsed['error']['code']
                $message = [string]$parsed['error']['message']
            }
        } catch {}
        if (-not $message) { $message = $raw }
    }
    if (-not $message) {
        $exceptionText = [string]$Record.Exception.Message
        $start = $exceptionText.IndexOf('{"error"', [System.StringComparison]::OrdinalIgnoreCase)
        if ($start -ge 0) {
            try {
                $jsonBody = ConvertFrom-Json -InputObject $exceptionText.Substring($start) -AsHashtable -ErrorAction Stop
                $code = [string]$jsonBody['error']['code']
                $message = [string]$jsonBody['error']['message']
            } catch {}
        }
        if (-not $message) { $message = $exceptionText }
    }
    if ($status -eq 0) {
        $search = [string]$Record.Exception.Message
        if ($search -match '(?i)\bBadRequest\b|\bBad Request\b') { $status = 400 }
        elseif ($search -match '(?i)\bForbidden\b') { $status = 403 }
        elseif ($search -match '(?i)\bUnauthorized\b') { $status = 401 }
    }
    $message = $message -replace '(?i)Bearer\s+[^\s,;]+','Bearer [redacted]'
    if ($message.Length -gt 550) { $message = $message.Substring(0,550) + ' [see report for details]' }
    $label = if ($status -gt 0) { "HTTP $status" } else { 'HTTP status unknown' }
    if ($code) { $label += " [$code]" }
    return "${label}: $message"
}

function Invoke-CARequest {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Path,
        [ValidateSet('GET','POST')][string]$Method = 'GET',
        [ValidateSet('v1.0','beta')][string]$ApiVersion = 'v1.0',
        [hashtable]$Body
    )
    # Graph collection pagination uses absolute @odata.nextLink URLs.
    # Accept only graph.microsoft.com and an explicit supported API version.
    if ($Path -match '^https://graph\.microsoft\.com/(?<version>v1\.0|beta)(?<relative>/.*)$') {
        $ApiVersion = [string]$Matches['version']
        $Path = [string]$Matches['relative']
    }
    # Graph beta is allowed only for CA011 riskRemediation and its read-back.
    # All other Conditional Access policy creation remains on Graph v1.0.
    if ($ApiVersion -eq 'beta') {
        if ($Path -notmatch '^/identity/conditionalAccess/policies(?:/[0-9a-fA-F-]{36})?(?:\?.*)?$') {
            throw 'Graph beta is restricted to Conditional Access policy create/verification.'
        }
        if ($Method -eq 'POST' -and ($null -eq $Body -or
                -not (@($Body['grantControls']['builtInControls']) -contains 'riskRemediation') -or
                [string]$Body['displayName'] -notmatch '^CA011\s*-')) {
            throw 'Graph beta POST is permitted only for CA011 risk-remediation payloads.'
        }
    }
    if (-not $Path.StartsWith('/')) { throw 'Graph path must start with /' }
    $uri = "https://graph.microsoft.com/$ApiVersion$Path"
    # Validate report-only and beta-policy allowlists before checking for the
    # installed Graph module, so unsafe calls always fail closed locally.
    if ($Method -eq 'POST' -and ($null -eq $Body -or $Body.state -cne 'enabledForReportingButNotEnforced')) {
        throw 'Safety invariant: only enabledForReportingButNotEnforced payloads may be posted.'
    }
    if (-not (Get-Command Invoke-MgGraphRequest -ErrorAction SilentlyContinue)) {
        throw 'Microsoft.Graph.Authentication not installed. Run: Install-Module Microsoft.Graph.Authentication -Scope CurrentUser'
    }
    $headers = @{ 'Prefer' = 'include-unknown-enum-members' }
    if ($Method -eq 'POST') {
        if ($null -eq $Body -or $Body.state -cne 'enabledForReportingButNotEnforced') {
            throw 'Safety invariant: only enabledForReportingButNotEnforced payloads may be posted.'
        }
        $json = ConvertTo-Json -InputObject $Body -Depth 100 -Compress
        if ($json.Contains('PENDING-COUNTRY-NAMED-LOCATION')) { throw 'Safety invariant: unresolved location cannot be deployed.' }
        # Never retry a POST with an uncertain result (a network failure may follow server creation).
        try {
            $response = Invoke-MgGraphRequest -Uri $uri -Method POST -Headers $headers -ContentType 'application/json' -Body $json -OutputType PSObject -ErrorAction Stop
        } catch {
            $detail = Get-CAGraphErrorDetails -Record $_
            throw "Graph POST $Path failed: $detail"
        }
    } else {
        for ($attempt = 0; $attempt -lt 3; $attempt++) {
            try {
                $response = Invoke-MgGraphRequest -Uri $uri -Method GET -Headers $headers -OutputType PSObject -ErrorAction Stop
                break
            } catch {
                if ($attempt -eq 2 -or $_.Exception.Message -notmatch '(429|503|504|throttl|temporar)') { throw }
                Start-Sleep -Seconds ([math]::Pow(2,$attempt + 1))
            }
        }
    }
    if ($null -eq $response) { throw "Graph returned no body: $Method $Path" }
    return ConvertTo-CAHash $response
}

function Confirm-CACreatedPolicy {
    <#
    .SYNOPSIS
        Verify a POST-acknowledged policy with bounded eventual-consistency retries.
    .NOTES
        NEVER posts. An existing Graph ID is preserved even if read-back fails.
        404 following a successful 201 can be a read-after-create delay.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$PolicyId,
        [Parameter(Mandatory)][string]$ExpectedName,
        [ValidateSet('v1.0','beta')][string]$ApiVersion = 'v1.0',
        [string]$ExpectedState = 'enabledForReportingButNotEnforced',
        [ValidateRange(1,20)][int]$Attempts = 8,
        [ValidateRange(0,10000)][int]$DelayMilliseconds = 750
    )
    $lastError = ''
    for ($i = 1; $i -le $Attempts; $i++) {
        try {
            $observed = Invoke-CARequest -Path "/identity/conditionalAccess/policies/$PolicyId" -ApiVersion $ApiVersion
            if ([string]$observed['id'] -ine $PolicyId) {
                throw "Unexpected policy ID returned for verification of $PolicyId."
            }
            if ([string]$observed['displayName'] -cne $ExpectedName) {
                throw "Policy $PolicyId was created, but its name differs from the submitted policy."
            }
            if ([string]$observed['state'] -cne $ExpectedState) {
                throw "Policy $PolicyId has state '$($observed['state'])', not the requested report-only state. Review immediately."
            }
            return [pscustomobject]@{ Verified=$true; Id=$PolicyId; Via='GET by ID'; Attempts=$i; Message='Read-back verified' }
        } catch {
            $lastError = $_.Exception.Message
            # A response can briefly be absent from the read replica; do not POST again.
            if ($lastError -notmatch '(?i)(NotFound|not found|404|429|503|504|throttl|temporar)') {
                return [pscustomobject]@{ Verified=$false; Id=$PolicyId; Via='GET by ID'; Attempts=$i; Message="Read-back could not verify the created policy: $lastError" }
            }
        }
        if ($i -lt $Attempts -and $DelayMilliseconds -gt 0) {
            Start-Sleep -Milliseconds ([math]::Min(10000,$DelayMilliseconds * $i))
        }
    }
    # The listing may become consistent before the per-ID GET endpoint.
    try {
        # The beta policy may not be fully represented by the v1.0 listing.
        # Use the matching API version for fallback verification.
        $inventory = if ($ApiVersion -eq 'beta') {
            @(Get-CACollection -Path '/identity/conditionalAccess/policies' -ApiVersion 'beta')
        } else { @(Get-CACollection '/identity/conditionalAccess/policies') }
        $matches = @($inventory | Where-Object { [string]$_['id'] -ieq $PolicyId })
        if ($matches.Count -eq 1) {
            $observed = $matches[0]
            if ([string]$observed['displayName'] -cne $ExpectedName -or [string]$observed['state'] -cne $ExpectedState) {
                return [pscustomobject]@{ Verified=$false; Id=$PolicyId; Via='List by ID'; Attempts=$Attempts; Message='Policy exists but name or report-only state differs. Manual review required.' }
            }
            return [pscustomobject]@{ Verified=$true; Id=$PolicyId; Via='List by ID'; Attempts=$Attempts; Message='Verified through policy inventory' }
        }
    } catch {
        $lastError += "; listing failed: $($_.Exception.Message)"
    }
    return [pscustomobject]@{
        Verified=$false; Id=$PolicyId; Via='GET / List'; Attempts=$Attempts
        Message="Policy POST returned ID $PolicyId, but Graph has not confirmed read-back. Last issue: $lastError. Do not recreate; refresh and verify this ID."
    }
}

function New-CACountryNamedLocation {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Name,
          [Parameter(Mandatory)][string[]]$Countries,
          [bool]$IncludeUnknown = $false)
    if ($Name.Trim().Length -lt 3 -or $Name.Trim().Length -gt 128) { throw 'Named location name must be between 3 and 128 characters.' }
    $codes = @($Countries | ForEach-Object { $_.Trim().ToUpperInvariant() } | Sort-Object -Unique)
    if ($codes.Count -lt 1) { throw 'Select at least one country before creating a named location.' }
    foreach ($code in $codes) {
        if ($code -cnotmatch '^[A-Z]{2}$') { throw "Invalid ISO country code: $code" }
    }
    Assert-CAWritePermission
    $body = @{
        '@odata.type' = '#microsoft.graph.countryNamedLocation'
        displayName = $Name.Trim()
        countriesAndRegions = $codes
        countryLookupMethod = 'clientIpAddress'
        includeUnknownCountriesAndRegions = $IncludeUnknown
    }
    # This is the ONLY non-policy POST in the builder. Named locations do not
    # enforce anything alone; creation requires separate final confirmation.
    $uri = 'https://graph.microsoft.com/v1.0/identity/conditionalAccess/namedLocations'
    $json = ConvertTo-Json -InputObject $body -Depth 12 -Compress
    $result = Invoke-MgGraphRequest -Uri $uri -Method POST -ContentType 'application/json' -Body $json -OutputType PSObject -ErrorAction Stop
    if (-not $result) { throw 'Named location POST returned no response. Check the tenant before retrying.' }
    $created = ConvertTo-CAHash $result
    if (-not $created['id']) { throw 'Named location creation returned no ID. Check the tenant before retrying.' }
    return $created
}

function Get-CACollection {
    param([Parameter(Mandatory)][string]$Path,
          [ValidateSet('v1.0','beta')][string]$ApiVersion = 'v1.0')
    $result = [System.Collections.Generic.List[object]]::new()
    $next = $Path
    do {
        $page = Invoke-CARequest -Path $next -ApiVersion $ApiVersion
        foreach ($entry in @($page['value'])) { if ($null -ne $entry) { [void]$result.Add($entry) } }
        $next = [string]$page['@odata.nextLink']
    } while (-not [string]::IsNullOrWhiteSpace($next))
    return $result.ToArray()
}

function Get-CARequiredScopes {
    # Request both read and write delegated permissions at initial sign-in.
    # Obtaining a scope does NOT write policies or override admin consent / Entra roles.
    return @(
        'Policy.Read.All'
        'Policy.ReadWrite.ConditionalAccess'
        'LicenseAssignment.Read.All'
        'User.Read.All'
        'RoleManagement.Read.Directory'
    )
}

function Assert-CAWritePermission {
    $ctx = Get-MgContext
    if (-not $ctx -or -not (@($ctx.Scopes) -contains 'Policy.ReadWrite.ConditionalAccess')) {
        throw 'Microsoft Graph write permission is not available. Reconnect and approve Policy.ReadWrite.ConditionalAccess. If your tenant requires admin consent, an authorized administrator must grant it. You also need a supported Entra role for policy creation.'
    }
}

function Disconnect-CADiscovery {
    # The app uses process-scoped auth; clearing this context prevents accidentally
    # reusing a token obtained for a different tenant within the same GUI session.
    if (Get-Command Get-MgContext -ErrorAction SilentlyContinue) {
        $ctx = Get-MgContext
        if ($ctx) { Disconnect-MgGraph -ErrorAction Stop | Out-Null }
    }
}

function Connect-CADiscovery {
    [CmdletBinding()]
    param([string]$TargetTenantId = '')
    Import-Module Microsoft.Graph.Authentication -ErrorAction Stop
    $target = $TargetTenantId.Trim()
    # Always remove the previous process-scoped Graph context, including when
    # the requested target GUID is invalid, so the UI cannot retain stale auth.
    Disconnect-CADiscovery
    if ($target -and $target -notmatch '^[0-9a-fA-F]{8}-([0-9a-fA-F]{4}-){3}[0-9a-fA-F]{12}$') {
        throw 'Target tenant ID must be a valid GUID (xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx).'
    }
    $scopes = @(Get-CARequiredScopes)
    $parameters = @{ Scopes=$scopes; ContextScope='Process'; NoWelcome=$true; ErrorAction='Stop' }
    if ($target) { $parameters['TenantId'] = $target }
    try {
        Connect-MgGraph @parameters | Out-Null
        $ctx = Get-MgContext
        if (-not $ctx -or -not $ctx.TenantId) { throw 'Graph authentication did not return a tenant ID.' }
        if ($target -and [string]$ctx.TenantId -ine $target) {
            throw "Authenticated tenant $($ctx.TenantId) differs from requested tenant $target."
        }
        Assert-CAWritePermission
        return [pscustomobject]@{ TenantId = [string]$ctx.TenantId; Account = [string]$ctx.Account; Scopes = @($ctx.Scopes) }
    } catch {
        $reason = $_.Exception.Message
        try { Disconnect-CADiscovery } catch { }
        throw "Microsoft Graph sign-in or consent failed. You may need administrator consent to Conditional Access read/write scopes. Details: $reason"
    }
}

function Get-CATenantState {
    $ctx = Get-MgContext
    if (-not $ctx -or -not $ctx.TenantId) { throw 'Connect to Microsoft Graph before refreshing.' }
    $result = @{
        tenantId = [string]$ctx.TenantId
        account = [string]$ctx.Account
        subscribedSkus = @(Get-CACollection '/subscribedSkus')
        existingPolicies = @(Get-CACollection '/identity/conditionalAccess/policies')
        namedLocations = @(Get-CACollection '/identity/conditionalAccess/namedLocations')
        roleDefinitions = @(Get-CACollection '/roleManagement/directory/roleDefinitions')
        authenticationStrengths = @(Get-CACollection '/policies/authenticationStrengthPolicies')
        securityDefaults = Invoke-CARequest '/policies/identitySecurityDefaultsEnforcementPolicy'
    }
    return $result
}

function Get-CAFilteredNamedLocationItems {
    <#
    .SYNOPSIS
        Return a WPF-bindable collection for zero, one, or many matching locations.
    .NOTES
        A filtered PowerShell pipeline with exactly one result returns a scalar;
        WPF ComboBox.ItemsSource requires System.Collections.IEnumerable.
        Return the collection itself without unrolling it.
    #>
    [CmdletBinding()]
    param(
        [AllowEmptyCollection()][object[]]$Locations = @(),
        [string]$Search = ''
    )
    $term = $Search.Trim()
    $view = [System.Collections.ObjectModel.ObservableCollection[object]]::new()
    foreach ($location in $Locations) {
        if ($null -eq $location) { continue }
        $label = [string]$location.Label
        if (-not $term -or $label.IndexOf($term, [System.StringComparison]::OrdinalIgnoreCase) -ge 0) {
            $view.Add($location)
        }
    }
    return ,$view
}

function Get-CAEffectiveTier {
    param([Parameter(Mandatory)][AllowEmptyCollection()][array]$Skus)
    $tier = 0
    foreach ($sku in $Skus) {
        if ([string]$sku['capabilityStatus'] -notin @('Enabled')) { continue }
        if ([string]$sku['skuPartNumber'] -in @('MICROSOFT_365_E7','M365_E7','SPE_E7')) {
            $tier = [math]::Max($tier,2)
        }
        foreach ($plan in @($sku['servicePlans'])) {
            if ([string]$plan['provisioningStatus'] -ne 'Success') { continue }
            $name = [string]$plan['servicePlanName']
            if ($name -eq 'AAD_PREMIUM_P2') { $tier = [math]::Max($tier,2) }
            if ($name -eq 'AAD_PREMIUM') { $tier = [math]::Max($tier,1) }
        }
    }
    return $tier
}

function Get-CAAgentLicenseSignals {
    [CmdletBinding()]
    param([Parameter(Mandatory)][AllowEmptyCollection()][array]$Skus)
    $agent365 = $false
    $e7 = $false
    $evidence = [System.Collections.Generic.List[string]]::new()
    # Microsoft's SKU mappings evolve. Inspect both enabled SKU names and
    # successfully provisioned service plans instead of trusting a GUI selection.
    foreach ($sku in $Skus) {
        if ([string]$sku['capabilityStatus'] -ne 'Enabled') { continue }
        $skuName = ([string]$sku['skuPartNumber']).ToUpperInvariant()
        if ($skuName -in @('MICROSOFT_365_E7','M365_E7','SPE_E7')) {
            $e7 = $true
            [void]$evidence.Add("Microsoft 365 E7 ($skuName)")
        }
        if ($skuName -eq 'AGENT_365' -or [string]$sku['skuId'] -eq '796a6fb4-740b-4d36-bf56-9c12ca7fa069') {
            $agent365 = $true
            [void]$evidence.Add('Agent 365 SKU')
        }
        foreach ($plan in @($sku['servicePlans'])) {
            if ([string]$plan['provisioningStatus'] -ne 'Success') { continue }
            if ([string]$plan['servicePlanName'] -eq 'AGENT_365' -or
                [string]$plan['servicePlanId'] -eq 'd0ce5ebb-9db0-491f-b780-8973a1d815fe') {
                $agent365 = $true
                [void]$evidence.Add('Agent 365 service plan')
            }
        }
    }
    # Microsoft 365 E7 includes Agent 365; a plan can be absent in some API
    # representations, so an explicitly identified E7 SKU is also evidence.
    if ($e7) { $agent365 = $true }
    $p2 = (Get-CAEffectiveTier -Skus $Skus) -ge 2
    return [pscustomobject]@{
        E7Detected = $e7
        Agent365Detected = $agent365
        P2Detected = $p2
        AgentRiskLicenseCandidate = ($p2 -and $agent365)
        Evidence = @($evidence.ToArray() | Sort-Object -Unique)
    }
}

function Get-CADetectedPlanLabel {
    <#
    .SYNOPSIS
        Friendly label from recognized enabled SKU IDs; fallback to the
        highest detected Entra entitlement, rather than inventing a plan.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][AllowEmptyCollection()][array]$Skus)
    $labels = @{
        MICROSOFT_365_E7='Microsoft 365 E7'; M365_E7='Microsoft 365 E7'; SPE_E7='Microsoft 365 E7'
        SPE_E5='Microsoft 365 E5'; SPE_E3='Microsoft 365 E3'
        SPE_F1='Microsoft 365 F1'; SPE_F3='Microsoft 365 F3'
        M365EDU_A3_FACULTY='Microsoft 365 A3'; M365EDU_A5_FACULTY='Microsoft 365 A5'
        SPB='Microsoft 365 Business Premium'; EMSPREMIUM='Enterprise Mobility + Security E5'
        EMS='Enterprise Mobility + Security E3'
        AAD_PREMIUM_P2='Microsoft Entra ID P2'; AAD_PREMIUM='Microsoft Entra ID P1'
    }
    $found = [System.Collections.Generic.List[string]]::new()
    foreach ($sku in $Skus) {
        if ([string]$sku['capabilityStatus'] -ne 'Enabled') { continue }
        $part = ([string]$sku['skuPartNumber']).ToUpperInvariant()
        if ($labels.ContainsKey($part)) { [void]$found.Add([string]$labels[$part]) }
    }
    $unique = @($found | Select-Object -Unique)
    if ($unique.Count -eq 1) { return [string]$unique[0] }
    if ($unique.Count -gt 1) { return 'Multiple plans: ' + ($unique -join ', ') }
    $tier = Get-CAEffectiveTier -Skus $Skus
    if ($tier -ge 2) { return 'Microsoft Entra ID P2' }
    if ($tier -eq 1) { return 'Microsoft Entra ID P1' }
    return 'No Entra P1/P2 license detected'
}

function Get-CAPolicyLicenseEligibility {
    <#
    .SYNOPSIS
        Policy eligibility from the tenant's reported enabled service plans.
    .NOTES
        Does not prove licensing of individual users targeted by a policy.
        The deployment acknowledgement and backend validation are unchanged.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][hashtable]$Definition,
          [Parameter(Mandatory)][AllowEmptyCollection()][array]$Skus)

    $key = [string]$Definition['code']
    $tier = Get-CAEffectiveTier -Skus $Skus
    $required = if ($key -eq 'CA007') { 'P2 + Agent 365' } elseif ([string]$Definition['license'] -eq 'P2') { 'Entra P2' } else { 'Entra P1' }
    if ([string]$Definition['stage'] -ne 'Stage 1') {
        return [pscustomobject]@{ CanDeploy=$false; Status='STAGE 2'; Required=$required; Reason='Planned for Stage 2' }
    }
    if ($tier -lt 1) {
        return [pscustomobject]@{ CanDeploy=$false; Status='NOT AVAILABLE'; Required=$required; Reason='Entra P1/P2 license not detected' }
    }
    if ($tier -lt 2 -and $required -ne 'Entra P1') {
        return [pscustomobject]@{ CanDeploy=$false; Status='NOT AVAILABLE'; Required=$required; Reason='Entra P2 required' }
    }
    if ($key -eq 'CA007') {
        $agent = Get-CAAgentLicenseSignals -Skus $Skus
        if (-not $agent.AgentRiskLicenseCandidate) {
            return [pscustomobject]@{ CanDeploy=$false; Status='NOT AVAILABLE'; Required=$required; Reason='Agent 365 entitlement not detected' }
        }
        return [pscustomobject]@{ CanDeploy=$false; Status='NOT IMPLEMENTED'; Required=$required; Reason='Agent-risk API not supported in this build' }
    }
    if ([string]$Definition['deploymentSupport'] -ne 'v1.0') {
        return [pscustomobject]@{ CanDeploy=$false; Status='NOT AVAILABLE'; Required=$required; Reason='Policy not supported in this build' }
    }
    return [pscustomobject]@{ CanDeploy=$true; Status='AVAILABLE'; Required=$required; Reason='' }
}

function Get-CALicenseInventoryRows {
    [CmdletBinding()]
    param([Parameter(Mandatory)][AllowEmptyCollection()][array]$Skus)
    $rows = [System.Collections.Generic.List[object]]::new()
    foreach ($sku in @($Skus | Sort-Object { [string]$_['skuPartNumber'] })) {
        $status = [string]$sku['capabilityStatus']
        $part = [string]$sku['skuPartNumber']
        $plans = @($sku['servicePlans'] | Where-Object { [string]$_['provisioningStatus'] -eq 'Success' } | ForEach-Object { [string]$_['servicePlanName'] })
        $features = [System.Collections.Generic.List[string]]::new()
        if ($plans -contains 'AAD_PREMIUM_P2') { [void]$features.Add('P2') }
        elseif ($plans -contains 'AAD_PREMIUM') { [void]$features.Add('P1') }
        if ($plans -contains 'AGENT_365' -or $part.ToUpperInvariant() -eq 'AGENT_365') { [void]$features.Add('Agent 365') }
        if ($part.ToUpperInvariant() -in @('MICROSOFT_365_E7','M365_E7','SPE_E7')) { [void]$features.Add('E7 bundle') }
        $prepaid = $sku['prepaidUnits']
        $enabled = if ($null -ne $prepaid -and $null -ne $prepaid['enabled']) { [string]$prepaid['enabled'] } else { '—' }
        $assigned = if ($null -ne $sku['consumedUnits']) { [string]$sku['consumedUnits'] } else { '—' }
        [void]$rows.Add([pscustomobject]@{
            Product=$part
            State=$status
            AvailableUnits=$enabled
            ConsumedUnits=$assigned
            Signals=if ($features.Count -gt 0) { $features -join ', ' } else { 'None recognized' }
        })
    }
    return $rows.ToArray()
}

function Resolve-CAUser {
    param([Parameter(Mandatory)][string]$UserPrincipalName)
    $encoded = [System.Uri]::EscapeDataString($UserPrincipalName.Trim())
    $user = Invoke-CARequest "/users/$encoded`?`$select=id,userPrincipalName,accountEnabled,onPremisesSyncEnabled"
    if (-not $user['id'] -or -not $user['accountEnabled']) {
        throw "Emergency account missing or disabled: $UserPrincipalName"
    }
    if ($user['onPremisesSyncEnabled'] -eq $true) {
        throw "Emergency account is synchronized rather than cloud-only: $UserPrincipalName"
    }
    return $user
}

Export-ModuleMember -Function Get-CAGraphErrorDetails,Get-CAFilteredNamedLocationItems,ConvertTo-CAHash,Invoke-CARequest,Get-CACollection,Get-CARequiredScopes,Connect-CADiscovery,Disconnect-CADiscovery,Assert-CAWritePermission,Get-CATenantState,Get-CAEffectiveTier,Get-CADetectedPlanLabel,Get-CAAgentLicenseSignals,Get-CAPolicyLicenseEligibility,Get-CALicenseInventoryRows,Resolve-CAUser,New-CACountryNamedLocation,Confirm-CACreatedPolicy
