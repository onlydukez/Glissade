import AppKit
import ApplicationServices
import Combine

enum Permission {
    /// Shows the macOS prompt, which also lists Glissade in System Settings.
    static func request() {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        _ = AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
    }
}

/// Notices other utilities that also rewrite mouse-wheel events.
final class RivalWatcher: ObservableObject {
    @Published private(set) var running: [String] = []
    private static let known = [
        "com.galambalazs.SmoothScroll": "SmoothScroll",
        "com.caldis.Mos": "Mos",
        "com.nuebling.mac-mouse-fix": "Mac Mouse Fix",
        "com.lujjjh.LinearMouse": "LinearMouse",
    ]
    private var observers: [NSObjectProtocol] = []

    init() {
        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in self?.update() })
        }
        update()
    }

    private func update() {
        let ids = Set(NSWorkspace.shared.runningApplications.compactMap { $0.isTerminated ? nil : $0.bundleIdentifier })
        running = Self.known.filter { ids.contains($0.key) }.map(\.value).sorted()
    }
}
