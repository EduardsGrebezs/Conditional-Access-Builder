# Security policy

**Status:** Release candidate, not independently security audited or production certified. Test-tenant report confirms 11 policies created and verified in report-only mode; additional Windows module-install and security validation remain necessary before broad use.

## Handling secrets and tenant data

- Never commit a tenant ID tied to an organization, real UPNs, user IDs, policy exports, named-location exports, sign-in logs, or authentication tokens. Sample values must be synthetic.
- The application authenticates interactively using delegated Microsoft Graph scopes. It does not embed a client secret or store passwords. Authentication permission approval and Conditional Access Administrator role requirements still apply.
- `%LOCALAPPDATA%\ConditionalAccessBuilder\Reports` contains sensitive deployment results including tenant ID, operator UPN, and policy IDs. `.gitignore` excludes any accidentally copied outputs, but **Git ignores do not protect files already committed**: check `git status`, staged changes, and history before publishing.
- Do not upload a local execution log, downloaded tenant inventory, certificate private key, or workbook containing real customer information as a GitHub issue or attachment.
- Prefer access restrictions on local report directories and remove old exports securely according to your organization's retention requirements.

## Safety model and limitations

- The deployed Graph policy state is enforced as `enabledForReportingButNotEnforced`. The tool does not enable, update, or delete tenant policies.
- Report-only policies can still have limited real-world user experience effects; never assume completely zero impact.
- A named location is a distinct Graph resource and may remain after a CA006 policy POST failure.
- Emergency access exclusions can be omitted for deliberate report-only testing, but should be configured and tested before any future enforcement.
- Automatic tenant-level licensing detection does not establish per-user licensing compliance. Agent-risk CA007 is intentionally **not deployable**: Graph beta support remains unimplemented, even when E7 is detected.
- Policy compiler and duplicate detection have not been independently penetration-tested. Review generated JSON and permissions with a qualified Entra administrator.

## Running source safely

- The public `Launch-GUI.cmd` deliberately does **not** set `-ExecutionPolicy Bypass`.
- Source is **not code-signed**. After verifying the source ZIP origin and reviewing its scripts, you may use `Unblock-File` on only the extracted project scripts if your organization's PowerShell policy permits it. Do not override organization-enforced policies.
- The portable release includes no bundled binaries or third-party packages; Microsoft Graph PowerShell Authentication is installed separately from a trusted repository.

## Vulnerability disclosure

Once the GitHub repository is public, use GitHub's private vulnerability-reporting feature (security advisories), if enabled, for sensitive findings. Do not disclose credentials, token material, tenant-specific exports, or internal account IDs in public issues.
