import Foundation

/// How a wheel notch turns into motion.
public struct Feel: Codable, Hashable {
    /// Pixels travelled by one unhurried notch.
    public var distance: Double
    /// Seconds until 99% of that distance has been covered.
    public var duration: Double
    /// Largest distance multiplier when the wheel is spun quickly (1 = off).
    public var boost: Double
    /// 0 eases in gently, 1 starts at full speed.
    public var attack: Double

    public init(distance: Double, duration: Double, boost: Double, attack: Double) {
        self.distance = distance
        self.duration = duration
        self.boost = boost
        self.attack = attack
    }

    public static let crisp = Feel(distance: 70, duration: 0.24, boost: 2.5, attack: 0.65)
    public static let balanced = Feel(distance: 85, duration: 0.42, boost: 3.5, attack: 0.4)
    public static let floaty = Feel(distance: 110, duration: 0.8, boost: 5, attack: 0.25)

    /// Values safe to feed to the engine, whatever was stored on disk.
    public var clamped: Feel {
        Feel(distance: min(max(distance, 10), 400),
             duration: min(max(duration, 0.08), 2),
             boost: min(max(boost, 1), 10),
             attack: min(max(attack, 0), 1))
    }
}
