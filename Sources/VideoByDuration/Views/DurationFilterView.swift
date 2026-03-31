import SwiftUI

struct DurationFilterView: View {
    @EnvironmentObject var store: FolderStore
    @State private var minText = ""
    @State private var maxText = ""

    var body: some View {
        HStack(spacing: 12) {
            Text("Filter:")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack(spacing: 4) {
                TextField("Min (sec)", text: $minText)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 80)
                    .onSubmit { applyFilter() }
                Text("–")
                TextField("Max (sec)", text: $maxText)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 80)
                    .onSubmit { applyFilter() }
            }

            Group {
                Button("< 30s") { setPreset(min: 0, max: 30) }
                Button("1-5 min") { setPreset(min: 60, max: 300) }
                Button("> 5 min") { setPreset(min: 300, max: .infinity) }
                Button("Clear") { clearFilter() }
            }
            .controlSize(.small)

            Spacer()
        }
    }

    private func setPreset(min: TimeInterval, max: TimeInterval) {
        minText = min > 0 ? "\(Int(min))" : ""
        maxText = max < .infinity ? "\(Int(max))" : ""
        store.setFilter(min: min, max: max)
    }

    private func clearFilter() {
        minText = ""
        maxText = ""
        store.clearFilter()
    }

    private func applyFilter() {
        let min = TimeInterval(minText) ?? 0
        let max = TimeInterval(maxText) ?? .infinity
        store.setFilter(min: min, max: max)
    }
}
