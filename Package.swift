// swift-tools-version: 6.2
import PackageDescription
let package = Package(name: "WeightCoach", platforms: [.iOS(.v17), .macOS(.v14)], products: [.library(name: "WeightCoachCore", targets: ["WeightCoachCore"])], targets: [
.systemLibrary(name: "CSQLite", path: "ios/Data/CSQLite"),
.target(name: "WeightCoachCore", dependencies: ["CSQLite"], path: "ios/Data", exclude: ["CSQLite"], resources: [.copy("SQLite/migrations")]),
.testTarget(name: "WeightCoachCoreTests", dependencies: ["WeightCoachCore"])
])
