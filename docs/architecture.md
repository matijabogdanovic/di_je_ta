# Architecture and decisions

## Ownership

SQLite in iPhone Application Support is the sole authoritative store. SwiftUI reads an observable app model refreshed after repository mutations. `WeightCoachCore` is a local Swift package containing models, calculations, SQLite and backups, tested on macOS without the UI. Apple SQLite is linked through a tiny system module; no external persistence framework.

The connection and repositories are MainActor-confined. This keeps small personal datasets simple and prevents overlapping transactions. Larger imports should move behind an actor when measurements justify it. Database errors surface visibly; startup failure never silently resets the journal. Application Support directory uses complete file protection, inherited by new database files. Unlock the phone to access protected data. No credentials or image blobs are in the schema.

## Meals

Final fields determine all totals. Manual entries have null estimates and confidence. Later AI recognition fills immutable original estimates; editing final values retains estimates. Meals and items save in one transaction; deleting a meal cascades to its items and audit response. AI response history has its own table for normalized structured responses. AI calls are now explicitly initiated from the photo review flow; manual meal logging still needs no AI.

Milestone 2 holds resized, metadata-stripped image bytes only in memory, uses an ephemeral URLSession, and releases photo references and pending tasks on save/cancel/dismiss/background. Failed analysis allows an explicit retry while the editor remains active. The camera does not save to Photos; library originals are untouched. The note can describe hidden butter/oil/sauces and is sent only on Estimate with AI. The original normalized response and note are saved alongside corrections after confirmation.

## Trends

Weight is one record per civil day; repeated saves replace that day's value. A seven-day trend averages available daily records within today plus the previous six calendar days. Missing days remain absent. Charts calculate averages using all stored weights, including days just outside the selected chart range. Weekly nutrition averages use days with at least one meal; partial days are included and the UI explains that limitation. Neither a fasting duration nor estimated exercise energy increases the calorie target.

Current date grouping uses the device's calendar/time zone; SQL also stores the civil date recorded at write time. Travel can change UI grouping relative to that stored date. A future migration should add explicit logging time zones if travel consistency matters. Unit conversion occurs only at the presentation boundary; stored weight remains kilograms.

## Planned boundaries

`ios/Services/OpenAI`: the WeightCoachAI package contains the replaceable MealRecognizing and AccessTokenProviding protocols, streamed Responses transport, validated structured estimates and Keychain OAuth lifecycle. Native system authentication uses a temporary loopback listener. No provider-dependent fields in authoritative nutrition records. Coaching remains future work.

`ios/Services/Garmin`: independent importer, mapping provider records into activity/sleep and deduplicating by day/source. Garmin is not required for manual tracking.

`ios/Services/Fasting`: eating-schedule records and adherence correlations; no automatic calorie credits.

`ios/Networking` and `Features/DesktopSync`: temporary authenticated HTTP session while foregrounded only. Validate actual Tailscale inbound routing on an iPhone before choosing the transport. Do not assume a wildcard bind plus installed Tailscale isolates a listener. If private interface binding or verified private-source enforcement is unavailable, fail closed and document the blocker.

`dashboard`: read-only browser data views, IndexedDB snapshot and offline application assets in Milestone 3. No server is running in Milestone 1.

## Milestones

1. Offline journal, migration schema, targets, history and backups: implemented.
2. Photo analysis, ingredient note, editable recognition, memory-only images and documented OAuth route: implemented; real-device OAuth and real-account inference remain to be verified.
3. Verified private networking, foreground server and offline desktop dashboard.
4. Structured-context coaching, historical notes, weekly summaries and trend-calibrated guidance.
5. Verified Garmin import, activity/sleep and fasting tracking.
