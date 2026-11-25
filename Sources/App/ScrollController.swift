import AppKit
import Combine

/// Intercepts mouse-wheel notches and replays them as smooth, pixel-sized scrolls.
///
/// Everything runs on the main thread: the event tap, the display link and the
/// settings all share it, so there is no shared state to lock.
final class ScrollController: NSObject, ObservableObject {
    enum Status: Equatable { case needsPermission, running, paused, failed }

    @Published private(set) var status: Status = .needsPermission
    @Published private(set) var smoothedNotches = 0

    private let preferences: Preferences
    private var engine: GlideEngine
    private var subscription: AnyCancellable?

    private var tap: CFMachPort?
    private var tapSource: CFRunLoopSource?
    private var healthTimer: Timer?

    private var link: CADisplayLink?
    private var lastFrame: CFTimeInterval?
    private var activity: NSObjectProtocol?
    private var glideFlags: CGEventFlags = []
    private var glideWindow = 0
    private var lastPointer = NSPoint.zero

    private var ownerCache: (window: Int, bundleID: String?) = (0, nil)

    /// Stamped on events we create so that our own tap lets them through.
    static let marker: Int64 = 0x474C_4944_45
    private let eventSource = CGEventSource(stateID: .privateState)

    /// Where finished events go. Replaced by the self-test.
    var post: (CGEvent) -> Void = { $0.post(tap: .cgSessionEventTap) }

    init(preferences: Preferences) {
        self.preferences = preferences
        self.engine = GlideEngine(feel: preferences.values.feel)
        super.init()
        eventSource?.localEventsSuppressionInterval = 0
        subscription = preferences.$values.sink { [weak self] new in
            guard let self else { return }
            self.engine.feel = new.feel
            if !new.enabled { self.stopGlide() }
            self.refresh(enabled: new.enabled)
        }
    }

    // MARK: Lifecycle

