# Database

The executable schema is [`001_initial.sql`](../ios/Data/SQLite/migrations/001_initial.sql). The package bundles migrations with its library.

`PRAGMA user_version` tracks schema revisions. A new database runs migration 1 inside an immediate transaction; failure rolls back. Newer schema versions fail visibly. Future migrations must be additive ordered files, with version advancement inside the same transaction. Reopening version 1 never reruns migration 1. WAL mode, a 3-second busy timeout and foreign-key enforcement are enabled.

| Table | Purpose |
| --- | --- |
| meals | Timestamp, recorded civil date, type, final totals, notes and audit times |
| meal_items | Original estimate and final grams/macros, confidence, parent foreign key |
| body_weight | One weigh-in per recorded civil date, kilograms |
| activity | Steps, energy, distance in metres, active minutes, heart rate, summary, stress/Body Battery and source |
| sleep | Start/end, stages and duration in minutes, score, resting HR and source |
| fasting | Start/end, duration, optional type and notes |
| ai_estimates | Normalized response, model, timestamp and correction audit |
| coach_notes | Date, category, summary and recommendations |
| settings | Single local row for targets, display units and weight goals |
| daily_metrics | Derived SQL view of final nutrition grouped by recorded date |

Activity/sleep/fasting/coach tables are prepared but have no ingestion UI yet. `daily_metrics` is a nutrition-only view in Milestone 1; activity, sleep, fasting and weight joins plus weekly summaries come later. Do not cache redundant metrics until their invalidation is designed.

Epoch timestamps are seconds since Unix epoch; civil dates are `YYYY-MM-DD`. IDs are UUID strings. Missing estimates and future provider metrics are null. Nutrition uses nonnegative REAL values; weight and targets require positive values. Repository validation rejects nonfinite numbers. Indexes support date and parent lookups. Save recalculates meal totals from final item fields in one transaction.

Exports are logical snapshots, not SQLite files. Version 1 exports table column keys with string values; absent/null SQL fields are omitted. The client must parse numeric fields explicitly. `exportedAt` is ISO 8601 UTC. All tables, including settings and AI audits, are included. Restore only accepts schema 1, validates identifiers and meal totals, enforces foreign keys, and replaces data atomically. Credentials and photos are never exported.
