import SwiftUI

/// The floating button's look: a frosted glass circle holding a tiny black hole.
/// Idle it's just the symbol; during focus the black hole swallows the clock;
/// now and then Holey's face shows up inside it.
struct FloatingOrb: View {
    enum Face: Equatable {
        case none
        case curious   // hover: eyes pop in and look up
        case peek      // random idle peek with a blink
        case happy     // finished something
        case sleepy    // nobody around for a while
    }

    var size: CGFloat = 52
    /// Clock text to show inside the black hole, e.g. "24:31". `nil` when no timer runs.
    var time: String?
    /// 0...1 for countdowns, `nil` for a stopwatch or no timer.
    var progress: Double?
    var paused = false
    var finished = false
    var face: Face = .none
    var highlighted = false

    static let disk = AngularGradient(
        colors: [Color(hex: 0xFFB36B), Color(hex: 0xFF5E7E), Color(hex: 0xA77BF3), Color(hex: 0x62B6FF), Color(hex: 0xFFB36B)],
        center: .center)

    private var timerMode: Bool { time != nil || finished }
    private var coreDiameter: CGFloat { size * (timerMode ? 0.8 : (face == .none ? 0.54 : 0.66)) }
    private var ringWidth: CGFloat { timerMode ? size * 0.055 : size * 0.065 }

    var body: some View {
        ZStack {
            glass

            // Glow behind the ring.
            Circle()
                .stroke(Self.disk, lineWidth: ringWidth * 1.4)
                .blur(radius: ringWidth * 1.3)
                .opacity(highlighted ? 0.95 : 0.6)
                .frame(width: coreDiameter, height: coreDiameter)

            if timerMode, let progress, !finished {
                Circle()
                    .stroke(.white.opacity(0.18), lineWidth: ringWidth)
                    .frame(width: coreDiameter, height: coreDiameter)
                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(Self.disk, style: StrokeStyle(lineWidth: ringWidth, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .frame(width: coreDiameter, height: coreDiameter)
                    .opacity(paused ? 0.5 : 1)
            } else {
                Circle()
                    .stroke(finished ? AngularGradient(colors: [Color(hex: 0x4ADE80)], center: .center) : Self.disk, lineWidth: ringWidth)
                    .frame(width: coreDiameter, height: coreDiameter)
                    .rotationEffect(.degrees(highlighted ? 120 : 0))
            }

            // The event horizon.
            Circle()
                .fill(.black)
                .frame(width: coreDiameter - ringWidth * 1.2, height: coreDiameter - ringWidth * 1.2)

            content
        }
        .frame(width: size, height: size)
        .animation(.spring(duration: 0.45, bounce: 0.25), value: face)
        .animation(.spring(duration: 0.5, bounce: 0.15), value: timerMode)
        .animation(.easeInOut(duration: 0.8), value: highlighted)
        .animation(.linear(duration: 1), value: progress)
    }

    private var glass: some View {
        Circle()
            .fill(.ultraThinMaterial)
            .overlay(Circle().fill(Color.black.opacity(0.22)))
            .overlay(
                Circle().strokeBorder(
                    LinearGradient(colors: [.white.opacity(0.55), .white.opacity(0.08), .white.opacity(0.22)],
                                   startPoint: .top, endPoint: .bottom),
                    lineWidth: 0.8)
            )
    }

    @ViewBuilder
    private var content: some View {
        if finished {
            Image(systemName: "checkmark")
                .font(.system(size: size * 0.24, weight: .black))
                .foregroundStyle(Color(hex: 0x4ADE80))
                .transition(.scale.combined(with: .opacity))
        } else if let time, face != .happy {
            VStack(spacing: 0) {
                if paused {
                    Image(systemName: "pause.fill")
                        .font(.system(size: size * 0.11, weight: .black))
                        .foregroundStyle(.white.opacity(0.6))
                }
                Text(time)
                    .font(.system(size: size * (time.count > 5 ? 0.17 : 0.2), weight: .semibold, design: .rounded).monospacedDigit())
                    .foregroundStyle(.white.opacity(paused ? 0.55 : 1))
                    .contentTransition(.numericText(countsDown: progress != nil))
                    .lineLimit(1)
                    .fixedSize()
            }
            .transition(.opacity)
        } else if face != .none {
            OrbFace(face: face, width: coreDiameter * 0.62)
                .transition(.scale(scale: 0.4).combined(with: .opacity))
        }
    }
}

private struct OrbFace: View {
    let face: FloatingOrb.Face
    let width: CGFloat
    @State private var blink = false

    var body: some View {
        let eyeW = width * 0.24
        let eyeH = width * 0.32
        VStack(spacing: width * 0.08) {
            HStack(spacing: width * 0.2) {
                eye(w: eyeW, h: eyeH)
                eye(w: eyeW, h: eyeH)
            }
            .frame(height: eyeH)
            mouth
                .frame(height: width * 0.14)
        }
        .onAppear {
            guard face == .peek else { return }
            // A single blink midway through the peek.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) {
                withAnimation(.easeIn(duration: 0.07)) { blink = true }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
                    withAnimation(.easeOut(duration: 0.1)) { blink = false }
                }
            }
        }
    }

    @ViewBuilder
    private func eye(w: CGFloat, h: CGFloat) -> some View {
        let line = StrokeStyle(lineWidth: max(1.2, w * 0.32), lineCap: .round)
        switch face {
        case .happy:
            Arc(up: true).stroke(.white, style: line).frame(width: w * 1.1, height: h * 0.45)
        case .sleepy:
            Arc(up: false).stroke(.white.opacity(0.85), style: line).frame(width: w * 1.1, height: h * 0.3)
        default:
            ZStack {
                Ellipse().fill(.white)
                Circle().fill(.black)
                    .frame(width: w * 0.55, height: w * 0.55)
                    .offset(y: face == .curious ? -h * 0.16 : h * 0.06)
            }
            .frame(width: w, height: h)
            .scaleEffect(x: 1, y: blink ? 0.1 : 1)
        }
    }

    @ViewBuilder
    private var mouth: some View {
        switch face {
        case .happy:
            Arc(up: false).fill(.white).frame(width: width * 0.3, height: width * 0.14)
        case .sleepy:
            Circle().stroke(.white.opacity(0.8), lineWidth: 1).frame(width: width * 0.1, height: width * 0.1)
        case .curious:
            Circle().fill(.white).frame(width: width * 0.1, height: width * 0.1)
        default:
            Arc(up: false).stroke(.white, style: StrokeStyle(lineWidth: max(1, width * 0.05), lineCap: .round))
                .frame(width: width * 0.22, height: width * 0.08)
        }
    }

    /// ∩ when `up`, ∪ otherwise.
    private struct Arc: Shape {
        var up: Bool
        func path(in r: CGRect) -> Path {
            var p = Path()
            let edge = up ? r.maxY : r.minY
            let control = up ? r.minY - r.height : r.maxY + r.height
            p.move(to: CGPoint(x: r.minX, y: edge))
            p.addQuadCurve(to: CGPoint(x: r.maxX, y: edge), control: CGPoint(x: r.midX, y: control))
            return p
        }
    }
}
