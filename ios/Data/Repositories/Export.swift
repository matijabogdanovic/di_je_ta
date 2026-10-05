import Foundation

public struct LogicalExport: Codable, Sendable {
    public var schemaVersion: Int
    public var exportedAt: Date
    // SQL column names form the versioned wire format. Values are strings or null;
    // SQLite numeric conversion happens at the consumer boundary.
    public var meals: [[String:String]]
    public var mealItems: [[String:String]]
    public var weights: [[String:String]]
    public var activities: [[String:String]]
    public var sleep: [[String:String]]
    public var fasts: [[String:String]]
    public var coachNotes: [[String:String]]
    public var aiEstimates: [[String:String]]
    public var settings: [[String:String]]
}
@MainActor
extension TrackingStore {
    public func exportData() throws -> Data {
        let snapshot = try database.transaction {
            try LogicalExport(schemaVersion: 1, exportedAt: Date(), meals: database.query("SELECT * FROM meals ORDER BY id"), mealItems: database.query("SELECT * FROM meal_items ORDER BY id"), weights: database.query("SELECT * FROM body_weight ORDER BY id"), activities: database.query("SELECT * FROM activity ORDER BY id"), sleep: database.query("SELECT * FROM sleep ORDER BY id"), fasts: database.query("SELECT * FROM fasting ORDER BY id"), coachNotes: database.query("SELECT * FROM coach_notes ORDER BY id"), aiEstimates: database.query("SELECT * FROM ai_estimates ORDER BY id"), settings: database.query("SELECT * FROM settings ORDER BY id"))
        }
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601; encoder.outputFormatting = [.prettyPrinted,.sortedKeys]
        return try encoder.encode(snapshot)
    }
    // Restore only backups produced by this version; transactional replace, never raw DB copying.
    public func importData(_ data: Data) throws {
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        let backup = try decoder.decode(LogicalExport.self, from:data)
        guard backup.schemaVersion == 1 else { throw StoreError.unsupportedVersion }
        let tables: [(String,[[String:String]])] = [("meals",backup.meals),("meal_items",backup.mealItems),("body_weight",backup.weights),("activity",backup.activities),("sleep",backup.sleep),("fasting",backup.fasts),("coach_notes",backup.coachNotes),("ai_estimates",backup.aiEstimates),("settings",backup.settings)]
        guard backup.settings.count == 1 else { throw StoreError.invalid("Backup must contain settings.") }
        try database.transaction {
            for table in ["meal_items","ai_estimates","meals","body_weight","activity","sleep","fasting","coach_notes","settings"] { try database.execute("DELETE FROM \(table)") }
            for (table,rows) in tables {
                let columns = try database.query("PRAGMA table_info(\(table))").compactMap { $0["name"] }
                for row in rows {
                    if table != "settings" { guard let id = row["id"], UUID(uuidString:id) != nil else { throw StoreError.invalid("Invalid record identifier.") } }
                    if let mealID = row["meal_id"], UUID(uuidString:mealID) == nil { throw StoreError.invalid("Invalid meal identifier.") }
                    for key in ["timestamp","created_at","updated_at","weight_kg","final_grams","final_calories","final_protein_g","final_carbs_g","final_fat_g"] {
                        if let raw = row[key] { guard let value = Double(raw), value.isFinite else { throw StoreError.invalid("Invalid numeric value.") } }
                    }
                    guard Set(row.keys).isSubset(of:Set(columns)) else { throw StoreError.invalid("Unknown backup fields.") }
                    let placeholders = Array(repeating:"?",count:columns.count).joined(separator:",")
                    try database.execute("INSERT INTO \(table) (\(columns.joined(separator:","))) VALUES (\(placeholders))", columns.map { row[$0] })
                }
            }
            let restoredTargets = try targets()
            try save(restoredTargets)
            // Exercise decoding and validation before committing malformed backups.
            guard try meals().allSatisfy({ !$0.items.isEmpty && $0.items.allSatisfy(\.isValid) }), try weights().allSatisfy({ $0.weightKg.isFinite && $0.weightKg > 0 }) else { throw StoreError.invalid("Invalid backup records.") }
            for meal in try meals() {
                let rows = try database.query("SELECT * FROM meals WHERE id=?", [meal.id.uuidString])
                let row = rows[0]
                let totals = meal.totals
                for (column,value) in [("total_calories",totals.calories),("total_protein_g",totals.protein),("total_carbs_g",totals.carbs),("total_fat_g",totals.fat)] {
                    guard let raw = row[column], let stored = Double(raw), stored.isFinite, abs(stored-value) < 0.00001 else { throw StoreError.invalid("Meal totals do not match final food values.") }
                }
            }
        }
    }
}
