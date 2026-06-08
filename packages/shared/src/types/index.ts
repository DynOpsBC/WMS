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
