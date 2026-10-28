# Test and release acceptance plan

**Status:** A user-provided Entra test-tenant report confirms 11 policies successfully created and verified in `enabledForReportingButNotEnforced`. The Gallery module, new per-user report path and packaging still need Windows acceptance testing.

## Automated checks

1. From the repo root on Windows PowerShell 7, install Pester and run `Invoke-Pester -Path ./Tests -CI`.
2. Validate source, XAML, JSON, package allowlists and the module manifest.
3. Run `./Tools/New-GitHubSourceZip.ps1` and `./Tools/New-Distributions.ps1`; inspect both ZIPs and checksums.
4. Use `Test-ModuleManifest ./dist/staging/ConditionalAccessBuilder/ConditionalAccessBuilder.psd1` and `Import-Module` from the staged module folder.
5. Confirm CI runs without network access to a tenant and with read-only GitHub token permission.

## Manual Windows and test-tenant smoke tests

1. Launch portable ZIP through `Launch-GUI.cmd`; check GUI tabs, buttons, licensing and startup with PowerShell 7 STA.
2. Launch from staged Gallery module using `Import-Module` then `Start-ConditionalAccessBuilder`.
3. Validate Connect, Sign Out, Refresh Data, full preview, emergency accounts (zero, one and two), and tenant switching.
4. In P1 and P2/E7 test tenants, confirm CA008/CA011 require P2, CA007 cannot be deployed, and Free is ineligible.
5. Preview CA001–CA006 and CA008–CA012, including CA004/CA005 workbook-defined targeting. Validate actual Graph payloads against approved design.
6. For CA006, test existing location reuse, new location creation, no writes on preview and no duplicate creation on repeat attempts.
7. Deploy a small sample in a nonproduction tenant. Check `CreatedAndVerified`, exact report-only state, duplicate skipping, and `OutcomeUnconfirmed` protections.
8. Confirm CA011 uses Graph beta with a warning; CA012 all-guests targeting uses Graph v1.0. Test sign-in results and overlapping policies before enforcement.
9. Confirm reports are written to `%LOCALAPPDATA%\ConditionalAccessBuilder\Reports`, **not** inside the source or installed module.
10. Validate short success popup; Activity Log retains detailed report location and Graph error information.
11. Verify no workbook, user data, Graph tokens, certificates, test reports or previous builds enter any public ZIP.
12. Test module installation from an internal feed and uninstall/reinstall before publishing to PSGallery.

Do not claim independent security certification. Do not enable any automatically generated policies without additional evaluation and emergency-access readiness.
