import { BcClient } from '@bcwmsapp/shared';
import { getAccessToken } from '../auth/msal.ts';

const env = {
  tenantId: import.meta.env.VITE_BC_TENANT_ID,
  environmentName: import.meta.env.VITE_BC_ENVIRONMENT,
  companyId: import.meta.env.VITE_BC_COMPANY_ID,
};

export const bcClient = new BcClient({ env, getAccessToken });
