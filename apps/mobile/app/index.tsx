import { Link, Stack } from 'expo-router';
import { Text, View, StyleSheet, Pressable } from 'react-native';

export default function SignInScreen() {
  return (
    <View style={styles.container}>
      <Stack.Screen options={{ title: 'BCWMSApp' }} />
      <Text style={styles.heading}>Sign in</Text>
      <Text style={styles.body}>
        Sign in with your Microsoft Entra ID work account. Entra ID PKCE wiring lands in M1.
      </Text>
      <Link href="/menu" asChild>
        <Pressable style={styles.button}>
          <Text style={styles.buttonText}>Sign in with Microsoft</Text>
        </Pressable>
      </Link>
    </View>
  );
}

const styles = StyleSheet.create({
  container: { flex: 1, backgroundColor: '#fff', padding: 24, justifyContent: 'center' },
  heading: { fontSize: 28, fontWeight: '600', color: '#0b3b66', marginBottom: 8 },
  body: { fontSize: 15, color: '#475569', marginBottom: 24 },
  button: { backgroundColor: '#1670c0', paddingVertical: 14, borderRadius: 10, alignItems: 'center' },
  buttonText: { color: '#fff', fontWeight: '600', fontSize: 16 },
});
