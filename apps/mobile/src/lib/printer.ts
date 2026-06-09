/**
 * Zebra ZPL printer abstraction. Production-shape only — the actual native
 * bridge to Bluetooth/USB Zebra Link-OS lives in a tiny native module
 * delivered as a custom dev-client (M6 ships that native module).
 */

import { NativeModules } from 'react-native';

export interface ZebraPrinter {
  id: string;
  name: string;
  connection: 'bluetooth' | 'usb' | 'tcp';
}

export class PrinterService {
  async listDevices(): Promise<ZebraPrinter[]> {
    const native = NativeModules['ZebraLinkOs'] as { listDevices?: () => Promise<ZebraPrinter[]> } | undefined;
    if (native?.listDevices) return native.listDevices();
    return [];
  }

  async print(printerId: string, zpl: string): Promise<void> {
    const native = NativeModules['ZebraLinkOs'] as { print?: (id: string, zpl: string) => Promise<void> } | undefined;
    if (native?.print) {
      await native.print(printerId, zpl);
      return;
    }
    console.warn('[printer] no native bridge — would print', zpl.slice(0, 80));
  }

  /** Generate a basic shipping-label ZPL (placeholder template). */
  shippingLabelZpl(opts: { to: string; tracking: string; weightLb: number }): string {
    return `^XA
^FO40,40^A0N,40,40^FDShip to:^FS
^FO40,90^A0N,28,28^FD${opts.to}^FS
^FO40,170^A0N,28,28^FDTracking: ${opts.tracking}^FS
^FO40,210^BCN,80,Y,N,N^FD${opts.tracking}^FS
^FO40,330^A0N,24,24^FDWeight: ${opts.weightLb} lb^FS
^XZ`;
  }
}

export const printer = new PrinterService();
