import { Stack } from 'expo-router';
import { FlowRunner } from '@/flows/FlowRunner';
import type { FlowStep } from '@/flows/types';

const STEPS: FlowStep[] = [
  { id: 'productionOrderNo', kind: 'scan', label: 'Scan production order' },
  { id: 'itemNo', kind: 'scan', label: 'Scan finished item', expects: 'item' },
  { id: 'qty', kind: 'enter-qty', label: 'Quantity completed' },
  { id: 'toBin', kind: 'scan', label: 'Scan put-away bin', expects: 'bin' },
  { id: 'confirm', kind: 'confirm', label: 'Report as finished' },
];

export default function RafFlow() {
  return (
    <>
      <Stack.Screen options={{ title: 'Report as finished' }} />
      <FlowRunner flowId="RAF" steps={STEPS} />
    </>
  );
}
