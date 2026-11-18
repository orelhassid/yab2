import SwiftUI
import ImageIO
import UniformTypeIdentifiers

private func photoKey(_ space: UUID) -> String { "home.photo." + space.uuidString }
private var photos: URL { Store.folder.appendingPathComponent("Home Pictures", isDirectory: true) }

struct HomePhoto: View {
    @AppStorage private var file: String
    @State private var image: NSImage?

    init(space: UUID) {
        _file = AppStorage(wrappedValue: "", photoKey(space), store: Store.settings)
    }

    var body: some View {
        GeometryReader { bounds in
            if let image, !file.isEmpty {
                Image(nsImage: image).resizable().scaledToFill()
                    .frame(width: bounds.size.width, height: bounds.size.height).clipped()
                    .overlay(Palette.stage.opacity(0.68))
            }
        }
        .task(id: file) { image = file.isEmpty ? nil : NSImage(contentsOf: photos.appendingPathComponent(file)) }
        .accessibilityHidden(true)
    }
}

struct HomePhotoMenu: View {
    @AppStorage private var file: String
    @State private var failed = false
    private static let stock = (try? FileManager.default.contentsOfDirectory(
        at: URL(fileURLWithPath: "/System/Library/Desktop Pictures"), includingPropertiesForKeys: nil
    ))?.filter { ["heic", "jpeg", "jpg", "png"].contains($0.pathExtension.lowercased()) }
        .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending } ?? []

    init(space: UUID) {
        _file = AppStorage(wrappedValue: "", photoKey(space), store: Store.settings)
    }

    var body: some View {
        Menu("Background image") {
            Button("Choose from Computer…") {
                let panel = NSOpenPanel()
                panel.allowedContentTypes = [.image]
                if panel.runModal() == .OK, let url = panel.url { install(url) }
            }
            Menu("Desktop Pictures") {
                ForEach(Self.stock, id: \.self) { url in
                    Button(url.deletingPathExtension().lastPathComponent) { install(url) }
                }
            }.disabled(Self.stock.isEmpty)
            Button("Remove Image") { replace(with: "") }.disabled(file.isEmpty)
        }
        .fixedSize()
        .alert("Couldn’t load this image", isPresented: $failed) { Button("OK") {} }
    }

    private func install(_ sourceURL: URL) {
        let options: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true,
                                       kCGImageSourceCreateThumbnailWithTransform: true,
                                       kCGImageSourceThumbnailMaxPixelSize: 3840]
        guard let source = CGImageSourceCreateWithURL(sourceURL as CFURL, nil),
              let bitmap = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary),
              let data = NSBitmapImageRep(cgImage: bitmap).representation(using: .jpeg, properties: [.compressionFactor: 0.88])
        else { failed = true; return }
        do {
            try FileManager.default.createDirectory(at: photos, withIntermediateDirectories: true)
            let name = UUID().uuidString + ".jpg"
            try data.write(to: photos.appendingPathComponent(name), options: .atomic)
            replace(with: name)
        } catch { failed = true }
    }

    private func replace(with name: String) {
        let old = file
        file = name
        if !old.isEmpty { try? FileManager.default.removeItem(at: photos.appendingPathComponent(old)) }
    }
}

struct SpacePageSettings: View {
    let space: UUID
    @AppStorage("appearance.spacePages", store: Store.settings) private var share = true
    var body: some View {
        SettingsRow("Use Space colors on library pages") {
            Toggle("Use Space colors on library pages", isOn: $share).labelsHidden().toggleStyle(.switch).controlSize(.small)
        }.settingsAnchor("space-pages")
        SettingsRow("Home background image") { HomePhotoMenu(space: space) }.settingsAnchor("home-photo")
    }
}
