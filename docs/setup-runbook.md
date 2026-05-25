# Setup Runbook

## Sandbox

- Tenant: `7fa2357e-26f2-4174-8e16-a713981356b8`
- Environment: `CustomerSandbox`
- Company: `Demo Business Central`
- URL: `https://businesscentral.dynamics.com/7fa2357e-26f2-4174-8e16-a713981356b8/CustomerSandbox?company=Demo%20Business%20Central`

## AL Install Steps

1. Open `al/` in Visual Studio Code with the AL extension on Windows.
2. Download symbols for Business Central 24.
3. Package the extension.
4. Publish to the sandbox with `schemaUpdateMode` set to `ForceSync` for initial scaffolding only.
5. Assign `DOPSWHS-ADMIN` to the sandbox test user.
6. Open Assisted Setup and verify the BCWMSApp setup tile opens the setup card.

## External Dependencies

- Azure AD app registration for Android MSAL.
- Azure Function, SignalR, Key Vault, and Application Insights deployment for push relay.
- Microsoft PartnerSource object range expansion request to `72000-72499`.

