import SwiftUI
import WeightCoachCore

@main
struct WeightCoachApp: App {
    @State private var model: AppModel?
    @State private var failure: String?
    var body: some Scene {
        WindowGroup {
            Group {
                if let model { RootView(model: model) }
                else if let failure { ContentUnavailableView("Unable to open your data", systemImage: "externaldrive.badge.exclamationmark", description: Text(failure)) }
                else { ProgressView("Opening your journal…") }
            }.task {
                guard model == nil && failure == nil else { return }
                do {
                    let directory = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true).appendingPathComponent("WeightCoach", isDirectory: true)
                    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.protectionKey: FileProtectionType.complete])
                    model = try AppModel(store: TrackingStore(path: directory.appendingPathComponent("journal.sqlite").path))
                } catch { failure = error.localizedDescription }
            }
        }
    }
}

@MainActor @Observable
final class AppModel {
    let store: TrackingStore
    var meals: [Meal] = []
    var weights: [WeighIn] = []
    var targets = Targets()
    var error: String?
    init(store: TrackingStore) throws { self.store = store; try reload() }
    func reload() throws { meals = try store.meals(); weights = try store.weights(); targets = try store.targets() }
    @discardableResult func perform(_ action: () throws -> Void) -> Bool {
        do { try action(); try reload(); return true }
        catch { self.error = error.localizedDescription; return false }
    }
    func displayWeight(_ kg: Double) -> Double { targets.units == "imperial" ? kg * 2.2046226218 : kg }
    var weightUnit: String { targets.units == "imperial" ? "lb" : "kg" }
}
