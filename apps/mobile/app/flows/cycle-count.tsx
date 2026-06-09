import { Stack } from 'expo-router';
import { FlowRunner } from '@/flows/FlowRunner';
import type { FlowStep } from '@/flows/types';

const STEPS: FlowStep[] = [
  { id: 'planNo', kind: 'scan', label: 'Scan or select count plan', expects: 'free' },
  { id: 'binCode', kind: 'scan', label: 'Scan bin to count', expects: 'bin' },
  { id: 'itemNo', kind: 'scan', label: 'Scan item', expects: 'item' },
  { id: 'countedQty', kind: 'enter-qty', label: 'Counted quantity' },
  { id: 'confirm', kind: 'confirm', label: 'Record count' },
];

export default function CycleCountFlow() {
  return (
    <>
      <Stack.Screen options={{ title: 'Cycle count' }} />
      <FlowRunner
        flowId="CYCLE-COUNT"
        steps={STEPS}
        endpoint={{ path: '/wmsCountVariances', method: 'POST' }}
        onComplete={() => {}}
      />
    </>
  );
}
