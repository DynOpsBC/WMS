import type { BcEnvironment, WmsLicensePlate, WmsWorker } from '../types/index.js';

const API_NAMESPACE = 'dynopsbc/wms/v1.0';

export interface BcClientOptions {
  env: BcEnvironment;
  getAccessToken: () => Promise<string>;
  baseUrl?: string;
}

export class BcApiError extends Error {
  constructor(
    message: string,
    readonly status: number,
    readonly body: unknown,
  ) {
    super(message);
    this.name = 'BcApiError';
  }
}

export class BcClient {
  private readonly base: string;

  constructor(private readonly opts: BcClientOptions) {
    const root =
      opts.baseUrl ?? `https://api.businesscentral.dynamics.com/v2.0`;
    this.base = `${root}/${opts.env.tenantId}/${opts.env.environmentName}/api/${API_NAMESPACE}/companies(${opts.env.companyId})`;
  }

  async listWorkers(signal?: AbortSignal): Promise<WmsWorker[]> {
    return this.get<{ value: WmsWorker[] }>('/wmsWorkers', signal).then(
      (r) => r.value,
    );
  }

  async listLicensePlates(signal?: AbortSignal): Promise<WmsLicensePlate[]> {
    return this.get<{ value: WmsLicensePlate[] }>(
      '/wmsLicensePlates',
      signal,
    ).then((r) => r.value);
  }

  private async get<T>(path: string, signal?: AbortSignal): Promise<T> {
    const token = await this.opts.getAccessToken();
    const res = await fetch(`${this.base}${path}`, {
      headers: {
        Authorization: `Bearer ${token}`,
        Accept: 'application/json',
      },
      signal,
    });
    if (!res.ok) {
      const body = await res.text();
      throw new BcApiError(`BC ${path} → ${res.status}`, res.status, body);
    }
    return (await res.json()) as T;
  }
}
