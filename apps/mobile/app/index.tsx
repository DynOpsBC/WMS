import { Link, Stack, useRouter } from 'expo-router';
import { useEffect } from 'react';
import { Text, View, StyleSheet, Pressable } from 'react-native';
import { auth } from '@/lib/auth';
import { scanner } from '@/lib/scanner';

export default function SignInScreen() {
  const router = useRouter();

  useEffect(() => {
    scanner.start();
    return () => scanner.stop();
  }, []);

  async function onPress() {
    await auth.signIn();
    router.replace('/menu');
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
        Sign in with your Microsoft Entra ID work account. Entra ID PKCE wiring with{' '}
        <Text style={{ fontFamily: 'Courier' }}>expo-auth-session</Text> lands in M1.5.
      </Text>
      <Pressable style={styles.button} onPress={onPress}>
        <Text style={styles.buttonText}>Sign in with Microsoft</Text>
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
  buttonText: { color: '#fff', fontWeight: '600', fontSize: 16 },
  link: { color: '#cde0f3', textAlign: 'center', fontSize: 13 },
});
