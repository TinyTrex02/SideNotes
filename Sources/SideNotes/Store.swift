import Foundation
import AppKit

struct Note: Identifiable, Codable {
    var id = UUID()
    var title = "Untitled"
    var rtfd: Data? = nil          // rich text + images
    var imageWidths: [Double] = [] // display width of each image, in order
    var plain = ""                 // plain text copy, used for search and email
    var updatedAt = Date()

    init() {}

    enum CodingKeys: String, CodingKey { case id, title, rtfd, imageWidths, plain, updatedAt, body }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        title = try c.decodeIfPresent(String.self, forKey: .title) ?? "Untitled"
        rtfd = try c.decodeIfPresent(Data.self, forKey: .rtfd)
        imageWidths = try c.decodeIfPresent([Double].self, forKey: .imageWidths) ?? []
        if let p = try c.decodeIfPresent(String.self, forKey: .plain) {
            plain = p
        } else {
            // notes saved by the first version only had a plain `body`
            plain = try c.decodeIfPresent(String.self, forKey: .body) ?? ""
        }
        updatedAt = try c.decodeIfPresent(Date.self, forKey: .updatedAt) ?? Date()
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(title, forKey: .title)
        try c.encodeIfPresent(rtfd, forKey: .rtfd)
        try c.encode(imageWidths, forKey: .imageWidths)
        try c.encode(plain, forKey: .plain)
        try c.encode(updatedAt, forKey: .updatedAt)
    }
}

struct DeletedNote: Identifiable, Codable {
    var note: Note
    var deletedAt = Date()

    var id: UUID { note.id }
}

enum AppearanceMode: String, CaseIterable {
    case grey
    case dark

    var title: String { self == .grey ? "Grey mode" : "Dark mode" }
    // The button shows the mode it will switch to.
    var icon: String { self == .grey ? "moon.fill" : "sun.max.fill" }
}

final class AppState: ObservableObject {
    @Published var notes: [Note] = []
    @Published var deletedNotes: [DeletedNote] = []
    @Published var selectedID: UUID?
    @Published var pinned = true       // true = stays on top even when you click elsewhere
    @Published var opacity = 1.0
    @Published var query = ""
    @Published var selectedImageWidth: Double? = nil
    @Published var maxImageWidth: Double = 340
    @Published var status: String? = nil
    @Published var activeFormats = Set<Format>()
    @Published var activeTextSize: TextSize = .medium
    @Published var isCollapsed = false
    @Published var appearanceMode: AppearanceMode {
        didSet { UserDefaults.standard.set(appearanceMode.rawValue, forKey: "appearanceMode") }
    }

    var hide: () -> Void = {}          // set by AppDelegate
    let editor = EditorController()

    private var live: [UUID: NSAttributedString] = [:]
    private var dirty = Set<UUID>()
    private var saveWork: DispatchWorkItem?
    private var statusWork: DispatchWorkItem?

    let dir: URL
    let url: URL
    let deletedURL: URL
    var backupsDir: URL { dir.appendingPathComponent("Backups", isDirectory: true) }

    init() {
        appearanceMode = AppearanceMode(
            rawValue: UserDefaults.standard.string(forKey: "appearanceMode") ?? ""
        ) ?? .grey
        let fm = FileManager.default
        dir = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("SideNotes", isDirectory: true)
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        url = dir.appendingPathComponent("notes.json")
        deletedURL = dir.appendingPathComponent("recently-deleted.json")

        if fm.fileExists(atPath: url.path) {
            if let data = try? Data(contentsOf: url),
               let saved = try? JSONDecoder().decode([Note].self, from: data),
               !saved.isEmpty {
                notes = saved
                // One-time safety copy of the old-format file before the upgrade rewrites it
                let legacy = dir.appendingPathComponent("notes-before-upgrade.json")
                if !fm.fileExists(atPath: legacy.path), saved.allSatisfy({ $0.rtfd == nil }) {
                    try? fm.copyItem(at: url, to: legacy)
                }
            } else {
                // Never silently overwrite a file we couldn't read
                let bad = dir.appendingPathComponent("notes-unreadable-\(Int(Date().timeIntervalSince1970)).json")
                try? fm.copyItem(at: url, to: bad)
            }
        }
        if let data = try? Data(contentsOf: deletedURL),
           let saved = try? JSONDecoder().decode([DeletedNote].self, from: data) {
            deletedNotes = saved
        }
        if notes.isEmpty { notes = [Note()] }
        selectedID = notes.first?.id
        editor.state = self
    }

