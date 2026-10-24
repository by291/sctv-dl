import SCTVCore
import SCTVFeatures
import SwiftUI

struct ArchiveDestination: View {
    @Environment(\.scenePhase) private var scenePhase
    @State private var isVisible = false
    @State private var model: ArchiveModel?

    @SceneStorage private var dateID: String
    @SceneStorage private var ascending: Bool
    @SceneStorage private var anchor: String

    let programme: Programme
    let repository: any ProgrammeRepository
    let catalogue: CatalogueModel
    let play: (ProgrammeContent, BroadcastDate) -> Void
    let download: ([ProgrammeContent], BroadcastDate) -> Void

    init(
        programme: Programme, repository: any ProgrammeRepository, catalogue: CatalogueModel,
        play: @escaping (ProgrammeContent, BroadcastDate) -> Void,
        download: @escaping ([ProgrammeContent], BroadcastDate) -> Void
    ) {
        self.programme = programme
        self.repository = repository
        self.catalogue = catalogue
        self.play = play
        self.download = download

        _dateID = SceneStorage(wrappedValue: "", "archive.\(programme.id).date")
        _ascending = SceneStorage(wrappedValue: true, "archive.\(programme.id).ascending")
        _anchor = SceneStorage(wrappedValue: "", "archive.\(programme.id).anchor")
    }

    var body: some View {
        Group {
            if let model {
                ArchiveView(
                    model: model, favourite: catalogue.favouriteIDs.contains(programme.id),
                    toggleFavourite: { Task { await catalogue.toggleFavourite(programme) } },
                    play: play, download: download
                )
                .onChange(of: model.selectedDateID) { _, value in
                    if let value { dateID = value }
                }
                .onChange(of: model.ascending) { _, value in ascending = value }
                // Persist at lifecycle boundaries without observing every scroll target
                // in this parent, which would invalidate the complete archive subtree.
                .onAppear { isVisible = true }
                .onDisappear {
                    isVisible = false
                    if let value = model.scrollAnchor { anchor = value }
                }
                .onChange(of: scenePhase) { _, phase in
                    if isVisible, phase != .active, let value = model.scrollAnchor {
                        anchor = value
                    }
                }
            } else {
                ProgressView("载入栏目")
            }
        }.task { restoreArchiveIfNeeded() }
    }

    private func restoreArchiveIfNeeded() {
        guard model == nil else { return }

        let restored = ArchiveModel(
            programme: programme, repository: repository, restoredDateID: dateID)
        restored.ascending = ascending
        restored.scrollAnchor = anchor.isEmpty ? nil : anchor
        model = restored
    }
}
