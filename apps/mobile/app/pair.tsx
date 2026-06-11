import { Stack, useRouter } from 'expo-router';
import { useEffect, useRef, useState } from 'react';
import { Text, View, StyleSheet, Pressable, ActivityIndicator, TextInput, Platform } from 'react-native';
import { auth, type DeviceCodeChallenge } from '@/lib/auth';
import { getOrCreateDevice, markPaired } from '@/lib/device';
import { bcClient, startRuntime } from '@/lib/runtime';

type Phase = 'idle' | 'requesting' | 'awaiting' | 'registering' | 'paired' | 'error';

export default function PairScreen() {
  const router = useRouter();
  const [phase, setPhase] = useState<Phase>('idle');
  const [challenge, setChallenge] = useState<DeviceCodeChallenge | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [secondsLeft, setSecondsLeft] = useState<number>(0);
  const [deviceName, setDeviceName] = useState('Warehouse handheld');
  const [defaultWarehouse, setDefaultWarehouse] = useState('MAIN');
  const abortRef = useRef<AbortController | null>(null);

  useEffect(() => {
    if (!challenge) return;
    setSecondsLeft(challenge.expiresInSec);
    const t = setInterval(() => setSecondsLeft((s) => Math.max(0, s - 1)), 1000);
    return () => clearInterval(t);
  }, [challenge]);

  async function begin() {
    setError(null);
    setPhase('requesting');
    try {
      const ch = await auth.startDeviceCode();
      setChallenge(ch);
      setPhase('awaiting');

      abortRef.current = new AbortController();
      const session = await auth.awaitDeviceCode(ch, abortRef.current.signal);

      setPhase('registering');
      const device = getOrCreateDevice({ deviceName, manufacturer: detectManufacturer() });
      const { deviceSystemId } = await bcClient.completePairing({
        deviceId: device.deviceId,
        deviceName,
        manufacturer: device.manufacturer,
        model: device.model,
        osVersion: Platform.Version?.toString() ?? '',
        appVersion: '0.1.0',
        defaultWarehouse,
      });
      markPaired({
        deviceName,
        deviceSystemId,
        companyId: session.objectId, // placeholder until we read company SystemId from BC
        pairedBy: session.username,
        defaultWarehouse,
      });
      setPhase('paired');
      startRuntime();
      setTimeout(() => router.replace('/menu'), 1200);
    } catch (e) {
      setError(e instanceof Error ? e.message : String(e));
      setPhase('error');
    }
  }

  function cancel() {
    abortRef.current?.abort();
    setPhase('idle');
    setChallenge(null);
    setError(null);
  }

  return (
    <View style={styles.container}>
      <Stack.Screen options={{ title: 'Pair with Business Central', headerStyle: { backgroundColor: '#0b3b66' }, headerTintColor: '#fff' }} />

      {phase === 'idle' && (
        <>
          <Text style={styles.heading}>Device details</Text>
          <Text style={styles.body}>These will be saved on the WMS Mobile Device record in Business Central.</Text>

          <Text style={styles.label}>Device name</Text>
          <TextInput value={deviceName} onChangeText={setDeviceName} style={styles.input} autoCapitalize="words" />

          <Text style={styles.label}>Default warehouse code</Text>
          <TextInput value={defaultWarehouse} onChangeText={setDefaultWarehouse} style={styles.input} autoCapitalize="characters" />

          <Pressable style={styles.button} onPress={begin}>
            <Text style={styles.buttonText}>Request pairing code</Text>
          </Pressable>
        </>
      )}

      {(phase === 'requesting') && (
        <View style={styles.center}>
          <ActivityIndicator size="large" color="#1670c0" />
          <Text style={styles.body}>Requesting pairing code from Microsoft…</Text>
        </View>
      )}

      {phase === 'awaiting' && challenge && (
        <>
          <Text style={styles.heading}>Hand to admin</Text>
          <Text style={styles.body}>
            Ask a warehouse administrator to open the URL below on a desktop, sign in with their Entra ID admin
            account, and type this code.
          </Text>

          <View style={styles.codeBlock}>
            <Text style={styles.codeLabel}>Code</Text>
            <Text style={styles.code}>{challenge.userCode}</Text>
            <Text style={styles.codeUrl}>{challenge.verificationUri}</Text>
          </View>

          <View style={styles.statusRow}>
            <ActivityIndicator color="#1670c0" />
            <Text style={styles.statusText}>
              Waiting for admin… expires in {Math.floor(secondsLeft / 60)}:{String(secondsLeft % 60).padStart(2, '0')}
            </Text>
          </View>

          <Pressable style={[styles.button, styles.secondary]} onPress={cancel}>
            <Text style={styles.secondaryText}>Cancel</Text>
          </Pressable>
        </>
      )}

      {phase === 'registering' && (
        <View style={styles.center}>
          <ActivityIndicator size="large" color="#1670c0" />
          <Text style={styles.body}>Registering device with Business Central…</Text>
        </View>
      )}

      {phase === 'paired' && (
        <View style={styles.center}>
          <Text style={styles.bigCheck}>✓</Text>
          <Text style={styles.heading}>Paired</Text>
          <Text style={styles.body}>This device is now bound to your Business Central company.</Text>
        </View>
      )}

      {phase === 'error' && (
        <>
          <Text style={styles.heading}>Pairing failed</Text>
          <Text style={styles.error}>{error}</Text>
          <Pressable style={styles.button} onPress={() => setPhase('idle')}>
            <Text style={styles.buttonText}>Try again</Text>
          </Pressable>
        </>
      )}
    </View>
  );
}

function detectManufacturer(): string {
  if (Platform.OS === 'ios') return 'Apple iOS';
  if (Platform.OS === 'android') return 'Android';
  return 'Other';
}

const styles = StyleSheet.create({
  container: { flex: 1, backgroundColor: '#fff', padding: 20 },
  center: { flex: 1, alignItems: 'center', justifyContent: 'center', gap: 16 },
  heading: { fontSize: 24, fontWeight: '600', color: '#0f172a', marginBottom: 6 },
  body: { fontSize: 14, color: '#475569', marginBottom: 16, lineHeight: 20 },
  label: { fontSize: 12, color: '#64748b', marginBottom: 6, marginTop: 12 },
  input: { borderWidth: 2, borderColor: '#1670c0', borderRadius: 10, paddingHorizontal: 14, paddingVertical: 12, fontSize: 16, color: '#0f172a' },
  button: { backgroundColor: '#1670c0', paddingVertical: 14, borderRadius: 10, alignItems: 'center', marginTop: 24 },
  buttonText: { color: '#fff', fontWeight: '600', fontSize: 16 },
  secondary: { backgroundColor: '#e2e8f0' },
  secondaryText: { color: '#0f172a', fontWeight: '600', fontSize: 16 },
  codeBlock: { backgroundColor: '#0b3b66', borderRadius: 14, padding: 24, alignItems: 'center', marginVertical: 16 },
  codeLabel: { color: '#cde0f3', fontSize: 12, textTransform: 'uppercase', letterSpacing: 1 },
  code: { color: '#fff', fontSize: 48, fontWeight: '700', fontFamily: 'Courier', letterSpacing: 6, marginVertical: 12 },
  codeUrl: { color: '#cde0f3', fontSize: 13 },
  statusRow: { flexDirection: 'row', alignItems: 'center', gap: 10, justifyContent: 'center' },
  statusText: { color: '#475569', fontSize: 13 },
  bigCheck: { fontSize: 80, color: '#10b981' },
  error: { color: '#dc2626', fontSize: 14, marginBottom: 16 },
});
