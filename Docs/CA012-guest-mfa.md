# CA012 — Require MFA for guests and external users

Stage 1 guest MFA policy. The revised user workbook included a guest MFA policy, but its IDs conflicted with previously assigned policy codes. This release preserves CA011 for risk remediation and assigns CA012 to guest MFA per the project owner's explicit instruction. Stage 2 policy codes are shifted to CA013–CA022 for uniqueness.

- Assignment: `includeUsers = ["GuestsOrExternalUsers"]` (all guests/external identities, without an additional subtype filter).
- Applications: `All`.
- Grant: `mfa`.
- State: `enabledForReportingButNotEnforced`.
- Exclusions: selected emergency account(s), and optionally the operator.
- Warning: overlaps with CA010, which includes guests under `All` users. Test with cross-tenant MFA trust and guest sign-in scenarios.
- Microsoft guidance: https://learn.microsoft.com/en-us/security/zero-trust/zero-trust-identity-device-access-policies-guest-access
- API schema: https://learn.microsoft.com/en-us/graph/api/resources/conditionalaccessusers?view=graph-rest-1.0
