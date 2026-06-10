import { z } from 'zod';

export const WmsLicensePlateStatusSchema = z.enum([
  'Open',
  'In Transit',
  'Quarantine',
  'Closed',
  'Shipped',
]);

export const WmsWorkerSchema = z.object({
  systemId: z.string().uuid(),
  userId: z.string().min(1).max(50),
  userName: z.string().max(100),
  defaultLocationCode: z.string().max(10),
  menuCode: z.string().max(20),
  inactive: z.boolean(),
  allowPickLocationOverride: z.boolean(),
  cycleCountSupervisor: z.boolean(),
  entraObjectId: z.string().uuid(),
  lastSignIn: z.string().datetime().nullable(),
  lastModifiedDateTime: z.string().datetime(),
});

export const WmsLicensePlateSchema = z.object({
  systemId: z.string().uuid(),
  number: z.string().min(1).max(20),
  locationCode: z.string().max(10),
  binCode: z.string().max(20),
  status: WmsLicensePlateStatusSchema,
  parentLpNumber: z.string().max(20),
  containerTypeCode: z.string().max(20),
  createdAt: z.string().datetime(),
  createdBy: z.string().max(50),
  closed: z.boolean(),
  lastModifiedDateTime: z.string().datetime(),
});

export const WmsActionStatusSchema = z.enum(['Pending', 'Succeeded', 'Failed']);

export const WmsActionRequestSchema = z.object({
  requestId: z.string().uuid(),
  flowId: z.string().min(1).max(50),
  payload: z.record(z.union([z.string(), z.number(), z.boolean(), z.null()])),
  workerId: z.string().max(50).optional(),
});

export const WmsActionResultSchema = z.object({
  systemId: z.string().uuid(),
  requestId: z.string().uuid(),
  flowId: z.string(),
  status: WmsActionStatusSchema,
  resultMessage: z.string(),
  resultDocumentNo: z.string(),
  processedAt: z.string().datetime().nullable(),
});

/**
 * Per-flow payload guards. Validated on the mobile client BEFORE enqueuing,
 * so a malformed scan never reaches the offline queue.
 */
export const FlowPayloadSchemas = {
  'PURCH-RECEIVE': z.object({
    receiptNo: z.string().min(1),
    itemNo: z.string().min(1),
    qty: z.number().positive(),
    binCode: z.string().optional(),
  }),
  'LP-RECEIVE': z.object({
    lpNo: z.string().min(1),
    receiptNo: z.string().min(1),
    locationCode: z.string().min(1),
  }),
  PICK: z.object({
    shipmentNo: z.string().min(1),
    sourceBin: z.string().min(1),
    itemNo: z.string().min(1),
    qty: z.number().positive(),
    stagingBin: z.string().min(1),
  }),
  'PALLET-PICK': z.object({
    shipmentNo: z.string().min(1),
    lpNo: z.string().min(1),
    stagingBin: z.string().min(1),
  }),
  'CYCLE-COUNT': z.object({
    planNo: z.string().min(1),
    binCode: z.string().min(1),
    itemNo: z.string().min(1),
    countedQty: z.number().nonnegative(),
  }),
  MOVEMENT: z.object({
    fromBin: z.string().min(1),
    itemNo: z.string().min(1),
    qty: z.number().positive(),
    toBin: z.string().min(1),
  }),
} as const;

export type KnownFlowId = keyof typeof FlowPayloadSchemas;
