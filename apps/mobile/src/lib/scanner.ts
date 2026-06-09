import { Platform, DeviceEventEmitter, NativeEventEmitter, NativeModules } from 'react-native';

export type ScannerSource = 'datawedge' | 'ble-hid' | 'camera' | 'manual';

export interface ScanEvent {
  data: string;
  symbology?: string;
  source: ScannerSource;
  timestamp: number;
}

type Listener = (e: ScanEvent) => void;

class ScannerService {
  private listeners = new Set<Listener>();
  private datawedgeSub: { remove: () => void } | null = null;

  start(): void {
    if (Platform.OS === 'android' && NativeModules.DataWedgeIntents) {
      const emitter = new NativeEventEmitter(NativeModules.DataWedgeIntents);
      this.datawedgeSub = emitter.addListener('datawedge_broadcast_intent', (intent: { 'com.symbol.datawedge.data_string'?: string; 'com.symbol.datawedge.label_type'?: string }) => {
        const data = intent['com.symbol.datawedge.data_string'];
        if (!data) return;
        this.emit({ data, symbology: intent['com.symbol.datawedge.label_type'], source: 'datawedge', timestamp: Date.now() });
      });
    }
    DeviceEventEmitter.addListener('bcwms.scan.hid', (data: string) => {
      this.emit({ data, source: 'ble-hid', timestamp: Date.now() });
    });
  }

  stop(): void {
    this.datawedgeSub?.remove();
    this.datawedgeSub = null;
    DeviceEventEmitter.removeAllListeners('bcwms.scan.hid');
  }

  on(listener: Listener): () => void {
    this.listeners.add(listener);
    return () => this.listeners.delete(listener);
  }

  emit(event: ScanEvent): void {
    for (const l of this.listeners) l(event);
  }

  /** Manually inject a scanned barcode (used by camera flow and unit tests). */
  manual(data: string, symbology?: string): void {
    this.emit({ data, symbology, source: 'manual', timestamp: Date.now() });
  }
}

export const scanner = new ScannerService();
