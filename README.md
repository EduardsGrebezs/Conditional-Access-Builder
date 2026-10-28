# Conditional Access Builder

**Windows · PowerShell 7 · Microsoft Entra ID · Version 1.0.0**

A PowerShell/WPF GUI for creating Microsoft Entra Conditional Access policies in **report-only mode**. The application never automatically enables policies.

## Requirements

- Windows 10/11 or Windows Server with Desktop Experience
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
3. Run **`Launch-GUI.cmd`** on Windows, or:

   ```powershell
   pwsh.exe -NoProfile -STA -File .\Start-EntraCABuilder.ps1
   ```

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

The GitHub repository provides the source. To build the portable ZIP and a PowerShell module candidate locally, run:

```powershell
.\Tools\New-Distributions.ps1
```

**PowerShell Gallery installation is not available until the module is published.** This repository's packaging scripts do not publish modules or releases automatically.

## License and security

Released under the [MIT License](LICENSE). See [SECURITY.md](SECURITY.md) for safe handling of tenant data and security concerns.
