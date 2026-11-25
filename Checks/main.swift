import Foundation

var failures = 0
func check(_ ok: Bool, _ name: String, _ detail: String = "") {
    print((ok ? "ok    " : "FAIL  ") + name + (detail.isEmpty ? "" : "  [\(detail)]"))
    if !ok { failures += 1 }
}
func run(_ e: inout GlideEngine, hz: Double, limit: Double = 10) -> (total: Int, frames: [Int], time: Double) {
    var total = 0, frames: [Int] = [], t = 0.0
    while !e.isIdle && t < limit {
        let d = e.advance(1 / hz).dy
        total += d; frames.append(d); t += 1 / hz
    }
    return (total, frames, t)
}
let presets = [("crisp", Feel.crisp), ("balanced", .balanced), ("floaty", .floaty)]

for (name, feel) in presets {
    for hz in [30.0, 60, 120, 144] {
        for sign in [1, -1] {
            var e = GlideEngine(feel: feel)
            e.notch(dx: 0, dy: sign, at: 0)
            let r = run(&e, hz: hz)
            check(r.total == sign * Int(feel.distance), "\(name) \(Int(hz))Hz sign \(sign): exact distance", "\(r.total)")
            check(r.frames.allSatisfy { $0 * sign >= 0 }, "\(name) \(Int(hz))Hz sign \(sign): never moves backwards")
        }
    }
    check(abs(GlideEngine.progress(feel, at: feel.duration) - 0.99) < 1e-6, "\(name): 99% at its duration")
    check(GlideEngine.progress(feel, at: 0) == 0, "\(name): starts at zero")
}

// Extremes of every slider
for d in [10.0, 400] { for t in [0.08, 2] { for a in [0.0, 1] {
    var e = GlideEngine(feel: Feel(distance: d, duration: t, boost: 10, attack: a))
    e.notch(dx: 0, dy: 1, at: 0)
    let r = run(&e, hz: 120)
    check(e.isIdle && r.total == Int(d) && r.frames.allSatisfy { $0 >= 0 }, "extreme d=\(d) t=\(t) a=\(a)", "\(r.total) in \(String(format: "%.2f", r.time))s")
}}}

// Irregular frames give the same total
do {
    var e = GlideEngine(feel: .balanced); e.notch(dx: 0, dy: 1, at: 0)
    var total = 0, i = 0
    while !e.isIdle && i < 5000 { total += e.advance([0.004, 0.033, 0.008, 0.09][i % 4]).dy; i += 1 }
    check(total == 85, "irregular frames: exact distance", "\(total)")
}
// Slow notches do not accelerate; a fast spin does, within its cap
do {
    var e = GlideEngine(feel: .balanced); var total = 0
    for i in 0..<5 { e.notch(dx: 0, dy: 1, at: Double(i)); total += run(&e, hz: 120).total }
    check(total == 5 * 85, "slow notches: no boost", "\(total)")

    var f = GlideEngine(feel: .balanced)
    for i in 0..<20 { f.notch(dx: 0, dy: 1, at: Double(i) * 0.02) }
    let fast = run(&f, hz: 120).total
    check(fast > 20 * 85 * 2 && fast <= Int(20 * 85 * 3.5), "fast spin: boosted within cap", "\(fast)")

    var g = GlideEngine(feel: Feel(distance: 85, duration: 0.42, boost: 1, attack: 0.4))
    for i in 0..<20 { g.notch(dx: 0, dy: 1, at: Double(i) * 0.02) }
    let off = run(&g, hz: 120).total
    check(off == 20 * 85, "boost 1: off", "\(off)")
}
// Reversing mid-glide answers on the next frame
do {
    var e = GlideEngine(feel: .floaty)
    for i in 0..<6 { e.notch(dx: 0, dy: 1, at: Double(i) * 0.05); _ = e.advance(0.05) }
    e.notch(dx: 0, dy: -1, at: 0.4)
    let r = run(&e, hz: 120)
    check(r.total == -110 && r.frames.allSatisfy { $0 <= 0 }, "reverse: drops the old glide", "\(r.total)")
}
// Sub-pixel carry while notches keep arriving
do {
    var e = GlideEngine(feel: Feel(distance: 37, duration: 0.5, boost: 1, attack: 0.3)); var total = 0
    for i in 0..<40 { e.notch(dx: 0, dy: 1, at: Double(i) * 0.06); for _ in 0..<7 { total += e.advance(1 / 120).dy } }
    total += run(&e, hz: 120).total
    check(total == 40 * 37, "no pixels lost across overlapping notches", "\(total)")
}
// Axes are independent, stop() is immediate, settings may change mid-glide
do {
    var e = GlideEngine(feel: .balanced); e.notch(dx: -1, dy: 1, at: 0)
    var h = 0, v = 0
    while !e.isIdle { let d = e.advance(1 / 120); h += d.dx; v += d.dy }
    check(h == -85 && v == 85, "axes independent", "\(h), \(v)")

    var s = GlideEngine(feel: .floaty); s.notch(dx: 0, dy: 1, at: 0); _ = s.advance(0.02); s.stop()
    check(s.isIdle && s.advance(0.02).dy == 0, "stop: immediate")

    var m = GlideEngine(feel: .crisp); m.notch(dx: 0, dy: 1, at: 0)
    var total = m.advance(0.03).dy; m.feel = .floaty
    let r = run(&m, hz: 120); total += r.total
    check(total == 70 && r.frames.allSatisfy { $0 >= 0 }, "settings change mid-glide", "\(total)")
}
print(failures == 0 ? "\nAll checks passed." : "\n\(failures) FAILED")
exit(failures == 0 ? 0 : 1)
