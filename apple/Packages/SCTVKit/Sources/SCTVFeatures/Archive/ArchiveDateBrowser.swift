import SCTVCore
import SwiftUI

struct ArchiveDateBrowser: View {
    let dates: [BroadcastDate]
    let selectedID: String?
    let select: (BroadcastDate) -> Void
    @State private var search = ""
    @State private var revealedSelection = false
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let groups = ArchiveDateGroup.group(dates, query: search)
        NavigationStack {
            ScrollViewReader { proxy in
                List {
                    ForEach(groups) { month in
                        Section {
                            ForEach(month.dates) { date in
                                dateRow(date).id(date.id)
                                    .onAppear {
                                        // The sheet task can precede native List registration on iPad.
                                        // Wait for a real row before revealing a distant selection.
                                        guard !revealedSelection else { return }
                                        revealedSelection = true
                                        if let selectedID {
                                            proxy.scrollTo(selectedID, anchor: .center)
                                        }
                                    }
                                    .listRowInsets(
                                        EdgeInsets(top: 2, leading: 20, bottom: 2, trailing: 20)
                                    )
                                    .listRowBackground(
                                        date.id == selectedID
                                            ? PresentationStyle.accent(scheme).opacity(0.08)
                                            : Color.clear)
                            }
                        } header: {
                            Text(month.title)
                                .font(.headline).foregroundStyle(.primary)
                                .textCase(nil)
                                .padding(.vertical, 6)
                        }
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .scrollDismissesKeyboard(.interactively)
                .accessibilityIdentifier("archive-date-list")
                .overlay {
                    if groups.isEmpty {
                        ContentUnavailableView(
                            "没有匹配的日期", systemImage: "calendar.badge.exclamationmark",
                            description: Text("直接输入年份、年月或完整日期，如 202610、20261023。"))
                    }
                }
            }
            .background(PresentationStyle.canvas(scheme))
            .searchable(text: $search, prompt: "搜索日期，如 202610")
            #if os(iOS)
                .keyboardType(.numberPad)
            #endif
            .navigationTitle("播出日期")
            #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭", systemImage: "xmark") { dismiss() }
                        .labelStyle(.iconOnly).help("关闭")
                }
            }
        }
        #if os(macOS)
            .frame(minWidth: 360, idealWidth: 420, minHeight: 400, idealHeight: 560)
        #else
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
            .presentationBackground(PresentationStyle.canvas(scheme))
        #endif
    }

    private func dateRow(_ date: BroadcastDate) -> some View {
        let selected = date.id == selectedID
        return Button {
            select(date)
        } label: {
            HStack {
                Text(ArchiveDateGroup.dateTitle(date.date))
                    .fontWeight(selected ? .semibold : .regular)
                    .monospacedDigit()
                Spacer()
                if selected {
                    Image(systemName: "checkmark").fontWeight(.semibold)
                }
            }
            .frame(minHeight: 40)
            .foregroundStyle(selected ? PresentationStyle.accent(scheme) : Color.primary)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(date.date)
        .accessibilityIdentifier("archive-date-\(date.id)")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
