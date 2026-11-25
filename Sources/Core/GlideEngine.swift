import Foundation

/// A critically damped spring pulling `remaining` to zero.
///
/// Motion is the exact solution of the spring, not a per-frame approximation,
/// so a glide covers the same distance at 60 Hz, 120 Hz, or across dropped frames.
struct Spring {
    private(set) var remaining = 0.0
    /// Pixels per second, signed the same way as `remaining`.
    private(set) var velocity = 0.0
    /// Movement not yet emitted because events carry whole pixels.
    private var carry = 0.0

    static let backlogLimit = 12_000.0

    var isIdle: Bool { remaining == 0 && velocity == 0 }

    mutating func push(_ distance: Double, omega: Double, attack: Double) {
        // Scrolling back should answer at once, not pay off the old glide first.
        if remaining * distance < 0 { reset() }
        remaining = min(max(remaining + distance, -Self.backlogLimit), Self.backlogLimit)
        velocity += attack * omega * distance
    }

    mutating func advance(_ dt: Double, omega: Double) -> Int {
        guard !isIdle else { return 0 }
        // Faster than this the spring would overshoot and bounce back.
        let ceiling = omega * abs(remaining)
        velocity = min(max(velocity, -ceiling), ceiling)

        let x0 = remaining, v0 = -velocity
        let b = v0 + omega * x0
        let decay = exp(-omega * dt)
        remaining = (x0 + b * dt) * decay
        velocity = -(v0 - omega * b * dt) * decay
        carry += x0 - remaining

        if abs(remaining) < 0.5 && abs(velocity) < 12 {
            let last = Int((carry + remaining).rounded())
            reset()
            return last
        }
        let whole = carry.rounded(.towardZero)
        carry -= whole
        return Int(whole)
    }

    mutating func reset() { self = Spring() }
}

/// Measures how quickly the wheel is being spun.
struct Tempo {
    private var lastTime: Double?
    private var lastSign = 0.0
    private var rate = 0.0

    static let slow = 7.0, fast = 30.0, pause = 0.25

    /// Returns 0 for unhurried notches, rising to 1 for a fast spin.
    mutating func strike(at time: Double, sign: Double) -> Double {
        defer { lastTime = time; lastSign = sign }
        guard let last = lastTime, sign == lastSign, time - last < Self.pause else {
            rate = 0
            return 0
        }
        // Coalesced events can share a timestamp; don't let one spike the rate.
        let instant = min(1 / max(time - last, 0.004), 60)
        rate = rate == 0 ? instant * 0.5 : rate * 0.6 + instant * 0.4
        let t = min(max((rate - Self.slow) / (Self.fast - Self.slow), 0), 1)
        return t * t * (3 - 2 * t)
    }
}

public struct GlideEngine {
    public var feel: Feel { didSet { feel = feel.clamped; omega = Self.omega(for: feel) } }
    private var omega: Double
    private var x = Spring(), y = Spring()
    private var tempoX = Tempo(), tempoY = Tempo()

    public init(feel: Feel) {
        self.feel = feel.clamped
        self.omega = Self.omega(for: feel.clamped)
    }

    public var isIdle: Bool { x.isIdle && y.isIdle }

    /// Registers one wheel notch; each argument is -1, 0 or +1.
    public mutating func notch(dx: Int, dy: Int, at time: Double) {
        if dx != 0 { Self.push(&x, &tempoX, Double(dx.signum()), time, feel, omega) }
        if dy != 0 { Self.push(&y, &tempoY, Double(dy.signum()), time, feel, omega) }
    }

    private static func push(_ spring: inout Spring, _ tempo: inout Tempo, _ sign: Double,
                             _ time: Double, _ feel: Feel, _ omega: Double) {
        let factor = 1 + (feel.boost - 1) * tempo.strike(at: time, sign: sign)
        spring.push((sign * feel.distance * factor).rounded(), omega: omega, attack: feel.attack)
    }

    /// Moves time forward and returns the whole pixels to scroll.
    public mutating func advance(_ dt: Double) -> (dx: Int, dy: Int) {
        let step = min(max(dt, 0), 0.1)
        return (x.advance(step, omega: omega), y.advance(step, omega: omega))
    }

    public mutating func stop() {
        x.reset(); y.reset()
        tempoX = Tempo(); tempoY = Tempo()
    }

    /// Fraction of a single notch covered after `time` seconds.
    public static func progress(_ feel: Feel, at time: Double) -> Double {
        let f = feel.clamped
        let wt = omega(for: f) * max(time, 0)
        return 1 - (1 + (1 - f.attack) * wt) * exp(-wt)
    }

    /// Spring stiffness that reaches 99% exactly at `feel.duration`.
    static func omega(for feel: Feel) -> Double {
        var low = 3.0, high = 9.0
        for _ in 0..<40 {
            let mid = (low + high) / 2
            if (1 + (1 - feel.attack) * mid) * exp(-mid) > 0.01 { low = mid } else { high = mid }
        }
        return (low + high) / 2 / feel.duration
    }
}
