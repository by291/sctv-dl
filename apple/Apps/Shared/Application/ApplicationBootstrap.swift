import Observation
import SwiftUI

@MainActor @Observable
final class ApplicationModel {
    var dependencies: AppDependencies?
    var failure: String?

    init() { prepare() }

    func prepare() {
        do {
            dependencies = try AppDependencies()
            failure = nil
        } catch {
            failure = error.localizedDescription
        }
    }
}

struct ApplicationBootstrap: View {
    let model: ApplicationModel

    var body: some View {
        Group {
            if ProcessInfo.processInfo.arguments.contains("--media-probe") {
                MediaProbeView()
            } else if let dependencies = model.dependencies {
                WorkspaceView(dependencies: dependencies)
            } else {
                ContentUnavailableView {
                    Label("无法打开资料库", systemImage: "externaldrive.badge.exclamationmark")
                } description: {
                    Text(model.failure ?? "")
                } actions: {
                    Button("重试", action: model.prepare)
                }
            }
        }
    }
}
