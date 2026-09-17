import AppKit
import SwiftData
import SwiftUI

struct NotepadCard: View {
    @Environment(DayClock.self) private var clock

    var body: some View {
        DailyNotepad(dayKey: clock.today).id(clock.today)
    }
}

private struct DailyNotepad: View {
    let dayKey: String
    @Query private var notes: [DailyNote]
    @Environment(\.modelContext) private var context
    @Environment(TaskActions.self) private var actions
    @State private var text = ""
    @State private var saveWork: DispatchWorkItem?
    @State private var flash = false
    /// Last text this card wrote, so its own saves aren't mistaken for outside edits.
    @State private var lastSaved: String?

    init(dayKey: String) {
        self.dayKey = dayKey
        _notes = Query(filter: #Predicate<DailyNote> { $0.dayKey == dayKey })
    }

    var body: some View {
        Card(tint: Palette.notepad) {
            VStack(alignment: .leading, spacing: 8) {
                CardHeader(icon: "square.and.pencil", title: "Notepad")
                Text(DayKey.date(dayKey) ?? .now, format: .dateTime.day().month(.abbreviated).year())
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Palette.inkSecondary)
                Rectangle().fill(Palette.inkTertiary.opacity(0.5)).frame(height: 0.5)
                    .padding(.bottom, 2)

                NoteTextView(text: $text, onMakeTask: makeTask)
                    .overlay(alignment: .topLeading) {
                        if text.isEmpty {
                            Text("Write something down…")
                                .font(.system(size: 13))
                                .foregroundStyle(Palette.inkTertiary)
                                .allowsHitTesting(false)
                        }
                    }

                CardFooter {
                    Label("\(wordCount) \(wordCount == 1 ? "word" : "words")", systemImage: "text.alignleft")
                        .labelStyle(CompactLabelStyle())
                } trailing: {
                    if flash {
                        Text("Task added").fontWeight(.semibold).transition(.opacity)
                    }
                }
            }
        }
        .onAppear { text = notes.first?.text ?? "" }
        .onChange(of: notes.first?.updatedAt) { _, _ in
            // Pick up edits made outside this card, e.g. by an assistant over MCP.
            let stored = notes.first?.text ?? ""
            if stored != lastSaved, stored != text { text = stored }
        }
        .onChange(of: text) { _, newValue in scheduleSave(newValue) }
        .onDisappear { saveNow(text) }
    }

    private var wordCount: Int {
        text.split { $0.isWhitespace || $0.isNewline }.count
    }

    private func makeTask(_ line: String) {
        guard actions.add(line, dayKey: dayKey) != nil else { return }
        withAnimation { flash = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) { withAnimation { flash = false } }
    }

    private func scheduleSave(_ value: String) {
        saveWork?.cancel()
        let work = DispatchWorkItem { saveNow(value) }
        saveWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: work)
    }

    private func saveNow(_ value: String) {
        lastSaved = value
        if let note = notes.first {
            guard note.text != value else { return }
            note.text = value
            note.updatedAt = .now
        } else {
            guard !value.isEmpty else { return }
            context.insert(DailyNote(dayKey: dayKey, text: value))
        }
        try? context.save()
    }
}

/// Plain-text editor that turns the current line into a task on ⌘↩.
struct NoteTextView: NSViewRepresentable {
    @Binding var text: String
    var onMakeTask: (String) -> Void

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = false
        scroll.borderType = .noBorder

        let tv = CommandReturnTextView()
        tv.drawsBackground = false
        tv.isRichText = false
        tv.allowsUndo = true
        tv.font = .systemFont(ofSize: 13)
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = 2
        tv.defaultParagraphStyle = paragraph
        tv.typingAttributes[.paragraphStyle] = paragraph
        tv.textColor = NSColor(Palette.ink)
        tv.insertionPointColor = NSColor(Palette.ink)
        tv.textContainerInset = .zero
        tv.textContainer?.lineFragmentPadding = 0
        tv.isAutomaticQuoteSubstitutionEnabled = false
        tv.isAutomaticDashSubstitutionEnabled = false
        tv.isVerticallyResizable = true
        tv.autoresizingMask = [.width]
        tv.textContainer?.widthTracksTextView = true
        tv.delegate = context.coordinator
        tv.onCommandReturn = { [weak tv] in
            guard let tv else { return }
            context.coordinator.extractLine(from: tv)
        }
        tv.string = text
        scroll.documentView = tv
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        context.coordinator.parent = self
        guard let tv = scroll.documentView as? NSTextView, tv.string != text else { return }
        tv.string = text
    }

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: NoteTextView

        init(parent: NoteTextView) { self.parent = parent }

        func textDidChange(_ notification: Notification) {
            guard let tv = notification.object as? NSTextView else { return }
            parent.text = tv.string
        }

        func extractLine(from tv: NSTextView) {
            let ns = tv.string as NSString
            let lineRange = ns.lineRange(for: tv.selectedRange())
            let line = ns.substring(with: lineRange).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty else { return }
            // Route through the text system so the removal is undoable.
            if tv.shouldChangeText(in: lineRange, replacementString: "") {
                tv.replaceCharacters(in: lineRange, with: "")
                tv.didChangeText()
            }
            parent.onMakeTask(line.replacingOccurrences(of: #"^([-*•]|\[ ?\])\s*"#, with: "", options: .regularExpression))
        }
    }
}

final class CommandReturnTextView: NSTextView {
    var onCommandReturn: (() -> Void)?

    override func keyDown(with event: NSEvent) {
        if event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command,
           event.keyCode == 36 || event.keyCode == 76 {
            onCommandReturn?()
            return
        }
        super.keyDown(with: event)
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if window?.firstResponder === self,
           event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command,
           event.keyCode == 36 || event.keyCode == 76 {
            onCommandReturn?()
            return true
        }
        return super.performKeyEquivalent(with: event)
    }
}
