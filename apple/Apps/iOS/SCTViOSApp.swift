import SwiftUI

@main
struct SCTViOSApp: App {
    @UIApplicationDelegateAdaptor(NativeApplicationDelegate.self) private var nativeDelegate
    @State private var model = ApplicationModel()
    var body: some Scene {
        WindowGroup { ApplicationBootstrap(model: model) }
    }
}
