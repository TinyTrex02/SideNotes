import AppKit
import SwiftUI
import UniformTypeIdentifiers

extension Notification.Name {
    static let focusSearch = Notification.Name("SideNotesFocusSearch")
}

extension NSAttributedString.Key {
    /// Marks images that have already been sized/compressed
    static let snImageDone = NSAttributedString.Key("SideNotesImageDone")
}

enum Format { case bold, italic, underline, strike }

// MARK: - Text style

enum TextStyle {
    static let baseSize: CGFloat = 14
    static var baseFont: NSFont { .systemFont(ofSize: baseSize) }
    static var defaultAttributes: [NSAttributedString.Key: Any] {
        [.font: baseFont, .foregroundColor: NSColor.textColor]
    }

    static func font(_ f: NSFont, _ trait: NSFontDescriptor.SymbolicTraits, _ on: Bool) -> NSFont {
        var t = f.fontDescriptor.symbolicTraits
        if on { t.insert(trait) } else { t.remove(trait) }
        return NSFont(descriptor: f.fontDescriptor.withSymbolicTraits(t), size: f.pointSize) ?? f
    }

    static func has(_ f: Format, _ attrs: [NSAttributedString.Key: Any]) -> Bool {
        switch f {
        case .bold: return (attrs[.font] as? NSFont)?.fontDescriptor.symbolicTraits.contains(.bold) ?? false
        case .italic: return (attrs[.font] as? NSFont)?.fontDescriptor.symbolicTraits.contains(.italic) ?? false
        case .underline: return ((attrs[.underlineStyle] as? Int) ?? 0) != 0
        case .strike: return ((attrs[.strikethroughStyle] as? Int) ?? 0) != 0
        }
    }

    /// Keeps only what SideNotes supports: bold, italic, underline, strikethrough, links, images.
    /// Everything else (fonts, sizes, colours from web pages) is reset to the note style.
    static func sanitize(_ s: NSAttributedString) -> NSMutableAttributedString {
        let out = NSMutableAttributedString(string: s.string, attributes: defaultAttributes)
        s.enumerateAttributes(in: NSRange(location: 0, length: s.length)) { attrs, r, _ in
            if let f = attrs[.font] as? NSFont {
                let t = f.fontDescriptor.symbolicTraits
                var nf = baseFont
                if t.contains(.bold) { nf = font(nf, .bold, true) }
                if t.contains(.italic) { nf = font(nf, .italic, true) }
                out.addAttribute(.font, value: nf, range: r)
            }
            if has(.underline, attrs) { out.addAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue, range: r) }
            if has(.strike, attrs) { out.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: r) }
            if let l = attrs[.link] { out.addAttribute(.link, value: l, range: r) }
            if let a = attrs[.attachment] { out.addAttribute(.attachment, value: a, range: r) }
        }
        return out
    }
}

// MARK: - Images

enum ImageUtil {
    static let defaultMax: CGFloat = 340
    private static let cache = NSMapTable<NSTextAttachment, NSImage>.weakToStrongObjects()

    static func image(of a: NSTextAttachment) -> NSImage? {
        if let c = cache.object(forKey: a) { return c }
        var img: NSImage?
        if let fw = a.fileWrapper {
            if fw.isRegularFile, let d = fw.regularFileContents { img = NSImage(data: d) }
        } else if let i = a.image {
            img = i
        } else if let cell = a.attachmentCell as? NSCell {
            img = cell.image
        }
        if let img { cache.setObject(img, forKey: a) }
        return img
    }

    static func width(_ a: NSTextAttachment) -> CGFloat {
        a.attachmentCell?.cellSize().width ?? a.bounds.width
    }

    static func setWidth(_ a: NSTextAttachment, _ w: CGFloat, base: NSImage) {
        guard base.size.width > 0 else { return }
        let width = max(24, w.rounded())
        let size = NSSize(width: width, height: (width * base.size.height / base.size.width).rounded())
        let img = (base.copy() as? NSImage) ?? base
        img.size = size
        a.attachmentCell = NSTextAttachmentCell(imageCell: img)
        a.bounds = NSRect(origin: .zero, size: size)
    }