    func start() {
        // Also catches permission being granted or revoked while we are running.
        // An active tap left behind after revocation can stall input system-wide.
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            guard let self else { return }
            self.refresh(enabled: self.preferences.values.enabled)
        }
        timer.tolerance = 0.2
        RunLoop.main.add(timer, forMode: .common)
        healthTimer = timer
        NSWorkspace.shared.notificationCenter.addObserver(
            self, selector: #selector(stopGlide),
            name: NSWorkspace.didActivateApplicationNotification, object: nil)
        NSWorkspace.shared.notificationCenter.addObserver(
            self, selector: #selector(stopGlide),
            name: NSWorkspace.activeSpaceDidChangeNotification, object: nil)
        refresh(enabled: preferences.values.enabled)
    }

    func shutDown() {
        healthTimer?.invalidate()
        stopGlide()
        removeTap()
    }

    private func refresh(enabled: Bool) {
        guard healthTimer != nil else { return }
        let next: Status
        if !AXIsProcessTrusted() {
            removeTap()
            next = .needsPermission
        } else if !enabled {
            removeTap()
            next = .paused
        } else if let tap {
            if !CGEvent.tapIsEnabled(tap: tap) { CGEvent.tapEnable(tap: tap, enable: true) }
            next = .running
        } else {
            next = installTap() ? .running : .failed
        }
        if status != next { status = next }
    }

    private func installTap() -> Bool {
        let types: [CGEventType] = [.scrollWheel, .leftMouseDown, .rightMouseDown, .otherMouseDown]
        let mask = types.reduce(CGEventMask(0)) { $0 | (1 << CGEventMask($1.rawValue)) }
        let callback: CGEventTapCallBack = { _, type, event, context in
            let me = Unmanaged<ScrollController>.fromOpaque(context!).takeUnretainedValue()
            return me.handle(type, event) ? Unmanaged.passUnretained(event) : nil
        }
        guard let port = CGEvent.tapCreate(
            tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
            eventsOfInterest: mask, callback: callback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()),
            let source = CFMachPortCreateRunLoopSource(nil, port, 0)
        else { return false }
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: port, enable: true)
        tap = port
        tapSource = source
        return true
    }

    private func removeTap() {
        stopGlide()
        if let tap {
            CGEvent.tapEnable(tap: tap, enable: false)
            CFMachPortInvalidate(tap)
        }
        if let tapSource { CFRunLoopRemoveSource(CFRunLoopGetMain(), tapSource, .commonModes) }
        tap = nil
        tapSource = nil
    }

    // MARK: Incoming events

    /// Returns true to let the event through untouched, false to swallow it.
    func handle(_ type: CGEventType, _ event: CGEvent) -> Bool {
        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return true
        case .leftMouseDown, .rightMouseDown, .otherMouseDown:
            if preferences.values.clickStopsGlide { stopGlide() }
            return true
        case .scrollWheel:
            return handleScroll(event)
        default:
            return true
        }
    }

    private func handleScroll(_ event: CGEvent) -> Bool {
        if event.getIntegerValueField(.eventSourceUserData) == Self.marker { return true }
        let settings = preferences.values

        // Trackpads and Magic Mouse are smooth already.
        if event.getIntegerValueField(.scrollWheelEventIsContinuous) != 0
            || event.getIntegerValueField(.scrollWheelEventScrollPhase) != 0
            || event.getIntegerValueField(.scrollWheelEventMomentumPhase) != 0 {
            stopGlide()
            return true
        }
        // Zooming and app shortcuts expect the original notches.
        let flags = event.flags
        if !flags.isDisjoint(with: [.maskCommand, .maskControl, .maskAlternate]) {
            stopGlide()
            return true
        }

        var dy = direction(event, .scrollWheelEventDeltaAxis1, .scrollWheelEventFixedPtDeltaAxis1, .scrollWheelEventPointDeltaAxis1)
        var dx = direction(event, .scrollWheelEventDeltaAxis2, .scrollWheelEventFixedPtDeltaAxis2, .scrollWheelEventPointDeltaAxis2)
        var outFlags = flags
        if flags.contains(.maskShift) && settings.shiftScrollsSideways {
            if dx == 0 { (dx, dy) = (dy, 0) }
            // Otherwise the receiving app would swap the axes a second time.
            outFlags.remove(.maskShift)
        }
        if !settings.smoothHorizontal && dx != 0 { return true }
        if dx == 0 && dy == 0 { return true }

        let window = windowUnderPointer()
        if isExcluded(window: window, settings.excluded) {
            stopGlide()
            return true
        }
        if window != glideWindow { engine.stop() }
        glideWindow = window
        lastPointer = NSEvent.mouseLocation
        glideFlags = outFlags

        let sign = settings.reverseWheel ? -1 : 1
        engine.notch(dx: dx * sign, dy: dy * sign, at: CACurrentMediaTime())
        smoothedNotches += 1
        startGlide()
        return false
    }

    /// macOS scales wheel deltas by its own acceleration; only the direction is kept.
    private func direction(_ event: CGEvent, _ lines: CGEventField, _ fixed: CGEventField, _ points: CGEventField) -> Int {
        let whole = event.getIntegerValueField(lines)
        if whole != 0 { return Int(whole.signum()) }
        let fraction = event.getDoubleValueField(fixed)
        if fraction != 0 { return fraction > 0 ? 1 : -1 }
        return Int(event.getIntegerValueField(points).signum())
    }

    private func windowUnderPointer() -> Int {
        NSWindow.windowNumber(at: NSEvent.mouseLocation, belowWindowWithWindowNumber: 0)
    }

    private func isExcluded(window: Int, _ apps: [ExcludedApp]) -> Bool {
        guard !apps.isEmpty, window > 0 else { return false }
        if ownerCache.window != window {
            let info = CGWindowListCopyWindowInfo([.optionIncludingWindow], CGWindowID(window)) as? [[String: Any]]
            let pid = info?.first?[kCGWindowOwnerPID as String] as? pid_t
            ownerCache = (window, pid.flatMap { NSRunningApplication(processIdentifier: $0)?.bundleIdentifier })
        }
        guard let owner = ownerCache.bundleID else { return false }
        return apps.contains { $0.id == owner }
    }

    // MARK: Outgoing events

    private func startGlide() {
        guard link == nil else { return }
        let pointer = NSEvent.mouseLocation
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(pointer) }) ?? NSScreen.main else {
            engine.stop()
            return
        }
        activity = ProcessInfo.processInfo.beginActivity(
            options: [.userInitiatedAllowingIdleSystemSleep, .latencyCritical], reason: "Scrolling")
        let new = screen.displayLink(target: self, selector: #selector(frame(_:)))
        let top = Float(screen.maximumFramesPerSecond)
        if top > 60 { new.preferredFrameRateRange = CAFrameRateRange(minimum: 60, maximum: top, preferred: top) }
        lastFrame = nil
        new.add(to: .main, forMode: .common)
        link = new
    }

    @objc func stopGlide() {
        engine.stop()
        link?.invalidate()
        link = nil
        if let activity { ProcessInfo.processInfo.endActivity(activity) }
        activity = nil
    }

    @objc private func frame(_ link: CADisplayLink) {
        // Don't spill a glide into whatever the pointer has moved onto.
        let pointer = NSEvent.mouseLocation
        if pointer != lastPointer {
            lastPointer = pointer
            if windowUnderPointer() != glideWindow {
                stopGlide()
                return
            }
        }
        let now = link.targetTimestamp
        let dt = lastFrame.map { now - $0 } ?? link.duration
        lastFrame = now
        let move = engine.advance(dt)
        if move.dx != 0 || move.dy != 0 { emit(move.dx, move.dy) }
        if engine.isIdle { stopGlide() }
    }

    private func emit(_ dx: Int, _ dy: Int) {
        guard let event = CGEvent(
            scrollWheelEvent2Source: eventSource, units: .pixel, wheelCount: 2,
            wheel1: Int32(dy), wheel2: Int32(dx), wheel3: 0) else { return }
        event.setIntegerValueField(.eventSourceUserData, value: Self.marker)
        event.flags = glideFlags
        post(event)
    }
}
