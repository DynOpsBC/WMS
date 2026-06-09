import { Stack } from 'expo-router';
import { FlowRunner } from '@/flows/FlowRunner';
import type { FlowStep } from '@/flows/types';

const STEPS: FlowStep[] = [
  { id: 'activityNo', kind: 'scan', label: 'Scan put-away activity', hint: 'Warehouse activity #' },
  { id: 'sourceBin', kind: 'scan', label: 'Confirm pick (source) bin', expects: 'bin' },
  { id: 'itemNo', kind: 'scan', label: 'Scan item', expects: 'item' },
  { id: 'qty', kind: 'enter-qty', label: 'Quantity' },
  { id: 'targetBin', kind: 'scan', label: 'Scan destination bin', expects: 'bin' },
  { id: 'confirm', kind: 'confirm', label: 'Register put-away' },
];

export default function PutawayFlow() {
  return (
    <>
      <Stack.Screen options={{ title: 'Put-away' }} />
      <FlowRunner
        flowId="PUTAWAY"
        steps={STEPS}
        endpoint={{ path: '/wmsPutaways', method: 'POST' }}
        onComplete={() => {}}
      />
    </>
  );
}
