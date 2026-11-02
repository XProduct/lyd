import SwiftUI

/// Shared timing / reduce-motion gates for Phase D tvOS polish (safe to use on iPad too).
enum LydMotion {
    static let washDuration: Double = 0.85
    static let crossfadeDuration: Double = 0.45
    static let breathPeriod: Double = 3.2
    static let progressEase: Double = 0.55
    static let staggerStep: Double = 0.035
    static let cinemaIdleSeconds: TimeInterval = 12

    static func allowsMotion(_ reduceMotion: Bool) -> Bool { !reduceMotion }

    /// Deterministic ambient hue from a stable id (album / song) — no image sampling required.
    static func washColor(for id: String?, fallback: Color = LydTheme.primary) -> Color {
        guard let id, !id.isEmpty else { return fallback }
        var hash: UInt64 = 5381
        for byte in id.utf8 {
            hash = ((hash << 5) &+ hash) &+ UInt64(byte)
        }
        let hue = Double(hash % 360) / 360.0
        return Color(hue: hue, saturation: 0.45, brightness: 0.35)
    }
}

struct CrossfadeValue<Value: Hashable>: View {
    let value: Value
    let reduceMotion: Bool
    let content: (Value) -> AnyView

    init(value: Value, reduceMotion: Bool, @ViewBuilder content: @escaping (Value) -> some View) {
        self.value = value
        self.reduceMotion = reduceMotion
        self.content = { AnyView(content($0)) }
    }

    var body: some View {
        content(value)
            .id(value)
            .transition(
                reduceMotion
                    ? .identity
                    : .asymmetric(
                        insertion: .opacity.combined(with: .scale(scale: 0.98)),
                        removal: .opacity
                    )
            )
            .animation(reduceMotion ? nil : .easeInOut(duration: LydMotion.crossfadeDuration), value: value)
    }
}

struct BreathingModifier: ViewModifier {
    let isPlaying: Bool
    let reduceMotion: Bool
    @State private var expanded = false

    func body(content: Content) -> some View {
        content
            .scaleEffect(scale)
            .opacity(opacity)
            .onAppear { syncBreath() }
            .onChange(of: isPlaying) { _, _ in syncBreath() }
            .onChange(of: reduceMotion) { _, _ in syncBreath() }
    }

    private var scale: CGFloat {
        guard LydMotion.allowsMotion(reduceMotion), isPlaying else { return 1 }
        return expanded ? 1.035 : 1.0
    }

    private var opacity: Double {
        guard LydMotion.allowsMotion(reduceMotion), isPlaying else { return 1 }
        return expanded ? 1.0 : 0.92
    }

    private func syncBreath() {
        guard LydMotion.allowsMotion(reduceMotion), isPlaying else {
            withAnimation(.easeOut(duration: 0.25)) { expanded = false }
            return
        }
        withAnimation(.easeInOut(duration: LydMotion.breathPeriod).repeatForever(autoreverses: true)) {
            expanded = true
        }
    }
}

extension View {
    func lydBreathing(isPlaying: Bool, reduceMotion: Bool) -> some View {
        modifier(BreathingModifier(isPlaying: isPlaying, reduceMotion: reduceMotion))
    }
}

/// Non-seekable progress with eased fill + soft playhead glow (Phase D #4).
struct EasedProgressBar: View {
    let progress: Double
    let reduceMotion: Bool
    var tint: Color = LydTheme.primary

    @State private var displayed: Double = 0

    var body: some View {
        GeometryReader { geo in
            let width = max(geo.size.width, 1)
            let clamped = min(max(displayed, 0), 1)
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.primary.opacity(0.15))
                Capsule()
                    .fill(tint.opacity(0.85))
                    .frame(width: width * clamped)
                Circle()
                    .fill(tint)
                    .frame(width: 14, height: 14)
                    .shadow(color: tint.opacity(reduceMotion ? 0 : 0.85), radius: reduceMotion ? 0 : 10)
                    .offset(x: max(0, width * clamped - 7))
            }
        }
        .frame(height: 10)
        .onAppear { displayed = progress }
        .onChange(of: progress) { _, newValue in
            if reduceMotion {
                displayed = newValue
            } else {
                withAnimation(.easeInOut(duration: LydMotion.progressEase)) {
                    displayed = newValue
                }
            }
        }
        .accessibilityHidden(true)
    }
}

/// Elapsed / duration with digit crossfade (Phase D #5).
struct CrossfadeTimeLabel: View {
    let milliseconds: Int64
    let reduceMotion: Bool
    var font: Font = .title3.monospacedDigit()

    private var text: String {
        let total = max(milliseconds, 0) / 1000
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    var body: some View {
        Text(text)
            .font(font)
            .foregroundStyle(Color.secondary)
            .contentTransition(reduceMotion ? .identity : .numericText())
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.25), value: text)
    }
}
