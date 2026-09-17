import SwiftUI

/// "Holey", the Black Hole mascot: a round little void with big eyes and a glowing accretion ring.
/// Drawn in vectors so it stays crisp from the 18pt top bar up to the 1024px app icon.
struct Mascot: View {
    enum Mood: Equatable {
        case normal
        /// Just finished something: happy arched eyes and a big open smile.
        case happy
        /// A focus session is running: half-lidded, determined eyes.
        case focused
        /// Nobody has visited in a while: closed eyes and drifting z's.
        case sleepy
    }

    var size: CGFloat
    /// Blinks now and then. Keep it off for static renders like the app icon.
    var blinks = false
    /// Eyes glance up toward the notch, used on hover.
    var lookUp = false
    var mood: Mood = .normal

    @State private var eyesClosed = false

    private var body_: CGFloat { size * 0.64 }

    var body: some View {
        ZStack {
            ring(front: false)

            // Soft violet glow so the black body separates from dark backgrounds.
            Circle()
                .fill(RadialGradient(colors: [Color(hex: 0x8B5CF6, opacity: 0.55), .clear],
                                     center: .center, startRadius: body_ * 0.35, endRadius: body_ * 0.85))
                .frame(width: body_ * 1.7, height: body_ * 1.7)

            Circle()
                .fill(RadialGradient(colors: [Color(hex: 0x2A2440), Color(hex: 0x050508)],
                                     center: UnitPoint(x: 0.35, y: 0.3), startRadius: 0, endRadius: body_ * 0.7))
                .frame(width: body_, height: body_)
                // Photon ring: the bright rim of light bent around the event horizon.
                .overlay(photonRing)

            face
                .offset(y: body_ * (lookUp && mood == .normal ? -0.1 : -0.05))

            ring(front: true)

            if mood == .sleepy {
                SleepyZs(size: size)
                    .offset(x: size * 0.3, y: -size * 0.3)
            } else {
                Sparkle(size: size * 0.11)
                    .scaleEffect(mood == .happy ? 1.5 : 1)
                    .offset(x: size * 0.38, y: -size * 0.36)
                Sparkle(size: size * 0.065)
                    .scaleEffect(mood == .happy ? 1.6 : 1)
                    .offset(x: -size * 0.39, y: -size * 0.26)
                    .opacity(0.8)
            }
        }
        .frame(width: size, height: size)
        .animation(.spring(response: 0.35, dampingFraction: 0.6), value: mood)
        .task(id: blinks) {
            guard blinks else { return }
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(Double.random(in: 2.8...5.5)))
                guard mood == .normal || mood == .focused else { continue }
                withAnimation(.easeIn(duration: 0.07)) { eyesClosed = true }
                try? await Task.sleep(for: .milliseconds(110))
                withAnimation(.easeOut(duration: 0.1)) { eyesClosed = false }
            }
        }
    }

    private var photonRing: some View {
        let rim = AngularGradient(colors: [Color(hex: 0xFFE2B8), Color(hex: 0xFF9E5E), Color(hex: 0xC084FC),
                                           Color(hex: 0x7DD3FC), Color(hex: 0xFFE2B8)],
                                  center: .center, angle: .degrees(-40))
        let line = max(0.8, size * 0.016)
        return ZStack {
            Circle().stroke(rim, lineWidth: line * 2.2).blur(radius: line * 1.6).opacity(mood == .sleepy ? 0.5 : 0.9)
            Circle().stroke(rim, lineWidth: line)
        }
        .frame(width: body_ + line, height: body_ + line)
    }

    private var face: some View {
        let eyeW = body_ * 0.19
        let eyeH = body_ * 0.25
        return VStack(spacing: body_ * 0.05) {
            HStack(spacing: body_ * 0.14) {
                eye(width: eyeW, height: eyeH, isLeft: true)
                eye(width: eyeW, height: eyeH, isLeft: false)
            }
            .frame(height: eyeH)
            ZStack {
                HStack(spacing: body_ * 0.42) {
                    Ellipse().fill(Color(hex: 0xFF7AA8, opacity: mood == .happy ? 0.7 : 0.45)).frame(width: body_ * 0.13, height: body_ * 0.07)
                    Ellipse().fill(Color(hex: 0xFF7AA8, opacity: mood == .happy ? 0.7 : 0.45)).frame(width: body_ * 0.13, height: body_ * 0.07)
                }
                .blur(radius: body_ * 0.012)
                mouth
            }
            .frame(height: body_ * 0.1)
        }
    }

    @ViewBuilder
    private var mouth: some View {
        let stroke = StrokeStyle(lineWidth: max(0.8, body_ * 0.035), lineCap: .round)
        switch mood {
        case .normal:
            Smile().stroke(.white.opacity(0.92), style: stroke)
                .frame(width: body_ * 0.16, height: body_ * 0.07)
        case .happy:
            OpenSmile().fill(.white)
                .frame(width: body_ * 0.22, height: body_ * 0.1)
        case .focused:
            Capsule().fill(.white.opacity(0.92))
                .frame(width: body_ * 0.11, height: max(0.8, body_ * 0.035))
        case .sleepy:
            Circle().stroke(.white.opacity(0.85), lineWidth: max(0.7, body_ * 0.028))
                .frame(width: body_ * 0.06, height: body_ * 0.06)
        }
    }

    @ViewBuilder
    private func eye(width: CGFloat, height: CGFloat, isLeft: Bool) -> some View {
        let stroke = StrokeStyle(lineWidth: max(1, width * 0.26), lineCap: .round)
        switch mood {
        case .happy:
            EyeArc(opensDown: false).stroke(.white, style: stroke)
                .frame(width: width, height: height * 0.45)
        case .sleepy:
            EyeArc(opensDown: true).stroke(.white.opacity(0.9), style: stroke)
                .frame(width: width, height: height * 0.3)
                .offset(y: height * 0.15)
        case .normal, .focused:
            ZStack {
                Ellipse().fill(.white)
                Ellipse()
                    .fill(Color(hex: 0x14121C))
                    .frame(width: width * 0.62, height: height * 0.62)
                    .offset(y: height * (lookUp && mood == .normal ? -0.14 : 0.08))
                Circle()
                    .fill(.white)
                    .frame(width: width * 0.26, height: width * 0.26)
                    .offset(x: width * 0.12, y: height * (lookUp && mood == .normal ? -0.26 : -0.06))
            }
            .overlay(alignment: .top) {
                if mood == .focused {
                    // Lids slanted toward the middle for a determined, game-on look.
                    Rectangle().fill(Color(hex: 0x100E18))
                        .frame(width: width * 1.6, height: height * 0.42)
                        .rotationEffect(.degrees(isLeft ? 18 : -18))
                        .offset(y: -height * 0.06)
                }
            }
            .clipShape(Ellipse())
            .frame(width: width, height: height)
            .scaleEffect(x: 1, y: eyesClosed ? 0.08 : 1)
        }
    }

    /// Tilted accretion ring. The back half is drawn behind the body and the front half over it.
    private func ring(front: Bool) -> some View {
        let gradient = AngularGradient(colors: [Color(hex: 0xFFB36B), Color(hex: 0xFF5E7E), Color(hex: 0xA77BF3),
                                                Color(hex: 0x62B6FF), Color(hex: 0xFFB36B)], center: .center)
        let width = size * 0.9
        let height = size * 0.28
        let line = max(1.2, size * 0.045)
        return ZStack {
            Ellipse()
                .trim(from: front ? 0 : 0.49, to: front ? 0.51 : 1)
                .stroke(gradient, style: StrokeStyle(lineWidth: line, lineCap: .butt))
                .blur(radius: line * 0.9)
                .opacity(0.8)
            Ellipse()
                .trim(from: front ? 0 : 0.49, to: front ? 0.51 : 1)
                .stroke(gradient, style: StrokeStyle(lineWidth: line, lineCap: .butt))
        }
        .frame(width: width, height: height)
        .rotationEffect(.degrees(-14))
        // Sits low on the body so it frames the face instead of crossing it.
        .offset(y: body_ * 0.3)
    }
}

