import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @ObservedObject var preferences: Preferences
    @ObservedObject var controller: ScrollController
    @ObservedObject var rivals: RivalWatcher
    @State private var loginOn = LoginItem.isOn
    @State private var loginError: String?

    var body: some View {
        VStack(spacing: 0) {
            StatusBar(preferences: preferences, controller: controller, rivals: rivals)
            Divider()
            HStack(alignment: .top, spacing: 0) {
                controls.frame(width: 440)
                Divider()
                VStack(alignment: .leading, spacing: 12) {
                    Text("One notch over time").font(.headline)
                    CurvePreview(feel: preferences.values.feel).frame(height: 120)
                    Text("Try it here").font(.headline).padding(.top, 4)
                    Playground()
                }
                .padding(20)
            }
        }
        .frame(width: 760, height: 620)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            loginOn = LoginItem.isOn
        }
    }

    private var controls: some View {
        Form {
            Section("Feel") {
                Picker("Preset", selection: presetBinding) {
                    Text("Crisp").tag(Feel?.some(.crisp))
                    Text("Balanced").tag(Feel?.some(.balanced))
                    Text("Floaty").tag(Feel?.some(.floaty))
                    Text("Custom").tag(Feel?.none)
                }
                .pickerStyle(.segmented)
                slider("Distance per notch", $preferences.values.feel.distance, 20...250, step: 5) { "\(Int($0)) px" }
                slider("Glide time", $preferences.values.feel.duration, 0.1...1.5, step: 0.02) { String(format: "%.2f s", $0) }
                slider("Fast-spin boost", $preferences.values.feel.boost, 1...8, step: 0.5) { $0 == 1 ? "Off" : String(format: "%.1f×", $0) }
                slider("Start", $preferences.values.feel.attack, 0...1, step: 0.05) { $0 < 0.34 ? "Soft" : $0 < 0.67 ? "Medium" : "Instant" }
            }
            Section("Behavior") {
                Toggle("Reverse the mouse wheel", isOn: $preferences.values.reverseWheel)
                Toggle("Smooth sideways scrolling", isOn: $preferences.values.smoothHorizontal)
                Toggle("Hold Shift to scroll sideways", isOn: $preferences.values.shiftScrollsSideways)
                Toggle("Click to stop a glide", isOn: $preferences.values.clickStopsGlide)
                Toggle("Open at login", isOn: Binding(get: { loginOn }, set: setLogin))
                if let loginError { Text(loginError).font(.caption).foregroundStyle(.red) }
            }
            Section("Leave these apps alone") {
                ForEach(preferences.values.excluded) { app in
                    HStack {
                        Text(app.name)
                        Spacer()
                        Button("Remove") { preferences.values.excluded.removeAll { $0.id == app.id } }
                    }
                }
                Button("Add app…", action: addApp)
            }
        }
        .formStyle(.grouped)
    }

    /// Nil means the sliders no longer match a preset.
    private var presetBinding: Binding<Feel?> {
        Binding(get: { [.crisp, .balanced, .floaty].first { $0 == preferences.values.feel } },
                set: { if let feel = $0 { preferences.values.feel = feel } })
    }

    private func slider(_ title: String, _ value: Binding<Double>, _ range: ClosedRange<Double>,
                        step: Double, _ format: @escaping (Double) -> String) -> some View {
        // Rounding here rather than with Slider(step:) avoids a row of tick marks.
        let snapped = Binding(get: { value.wrappedValue },
                              set: { value.wrappedValue = ($0 / step).rounded() * step })
        return HStack {
            Text(title).frame(width: 130, alignment: .leading)
            Slider(value: snapped, in: range).labelsHidden().accessibilityLabel(title)
            Text(format(value.wrappedValue)).monospacedDigit().foregroundStyle(.secondary)
                .frame(width: 58, alignment: .trailing)
        }
    }

    private func setLogin(_ on: Bool) {
        do { try LoginItem.set(on); loginError = nil }
        catch { loginError = "Couldn’t change this: \(error.localizedDescription)" }
        loginOn = LoginItem.isOn
    }

    private func addApp() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.allowsMultipleSelection = true
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.prompt = "Add"
        guard panel.runModal() == .OK else { return }
        for url in panel.urls {
            guard let id = Bundle(url: url)?.bundleIdentifier,
                  !preferences.values.excluded.contains(where: { $0.id == id }) else { continue }
            let name = FileManager.default.displayName(atPath: url.path)
            preferences.values.excluded.append(ExcludedApp(id: id, name: name.replacingOccurrences(of: ".app", with: "")))
        }
    }
}