    var index: Int? { notes.firstIndex { $0.id == selectedID } }

    var currentCounts: (words: Int, characters: Int) {
        guard let i = index else { return (0, 0) }
        let text = notes[i].plain
        var words = 0
        text.enumerateSubstrings(in: text.startIndex..<text.endIndex, options: .byWords) { _, _, _, _ in
            words += 1
        }
        return (words, text.count)
    }

    // MARK: Documents

    func document(for id: UUID) -> NSAttributedString {
        if let d = live[id] { return d }
        guard let n = notes.first(where: { $0.id == id }) else { return NSAttributedString() }
        let d = NoteCodec.decode(n)
        live[id] = d
        return d
    }

    func bodyChanged(_ id: UUID, _ doc: NSAttributedString) {
        live[id] = doc
        dirty.insert(id)
        if let i = notes.firstIndex(where: { $0.id == id }) {
            notes[i].plain = doc.string.replacingOccurrences(of: "\u{FFFC}", with: "")
            notes[i].updatedAt = Date()
        }
        scheduleSave()
    }

    func newNote() {
        let n = Note()
        notes.insert(n, at: 0)
        selectedID = n.id
        scheduleSave()
        DispatchQueue.main.async { self.editor.focus() }
    }

    func deleteCurrent() {
        guard let i = index else { return }
        let id = notes[i].id
        if let doc = live[id] {
            let (data, widths) = NoteCodec.encode(doc)
            notes[i].rtfd = data
            notes[i].imageWidths = widths
            dirty.remove(id)
        }
        deletedNotes.insert(DeletedNote(note: notes[i]), at: 0)
        notes.remove(at: i)
        live[id] = nil
        dirty.remove(id)
        if notes.isEmpty { notes = [Note()] }
        selectedID = notes.first?.id
        scheduleSave()
    }

    func restoreDeleted(_ id: UUID) {
        guard let i = deletedNotes.firstIndex(where: { $0.id == id }) else { return }
        let restored = deletedNotes.remove(at: i).note
        notes.insert(restored, at: 0)
        selectedID = restored.id
        scheduleSave()
        DispatchQueue.main.async { self.editor.focus() }
    }

    func permanentlyDelete(_ id: UUID) {
        deletedNotes.removeAll { $0.id == id }
        scheduleSave()
    }

    // MARK: Saving

    /// Debounced autosave (0.5s after last edit)
    func scheduleSave() {
        saveWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.saveNow() }
        saveWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: work)
    }

    func saveNow() {
        saveWork?.cancel()
        saveWork = nil
        for id in dirty {
            guard let doc = live[id], let i = notes.firstIndex(where: { $0.id == id }) else { continue }
            let (data, widths) = NoteCodec.encode(doc)
            notes[i].rtfd = data
            notes[i].imageWidths = widths
        }
        dirty.removeAll()
        if let data = try? JSONEncoder().encode(notes) {
            try? data.write(to: url, options: .atomic)
        }
        if let data = try? JSONEncoder().encode(deletedNotes) {
            try? data.write(to: deletedURL, options: .atomic)
        }
        autoBackupIfDue()
    }

    // MARK: Search

    var searchResults: [Note] {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return [] }
        return notes.filter { $0.title.localizedStandardContains(q) || $0.plain.localizedStandardContains(q) }
    }

    func openFromSearch(_ id: UUID) {
        let q = query.trimmingCharacters(in: .whitespaces)
        query = ""
        selectedID = id
        DispatchQueue.main.async {
            self.editor.show(id)
            self.editor.highlight(q)
        }
    }

    // MARK: Status line

    func flash(_ message: String) {
        status = message
        statusWork?.cancel()
        let w = DispatchWorkItem { [weak self] in self?.status = nil }
        statusWork = w
        DispatchQueue.main.asyncAfter(deadline: .now() + 4, execute: w)
    }
}
