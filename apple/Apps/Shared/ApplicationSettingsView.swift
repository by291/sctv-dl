import SCTVFeatures
import SwiftUI

#if os(macOS)
    import AppKit
#endif

struct ApplicationSettingsView: View {
    let dependencies: AppDependencies
    @State private var warning: String?
    var body: some View {
        SettingsView(
            model: dependencies.settings, clearCache: dependencies.cache.clearProgrammeCache,
            destinationDescription: destinationDescription,
            chooseDirectory: chooseDirectory,
            resetDirectory: resetDirectory,
            appVersion: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
                ?? "0.1.0"
        )
        .preferredColorScheme(colorScheme)
        .alert(
            "下载目录", isPresented: Binding(get: { warning != nil }, set: { if !$0 { warning = nil } })
        ) {
            Button("好") { warning = nil }
        } message: {
            Text(warning ?? "")
        }
    }
    private var colorScheme: ColorScheme? {
        switch dependencies.settings.value.appearance {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }

    private var destinationDescription: String {
        switch dependencies.downloads.destination {
        case .applicationManaged: "应用下载目录"
        case .external: "已授权的外部目录"
        }
    }
    private var chooseDirectory: (() -> Void)? {
        #if os(macOS)
            return {
                let panel = NSOpenPanel()
                panel.canChooseFiles = false
                panel.canChooseDirectories = true
                panel.allowsMultipleSelection = false
                panel.prompt = "选择下载目录"
                Task {
                    guard await panel.begin() == .OK, let directory = panel.url else { return }
                    do { try await dependencies.downloads.chooseDirectory(directory) } catch {
                        warning = error.localizedDescription
                    }
                }
            }
        #else
            return nil
        #endif
    }
    private var resetDirectory: (() -> Void)? {
        #if os(macOS)
            return {
                do { try dependencies.downloads.useManagedDirectory() } catch {
                    warning = error.localizedDescription
                }
            }
        #else
            return nil
        #endif
    }
}