private struct StatusBar: View {
    @ObservedObject var preferences: Preferences
    @ObservedObject var controller: ScrollController
    @ObservedObject var rivals: RivalWatcher

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: icon).foregroundStyle(tint).font(.title2)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.headline)
                    Text(detail).font(.callout).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 12)
                if controller.status == .needsPermission {
                    Button("Allow…", action: Permission.request).buttonStyle(.borderedProminent)
                } else {
                    Toggle("Smooth scrolling", isOn: $preferences.values.enabled).toggleStyle(.switch).labelsHidden()
                        .accessibilityLabel("Smooth scrolling")
                }
            }
            if !rivals.running.isEmpty {
                Label {
                    Text("\(rivals.running.joined(separator: " and ")) is also running. Quit it so two apps don’t both handle the wheel.")
                } icon: {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                }
                .font(.callout)
            }
        }
        .padding(.horizontal, 20).padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var icon: String {
        switch controller.status {
        case .running: return "checkmark.circle.fill"
        case .paused: return "pause.circle.fill"
        case .needsPermission: return "hand.raised.fill"
        case .failed: return "xmark.octagon.fill"
        }
    }
    private var tint: Color {
        switch controller.status {
        case .running: return .green
        case .paused: return .secondary
        case .needsPermission: return .orange
        case .failed: return .red
        }
    }
    private var title: String {
        switch controller.status {
        case .running: return "Smoothing your mouse wheel"
        case .paused: return "Paused"
        case .needsPermission: return "Glissade needs Accessibility access"
        case .failed: return "Couldn’t read the mouse wheel"
        }
    }
    private var detail: String {
        switch controller.status {
        case .running:
            let n = controller.smoothedNotches
            return n == 0 ? "Scroll with a mouse wheel to start." : "\(n) notch\(n == 1 ? "" : "es") smoothed since launch."
        case .paused: return "The wheel behaves as macOS normally does."
        case .needsPermission: return "macOS requires it to change scroll events. Glissade never connects to the internet."
        case .failed: return "Remove Glissade from Accessibility in System Settings, add it again, then reopen Glissade."
        }
    }
}

/// Distance covered after a single notch, against a fixed 1.5 s axis so presets compare.
private struct CurvePreview: View {
    let feel: Feel
    var body: some View {
        Canvas { g, size in
            let span = 1.5, base = size.height - 16
            var axis = Path()
            axis.move(to: CGPoint(x: 0, y: base)); axis.addLine(to: CGPoint(x: size.width, y: base))
            g.stroke(axis, with: .color(.secondary.opacity(0.4)))
            for t in [0.5, 1.0] {
                let x = size.width * t / span
                var line = Path(); line.move(to: CGPoint(x: x, y: 0)); line.addLine(to: CGPoint(x: x, y: base))
                g.stroke(line, with: .color(.secondary.opacity(0.18)))
                g.draw(Text(String(format: "%.1f s", t)).font(.caption2).foregroundStyle(.secondary),
                       at: CGPoint(x: x, y: size.height - 7))
            }
            var curve = Path()
            for px in stride(from: 0.0, through: size.width, by: 1) {
                let p = GlideEngine.progress(feel, at: px / size.width * span)
                let point = CGPoint(x: px, y: base - p * (base - 6))
                px == 0 ? curve.move(to: point) : curve.addLine(to: point)
            }
            g.stroke(curve, with: .color(.accentColor), style: StrokeStyle(lineWidth: 2.5, lineJoin: .round))
        }
        .accessibilityLabel("Reaches full distance in \(String(format: "%.2f", feel.duration)) seconds")
    }
}

private struct Playground: View {
    var body: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(1...200, id: \.self) { i in
                    HStack {
                        Text("Line \(i)").monospacedDigit()
                        Spacer()
                        Capsule().fill(Color(hue: Double(i % 40) / 40, saturation: 0.5, brightness: 0.85))
                            .frame(width: 40 + CGFloat((i * 37) % 90), height: 8)
                    }
                    .padding(.horizontal, 12).frame(height: 30)
                    .background(i.isMultiple(of: 2) ? Color.primary.opacity(0.04) : .clear)
                }
            }
        }
        .background(Color(nsColor: .textBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color(nsColor: .separatorColor)))
    }
}
