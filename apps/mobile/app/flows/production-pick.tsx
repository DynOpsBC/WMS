import { Stack } from 'expo-router';
import { FlowRunner } from '@/flows/FlowRunner';
import type { FlowStep } from '@/flows/types';

const STEPS: FlowStep[] = [
  { id: 'productionOrderNo', kind: 'scan', label: 'Scan production order' },
  { id: 'componentItemNo', kind: 'scan', label: 'Scan component', expects: 'item' },
  { id: 'fromBin', kind: 'scan', label: 'Scan source bin', expects: 'bin' },
  { id: 'qty', kind: 'enter-qty', label: 'Quantity consumed' },
  { id: 'confirm', kind: 'confirm', label: 'Post consumption' },
];

export default function ProductionPickFlow() {
  return (
    <>
      <Stack.Screen options={{ title: 'Production pick' }} />
      <FlowRunner
        flowId="PRODUCTION-PICK"
        steps={STEPS}
        endpoint={{ path: '/wmsProduction/consume', method: 'POST' }}
        onComplete={() => {}}
      />
    </>
  );
}
