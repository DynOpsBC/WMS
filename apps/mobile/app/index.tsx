import { Link, Stack, useRouter } from 'expo-router';
import { useEffect } from 'react';
import { Text, View, StyleSheet, Pressable } from 'react-native';
import { auth } from '@/lib/auth';
import { loadDevice } from '@/lib/device';
import { scanner } from '@/lib/scanner';
import { startRuntime } from '@/lib/runtime';

/**
 * Entry screen. Decides between three states:
 * - Device is paired + has a session  → straight to /menu
 * - Device is paired but session expired → silent refresh then /menu (handled by getAccessToken)
 * - Device is unpaired → /pair
 *
 * Workers do not see this screen day to day — only on first device setup.
 */
export default function EntryScreen() {
  const router = useRouter();

  useEffect(() => {
    scanner.start();
    const device = loadDevice();
    if (device?.status === 'active' && auth.loadSession()) {
      startRuntime();
      router.replace('/menu');
    } else if (device?.status === 'revoked') {
      router.replace('/pair' as never);
    }
    return () => scanner.stop();
  }, [router]);

  const device = loadDevice();
  const wasRevoked = device?.status === 'revoked';

  return (
    <View style={styles.container}>
      <Stack.Screen options={{ headerShown: false }} />
      <View style={styles.brand}>
        <View style={styles.logo} />
        <Text style={styles.appName}>BCWMSApp</Text>
      </View>
      <Text style={styles.heading}>{wasRevoked ? 'Device revoked' : 'Pair this device'}</Text>
      <Text style={styles.body}>
        {wasRevoked
          ? 'This device was revoked by a warehouse administrator. Re-pair to continue using it.'
          : 'This warehouse device needs to be paired with Business Central one time. After pairing, workers can use the scanner without signing in again.'}
      </Text>

      <View style={styles.steps}>
        <Step n={1} label="Tap the button below to request a pairing code." />
        <Step n={2} label="Hand the device to a warehouse administrator." />
        <Step n={3} label="Admin opens the URL on a desktop and enters the code." />
        <Step n={4} label="Device is now bound to your Business Central company. Done." />
      </View>

      <Link href={'/pair' as never} asChild>
        <Pressable style={styles.button}>
          <Text style={styles.buttonText}>Begin pairing</Text>
        </Pressable>
      </Link>
      <Link href="/diagnostics" asChild>
        <Pressable hitSlop={10}><Text style={styles.link}>Run Wi-Fi diagnostics</Text></Pressable>
      </Link>
      {!auth.configured && (
        <Text style={styles.warning}>⚠ EXPO_PUBLIC_ENTRA_* env vars are not set yet.</Text>
      )}
      {device && <Text style={styles.deviceLine}>Device ID: <Text style={styles.mono}>{device.deviceId.slice(0, 8)}…</Text></Text>}
    </View>
  );
}

function Step({ n, label }: { n: number; label: string }) {
  return (
    <View style={styles.step}>
      <View style={styles.stepNum}><Text style={styles.stepNumText}>{n}</Text></View>
      <Text style={styles.stepLabel}>{label}</Text>
    </View>
  );
}

const styles = StyleSheet.create({
  container: { flex: 1, backgroundColor: '#0b3b66', padding: 24, justifyContent: 'center' },
  brand: { flexDirection: 'row', alignItems: 'center', gap: 12, marginBottom: 24 },
  logo: { width: 32, height: 32, backgroundColor: '#1670c0', borderRadius: 4 },
  appName: { fontSize: 22, fontWeight: '600', color: '#fff' },
  heading: { fontSize: 28, fontWeight: '600', color: '#fff', marginBottom: 8 },
  body: { fontSize: 14, color: '#cde0f3', marginBottom: 24, lineHeight: 20 },
  steps: { marginBottom: 24, gap: 10 },
  step: { flexDirection: 'row', alignItems: 'center', gap: 12 },
  stepNum: { width: 24, height: 24, borderRadius: 12, backgroundColor: '#1670c0', alignItems: 'center', justifyContent: 'center' },
  stepNumText: { color: '#fff', fontWeight: '700', fontSize: 13 },
  stepLabel: { color: '#cde0f3', fontSize: 13, flex: 1 },
  button: { backgroundColor: '#1670c0', paddingVertical: 14, borderRadius: 10, alignItems: 'center', marginBottom: 16 },
  buttonText: { color: '#fff', fontWeight: '600', fontSize: 16 },
  link: { color: '#cde0f3', textAlign: 'center', fontSize: 13 },
  warning: { color: '#fbbf24', textAlign: 'center', marginTop: 16, fontSize: 12 },
  deviceLine: { color: '#94a3b8', textAlign: 'center', marginTop: 8, fontSize: 11 },
  mono: { fontFamily: 'Courier' },
});
