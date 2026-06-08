/// <reference types="vite/client" />
/// <reference types="vite-plugin-pwa/client" />

interface ImportMetaEnv {
  readonly VITE_ENTRA_TENANT_ID: string;
  readonly VITE_ENTRA_CLIENT_ID: string;
  readonly VITE_BC_TENANT_ID: string;
  readonly VITE_BC_ENVIRONMENT: string;
  readonly VITE_BC_COMPANY_ID: string;
}

interface ImportMeta {
  readonly env: ImportMetaEnv;
}
