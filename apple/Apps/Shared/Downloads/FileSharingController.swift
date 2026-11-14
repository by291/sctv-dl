import Foundation
import OSLog
import Observation
import SCTVCore
import SCTVDownloads
import SCTVFeatures
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
    private let logger = Logger(subsystem: "dev.sctvdl.apple", category: "file-sharing")
    private var isHandlingFileAction = false

    init(downloads: DownloadDependencies) { self.downloads = downloads }

    func export(_ task: DownloadTask) async {
        guard beginFileAction() else { return }

        defer { isHandlingFileAction = false }
        do {
            let lease = try await downloads.access.open(task.id)
            try Task.checkCancellation()

            #if os(macOS)
                let panel = NSSavePanel()
                panel.nameFieldStringValue = task.filename
                panel.allowedContentTypes = [.mpeg4Movie]
                guard await panel.begin() == .OK, let destination = panel.url else { return }

                try Task.checkCancellation()
                try await downloads.export.copy(lease, to: destination, replaceExisting: true)
            #else
                sharing = SharedFile(lease: lease)
            #endif
        } catch {
            reportFailure(error, fallback: "无法导出文件，请重试。")
        }
    }

    func reauthorize(_ task: DownloadTask) async {
        #if os(macOS)
            guard case .external(let id) = task.destination else { return }
            guard beginFileAction() else { return }

            defer { isHandlingFileAction = false }
            let panel = NSOpenPanel()
            panel.canChooseDirectories = true
            panel.canChooseFiles = false
            panel.allowsMultipleSelection = false
            panel.message = "重新授权此目录会恢复所有使用它的下载任务。请选择原目录，或为尚未保存的文件指定新位置。"
            guard await panel.begin() == .OK, let directory = panel.url else { return }

            do {
                try Task.checkCancellation()
                _ = try await downloads.directories.authorize(directory, replacing: id)
                try await downloads.service.reconcile()
            } catch {
                reportFailure(error, fallback: "无法重新授权下载目录，请重试。")
            }
        #endif
    }

    func reveal(_ task: DownloadTask) async {
        #if os(macOS)
            guard beginFileAction() else { return }

            defer { isHandlingFileAction = false }
            do {
                let lease = try await downloads.access.open(task.id)
                try Task.checkCancellation()

                NSWorkspace.shared.activateFileViewerSelecting([lease.url])
                withExtendedLifetime(lease) {}
            } catch {
                reportFailure(error, fallback: "无法在访达中显示文件，请重试。")
            }
        #endif
    }

    private func beginFileAction() -> Bool {
        // One lease and native presentation own the interaction until the panel or sheet finishes.
        guard !isHandlingFileAction, sharing == nil else { return false }

        isHandlingFileAction = true
        return true
    }

    private func reportFailure(_ error: any Error, fallback: String) {
        guard !(error is CancellationError) else { return }

        logger.error(
            "Downloaded file action failed: \(error.localizedDescription, privacy: .private)")
        if let fileError = error as? DownloadFileError {
            warning = DownloadIssueMessage.text(for: fileError.issueCode)
        } else {
            warning = fallback
        }
    }
}

#if os(iOS)
    struct FileShareView: UIViewControllerRepresentable {
        // The sheet retains its scope lease through completion or cancellation.
        let file: SharedFile

        func makeUIViewController(context: Context) -> UIActivityViewController {
            UIActivityViewController(activityItems: [file.lease.url], applicationActivities: nil)
        }

        func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
    }
#endif
