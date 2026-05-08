import SwiftUI

struct HistoryDrawerView: View {
    @ObservedObject var store: HistoryStore
    @Binding var selectedID: UUID?
    let onPick: (HistoryEntry) -> Void
    let onDelete: (HistoryEntry) -> Void

    var body: some View {
        if store.entries.isEmpty {
            Text("尚无历史记录")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(store.entries) { entry in
                            row(entry)
                                .id(entry.id)
                                .background(
                                    selectedID == entry.id
                                        ? Color.accentColor.opacity(0.18)
                                        : Color.clear
                                )
                                .contentShape(Rectangle())
                                .onTapGesture { onPick(entry) }
                        }
                    }
                }
                .frame(maxHeight: 200)
                .onChange(of: selectedID) { new in
                    if let id = new {
                        withAnimation(.linear(duration: 0.08)) {
                            proxy.scrollTo(id, anchor: .center)
                        }
                    }
                }
            }
        }
    }

    private func row(_ entry: HistoryEntry) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(entry.query)
                .font(.system(size: 12, weight: .medium))
                .lineLimit(1)
                .frame(maxWidth: 140, alignment: .leading)

            Text(preview(entry.result))
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)

            Text(relative(entry.timestamp))
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
    }

    private func preview(_ s: String) -> String {
        let stripped = s
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if stripped.count <= 60 { return stripped }
        return String(stripped.prefix(60)) + "…"
    }

    private func relative(_ d: Date) -> String {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .abbreviated
        return f.localizedString(for: d, relativeTo: Date())
    }
}
