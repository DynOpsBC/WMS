import { BcClient } from '@bcwmsapp/shared';
import { auth } from './auth';

export function makeBcClient() {
  const env = {
    tenantId: process.env.EXPO_PUBLIC_BC_TENANT_ID!,
    environmentName: process.env.EXPO_PUBLIC_BC_ENVIRONMENT!,
    companyId: process.env.EXPO_PUBLIC_BC_COMPANY_ID!,
  };
  return new BcClient({ env, getAccessToken: auth.getAccessToken });
}
