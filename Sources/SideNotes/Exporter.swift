import AppKit

enum Exporter {
    static func escape(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }

    /// Turns every non-ASCII character into an HTML entity (keeps the AppleScript pure ASCII)
    static func asciiHTML(_ s: String) -> String {
        var out = ""
        for u in s.unicodeScalars {
            if u.isASCII { out.unicodeScalars.append(u) } else { out += "&#\(u.value);" }
        }
        return out
    }

    static func bodyHTML(_ s: NSAttributedString) -> String {
        var html = ""
        let ns = s.string as NSString
        s.enumerateAttributes(in: NSRange(location: 0, length: s.length)) { attrs, r, _ in
            if let a = attrs[.attachment] as? NSTextAttachment {
                if DividerUtil.isDivider(a) {
                    html += "<hr>"
                } else if let img = ImageUtil.htmlData(a) {
                    html += "<img src=\"data:\(img.1);base64,\(img.0.base64EncodedString())\" width=\"\(Int(ImageUtil.width(a)))\" style=\"max-width:100%;height:auto\">"
                }
                return
            }
            var t = escape(ns.substring(with: r)).replacingOccurrences(of: "\n", with: "<br>")
            if TextStyle.has(.bold, attrs) { t = "<b>\(t)</b>" }
            if TextStyle.has(.italic, attrs) { t = "<i>\(t)</i>" }
            if TextStyle.has(.underline, attrs) { t = "<u>\(t)</u>" }
            if TextStyle.has(.strike, attrs) { t = "<s>\(t)</s>" }
            if let font = attrs[.font] as? NSFont {
                let size = TextSize.closest(to: font.pointSize)
                if size != .medium { t = "<span style=\"font-size:\(Int(size.rawValue))px\">\(t)</span>" }
            }
            if let l = attrs[.link] {
                let href = (l as? URL)?.absoluteString ?? "\(l)"
                t = "<a href=\"\(escape(href))\">\(t)</a>"
            }
            html += t
        }
        return html
    }

    static func document(_ notes: [Note], _ doc: (Note) -> NSAttributedString) -> String {
        let df = DateFormatter()
        df.dateStyle = .medium
        df.timeStyle = .short
        var out = """
        <!doctype html><html><head><meta charset="utf-8"><title>SideNotes</title>
        <style>body{font:15px -apple-system,Helvetica,sans-serif;max-width:760px;margin:40px auto;padding:0 16px;line-height:1.5;color:#222}
        article{border-bottom:1px solid #ddd;padding:16px 0 28px}h2{margin:0 0 4px}.d{color:#888;font-size:12px;margin-bottom:12px}
        img{border-radius:6px;margin:6px 0}</style></head><body><h1>SideNotes</h1>
        """
        for n in notes {
            let title = n.title.isEmpty ? "Untitled" : n.title
            out += "<article><h2>\(escape(title))</h2><div class=\"d\">\(df.string(from: n.updatedAt))</div><div>\(bodyHTML(doc(n)))</div></article>\n"
        }
        return out + "</body></html>"
    }
}

// MARK: - Backups, email, Apple Notes

extension AppState {
    private static let lastBackupKey = "SideNotesLastBackup"

    func autoBackupIfDue() {
        let last = UserDefaults.standard.object(forKey: Self.lastBackupKey) as? Date ?? .distantPast
        if Date().timeIntervalSince(last) > 24 * 3600 { writeBackup() }
    }

