Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-CARoleIdList {
    param([string]$Text,[array]$RoleDefinitions)
    if ([string]::IsNullOrWhiteSpace($Text)) { return ,@() }
    $ids = [System.Collections.Generic.List[string]]::new()
    foreach ($line in @($Text -split '\r?\n')) {
        $name = $line.Trim()
        if (-not $name) { continue }
        $role = @($RoleDefinitions | Where-Object { $_['displayName'] -ieq $name })
        if ($role.Count -ne 1) { throw "Cannot uniquely resolve Entra role '$name'; check directory role definitions." }
        [void]$ids.Add([string]$role[0]['id'])
    }
    return $ids.ToArray()
}

function Get-CALocationId {
    param([string]$Selection,[array]$NamedLocations)
    if (-not $Selection.Trim()) { throw 'CA006 requires a named location selection.' }
    if ($Selection -ceq 'PENDING-COUNTRY-NAMED-LOCATION') { return $Selection }
    $match = @($NamedLocations | Where-Object { $_['id'] -ieq $Selection.Trim() -or $_['displayName'] -ieq $Selection.Trim() })
    if ($match.Count -ne 1) { throw "Named location '$Selection' was not found uniquely in the connected tenant." }
    return [string]$match[0]['id']
}

function New-CAStage1Policy {
    [CmdletBinding()]
    param([Parameter(Mandatory)][hashtable]$Definition,
          [Parameter(Mandatory)][hashtable]$Tenant,
          [AllowEmptyCollection()][string[]]$EmergencyIds,
          [string]$BlockedLocation = '')
    $code = [string]$Definition['code']
    if ($code -eq 'CA007') { throw 'CA007 requires preview agent-risk Graph APIs and appropriate additional licensing; it is not deployable in this version.' }
    if ([string]$Definition['stage'] -ne 'Stage 1') { throw "Policy $code is Stage 2 (not deployable)." }
    if ($EmergencyIds.Count -gt 3) { throw 'A maximum of two emergency accounts plus the signed-in account is supported.' }
    foreach ($id in $EmergencyIds) { $guid = [guid]::Empty; if (-not [guid]::TryParse($id,[ref]$guid)) { throw "Invalid emergency object ID: $id" } }
    $level = if ($Definition['license'] -eq 'P2') { 2 } else { 1 }
    if ((Get-CAEffectiveTier -Skus $Tenant['subscribedSkus']) -lt $level) { throw "Policy $code requires Entra ID P$level entitlements." }
    $fields = $Definition['sourceFields']
    $users = @{ excludeUsers = @($EmergencyIds) }
    if ($code -notin @('CA009','CA012')) { $users['includeUsers'] = @('All') }
    $conditions = @{
        users = $users
        applications = @{ includeApplications = @('All') }
        clientAppTypes = @('all')
    }
    $grant = @{ operator='OR'; builtInControls=@('block') }
    $sessions = $null
    switch ($code) {
        CA001 { $conditions['clientAppTypes'] = @('exchangeActiveSync','other') }
        CA002 { $conditions['authenticationFlows'] = @{ transferMethods = 'deviceCodeFlow' } }
        CA003 { $conditions['authenticationFlows'] = @{ transferMethods = 'authenticationTransfer' } }
        CA004 { $conditions['platforms'] = @{ includePlatforms = @('all'); excludePlatforms = @('android','iOS','windows','macOS') } }
        CA005 {
            $conditions['applications']['includeApplications'] = @('797f4846-ba00-4fd7-ba43-dac1f8f63013')
            $roles = Get-CARoleIdList -Text ([string]$fields['excludeRoles']) -RoleDefinitions $Tenant['roleDefinitions']
            if ($roles.Count -lt 1) { throw 'CA005 has no exclusion roles from the source workbook.' }
            $users['excludeRoles'] = @($roles)
        }
        CA006 { $conditions['locations'] = @{ includeLocations = @((Get-CALocationId -Selection $BlockedLocation -NamedLocations $Tenant['namedLocations'])) } }
        CA008 { $conditions['signInRiskLevels'] = @('high') }
        CA009 {
            $users['includeRoles'] = @(Get-CARoleIdList -Text ([string]$fields['includeRoles']) -RoleDefinitions $Tenant['roleDefinitions'])
            if ($users['includeRoles'].Count -lt 1) { throw 'CA009 has no administrator role targets.' }
            $grant = @{ operator='OR'; builtInControls=@(); authenticationStrength=@{ id='00000000-0000-0000-0000-000000000004' } }
            $sessions = @{ signInFrequency = @{ isEnabled=$true; type='days'; value=1; frequencyInterval='timeBased' }; persistentBrowser=@{ isEnabled=$true; mode='never' } }
        }
        CA010 { $grant = @{ operator='OR'; builtInControls=@('mfa') } }
        CA012 {
            # Guest/external scope, not all users. External tenants=all.
            $users['includeUsers'] = @('GuestsOrExternalUsers')
            # v1.0 supports the special all-guests target without a nested
            # includeGuestsOrExternalUsers object. This avoids introducing
            # unnecessary subtype filters for CA012 (all guest/external users).
            # The source workbook requests all guests, not selected tenant IDs.
            $grant = @{ operator='OR'; builtInControls=@('mfa') }
        }
        CA011 {
            $conditions['userRiskLevels'] = @('high')
            # Risk remediation must use auth strength AND and no unrelated CA conditions.
            $conditions.Remove('clientAppTypes')
            $grant = @{ operator='AND'; builtInControls=@('riskRemediation'); authenticationStrength=@{id='00000000-0000-0000-0000-000000000002'} }
            $sessions = @{ signInFrequency=@{ isEnabled=$true; frequencyInterval='everyTime'; authenticationType='primaryAndSecondaryAuthentication' } }
        }
        default { throw "Unknown Stage 1 policy: $code" }
    }
    $payload = @{
        displayName = [string]$Definition['displayName']
        state = 'enabledForReportingButNotEnforced'
        conditions = $conditions
        grantControls = $grant
    }
    if ($null -ne $sessions) { $payload['sessionControls'] = $sessions }
    Assert-CAPolicySafety -Payload $payload -EmergencyIds $EmergencyIds
    return $payload
}

