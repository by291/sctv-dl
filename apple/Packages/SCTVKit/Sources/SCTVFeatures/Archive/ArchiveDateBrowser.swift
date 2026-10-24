import SCTVCore
import SwiftUI

struct ArchiveDateBrowser: View {
    let selectedID: String?
    let select: (BroadcastDate) -> Void
    @State private var model: ArchiveDateBrowserModel
    @State private var revealedSelection = false
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme

    init(
        dates: [BroadcastDate], selectedID: String?, select: @escaping (BroadcastDate) -> Void
    ) {
        self.selectedID = selectedID
        self.select = select
        _model = State(initialValue: ArchiveDateBrowserModel(dates: dates, selectedID: selectedID))
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                monthNavigation
                ScrollViewReader { proxy in
                    List {
                        ForEach(model.visibleMonths) { month in
                            Section {
                                ForEach(month.dates) { date in
                                    dateRow(date).id(date.id)
                                        .onAppear {
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
                                if model.searching {
                                    Text(month.title)
                                        .font(.headline).foregroundStyle(.primary)
                                        .textCase(nil)
                                        .padding(.vertical, 6)
                                }
                            }
                        }
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                    .scrollDismissesKeyboard(.interactively)
                    .accessibilityIdentifier("archive-date-list")
                    .onChange(of: model.monthID) { _, _ in
                        if let first = model.visibleMonths.first?.dates.first {
                            proxy.scrollTo(first.id, anchor: .top)
                        }
                    }
                    .overlay {
                        if model.visibleMonths.isEmpty {
                            ContentUnavailableView(
                                "没有匹配的日期", systemImage: "calendar.badge.exclamationmark",
                                description: Text("直接输入年份、年月或完整日期，如 202610、20261023。"))
                        }
                    }
                }
            }
            .background(PresentationStyle.canvas(scheme))
            .searchable(text: $model.search, prompt: "搜索日期，如 202610")
            #if os(iOS)
                .keyboardType(.numberPad)
                .navigationBarTitleDisplayMode(.inline)
            #endif
            .navigationTitle("播出日期")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭", systemImage: "xmark") { dismiss() }
                        .labelStyle(.iconOnly).help("关闭")
                }
            }
        }
        #if os(iOS)
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
            .presentationBackground(PresentationStyle.canvas(scheme))
        #endif
    }

    private var monthNavigation: some View {
        HStack {
            Menu {
                ForEach(model.months) { month in
                    Button {
                        model.selectMonth(month.id)
                    } label: {
                        if month.id == model.monthID {
                            Label(month.title, systemImage: "checkmark")
                        } else {
                            Text(month.title)
                        }
                    }
                }
            } label: {
                HStack(spacing: 6) {
                    Text(model.monthTitle).font(.headline)
                    Image(systemName: "chevron.down").font(.caption.weight(.semibold))
                }
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
            .disabled(model.searching)
            Spacer()
            monthButton("上个月", symbol: "chevron.left", delta: 1)
                .disabled(model.searching || !model.hasPreviousMonth)
            monthButton("下个月", symbol: "chevron.right", delta: -1)
                .disabled(model.searching || !model.hasNextMonth)
        }
        .buttonStyle(.borderless)
        .labelStyle(.iconOnly)
        .controlSize(.large)
        .padding(.horizontal, 20)
        .padding(.vertical, 4)
    }

    private func monthButton(_ title: String, symbol: String, delta: Int) -> some View {
        Button {
            model.changeMonth(by: delta)
        } label: {
            Image(systemName: symbol)
                .frame(width: 44, height: 44).contentShape(Rectangle())
        }
        .accessibilityLabel(title)
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
