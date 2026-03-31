import AppKit
import Quartz

class AppDelegate: NSObject, NSApplicationDelegate {
    var selectedVideoURL: URL?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    func toggleQuickLook() {
        guard let panel = QLPreviewPanel.shared() else { return }
        if panel.isVisible {
            panel.reloadData()
        } else {
            panel.center()
            panel.makeKeyAndOrderFront(nil)
        }
    }
}
