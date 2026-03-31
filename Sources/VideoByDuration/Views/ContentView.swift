import SwiftUI

struct ContentView: View {
    @EnvironmentObject var store: FolderStore

    var body: some View {
        NavigationSplitView {
            SidebarView()
        } detail: {
            VStack(spacing: 0) {
                DurationFilterView()
                    .padding(.horizontal)
                    .padding(.vertical, 8)
                Divider()
                if store.videoItems.isEmpty && !store.isScanning {
                    ContentUnavailableView(
                        "No Videos",
                        systemImage: "film",
                        description: Text("Add a folder from the sidebar to get started.")
                    )
                } else {
                    VideoTableView()
                }
            }
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    if let url = FileUtilities.chooseFolder() {
                        store.addFolder(url)
                    }
                } label: {
                    Label("Add Folder", systemImage: "plus.rectangle.on.folder")
                }
            }
            ToolbarItem {
                Button {
                    store.rescanAll()
                } label: {
                    Label("Rescan", systemImage: "arrow.clockwise")
                }
                .disabled(store.isScanning)
            }
            ToolbarItem {
                if store.isScanning {
                    ProgressView()
                        .controlSize(.small)
                }
            }
        }
        .navigationTitle("Video by Duration")
    }
}
