import Foundation

public struct MealEstimateAudit: Codable, Sendable {
    public var modelName:String
    public var timestamp:Date
    public var normalizedResponse:String
    public var originalTotals:Nutrition
    public init(modelName:String,timestamp:Date,normalizedResponse:String,originalTotals:Nutrition) {
        self.modelName = modelName; self.timestamp = timestamp; self.normalizedResponse = normalizedResponse; self.originalTotals = originalTotals
    }
}
