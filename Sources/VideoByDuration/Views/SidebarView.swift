import SwiftUI

struct SidebarView: View {
    @EnvironmentObject var store: FolderStore

    var body: some View {
        List {
            Section("Folders") {
                if store.folders.isEmpty {
                    Text("No folders added")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(store.folders, id: \.self) { folder in
                        HStack {
                            VStack(alignment: .leading) {
                                Text(folder.lastPathComponent)
                                    .fontWeight(.medium)
                                Text(folder.path)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                            Spacer()
                            Button {
                                store.removeFolder(folder)
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                            .help("Remove folder")
                        }
                        .contextMenu {
                            Button("Remove Folder") {
                                store.removeFolder(folder)
                            }
                            Button("Reveal in Finder") {
                                FileUtilities.revealInFinder(folder)
                            }
                        }
                    }
                    .onDelete { indexSet in
                        for index in indexSet {
                            store.removeFolder(store.folders[index])
                        }
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .safeAreaInset(edge: .bottom) {
            Button {
                if let url = FileUtilities.chooseFolder() {
                    store.addFolder(url)
                }
            } label: {
                Label("Add Folder", systemImage: "plus")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderless)
            .padding()
        }
    }
}
