import AppKit

enum FileUtilities {
    static func chooseFolder() -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.message = "Choose a folder to scan for videos"
        guard panel.runModal() == .OK else { return nil }
        return panel.url
    }

    static func revealInFinder(_ url: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    static func openFile(_ url: URL) {
        NSWorkspace.shared.open(url)
    }
}
