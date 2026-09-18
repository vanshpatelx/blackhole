import AppKit
import SwiftUI

enum Palette {
    static let panel = Color.black
    static let tasks = Color(hex: 0x819F89)
    static let timer = Color(hex: 0x948BAE)
    static let notepad = Color(hex: 0xA09A5E)
    static let events = Color(hex: 0x8199AE)
    static let insightsSummary = tasks
    static let insightsChart = timer

    static let ink = Color(hex: 0x17171A)
    static let inkSecondary = ink.opacity(0.58)
    static let inkTertiary = ink.opacity(0.38)
    /// Recessed wells inside cards: inputs, rows, event tiles.
    static let well = Color.black.opacity(0.08)
    static let wellStrong = Color.black.opacity(0.13)

    static let chrome = Color(hex: 0x2A2A2D)
    static let chromeSelected = Color(hex: 0x4A4A4E)
    static let chromeText = Color.white.opacity(0.88)
}

enum Radius {
    static let card: CGFloat = 18
    static let well: CGFloat = 12
    static let pill: CGFloat = 8
}

extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: opacity
        )
    }
}

// MARK: Grain

/// Film-grain noise tile generated once at launch, so no image assets are needed.
enum Grain {
    static let image: NSImage = {
        let size = 192
        var pixels = [UInt8](repeating: 0, count: size * size * 4)
        var rng = SystemRandomNumberGenerator()
        for i in stride(from: 0, to: pixels.count, by: 4) {
            let v = UInt8.random(in: 0 ... 255, using: &rng)
            pixels[i] = v; pixels[i + 1] = v; pixels[i + 2] = v; pixels[i + 3] = 255
        }
        let provider = CGDataProvider(data: Data(pixels) as CFData)!
        let cg = CGImage(
            width: size,
            height: size,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: size * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
            provider: provider,
            decode: nil,
            shouldInterpolate: false,
            intent: .defaultIntent
        )!
        // Half-size points: the tile renders at 2x pixel density on Retina for a finer grain.
        return NSImage(cgImage: cg, size: NSSize(width: size / 2, height: size / 2))
    }()
}

struct GrainOverlay: View {
    var opacity: Double = 0.09

    var body: some View {
        Image(nsImage: Grain.image)
            .resizable(resizingMode: .tile)
            .blendMode(.overlay)
            .opacity(opacity)
            .allowsHitTesting(false)
    }
}

// MARK: Card

struct Card<Content: View>: View {
    let tint: Color
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(14)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background {
                RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                    .fill(tint)
                    .overlay(GrainOverlay().clipShape(RoundedRectangle(cornerRadius: Radius.card, style: .continuous)))
                    // Flatten the grain blend into one GPU layer so open/close animations stay smooth.
                    .drawingGroup()
            }
            .foregroundStyle(Palette.ink)
    }
}

struct CardHeader<Trailing: View>: View {
    let icon: String
    let title: String
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: icon)
                .font(.system(size: 12.5, weight: .semibold))
            Text(title)
                .font(.system(size: 13.5, weight: .semibold))
            Spacer(minLength: 4)
            trailing
        }
        .frame(height: 22)
    }
}

extension CardHeader where Trailing == EmptyView {
    init(icon: String, title: String) {
        self.init(icon: icon, title: title) { EmptyView() }
    }
}

struct CardFooter<Leading: View, Trailing: View>: View {
    @ViewBuilder var leading: Leading
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(spacing: 4) {
            leading
            Spacer(minLength: 4)
            trailing
        }
        .font(.system(size: 11, weight: .medium))
        .foregroundStyle(Palette.inkSecondary)
        .lineLimit(1)
        .frame(height: 18)
    }
}

struct DottedDivider: View {
    var body: some View {
        Line()
            .stroke(Palette.inkTertiary, style: StrokeStyle(lineWidth: 1, dash: [1.5, 3]))
            .frame(height: 1)
    }

    private struct Line: Shape {
        func path(in rect: CGRect) -> Path {
            var p = Path()
            p.move(to: CGPoint(x: rect.minX, y: rect.midY))
            p.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
            return p
        }
    }
}

// MARK: Buttons

/// Dark pill used for Start / Pause / Resume.
struct PillButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12.5, weight: .semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 13)
            .frame(height: 30)
            .background(RoundedRectangle(cornerRadius: Radius.pill, style: .continuous).fill(Palette.ink))
            .opacity(configuration.isPressed ? 0.75 : 1)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

/// Small borderless icon button that shows a soft well on hover.
struct IconButton: View {
    let systemName: String
    var size: CGFloat = 20
    var help: String = ""
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 10.5, weight: .semibold))
                .frame(width: size, height: size)
                .background(Circle().fill(hovering ? Palette.well : .clear))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(help)
        .onHover { hovering = $0 }
    }
}

/// Top-bar chrome button on the black panel, e.g. "Open app".
struct ChromeButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(Palette.chromeText)
            .padding(.horizontal, 10)
            .frame(height: 24)
            .background(RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(configuration.isPressed ? Palette.chromeSelected : Palette.chrome))
    }
}

struct ChromeTabs<Tab: Hashable & Identifiable & RawRepresentable>: View where Tab.RawValue == String {
    let tabs: [Tab]
    @Binding var selection: Tab
    @Namespace private var ns

    var body: some View {
        HStack(spacing: 0) {
            ForEach(tabs) { tab in
                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) { selection = tab }
                } label: {
                    Text(tab.rawValue)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Palette.chromeText)
                        .lineLimit(1)
                        .fixedSize()
                        .padding(.horizontal, 11)
                        .frame(height: 22)
                        .background {
                            if selection == tab {
                                RoundedRectangle(cornerRadius: 5, style: .continuous)
                                    .fill(Palette.chromeSelected)
                                    .matchedGeometryEffect(id: "tab", in: ns)
                            }
                        }
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(2)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Palette.chrome))
    }
}

/// Menu whose label is drawn exactly as given, so fonts and colors apply (borderless menus ignore them).
struct PlainMenu<Label: View, Content: View>: View {
    @ViewBuilder var content: Content
    @ViewBuilder var label: Label

    var body: some View {
        Menu {
            content
        } label: {
            label.contentShape(Rectangle())
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
    }
}

/// "⋯" button that opens a menu, with a soft hover well.
struct EllipsisMenu<Content: View>: View {
    @ViewBuilder var content: Content
    @State private var hovering = false

    var body: some View {
        PlainMenu {
            content
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(Palette.ink.opacity(0.75))
                .frame(width: 22, height: 22)
                .background(Circle().fill(hovering ? Palette.well : .clear))
        }
        .onHover { hovering = $0 }
    }
}

/// Two-option segmented control drawn on a card (Tasks / Focus in Insights).
struct CardSegmented<Option: Hashable>: View {
    let options: [(Option, String)]
    @Binding var selection: Option

    var body: some View {
        HStack(spacing: 0) {
            ForEach(options, id: \.0) { option, label in
                Button {
                    withAnimation(.easeOut(duration: 0.15)) { selection = option }
                } label: {
                    Text(label)
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundStyle(selection == option ? Palette.ink : .white)
                        .frame(width: 58, height: 22)
                        .background(RoundedRectangle(cornerRadius: 5, style: .continuous).fill(selection == option ? .white : .clear))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(2)
        .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(Palette.ink))
    }
}
