import SwiftUI

/// Renders digits and colons as a 5×7 LED dot grid.
struct DotMatrixText: View {
    let text: String
    var dot: CGFloat = 3
    var spacing: CGFloat = 1.4
    var color: Color = Palette.ink

    private var pitch: CGFloat {
        dot + spacing
    }

    var body: some View {
        let glyphs = text.compactMap { Self.glyphs[$0] }
        let width = glyphs.reduce(CGFloat(0)) { $0 + CGFloat($1.first?.count ?? 0) * pitch } + CGFloat(max(0, glyphs.count - 1)) * pitch
        Canvas { ctx, _ in
            var x: CGFloat = 0
            for glyph in glyphs {
                for (row, line) in glyph.enumerated() {
                    for (col, bit) in line.enumerated() where bit == "1" {
                        let rect = CGRect(x: x + CGFloat(col) * pitch, y: CGFloat(row) * pitch, width: dot, height: dot)
                        ctx.fill(Path(ellipseIn: rect), with: .color(color))
                    }
                }
                x += CGFloat(glyph.first?.count ?? 0) * pitch + pitch
            }
        }
        .frame(width: max(0, width - spacing), height: 7 * pitch - spacing)
        .accessibilityLabel(text)
    }

    static func format(seconds: Int) -> String {
        let s = max(0, seconds)
        if s >= 3600 {
            return String(format: "%d:%02d:%02d", s / 3600, (s % 3600) / 60, s % 60)
        }
        return String(format: "%02d:%02d", s / 60, s % 60)
    }

    private static let glyphs: [Character: [String]] = [
        "0": ["01110", "10001", "10001", "10001", "10001", "10001", "01110"],
        "1": ["00100", "01100", "00100", "00100", "00100", "00100", "01110"],
        "2": ["01110", "10001", "00001", "00010", "00100", "01000", "11111"],
        "3": ["11111", "00010", "00100", "00010", "00001", "10001", "01110"],
        "4": ["00010", "00110", "01010", "10010", "11111", "00010", "00010"],
        "5": ["11111", "10000", "11110", "00001", "00001", "10001", "01110"],
        "6": ["00110", "01000", "10000", "11110", "10001", "10001", "01110"],
        "7": ["11111", "00001", "00010", "00100", "01000", "01000", "01000"],
        "8": ["01110", "10001", "10001", "01110", "10001", "10001", "01110"],
        "9": ["01110", "10001", "10001", "01111", "00001", "00010", "01100"],
        ":": ["0", "0", "1", "0", "1", "0", "0"]
    ]
}
