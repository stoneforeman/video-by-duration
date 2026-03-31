import Foundation

struct VideoItem: Identifiable, Hashable {
    let id = UUID()
    let url: URL
    let filename: String
    let folderPath: String
    let fileSize: Int64
    var duration: TimeInterval?
    var isLoadingDuration: Bool = true

    var fileSizeFormatted: String {
        ByteCountFormatter.string(fromByteCount: fileSize, countStyle: .file)
    }

    var durationFormatted: String {
        guard let duration else { return isLoadingDuration ? "..." : "N/A" }
        return DurationFormatter.format(duration)
    }

    var sortableDuration: Double {
        duration ?? -1
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    static func == (lhs: VideoItem, rhs: VideoItem) -> Bool {
        lhs.id == rhs.id
    }
}
