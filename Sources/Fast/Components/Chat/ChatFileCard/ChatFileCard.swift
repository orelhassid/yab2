import AppKit
import PDFKit
import QuickLookThumbnailing
import SwiftUI
import UniformTypeIdentifiers

// A file a turn gave you, as Grok shows one under its answer: the file's
// first page, its name, what is in it and how big ("3 pages · 570 KB"),
// and the folder it is in. A page an agent saved (save_page, pdf), a
// download it made, a file it sent (SendUserFile). A click looks at it in
// Quick Look over Yab, a drag takes it out as the file, right-click opens
// it or shows it in Finder. Concept: artifact FUTYbRZ6dHjMa3XRwTa52p.

/// The files, a card each, one under another.
struct ChatFileCards: View {
    let paths: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(paths, id: \.self) { ChatFileCard(path: $0, group: paths) }
        }
        .background { ChatQuickLookAnchorView() }
    }
}

struct ChatFileCard: View {
    let path: String
    /// The turn's files, for ← and → in Quick Look.
    let group: [String]
    /// What is already known of it (a test's picture); read when nil.
    var preread: About? = nil
    @State private var about: About?
    @State private var hovering = false
    @FocusState private var focused: Bool

    /// As wide as its name, up to this.
    static let width: CGFloat = 300

    private var url: URL { URL(fileURLWithPath: AgentLines.localPath(path)) }

    var body: some View {
        let known = about ?? preread
        let there = known?.there ?? true
        // Gone, only what is in the card fades: the card itself stays
        // opaque, or the black its shadow is cast from shows through.
        return framed(row(known, there: there).opacity(there ? 1 : 0.55), there: there)
            .accessibilityElement(children: .combine)
            .accessibilityLabel(url.lastPathComponent + (known.map { ", " + $0.line } ?? ""))
            .accessibilityAddTraits(.isButton)
            .task(id: path) {
                if let preread { about = preread } else { about = await About.read(url) }
            }
    }

