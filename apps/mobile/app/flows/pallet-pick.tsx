import { Stack } from 'expo-router';
import { FlowPayloadSchemas } from '@bcwmsapp/shared';
import { FlowRunner } from '@/flows/FlowRunner';
import type { FlowStep } from '@/flows/types';

const STEPS: FlowStep[] = [
  { id: 'shipmentNo', kind: 'scan', label: 'Scan shipment', expects: 'shipment' },
  { id: 'lpNo', kind: 'scan', label: 'Scan pallet license plate', expects: 'lp', hint: 'One scan registers every item on the LP' },
  { id: 'stagingBin', kind: 'scan', label: 'Place at staging bin', expects: 'bin' },
  { id: 'confirm', kind: 'confirm', label: 'Register pallet pick' },
];

export default function PalletPickFlow() {
  return (
    <>
      <Stack.Screen options={{ title: 'Pallet Pick' }} />
      <FlowRunner flowId="PALLET-PICK" steps={STEPS} schema={FlowPayloadSchemas['PALLET-PICK']} />
    </>
  );
}
