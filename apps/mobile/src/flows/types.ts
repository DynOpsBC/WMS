export type FlowStepKind =
  | 'scan'
  | 'enter-qty'
  | 'enter-text'
  | 'select-option'
  | 'capture-lot'
  | 'capture-serial'
  | 'capture-expiry'
  | 'capture-weight'
  | 'confirm'
  | 'done';

export interface FlowStep {
  id: string;
  kind: FlowStepKind;
  label: string;
  hint?: string;
  expects?: 'item' | 'bin' | 'lp' | 'location' | 'po' | 'shipment' | 'transfer' | 'rma' | 'lot' | 'serial' | 'qty' | 'free';
}

export interface FlowState {
  flowId: string;
  steps: FlowStep[];
  cursor: number;
  data: Record<string, string | number>;
}