    static func pixelSize(_ img: NSImage) -> NSSize {
        let px = img.representations
            .map { NSSize(width: $0.pixelsWide, height: $0.pixelsHigh) }
            .filter { $0.width > 0 && $0.height > 0 }
            .max { $0.width < $1.width }
        return px ?? NSSize(width: img.size.width * 2, height: img.size.height * 2)
    }

    static func bitmap(_ img: NSImage, maxPixels: CGFloat) -> NSBitmapImageRep? {
        let px = pixelSize(img)
        guard px.width > 0, px.height > 0 else { return nil }
        let scale = min(1, maxPixels / max(px.width, px.height))
        let tw = max(1, Int(px.width * scale)), th = max(1, Int(px.height * scale))
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: tw, pixelsHigh: th,
                                         bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                         colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { return nil }
        rep.size = NSSize(width: tw, height: th)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        img.draw(in: NSRect(x: 0, y: 0, width: tw, height: th), from: .zero, operation: .copy, fraction: 1)
        NSGraphicsContext.restoreGraphicsState()
        return rep
    }

    private static func ext(_ fw: FileWrapper) -> String {
        ((fw.preferredFilename ?? fw.filename ?? "") as NSString).pathExtension.lowercased()
    }

    /// Returns a compact PNG/JPEG file for the image, or nil if the current file is already fine.
    static func storableWrapper(for a: NSTextAttachment, image: NSImage) -> FileWrapper? {
        if let fw = a.fileWrapper, fw.isRegularFile, let d = fw.regularFileContents,
           ["png", "jpg", "jpeg", "gif"].contains(ext(fw)), d.count <= 3_000_000 {
            return nil
        }
        guard let rep = bitmap(image, maxPixels: 2400) else { return nil }
        var data = rep.representation(using: .png, properties: [:])
        var e = "png"
        if data == nil || data!.count > 1_500_000,
           let jpg = rep.representation(using: .jpeg, properties: [.compressionFactor: 0.85]) {
            data = jpg
            e = "jpg"
        }
        guard let out = data else { return nil }
        let fw = FileWrapper(regularFileWithContents: out)
        fw.preferredFilename = "image-\(UUID().uuidString.prefix(8)).\(e)"
        return fw
    }

    /// Image bytes + MIME type for HTML export
    static func htmlData(_ a: NSTextAttachment) -> (Data, String)? {
        if let fw = a.fileWrapper, fw.isRegularFile, let d = fw.regularFileContents {
            switch ext(fw) {
            case "png": return (d, "image/png")
            case "jpg", "jpeg": return (d, "image/jpeg")
            case "gif": return (d, "image/gif")
            default: break
            }
        }
        guard let img = image(of: a), let rep = bitmap(img, maxPixels: 2400),
              let d = rep.representation(using: .png, properties: [:]) else { return nil }
        return (d, "image/png")
    }
}

// MARK: - Saving / loading rich text

enum NoteCodec {
    static func attachments(in s: NSAttributedString) -> [(NSTextAttachment, NSRange)] {
        var out: [(NSTextAttachment, NSRange)] = []
        s.enumerateAttribute(.attachment, in: NSRange(location: 0, length: s.length)) { v, r, _ in
            if let a = v as? NSTextAttachment { out.append((a, r)) }
        }
        return out
    }

    static func encode(_ s: NSAttributedString) -> (Data?, [Double]) {
        let widths = attachments(in: s).map { Double(ImageUtil.width($0.0)) }
        let data = s.rtfd(from: NSRange(location: 0, length: s.length),
                          documentAttributes: [.documentType: NSAttributedString.DocumentType.rtfd])
        return (data, widths)
    }

