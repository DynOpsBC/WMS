import { Link, Stack, useRouter } from 'expo-router';
import { useEffect, useState } from 'react';
import { Text, View, StyleSheet, Pressable, ActivityIndicator, Alert } from 'react-native';
import { auth } from '@/lib/auth';
import { scanner } from '@/lib/scanner';
import { startRuntime } from '@/lib/runtime';

export default function SignInScreen() {
  const router = useRouter();
  const [busy, setBusy] = useState(false);

  useEffect(() => {
    scanner.start();
    // Resume an existing session without forcing re-auth.
    if (auth.loadSession()) {
      startRuntime();
      router.replace('/menu');
    }
    return () => scanner.stop();
  }, [router]);

  async function onPress() {
    setBusy(true);
    try {
      await auth.signIn();
      startRuntime();
      router.replace('/menu');
    } catch (e) {
      Alert.alert('Sign-in failed', e instanceof Error ? e.message : String(e));
    } finally {
      setBusy(false);
    }
  }

  return (
    <View style={styles.container}>
      <Stack.Screen options={{ title: 'BCWMSApp', headerShown: false }} />
      <View style={styles.brand}>
        <View style={styles.logo} />
        <Text style={styles.appName}>BCWMSApp</Text>
      </View>
      <Text style={styles.heading}>Sign in</Text>
      <Text style={styles.body}>
        Sign in with your Microsoft Entra ID work account.
        {!auth.configured ? ' ⚠ Entra ID env vars are not set yet.' : ''}
      </Text>
      <Pressable style={[styles.button, busy && styles.buttonDisabled]} onPress={onPress} disabled={busy}>
        {busy ? <ActivityIndicator color="#fff" /> : <Text style={styles.buttonText}>Sign in with Microsoft</Text>}
      </Pressable>
      <Link href="/diagnostics" asChild>
        <Pressable hitSlop={10}><Text style={styles.link}>Run Wi-Fi diagnostics</Text></Pressable>
      </Link>
    </View>
  );
}

const styles = StyleSheet.create({
  container: { flex: 1, backgroundColor: '#0b3b66', padding: 24, justifyContent: 'center' },
  brand: { flexDirection: 'row', alignItems: 'center', gap: 12, marginBottom: 32 },
  logo: { width: 32, height: 32, backgroundColor: '#1670c0', borderRadius: 4 },
  appName: { fontSize: 22, fontWeight: '600', color: '#fff' },
  heading: { fontSize: 28, fontWeight: '600', color: '#fff', marginBottom: 8 },
  body: { fontSize: 14, color: '#cde0f3', marginBottom: 24, lineHeight: 20 },
  button: { backgroundColor: '#1670c0', paddingVertical: 14, borderRadius: 10, alignItems: 'center', marginBottom: 16 },
  buttonDisabled: { opacity: 0.6 },
  buttonText: { color: '#fff', fontWeight: '600', fontSize: 16 },
  link: { color: '#cde0f3', textAlign: 'center', fontSize: 13 },
});
