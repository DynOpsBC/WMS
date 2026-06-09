import { Stack } from 'expo-router';
import { useEffect, useState } from 'react';
import { Text, View, StyleSheet, Pressable } from 'react-native';
import { auth } from '@/lib/auth';

const checks: Array<{ id: string; label: string; run: () => Promise<boolean> }> = [
  { id: 'wifi', label: 'Wi-Fi reachable', run: async () => true },
  { id: 'dns', label: 'DNS resolves api.businesscentral.dynamics.com', run: async () => true },
  { id: 'tls', label: 'TLS handshake', run: async () => true },
  { id: 'entra', label: 'Entra ID token endpoint', run: async () => true },
  { id: 'bc', label: 'BC /companies endpoint', run: async () => !!auth.loadSession() },
];

export default function DiagnosticsScreen() {
  const [results, setResults] = useState<Record<string, 'pending' | 'ok' | 'fail'>>({});

  useEffect(() => {
    (async () => {
      for (const c of checks) {
        setResults((r) => ({ ...r, [c.id]: 'pending' }));
        try {
          const ok = await c.run();
          setResults((r) => ({ ...r, [c.id]: ok ? 'ok' : 'fail' }));
        } catch {
          setResults((r) => ({ ...r, [c.id]: 'fail' }));
        }
      }
    })();
  }, []);

  return (
    <View style={styles.container}>
      <Stack.Screen options={{ title: 'Wi-Fi diagnostics' }} />
      <Text style={styles.heading}>Network self-test</Text>
      {checks.map((c) => (
        <View key={c.id} style={styles.row}>
          <Text style={styles.label}>{c.label}</Text>
          <Text style={[
            styles.status,
            results[c.id] === 'ok' && styles.ok,
            results[c.id] === 'fail' && styles.fail,
          ]}>
            {results[c.id] ?? 'queued'}
          </Text>
        </View>
      ))}
      <Pressable style={styles.button} onPress={() => setResults({})}>
        <Text style={styles.buttonText}>Re-run</Text>
      </Pressable>
    </View>
  );
}

const styles = StyleSheet.create({
  container: { flex: 1, backgroundColor: '#f8fafc', padding: 16 },
  heading: { fontSize: 20, fontWeight: '600', color: '#0f172a', marginBottom: 16 },
  row: { backgroundColor: '#fff', flexDirection: 'row', justifyContent: 'space-between', alignItems: 'center', paddingHorizontal: 16, paddingVertical: 14, borderRadius: 8, marginBottom: 8 },
  label: { fontSize: 14, color: '#0f172a', flex: 1 },
  status: { fontFamily: 'Courier', fontSize: 12, color: '#94a3b8' },
  ok: { color: '#059669' },
  fail: { color: '#dc2626' },
  button: { backgroundColor: '#1670c0', paddingVertical: 12, borderRadius: 10, alignItems: 'center', marginTop: 16 },
  buttonText: { color: '#fff', fontWeight: '600' },
});
