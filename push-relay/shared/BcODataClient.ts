import type { TenantPrinters } from "./PrinterTokenRegistry.js";

export type PrintJobDto = {
  jobId: number;
  sourceDoc: string;
  printerId: string;
  channel: string;
  format: string;
  status: string;
  copies: number;
  payload: string;
  payloadSize: number;
  createdAt: string;
  agentId?: string;
};

export class BcODataClient {
  constructor(private readonly tenant: TenantPrinters) {}

  private base(): string {
    return `${this.tenant.bcBaseUrl.replace(/\/$/, "")}/api/dynops/warehouse/v2.0/companies(${this.tenant.bcCompanyId})/printJobs`;
  }

  private headers(): Record<string, string> {
    return {
      Authorization: `Bearer ${this.tenant.bcBearer}`,
      Accept: "application/json",
      "Content-Type": "application/json",
    };
  }

  async listQueued(printerId: string, top = 10): Promise<PrintJobDto[]> {
    const filter = encodeURIComponent(`channel eq 'SelfHosted' and status eq 'Queued' and printerId eq '${printerId.replace(/'/g, "''")}'`);
    const url = `${this.base()}?$filter=${filter}&$top=${top}&$orderby=createdAt`;
    const response = await fetch(url, { headers: this.headers() });
    if (!response.ok) {
      throw new Error(`BC OData GET failed: ${response.status} ${await response.text()}`);
    }
    const json = (await response.json()) as { value: PrintJobDto[] };
    return json.value ?? [];
  }

  async claim(jobId: number, agentId: string): Promise<boolean> {
    const url = `${this.base()}(${jobId})/Microsoft.NAV.claim`;
    const response = await fetch(url, {
      method: "POST",
      headers: this.headers(),
      body: JSON.stringify({ agentId }),
    });
    return response.ok;
  }

  async markStatus(jobId: number, success: boolean, message: string): Promise<boolean> {
    const action = success ? "markSuccess" : "markFailure";
    const url = `${this.base()}(${jobId})/Microsoft.NAV.${action}`;
    const response = await fetch(url, {
      method: "POST",
      headers: this.headers(),
      body: JSON.stringify({ message }),
    });
    return response.ok;
  }
}
