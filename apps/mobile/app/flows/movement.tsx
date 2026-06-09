import { Stack } from 'expo-router';
import { FlowRunner } from '@/flows/FlowRunner';
import type { FlowStep } from '@/flows/types';

const STEPS: FlowStep[] = [
  { id: 'fromBin', kind: 'scan', label: 'Scan source bin', expects: 'bin' },
  { id: 'itemNo', kind: 'scan', label: 'Scan item', expects: 'item' },
  { id: 'qty', kind: 'enter-qty', label: 'Quantity to move' },
  { id: 'toBin', kind: 'scan', label: 'Scan destination bin', expects: 'bin' },
  { id: 'confirm', kind: 'confirm', label: 'Register movement' },
];

export default function MovementFlow() {
  return (
    <>
      <Stack.Screen options={{ title: 'Movement' }} />
      <FlowRunner
        flowId="MOVEMENT"
        steps={STEPS}
        endpoint={{ path: '/wmsMovements', method: 'POST' }}
        onComplete={() => {}}
      />
    </>
  );
}
