import Foundation
import SwiftUI
import AVFoundation

@MainActor
class FolderStore: ObservableObject {
    @Published var folders: [URL] = []
    @Published var videoItems: [VideoItem] = []
    @Published var isScanning = false
    @Published var minDuration: TimeInterval = 0
    @Published var maxDuration: TimeInterval = .infinity

    private let bookmarksKey = "savedFolderBookmarks"
    private static let supportedExtensions: Set<String> = ["mp4", "mov", "avi", "mkv", "m4v", "wmv", "webm"]

    var filteredItems: [VideoItem] {
        videoItems.filter { item in
            guard let dur = item.duration else { return true }
            return dur >= minDuration && dur <= maxDuration
        }
    }

    var statusText: String {
        let filtered = filteredItems.count
        let total = videoItems.count
        if isScanning {
            let loaded = videoItems.filter({ !$0.isLoadingDuration }).count
            return "Loading durations... \(loaded)/\(total)"
        }
        if filtered == total {
            return "\(total) videos"
        }
        return "Showing \(filtered) of \(total) videos"
    }

    init() {
        loadFolders()
    }

    func addFolder(_ url: URL) {
        guard !folders.contains(url) else { return }
        folders.append(url)
        saveFolders()
        scanFolder(url)
    }

    func removeFolder(_ url: URL) {
        folders.removeAll { $0 == url }
        videoItems.removeAll { $0.url.path.hasPrefix(url.path) }
        saveFolders()
    }

    func rescanAll() {
        videoItems.removeAll()
        for folder in folders {
            scanFolder(folder)
        }
    }

    func setFilter(min: TimeInterval, max: TimeInterval) {
        minDuration = min
        maxDuration = max
    }

    func clearFilter() {
        minDuration = 0
        maxDuration = .infinity
    }

    // MARK: - Scanning

    private func scanFolder(_ url: URL) {
        isScanning = true

        // Step 1: Find all video files (synchronous, fast)
        var newItems: [VideoItem] = []
        if let enumerator = FileManager.default.enumerator(
            at: url,
            includingPropertiesForKeys: [.fileSizeKey],
            options: [.skipsHiddenFiles]
        ) {
            for case let fileURL as URL in enumerator {
                guard Self.supportedExtensions.contains(fileURL.pathExtension.lowercased()) else { continue }
                let fileSize = (try? fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize).map(Int64.init) ?? 0
                let item = VideoItem(
                    url: fileURL,
                    filename: fileURL.lastPathComponent,
                    folderPath: fileURL.deletingLastPathComponent().path,
                    fileSize: fileSize,
                    duration: nil,
                    isLoadingDuration: true
                )
                newItems.append(item)
            }
        }
        videoItems.append(contentsOf: newItems)

        // Step 2: Load durations on a background GCD queue, post results back one at a time
        let items = newItems
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let group = DispatchGroup()
            let semaphore = DispatchSemaphore(value: 8) // max 8 concurrent

            for item in items {
                semaphore.wait()
                group.enter()

                let asset = AVURLAsset(url: item.url)
                asset.loadValuesAsynchronously(forKeys: ["duration"]) {
                    var duration: TimeInterval? = nil
                    let status = asset.statusOfValue(forKey: "duration", error: nil)
                    if status == .loaded {
                        let secs = CMTimeGetSeconds(asset.duration)
                        if secs.isFinite { duration = secs }
                    }

                    DispatchQueue.main.async {
                        self?.updateDuration(id: item.id, duration: duration)
                    }

                    semaphore.signal()
                    group.leave()
                }
            }

            group.wait()
            DispatchQueue.main.async {
                self?.isScanning = false
            }
        }
    }

    private func updateDuration(id: UUID, duration: TimeInterval?) {
        if let idx = videoItems.firstIndex(where: { $0.id == id }) {
            videoItems[idx].duration = duration
            videoItems[idx].isLoadingDuration = false
        }
    }

    // MARK: - Persistence

    private func saveFolders() {
        let bookmarks = folders.compactMap { url -> Data? in
            try? url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil)
        }
        UserDefaults.standard.set(bookmarks, forKey: bookmarksKey)
    }

    private func loadFolders() {
        guard let bookmarks = UserDefaults.standard.array(forKey: bookmarksKey) as? [Data] else { return }
        for data in bookmarks {
            var isStale = false
            guard let url = try? URL(resolvingBookmarkData: data, options: .withSecurityScope, relativeTo: nil, bookmarkDataIsStale: &isStale) else { continue }
            guard url.startAccessingSecurityScopedResource() else { continue }
            folders.append(url)
            scanFolder(url)
        }
    }
}
