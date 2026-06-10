import { Stack } from 'expo-router';
import { FlowPayloadSchemas } from '@bcwmsapp/shared';
import { FlowRunner } from '@/flows/FlowRunner';
import type { FlowStep } from '@/flows/types';

const STEPS: FlowStep[] = [
  { id: 'lpNo', kind: 'scan', label: 'Scan License Plate', expects: 'lp', hint: 'LPN on the pallet' },
  { id: 'receiptNo', kind: 'scan', label: 'Scan ASN / receipt #', expects: 'po' },
  { id: 'locationCode', kind: 'scan', label: 'Scan receiving bin', expects: 'bin' },
  { id: 'confirm', kind: 'confirm', label: 'Register LP receipt' },
];

export default function LpReceiveFlow() {
  return (
    <>
      <Stack.Screen options={{ title: 'LP Receive' }} />
      <FlowRunner flowId="LP-RECEIVE" steps={STEPS} schema={FlowPayloadSchemas['LP-RECEIVE']} />
    </>
  );
}