    /// Writes a readable HTML copy (with images) + a raw JSON copy. Keeps the newest 30 of each.
    @discardableResult
    func writeBackup() -> URL? {
        let fm = FileManager.default
        try? fm.createDirectory(at: backupsDir, withIntermediateDirectories: true)
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd HHmm"
        let stamp = df.string(from: Date())
        let html = backupsDir.appendingPathComponent("SideNotes \(stamp).html")
        let json = backupsDir.appendingPathComponent("notes \(stamp).json")
        let doc = Exporter.document(notes) { self.document(for: $0.id) }
        do { try doc.write(to: html, atomically: true, encoding: .utf8) } catch { return nil }
        try? fm.removeItem(at: json)
        try? fm.copyItem(at: url, to: json)
        UserDefaults.standard.set(Date(), forKey: Self.lastBackupKey)

        if let files = try? fm.contentsOfDirectory(at: backupsDir, includingPropertiesForKeys: nil) {
            for e in ["html", "json"] {
                let list = files.filter { $0.pathExtension == e }.sorted { $0.lastPathComponent > $1.lastPathComponent }
                for old in list.dropFirst(30) { try? fm.removeItem(at: old) }
            }
        }
        return html
    }

    func backupNow() {
        saveNow()
        if writeBackup() != nil { flash("Backed up \(notes.count) notes") } else { flash("Backup failed") }
    }

    func showBackups() {
        try? FileManager.default.createDirectory(at: backupsDir, withIntermediateDirectories: true)
        NSWorkspace.shared.open(backupsDir)
    }

    func emailAllNotes() {
        saveNow()
        guard let file = writeBackup() else { flash("Couldn't prepare the notes file"); return }
        guard let svc = NSSharingService(named: .composeEmail) else { flash("Mail isn't set up on this Mac"); return }
        let df = DateFormatter()
        df.dateStyle = .medium
        svc.subject = "SideNotes – \(notes.count) notes – \(df.string(from: Date()))"
        let text = notes.map { "\($0.title.isEmpty ? "Untitled" : $0.title)\n\n\($0.plain)" }
            .joined(separator: "\n\n———\n\n")
        let body = text + "\n\n(The attached file has every note with its formatting and images.)"
        let items: [Any] = [body, file]
        guard svc.canPerform(withItems: items) else { flash("Mail isn't set up on this Mac"); return }
        hide()
        svc.perform(withItems: items)
    }

    /// Mirrors every note into a "SideNotes" folder in Apple Notes (that folder is replaced each time).
    func sendAllToAppleNotes() {
        saveNow()
        func q(_ s: String) -> String {
            "\"" + s.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\""
        }
        var lines = [
            "tell application \"Notes\"",
            "set acc to default account",
            "if not (exists folder \"SideNotes\" of acc) then make new folder at acc with properties {name:\"SideNotes\"}",
            "set f to folder \"SideNotes\" of acc",
            "delete every note of f",
        ]
        for n in notes.reversed() {
            let title = n.title.isEmpty ? "Untitled" : n.title
            let body = Exporter.asciiHTML("<h1>\(Exporter.escape(title))</h1>" + Exporter.bodyHTML(document(for: n.id)))
            lines.append("make new note at f with properties {body:\(q(body))}")
        }
        lines.append("end tell")
        let script = lines.joined(separator: "\n")
        let count = notes.count
        flash("Sending to Apple Notes…")

        DispatchQueue.global(qos: .userInitiated).async {
            let fm = FileManager.default
            let tmp = fm.temporaryDirectory.appendingPathComponent("sidenotes-\(UUID().uuidString).applescript")
            var ok = false
            var err = ""
            do {
                try script.write(to: tmp, atomically: true, encoding: .utf8)
                let p = Process()
                p.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
                p.arguments = [tmp.path]
                let errPipe = Pipe()
                p.standardError = errPipe
                p.standardOutput = Pipe()
                try p.run()
                let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
                p.waitUntilExit()
                ok = p.terminationStatus == 0
                err = String(data: errData, encoding: .utf8) ?? ""
            } catch {
                err = error.localizedDescription
            }
            try? fm.removeItem(at: tmp)
            DispatchQueue.main.async {
                if ok { self.flash("Sent \(count) notes to Apple Notes › SideNotes") }
                else if err.contains("-1743") { self.flash("Allow SideNotes under Privacy & Security › Automation") }
                else { self.flash("Apple Notes: \(err.trimmingCharacters(in: .whitespacesAndNewlines).prefix(90))") }
            }
        }
    }
}
