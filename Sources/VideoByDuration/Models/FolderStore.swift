import Foundation
import SwiftUI
import AVFoundation

@MainActor
class FolderStore: ObservableObject {
    @Published var folders: [URL] = []
    @Published var videoItems: [VideoItem] = []
    @Published var isScanning = false
    @Published var tableRefreshID = UUID()
    @Published var minDuration: TimeInterval = 0
    @Published var maxDuration: TimeInterval = .infinity

    private let bookmarksKey = "savedFolderBookmarks"
    private static let supportedExtensions: Set<String> = ["mp4", "mov", "avi", "mkv", "m4v", "wmv", "webm"]
    private var activeScanCount = 0
    static func log(_ msg: String) {
        let line = "\(Date()): \(msg)\n"
        if let data = line.data(using: .utf8) {
            let path = "/tmp/vbd_debug.log"
            if let fh = FileHandle(forWritingAtPath: path) {
                fh.seekToEndOfFile(); fh.write(data); fh.closeFile()
            } else {
                FileManager.default.createFile(atPath: path, contents: data)
            }
        }
    }

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
        Self.log("[SCAN] Found \(newItems.count) files in \(url.lastPathComponent)")
        Self.log("[SCAN] videoItems before append: \(videoItems.count)")
        videoItems.append(contentsOf: newItems)
        Self.log("[SCAN] videoItems after append: \(videoItems.count)")

        guard !newItems.isEmpty else { return }

        activeScanCount += 1
        isScanning = true

        let itemData = newItems.map { (id: $0.id, url: $0.url) }

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            Self.log("[BG] Starting duration load for \(itemData.count) files")
            var durations: [UUID: TimeInterval] = [:]

            for (i, entry) in itemData.enumerated() {
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
                } else {
                    Self.log("[BG] TIMEOUT or nil for file \(i)")
                }
            }

            Self.log("[BG] Loaded \(durations.count)/\(itemData.count) durations, posting to main")

            DispatchQueue.main.async {
                guard let self else { Self.log("[BG] self is nil!"); return }

                Self.log("[MAIN] videoItems count before update: \(self.videoItems.count)")
                let idsToUpdate = Set(durations.keys)
                let matchCount = self.videoItems.filter { idsToUpdate.contains($0.id) }.count
                Self.log("[MAIN] items matching duration IDs: \(matchCount)")

                var newArray = self.videoItems
                var updated = 0
                for i in newArray.indices {
                    if let dur = durations[newArray[i].id] {
                        newArray[i].duration = dur
                        newArray[i].isLoadingDuration = false
                        updated += 1
                    }
                }
                Self.log("[MAIN] updated \(updated) items, replacing array")
                self.videoItems = newArray
                self.tableRefreshID = UUID()  // Force Table to re-render

                self.activeScanCount -= 1
                if self.activeScanCount <= 0 {
                    self.activeScanCount = 0
                    self.isScanning = false
                }
                Self.log("[MAIN] done, videoItems count: \(self.videoItems.count), isScanning: \(self.isScanning)")
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
