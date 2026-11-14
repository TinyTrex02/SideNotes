import SwiftUI
import AppKit

struct ContentView: View {
    @EnvironmentObject var state: AppState
    @FocusState private var searchFocused: Bool
    @State private var browser: NoteBrowserMode?

    private var searching: Bool { !state.query.trimmingCharacters(in: .whitespaces).isEmpty }

    var body: some View {
        Group {
            if state.isCollapsed {
                CollapsedDotView { state.isCollapsed = false }
            } else {
                expandedPanel
            }
        }
        .animation(.snappy(duration: 0.28), value: state.isCollapsed)
        .preferredColorScheme(state.appearanceMode == .dark ? .dark : nil)
        .sheet(item: $browser) { mode in
            NoteBrowserView(mode: mode)
                .environmentObject(state)
        }
        .onReceive(NotificationCenter.default.publisher(for: .focusSearch)) { _ in searchFocused = true }
    }

    private var expandedPanel: some View {
        VStack(spacing: 0) {
            header
            panelDivider
            formatBar
            panelDivider
            ZStack {
                RichEditor(controller: state.editor, noteID: state.selectedID)
                if searching { results }
            }
            panelDivider
            footer
        }
        .background {
            if state.appearanceMode == .dark {
                Color.black
            } else {
                Rectangle().fill(.regularMaterial)
            }
        }
    }

    // MARK: Header
    private var header: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                Menu {
                    Button {
                        browser = .all
                    } label: {
                        Label("View All", systemImage: "square.grid.2x2")
                    }
                    Divider()
                    ForEach(state.notes) { n in
                        Button(n.title.isEmpty ? "Untitled" : n.title) { state.selectedID = n.id }
                    }
                    Divider()
                    Button {
                        browser = .deleted
                    } label: {
                        Label("Recently Deleted", systemImage: "trash")
                    }
                } label: {
                    HStack(spacing: 2) {
                        Image(systemName: "note.text")
                        Image(systemName: "chevron.down").font(.system(size: 8, weight: .bold))
                    }
                }
                .menuStyle(.borderlessButton)
                .frame(width: 34)

                TextField("Title (e.g. Lex Fridman #412)", text: titleBinding)
                    .textFieldStyle(.plain)
                    .font(.headline)

