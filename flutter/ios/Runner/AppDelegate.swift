import Flutter
import UIKit
import MediaPlayer

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate, UIDocumentPickerDelegate {
  private var exportResult: FlutterResult?
  private var exportPicker: UIDocumentPickerViewController?

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    let playerRegistrar = engineBridge.pluginRegistry.registrar(forPlugin: "SctvPlayerEnvironment")!
    PlayerEnvironment.register(with: playerRegistrar)
    let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "SctvFiles")!
    let channel = FlutterMethodChannel(name: "dev.sctvdl.flutter/files", binaryMessenger: registrar.messenger())
    channel.setMethodCallHandler { [weak self] call, result in
      if call.method == "excludeFromBackup" {
        guard let arguments = call.arguments as? [String: Any], let path = arguments["path"] as? String else { result(false); return }
        var url = URL(fileURLWithPath: path).standardizedFileURL
        let home = URL(fileURLWithPath: NSHomeDirectory()).standardizedFileURL.path + "/"
        guard url.path.hasPrefix(home) else { result(false); return }
        do {
          var values = URLResourceValues()
          values.isExcludedFromBackup = true
          try url.setResourceValues(values)
          let confirmed = try url.resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup == true
          result(confirmed)
        } catch { result(FlutterError(code: "backup_exclusion_failed", message: error.localizedDescription, details: nil)) }
        return
      }
      guard call.method == "export" else { result(FlutterMethodNotImplemented); return }
      guard let self = self, let arguments = call.arguments as? [String: Any], let path = arguments["path"] as? String else {
        result(FlutterError(code: "invalid_path", message: "A local video path is required", details: nil)); return
      }
      guard self.exportResult == nil else {
        result(FlutterError(code: "export_busy", message: "Another export is already open", details: nil)); return
      }
      let url = URL(fileURLWithPath: path).standardizedFileURL
      let home = URL(fileURLWithPath: NSHomeDirectory()).standardizedFileURL.path + "/"
      guard url.path.hasPrefix(home), FileManager.default.fileExists(atPath: url.path) else {
        result(FlutterError(code: "missing_file", message: "The app-owned video is unavailable", details: nil)); return
      }
      let picker = UIDocumentPickerViewController(forExporting: [url], asCopy: true)
      picker.delegate = self
      self.exportResult = result
      self.exportPicker = picker
      guard let presenter = self.visibleController() else {
        self.finishExport(false); return
      }
      presenter.present(picker, animated: true)
    }
  }

  private func visibleController() -> UIViewController? {
    var controller = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
      .flatMap(\.windows).first(where: \.isKeyWindow)?.rootViewController
    while let presented = controller?.presentedViewController { controller = presented }
    return controller
  }

  func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
    finishExport(!urls.isEmpty)
  }

  func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) { finishExport(false) }

  private func finishExport(_ success: Bool) {
    let result = exportResult
    exportResult = nil
    exportPicker = nil
    result?(success)
  }
}


/// Public system volume UI: only the user's interaction changes its volume.
private final class SystemVolumeFactory: NSObject, FlutterPlatformViewFactory {
  func create(withFrame frame: CGRect, viewIdentifier viewId: Int64, arguments args: Any?) -> FlutterPlatformView {
    SystemVolumeView(frame: frame)
  }
}
private final class SystemVolumeView: NSObject, FlutterPlatformView {
  private let control: MPVolumeView
  init(frame: CGRect) {
    control = MPVolumeView(frame: frame)
    control.showsRouteButton = false
    control.accessibilityLabel = "系统音量"
    super.init()
  }
  func view() -> UIView { control }
}
private final class PlayerEnvironment: NSObject {
  private var enteringBrightness: CGFloat?
  private var backgroundObserver: NSObjectProtocol?
  private var screen: UIScreen? {
    UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first?.screen
  }
  static func register(with registrar: FlutterPluginRegistrar) {
    let owner = PlayerEnvironment()
    registrar.register(SystemVolumeFactory(), withId: "dev.sctvdl.flutter/system_volume")
    let channel = FlutterMethodChannel(name: "dev.sctvdl.flutter/player_environment", binaryMessenger: registrar.messenger())
    channel.setMethodCallHandler { call, result in owner.handle(call, result: result) }
    owner.backgroundObserver = NotificationCenter.default.addObserver(forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main) { [weak owner] _ in owner?.restore() }
  }
  deinit {
    if let observer = backgroundObserver { NotificationCenter.default.removeObserver(observer) }
  }
  private func restore() {
    if let brightness = enteringBrightness { screen?.brightness = brightness }
    enteringBrightness = nil
  }
  private func handle(_ call: FlutterMethodCall, result: FlutterResult) {
    switch call.method {
    case "brightness", "beginBrightness":
      let value = screen?.brightness ?? 0.5
      if call.method == "beginBrightness" && enteringBrightness == nil { enteringBrightness = value }
      result(Double(value))
    case "setBrightness":
      guard let value = call.arguments as? Double, value.isFinite else { result(FlutterError(code: "invalid_brightness", message: "Expected finite brightness", details: nil)); return }
      if enteringBrightness == nil { enteringBrightness = screen?.brightness }
      screen?.brightness = CGFloat(min(1, max(0, value)))
      result(nil)
    case "restoreBrightness": restore(); result(nil)
    case "needsGestureHint":
      let show = !UserDefaults.standard.bool(forKey: "player_gesture_hint_seen")
      result(show)
    case "acknowledgeGestureHint":
      UserDefaults.standard.set(true, forKey: "player_gesture_hint_seen")
      result(nil)
    default: result(FlutterMethodNotImplemented)
    }
  }
}
