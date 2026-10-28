# GitHub and PowerShell Gallery publishing checklist

This project has **not** been uploaded to GitHub or the PowerShell Gallery by these build scripts. Publishing is a separate owner-approved operation.

## 1. Publish source to GitHub

1. Review all `.ps1`, `.psm1`, `.psd1`, XAML, JSON, and CI workflow files; ensure licensing and source attribution are appropriate.
2. Run `Invoke-Pester -Path ./Tests -CI` and `./Tools/New-Distributions.ps1` on **Windows PowerShell 7**. Run smoke tests using a **dedicated nonproduction Entra tenant**.
3. Run `./Tools/New-GitHubSourceZip.ps1`. Inspect the allowlisted entries, checksums, and secret scan results.
4. Create a public repository using the desired GitHub organization/user. Commit **extracted source**, not distribution ZIPs. `dist/`, `Reports/`, Excel files, real tenant identifiers and logs must stay uncommitted.
5. Enable branch protection, Dependabot, code scanning/secret scanning and private security reporting where available.
6. Make a tagged release `v1.0.0` **only after validation**. Attach the reviewed portable archive, checksums, and release notes. Do not misrepresent live testing as an independent audit.

## 2. Prepare the PowerShell Gallery module

First choose and confirm an unused Gallery module name. The current candidate is **ConditionalAccessBuilder**.

```powershell
.\Tools\New-Distributions.ps1
Test-ModuleManifest .\dist\staging\ConditionalAccessBuilder\ConditionalAccessBuilder.psd1
Import-Module .\dist\staging\ConditionalAccessBuilder\ConditionalAccessBuilder.psd1 -Force
Get-Command Start-ConditionalAccessBuilder
Start-ConditionalAccessBuilder
```

The last command launches the GUI; it does **not** deploy policies without operator confirmation. Run this on Windows PowerShell 7 with the Microsoft Graph dependency installed and WPF available. If successful, check packaged files and try installation via an **internal test repository** before public release.

Set the *real* `ProjectUri` to your public GitHub repository in the module manifest before publishing. Do not invent a link. Update `ReleaseNotes` and module version with each release.

## 3. Publish after approval

PowerShell Gallery publisher account/API key required. Keep the key out of source control and shell history. Example in an owner-controlled release session:

```powershell
# The publisher supplies the key securely in this session.
# Do not commit it or save it in a script.
Publish-Module -Path .\dist\staging\ConditionalAccessBuilder `
  -Repository PSGallery -NuGetApiKey $env:PSGALLERY_API_KEY `
  -WhatIf -Verbose
```

Remove `-WhatIf` **only when you are intentionally ready to publish**. The command does not configure a publication key. Do not auto-publish from every GitHub push.

End-user command after publication:

```powershell
Install-Module ConditionalAccessBuilder -Scope CurrentUser
Import-Module ConditionalAccessBuilder
Start-ConditionalAccessBuilder
```

If publishing uses a different module name, update manifest, folder, docs and commands. See official Microsoft PowerShell Gallery requirements.

## Supply-chain security reminders

- Source archive and portable module are built from an explicit allowlist.
- No workbook, credentials, token cache, test tenant exports, reports or previous releases are packaged.
- `.gitignore` does not scrub already committed data: review staged content and Git history before opening the repository.
- No signing identity or automatic execution-policy bypass is bundled. Signing can be introduced later through a publisher-controlled CI/release process.
- Do not grant GitHub Actions write permissions or use a release API key in untrusted pull-request workflows.
