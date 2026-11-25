import AppKit
import Combine
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    let preferences: Preferences
    let controller: ScrollController
    let rivals = RivalWatcher()
    private var statusItem: NSStatusItem!
    private var window: NSWindow?
    private var subscriptions = Set<AnyCancellable>()

    override init() {
        preferences = Preferences()
        controller = ScrollController(preferences: preferences)
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu
        controller.$status.sink { [weak self] in self?.updateIcon($0) }.store(in: &subscriptions)
        controller.start()

        let firstRun = !UserDefaults.standard.bool(forKey: "hasLaunched")
        UserDefaults.standard.set(true, forKey: "hasLaunched")
        if firstRun || controller.status == .needsPermission { showSettings() }
    }

    func applicationWillTerminate(_ notification: Notification) { controller.shutDown() }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showSettings()
        return false
    }

    private func updateIcon(_ status: ScrollController.Status) {
        let name = status == .running ? "computermouse.fill" : "computermouse"
        statusItem.button?.image = NSImage(systemSymbolName: name, accessibilityDescription: "Glissade")
        statusItem.button?.appearsDisabled = status != .running
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let title: String
        switch controller.status {
        case .running: title = "Smoothing your mouse wheel"
        case .paused: title = "Paused"
        case .needsPermission: title = "Needs Accessibility access"
        case .failed: title = "Couldn’t read the mouse wheel"
        }
        menu.addItem(withTitle: title, action: nil, keyEquivalent: "")
        menu.addItem(.separator())
        add(menu, preferences.values.enabled ? "Pause" : "Resume", #selector(toggle))
        add(menu, "Settings…", #selector(showSettings), ",")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit Glissade", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
    }

    private func add(_ menu: NSMenu, _ title: String, _ action: Selector, _ key: String = "") {
        menu.addItem(withTitle: title, action: action, keyEquivalent: key).target = self
    }

    @objc private func toggle() { preferences.values.enabled.toggle() }

    @objc private func showSettings() {
        if window == nil {
            let w = NSWindow(contentRect: .zero, styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
            w.title = "Glissade"
            w.contentView = NSHostingView(rootView: SettingsView(preferences: preferences, controller: controller, rivals: rivals))
            w.setContentSize(NSSize(width: 760, height: 620))
            w.isReleasedWhenClosed = false
            w.center()
            window = w
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    /// Draws the settings window to a PNG without showing it on screen.
    func renderSettings(to path: String, dark: Bool) {
        let view = NSHostingView(rootView: SettingsView(preferences: preferences, controller: controller, rivals: rivals))
        let w = NSWindow(contentRect: NSRect(x: -4000, y: -4000, width: 760, height: 620), styleMask: [.titled], backing: .buffered, defer: false)
        w.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        w.contentView = view
        w.setContentSize(NSSize(width: 760, height: 620))
        w.orderBack(nil)
        RunLoop.main.run(until: Date().addingTimeInterval(1))
        let target = view.superview ?? view
        guard let rep = target.bitmapImageRepForCachingDisplay(in: target.bounds) else { return }
        target.cacheDisplay(in: target.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
    }
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let arguments = CommandLine.arguments
if arguments.contains("--self-test") { SelfTest.run() }

let delegate = AppDelegate()
if let i = arguments.firstIndex(of: "--render"), arguments.count > i + 1 {
    delegate.renderSettings(to: arguments[i + 1], dark: arguments.contains("--dark"))
    exit(0)
}
app.delegate = delegate
app.run()
