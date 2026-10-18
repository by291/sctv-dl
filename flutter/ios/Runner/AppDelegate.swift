import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private let files = FilesChannel()

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    let playerRegistrar = engineBridge.pluginRegistry.registrar(forPlugin: "SctvPlayerEnvironment")!
    PlayerEnvironment.register(with: playerRegistrar)
    let filesRegistrar = engineBridge.pluginRegistry.registrar(forPlugin: "SctvFiles")!
    files.register(with: filesRegistrar)
  }
}
