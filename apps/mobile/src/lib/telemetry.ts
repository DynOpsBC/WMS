/**
 * Telemetry abstraction. Real wiring uses
 * @microsoft/applicationinsights-react-native + Application Insights connection string.
 * Off by default in dev; opt-in via EXPO_PUBLIC_APPINSIGHTS_CONN.
 */

interface Event {
  name: string;
  properties?: Record<string, string | number | boolean>;
}

class TelemetryService {
  private enabled = !!process.env.EXPO_PUBLIC_APPINSIGHTS_CONN;
  private queue: Event[] = [];

  track(name: string, properties?: Event['properties']): void {
    if (!this.enabled) {
      if (__DEV__) console.log('[telemetry]', name, properties ?? {});
      return;
    }
    this.queue.push({ name, properties });
    if (this.queue.length >= 20) this.flush();
  }

  flush(): void {
    if (this.queue.length === 0) return;
    // TODO[m8.5]: POST to App Insights ingestion endpoint.
    this.queue = [];
  }
}

export const telemetry = new TelemetryService();