                Button { state.newNote() } label: { Image(systemName: "plus") }
                    .help("New note")
                Button {
                    state.appearanceMode = state.appearanceMode == .grey ? .dark : .grey
                } label: {
                    Image(systemName: state.appearanceMode.icon)
                }
                .help(state.appearanceMode == .grey ? "Switch to matte-black dark mode" : "Switch to translucent grey mode")
                Button { state.isCollapsed = true } label: {
                    Image(systemName: "circle.dotted.circle")
                }
                .help("Collapse to floating dot")
                Button { state.pinned.toggle() } label: {
                    Image(systemName: state.pinned ? "pin.fill" : "pin.slash")
                }
                .help(state.pinned ? "Pinned: stays on top" : "Unpinned: hides when you click away")
                Button { state.hide() } label: { Image(systemName: "xmark") }
                    .help("Close (Esc)")
            }
            .buttonStyle(.borderless)

            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Search all notes (⌘F)", text: $state.query)
                    .textFieldStyle(.plain)
                    .focused($searchFocused)
                    .onSubmit {
                        if let first = state.searchResults.first { state.openFromSearch(first.id) }
                    }
                if !state.query.isEmpty {
                    Button { state.query = "" } label: { Image(systemName: "xmark.circle.fill") }
                        .buttonStyle(.borderless)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(RoundedRectangle(cornerRadius: 7).fill(Color.primary.opacity(0.06)))
        }
        .padding(.horizontal, 12)
        .padding(.top, 8)
        .padding(.bottom, 8)
    }

    // MARK: Formatting bar
    private var formatBar: some View {
        HStack(spacing: 2) {
            fmt(.bold, "Bold (⌘B)")
            fmt(.italic, "Italic (⌘I)")
            fmt(.underline, "Underline (⌘U)")
            fmt(.strike, "Strikethrough (⇧⌘X)")

            toolbarDivider

            Menu {
                ForEach(TextSize.allCases) { size in
                    Button {
                        state.editor.applySize(size)
                        state.editor.focus()
                    } label: {
                        if state.activeTextSize == size { Image(systemName: "checkmark") }
                        Text(size.title)
                    }
                }
            } label: {
                HStack(spacing: 3) {
                    Text("Aa").fontWeight(.medium)
                    Text(state.activeTextSize.title).font(.caption)
                }
                .frame(height: 20)
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .help("Text size")

            toolbarDivider

            Button { state.editor.insertImagesFromDisk() } label: {
                Image(systemName: "photo").frame(width: 24, height: 20)
            }
            .help("Insert image. You can also paste or drag one in. Click an image to resize it.")

            Button { state.editor.insertDivider() } label: {
                Image(systemName: "minus").frame(width: 24, height: 20)
            }
            .help("Insert horizontal separator")

            Button { state.editor.insertCheckbox() } label: {
                Image(systemName: "checklist").frame(width: 24, height: 20)
            }
            .help("Insert clickable checkbox")

            if let w = state.selectedImageWidth {
                Image(systemName: "arrow.left.and.right")
                    .foregroundStyle(.secondary)
                    .padding(.leading, 6)
                Slider(value: Binding(get: { w }, set: { state.editor.resizeSelectedImages(to: $0) }),
                       in: 40...max(80, state.maxImageWidth))
                    .frame(maxWidth: 120)
                    .help("Image size")
                Button("Fit") { state.editor.resizeSelectedImages(to: state.maxImageWidth) }
                    .help("Fit image to panel width")
            }
            Spacer()
        }
        .buttonStyle(.borderless)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
    }

    private func fmt(_ format: Format, _ help: String) -> some View {
        Button {
            state.editor.apply(format)
            state.editor.focus()
        } label: {
            formatLabel(format)
                .frame(width: 24, height: 20)
                .background(
                    RoundedRectangle(cornerRadius: 5)
                        .fill(state.activeFormats.contains(format) ? Color.accentColor.opacity(0.22) : .clear)
                )
        }
        .help(help)
        .accessibilityValue(state.activeFormats.contains(format) ? "On" : "Off")
    }

    private var toolbarDivider: some View {
        Rectangle()
            .fill(Color.white.opacity(state.appearanceMode == .dark ? 0.38 : 0.58))
            .frame(width: 1, height: 16)
            .padding(.horizontal, 4)
    }

    @ViewBuilder
    private func formatLabel(_ format: Format) -> some View {
        switch format {
        case .bold: Text("B").bold()
        case .italic: Text("I").italic()
        case .underline: Text("U").underline()
        case .strike: Text("S").strikethrough()
        }
    }

    // MARK: Search results
    private var results: some View {
        let q = state.query.trimmingCharacters(in: .whitespaces)
        let found = state.searchResults
        return ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                if found.isEmpty {
                    Text("No notes match “\(q)”")
                        .foregroundStyle(.secondary)
                        .padding(14)
                }
                ForEach(found) { n in
                    Button { state.openFromSearch(n.id) } label: {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(n.title.isEmpty ? "Untitled" : n.title)
                                .font(.headline)
                                .lineLimit(1)
                            Text(snippet(n.plain, q))
                                .font(.callout)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 9)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    Divider()
                }
            }
        }
        .background(state.appearanceMode == .dark ? Color.black : Color(nsColor: .windowBackgroundColor))
    }

    private func snippet(_ text: String, _ q: String) -> String {
        let flat = text.replacingOccurrences(of: "\n", with: " ")
        guard let r = flat.range(of: q, options: [.caseInsensitive, .diacriticInsensitive]) else {
            return String(flat.prefix(100))
        }
        let start = flat.index(r.lowerBound, offsetBy: -40, limitedBy: flat.startIndex) ?? flat.startIndex
        let end = flat.index(r.upperBound, offsetBy: 60, limitedBy: flat.endIndex) ?? flat.endIndex
        let middle = String(flat[start..<end])
        return (start > flat.startIndex ? "…" : "") + middle + (end < flat.endIndex ? "…" : "")
    }

    // MARK: Footer
    private var footer: some View {
        ViewThatFits(in: .horizontal) {
            footerRow(showCounts: true, opacityWidth: 70)
            footerRow(showCounts: false, opacityWidth: 48)
        }
        .buttonStyle(.borderless)
        .font(.callout)
        .padding(10)
    }

    private func footerRow(showCounts: Bool, opacityWidth: CGFloat) -> some View {
        let counts = state.currentCounts
        return HStack(spacing: 12) {
            Button { state.editor.insertTimestamp() } label: {
                Image(systemName: "clock").frame(width: 22, height: 20)
            }
            .help("Insert current time")
            .accessibilityLabel("Insert current time")

            shareMenu

            Button(role: .destructive) { state.deleteCurrent() } label: {
                Image(systemName: "trash").frame(width: 22, height: 20)
            }
            .help("Move note to Recently Deleted")

            Spacer(minLength: 6)

            if showCounts {
                Text("\(counts.words) words · \(counts.characters) chars")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .fixedSize()
            }

            if let s = state.status {
                Text(s)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            } else if state.appearanceMode == .grey {
                Image(systemName: "circle.lefthalf.filled").foregroundStyle(.secondary)
                Slider(value: $state.opacity, in: 0.3...1.0)
                    .frame(width: opacityWidth)
                    .help("Grey mode opacity")
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private var shareMenu: some View {
        Menu {
            Button("Copy This Note") {
                state.editor.copyCurrentNote()
                state.flash("Copied")
            }
            Divider()
            Button("Send All to Apple Notes") { state.sendAllToAppleNotes() }
            Button("Email All Notes…") { state.emailAllNotes() }
            Divider()
            Button("Back Up Now") { state.backupNow() }
            Button("Show Backups in Finder") { state.showBackups() }
        } label: {
            Image(systemName: "square.and.arrow.up").frame(width: 22, height: 20)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .help("Share and back up")
        .accessibilityLabel("Share and back up")
    }

    private var panelDivider: some View {
        Rectangle()
            .fill(Color.white.opacity(state.appearanceMode == .dark ? 0.34 : 0.52))
            .frame(height: 1)
    }

    // MARK: Helpers
    private var titleBinding: Binding<String> {
        Binding(
            get: { state.index.map { state.notes[$0].title } ?? "" },
            set: { new in
                guard let i = state.index else { return }
                state.notes[i].title = new
                state.notes[i].updatedAt = Date()
                state.scheduleSave()
            }
        )
    }
}

private enum NoteBrowserMode: String, Identifiable {
    case all
    case deleted

    var id: String { rawValue }
}

private struct NoteBrowserView: View {
    @EnvironmentObject var state: AppState
    @Environment(\.dismiss) private var dismiss
    let mode: NoteBrowserMode

    private let columns = [GridItem(.adaptive(minimum: 155, maximum: 205), spacing: 16)]

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(mode == .all ? "All Notes" : "Recently Deleted")
                    .font(.title2.bold())
                Spacer()
                if mode == .deleted && !state.deletedNotes.isEmpty {
                    Text("\(state.deletedNotes.count) item\(state.deletedNotes.count == 1 ? "" : "s")")
                        .foregroundStyle(.secondary)
                }
                Button { dismiss() } label: { Image(systemName: "xmark.circle.fill") }
                    .buttonStyle(.borderless)
                    .font(.title3)
                    .help("Close")
            }
            .padding(18)

            Divider()

            ScrollView {
                if mode == .deleted && state.deletedNotes.isEmpty {
                    VStack(spacing: 10) {
                        Image(systemName: "trash").font(.system(size: 32))
                        Text("Recently Deleted is empty").font(.headline)
                    }
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 260)
                } else {
                    LazyVGrid(columns: columns, spacing: 16) {
                        if mode == .all {
                            ForEach(state.notes) { note in allNoteCard(note) }
                        } else {
                            ForEach(state.deletedNotes) { item in deletedNoteCard(item) }
                        }
                    }
                    .padding(18)
                }
            }
        }
        .frame(minWidth: 560, idealWidth: 700, minHeight: 390, idealHeight: 500)
        .background(state.appearanceMode == .dark ? Color.black : Color(nsColor: .windowBackgroundColor))
        .preferredColorScheme(state.appearanceMode == .dark ? .dark : nil)
    }

    private func allNoteCard(_ note: Note) -> some View {
        Button {
            state.selectedID = note.id
            dismiss()
            DispatchQueue.main.async { state.editor.focus() }
        } label: {
            noteCard(note)
        }
        .buttonStyle(.plain)
        .help("Open \(displayTitle(note))")
    }

    private func deletedNoteCard(_ item: DeletedNote) -> some View {
        VStack(spacing: 8) {
            noteCard(item.note)
            HStack {
                Button("Restore") {
                    state.restoreDeleted(item.id)
                    dismiss()
                }
                Spacer()
                Button(role: .destructive) {
                    state.permanentlyDelete(item.id)
                } label: {
                    Image(systemName: "trash.slash")
                }
                .help("Delete permanently")
            }
            .buttonStyle(.borderless)
            .padding(.horizontal, 4)
        }
    }

    private func noteCard(_ note: Note) -> some View {
        VStack(spacing: 0) {
            Text(preview(note))
                .font(.callout)
                .foregroundStyle(.secondary)
                .lineLimit(6)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(12)

            Rectangle().fill(Color.white.opacity(0.3)).frame(height: 1)

            Text(displayTitle(note))
                .font(.headline)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
        }
        .frame(height: 160)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(state.appearanceMode == .dark ? Color.white.opacity(0.08) : Color.primary.opacity(0.065))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.white.opacity(state.appearanceMode == .dark ? 0.22 : 0.45), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func displayTitle(_ note: Note) -> String {
        note.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Untitled" : note.title
    }

    private func preview(_ note: Note) -> String {
        let text = note.plain.trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? "No text" : text
    }
}