function Assert-CAPolicySafety {
    param([Parameter(Mandatory)][hashtable]$Payload,[string[]]$EmergencyIds)
    if ($Payload['state'] -cne 'enabledForReportingButNotEnforced') { throw 'Only report-only policy creation is allowed.' }
    $conditions = $Payload['conditions']
    if (-not $conditions -or -not $conditions['applications'] -or -not $Payload['grantControls']) { throw 'Missing required CA conditions or controls.' }
    $users = $conditions['users']
    if (-not $users) { throw 'User-targeted safety validation failed: no users condition.' }
    $targeted = @($users['includeUsers']) + @($users['includeGroups']) + @($users['includeRoles']) + @($users['includeGuestsOrExternalUsers'])
    if (@($targeted | Where-Object { $_ -and $_ -ne 'None' }).Count -lt 1) { throw 'Refusing policy with empty user targeting.' }
    $excluded = @($users['excludeUsers'])
    foreach ($id in $EmergencyIds) { if ($id -notin $excluded) { throw "Missing verified emergency access exclusion $id" } }
    if (@($users['excludeUsers'] | Where-Object { $_ -eq 'All' }).Count -gt 0) { throw 'Excluding All users is invalid.' }
    if ($conditions['applications']['includeApplications'].Count -lt 1 -and $conditions['applications']['includeUserActions'].Count -lt 1) {
        throw 'Missing applications or user actions.'
    }
}

function ConvertTo-CACanonical {
    param($Object)
    # A deterministic, normalized representation of the security-relevant fields.
    if ($null -eq $Object) { return $null }
    if ($Object -is [System.Collections.IDictionary]) {
        $keys = @($Object.Keys | Where-Object { $_ -notin @('id','createdDateTime','modifiedDateTime','displayName','state','templateId') -and $_ -notmatch '^@odata\.' } | Sort-Object)
        $ordered = [ordered]@{}
        foreach ($k in $keys) { if ($null -ne $Object[$k]) { $ordered[[string]$k] = ConvertTo-CACanonical $Object[$k] } }
        return $ordered
    }
    if ($Object -is [array]) {
        return ,@($Object | ForEach-Object { ConvertTo-CACanonical $_ } | Sort-Object { ConvertTo-Json -InputObject $_ -Depth 100 -Compress })
    }
    return $Object
}

function Get-CADuplicate {
    param([hashtable]$Payload,[array]$ExistingPolicies)
    foreach ($existing in $ExistingPolicies) {
        if ($Payload['templateId'] -and $existing['templateId'] -and $Payload['templateId'] -eq $existing['templateId']) {
            return "Template already exists: $($existing['displayName']) [$($existing['id'])]"
        }
        if ([string]$Payload['displayName'] -ieq [string]$existing['displayName']) {
            return "Existing policy with same name: $($existing['displayName']) [$($existing['id'])] (review before changing)"
        }
        # Normalize only the three policy objects relevant for effective behavior.
        $a = @{ conditions=$Payload['conditions']; grantControls=$Payload['grantControls']; sessionControls=$Payload['sessionControls'] }
        $b = @{ conditions=$existing['conditions']; grantControls=$existing['grantControls']; sessionControls=$existing['sessionControls'] }
        $jsonA = ConvertTo-Json -InputObject (ConvertTo-CACanonical $a) -Depth 100 -Compress
        $jsonB = ConvertTo-Json -InputObject (ConvertTo-CACanonical $b) -Depth 100 -Compress
        if ($jsonA -ceq $jsonB) { return "Equivalent policy configuration exists: $($existing['displayName']) [$($existing['id'])]" }
    }
    return $null
}

Export-ModuleMember -Function Get-CARoleIdList,Get-CALocationId,New-CAStage1Policy,Assert-CAPolicySafety,Get-CADuplicate
