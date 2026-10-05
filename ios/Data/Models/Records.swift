import Foundation

public struct Nutrition: Codable, Equatable, Sendable {
    public var calories: Double
    public var protein: Double
    public var carbs: Double
    public var fat: Double
    public init(calories: Double = 0, protein: Double = 0, carbs: Double = 0, fat: Double = 0) {
        self.calories = calories; self.protein = protein; self.carbs = carbs; self.fat = fat
    }
    public var isValid: Bool { [calories, protein, carbs, fat].allSatisfy { $0.isFinite && $0 >= 0 } }
    public static func + (a: Self, b: Self) -> Self {
        .init(calories: a.calories + b.calories, protein: a.protein + b.protein, carbs: a.carbs + b.carbs, fat: a.fat + b.fat)
    }
}
public struct MealItem: Codable, Identifiable, Equatable, Sendable {
    public var id = UUID()
    public var foodName: String
    public var finalGrams: Double
    public var final: Nutrition
    public var estimatedGrams: Double?
    public var estimate: Nutrition?
    public var confidence: Double?
    public var createdAt = Date()
    public init(foodName: String = "", finalGrams: Double = 0, final: Nutrition = .init(), estimatedGrams: Double? = nil, estimate: Nutrition? = nil, confidence: Double? = nil) {
        self.foodName = foodName; self.finalGrams = finalGrams; self.final = final
        self.estimatedGrams = estimatedGrams; self.estimate = estimate; self.confidence = confidence
    }
    public var isValid: Bool {
        !foodName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && finalGrams.isFinite && finalGrams >= 0 && final.isValid && (estimate?.isValid ?? true) && (estimatedGrams.map { $0.isFinite && $0 >= 0 } ?? true) && (confidence.map { $0.isFinite && (0...1).contains($0) } ?? true)
    }
}
public struct Meal: Codable, Identifiable, Equatable, Sendable {
    public var id = UUID()
    public var timestamp: Date
    public var mealType: String
    public var notes: String
    public var items: [MealItem]
    public var createdAt = Date()
    public var updatedAt = Date()
    public init(timestamp: Date = Date(), mealType: String = "Lunch", notes: String = "", items: [MealItem] = []) {
        self.timestamp = timestamp; self.mealType = mealType; self.notes = notes; self.items = items
    }
    public var totals: Nutrition { items.reduce(.init()) { $0 + $1.final } }
}
public struct WeighIn: Codable, Identifiable, Equatable, Sendable {
    public var id = UUID()
    public var date: Date
    public var weightKg: Double
    public var createdAt = Date()
    public init(date: Date = Date(), weightKg: Double) { self.date = date; self.weightKg = weightKg }
}
public enum Trends {
    // Calendar windows, not the last seven observations. Missing days are never zero-filled.
    public static func average(weights: [WeighIn], ending: Date, days: Int = 7, calendar: Calendar = .current) -> Double? {
        guard days > 0, let start = calendar.date(byAdding: .day, value: 1 - days, to: calendar.startOfDay(for: ending)), let end = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: ending)) else { return nil }
        let values = weights.filter { $0.date >= start && $0.date < end }
        guard !values.isEmpty else { return nil }
        return values.reduce(0) { $0 + $1.weightKg } / Double(values.count)
    }
    public static func dailyNutrition(meals: [Meal], day: Date, calendar: Calendar = .current) -> Nutrition {
        meals.filter { calendar.isDate($0.timestamp, inSameDayAs: day) }.reduce(.init()) { $0 + $1.totals }
    }
    public static func weeklyNutrition(meals: [Meal], ending: Date, calendar: Calendar = .current) -> Nutrition? {
        let days = (0..<7).compactMap { calendar.date(byAdding: .day, value: -$0, to: ending) }
        let logged = days.filter { day in meals.contains { calendar.isDate($0.timestamp, inSameDayAs: day) } }
        guard !logged.isEmpty else { return nil }
        let sum = logged.reduce(Nutrition()) { $0 + dailyNutrition(meals: meals, day: $1, calendar: calendar) }
        let count = Double(logged.count)
        return .init(calories: sum.calories/count, protein: sum.protein/count, carbs: sum.carbs/count, fat: sum.fat/count)
    }
}
