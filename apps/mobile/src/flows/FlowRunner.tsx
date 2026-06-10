import { useMemo, useState } from 'react';
import { Text, View, StyleSheet, Pressable, TextInput, Alert } from 'react-native';
import type { z } from 'zod';
import { useScan } from '@/hooks/useScan';
import { OfflineQueue } from '@/lib/offlineQueue';
import { syncEngine } from '@/lib/runtime';
import { auth } from '@/lib/auth';
import { newRequestId } from '@/lib/id';
import type { FlowStep } from './types';

interface Props {
  flowId: string;
  steps: FlowStep[];
  /** Optional zod guard from FlowPayloadSchemas — rejects malformed input before enqueue. */
  schema?: z.ZodTypeAny;
  onComplete?: (data: Record<string, string | number>) => void;
}

/**
 * Generic flow runner mirroring D365 WMA's "step prompt + scan / enter / next" pattern.
 * On completion it validates, enqueues a transactional action, and triggers the
 * sync engine — which POSTs it to BC's `wmsActionRequests` endpoint with retry/backoff.
 */
export function FlowRunner({ flowId, steps, schema, onComplete }: Props) {
  const [cursor, setCursor] = useState(0);
  const [data, setData] = useState<Record<string, string | number>>({});
  const [input, setInput] = useState('');
  const step = useMemo(() => steps[cursor], [steps, cursor]);

  useScan(
    (e) => {
      if (step?.kind === 'scan') accept(e.data);
    },
    [step],
  );

  function accept(value: string | number) {
    if (!step) return;
    const next = { ...data, [step.id]: value };
    setData(next);
    setInput('');
    if (cursor + 1 < steps.length) setCursor(cursor + 1);
    else complete(next);
  }

  function complete(final: Record<string, string | number>) {
    // Strip the trailing "confirm" step value; it carries no data.
    const payload: Record<string, string | number> = { ...final };
    delete payload['confirm'];

    if (schema) {
      const parsed = schema.safeParse(payload);
      if (!parsed.success) {
        Alert.alert('Invalid entry', parsed.error.issues.map((i) => i.message).join('\n'));
        return;
      }
    }

    const session = auth.loadSession();
    OfflineQueue.enqueue({
      requestId: newRequestId(),
      flowId,
      payload,
      ...(session?.username ? { workerId: session.username } : {}),
    });

    void syncEngine.flush();
    onComplete?.(final);

    const pending = OfflineQueue.size();
    Alert.alert(
      'Recorded',
      pending > 1
        ? `${flowId} queued. ${pending} actions waiting to sync.`
        : `${flowId} submitted to Business Central.`,
    );
    setCursor(0);
    setData({});
  }

  if (!step) {
    return (
      <View style={styles.container}>
        <Text style={styles.label}>Flow complete</Text>
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
        <Pressable style={[styles.button, styles.secondary]} onPress={() => cursor > 0 && setCursor(cursor - 1)}>
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
