import Flutter
import MediaPlayer
import UIKit

/// Public system volume UI: only the user's interaction changes its volume.
private final class SystemVolumeFactory: NSObject, FlutterPlatformViewFactory {
  func create(withFrame frame: CGRect, viewIdentifier viewId: Int64, arguments args: Any?)
    -> FlutterPlatformView
  {
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
final class PlayerEnvironment: NSObject {
  private var enteringBrightness: CGFloat?
  private var backgroundObserver: NSObjectProtocol?
  private var screen: UIScreen? {
    UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first?.screen
  }
  static func register(with registrar: FlutterPluginRegistrar) {
    let owner = PlayerEnvironment()
    registrar.register(SystemVolumeFactory(), withId: "dev.sctvdl.flutter/system_volume")
    let channel = FlutterMethodChannel(
      name: "dev.sctvdl.flutter/player_environment", binaryMessenger: registrar.messenger())
    channel.setMethodCallHandler { call, result in owner.handle(call, result: result) }
    owner.backgroundObserver = NotificationCenter.default.addObserver(
      forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main
    ) { [weak owner] _ in owner?.restore() }
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
      if call.method == "beginBrightness" && enteringBrightness == nil {
        enteringBrightness = value
      }
      result(Double(value))
    case "setBrightness":
      guard let value = call.arguments as? Double, value.isFinite else {
        result(
          FlutterError(
            code: "invalid_brightness", message: "Expected finite brightness", details: nil))
        return
      }
      if enteringBrightness == nil { enteringBrightness = screen?.brightness }
      screen?.brightness = CGFloat(min(1, max(0, value)))
      result(nil)
    case "restoreBrightness":
      restore()
      result(nil)
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
