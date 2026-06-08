# BCWMSApp — Mobile (React Native + Expo)

Scanner-driven warehouse worker UI targeting **Zebra** (TC-series via Datawedge keyboard-wedge) and **Honeywell** (CT45 via Bluetooth HID / SDK).

## Run

```bash
pnpm install                # from repo root
pnpm -C apps/mobile start
```

Press `i` for iOS simulator, `a` for Android emulator, or scan the QR with Expo Go.

## Hardware integration

- **Zebra Datawedge**: an intent filter on `com.symbol.datawedge.api.RESULT_ACTION` is registered in `app.json`. M1 hooks `expo-intent-launcher` listeners to deliver scans into the active flow.
- **Honeywell CT45**: pair the integrated scanner as BLE HID — barcodes are delivered as keyboard input by default. M1 adds a dedicated `Scanner` service that distinguishes Datawedge intents vs. HID vs. vision-camera (`react-native-vision-camera`).