    static func decode(_ n: Note) -> NSAttributedString {
        var raw = NSAttributedString(string: n.plain)
        if let d = n.rtfd, let s = NSAttributedString(rtfd: d, documentAttributes: nil) { raw = s }
        let s = TextStyle.sanitize(raw)
        for (i, item) in attachments(in: s).enumerated() {
            let (a, r) = item
            if let img = ImageUtil.image(of: a) {
                let saved = i < n.imageWidths.count ? n.imageWidths[i] : 0
                let w = saved > 0 ? CGFloat(saved) : min(img.size.width, ImageUtil.defaultMax)
                ImageUtil.setWidth(a, w, base: img)
            }
            s.addAttribute(.snImageDone, value: true, range: r)
        }
        return s
    }
}

// MARK: - Text view

final class NoteTextView: NSTextView {
    var onFormat: ((Format) -> Void)?

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard window?.firstResponder === self else { return super.performKeyEquivalent(with: event) }
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard flags.contains(.command), !flags.contains(.control), !flags.contains(.option),
              let key = event.charactersIgnoringModifiers?.lowercased() else {
            return super.performKeyEquivalent(with: event)
        }
        let shift = flags.contains(.shift)
        switch key {
        case "b": onFormat?(.bold); return true
        case "i": onFormat?(.italic); return true
        case "u": onFormat?(.underline); return true
        case "x" where shift: onFormat?(.strike); return true
        case "x": cut(nil); return true
        case "c": copy(nil); return true
        case "v": paste(nil); return true
        case "a": selectAll(nil); return true
        case "z":
            if shift { undoManager?.redo() } else { undoManager?.undo() }
            return true
        case "f":
            NotificationCenter.default.post(name: .focusSearch, object: nil)
            return true
        default:
            return super.performKeyEquivalent(with: event)
        }
    }

    /// Paste keeps bold/italic/underline/strike, links and images, but drops foreign fonts and colours.
    override func paste(_ sender: Any?) {
        let pb = NSPasteboard.general
        let types = pb.types ?? []
        let hasString = types.contains(.string)
        let hasImage = types.contains(.tiff) || types.contains(.png)
        let hasRich = types.contains(.rtfd) || types.contains(.rtf) || types.contains(.html)
            || types.contains(NSPasteboard.PasteboardType("com.apple.flat-rtfd"))

        if hasImage && !hasString { super.paste(sender); return }
        if hasRich,
           let attr = pb.readObjects(forClasses: [NSAttributedString.self], options: nil)?.first as? NSAttributedString,
           attr.length > 0 {
            insertText(TextStyle.sanitize(attr), replacementRange: selectedRange())
            return
        }
        super.paste(sender)
    }

    // Esc hides the panel instead of triggering autocomplete
    override func cancelOperation(_ sender: Any?) { window?.cancelOperation(sender) }
}

// MARK: - Editor controller

final class EditorController: NSObject, NSTextViewDelegate {
    weak var state: AppState?
    let textView: NoteTextView
    let scrollView: NSScrollView
    private(set) var noteID: UUID?

    override init() {
        // Explicit TextKit 1 stack so image sizing behaves predictably
        let storage = NSTextStorage()
        let layout = NSLayoutManager()
        storage.addLayoutManager(layout)
        let container = NSTextContainer(containerSize: NSSize(width: 380, height: CGFloat.greatestFiniteMagnitude))
        container.widthTracksTextView = true
        layout.addTextContainer(container)

        let tv = NoteTextView(frame: NSRect(x: 0, y: 0, width: 380, height: 600), textContainer: container)
        tv.minSize = NSSize(width: 0, height: 0)
        tv.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        tv.isVerticallyResizable = true
        tv.isHorizontallyResizable = false
        tv.autoresizingMask = [.width]
        tv.isRichText = true
        tv.importsGraphics = true
        tv.allowsUndo = true
        tv.drawsBackground = false
        tv.textContainerInset = NSSize(width: 8, height: 10)
        tv.typingAttributes = TextStyle.defaultAttributes
        textView = tv

        let sv = NSScrollView(frame: NSRect(x: 0, y: 0, width: 380, height: 600))
        sv.hasVerticalScroller = true
        sv.autohidesScrollers = true
        sv.drawsBackground = false
        sv.documentView = tv
        scrollView = sv

        super.init()
        tv.delegate = self
        tv.onFormat = { [weak self] f in self?.apply(f) }
    }

