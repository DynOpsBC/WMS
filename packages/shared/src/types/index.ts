export type Iso8601DateTime = string;
export type Guid = string;

export interface WmsWorker {
  systemId: Guid;
  userId: string;
  userName: string;
  defaultLocationCode: string;
  menuCode: string;
  inactive: boolean;
  allowPickLocationOverride: boolean;
  cycleCountSupervisor: boolean;
  entraObjectId: Guid;
  lastSignIn: Iso8601DateTime | null;
  lastModifiedDateTime: Iso8601DateTime;
}

export type WmsLicensePlateStatus =
  | 'Open'
  | 'In Transit'
  | 'Quarantine'
  | 'Closed'
  | 'Shipped';

export interface WmsLicensePlate {
  systemId: Guid;
  number: string;
  locationCode: string;
  binCode: string;
  status: WmsLicensePlateStatus;
  parentLpNumber: string;
  containerTypeCode: string;
  createdAt: Iso8601DateTime;
  createdBy: string;
  closed: boolean;
  lastModifiedDateTime: Iso8601DateTime;
}

export interface WmsContainer {
  systemId: Guid;
  number: string;
  shipmentNumber: string;
  containerTypeCode: string;
  packingLocation: string;
  status: string;
  grossWeight: number;
  trackingNumber: string;
  lastModifiedDateTime: Iso8601DateTime;
}

export interface WmsCycleCountPlan {
  systemId: Guid;
  planNumber: string;
  description: string;
  locationCode: string;
  scheduledFor: string | null;
  requiresSupervisor: boolean;
  status: string;
  lastModifiedDateTime: Iso8601DateTime;
}

export interface WmsCountVariance {
  systemId: Guid;
  planNumber: string;
  lineNumber: number;
  itemNumber: string;
  locationCode: string;
  binCode: string;
  systemQuantity: number;
  countedQuantity: number;
  variance: number;
  countedBy: string;
  approvedBy: string;
  lastModifiedDateTime: Iso8601DateTime;
}

export interface WmsCarrier {
  systemId: Guid;
  code: string;
  name: string;
  provider: string;
  active: boolean;
  lastModifiedDateTime: Iso8601DateTime;
}

export interface WmsShippingRate {
  systemId: Guid;
  rateId: Guid;
  shipmentNumber: string;
  carrierCode: string;
  serviceCode: string;
  serviceName: string;
  amount: number;
  currency: string;
  estimatedDays: number;
  selected: boolean;
  lastModifiedDateTime: Iso8601DateTime;
}

export interface WmsMenuItem {
  systemId: Guid;
  menuCode: string;
  lineNumber: number;
  description: string;
  itemType: string;
  childMenuCode: string;
  flowId: string;
  icon: string;
}

export interface WmsWorkerMenu {
  systemId: Guid;
  code: string;
  description: string;
  isRoot: boolean;
  menuItems?: WmsMenuItem[];
}

/**
 * A single transactional submission from a mobile flow (receive, pick, count, …).
 * `requestId` is the idempotency key — re-submitting the same id is a no-op on the BC side.
 */
export interface WmsActionRequest {
  requestId: Guid;
  flowId: string;
  payload: Record<string, string | number | boolean | null>;
  workerId?: string;
  /** Locally-generated device UUID. BC validates it's an Active WMS Mobile Device. */
  deviceId?: string;
}

export type WmsDeviceStatus = 'Unpaired' | 'Pending' | 'Active' | 'Revoked';

export interface WmsMobileDevice {
  systemId: Guid;
  deviceId: string;
  deviceName: string;
  manufacturer: string;
  model: string;
  osVersion: string;
  appVersion: string;
  defaultWarehouse: string;
  status: WmsDeviceStatus;
  pairedAt: Iso8601DateTime | null;
  pairedBy: string;
  companyId: Guid;
  lastSeen: Iso8601DateTime | null;
  revokedAt: Iso8601DateTime | null;
  revokedBy: string;
  revokeReason: string;
  lastModifiedDateTime: Iso8601DateTime;
}

export interface CompletePairingInput {
  deviceId: string;
  deviceName: string;
  manufacturer: string;
  model: string;
  osVersion: string;
  appVersion: string;
  defaultWarehouse: string;
}

export type WmsActionStatus = 'Pending' | 'Succeeded' | 'Failed';

export interface WmsActionResult {
  systemId: Guid;
  requestId: Guid;
  flowId: string;
  status: WmsActionStatus;
  resultMessage: string;
  resultDocumentNo: string;
  processedAt: Iso8601DateTime | null;
}

export interface BcEnvironment {
  tenantId: Guid;
  environmentName: string;
  companyId: Guid;
}

export interface AuthSession {
  accessToken: string;
  expiresAt: Iso8601DateTime;
  account: {
    objectId: Guid;
    username: string;
    name: string;
  };
}
