# Contributing

Thank you for helping Microsoft Entra administrators work safely.

1. Open an issue explaining the change and applicable Microsoft Learn references.
2. For new Conditional Access controls, document licensing, prerequisites, supported Graph API version, emergency account handling, and policy interactions.
3. Keep all policy POST operations in **report-only** mode. Never introduce automatic `enabled` policies, credential capture, or automatic Security Defaults removal.
4. Add/extend Pester tests and test in a throwaway nonproduction tenant before proposing write-path changes.
5. Never commit tenant IDs, exported access policies, emergency user details, credentials, or access tokens.
6. Use clear commit messages and submit a PR with testing notes.

For security-sensitive bugs, avoid posting real tenant data. See `SECURITY.md`.
