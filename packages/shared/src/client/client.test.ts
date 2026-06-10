import { describe, expect, it, vi } from 'vitest';
import { BcApiError, BcClient, BcOfflineError } from './index';

const env = {
  tenantId: '11111111-1111-1111-1111-111111111111',
  environmentName: 'Sandbox',
  companyId: '22222222-2222-2222-2222-222222222222',
};

function clientWith(fetchImpl: typeof fetch) {
  return new BcClient({ env, getAccessToken: async () => 'token-abc', fetchImpl });
}

describe('BcClient.submitAction', () => {
  it('POSTs a serialized payload with bearer auth and parses the result', async () => {
    const fetchImpl = vi.fn(async (_url: string, init?: RequestInit) => {
      expect(init?.method).toBe('POST');
      const headers = init?.headers as Record<string, string>;
      expect(headers['Authorization']).toBe('Bearer token-abc');
      expect(headers['Content-Type']).toBe('application/json');
      const body = JSON.parse(init!.body as string);
      expect(body).toMatchObject({
        requestId: 'req-1',
        flowId: 'PICK',
        payload: JSON.stringify({ shipmentNo: 'WHS-1', qty: 5 }),
        workerId: 'PETER',
      });
      return new Response(
        JSON.stringify({
          systemId: '33333333-3333-3333-3333-333333333333',
          requestId: 'req-1',
          flowId: 'PICK',
          status: 'Succeeded',
          resultMessage: 'OK',
          resultDocumentNo: 'WHS-1',
          processedAt: '2026-06-10T10:00:00Z',
        }),
        { status: 201, headers: { 'Content-Type': 'application/json' } },
      );
    }) as unknown as typeof fetch;

    const result = await clientWith(fetchImpl).submitAction({
      requestId: 'req-1',
      flowId: 'PICK',
      payload: { shipmentNo: 'WHS-1', qty: 5 },
      workerId: 'PETER',
    });

    expect(result.status).toBe('Succeeded');
    expect(result.resultDocumentNo).toBe('WHS-1');
    expect(fetchImpl).toHaveBeenCalledOnce();
  });

  it('throws a retryable BcApiError on 503', async () => {
    const fetchImpl = vi.fn(async () => new Response('busy', { status: 503 })) as unknown as typeof fetch;
    const err = await clientWith(fetchImpl)
      .submitAction({ requestId: 'r', flowId: 'PICK', payload: {} })
      .catch((e) => e);
    expect(err).toBeInstanceOf(BcApiError);
    expect((err as BcApiError).retryable).toBe(true);
  });

  it('throws a non-retryable BcApiError on 400', async () => {
    const fetchImpl = vi.fn(async () => new Response('bad', { status: 400 })) as unknown as typeof fetch;
    const err = await clientWith(fetchImpl)
      .submitAction({ requestId: 'r', flowId: 'PICK', payload: {} })
      .catch((e) => e);
    expect(err).toBeInstanceOf(BcApiError);
    expect((err as BcApiError).retryable).toBe(false);
  });

  it('throws BcOfflineError when fetch rejects (network down)', async () => {
    const fetchImpl = vi.fn(async () => {
      throw new TypeError('Failed to fetch');
    }) as unknown as typeof fetch;
    const err = await clientWith(fetchImpl)
      .submitAction({ requestId: 'r', flowId: 'PICK', payload: {} })
      .catch((e) => e);
    expect(err).toBeInstanceOf(BcOfflineError);
  });
});

describe('BcClient reads', () => {
  it('unwraps the OData value array', async () => {
    const fetchImpl = vi.fn(
      async () =>
        new Response(JSON.stringify({ value: [{ number: 'LPN-1' }, { number: 'LPN-2' }] }), {
          status: 200,
          headers: { 'Content-Type': 'application/json' },
        }),
    ) as unknown as typeof fetch;
    const lps = await clientWith(fetchImpl).listLicensePlates();
    expect(lps).toHaveLength(2);
  });
});
