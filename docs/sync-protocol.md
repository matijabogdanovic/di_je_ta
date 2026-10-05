# Desktop sync protocol (Milestone 3 design)

No HTTP listener or desktop sync is implemented in Milestone 1.

The iPhone begins a foreground-only session on explicit Desktop Sync activation. Generate at least 256 bits of cryptographic randomness for a token, require it on all data routes, and invalidate it when stopped or the app leaves the foreground. Avoid logging it. No background modes, UPnP, public bind assumption, Tailscale Funnel, hosting vendor or domain.

Tailscale installation alone does not prove an embedded iOS HTTP listener accepts private inbound traffic. Verify this on actual devices and verify private interface binding/source enforcement before enabling the listener. If impossible with the supported iOS networking model, stop and resolve architecture before claiming compliance. Never substitute a publicly reachable listener.

Planned routes: `GET /` serves dashboard shell; `GET /api/export` returns a full versioned snapshot; `GET /api/dashboard`, `/api/meals`, `/api/weight`, `/api/activity`, `/api/sleep`, `/api/fasting` return derived or filtered read-only views. Reject mutation methods. No SQLite download endpoint. Return 401 for missing/expired tokens, no permissive CORS, no-store for API responses and a restrictive CSP for shell assets.

Prefer a URL fragment for the bootstrap token, consumed and removed from browser history immediately, then an Authorization bearer header held only in memory. The user's example query token is convenient but can leak through history and logs; do not persist credentials in IndexedDB or localStorage. Each activation needs a fresh token. Asset versioning and phone hostname/address changes need a deliberate browser-origin strategy.

IndexedDB stores one validated full snapshot in an atomic transaction. Render the cache immediately; on successful authenticated fetch replace it and update Last synced. Network/auth errors leave cache intact and show offline/expired status. Reject unsupported schema versions without replacing cache. Version 1 numeric values are explicitly parsed from strings. Read-only everywhere: no write controls or requests. Cache dashboard assets for actual offline reload; IndexedDB data alone does not make the HTML available after the phone stops. Service-worker secure-context constraints over private HTTP must be solved before promising offline reload (a saved local dashboard bundle is an alternative).

Browser caches contain health data and should have a clear-cache action. V1 intentionally has no conflict resolution, uploads or bidirectional synchronization.
