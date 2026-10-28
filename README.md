# Conditional Access Builder

A PowerShell/WPF GUI for creating Microsoft Entra Conditional Access policies in **report-only mode**. The application never automatically enables policies.

## Requirements

- PowerShell 7.2 or later
- Microsoft Entra ID P1/P2 licensing for the selected policies
- Microsoft Graph consent and an appropriately privileged Entra administrator account

Install the Microsoft Graph authentication module in PowerShell 7:

```powershell
Install-Module Microsoft.Graph.Authentication -Scope CurrentUser
```

## Run the builder

1. Use **Code → Download ZIP** on GitHub, or clone this repository.
2. Extract the ZIP and review the scripts before execution.
3. Open **PowerShell 7**, navigate to the extracted application folder, and run:

   ```powershell
   Set-Location "C:\path\to\Conditional-Access-Builder-main"
   .\Start-EntraCABuilder.ps1
   ```

   If the session is not in STA mode, start PowerShell using `pwsh.exe -NoProfile -STA` first.

The scripts are not code-signed. If Windows blocks trusted downloaded files, follow your organization's execution-policy rules; do not bypass an enforced policy.

## Use

1. Select **Connect**, sign in, then **Refresh Data**.
2. Configure emergency-account exclusions (one or two accounts recommended) and, for CA006, a named location.
3. Choose the policies, then select **Preview Run** and review the proposed configuration.
4. Confirm licensing and select **Deploy**. Only report-only policies can be created.
5. Verify the resulting policies in Microsoft Entra and review the **Activity Log**.

## Included functionality

- CA001–CA006 and CA008–CA012: configurable report-only baseline
- Licensing checks, policy validation, and duplicate detection
- Named-location country selection for CA006
- Optional emergency-account and signed-in-administrator exclusions
- CA011 uses the Microsoft Graph **beta** endpoint for risk remediation
- CA007 (high-risk agents) is **not implemented**, including for E7 tenants

**Important:** Microsoft recommends at least two emergency access accounts before enforcing Conditional Access. Review real sign-in results and dependencies before enabling any policies manually. Creating a named location is a separate Graph write, even if its corresponding policy cannot be created.

## Logs and privacy

Deployment reports are saved locally under:

`%LOCALAPPDATA%\ConditionalAccessBuilder\Reports`

Reports may contain tenant, policy, and operator identifiers. Do not post them publicly.

## Distribution

**Code → Download ZIP** contains everything required to run the builder. No installer or batch launcher is needed.

### PowerShell module (after Gallery publication)

On Windows with PowerShell 7.2 or later, users will be able to install and start the same GUI:

```powershell
Install-Module ConditionalAccessBuilder -Scope CurrentUser
Start-ConditionalAccessBuilder
```

With PowerShell 7.4+, `Install-PSResource ConditionalAccessBuilder -Scope CurrentUser` is another supported installation option.

**Not published yet:** the commands above will work after the package is released to PowerShell Gallery. Installing the module does not connect to a tenant or create Conditional Access policies.

To validate the module locally before publication, clone the repository (the GitHub **Code → Download ZIP** archive deliberately excludes developer tooling), then run:

```powershell
.\Tools\Build-Module.ps1
$module = Join-Path $PWD 'dist\ConditionalAccessBuilder\ConditionalAccessBuilder.psd1'
Test-ModuleManifest $module
Import-Module $module -Force
Get-Command Start-ConditionalAccessBuilder
Start-ConditionalAccessBuilder
```

The module needs the Microsoft.Graph.Authentication dependency. When publishing, the project owner must use their own PowerShell Gallery publisher account and API key. **Never commit or share an API key.**

## License and security

Released under the [MIT License](LICENSE). See [SECURITY.md](SECURITY.md) for safe handling of tenant data and security concerns.
