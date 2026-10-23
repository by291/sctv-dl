import SCTVFeatures
import SwiftUI

@main
struct SCTVmacOSApp: App {
    @NSApplicationDelegateAdaptor(NativeApplicationDelegate.self) private var nativeDelegate
    @State private var model = ApplicationModel()
    var body: some Scene {
        WindowGroup("SCTV", id: "workspace") {
            ApplicationBootstrap(model: model).frame(minWidth: 720, minHeight: 480)
        }
        .defaultSize(width: 1180, height: 800)
        .defaultLaunchBehavior(.presented)
        Window("播放器", id: "player") {
            if let dependencies = model.dependencies {
                let session = dependencies.player
                let presentation = session.presentationID
                NavigationStack {
                    PlayerSessionView(
                        session: session, download: dependencies.downloadCurrentProgramme)
                }
                .frame(minWidth: 640, minHeight: 480)
                .onDisappear {
                    Task {
                        await session.close(expected: presentation)
                    }
                }
            } else {
                ContentUnavailableView("请先选择节目", systemImage: "play.rectangle")
            }
        }
        .defaultLaunchBehavior(.suppressed)
        .restorationBehavior(.disabled)
        Settings {
            if let dependencies = model.dependencies {
                ApplicationSettingsView(dependencies: dependencies).frame(width: 460, height: 450)
            }
        }
    }
}
