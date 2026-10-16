import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate, UIDocumentPickerDelegate {
  private var exportResult: FlutterResult?
  private var exportPicker: UIDocumentPickerViewController?

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
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
