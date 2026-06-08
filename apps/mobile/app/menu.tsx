import { Stack } from 'expo-router';
import { FlatList, Text, View, StyleSheet, Pressable } from 'react-native';

const menuItems = [
  { id: 'PURCH-RECEIVE', label: 'Purchase order receive', icon: 'inbox' },
  { id: 'LP-RECEIVE', label: 'License plate receive', icon: 'package' },
  { id: 'PUTAWAY', label: 'Put-away', icon: 'shelf' },
  { id: 'PICK', label: 'Pick', icon: 'pick' },
  { id: 'PACK', label: 'Pack into container', icon: 'box' },
  { id: 'CYCLE-COUNT', label: 'Cycle count', icon: 'counter' },
  { id: 'MOVEMENT', label: 'Inventory movement', icon: 'arrows' },
  { id: 'TRANSFER', label: 'Warehouse transfer', icon: 'transfer' },
];

export default function MenuScreen() {
  return (
    <View style={styles.container}>
      <Stack.Screen options={{ title: 'Main menu' }} />
      <FlatList
        data={menuItems}
        keyExtractor={(i) => i.id}
        renderItem={({ item }) => (
          <Pressable style={styles.row} onPress={() => {}}>
            <Text style={styles.rowText}>{item.label}</Text>
            <Text style={styles.rowFlow}>{item.id}</Text>
          </Pressable>
        )}
        ItemSeparatorComponent={() => <View style={styles.sep} />}
      />
      <Text style={styles.footer}>
        M0 scaffold · menu items are placeholders; M1 fetches from /wmsWorkerMenus.
      </Text>
    </View>
  );
}

const styles = StyleSheet.create({
  container: { flex: 1, backgroundColor: '#f8fafc' },
  row: { backgroundColor: '#fff', paddingHorizontal: 20, paddingVertical: 18, flexDirection: 'row', justifyContent: 'space-between', alignItems: 'center' },
  rowText: { fontSize: 16, color: '#0f172a', fontWeight: '500' },
  rowFlow: { fontSize: 12, fontFamily: 'Courier', color: '#64748b' },
  sep: { height: 1, backgroundColor: '#e2e8f0' },
  footer: { padding: 16, textAlign: 'center', color: '#64748b', fontSize: 12 },
});