    private var storage: NSTextStorage { textView.textStorage! }

    var maxImageWidth: CGFloat {
        let w = textView.textContainer?.containerSize.width ?? 0
        let pad = (textView.textContainer?.lineFragmentPadding ?? 5) * 2
        return w > 100 ? w - pad - 4 : ImageUtil.defaultMax
    }

    func focus() { textView.window?.makeFirstResponder(textView) }

    func show(_ id: UUID?) {
        guard id != noteID else { return }
        noteID = id
        let doc = id.flatMap { state?.document(for: $0) } ?? NSAttributedString()
        storage.setAttributedString(doc)
        textView.typingAttributes = TextStyle.defaultAttributes
        textView.undoManager?.removeAllActions()
        textView.setSelectedRange(NSRange(location: 0, length: 0))
        textView.scrollRangeToVisible(NSRange(location: 0, length: 0))
        refreshImageSelection()
    }

    // MARK: Delegate

    func textDidChange(_ notification: Notification) {
        normalizeNewImages()
        push()
    }

    func textViewDidChangeSelection(_ notification: Notification) {
        refreshImageSelection()
    }

    private func push() {
        guard let id = noteID else { return }
        state?.bodyChanged(id, NSAttributedString(attributedString: storage))
    }

    /// New images (pasted, dropped, inserted) get compressed and fitted to the panel width
    private func normalizeNewImages() {
        let pending = NoteCodec.attachments(in: storage).filter {
            storage.attribute(.snImageDone, at: $0.1.location, effectiveRange: nil) == nil
        }
        guard !pending.isEmpty else { return }
        storage.beginEditing()
        for (a, r) in pending {
            if let img = ImageUtil.image(of: a) {
                if let fw = ImageUtil.storableWrapper(for: a, image: img) { a.fileWrapper = fw }
                ImageUtil.setWidth(a, min(img.size.width, maxImageWidth), base: img)
                storage.addAttribute(.attachment, value: a, range: r)
            }
            storage.addAttribute(.snImageDone, value: true, range: r)
        }
        storage.endEditing()
    }

    // MARK: Formatting

    func apply(_ f: Format) {
        let r = textView.selectedRange()
        if r.length == 0 {
            var attrs = textView.typingAttributes
            switch f {
            case .bold, .italic:
                let trait: NSFontDescriptor.SymbolicTraits = f == .bold ? .bold : .italic
                let font = (attrs[.font] as? NSFont) ?? TextStyle.baseFont
                attrs[.font] = TextStyle.font(font, trait, !font.fontDescriptor.symbolicTraits.contains(trait))
            case .underline, .strike:
                let key: NSAttributedString.Key = f == .underline ? .underlineStyle : .strikethroughStyle
                if TextStyle.has(f, attrs) { attrs.removeValue(forKey: key) }
                else { attrs[key] = NSUnderlineStyle.single.rawValue }
            }
            textView.typingAttributes = attrs
            return
        }

        let storage = self.storage
        var allOn = true
        storage.enumerateAttributes(in: r) { attrs, _, stop in
            if !TextStyle.has(f, attrs) { allOn = false; stop.pointee = true }
        }
        guard textView.shouldChangeText(in: r, replacementString: nil) else { return }
        storage.beginEditing()
        switch f {
        case .bold, .italic:
            let trait: NSFontDescriptor.SymbolicTraits = f == .bold ? .bold : .italic
            storage.enumerateAttribute(.font, in: r) { v, sub, _ in
                let font = (v as? NSFont) ?? TextStyle.baseFont
                storage.addAttribute(.font, value: TextStyle.font(font, trait, !allOn), range: sub)
            }
        case .underline, .strike:
            let key: NSAttributedString.Key = f == .underline ? .underlineStyle : .strikethroughStyle
            if allOn { storage.removeAttribute(key, range: r) }
            else { storage.addAttribute(key, value: NSUnderlineStyle.single.rawValue, range: r) }
        }
        storage.endEditing()
        textView.didChangeText()
    }

