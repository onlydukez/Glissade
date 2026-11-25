import AppKit

/// `Glissade --self-test` feeds synthetic events through the real controller and
/// display link, capturing what would be posted. Needs no permissions.
enum SelfTest {
    static func run() -> Never {
        var failures = 0
        func check(_ ok: Bool, _ name: String, _ detail: String = "") {
            print((ok ? "ok    " : "FAIL  ") + name + (detail.isEmpty ? "" : "  [\(detail)]"))
            if !ok { failures += 1 }
        }
        func spin(_ seconds: Double) { RunLoop.main.run(until: Date().addingTimeInterval(seconds)) }
        func wheel(_ y: Int32, _ x: Int32 = 0, flags: CGEventFlags = [], units: CGScrollEventUnit = .line) -> CGEvent {
            let e = CGEvent(scrollWheelEvent2Source: nil, units: units, wheelCount: 2, wheel1: y, wheel2: x, wheel3: 0)!
            e.flags = flags
            return e
        }
        let prefs = Preferences(store: nil)
        prefs.values.feel = Feel(distance: 100, duration: 0.3, boost: 1, attack: 0.4)
        let c = ScrollController(preferences: prefs)
        var out: [CGEvent] = []
        var stamps: [CFTimeInterval] = []
        c.post = { out.append($0); stamps.append(CACurrentMediaTime()) }
        // A fake pointer, so using the Mac during the test can't affect it.
        var spot = NSPoint(x: 10, y: 10), win = 1
        c.pointer = { spot }
        c.windowAt = { _ in win }
        func total(_ field: CGEventField) -> Int { out.reduce(0) { $0 + Int($1.getIntegerValueField(field)) } }
        let y = CGEventField.scrollWheelEventPointDeltaAxis1, x = CGEventField.scrollWheelEventPointDeltaAxis2
        func reset() { c.stopGlide(); out = []; stamps = [] }

        check(!c.handle(.scrollWheel, wheel(1)), "wheel notch is swallowed")
        spin(1)
        check(total(y) == 100 && total(x) == 0, "notch becomes exactly 100 px", "\(total(y)) px in \(out.count) events")
        check(out.count >= 10, "spread over many frames", "\(out.count)")
        if stamps.count > 2 {
            let gaps = zip(stamps.dropFirst(), stamps).map { $0 - $1 }.sorted()
            print(String(format: "      frame gap median %.1f ms", gaps[gaps.count / 2] * 1000))
        }
        check(out.allSatisfy { $0.getIntegerValueField(.scrollWheelEventIsContinuous) == 1 }, "output is pixel-precise")
        check(out.allSatisfy { c.handle(.scrollWheel, $0) }, "own events pass through (no feedback loop)")

        reset(); _ = c.handle(.scrollWheel, wheel(-5)); spin(1)
        check(total(y) == -100, "direction kept, system acceleration ignored", "\(total(y))")
        reset()
        check(c.handle(.scrollWheel, wheel(12, units: .pixel)), "trackpad-style event untouched")
        for (name, f) in [("cmd", CGEventFlags.maskCommand), ("ctrl", .maskControl), ("option", .maskAlternate)] {
            check(c.handle(.scrollWheel, wheel(1, flags: f)), "\(name)+wheel untouched")
        }
        reset(); _ = c.handle(.scrollWheel, wheel(1, flags: .maskShift)); spin(1)
        check(total(x) == 100 && total(y) == 0, "shift+wheel scrolls sideways", "\(total(x)), \(total(y))")
        check(out.allSatisfy { !$0.flags.contains(.maskShift) }, "shift removed from output")

        reset(); prefs.values.reverseWheel = true; _ = c.handle(.scrollWheel, wheel(1)); spin(1)
        check(total(y) == -100, "reverse wheel"); prefs.values.reverseWheel = false

        reset(); prefs.values.smoothHorizontal = false
        check(c.handle(.scrollWheel, wheel(0, 1)), "horizontal left alone when turned off"); prefs.values.smoothHorizontal = true

        reset(); _ = c.handle(.scrollWheel, wheel(1)); spin(0.05)
        let before = out.count
        check(c.handle(.leftMouseDown, wheel(0)), "click passes through"); spin(0.4)
        check(out.count == before, "click stops the glide")

        reset(); _ = c.handle(.scrollWheel, wheel(1)); spin(0.05)
        spot.x += 5; spin(1)
        check(total(y) == 100, "moving within a window keeps gliding", "\(total(y))")
        reset(); _ = c.handle(.scrollWheel, wheel(1)); spin(0.05)
        spot.x += 5; win = 2
        let left = out.count; spin(0.4)
        check(out.count == left && left > 0, "moving to another window stops the glide", "\(left), \(out.count)")

        // Any real window will do for matching an app to its exclusion.
        let spotted = (CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] ?? []).first {
            ($0[kCGWindowOwnerPID as String] as? pid_t).flatMap { NSRunningApplication(processIdentifier: $0)?.bundleIdentifier } != nil
        }
        win = spotted?[kCGWindowNumber as String] as? Int ?? 0
        let info = CGWindowListCopyWindowInfo([.optionIncludingWindow], CGWindowID(max(win, 0))) as? [[String: Any]]
        if let pid = info?.first?[kCGWindowOwnerPID as String] as? pid_t,
           let id = NSRunningApplication(processIdentifier: pid)?.bundleIdentifier {
            prefs.values.excluded = [ExcludedApp(id: id, name: id)]
            check(c.handle(.scrollWheel, wheel(1)), "excluded app untouched")
            prefs.values.excluded = []
        } else { print("skip  excluded app (no identifiable window on screen)") }

        reset()
        print(failures == 0 ? "\nSelf-test passed." : "\n\(failures) FAILED")
        exit(failures == 0 ? 0 : 1)
    }
}
