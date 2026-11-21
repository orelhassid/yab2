import SwiftUI
import ImageIO
import UniformTypeIdentifiers

private func photoKey(_ space: UUID) -> String { "home.photo." + space.uuidString }
private var photos: URL { Store.folder.appendingPathComponent("Home Pictures", isDirectory: true) }

private enum HomePreset: String, CaseIterable {
    case nebula, butterflies, eclipse, stoneArch = "stone-arch", meadow, ember

    var title: String { rawValue.replacingOccurrences(of: "-", with: " ").capitalized }

    func url(preview: Bool = false) -> URL? {
        Bundle.main.url(forResource: rawValue + (preview ? "-preview" : ""), withExtension: "webp",
                        subdirectory: "HomeBackgrounds")
    }
}

private func photoURL(_ file: String) -> URL? {
    if let preset = HomePreset(rawValue: file) { return preset.url() }
    return file.isEmpty ? nil : photos.appendingPathComponent(file)
}

struct WorkspaceTheme {
    var look: SpacePaint?
    var hasPhoto = false
    var active: Bool { look != nil || hasPhoto }
    @MainActor var tone: Tone? { look.map { SpaceSurface.tone(for: SpaceWash.painted($0).color) } }
}

private struct WorkspaceThemeKey: EnvironmentKey {
    static let defaultValue = WorkspaceTheme()
}

extension EnvironmentValues {
    var workspaceTheme: WorkspaceTheme {
        get { self[WorkspaceThemeKey.self] }
        set { self[WorkspaceThemeKey.self] = newValue }
    }
}

/// The window and its native sidebar have separate SwiftUI hosting roots.
struct WorkspaceThemeReader<Content: View>: View {
    let browser: Browser
    @ViewBuilder var content: (WorkspaceTheme) -> Content

    var body: some View {
        StoredWorkspaceTheme(space: browser.spaceID, projectLook: browser.developmentLook, privateWindow: browser.windowPurpose == .privateOnly, content: content)
    }
}

private struct StoredWorkspaceTheme<Content: View>: View {
    let projectLook: SpacePaint?
    let privateWindow: Bool
    let content: (WorkspaceTheme) -> Content
    @AppStorage private var look: Data
    @AppStorage private var photo: String

    init(space: UUID, projectLook: SpacePaint?, privateWindow: Bool, content: @escaping (WorkspaceTheme) -> Content) {
        self.projectLook = projectLook
        self.privateWindow = privateWindow
        self.content = content
        _look = AppStorage(wrappedValue: Data(), "home.look." + space.uuidString, store: Store.settings)
        _photo = AppStorage(wrappedValue: "", photoKey(space), store: Store.settings)
    }

    var body: some View {
        let theme = privateWindow ? WorkspaceTheme() :
            WorkspaceTheme(look: projectLook ?? (try? JSONDecoder().decode(SpacePaint.self, from: look)), hasPhoto: projectLook == nil && !photo.isEmpty)
        let tone = theme.tone
        content(theme)
            .environment(\.workspaceTheme, theme)
            .transformEnvironment(\.tone) { if let tone { $0 = tone } }
            .transformEnvironment(\.colorScheme) { if let tone { $0 = tone.scheme } }
    }
}

private struct PhotoLayers: DynamicProperty {
    @AppStorage var noise: Double
    @AppStorage var blur: Double
    @AppStorage var transparency: Double

    init(space: UUID) {
        let key = photoKey(space)
        _noise = AppStorage(wrappedValue: 0, key + ".noise", store: Store.settings)
        _blur = AppStorage(wrappedValue: 0, key + ".blur", store: Store.settings)
        _transparency = AppStorage(wrappedValue: 0.68, key + ".transparency", store: Store.settings)
    }
}

struct HomePhotoEffects: View {
    @AppStorage private var file: String
    let base: LookFields
    private var layers: PhotoLayers

    init(space: UUID, base: LookFields) {
        self.base = base
        layers = PhotoLayers(space: space)
        _file = AppStorage(wrappedValue: "", photoKey(space), store: Store.settings)
    }

    var body: some View {
        VStack(spacing: 10) {
            slider("Noise", file.isEmpty ? base.grain : layers.$noise)
            slider("Blur", layers.$blur).disabled(file.isEmpty)
            slider("Transparency", file.isEmpty ? base.transparency : layers.$transparency)
        }
    }

    private func slider(_ title: String, _ amount: Binding<Double>) -> some View {
        HStack {
            Text(title).frame(width: 88, alignment: .leading)
            Slider(value: amount, in: 0...1, step: 0.01).accessibilityLabel(title)
            Text(amount.wrappedValue.formatted(.percent.precision(.fractionLength(0))))
                .monospacedDigit().foregroundStyle(.secondary).frame(width: 38, alignment: .trailing)
        }.font(.callout)
    }
}

struct HomePhoto: View {
    @AppStorage private var file: String
    private var layers: PhotoLayers
    @State private var image: NSImage?

    init(space: UUID) {
        layers = PhotoLayers(space: space)
        _file = AppStorage(wrappedValue: "", photoKey(space), store: Store.settings)
    }

