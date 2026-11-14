import Flutter
import UIKit

/// Owns file operations and the pending export reply for one Flutter engine.
final class FilesChannel: NSObject, FlutterPlugin {
  private struct PendingExport {
    let picker: UIDocumentPickerViewController
    let scene: UIWindowScene?
    let reply: FlutterResult
  }

  private let exportPresenter: () -> UIViewController?
  private var pendingExport: PendingExport?

  init(exportPresenter: @escaping () -> UIViewController? = FilesChannel.visibleController) {
    self.exportPresenter = exportPresenter
    super.init()

    NotificationCenter.default.addObserver(
      self,
      selector: #selector(sceneDidDisconnect(_:)),
      name: UIScene.didDisconnectNotification,
      object: nil
    )
  }

  /// Binds the file channel to this engine's lifetime.
  static func register(with registrar: FlutterPluginRegistrar) {
    let owner = FilesChannel()
    let channel = FlutterMethodChannel(
      name: "dev.sctvdl.flutter/files",
      binaryMessenger: registrar.messenger()
    )
    // Flutter only sends the engine-detach callback to published plugins.
    registrar.publish(owner)
    registrar.addMethodCallDelegate(owner, channel: channel)
  }

  /// Completes an outstanding export if Flutter destroys its engine first.
  func detachFromEngine(for registrar: FlutterPluginRegistrar) {
    cancelPendingExport()
  }

  /// Dispatches a file channel request and replies on the Flutter platform thread.
  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "excludeFromBackup":
      excludeFromBackup(call, result: result)
    case "export":
      export(call, result: result)
    default:
      result(FlutterMethodNotImplemented)
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

    guard pendingExport == nil else {
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

    guard let presenter = exportPresenter() else {
      result(presentationError())
      return
    }

    let picker = UIDocumentPickerViewController(forExporting: [url], asCopy: true)
    picker.delegate = self
    pendingExport = PendingExport(
      picker: picker,
      scene: presenter.viewIfLoaded?.window?.windowScene,
      reply: result
    )

    presenter.present(picker, animated: true)
    picker.presentationController?.delegate = self
    observePresentation(of: picker, from: presenter)
  }

  private func observePresentation(
    of picker: UIDocumentPickerViewController,
    from presenter: UIViewController
  ) {
    // An accepted presentation can still lose its transition before becoming visible.
    picker.transitionCoordinator?.animate(alongsideTransition: nil) {
      [weak self, weak picker] transition in
      if transition.isCancelled, let picker {
        self?.failPresentation(of: picker)
      }
    }

    // UIKit can decline a presentation without calling its completion or delegate.
    // Check for the modal relationship after UIKit has handled the presentation request.
    DispatchQueue.main.async { [weak self, weak presenter, weak picker] in
      guard let picker, picker.presentingViewController == nil,
        presenter?.presentedViewController !== picker
      else {
        return
      }

      self?.failPresentation(of: picker)
    }
  }

  private func failPresentation(of picker: UIDocumentPickerViewController) {
    finishExport(picker, result: presentationError())
  }

  private func presentationError() -> FlutterError {
    FlutterError(
      code: "export_unavailable",
      message: "The system export picker could not be presented",
      details: nil
    )
  }

  private func ownedURL(_ path: String) -> URL? {
    let url = URL(fileURLWithPath: path).standardizedFileURL
    let home = URL(fileURLWithPath: NSHomeDirectory()).standardizedFileURL.path + "/"
    return url.path.hasPrefix(home) ? url : nil
  }

  private static func visibleController() -> UIViewController? {
    let activeScenes = UIApplication.shared.connectedScenes.compactMap { scene in
      scene.activationState == .foregroundActive ? scene as? UIWindowScene : nil
    }
    let keyWindow = activeScenes.flatMap(\.windows).first(where: \.isKeyWindow)
    guard var controller = keyWindow?.rootViewController else {
      return nil
    }

    while let presented = controller.presentedViewController {
      controller = presented
    }

    guard controller.viewIfLoaded?.window != nil, !controller.isBeingDismissed,
      !controller.isBeingPresented
    else {
      return nil
    }

    return controller
  }

  @objc private func sceneDidDisconnect(_ notification: Notification) {
    guard let scene = notification.object as? UIWindowScene, pendingExport?.scene === scene else {
      return
    }

    cancelPendingExport()
  }

  private func cancelPendingExport() {
    guard let picker = pendingExport?.picker else {
      return
    }

    picker.dismiss(animated: false)
    finishExport(picker, result: false)
  }

  private func finishExport(_ controller: UIViewController, result: Any) {
    // UIKit callbacks can overlap or arrive after Flutter starts a new export.
    guard let pending = pendingExport, pending.picker === controller else {
      return
    }

    pendingExport = nil
    pending.picker.delegate = nil
    pending.picker.presentationController?.delegate = nil
    pending.reply(result)
  }
}

extension FilesChannel: UIDocumentPickerDelegate, UIAdaptivePresentationControllerDelegate {
  /// Completes an export once the document picker reports a destination.
  func documentPicker(
    _ controller: UIDocumentPickerViewController,
    didPickDocumentsAt urls: [URL]
  ) {
    finishExport(controller, result: !urls.isEmpty)
  }

  /// Treats the document picker's Cancel action as an ordinary false reply.
  func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
    finishExport(controller, result: false)
  }

  /// Handles interactive dismissal even if the picker never reports Cancel.
  func presentationControllerDidDismiss(_ presentationController: UIPresentationController) {
    let controller = presentationController.presentedViewController
    finishExport(controller, result: false)
  }
}
