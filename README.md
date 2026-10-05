# Weight Coach

Personal, iPhone-first nutrition and weight journal. The iPhone SQLite database is authoritative. No server, cloud database, analytics, or third-party runtime dependencies.

## Milestone 1

Implemented: SwiftUI Today, manual multi-food meal logging and editing, dated meal history, daily weight logging and deletion, weight/protein/calorie charts (7/30/90/365/all days), 7-day calendar weight averages, logged-day weekly nutrition averages, SQLite migrations, persisted targets and unit preferences, JSON export and transactional restore.

AI, photos, desktop sync/dashboard, Garmin, sleep/activity ingestion and fasting are deliberately scheduled for later milestones. Connections are visibly labeled as unavailable. No fake health data is seeded.

## Run on iPhone

1. Open `ios/WeightCoach.xcodeproj` in Xcode 26 or newer with Swift 6.2+.
2. Select the WeightCoach scheme and your iPhone or simulator (iOS 17+).
3. For a physical iPhone, choose your own signing team and unique bundle identifier under Signing & Capabilities.
4. Run. Start with Settings to configure targets, then log meals and weight.

The app links the local Swift package at the repository root. No project generator or package downloads are needed. Personal device provisioning and any Apple developer account costs are separate from hosting; there is no recurring hosting service.

## Verify

```sh
swift test
xcodebuild -project ios/WeightCoach.xcodeproj -scheme WeightCoach \
  -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath /tmp/weight-coach-derived CODE_SIGNING_ALLOWED=NO build
```

Restricted environments can run core tests with:

```sh
CLANG_MODULE_CACHE_PATH=/tmp/weight-coach-clang \
SWIFTPM_MODULECACHE_OVERRIDE=/tmp/weight-coach-modules \
swift test --disable-sandbox --scratch-path /tmp/weight-coach-build
```

See [architecture](docs/architecture.md), [database](docs/database.md), [sync protocol](docs/sync-protocol.md), and [integration research](docs/integrations.md).

## Backup

Settings → Export JSON backup writes versioned structured records through the system document picker. Restore explicitly replaces the journal and asks for confirmation before selecting a file; malformed or incompatible backups roll back. Export files contain personal health data. Keep them in your chosen private location. Automatic NAS backup is not implemented.

## Repository

The single source repository is [matijabogdanovic/di_je_ta](https://github.com/matijabogdanovic/di_je_ta). GitHub stores source code only; it is not a backend or datastore for the app. No public app hosting or custom domain is configured.
