# Weight Coach

Personal, iPhone-first nutrition and weight journal. The iPhone SQLite database is authoritative. No server, cloud database, analytics, or third-party runtime dependencies.

## Implemented

Implemented: SwiftUI Today, manual multi-food meal logging and editing, dated meal history, daily weight logging and deletion, weight/protein/calorie charts (7/30/90/365/all days), 7-day calendar weight averages, logged-day weekly nutrition averages, SQLite migrations, persisted targets and unit preferences, JSON export and transactional restore.

Milestone 2 adds camera/photo-library input, an optional hidden-ingredient note, ChatGPT sign-in, account-specific model selection, image recognition with confidence and assumptions, editable review, and structured estimate/correction audits. Photos are held only in app memory and discarded on save, cancel, leaving the editor, or backgrounding.

Desktop sync/dashboard, coaching, Garmin, sleep/activity ingestion and fasting remain later milestones. No fake health data is seeded.

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

## Photo recognition

1. Settings → Connect ChatGPT → Continue with ChatGPT. Authorize plan usage, then choose an available model that supports images and structured output.
2. Today → Add Meal → Camera or Photo library.
3. Add context before sending, e.g. “Bread covered with vegetables; there is 10 g of butter underneath.”
4. Tap Estimate with AI. This transmits only the selected photo and note to OpenAI.
5. Review assumptions and confidence, edit foods/grams/calories/macros, then Save meal.

Butter, oil, sauces and other hidden ingredients are explicitly included in the prompt; unknown amounts remain estimates. Editing the note after recognition shows a reminder to analyze again. Reanalysis asks before replacing populated food entries. Manual logging remains usable without a connection.

The sign-in transport uses the officially documented HTTP loopback callback while the system authentication sheet is open. Build and deterministic auth tests pass; real-account sign-in and meal recognition still require validation on your iPhone. No production OAuth credentials or personal photos were used during development. See [integration details](docs/integrations.md).

## Backup

Settings → Export JSON backup writes versioned structured records through the system document picker. Restore explicitly replaces the journal and asks for confirmation before selecting a file; malformed or incompatible backups roll back. Export files contain personal health data. Keep them in your chosen private location. Automatic NAS backup is not implemented.

## Repository

The single source repository is [matijabogdanovic/di_je_ta](https://github.com/matijabogdanovic/di_je_ta). GitHub stores source code only; it is not a backend or datastore for the app. No public app hosting or custom domain is configured.
