import { Stack } from 'expo-router';
import { FlowRunner } from '@/flows/FlowRunner';
import type { FlowStep } from '@/flows/types';

const STEPS: FlowStep[] = [
  { id: 'shipmentNo', kind: 'scan', label: 'Scan shipment', expects: 'shipment' },
  { id: 'sourceBin', kind: 'scan', label: 'Confirm source bin', expects: 'bin', hint: 'System-suggested by bin ranking + FEFO' },
  { id: 'itemNo', kind: 'scan', label: 'Scan item', expects: 'item' },
  { id: 'lot', kind: 'capture-lot', label: 'Confirm lot (if tracked)' },
  { id: 'qty', kind: 'enter-qty', label: 'Quantity picked' },
  { id: 'stagingBin', kind: 'scan', label: 'Place at staging bin', expects: 'bin' },
  { id: 'confirm', kind: 'confirm', label: 'Register pick line' },
];

export default function PickFlow() {
  return (
    <>
      <Stack.Screen options={{ title: 'Pick' }} />
      <FlowRunner
        flowId="PICK"
        steps={STEPS}
        endpoint={{ path: '/wmsPicks', method: 'POST' }}
        onComplete={() => {}}
      />
    </>
  );
}
