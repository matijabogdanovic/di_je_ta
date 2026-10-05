import Foundation

public struct Targets: Codable, Equatable, Sendable {
    public var calories: Double = 2000
    public var protein: Double = 140
    public var weight: Double = 80
    public var lossRate: Double = 0.5
    public var units: String = "metric"
    public init() {}
}
@MainActor
public final class TrackingStore {
    public let database: Database
    public init(path: String) throws { database = try Database(path: path) }
    private func day(_ date: Date) -> String {
        let c = Calendar.current.dateComponents([.year,.month,.day], from: date)
        return String(format: "%04d-%02d-%02d", c.year!, c.month!, c.day!)
    }
    public func save(_ meal: Meal, audit: MealEstimateAudit? = nil) throws {
        guard !meal.items.isEmpty, meal.items.allSatisfy(\.isValid), meal.totals.isValid,
              Set(meal.items.map(\.id)).count == meal.items.count,
              ["Breakfast","Lunch","Dinner","Snack"].contains(meal.mealType) else { throw StoreError.invalid("Add valid food amounts and nonnegative nutrition values.") }
        let n = meal.totals
        try database.transaction {
            try database.execute("INSERT INTO meals VALUES (?,?,?,?,?,?,?,?,?,?,?) ON CONFLICT(id) DO UPDATE SET date=excluded.date,timestamp=excluded.timestamp,meal_type=excluded.meal_type,total_calories=excluded.total_calories,total_protein_g=excluded.total_protein_g,total_carbs_g=excluded.total_carbs_g,total_fat_g=excluded.total_fat_g,notes=excluded.notes,updated_at=excluded.updated_at", [meal.id.uuidString,day(meal.timestamp),String(meal.timestamp.timeIntervalSince1970),meal.mealType,String(n.calories),String(n.protein),String(n.carbs),String(n.fat),meal.notes,String(meal.createdAt.timeIntervalSince1970),String(Date().timeIntervalSince1970)])
            try database.execute("DELETE FROM meal_items WHERE meal_id=?", [meal.id.uuidString])
            for i in meal.items {
                try database.execute("INSERT INTO meal_items VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)", [i.id.uuidString,meal.id.uuidString,i.foodName,i.estimatedGrams.map(String.init(describing:)),String(i.finalGrams),i.estimate.map { String($0.calories) },String(i.final.calories),i.estimate.map { String($0.protein) },String(i.final.protein),i.estimate.map { String($0.carbs) },String(i.final.carbs),i.estimate.map { String($0.fat) },String(i.final.fat),i.confidence.map(String.init(describing:)),String(i.createdAt.timeIntervalSince1970)])
            }
            if let audit {
                guard audit.originalTotals.isValid, !audit.modelName.isEmpty else { throw StoreError.invalid("Invalid original estimate.") }
                let encoded = try JSONEncoder().encode(audit)
                try database.execute("INSERT INTO ai_estimates VALUES (?,?,?,?,?,?)", [UUID().uuidString,meal.id.uuidString,String(decoding:encoded,as:UTF8.self),audit.modelName,String(audit.timestamp.timeIntervalSince1970),nil])
            }
            for row in try database.query("SELECT id,normalized_response FROM ai_estimates WHERE meal_id=?", [meal.id.uuidString]) {
                guard let raw = row["normalized_response"], let original = try? JSONDecoder().decode(MealEstimateAudit.self,from:Data(raw.utf8)) else { continue }
                let a = original.originalTotals
                let delta = Nutrition(calories:n.calories-a.calories,protein:n.protein-a.protein,carbs:n.carbs-a.carbs,fat:n.fat-a.fat)
                let data = try JSONEncoder().encode(delta)
                try database.execute("UPDATE ai_estimates SET user_correction_delta=? WHERE id=?",[String(decoding:data,as:UTF8.self),row["id"]])
            }
        }
    }
    public func meals() throws -> [Meal] {
        try database.query("SELECT * FROM meals ORDER BY timestamp DESC").map { r in
            let rows = try database.query("SELECT * FROM meal_items WHERE meal_id=? ORDER BY rowid", [r["id"]!])
            let items = rows.map { i -> MealItem in
                var item = MealItem(foodName: i["food_name"]!, finalGrams: number(i,"final_grams"), final: nutrition(i,prefix:"final_"), estimatedGrams: i["estimated_grams"].flatMap(Double.init), estimate: i["estimated_calories"] == nil ? nil : nutrition(i,prefix:"estimated_"), confidence: i["confidence"].flatMap(Double.init))
                item.id = UUID(uuidString:i["id"]!)!; item.createdAt = date(i,"created_at"); return item
            }
            var meal = Meal(timestamp: date(r,"timestamp"), mealType: r["meal_type"]!, notes: r["notes"]!, items: items)
            meal.id = UUID(uuidString:r["id"]!)!; meal.createdAt = date(r,"created_at"); meal.updatedAt = date(r,"updated_at"); return meal
        }
    }
    public func deleteMeal(_ id: UUID) throws { try database.execute("DELETE FROM meals WHERE id=?", [id.uuidString]) }
    public func save(_ weight: WeighIn) throws {
        guard weight.weightKg.isFinite, weight.weightKg > 0 else { throw StoreError.invalid("Enter a positive body weight.") }
        try database.execute("INSERT INTO body_weight VALUES (?,?,?,?,?) ON CONFLICT(date) DO UPDATE SET weight_kg=excluded.weight_kg,timestamp=excluded.timestamp", [weight.id.uuidString,day(weight.date),String(weight.date.timeIntervalSince1970),String(weight.weightKg),String(weight.createdAt.timeIntervalSince1970)])
    }
    public func weights() throws -> [WeighIn] {
        try database.query("SELECT * FROM body_weight ORDER BY timestamp").map { r in
            var w = WeighIn(date: date(r,"timestamp"), weightKg:number(r,"weight_kg")); w.id = UUID(uuidString:r["id"]!)!; w.createdAt = date(r,"created_at"); return w
        }
    }
    public func deleteWeight(_ id: UUID) throws { try database.execute("DELETE FROM body_weight WHERE id=?",[id.uuidString]) }
    public func targets() throws -> Targets {
        let r = try database.query("SELECT * FROM settings")[0]
        var t = Targets(); t.calories = number(r,"calorie_target"); t.protein = number(r,"protein_target"); t.weight = number(r,"target_weight"); t.lossRate = number(r,"loss_rate"); t.units = r["units"]!; return t
    }
    public func save(_ t: Targets) throws {
        guard [t.calories,t.protein,t.weight].allSatisfy({ $0.isFinite && $0 > 0 }), t.lossRate.isFinite, t.lossRate >= 0, ["metric","imperial"].contains(t.units) else { throw StoreError.invalid("Enter valid targets.") }
        try database.execute("UPDATE settings SET calorie_target=?,protein_target=?,target_weight=?,loss_rate=?,units=? WHERE id=1", [String(t.calories),String(t.protein),String(t.weight),String(t.lossRate),t.units])
    }
    private func number(_ r: [String:String], _ key: String) -> Double { Double(r[key] ?? "0") ?? 0 }
    private func date(_ r: [String:String], _ key: String) -> Date { Date(timeIntervalSince1970:number(r,key)) }
    private func nutrition(_ r: [String:String], prefix: String) -> Nutrition { .init(calories:number(r,prefix+"calories"),protein:number(r,prefix+"protein_g"),carbs:number(r,prefix+"carbs_g"),fat:number(r,prefix+"fat_g")) }
}
