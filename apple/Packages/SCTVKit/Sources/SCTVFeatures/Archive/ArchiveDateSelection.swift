import SCTVCore
import SwiftUI

struct ArchiveDateSelection: View {
    @Bindable var model: ArchiveModel
    @State private var showingDates = false
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        if !model.dates.isEmpty {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text("播出日期").font(.headline)
                    Spacer()
                    Button {
                        showingDates = true
                    } label: {
                        Label(model.broadcast?.date ?? "全部日期", systemImage: "calendar")
                            .font(.subheadline).monospacedDigit()
                    }
                    .accessibilityLabel("全部日期")
                    .accessibilityValue(model.broadcast?.date ?? "")
                    .accessibilityIdentifier("archive-all-dates")
                }
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(model.dates.prefix(14)) { date in
                            Button {
                                Task { await model.selectDate(date.id) }
                            } label: {
                                Text(date.date).font(.subheadline.weight(.medium)).monospacedDigit()
                                    .padding(.horizontal, 16).padding(.vertical, 13)
                                    .foregroundStyle(
                                        date.id == model.selectedDateID
                                            ? (scheme == .dark ? Color.black : .white) : .primary
                                    )
                                    .background(
                                        date.id == model.selectedDateID
                                            ? PresentationStyle.accent(scheme)
                                            : PresentationStyle.surface(scheme), in: Capsule())
                            }
                            .buttonStyle(.plain)
                            .accessibilityAddTraits(
                                date.id == model.selectedDateID ? .isSelected : [])
                        }
                    }
                }
            }
            // Some programmes have thousands of dates. Construct their rows only
            // while browsing dates, never inside the scrolling archive's picker.
            .sheet(isPresented: $showingDates) {
                ArchiveDateBrowser(dates: model.dates, selectedID: model.selectedDateID) { date in
                    showingDates = false
                    Task { await model.selectDate(date.id) }
                }
            }
        }
    }
}

private struct ArchiveDateBrowser: View {
    let dates: [BroadcastDate]
    let selectedID: String?
    let select: (BroadcastDate) -> Void
    @State private var search = ""
    @Environment(\.dismiss) private var dismiss

    private var query: String { search.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var selectedDate: BroadcastDate? { dates.first { $0.id == selectedID } }
    private var filteredDates: [BroadcastDate] {
        query.isEmpty
            ? dates.filter { $0.id != selectedID }
            : dates.filter { $0.date.contains(query) }
    }

    var body: some View {
        NavigationStack {
            List {
                // Keep the selection visible without scrolling thousands of rows
                // before the native sheet has finished laying out its list.
                if query.isEmpty, let date = selectedDate {
                    Section("当前选择") { dateRow(date) }
                }
                Section("全部日期") {
                    ForEach(filteredDates) { date in dateRow(date) }
                }
            }
            .accessibilityIdentifier("archive-date-list")
            .overlay {
                if !query.isEmpty && filteredDates.isEmpty {
                    ContentUnavailableView.search(text: search)
                }
            }
            .searchable(text: $search, prompt: "搜索日期，如 2026-10")
            .navigationTitle("播出日期")
            #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                }
            }
        }
        #if os(macOS)
            .frame(minWidth: 360, idealWidth: 420, minHeight: 400, idealHeight: 560)
        #else
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        #endif
    }

    private func dateRow(_ date: BroadcastDate) -> some View {
        Button {
            select(date)
        } label: {
            HStack {
                Text(date.date).monospacedDigit().foregroundStyle(.primary)
                Spacer()
                if date.id == selectedID {
                    Image(systemName: "checkmark").fontWeight(.semibold)
                }
            }
            .contentShape(Rectangle())
        }
        .accessibilityIdentifier("archive-date-\(date.id)")
        .accessibilityAddTraits(date.id == selectedID ? .isSelected : [])
    }

}
