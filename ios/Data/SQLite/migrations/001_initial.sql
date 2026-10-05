CREATE TABLE meals (
 id TEXT PRIMARY KEY, date TEXT NOT NULL, timestamp REAL NOT NULL, meal_type TEXT NOT NULL,
 total_calories REAL NOT NULL CHECK(total_calories>=0), total_protein_g REAL NOT NULL CHECK(total_protein_g>=0),
 total_carbs_g REAL NOT NULL CHECK(total_carbs_g>=0), total_fat_g REAL NOT NULL CHECK(total_fat_g>=0),
 notes TEXT NOT NULL, created_at REAL NOT NULL, updated_at REAL NOT NULL);
CREATE INDEX meals_date ON meals(date);
CREATE TABLE meal_items (
 id TEXT PRIMARY KEY, meal_id TEXT NOT NULL REFERENCES meals(id) ON DELETE CASCADE, food_name TEXT NOT NULL,
 estimated_grams REAL, final_grams REAL NOT NULL CHECK(final_grams>=0),
 estimated_calories REAL, final_calories REAL NOT NULL CHECK(final_calories>=0),
 estimated_protein_g REAL, final_protein_g REAL NOT NULL CHECK(final_protein_g>=0),
 estimated_carbs_g REAL, final_carbs_g REAL NOT NULL CHECK(final_carbs_g>=0),
 estimated_fat_g REAL, final_fat_g REAL NOT NULL CHECK(final_fat_g>=0),
 confidence REAL CHECK(confidence BETWEEN 0 AND 1), created_at REAL NOT NULL);
CREATE INDEX meal_items_parent ON meal_items(meal_id);
CREATE TABLE body_weight (id TEXT PRIMARY KEY, date TEXT NOT NULL UNIQUE, timestamp REAL NOT NULL, weight_kg REAL NOT NULL CHECK(weight_kg>0), created_at REAL NOT NULL);
CREATE TABLE activity (id TEXT PRIMARY KEY, date TEXT NOT NULL UNIQUE, steps INTEGER, active_calories REAL, total_calories REAL, distance_m REAL, active_minutes REAL, resting_hr REAL, average_hr REAL, training_summary TEXT, body_battery REAL, stress REAL, source TEXT);
CREATE TABLE sleep (id TEXT PRIMARY KEY, date TEXT NOT NULL UNIQUE, sleep_start REAL, sleep_end REAL, duration_minutes REAL, deep_minutes REAL, light_minutes REAL, rem_minutes REAL, awake_minutes REAL, sleep_score REAL, resting_hr REAL, source TEXT);
CREATE TABLE fasting (id TEXT PRIMARY KEY, start_time REAL NOT NULL, end_time REAL, duration_minutes REAL, fasting_type TEXT, notes TEXT);
CREATE TABLE ai_estimates (id TEXT PRIMARY KEY, meal_id TEXT NOT NULL REFERENCES meals(id) ON DELETE CASCADE, normalized_response TEXT NOT NULL, model_name TEXT NOT NULL, timestamp REAL NOT NULL, user_correction_delta TEXT);
CREATE TABLE coach_notes (id TEXT PRIMARY KEY, date TEXT NOT NULL, category TEXT NOT NULL, summary TEXT NOT NULL, recommendations TEXT NOT NULL);
CREATE TABLE settings (id INTEGER PRIMARY KEY CHECK(id=1), calorie_target REAL NOT NULL CHECK(calorie_target>0), protein_target REAL NOT NULL CHECK(protein_target>0), target_weight REAL NOT NULL CHECK(target_weight>0), loss_rate REAL NOT NULL CHECK(loss_rate>=0), units TEXT NOT NULL CHECK(units IN ('metric','imperial')));
INSERT INTO settings VALUES (1,2000,140,80,0.5,'metric');
CREATE VIEW daily_metrics AS SELECT date, SUM(total_calories) AS calories, SUM(total_protein_g) AS protein_g, SUM(total_carbs_g) AS carbs_g, SUM(total_fat_g) AS fat_g FROM meals GROUP BY date;
