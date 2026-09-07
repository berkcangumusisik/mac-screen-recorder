import AppKit
import SwiftUI

@MainActor
final class LibraryWindowController {

    private var window: NSWindow?
    private unowned let environment: AppEnvironment

    init(environment: AppEnvironment) {
        self.environment = environment
    }

    func show() {
        if window == nil {
            let hosting = NSHostingController(rootView: LibraryView(environment: environment))
            let window = NSWindow(contentViewController: hosting)
            window.title = String(localized: "Snaplet History")
            window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
            window.setContentSize(NSSize(width: 860, height: 600))
            window.minSize = NSSize(width: 640, height: 420)
            window.isReleasedWhenClosed = false
            window.center()
            self.window = window
        }
        LibraryStore.shared.reload()
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}

struct LibraryView: View {
    let environment: AppEnvironment
    @ObservedObject private var store = LibraryStore.shared
    @ObservedObject private var settings = SettingsStore.shared

    @State private var query = ""
    @State private var kindFilter: CaptureKind?
    @State private var favouritesOnly = false
    @State private var pendingTrash: CaptureRecord?

    private let columns = [GridItem(.adaptive(minimum: 190), spacing: 14)]

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            if !store.isAvailable {
                emptyState(title: String(localized: "History is unavailable"),
                           message: String(localized: "Snaplet could not open its local history database. Captures still work; only the history list is affected."))
            } else if !settings.preferences.historyEnabled {
                emptyState(title: String(localized: "History is turned off"),
                           message: String(localized: "Turn it on in Settings › Library to keep a local record of your captures."))
            } else if filteredItems.isEmpty {
                emptyState(title: query.isEmpty
                           ? String(localized: "Nothing here yet")
                           : String(localized: "No matches"),
                           message: query.isEmpty
                           ? String(localized: "Captures you save appear here, searchable by file name and by any text Snaplet recognised in them.")
                           : String(localized: "Try a different search term, or clear the filters."))
            } else {
                grid
            }
        }
        .frame(minWidth: 640, minHeight: 420)
        .onAppear { store.reload() }
        .confirmationDialog(String(localized: "Move this file to the Trash?"),
                            isPresented: Binding(get: { pendingTrash != nil },
                                                 set: { if !$0 { pendingTrash = nil } })) {
            Button(String(localized: "Move to Trash"), role: .destructive) {
                if let item = pendingTrash {
                    do { try store.moveFileToTrash(item) }
                    catch { ErrorPresenter.present(.fileWriteFailed(error.localizedDescription)) }
                }
                pendingTrash = nil
            }
            Button(String(localized: "Cancel"), role: .cancel) { pendingTrash = nil }
        } message: {
            Text(String(localized: "This moves the actual file to the Trash. Removing an item from the history instead leaves the file where it is."))
        }
    }

    private var filteredItems: [CaptureRecord] {
        store.filtered(query: query, kind: kindFilter, favouritesOnly: favouritesOnly)
    }

    private var toolbar: some View {
        HStack(spacing: 10) {
            Picker("", selection: $kindFilter) {
                Text(String(localized: "All")).tag(CaptureKind?.none)
                ForEach(CaptureKind.allCases, id: \.self) { kind in
                    Text(kind.displayName).tag(CaptureKind?.some(kind))
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 240)

            Toggle(isOn: $favouritesOnly) {
                Image(systemName: favouritesOnly ? "star.fill" : "star")
            }
            .toggleStyle(.button)
            .help(String(localized: "Favourites only"))
            .accessibilityLabel(Text("Show favourites only"))

            Spacer()

            TextField(String(localized: "Search names and recognised text"), text: $query)
                .textFieldStyle(.roundedBorder)
                .frame(width: 280)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private var grid: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 14) {
                ForEach(filteredItems) { item in
                    CaptureRecordCard(item: item,
                                    thumbnail: store.thumbnail(for: item),
                                    onOpen: { open(item) },
                                    onReveal: { NSWorkspace.shared.activateFileViewerSelecting([item.url]) },
                                    onFavourite: { store.toggleFavorite(item) },
                                    onRemove: { store.removeFromHistory(item) },
                                    onTrash: { pendingTrash = item })
                }
            }
            .padding(14)
        }
    }

    private func emptyState(title: String, message: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: 40))
                .foregroundStyle(.tertiary)
            Text(title).font(.headline)
            Text(message)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 380)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    private func open(_ item: CaptureRecord) {
        guard item.fileExists else {
            ErrorPresenter.present(.fileWriteFailed(String(localized: "that file is no longer on disk")))
            return
        }
        environment.openFromLibrary(item)
    }
}

struct CaptureRecordCard: View {
    let item: CaptureRecord
    let thumbnail: NSImage?
    let onOpen: () -> Void
    let onReveal: () -> Void
    let onFavourite: () -> Void
    let onRemove: () -> Void
    let onTrash: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ZStack(alignment: .topTrailing) {
                Group {
                    if let thumbnail {
                        Image(nsImage: thumbnail)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    } else {
                        Image(systemName: item.kind == .video ? "film" : "photo")
                            .font(.system(size: 28))
                            .foregroundStyle(.tertiary)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
                .frame(height: 120)
                .frame(maxWidth: .infinity)
                .clipped()
                .background(Color.secondary.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

                if item.kind == .video {
                    Image(systemName: "play.circle.fill")
                        .font(.title2)
                        .foregroundStyle(.white.opacity(0.9))
                        .padding(6)
                }
            }
            .onTapGesture(count: 2, perform: onOpen)

            Text(item.fileName)
                .font(.caption)
                .lineLimit(1)
                .truncationMode(.middle)

            HStack(spacing: 6) {
                Text(item.pixelDescription)
                Text("·")
                Text(ByteCountFormatter.string(fromByteCount: Int64(item.fileSize), countStyle: .file))
                if !item.fileExists {
                    Text("·")
                    Text(String(localized: "Missing")).foregroundStyle(.orange)
                }
            }
            .font(.caption2)
            .foregroundStyle(.secondary)

            HStack(spacing: 4) {
                Button(action: onOpen) { Image(systemName: "pencil") }
                    .help(String(localized: "Edit"))
                    .accessibilityLabel(Text("Edit"))
                Button(action: onReveal) { Image(systemName: "folder") }
                    .help(String(localized: "Show in Finder"))
                    .accessibilityLabel(Text("Show in Finder"))
                Button(action: onFavourite) {
                    Image(systemName: item.isFavorite ? "star.fill" : "star")
                }
                .help(String(localized: "Favourite"))
                .accessibilityLabel(Text("Favourite"))
                Spacer()
                Menu {
                    Button(String(localized: "Remove from history"), action: onRemove)
                    Button(String(localized: "Move file to Trash…"), role: .destructive, action: onTrash)
                } label: {
                    Image(systemName: "ellipsis")
                }
                .menuStyle(.borderlessButton)
                .frame(width: 24)
                .accessibilityLabel(Text("More actions"))
            }
            .buttonStyle(.borderless)
            .controlSize(.small)
        }
        .padding(8)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text("\(item.fileName), \(item.pixelDescription)"))
    }
}
