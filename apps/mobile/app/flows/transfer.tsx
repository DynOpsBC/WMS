import { Stack } from 'expo-router';
import { FlowRunner } from '@/flows/FlowRunner';
import type { FlowStep } from '@/flows/types';

const STEPS: FlowStep[] = [
  { id: 'fromLocation', kind: 'scan', label: 'Scan from warehouse', expects: 'location' },
  { id: 'toLocation', kind: 'scan', label: 'Scan to warehouse', expects: 'location' },
  { id: 'itemNo', kind: 'scan', label: 'Scan item', expects: 'item' },
  { id: 'qty', kind: 'enter-qty', label: 'Quantity to transfer' },
  { id: 'confirm', kind: 'confirm', label: 'Register transfer' },
];

export default function TransferFlow() {
  return (
    <>
      <Stack.Screen options={{ title: 'Transfer' }} />
      <FlowRunner
        flowId="TRANSFER"
        steps={STEPS}
        endpoint={{ path: '/wmsTransfers', method: 'POST' }}
        onComplete={() => {}}
      />
    </>
  );
}
