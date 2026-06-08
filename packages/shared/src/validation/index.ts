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