    var body: some View {
        GeometryReader { bounds in
            if let image, !file.isEmpty {
                Image(nsImage: image).resizable().scaledToFill()
                    .frame(width: bounds.size.width, height: bounds.size.height)
                    .blur(radius: layers.blur * 24, opaque: true)
                    .clipped()
                    .opacity(1 - layers.transparency)
                    .overlay {
                        if layers.noise > 0 {
                            Image(nsImage: Grain.tile).resizable(resizingMode: .tile)
                                .opacity(Grain.opacity(layers.noise))
                        }
                    }
            }
        }
        .task(id: file) { image = photoURL(file).flatMap(NSImage.init(contentsOf:)) }
        .accessibilityHidden(true)
    }
}

struct HomePhotoGallery: View {
    @AppStorage private var file: String
    @State private var failed = false
    @State private var page = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var uploadPreview: NSImage?

    init(space: UUID) {
        _file = AppStorage(wrappedValue: "", photoKey(space), store: Store.settings)
    }

    var body: some View {
        VStack(alignment: .trailing, spacing: 4) {
            HStack(alignment: .top, spacing: 8) {
                ForEach(0..<4, id: \.self) { column in
                    let index = page * 4 + column
                    if index < itemCount { galleryItem(index) }
                    else { Color.clear.frame(maxWidth: .infinity) }
                }
            }
            .id(page)
            .transition(.push(from: page == 0 ? .leading : .trailing))
            .clipped()
            .simultaneousGesture(DragGesture(minimumDistance: 24).onEnded { drag in
                guard abs(drag.translation.width) > abs(drag.translation.height) else { return }
                turnPage(drag.translation.width < 0 ? 1 : -1)
            })
            HStack(spacing: 4) {
                arrow("chevron.left", label: "Previous backgrounds", offset: -1)
                arrow("chevron.right", label: "Next backgrounds", offset: 1)
            }
        }
        .task(id: file) {
            uploadPreview = nil
            guard HomePreset(rawValue: file) == nil, let url = photoURL(file),
                  let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return }
            let options: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true,
                                             kCGImageSourceThumbnailMaxPixelSize: 300]
            if let thumb = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) {
                uploadPreview = NSImage(cgImage: thumb, size: .zero)
            }
        }
        .alert("Couldn’t load this image", isPresented: $failed) { Button("OK") {} }
    }

    private var itemCount: Int { 2 + HomePreset.allCases.count }
    private var pageCount: Int { (itemCount + 3) / 4 }

    @ViewBuilder private func galleryItem(_ index: Int) -> some View {
        switch index {
        case 0:
            tile("No Image", symbol: "nosign", selected: file.isEmpty) { replace(with: "") }
        case 1:
            tile("Upload image", symbol: "square.and.arrow.up", image: uploadPreview,
                 selected: !file.isEmpty && HomePreset(rawValue: file) == nil) {
                let panel = NSOpenPanel()
                panel.allowedContentTypes = [.image]
                if panel.runModal() == .OK, let url = panel.url { install(url) }
            }
        default:
            let preset = HomePreset.allCases[index - 2]
            tile(preset.title, symbol: "photo", image: preset.url(preview: true).flatMap(NSImage.init(contentsOf:)),
                 selected: file == preset.rawValue) { replace(with: preset.rawValue) }
        }
    }

    private func arrow(_ symbol: String, label: String, offset: Int) -> some View {
        Button { turnPage(offset) } label: { Image(systemName: symbol) }
            .buttonStyle(.yab(.quiet, .small, icon: .square))
            .accessibilityLabel(label)
            .disabled(!(0..<pageCount).contains(page + offset))
    }

    private func turnPage(_ offset: Int) {
        let target = page + offset
        guard (0..<pageCount).contains(target) else { return }
        withAnimation(reduceMotion ? nil : Motion.quick) { page = target }
    }

    private func tile(_ title: String, symbol: String, image: NSImage? = nil, selected: Bool,
                      action: @escaping () -> Void) -> some View {
        let shape = RoundedRectangle(cornerRadius: Radius.control)
        return Button(action: action) {
            VStack(spacing: 4) {
                shape.fill(Palette.ink.opacity(0.08))
                    .aspectRatio(1, contentMode: .fit)
                    .overlay {
                        if let image { Image(nsImage: image).resizable().scaledToFill() }
                        else { Image(systemName: symbol).foregroundStyle(.secondary) }
                    }
                    .clipShape(shape)
                    .overlay { if selected { shape.strokeBorder(Palette.ink, lineWidth: 2) } }
                Text(title).font(.caption).lineLimit(1)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity)
        .accessibilityLabel(title)
        .accessibilityAddTraits(selected ? .isSelected : [])
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
        if old != name, !old.isEmpty, HomePreset(rawValue: old) == nil { try? FileManager.default.removeItem(at: photos.appendingPathComponent(old)) }
    }
}

struct SpacePageSettings: View {
    let space: UUID
    @AppStorage("appearance.spacePages", store: Store.settings) private var share = true
    var body: some View {
        SettingsRow("Use Space colors on library pages") {
            Toggle("Use Space colors on library pages", isOn: $share).labelsHidden().toggleStyle(.switch).controlSize(.small)
        }.settingsAnchor("space-pages")
        VStack(alignment: .leading, spacing: 8) {
            SettingsText("Home background image", size: 13)
            HomePhotoGallery(space: space).frame(maxWidth: 300)
        }.settingsAnchor("home-photo")
    }
}
