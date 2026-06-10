import type {
  BcEnvironment,
  WmsActionRequest,
  WmsActionResult,
  WmsCarrier,
  WmsContainer,
  WmsCountVariance,
  WmsCycleCountPlan,
  WmsLicensePlate,
  WmsShippingRate,
  WmsWorker,
  WmsWorkerMenu,
} from '../types';

const API_NAMESPACE = 'dynopsbc/wms/v1.0';

export interface BcClientOptions {
  env: BcEnvironment;
  getAccessToken: () => Promise<string>;
  /** Override the API root (used by tests / on-prem). */
  baseUrl?: string;
  /** Injectable fetch for tests / non-browser runtimes. */
  fetchImpl?: typeof fetch;
}

/** HTTP-level failure from BC (4xx/5xx). Not retryable unless 5xx/429. */
export class BcApiError extends Error {
  constructor(
    message: string,
    readonly status: number,
    readonly body: unknown,
  ) {
    super(message);
    this.name = 'BcApiError';
  }

  /** 5xx and 429 are transient — safe to retry. 4xx (except 429) are permanent. */
  get retryable(): boolean {
    return this.status >= 500 || this.status === 429;
  }
}

/** Network-level failure (offline, DNS, TLS, abort). Always retryable. */
export class BcOfflineError extends Error {
  constructor(
    message: string,
    readonly cause?: unknown,
  ) {
    super(message);
    this.name = 'BcOfflineError';
  }
}

export class BcClient {
  private readonly base: string;
  private readonly doFetch: typeof fetch;

  constructor(private readonly opts: BcClientOptions) {
    const root = opts.baseUrl ?? `https://api.businesscentral.dynamics.com/v2.0`;
    this.base = `${root}/${opts.env.tenantId}/${opts.env.environmentName}/api/${API_NAMESPACE}/companies(${opts.env.companyId})`;
    this.doFetch = opts.fetchImpl ?? fetch;
  }

  // ---- Reads -------------------------------------------------------------

  listWorkers(signal?: AbortSignal): Promise<WmsWorker[]> {
    return this.getList<WmsWorker>('/wmsWorkers', signal);
  }

  listLicensePlates(signal?: AbortSignal): Promise<WmsLicensePlate[]> {
    return this.getList<WmsLicensePlate>('/wmsLicensePlates', signal);
  }

  listContainers(signal?: AbortSignal): Promise<WmsContainer[]> {
    return this.getList<WmsContainer>('/wmsContainers', signal);
  }

  listCycleCountPlans(signal?: AbortSignal): Promise<WmsCycleCountPlan[]> {
    return this.getList<WmsCycleCountPlan>('/wmsCycleCountPlans', signal);
  }

  listCountVariances(signal?: AbortSignal): Promise<WmsCountVariance[]> {
    return this.getList<WmsCountVariance>('/wmsCountVariances', signal);
  }

  listCarriers(signal?: AbortSignal): Promise<WmsCarrier[]> {
    return this.getList<WmsCarrier>('/wmsCarriers', signal);
  }

  listShippingRates(shipmentNumber: string, signal?: AbortSignal): Promise<WmsShippingRate[]> {
    const filter = `?$filter=shipmentNumber eq '${encodeURIComponent(shipmentNumber)}'`;
    return this.getList<WmsShippingRate>(`/wmsShippingRates${filter}`, signal);
  }

  /** Worker menu tree, expanding child menu items for the mobile app. */
  getWorkerMenu(menuCode: string, signal?: AbortSignal): Promise<WmsWorkerMenu | undefined> {
    const path = `/wmsWorkerMenus?$filter=code eq '${encodeURIComponent(menuCode)}'&$expand=menuItems`;
    return this.getList<WmsWorkerMenu>(path, signal).then((rows) => rows[0]);
  }

  // ---- Transactional write (the sync spine) ------------------------------

  /**
   * Submit a transactional flow action (receive/pick/count/…) to BC.
   * Posts to the `wmsActionRequests` API set; BC's OnInsert dispatches to the
   * right service codeunit and returns the result inline. Idempotent on
   * `requestId` — re-posting the same id returns the prior result.
   */
  async submitAction(req: WmsActionRequest, signal?: AbortSignal): Promise<WmsActionResult> {
    const body = {
      requestId: req.requestId,
      flowId: req.flowId,
      payload: JSON.stringify(req.payload),
      workerId: req.workerId ?? '',
    };
    return this.send<WmsActionResult>('POST', '/wmsActionRequests', body, signal);
  }

  /** Look up a previously-submitted action result (used to confirm after a flaky network). */
  async getActionResult(requestId: string, signal?: AbortSignal): Promise<WmsActionResult | undefined> {
    const path = `/wmsActionRequests?$filter=requestId eq ${requestId}`;
    return this.getList<WmsActionResult>(path, signal).then((rows) => rows[0]);
  }

  // ---- Low-level ---------------------------------------------------------

  private async getList<T>(path: string, signal?: AbortSignal): Promise<T[]> {
    const r = await this.send<{ value: T[] }>('GET', path, undefined, signal);
    return r.value;
  }

  private async send<T>(
    method: 'GET' | 'POST' | 'PATCH',
    path: string,
    body: unknown,
    signal?: AbortSignal,
  ): Promise<T> {
    let token: string;
    try {
      token = await this.opts.getAccessToken();
    } catch (e) {
      throw new BcOfflineError('Failed to acquire access token', e);
    }

    const headers: Record<string, string> = {
      Authorization: `Bearer ${token}`,
      Accept: 'application/json',
    };
    if (body !== undefined) headers['Content-Type'] = 'application/json';

    const init: RequestInit = { method, headers };
    if (body !== undefined) init.body = JSON.stringify(body);
    if (signal) init.signal = signal;

    let res: Response;
    try {
      res = await this.doFetch(`${this.base}${path}`, init);
    } catch (e) {
      // fetch only rejects on network failure — everything HTTP resolves.
      throw new BcOfflineError(`Network error calling ${method} ${path}`, e);
    }

    if (!res.ok) {
      const text = await res.text().catch(() => '');
      throw new BcApiError(`BC ${method} ${path} → ${res.status}`, res.status, text);
    }

    if (res.status === 204) return undefined as T;
    return (await res.json()) as T;
  }
}
