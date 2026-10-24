#if os(macOS)
    import SCTVCore
    import SwiftUI

    struct MacArchiveDateBrowser: View {
        let selectedID: String?
        let select: (BroadcastDate) -> Void
        @State private var model: ArchiveDateBrowserModel
        @Environment(\.dismiss) private var dismiss
        @Environment(\.colorScheme) private var scheme

        init(
            dates: [BroadcastDate], selectedID: String?,
            select: @escaping (BroadcastDate) -> Void
        ) {
            self.selectedID = selectedID
            self.select = select
            _model = State(
                initialValue: ArchiveDateBrowserModel(dates: dates, selectedID: selectedID))
        }

        var body: some View {
            VStack(spacing: 0) {
                HStack {
                    Text("播出日期").font(.headline)
                    Spacer()
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .frame(width: 28, height: 28).contentShape(Rectangle())
                    }
                    .accessibilityLabel("关闭").buttonStyle(.plain)
                    .help("关闭").keyboardShortcut(.cancelAction)
                }.padding(16)
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
                        Text(model.monthTitle)
                            .font(.headline)
                    }
                    .menuStyle(.borderlessButton).fixedSize()
                    .disabled(model.searching)
                    Spacer()
                    monthButton("上个月", symbol: "chevron.left", delta: 1)
                        .disabled(model.searching || !model.hasPreviousMonth)
                    monthButton("下个月", symbol: "chevron.right", delta: -1)
                        .disabled(model.searching || !model.hasNextMonth)
                }
                .labelStyle(.iconOnly).buttonStyle(.borderless)
                .padding(.horizontal, 16).padding(.bottom, 12)
                Divider()
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 2, pinnedViews: .sectionHeaders) {
                            ForEach(model.visibleMonths) { month in
                                Section {
                                    ForEach(month.dates) { date in
                                        dateRow(date).id(date.id)
                                    }
                                } header: {
                                    if model.searching {
                                        Text(month.title).font(.subheadline.weight(.semibold))
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                            .padding(8)
                                            .background(PresentationStyle.canvas(scheme))
                                    }
                                }
                            }
                        }.padding(8)
                    }
                    .accessibilityIdentifier("archive-date-list")
                    .task {
                        if let selectedID { proxy.scrollTo(selectedID, anchor: .center) }
                    }
                    .onChange(of: model.monthID) { _, _ in
                        if let first = model.visibleMonths.first?.dates.first {
                            proxy.scrollTo(first.id, anchor: .top)
                        }
                    }
                    .onChange(of: model.search) { _, _ in
                        if let first = model.visibleMonths.first?.dates.first {
                            proxy.scrollTo(first.id, anchor: .top)
                        }
                    }
                    .overlay {
                        if model.visibleMonths.isEmpty {
                            ContentUnavailableView(
                                "没有匹配的日期", systemImage: "calendar.badge.exclamationmark",
                                description: Text("试试年份、年月或完整日期，如 202610。"))
                        }
                    }
                }
                Divider()
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    TextField("搜索日期，如 202610", text: $model.search)
                        .textFieldStyle(.plain)
                        .accessibilityIdentifier("archive-date-search")
                    if !model.search.isEmpty {
                        Button("清除搜索", systemImage: "xmark.circle.fill") { model.search = "" }
                            .labelStyle(.iconOnly).buttonStyle(.plain)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(10)
                .background(
                    PresentationStyle.surface(scheme), in: RoundedRectangle(cornerRadius: 8)
                )
                .padding(12)
            }
            .frame(width: 340, height: 460)
            .background(PresentationStyle.canvas(scheme))
        }

        private func monthButton(_ title: String, symbol: String, delta: Int) -> some View {
            Button {
                model.changeMonth(by: delta)
            } label: {
                Image(systemName: symbol)
                    .frame(width: 28, height: 28).contentShape(Rectangle())
            }
            .accessibilityLabel(title).help(title)
        }

        private func dateRow(_ date: BroadcastDate) -> some View {
            let selected = date.id == selectedID
            return Button {
                select(date)
            } label: {
                HStack {
                    Text(ArchiveDateGroup.dateTitle(date.date)).monospacedDigit()
                    Spacer()
                    if selected { Image(systemName: "checkmark").fontWeight(.semibold) }
                }
                .font(.body.weight(selected ? .semibold : .regular))
                .padding(.horizontal, 12).frame(height: 34)
                .foregroundStyle(selected ? PresentationStyle.accent(scheme) : .primary)
                .background(
                    selected ? PresentationStyle.accent(scheme).opacity(0.1) : .clear,
                    in: RoundedRectangle(cornerRadius: 8)
                )
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(date.date)
            .accessibilityIdentifier("archive-date-\(date.id)")
            .accessibilityAddTraits(selected ? .isSelected : [])
        }
    }
#endif
