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
    private let scanQueue = DispatchQueue(label: "com.vbd.scan", qos: .userInitiated)
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

        guard !newItems.isEmpty else { return }

        // Track active scans so isScanning stays true until ALL folders finish
        activeScanCount += 1
        isScanning = true

        // Step 2: Load durations on a serial queue (one file at a time, guaranteed completion)
        let items = newItems
        scanQueue.async { [weak self] in
            for item in items {
                let asset = AVURLAsset(url: item.url)
                let cmDuration = asset.duration
                let secs = CMTimeGetSeconds(cmDuration)
                let duration: TimeInterval? = secs.isFinite ? secs : nil

                DispatchQueue.main.async {
                    self?.updateDuration(id: item.id, duration: duration)
                }
            }
            DispatchQueue.main.async {
                guard let self else { return }
                self.activeScanCount -= 1
                if self.activeScanCount <= 0 {
                    self.activeScanCount = 0
                    self.isScanning = false
                }
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
