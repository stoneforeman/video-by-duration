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
    private var activeScanCount = 0

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

    func deleteVideo(id: UUID) -> Bool {
        guard let idx = videoItems.firstIndex(where: { $0.id == id }) else { return false }
        let item = videoItems[idx]
        do {
            try FileManager.default.trashItem(at: item.url, resultingItemURL: nil)
            videoItems.remove(at: idx)
            return true
        } catch {
            return false
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

        guard !newItems.isEmpty else { return }

        activeScanCount += 1
        isScanning = true

        // Each folder gets its own independent background thread
        // No serial queue — folders don't block each other
        let itemData = newItems.map { (id: $0.id, url: $0.url) }

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            var durations: [UUID: TimeInterval] = [:]

            for entry in itemData {
                // Timeout: skip files that take more than 5s to read duration
                let sem = DispatchSemaphore(value: 0)
                var result: TimeInterval? = nil

                DispatchQueue.global(qos: .utility).async {
                    let asset = AVURLAsset(url: entry.url)
                    let secs = CMTimeGetSeconds(asset.duration)
                    if secs.isFinite {
                        result = secs
                    }
                    sem.signal()
                }

                let timeout = sem.wait(timeout: .now() + 5)
                if timeout == .success, let dur = result {
                    durations[entry.id] = dur
                }
            }

            // Single atomic update: rebuild videoItems array with durations filled in
            DispatchQueue.main.async {
                guard let self else { return }

                var newArray = self.videoItems
                for i in newArray.indices {
                    if let dur = durations[newArray[i].id] {
                        newArray[i].duration = dur
                        newArray[i].isLoadingDuration = false
                    }
                }
                self.videoItems = newArray

                self.activeScanCount -= 1
                if self.activeScanCount <= 0 {
                    self.activeScanCount = 0
                    self.isScanning = false
                }
            }
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
