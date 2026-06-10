/// <reference types="expo/types" />

// EXPO_PUBLIC_* env vars are inlined by the Expo bundler at build time.
declare const process: {
  env: {
    EXPO_PUBLIC_ENTRA_TENANT_ID?: string;
    EXPO_PUBLIC_ENTRA_CLIENT_ID?: string;
    EXPO_PUBLIC_BC_TENANT_ID?: string;
    EXPO_PUBLIC_BC_ENVIRONMENT?: string;
    EXPO_PUBLIC_BC_COMPANY_ID?: string;
    EXPO_PUBLIC_APPINSIGHTS_CONN?: string;
    [key: string]: string | undefined;
  };
};

declare const __DEV__: boolean;
