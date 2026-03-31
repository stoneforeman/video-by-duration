import SwiftUI
import Quartz
import AVKit

struct VideoTableView: View {
    @EnvironmentObject var store: FolderStore
    @State private var selection = Set<VideoItem.ID>()
    @State private var sortOrder = [KeyPathComparator(\VideoItem.sortableDuration)]
    @State private var showDeleteAlert = false
    @State private var itemToDelete: VideoItem?

    var sortedItems: [VideoItem] {
        store.filteredItems.sorted(using: sortOrder)
    }

    var body: some View {
        Table(sortedItems, selection: $selection, sortOrder: $sortOrder) {
            TableColumn("Filename", value: \.filename) { item in
                Text(item.filename)
                    .lineLimit(1)
            }
            .width(min: 200, ideal: 300)

            TableColumn("Duration", value: \.sortableDuration) { item in
                Text(item.durationFormatted)
                    .monospacedDigit()
            }
            .width(min: 80, ideal: 100)

            TableColumn("Size", value: \.fileSize) { item in
                Text(item.fileSizeFormatted)
                    .monospacedDigit()
            }
            .width(min: 80, ideal: 100)

            TableColumn("Path", value: \.folderPath) { item in
                Text(item.folderPath)
                    .lineLimit(1)
                    .foregroundStyle(.secondary)
            }
            .width(min: 200, ideal: 400)
        }
        .contextMenu(forSelectionType: VideoItem.ID.self) { ids in
            if let id = ids.first, let item = sortedItems.first(where: { $0.id == id }) {
                Button("Reveal in Finder") {
                    FileUtilities.revealInFinder(item.url)
                }
                Button("Open") {
                    FileUtilities.openFile(item.url)
                }
                Button("Quick Look") {
                    PreviewWindowController.shared.toggle(url: item.url)
                }
                Divider()
                Button("Move to Trash", role: .destructive) {
                    itemToDelete = item
                    showDeleteAlert = true
                }
            }
        }
        .onKeyPress(.space) {
            guard let id = selection.first,
                  let item = sortedItems.first(where: { $0.id == id }) else {
                return .ignored
            }
            PreviewWindowController.shared.toggle(url: item.url)
            return .handled
        }
        .onDeleteCommand {
            if let id = selection.first, let item = sortedItems.first(where: { $0.id == id }) {
                itemToDelete = item
                showDeleteAlert = true
            }
        }
        .alert("Move to Trash?", isPresented: $showDeleteAlert, presenting: itemToDelete) { item in
            Button("Move to Trash", role: .destructive) {
                _ = store.deleteVideo(id: item.id)
                selection.remove(item.id)
            }
            Button("Cancel", role: .cancel) {}
        } message: { item in
            Text("Are you sure you want to move \"\(item.filename)\" to the Trash?")
        }
        .safeAreaInset(edge: .bottom) {
            HStack {
                Text(store.statusText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .padding(.horizontal)
            .padding(.vertical, 4)
            .background(.bar)
        }
    }
}

// MARK: - Preview Window using AVPlayerView

class PreviewWindowController {
    static let shared = PreviewWindowController()

    private var window: NSWindow?
    private var playerView: AVPlayerView?
    private var player: AVPlayer?

    private var currentURL: URL?

    func toggle(url: URL) {
        // If preview is visible, always close it first
        if let window, window.isVisible {
            player?.pause()
            window.close()
            // If same file, just close (toggle off)
            if currentURL == url {
                currentURL = nil
                return
            }
        }

        // Open preview for this file
        currentURL = url
        player = AVPlayer(url: url)
        playerView = AVPlayerView()
        playerView!.player = player
        playerView!.controlsStyle = .floating

        // Non-activating panel: never steals keyboard focus from the table
        let w = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 800, height: 500),
            styleMask: [.titled, .closable, .resizable, .nonactivatingPanel, .utilityWindow],
            backing: .buffered,
            defer: false
        )
        w.title = url.lastPathComponent
        w.contentView = playerView
        w.level = .floating
        w.hidesOnDeactivate = false
        w.center()
        w.orderFront(nil)  // orderFront, NOT makeKeyAndOrderFront — keeps focus on table
        w.isReleasedWhenClosed = false
        self.window = w

        player?.play()
    }
}
