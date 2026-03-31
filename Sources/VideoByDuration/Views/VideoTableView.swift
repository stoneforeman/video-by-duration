import SwiftUI
import Quartz
import AVKit

struct VideoTableView: View {
    @EnvironmentObject var store: FolderStore
    @State private var selection = Set<VideoItem.ID>()
    @State private var sortOrder = [KeyPathComparator(\VideoItem.sortableDuration)]

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
        // If showing the same file, close it
        if let window, window.isVisible, currentURL == url {
            player?.pause()
            window.close()
            currentURL = nil
            return
        }

        // If window exists and is visible with a different file, swap content
        if let window, window.isVisible {
            currentURL = url
            player?.replaceCurrentItem(with: AVPlayerItem(url: url))
            player?.play()
            window.title = url.lastPathComponent
            window.makeKeyAndOrderFront(nil)
            return
        }

        // Create player
        currentURL = url
        player = AVPlayer(url: url)
        playerView = AVPlayerView()
        playerView!.player = player

        // Create floating panel that doesn't steal focus (like Quick Look)
        let w = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 800, height: 500),
            styleMask: [.titled, .closable, .resizable, .nonactivatingPanel, .utilityWindow],
            backing: .buffered,
            defer: false
        )
        w.title = url.lastPathComponent
        w.contentView = playerView
        w.level = .floating
        w.center()
        w.orderFront(nil)
        w.isReleasedWhenClosed = false
        self.window = w

        player?.play()
    }

    func close() {
        player?.pause()
        window?.close()
    }
}
