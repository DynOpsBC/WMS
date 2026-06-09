# BCWMSApp — Admin guide

## Installation

### 1. Install the BC AL extension

1. In Business Central admin centre, open your environment.
2. Upload `BCWMSApp-0.1.0.0.app` from AppSource (or sideload via the extension management page in a sandbox).
3. Verify the permission set `WMS` is available.

### 2. Configure an Entra ID app registration

1. Azure portal → App registrations → New registration. Name it `BCWMSApp`.
2. Add redirect URIs:
   - Web: `https://<your-web-host>/`
   - Mobile: `bcwmsapp://auth`
3. API permissions: add `Dynamics 365 Business Central → user_impersonation` (delegated).
4. Expose an API or use the BC default scope — `https://api.businesscentral.dynamics.com/.default`.
5. Copy the Tenant ID + Client ID into both apps' env files.

### 3. Set up master data

In the BC web client:

1. Search for **WMS Workers** → create one per warehouse user. Map each to an Entra `oid`.
2. Search for **WMS Worker Menus** → create at least one root menu, then add menu items.
3. Edit each **Location** → toggle *WMS Enabled* + set the default packing policy.
4. Open each **Bin** → set ranking, *WMS Pickable*, *WMS Receivable*, optional *WMS Quarantine*.

### 4. Deploy the web PWA

1. `pnpm -C apps/web build`
2. Deploy the `dist/` folder to your static host (Azure Static Web Apps, Cloudflare Pages, Netlify).
3. Set env vars at deploy time.

### 5. Build the mobile app

1. `pnpm -C apps/mobile prebuild` (creates native projects).
2. Build a custom dev client with `eas build --profile development`.
3. Distribute via internal MDM / Intune to Zebra TC22 / Honeywell CT45 devices.

## Day-to-day operations

- Assign workers to menus from `apps/web` → Setup → Workers.
- Edit menus visually in **Menu Designer**.
- Watch live activity on the **Dashboard**.
- Approve count variances under **Counts**.
- Rate-shop and print labels under **Shipping**.

## Troubleshooting

- Mobile won't sign in → run **Wi-Fi diagnostics** from the sign-in screen.
- Picks not visible on mobile → verify Worker has the menu assigned and the location is *WMS Enabled*.
- Labels print blank → confirm the Zebra is reachable on Bluetooth and the dev client includes the `ZebraLinkOs` native module.
