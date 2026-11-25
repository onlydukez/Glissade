import AppKit
import Combine
import ServiceManagement

struct ExcludedApp: Codable, Equatable, Identifiable {
    var id: String        // bundle identifier
    var name: String
}

struct StoredSettings: Codable, Equatable {
    var enabled = true
    var feel = Feel.balanced
    var reverseWheel = false
    var smoothHorizontal = true
    var shiftScrollsSideways = true
    var clickStopsGlide = true
    var excluded: [ExcludedApp] = []
}

/// User settings, saved as they change.
final class Preferences: ObservableObject {
    @Published var values: StoredSettings { didSet { if values != oldValue { save() } } }
    private static let key = "settings.v1"
    private let store: UserDefaults?

    init(store: UserDefaults? = .standard) {
        self.store = store
        if let data = store?.data(forKey: Self.key),
           let saved = try? JSONDecoder().decode(StoredSettings.self, from: data) {
            values = saved
            values.feel = saved.feel.clamped
        } else {
            values = StoredSettings()
        }
    }

    private func save() {
        if let data = try? JSONEncoder().encode(values) { store?.set(data, forKey: Self.key) }
    }
}

enum LoginItem {
    static var isOn: Bool { SMAppService.mainApp.status == .enabled }
    static func set(_ on: Bool) throws {
        if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
    }
}
