import Flutter
import UIKit

/// Owns the pending export result until the system picker completes or cancels.
final class FilesChannel: NSObject, UIDocumentPickerDelegate {
  private var exportResult: FlutterResult?
  private var exportPicker: UIDocumentPickerViewController?

  func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(
      name: "dev.sctvdl.flutter/files", binaryMessenger: registrar.messenger())
    channel.setMethodCallHandler { [weak self] call, result in
      guard let self else {
        result(
          FlutterError(code: "files_unavailable", message: "File owner was released", details: nil))
        return
      }
      switch call.method {
      case "excludeFromBackup": excludeFromBackup(call, result: result)
      case "export": export(call, result: result)
      default: result(FlutterMethodNotImplemented)
      }
    }
  }

  private func excludeFromBackup(_ call: FlutterMethodCall, result: FlutterResult) {
    guard let arguments = call.arguments as? [String: Any],
      let path = arguments["path"] as? String,
      var url = ownedURL(path)
    else {
      result(false)
      return
    }

    do {
      var values = URLResourceValues()
      values.isExcludedFromBackup = true
      try url.setResourceValues(values)
      let confirmed =
        try url.resourceValues(forKeys: [.isExcludedFromBackupKey])
        .isExcludedFromBackup == true
      result(confirmed)
    } catch {
      result(
        FlutterError(
          code: "backup_exclusion_failed", message: error.localizedDescription, details: nil))
    }
  }

  private func export(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard let arguments = call.arguments as? [String: Any], let path = arguments["path"] as? String
    else {
      result(
        FlutterError(code: "invalid_path", message: "A local video path is required", details: nil))
      return
    }
    guard exportResult == nil else {
      result(
        FlutterError(code: "export_busy", message: "Another export is already open", details: nil))
      return
    }
    guard let url = ownedURL(path), FileManager.default.fileExists(atPath: url.path) else {
      result(
        FlutterError(
          code: "missing_file", message: "The app-owned video is unavailable", details: nil))
      return
    }

    let picker = UIDocumentPickerViewController(forExporting: [url], asCopy: true)
    picker.delegate = self
    exportResult = result
    exportPicker = picker
    guard let presenter = visibleController() else {
      finishExport(false)
      return
    }
    presenter.present(picker, animated: true)
  }

  private func ownedURL(_ path: String) -> URL? {
    let url = URL(fileURLWithPath: path).standardizedFileURL
    let home = URL(fileURLWithPath: NSHomeDirectory()).standardizedFileURL.path + "/"
    return url.path.hasPrefix(home) ? url : nil
  }

  private func visibleController() -> UIViewController? {
    var controller = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
      .flatMap(\.windows).first(where: \.isKeyWindow)?.rootViewController
    while let presented = controller?.presentedViewController { controller = presented }
    return controller
  }

  func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL])
  {
    finishExport(!urls.isEmpty)
  }

  func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
    finishExport(false)
  }

  private func finishExport(_ success: Bool) {
    let result = exportResult
    exportResult = nil
    exportPicker = nil
    result?(success)
  }
}
