# Conditional Access Builder

**Version 1.0.0 · Windows / PowerShell 7 / WPF · Community project**

A graphical tool to create **report-only** Microsoft Entra Conditional Access policies. Connect with Microsoft Graph, discover licenses, configure emergency access exclusions and named locations, and deploy a selected baseline. **No CA policy is automatically enforced.**

## Features

- Stage 1: CA001–CA012; **CA007 (high-risk agents) is not implemented** even when E7/Agent 365 is licensed.
- License-aware eligibility from tenant subscription data (P1/P2, common M365 bundles); no Entra Free deployment.
- One or two emergency accounts, optional signed-in-user exclusion, or deliberate no-account report-only testing.
- Country-based named location creation or reuse.
- Preview of JSON, license and policy validation, duplicate checks, final tenant confirmation.
- Report-only deployment; CA011 risk-remediation uses **Microsoft Graph beta**, which can change.

## Option A — Portable download (GitHub Releases)

1. Install **PowerShell 7.2+** on Windows 10/11 or Windows Server with Desktop Experience.
2. Install the Graph prerequisite in PowerShell 7:

   ```powershell
   Install-Module Microsoft.Graph.Authentication -Scope CurrentUser
   ```

3. Download the **Portable.zip** from the GitHub Release (once published), verify the SHA-256 checksum, extract, review the source, then double-click `Launch-GUI.cmd`. You can also run:

   ```powershell
   pwsh.exe -NoProfile -STA -File .\Start-EntraCABuilder.ps1
   ```

## Option B — Install as a PowerShell module (after PowerShell Gallery publication)

On Windows with PowerShell 7:

```powershell
Install-Module ConditionalAccessBuilder -Scope CurrentUser
Import-Module ConditionalAccessBuilder
Start-ConditionalAccessBuilder
```

Windows `pwsh` normally starts in STA mode; if hosting in an MTA process, launch a new session with `pwsh -STA`. The GUI is Windows-only; the packaging scripts are cross-platform.

## Run workflow

1. **Connect**, consent to requested Microsoft Graph scopes if authorized, then **Refresh Data**.
2. Optionally configure emergency exclusions and select countries or an existing named location for CA006.
3. **Select All** or select individual eligible policies. **Preview Run** and inspect the generated configuration and any blocked policies.
4. Confirm target-user licensing, select **Deploy** and review the target tenant confirmation.
5. Check the **Activity Log** and generated report-only policies in Microsoft Entra. Never enable policies without independent testing and emergency access planning.

### Runtime report folder

`%LOCALAPPDATA%\ConditionalAccessBuilder\Reports` contains deployment JSON and `.journal.jsonl` files, including tenant and operator identifiers. **Do not upload reports to a public GitHub repository or issue.**

## Source and security

- The tool requests delegated read permissions and `Policy.ReadWrite.ConditionalAccess` when connecting; the operator also needs an authorized Entra role. Connection alone makes no tenant changes.
- CA006 named-location creation is a separate tenant write and may remain if policy creation fails.
- Graph beta is used solely for CA011. CA007 remains unavailable; not every advertised Microsoft template/feature is deployed.

Review [`SECURITY.md`](SECURITY.md), [`Docs/TEST-PLAN.md`](Docs/TEST-PLAN.md), and [`Docs/GITHUB-PUBLISHING.md`](Docs/GITHUB-PUBLISHING.md) before publishing or deploying.

## Community

MIT licensed. Contributions and security reports are welcome; see `CONTRIBUTING.md` and `SECURITY.md`. No guarantee of suitability for production environments.