private struct Smile: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.minX, y: rect.minY))
        p.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.minY), control: CGPoint(x: rect.midX, y: rect.maxY * 1.6))
        return p
    }
}

/// Wide "D" smile, filled.
private struct OpenSmile: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.minX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        p.addQuadCurve(to: CGPoint(x: rect.minX, y: rect.minY), control: CGPoint(x: rect.midX, y: rect.maxY * 1.9))
        p.closeSubpath()
        return p
    }
}

/// ∩ for happy eyes, ∪ for sleeping eyes.
private struct EyeArc: Shape {
    var opensDown: Bool

    func path(in rect: CGRect) -> Path {
        var p = Path()
        let edgeY = opensDown ? rect.minY : rect.maxY
        let controlY = opensDown ? rect.maxY * 1.6 : rect.minY - rect.height * 0.9
        p.move(to: CGPoint(x: rect.minX, y: edgeY))
        p.addQuadCurve(to: CGPoint(x: rect.maxX, y: edgeY), control: CGPoint(x: rect.midX, y: controlY))
        return p
    }
}

private struct SleepyZs: View {
    var size: CGFloat

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            Text("z").font(.system(size: size * 0.1, weight: .heavy, design: .rounded))
            Text("z").font(.system(size: size * 0.15, weight: .heavy, design: .rounded))
                .offset(x: size * 0.08, y: -size * 0.1)
        }
        .foregroundStyle(.white.opacity(0.85))
        .phaseAnimator([false, true]) { content, up in
            content
                .offset(y: up ? -size * 0.04 : size * 0.01)
                .opacity(up ? 1 : 0.55)
        } animation: { _ in .easeInOut(duration: 1.4) }
    }
}

