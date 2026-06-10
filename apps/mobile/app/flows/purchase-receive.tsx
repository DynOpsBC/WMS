import { Stack } from 'expo-router';
import { FlowPayloadSchemas } from '@bcwmsapp/shared';
import { FlowRunner } from '@/flows/FlowRunner';
import type { FlowStep } from '@/flows/types';

const STEPS: FlowStep[] = [
  { id: 'receiptNo', kind: 'scan', label: 'Scan warehouse receipt', expects: 'po', hint: 'Receipt # or PO #' },
  { id: 'itemNo', kind: 'scan', label: 'Scan item barcode', expects: 'item' },
  { id: 'qty', kind: 'enter-qty', label: 'Enter quantity received' },
  { id: 'binCode', kind: 'scan', label: 'Scan put-away bin (optional)', expects: 'bin', hint: 'Leave blank to defer put-away' },
  { id: 'confirm', kind: 'confirm', label: 'Confirm receipt' },
];

export default function PurchaseReceiveFlow() {
  return (
    <>
      <Stack.Screen options={{ title: 'PO Receive' }} />
      <FlowRunner flowId="PURCH-RECEIVE" steps={STEPS} schema={FlowPayloadSchemas['PURCH-RECEIVE']} />
    </>
  );
}
