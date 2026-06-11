import { Link, Stack, useRouter } from 'expo-router';
import { useEffect, useState } from 'react';
import { FlatList, Text, View, StyleSheet, Pressable } from 'react-native';
import { useSync } from '@/hooks/useSync';
import { bcClient } from '@/lib/runtime';
import { loadDevice } from '@/lib/device';

interface MenuRow {
  id: string;
  flowId: string;
  label: string;
}

const SYNC_COLOR: Record<string, string> = {
  idle: '#34d399',
  syncing: '#fbbf24',
  offline: '#94a3b8',
  error: '#f87171',
};

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
  const sync = useSync();
  const router = useRouter();
  const device = loadDevice();

  // If the device was revoked while the menu was open, bounce back to pairing.
  useEffect(() => {
    if (device?.status === 'revoked') router.replace('/');
  }, [device?.status, router]);

  useEffect(() => {
    let cancelled = false;
    (async () => {
      try {
        const menu = await bcClient.getWorkerMenu('MAIN');
        if (!cancelled && menu?.menuItems?.length) {
          setItems(
            menu.menuItems
              .filter((m) => m.itemType === 'Flow')
              .map((m) => ({ id: String(m.lineNumber), flowId: m.flowId, label: m.description })),
          );
        }
      } catch {
        /* offline → keep FALLBACK */
      }
    })();
    return () => { cancelled = true; };
  }, []);

  return (
    <View style={styles.container}>
      <Stack.Screen options={{ title: 'Main menu' }} />
      <View style={styles.statusBar}>
        <View style={styles.deviceCol}>
          <Text style={styles.deviceName}>{device?.deviceName ?? 'Unpaired device'}</Text>
          <Text style={styles.deviceMeta}>
            {device?.defaultWarehouse ?? '—'} · paired by {device?.pairedBy ?? '—'}
          </Text>
        </View>
        <View style={styles.syncWrap}>
          <View style={[styles.syncDot, { backgroundColor: SYNC_COLOR[sync.status] ?? '#94a3b8' }]} />
          <Text style={styles.statusText}>
            {sync.status}{sync.pending > 0 ? ` · ${sync.pending}` : ''}
          </Text>
        </View>
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
  statusBar: { flexDirection: 'row', justifyContent: 'space-between', alignItems: 'center', backgroundColor: '#0b3b66', paddingHorizontal: 16, paddingVertical: 10, gap: 8 },
  deviceCol: { flex: 1 },
  deviceName: { color: '#fff', fontSize: 13, fontWeight: '600' },
  deviceMeta: { color: '#cde0f3', fontSize: 10, marginTop: 1 },
  statusText: { color: '#cde0f3', fontSize: 12 },
  syncWrap: { flexDirection: 'row', alignItems: 'center', gap: 6 },
  syncDot: { width: 8, height: 8, borderRadius: 4 },
  statusLink: { color: '#fff', fontWeight: '600', fontSize: 12 },
  row: { backgroundColor: '#fff', paddingHorizontal: 20, paddingVertical: 18, flexDirection: 'row', justifyContent: 'space-between', alignItems: 'center' },
  rowText: { fontSize: 16, color: '#0f172a', fontWeight: '500' },
  rowFlow: { fontSize: 11, fontFamily: 'Courier', color: '#64748b' },
  sep: { height: 1, backgroundColor: '#e2e8f0' },
});