    // MARK: Images

    func insertImagesFromDisk() {
        guard let window = textView.window else { return }
        let op = NSOpenPanel()
        op.allowedContentTypes = [.image]
        op.allowsMultipleSelection = true
        op.canChooseDirectories = false
        op.message = "Choose images to add to this note"
        op.beginSheetModal(for: window) { [weak self] resp in
            guard resp == .OK, let self else { return }
            let out = NSMutableAttributedString()
            for url in op.urls {
                guard let fw = try? FileWrapper(url: url, options: .immediate) else { continue }
                out.append(NSAttributedString(attachment: NSTextAttachment(fileWrapper: fw)))
                out.append(NSAttributedString(string: "\n", attributes: TextStyle.defaultAttributes))
            }
            guard out.length > 0 else { return }
            window.makeFirstResponder(self.textView)
            self.textView.insertText(out, replacementRange: self.textView.selectedRange())
        }
    }

    /// The image(s) selected, or the image right next to the cursor
    func selectedImages() -> [(NSTextAttachment, NSRange, NSImage)] {
        let sel = textView.selectedRange()
        var ranges: [NSRange] = []
        if sel.length > 0 {
            ranges = [sel]
        } else {
            if sel.location > 0 { ranges.append(NSRange(location: sel.location - 1, length: 1)) }
            if sel.location < storage.length { ranges.append(NSRange(location: sel.location, length: 1)) }
        }
        var out: [(NSTextAttachment, NSRange, NSImage)] = []
        for range in ranges where range.location + range.length <= storage.length {
            storage.enumerateAttribute(.attachment, in: range) { v, r, _ in
                if let a = v as? NSTextAttachment, let img = ImageUtil.image(of: a) { out.append((a, r, img)) }
            }
            if sel.length == 0 && !out.isEmpty { break }
        }
        return out
    }

    func resizeSelectedImages(to w: Double) {
        let items = selectedImages()
        guard !items.isEmpty else { return }
        storage.beginEditing()
        for (a, r, img) in items {
            ImageUtil.setWidth(a, CGFloat(w), base: img)
            storage.addAttribute(.attachment, value: a, range: r)
        }
        storage.endEditing()
        push()
        refreshImageSelection()
    }

    func refreshImageSelection() {
        let w = selectedImages().first.map { Double(ImageUtil.width($0.0)) }
        let m = Double(maxImageWidth)
        DispatchQueue.main.async { [weak self] in
            self?.state?.selectedImageWidth = w
            self?.state?.maxImageWidth = max(m, w ?? 0, 80)
        }
    }

    // MARK: Misc

    func highlight(_ q: String) {
        guard !q.isEmpty else { return }
        let r = (storage.string as NSString).range(of: q, options: [.caseInsensitive, .diacriticInsensitive])
        guard r.location != NSNotFound else { return }
        focus()
        textView.setSelectedRange(r)
        textView.scrollRangeToVisible(r)
        textView.showFindIndicator(for: r)
    }

    func insertTimestamp() {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        let sel = textView.selectedRange()
        let ns = storage.string as NSString
        let atLineStart = sel.location == 0 || ns.character(at: sel.location - 1) == 10
        let text = (atLineStart ? "" : "\n") + "[\(f.string(from: Date()))] "
        focus()
        textView.insertText(text, replacementRange: sel)
    }

    func copyCurrentNote() {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.writeObjects([NSAttributedString(attributedString: storage)])
    }
}

// MARK: - SwiftUI wrapper

struct RichEditor: NSViewRepresentable {
    let controller: EditorController
    let noteID: UUID?

    func makeNSView(context: Context) -> NSScrollView { controller.scrollView }
    func updateNSView(_ nsView: NSScrollView, context: Context) { controller.show(noteID) }
}
