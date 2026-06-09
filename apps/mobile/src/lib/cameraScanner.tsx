import { useCallback, useState } from 'react';
import { View, Text, Pressable, StyleSheet, Modal, FlatList } from 'react-native';
import { scanner } from './scanner';

/**
 * Multi-barcode camera scanner (WMA v4 parity).
 *
 * Open the camera, run vision-camera's code scanner on every frame, accumulate
 * all detected barcodes for ~500ms, then surface a chooser so the worker
 * picks which code to register. Falls back to single-pick on tap.
 *
 * Visible UI is fully wired; the camera frame producer + vision-camera plugin
 * land in M8.5 as a tiny native module (camera-frame-processor).
 */

interface DetectedCode {
  data: string;
  symbology: string;
}

interface Props {
  visible: boolean;
  onPick: (code: DetectedCode) => void;
  onClose: () => void;
}

export function MultiBarcodeScanner({ visible, onPick, onClose }: Props) {
  const [detected, setDetected] = useState<DetectedCode[]>([]);

  const onFrame = useCallback((codes: DetectedCode[]) => {
    setDetected((prev) => {
      const merged = [...prev];
      for (const c of codes) {
        if (!merged.find((m) => m.data === c.data)) merged.push(c);
      }
      return merged;
    });
  }, []);

  function pick(c: DetectedCode) {
    onPick(c);
    scanner.manual(c.data, c.symbology);
    setDetected([]);
    onClose();
  }

  // useEffect would attach vision-camera processor here. Demo: seed two codes.
  // (Removed for runtime correctness — real wiring lives in M8.5.)
  void onFrame;

  return (
    <Modal visible={visible} animationType="slide" onRequestClose={onClose}>
      <View style={styles.container}>
        <View style={styles.viewfinder}>
          <Text style={styles.viewfinderText}>Camera preview</Text>
          <Text style={styles.hint}>Multi-barcode capture. Tap a code to register.</Text>
        </View>
        <FlatList
          data={detected}
          keyExtractor={(c) => c.data}
          ListEmptyComponent={<Text style={styles.empty}>No codes detected yet.</Text>}
          renderItem={({ item }) => (
            <Pressable style={styles.code} onPress={() => pick(item)}>
              <Text style={styles.codeData}>{item.data}</Text>
              <Text style={styles.codeSym}>{item.symbology}</Text>
            </Pressable>
          )}
        />
        <Pressable style={styles.close} onPress={onClose}>
          <Text style={styles.closeText}>Close</Text>
        </Pressable>
      </View>
    </Modal>
  );
}

const styles = StyleSheet.create({
  container: { flex: 1, backgroundColor: '#0f172a' },
  viewfinder: { aspectRatio: 4 / 3, backgroundColor: '#1e293b', alignItems: 'center', justifyContent: 'center' },
  viewfinderText: { color: '#cbd5e1', fontSize: 16 },
  hint: { color: '#94a3b8', fontSize: 12, marginTop: 6 },
  empty: { color: '#94a3b8', textAlign: 'center', padding: 24 },
  code: { padding: 16, borderBottomColor: '#334155', borderBottomWidth: 1, flexDirection: 'row', justifyContent: 'space-between' },
  codeData: { color: '#fff', fontFamily: 'Courier', fontSize: 16 },
  codeSym: { color: '#94a3b8', fontSize: 12 },
  close: { padding: 18, alignItems: 'center', backgroundColor: '#1670c0' },
  closeText: { color: '#fff', fontWeight: '600' },
});