/// Four-point twinkle star.
struct Sparkle: View {
    var size: CGFloat

    var body: some View {
        SparkleShape()
            .fill(.white)
            .shadow(color: .white.opacity(0.8), radius: size * 0.25)
            .frame(width: size, height: size)
    }

    private struct SparkleShape: Shape {
        func path(in r: CGRect) -> Path {
            var p = Path()
            let c = CGPoint(x: r.midX, y: r.midY)
            let k = r.width * 0.12
            p.move(to: CGPoint(x: c.x, y: r.minY))
            p.addQuadCurve(to: CGPoint(x: r.maxX, y: c.y), control: CGPoint(x: c.x + k, y: c.y - k))
            p.addQuadCurve(to: CGPoint(x: c.x, y: r.maxY), control: CGPoint(x: c.x + k, y: c.y + k))
            p.addQuadCurve(to: CGPoint(x: r.minX, y: c.y), control: CGPoint(x: c.x - k, y: c.y + k))
            p.addQuadCurve(to: CGPoint(x: c.x, y: r.minY), control: CGPoint(x: c.x - k, y: c.y - k))
            return p
        }
    }
}

/// The mascot on its deep-space tile, used as the app icon and brand mark.
struct MascotTile: View {
    var size: CGFloat
    var blinks = false
    var mood: Mascot.Mood = .normal

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.225, style: .continuous)
            .fill(LinearGradient(colors: [Color(hex: 0x2B1F4A), Color(hex: 0x120E22), Color(hex: 0x07060D)],
                                 startPoint: .top, endPoint: .bottom))
            .overlay(StarField(size: size))
            .overlay(Mascot(size: size * 1.02, blinks: blinks, mood: mood).offset(y: -size * 0.02))
            // Clip once, after positioning, so the glow and ring stay inside the tile.
            .clipShape(RoundedRectangle(cornerRadius: size * 0.225, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: size * 0.225, style: .continuous)
                .strokeBorder(.white.opacity(0.14), lineWidth: max(0.5, size * 0.006)))
            .frame(width: size, height: size)
    }
}

struct StarField: View {
    var size: CGFloat

    // Fixed positions so the icon renders identically every time.
    private static let stars: [(x: CGFloat, y: CGFloat, r: CGFloat, a: Double)] = [
        (0.12, 0.14, 0.008, 0.7), (0.26, 0.08, 0.005, 0.5), (0.78, 0.12, 0.006, 0.6), (0.9, 0.3, 0.005, 0.5),
        (0.08, 0.55, 0.006, 0.45), (0.16, 0.86, 0.007, 0.55), (0.52, 0.93, 0.005, 0.4), (0.86, 0.8, 0.008, 0.6),
        (0.94, 0.58, 0.004, 0.4), (0.62, 0.05, 0.004, 0.45),
    ]

    var body: some View {
        Canvas { ctx, sz in
            for s in Self.stars {
                let r = s.r * size
                ctx.fill(Path(ellipseIn: CGRect(x: s.x * sz.width - r, y: s.y * sz.height - r, width: r * 2, height: r * 2)),
                         with: .color(.white.opacity(s.a)))
            }
        }
    }
}

/// Mascot tile laid out on Apple's macOS icon grid: 824pt artwork centered on a 1024pt canvas with a drop shadow.
struct AppIconArtwork: View {
    var body: some View {
        MascotTile(size: 824)
            .shadow(color: .black.opacity(0.35), radius: 22, y: 12)
            .frame(width: 1024, height: 1024)
    }
}
