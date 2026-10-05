import XCTest
@testable import WeightCoachCore

final class CoreTests: XCTestCase {
    func testNutritionUsesFinalRatherThanEstimate() {
        let item = MealItem(foodName:"Chicken",finalGrams:100,final:.init(calories:170,protein:30),estimatedGrams:200,estimate:.init(calories:340,protein:60),confidence:0.5)
        XCTAssertEqual(Meal(items:[item,item]).totals.calories,340)
        XCTAssertEqual(Meal(items:[item]).totals.protein,30)
        XCTAssertFalse(MealItem(foodName:"Food",final:.init(calories:.nan)).isValid)
    }
    func testRollingAverageUsesCalendarWindow() {
        var calendar = Calendar(identifier:.gregorian); calendar.timeZone = TimeZone(secondsFromGMT:0)!
        let end = Date(timeIntervalSince1970:1_700_000_000)
        let weights = [WeighIn(date:end,weightKg:90), WeighIn(date:calendar.date(byAdding:.day,value:-6,to:end)!,weightKg:92),WeighIn(date:calendar.date(byAdding:.day,value:-7,to:end)!,weightKg:110)]
        XCTAssertEqual(Trends.average(weights:weights,ending:end,calendar:calendar),91)
        XCTAssertNil(Trends.average(weights:[],ending:end))
    }
    func testWeeklyNutritionExcludesUnloggedDays() {
        let end = Date()
        let meals = [Meal(timestamp:end,items:[MealItem(foodName:"A",final:.init(calories:100,protein:10))]),Meal(timestamp:end,items:[MealItem(foodName:"B",final:.init(calories:200,protein:20))])]
        XCTAssertEqual(Trends.weeklyNutrition(meals:meals,ending:end)?.calories,300)
    }
    @MainActor func testMigrationPersistenceEditingAndForeignKeys() throws {
        let path = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
        defer { for suffix in ["","-wal","-shm"] { try? FileManager.default.removeItem(atPath:path+suffix) } }
        let store = try TrackingStore(path:path)
        var meal = Meal(items:[MealItem(foodName:"Oats",finalGrams:50,final:.init(calories:180),estimatedGrams:40,estimate:.init(calories:150),confidence:0.8)])
        try store.save(meal)
        meal.items[0].final.calories = 200; try store.save(meal)
        let reopened = try TrackingStore(path:path)
        XCTAssertEqual(try reopened.meals()[0].totals.calories,200)
        XCTAssertEqual(try reopened.meals()[0].items[0].estimate?.calories,150)
        XCTAssertEqual(try store.database.query("PRAGMA user_version")[0]["user_version"],"1")
        try store.deleteMeal(meal.id)
        XCTAssertTrue(try store.database.query("SELECT * FROM meal_items").isEmpty)
    }
    @MainActor func testDailyWeighInUpsertAndInvalidMealRollback() throws {
        let store = try TrackingStore(path:":memory:")
        try store.save(WeighIn(weightKg:91)); try store.save(WeighIn(weightKg:90))
        XCTAssertEqual(try store.weights().count,1)
        XCTAssertEqual(try store.weights()[0].weightKg,90)
        var meal = Meal(items:[MealItem(foodName:"A",final:.init(calories:10))]); try store.save(meal)
        meal.items[0].final.calories = -1
        XCTAssertThrowsError(try store.save(meal))
        XCTAssertEqual(try store.meals()[0].totals.calories,10)
    }
    @MainActor func testExportRestoreSerializationAndRollback() throws {
        let source = try TrackingStore(path:":memory:")
        try source.save(Meal(items:[MealItem(foodName:"Soup ' 🥣",final:.init(calories:150))]))
        try source.save(WeighIn(weightKg:92))
        let data = try source.exportData()
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        let export = try decoder.decode(LogicalExport.self,from:data)
        XCTAssertEqual(export.schemaVersion,1); XCTAssertEqual(export.mealItems.count,1)
        let destination = try TrackingStore(path:":memory:"); try destination.importData(data)
        XCTAssertEqual(try source.meals(),try destination.meals())
        XCTAssertEqual(try source.weights(),try destination.weights())
        var broken = export; broken.weights[0]["weight_kg"] = "-1"
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
        XCTAssertThrowsError(try destination.importData(encoder.encode(broken)))
        XCTAssertEqual(try destination.weights()[0].weightKg,92)
        broken = export; broken.schemaVersion = 99
        XCTAssertThrowsError(try destination.importData(encoder.encode(broken)))
    }
    @MainActor func testMalformedBackupIdentifiersAndTotalsAreRejected() throws {
        let store = try TrackingStore(path:":memory:")
        try store.save(Meal(items:[MealItem(foodName:"Dinner",final:.init(calories:500))]))
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        let good = try decoder.decode(LogicalExport.self,from:store.exportData())
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
        var broken = good; broken.meals[0]["id"] = "not-a-uuid"
        XCTAssertThrowsError(try store.importData(encoder.encode(broken)))
        broken = good; broken.meals[0]["total_calories"] = "999"
        XCTAssertThrowsError(try store.importData(encoder.encode(broken)))
        broken = good; broken.settings[0]["calorie_target"] = "NaN"
        XCTAssertThrowsError(try store.importData(encoder.encode(broken)))
        XCTAssertEqual(try store.meals()[0].totals.calories,500)
    }
    @MainActor func testFailedItemInsertRollsBackParentAndDeletion() throws {
        let store = try TrackingStore(path:":memory:")
        let original = Meal(items:[MealItem(foodName:"First",final:.init(calories:100))])
        try store.save(original)
        var other = Meal(items:[MealItem(foodName:"Second",final:.init(calories:200))])
        other.items[0].id = original.items[0].id
        XCTAssertThrowsError(try store.save(other))
        XCTAssertEqual(try store.meals().count,1)
        XCTAssertEqual(try store.meals()[0].items[0].foodName,"First")
    }

}
