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
                    #if os(macOS)
                        .popover(isPresented: $showingDates, arrowEdge: .bottom) {
                            MacArchiveDateBrowser(
                                dates: model.dates, selectedID: model.selectedDateID
                            ) { date in
                                showingDates = false
                                Task { await model.selectDate(date.id) }
                            }
                        }
                    #endif
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
            #if os(iOS)
                .sheet(isPresented: $showingDates) {
                    ArchiveDateBrowser(dates: model.dates, selectedID: model.selectedDateID) {
                        date in
                        showingDates = false
                        Task { await model.selectDate(date.id) }
                    }
                }
            #endif
        }
    }
}
