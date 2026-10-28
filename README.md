# Conditional Access Builder

**Version 1.0.0 · Windows / PowerShell 7 / WPF · Community project**

A graphical tool to prepare, preview and create **report-only** Microsoft Entra Conditional Access policies. Connect with Microsoft Graph, discover licenses and existing policies, configure emergency access exclusions and named locations, and deploy a selected baseline. **No CA policy is automatically enforced.**

> **Release status: GitHub-ready source / release candidate.** The author has confirmed 11 report-only CA policies were created and verified in a test tenant (CA001–CA006 and CA008–CA012). This is not an independent security audit, and the PowerShell Gallery module entrypoint has not yet been exercised on Windows. Test carefully before real organizational use.

## Features

- Stage 1: CA001–CA012; **CA007 (high-risk agents) is not implemented** even when E7/Agent 365 is licensed. Stage 2 is deferred.
- License-aware eligibility from tenant subscription data (P1/P2, common M365 bundles); no Entra Free deployment.
- One or two emergency accounts, optional signed-in-user exclusion, or deliberate no-account report-only testing.
- CA006 country-based named location creation or reuse.
- Preview of JSON, license and policy validation, duplicate checks, final tenant confirmation.
- Report-only deployment; CA011 risk-remediation uses **Microsoft Graph beta**, which can change.
- Reports and transaction journals saved in the current user's local data, **not** the repository or installed module folder.

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

The **PowerShell Gallery package is not published yet**. The source repository includes a module wrapper and a reproducible packaging script. The above installation command only works once an approved publisher uploads the reviewed module to the Gallery under this available name. If the name is taken, use a different module name in both the manifest and documentation.

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

- The portable launcher does not bypass execution policy and scripts are unsigned. If a downloaded copy is blocked, first verify the download/source, then follow your organization's approved process for unblocking trusted source. Do not bypass managed execution policies.
- The tool requests delegated read permissions and `Policy.ReadWrite.ConditionalAccess` when connecting; the operator also needs an authorized Entra role. Connection alone makes no tenant changes.
- CA006 named-location creation is a separate tenant write and may remain if policy creation fails.
- If the app reports a pending or uncertain creation result, **do not retry blindly**. Refresh and inspect existing policies.
- Graph beta is used solely for CA011. CA007 remains unavailable; not every advertised Microsoft template/feature is deployed.
- Tenant-level license discovery is not per-user license coverage verification.
- Report-only is not a guarantee of zero user impact.

Review [`SECURITY.md`](SECURITY.md), [`Docs/TEST-PLAN.md`](Docs/TEST-PLAN.md), and [`Docs/GITHUB-PUBLISHING.md`](Docs/GITHUB-PUBLISHING.md) before publishing or deploying.

## Build distributions locally

From the repository root on PowerShell 7:

```powershell
.\Tools\New-GitHubSourceZip.ps1
.\Tools\New-Distributions.ps1
```

This builds a source archive and two runtime packages in `dist/`: **Portable** for GitHub Releases, and a **PSGallery-review** module package. `dist/staging/ConditionalAccessBuilder` is the directory used later with `Publish-Module`. Nothing is uploaded automatically.

## Community

MIT licensed. Contributions and security reports are welcome; see `CONTRIBUTING.md` and `SECURITY.md`. No guarantee of suitability for production environments.