private struct CollapsedDotView: View {
    @EnvironmentObject var state: AppState
    let expand: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: expand) {
            ZStack {
                Group {
                    if state.appearanceMode == .dark {
                        Circle().fill(Color.black)
                    } else {
                        Circle().fill(.regularMaterial)
                    }
                }
                .shadow(color: .black.opacity(0.22), radius: 8, y: 3)
                Circle()
                    .stroke(Color.accentColor.opacity(hovering ? 0.9 : 0.55), lineWidth: 2)
                    .padding(4)
                Circle()
                    .fill(Color.accentColor)
                    .frame(width: hovering ? 13 : 10, height: hovering ? 13 : 10)
                ForEach(0..<3, id: \.self) { index in
                    Circle()
                        .fill(Color.accentColor.opacity(0.72))
                        .frame(width: 4, height: 4)
                        .offset(y: -15)
                        .rotationEffect(.degrees(Double(index) * 120 + (hovering ? 60 : 0)))
                }
            }
            .padding(3)
            .contentShape(Circle())
            .scaleEffect(hovering ? 1.06 : 1)
        }
        .buttonStyle(.plain)
        .help("Open SideNotes")
        .onHover { hovering = $0 }
        .animation(.spring(response: 0.28, dampingFraction: 0.68), value: hovering)
        .padding(3)
    }
}
