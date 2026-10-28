# Security policy

## Handling secrets and tenant data

- Never commit a tenant ID tied to an organization, real UPNs, user IDs, policy exports, named-location exports, sign-in logs, or authentication tokens. Sample values must be synthetic.
- The application authenticates interactively using delegated Microsoft Graph scopes. It does not embed a client secret or store passwords. Authentication permission approval and Conditional Access Administrator role requirements still apply.
- `%LOCALAPPDATA%\ConditionalAccessBuilder\Reports` contains sensitive deployment results including tenant ID, operator UPN, and policy IDs.

## Running source safely

- Run the reviewed script using PowerShell 7. Do not bypass your organization's execution policy.
- Source is **not code-signed**. After verifying the source ZIP origin and reviewing its scripts, you may use `Unblock-File` on only the extracted project scripts if your organization's PowerShell policy permits it. Do not override organization-enforced policies.

