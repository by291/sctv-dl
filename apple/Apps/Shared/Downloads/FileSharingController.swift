import Foundation
import Observation
import SCTVCore
import SCTVDownloads
import SwiftUI

#if os(macOS)
    import AppKit
#else
    import UIKit
#endif

struct SharedFile: Identifiable {
    let id = UUID()
    let lease: LocalFileLease
}

@MainActor @Observable
final class FileSharingController {
    var sharing: SharedFile?
    var warning: String?
    private let downloads: DownloadDependencies
    init(downloads: DownloadDependencies) { self.downloads = downloads }

    func export(_ task: DownloadTask) async {
        do {
            let lease = try await downloads.access.open(task.id)
            #if os(macOS)
                let panel = NSSavePanel()
                panel.nameFieldStringValue = task.filename
                panel.allowedContentTypes = [.mpeg4Movie]
                guard await panel.begin() == .OK, let destination = panel.url else { return }
                try await downloads.export.copy(lease, to: destination, replaceExisting: true)
            #else
                sharing = SharedFile(lease: lease)
            #endif
        } catch { warning = error.localizedDescription }
    }

    func reauthorize(_ task: DownloadTask) async {
        #if os(macOS)
            guard case .external(let id) = task.destination else { return }
            let panel = NSOpenPanel()
            panel.canChooseDirectories = true
            panel.canChooseFiles = false
            panel.allowsMultipleSelection = false
            panel.message = "重新授权此目录会恢复所有使用它的下载任务。请选择原目录，或为尚未保存的文件指定新位置。"
            guard await panel.begin() == .OK, let directory = panel.url else { return }
            do {
                _ = try await downloads.directories.authorize(directory, replacing: id)
                try await downloads.service.reconcile()
            } catch { warning = error.localizedDescription }
        #endif
    }

    func reveal(_ task: DownloadTask) async {
        #if os(macOS)
            do {
                let lease = try await downloads.access.open(task.id)
                NSWorkspace.shared.activateFileViewerSelecting([lease.url])
                withExtendedLifetime(lease) {}
            } catch { warning = error.localizedDescription }
        #endif
    }
}

#if os(iOS)
    struct FileShareView: UIViewControllerRepresentable {
        let file: SharedFile
        func makeUIViewController(context: Context) -> UIActivityViewController {
            UIActivityViewController(activityItems: [file.lease.url], applicationActivities: nil)
        }
        func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
        // The sheet retains SharedFile and its scope lease through completion or cancellation.
    }
#endif
