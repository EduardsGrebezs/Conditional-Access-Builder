# Changelog

## v1.0.0 — GitHub release candidate (2026-10-28)

- Windows PowerShell 7 WPF application with Microsoft Graph connection and tenant discovery.
- Stage 1 CA policies CA001–CA012 (except CA007, intentionally unavailable); Stage 2 is reserved.
- Automatic licensing and existing-policy checks; emergency-account and country-named-location configuration.
- Dry run, read-back verified report-only deployment, duplicate checks, transaction journals, and Graph error reporting.
- CA011 risk remediation is created through Microsoft Graph beta; other policies use v1.0.
- Live test-tenant deployment report confirms 11 policies created and verified in report-only mode. This is not an independent audit.
- GitHub preparation: simplified success popup, per-user report storage, source allowlist, portable ZIP, and PowerShell Gallery module wrapper.
- No automatic policy enablement, editing or deletion. CA007 agent-risk policy support remains unimplemented.

**Before publication:** run the Windows GUI and module-install smoke tests, Pester, secret scanning, and release signing decisions. No GitHub or Gallery upload has been performed.
