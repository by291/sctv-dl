import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  /// Registers Flutter plugins and the host channels on the implicit engine.
  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    let registry = engineBridge.pluginRegistry
    GeneratedPluginRegistrant.register(with: registry)

    if let playerRegistrar = registry.registrar(forPlugin: "SctvPlayerEnvironment") {
      PlayerEnvironment.register(with: playerRegistrar)
    }
    if let filesRegistrar = registry.registrar(forPlugin: "SctvFiles") {
      FilesChannel.register(with: filesRegistrar)
    }
  }
}
