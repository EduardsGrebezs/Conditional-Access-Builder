# Conditional Access Builder

A PowerShell/WPF GUI for creating Microsoft Entra Conditional Access policies in **report-only mode**. The application never automatically enables policies.

## Requirements

- Windows 11 or Windows Server with Desktop Experience (WPF GUI)
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

- Licensing checks, policy validation, and duplicate detection
- Named-location country selection for CA006
- Optional emergency-account and signed-in-administrator exclusions
- CA011 uses the Microsoft Graph **beta** endpoint for risk remediation

**Important:** Microsoft recommends at least two emergency access accounts before enforcing Conditional Access. Review real sign-in results and dependencies before enabling any policies manually. Creating a named location is a separate Graph write, even if its corresponding policy cannot be created.

