import { Stack } from 'expo-router';
import { FlowRunner } from '@/flows/FlowRunner';
import type { FlowStep } from '@/flows/types';

const STEPS: FlowStep[] = [
  { id: 'shipmentNo', kind: 'scan', label: 'Scan shipment', expects: 'shipment' },
  { id: 'containerNo', kind: 'scan', label: 'Scan or generate container #', expects: 'lp', hint: 'Print LP from handheld' },
  { id: 'itemNo', kind: 'scan', label: 'Scan item to pack', expects: 'item' },
  { id: 'qty', kind: 'enter-qty', label: 'Quantity into container' },
  { id: 'weight', kind: 'capture-weight', label: 'Capture weight (if catch-weight)' },
  { id: 'confirm', kind: 'confirm', label: 'Add to container' },
];

export default function PackFlow() {
  return (
    <>
      <Stack.Screen options={{ title: 'Pack' }} />
      <FlowRunner flowId="PACK" steps={STEPS} />
    </>
  );
}
