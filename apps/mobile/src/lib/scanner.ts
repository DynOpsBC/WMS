import { Platform } from 'react-native';
// Native event emitters are not implemented in react-native-web. Import them
// dynamically so the module still loads on the web target.
// eslint-disable-next-line @typescript-eslint/no-require-imports
const RN = require('react-native') as {
  DeviceEventEmitter?: {
    addListener: (e: string, cb: (data: string) => void) => { remove: () => void };
    removeAllListeners: (e: string) => void;
  };
  NativeEventEmitter?: new (m: unknown) => { addListener: (e: string, cb: (v: unknown) => void) => { remove: () => void } };
  NativeModules?: { DataWedgeIntents?: unknown };
};

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
    if (Platform.OS === 'android' && RN.NativeModules?.DataWedgeIntents && RN.NativeEventEmitter) {
      const emitter = new RN.NativeEventEmitter(RN.NativeModules.DataWedgeIntents);
      this.datawedgeSub = emitter.addListener('datawedge_broadcast_intent', (raw: unknown) => {
        const intent = raw as { 'com.symbol.datawedge.data_string'?: string; 'com.symbol.datawedge.label_type'?: string };
        const data = intent['com.symbol.datawedge.data_string'];
        if (!data) return;
        this.emit({ data, symbology: intent['com.symbol.datawedge.label_type'], source: 'datawedge', timestamp: Date.now() });
      });
    }
    RN.DeviceEventEmitter?.addListener('bcwms.scan.hid', (data: string) => {
      this.emit({ data, source: 'ble-hid', timestamp: Date.now() });
    });
  }

  stop(): void {
    this.datawedgeSub?.remove();
    this.datawedgeSub = null;
    RN.DeviceEventEmitter?.removeAllListeners('bcwms.scan.hid');
  }

  on(listener: Listener): () => void {
    this.listeners.add(listener);
    return () => { this.listeners.delete(listener); };
  }

  emit(event: ScanEvent): void {
    for (const l of this.listeners) l(event);
  }

  manual(data: string, symbology?: string): void {
    this.emit({ data, symbology, source: 'manual', timestamp: Date.now() });
  }
}

export const scanner = new ScannerService();
