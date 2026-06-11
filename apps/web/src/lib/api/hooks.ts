import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query';
import type { WmsActionRequest } from '@bcwmsapp/shared';
import { bcClient } from './client.ts';

export function useCountVariances() {
  return useQuery({
    queryKey: ['countVariances'],
    queryFn: ({ signal }) => bcClient.listCountVariances(signal),
    retry: 1,
  });
}

export function useCarriers() {
  return useQuery({
    queryKey: ['carriers'],
    queryFn: ({ signal }) => bcClient.listCarriers(signal),
    retry: 1,
  });
}

export function useShippingRates(shipmentNumber: string) {
  return useQuery({
    queryKey: ['shippingRates', shipmentNumber],
    queryFn: ({ signal }) => bcClient.listShippingRates(shipmentNumber, signal),
    enabled: shipmentNumber.length > 0,
    retry: 1,
  });
}

export function useContainers() {
  return useQuery({
    queryKey: ['containers'],
    queryFn: ({ signal }) => bcClient.listContainers(signal),
    retry: 1,
  });
}

/** Submit a transactional action to BC (e.g. approve a count variance). */
export function useSubmitAction() {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: (req: WmsActionRequest) => bcClient.submitAction(req),
    onSuccess: () => {
      void qc.invalidateQueries({ queryKey: ['countVariances'] });
    },
  });
}

export function useMobileDevices() {
  return useQuery({
    queryKey: ['mobileDevices'],
    queryFn: ({ signal }) => bcClient.listMobileDevices(signal),
    retry: 1,
  });
}

export function useRevokeDevice() {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: ({ deviceId, reason }: { deviceId: string; reason: string }) =>
      bcClient.revokeDevice(deviceId, reason),
    onSuccess: () => {
      void qc.invalidateQueries({ queryKey: ['mobileDevices'] });
    },
  });
}