    private func row(_ known: About?, there: Bool) -> some View {
        HStack(spacing: CardFrame.wellGap) {
            thumb
            VStack(alignment: .leading, spacing: 1) {
                Text(url.lastPathComponent)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Palette.ink)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(there ? known?.line ?? " " : "Moved or deleted")
                    .font(.system(size: 12))
                    .foregroundStyle(Palette.muted)
                    .monospacedDigit()
                    .lineLimit(1)
            }
            if there {
                Button { NSWorkspace.shared.activateFileViewerSelecting([url]) } label: { Symbol("folder", size: 14) }
                    .buttonStyle(.yab(.quiet, .regular, icon: .square))
                    .keyTip("Show in Finder · " + Self.place(url.deletingLastPathComponent()))
            }
        }
    }

    private func framed(_ row: some View, there: Bool) -> some View {
        let shape = RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
        return row
            .restingCardFrame()
            .overlay {
                // Under the pointer the edge darkens a little; nothing moves.
                shape.strokeBorder(Palette.hairline, lineWidth: 1) // design: a second hairline over restingCardFrame's, the edge under the pointer
                    .opacity((hovering || focused) && there ? 1 : 0)
            }
            .contentShape(shape)
            .onHover { hovering = $0 }
            .onTapGesture { if there { look() } }
            // Focused, Space looks at it too, as in Finder.
            .focusable()
            .focused($focused)
            .focusEffectDisabled()
            .onKeyPress(.space) {
                guard there else { return .ignored }
                look()
                return .handled
            }
            .onDrag { there ? NSItemProvider(contentsOf: url) ?? NSItemProvider() : NSItemProvider() }
            .contextMenu { if there { menu } }
            // Its own width, its name's, never more: the room past it is
            // the turn's, not the card's.
            .frame(maxWidth: Self.width, alignment: .leading)
    }

    @ViewBuilder private var menu: some View {
        Button("Open") { NSWorkspace.shared.open(url) }
        Button("Show in Finder", mark: "yab.folder.search") { NSWorkspace.shared.activateFileViewerSelecting([url]) }
        Button("Copy") {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.writeObjects([url as NSURL])
        }
    }

    /// Quick Look over Yab, ← and → walking the turn's files.
    private func look() {
        let all = group.map { URL(fileURLWithPath: AgentLines.localPath($0)) }
        ChatQuickLook.shared.show(all, at: all.firstIndex(of: url) ?? 0)
    }

    /// The file's first page, the corner of a control, a band at its foot
    /// with the format in its own color. A picture is its own thumb.
    private var thumb: some View {
        let shape = RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
        let format = Self.format(url)
        return Color.white
            .overlay {
                if let image = (about ?? preread)?.thumb {
                    Image(nsImage: image).resizable().aspectRatio(contentMode: .fill)
                        .frame(width: CardFrame.well, height: CardFrame.well, alignment: .top)
                }
            }
            .overlay(alignment: .bottom) {
                if let format {
                    Text(format.word)
                        .font(.system(size: 7, weight: .bold)) // design: the format on a 40 pt page's foot, as Finder's document icons print it
                        .tracking(0.3)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity, minHeight: 11)
                        .background(format.color)
                }
            }
            .frame(width: CardFrame.well, height: CardFrame.well)
            .clipShape(shape)
            .overlay(shape.strokeBorder(Color.black.opacity(0.08), lineWidth: 1)) // design: the page's own edge on white, both themes
    }

    /// The word on a thumb's band and its color, by what the file is.
    static func format(_ url: URL) -> (word: String, color: Color)? {
        switch url.pathExtension.lowercased() {
        case "pdf": ("PDF", Color(red: 0.90, green: 0.28, blue: 0.23))
        case "html", "htm": ("HTML", Color(red: 0.91, green: 0.51, blue: 0.23))
        case "webarchive": ("ARCHIVE", Color(red: 0.23, green: 0.48, blue: 0.91))
        case "md", "markdown": ("MD", Color(red: 0.36, green: 0.39, blue: 0.44))
        case "txt": ("TXT", Color(red: 0.54, green: 0.56, blue: 0.60))
        case "csv", "tsv": (url.pathExtension.uppercased(), Color(red: 0.13, green: 0.60, blue: 0.33))
        case "ics": ("ICS", Color(red: 0.58, green: 0.36, blue: 0.85))
        case "json": ("JSON", Color(red: 0.80, green: 0.58, blue: 0.10))
        case "png", "jpg", "jpeg", "gif", "webp", "heic": nil
        case "": nil
        default: (String(url.pathExtension.uppercased().prefix(7)), Color(red: 0.54, green: 0.56, blue: 0.60))
        }
    }

    /// "Downloads › yab": the folder, said as a person finds it.
    static func place(_ folder: URL) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let parts = folder.path.replacingOccurrences(of: home + "/", with: "").split(separator: "/").map(String.init)
        return parts.prefix(2).joined(separator: " › ")
    }

    /// What the card says about its file, read off main.
    struct About: Equatable {
        var there: Bool
        var line: String
        var thumb: NSImage?

        static func read(_ url: URL) async -> About {
            let line = await Task.detached(priority: .utility) { () -> String? in
                guard FileManager.default.fileExists(atPath: url.path) else { return nil }
                return Self.line(url)
            }.value
            guard let line else { return About(there: false, line: "") }
            let request = QLThumbnailGenerator.Request(fileAt: url, size: CGSize(width: CardFrame.well, height: CardFrame.well),
                                                       scale: 2, representationTypes: .thumbnail)
            let thumb = try? await QLThumbnailGenerator.shared.generateBestRepresentation(for: request)
            return About(there: true, line: line, thumb: thumb?.nsImage)
        }

        /// "3 pages · 570 KB", "Web Archive · 2.4 MB", "2,140 words · 14 KB",
        /// "1600 × 9120 · 3.1 MB", "48 rows · 3 KB", "4 events · 2 KB".
        nonisolated static func line(_ url: URL) -> String {
            let bytes = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            let size = ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
            let what: String
            switch url.pathExtension.lowercased() {
            case "pdf":
                let pages = PDFDocument(url: url)?.pageCount ?? 0
                what = pages == 1 ? "1 page" : "\(pages) pages"
            case "md", "markdown", "txt":
                let text = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
                let count = text.split(whereSeparator: { $0.isWhitespace }).count
                what = (count.formatted(.number)) + (count == 1 ? " word" : " words")
            case "html", "htm":
                what = "HTML page"
            case "webarchive":
                what = "Web Archive"
            case "csv", "tsv", "ics", "json":
                // What save_file made: "48 rows", "4 events", "12 items".
                what = SaveFile.counted(url) ?? UTType(filenameExtension: url.pathExtension)?.localizedDescription ?? "File"
            default:
                if let source = CGImageSourceCreateWithURL(url as CFURL, nil),
                   let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
                   let w = props[kCGImagePropertyPixelWidth] as? Int, let h = props[kCGImagePropertyPixelHeight] as? Int {
                    what = "\(w) × \(h)"
                } else {
                    what = UTType(filenameExtension: url.pathExtension)?.localizedDescription ?? "File"
                }
            }
            return what + " · " + size
        }
    }
}
