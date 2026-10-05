// swift-tools-version: 6.2
import PackageDescription
let package = Package(name: "WeightCoach", platforms: [.iOS(.v17), .macOS(.v14)], products: [.library(name: "WeightCoachCore", targets: ["WeightCoachCore"]), .library(name: "WeightCoachAI", targets: ["WeightCoachAI"])], targets: [
.systemLibrary(name: "CSQLite", path: "ios/Data/CSQLite"),
.target(name: "WeightCoachCore", dependencies: ["CSQLite"], path: "ios/Data", exclude: ["CSQLite"], resources: [.copy("SQLite/migrations")]),
.target(name: "WeightCoachAI", dependencies: ["WeightCoachCore"], path: "ios/Services/OpenAI"),
.testTarget(name: "WeightCoachAITests", dependencies: ["WeightCoachAI", "WeightCoachCore"]),
.testTarget(name: "WeightCoachCoreTests", dependencies: ["WeightCoachCore"])
])
