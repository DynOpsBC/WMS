import { useMemo, useState } from 'react';
import { Text, View, StyleSheet, Pressable, TextInput, Alert } from 'react-native';
import { useScan } from '@/hooks/useScan';
import { OfflineQueue } from '@/lib/offlineQueue';
import type { FlowStep } from './types';

interface Props {
  flowId: string;
  steps: FlowStep[];
  onComplete: (data: Record<string, string | number>) => Promise<void> | void;
  endpoint?: { path: string; method: 'POST' | 'PATCH' };
}

/**
 * Generic flow runner mirroring D365 WMA's "step prompt + scan / enter / next" pattern.
 * - Each step prompts for one value (scan, qty, lot, serial, etc.).
 * - Scans auto-advance.
 * - On completion, enqueues a POST/PATCH if `endpoint` is provided.
 */
export function FlowRunner({ flowId, steps, onComplete, endpoint }: Props) {
  const [cursor, setCursor] = useState(0);
  const [data, setData] = useState<Record<string, string | number>>({});
  const [input, setInput] = useState('');
  const step = useMemo(() => steps[cursor], [steps, cursor]);

  useScan(
    (e) => {
      if (!step) return;
      if (step.kind === 'scan') accept(e.data);
    },
    [step],
  );

  function accept(value: string | number) {
    if (!step) return;
    const next = { ...data, [step.id]: value };
    setData(next);
    setInput('');
    if (cursor + 1 < steps.length) {
      setCursor(cursor + 1);
    } else {
      complete(next);
    }
  }

  async function complete(final: Record<string, string | number>) {
    if (endpoint) {
      OfflineQueue.enqueue({
        type: endpoint.method,
        path: endpoint.path,
        body: { flowId, ...final },
        idempotencyKey: `${flowId}-${Date.now()}`,
      } as never);
    }
    await onComplete(final);
    Alert.alert('Done', `${flowId} recorded.`);
    setCursor(0);
    setData({});
  }

  if (!step) {
    return (
      <View style={styles.container}>
        <Text style={styles.heading}>Flow complete</Text>
      </View>
    );
  }

  return (
    <View style={styles.container}>
      <View style={styles.progress}>
        <Text style={styles.progressText}>
          Step {cursor + 1} / {steps.length}
        </Text>
        <Text style={styles.flowId}>{flowId}</Text>
      </View>
      <Text style={styles.label}>{step.label}</Text>
      {step.hint ? <Text style={styles.hint}>{step.hint}</Text> : null}
      <TextInput
        style={styles.input}
        value={input}
        onChangeText={setInput}
        onSubmitEditing={() => input && accept(step.kind === 'enter-qty' ? Number(input) : input)}
        keyboardType={step.kind === 'enter-qty' ? 'numeric' : 'default'}
        autoCapitalize="characters"
        autoFocus
        placeholder={step.kind === 'scan' ? 'Scan or type…' : 'Enter value'}
        placeholderTextColor="#94a3b8"
      />
      <View style={styles.captured}>
        {Object.entries(data).map(([k, v]) => (
          <View key={k} style={styles.kv}>
            <Text style={styles.kvKey}>{k}</Text>
            <Text style={styles.kvVal}>{String(v)}</Text>
          </View>
        ))}
      </View>
      <View style={styles.actions}>
        <Pressable
          style={[styles.button, styles.secondary]}
          onPress={() => cursor > 0 && setCursor(cursor - 1)}
        >
          <Text style={styles.secondaryText}>Back</Text>
        </Pressable>
        <Pressable
          style={styles.button}
          onPress={() => input && accept(step.kind === 'enter-qty' ? Number(input) : input)}
        >
          <Text style={styles.buttonText}>Next</Text>
        </Pressable>
      </View>
    </View>
  );
}

const styles = StyleSheet.create({
  container: { flex: 1, backgroundColor: '#fff', padding: 16 },
  progress: { flexDirection: 'row', justifyContent: 'space-between', marginBottom: 12 },
  progressText: { color: '#64748b', fontSize: 12 },
  flowId: { color: '#64748b', fontSize: 12, fontFamily: 'Courier' },
  label: { fontSize: 22, fontWeight: '600', color: '#0f172a', marginBottom: 4 },
  hint: { fontSize: 13, color: '#64748b', marginBottom: 16 },
  input: { borderWidth: 2, borderColor: '#1670c0', borderRadius: 10, paddingHorizontal: 14, paddingVertical: 14, fontSize: 18, color: '#0f172a', marginBottom: 16 },
  captured: { flex: 1 },
  kv: { flexDirection: 'row', justifyContent: 'space-between', paddingVertical: 8, borderBottomWidth: 1, borderBottomColor: '#f1f5f9' },
  kvKey: { color: '#64748b', fontSize: 13 },
  kvVal: { color: '#0f172a', fontSize: 13, fontWeight: '600', fontFamily: 'Courier' },
  actions: { flexDirection: 'row', gap: 12, marginTop: 12 },
  button: { flex: 1, backgroundColor: '#1670c0', paddingVertical: 14, borderRadius: 10, alignItems: 'center' },
  buttonText: { color: '#fff', fontWeight: '600' },
  secondary: { backgroundColor: '#e2e8f0' },
  secondaryText: { color: '#0f172a', fontWeight: '600' },
});
