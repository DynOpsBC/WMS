import { Link, Stack } from 'expo-router';
import { useEffect, useState } from 'react';
import { FlatList, Text, View, StyleSheet, Pressable } from 'react-native';
import { auth } from '@/lib/auth';
import { OfflineQueue } from '@/lib/offlineQueue';

interface MenuRow {
  id: string;
  flowId: string;
  label: string;
}

const FALLBACK: MenuRow[] = [
  { id: '1', flowId: 'PURCH-RECEIVE', label: 'Purchase order receive' },
  { id: '2', flowId: 'LP-RECEIVE', label: 'License plate receive' },
  { id: '3', flowId: 'PUTAWAY', label: 'Put-away' },
  { id: '4', flowId: 'PICK', label: 'Pick' },
  { id: '5', flowId: 'PALLET-PICK', label: 'Pallet pick (single LP)' },
  { id: '6', flowId: 'PACK', label: 'Pack into container' },
  { id: '7', flowId: 'CYCLE-COUNT', label: 'Cycle count' },
  { id: '8', flowId: 'MOVEMENT', label: 'Inventory movement' },
  { id: '9', flowId: 'TRANSFER', label: 'Warehouse transfer' },
  { id: '10', flowId: 'RAF', label: 'Report as finished' },
];

const FLOW_HREF: Record<string, string> = {
  'PURCH-RECEIVE': '/flows/purchase-receive',
  'LP-RECEIVE': '/flows/lp-receive',
  'PUTAWAY': '/flows/putaway',
  'PICK': '/flows/pick',
  'PALLET-PICK': '/flows/pallet-pick',
  'PACK': '/flows/pack',
  'CYCLE-COUNT': '/flows/cycle-count',
  'MOVEMENT': '/flows/movement',
  'TRANSFER': '/flows/transfer',
  'RAF': '/flows/raf',
};

export default function MenuScreen() {
  const [items, setItems] = useState<MenuRow[]>(FALLBACK);
  const [pending, setPending] = useState(OfflineQueue.size());

  useEffect(() => {
    // M1.5: fetch from /wmsWorkerMenus and render dynamically.
    const i = setInterval(() => setPending(OfflineQueue.size()), 2000);
    return () => clearInterval(i);
  }, []);

  const session = auth.loadSession();

  return (
    <View style={styles.container}>
      <Stack.Screen options={{ title: 'Main menu' }} />
      <View style={styles.statusBar}>
        <Text style={styles.statusText}>Worker: {session?.name ?? '—'}</Text>
        <Text style={styles.statusText}>Queue: {pending}</Text>
        <Link href="/diagnostics" asChild>
          <Pressable hitSlop={10}><Text style={styles.statusLink}>Wi-Fi</Text></Pressable>
        </Link>
      </View>
      <FlatList
        data={items}
        keyExtractor={(i) => i.id}
        renderItem={({ item }) => {
          const href = FLOW_HREF[item.flowId];
          const inner = (
            <View style={styles.row}>
              <Text style={styles.rowText}>{item.label}</Text>
              <Text style={styles.rowFlow}>{item.flowId}</Text>
            </View>
          );
          return href ? <Link href={href as never} asChild>{inner}</Link> : inner;
        }}
        ItemSeparatorComponent={() => <View style={styles.sep} />}
      />
    </View>
  );
}

const styles = StyleSheet.create({
  container: { flex: 1, backgroundColor: '#f8fafc' },
  statusBar: { flexDirection: 'row', justifyContent: 'space-between', backgroundColor: '#0b3b66', paddingHorizontal: 16, paddingVertical: 10 },
  statusText: { color: '#cde0f3', fontSize: 12 },
  statusLink: { color: '#fff', fontWeight: '600', fontSize: 12 },
  row: { backgroundColor: '#fff', paddingHorizontal: 20, paddingVertical: 18, flexDirection: 'row', justifyContent: 'space-between', alignItems: 'center' },
  rowText: { fontSize: 16, color: '#0f172a', fontWeight: '500' },
  rowFlow: { fontSize: 11, fontFamily: 'Courier', color: '#64748b' },
  sep: { height: 1, backgroundColor: '#e2e8f0' },
});
