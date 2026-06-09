import { Stack } from 'expo-router';
import { useState } from 'react';
import { View, Text, StyleSheet, Pressable, TextInput, Alert } from 'react-native';
import { printer } from '@/lib/printer';

export default function ShipFlow() {
  const [shipmentNo, setShipmentNo] = useState('');
  const [tracking, setTracking] = useState('');

  async function printLabel() {
    if (!shipmentNo || !tracking) {
      Alert.alert('Missing data', 'Scan shipment and tracking #');
      return;
    }
    const zpl = printer.shippingLabelZpl({ to: shipmentNo, tracking, weightLb: 2.4 });
    await printer.print('default', zpl);
    Alert.alert('Sent to printer', `Label for ${tracking} dispatched.`);
  }

  return (
    <View style={styles.container}>
      <Stack.Screen options={{ title: 'Ship & label' }} />
      <Text style={styles.label}>Shipment #</Text>
      <TextInput value={shipmentNo} onChangeText={setShipmentNo} style={styles.input} autoCapitalize="characters" />
      <Text style={styles.label}>Tracking #</Text>
      <TextInput value={tracking} onChangeText={setTracking} style={styles.input} autoCapitalize="characters" />
      <Pressable style={styles.button} onPress={printLabel}>
        <Text style={styles.buttonText}>Print Zebra label</Text>
      </Pressable>
    </View>
  );
}

const styles = StyleSheet.create({
  container: { flex: 1, backgroundColor: '#fff', padding: 16 },
  label: { fontSize: 13, color: '#64748b', marginBottom: 6, marginTop: 12 },
  input: { borderWidth: 2, borderColor: '#1670c0', borderRadius: 10, paddingHorizontal: 14, paddingVertical: 12, fontSize: 16 },
  button: { backgroundColor: '#1670c0', paddingVertical: 14, borderRadius: 10, alignItems: 'center', marginTop: 24 },
  buttonText: { color: '#fff', fontWeight: '600', fontSize: 16 },
});
