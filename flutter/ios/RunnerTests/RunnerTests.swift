import Flutter
import UIKit
import XCTest

@testable import Runner

final class RunnerTests: XCTestCase {
  @MainActor
  func testRejectedPresentationReleasesExportForRetry() throws {
    let video = try makeVideo()
    defer {
      try? FileManager.default.removeItem(at: video)
    }
    let presenter = ExportPresenter()
    let files = FilesChannel(exportPresenter: { presenter })
    let rejection = expectation(description: "UIKit rejected the export")

    files.handle(exportCall(for: video)) { result in
      XCTAssertEqual((result as? FlutterError)?.code, "export_unavailable")
      rejection.fulfill()
    }
    wait(for: [rejection], timeout: 1)

    presenter.acceptsPresentation = true
    let retry = expectation(description: "The next export can complete")
    files.handle(exportCall(for: video)) { result in
      XCTAssertEqual(result as? Bool, true)
      retry.fulfill()
    }
    let picker = try XCTUnwrap(presenter.picker)
    picker.delegate?.documentPicker?(picker, didPickDocumentsAt: [video])

    wait(for: [retry], timeout: 1)
  }

  @MainActor
  func testCancelledExportCanRetryWithoutConsumingItsResult() throws {
    let video = try makeVideo()
    defer {
      try? FileManager.default.removeItem(at: video)
    }
    let presenter = ExportPresenter()
    presenter.acceptsPresentation = true
    let files = FilesChannel(exportPresenter: { presenter })
    var cancelledResults = [Bool]()
    var retryResults = [Bool]()

    files.handle(exportCall(for: video)) { result in
      XCTAssertEqual(result as? Bool, false)
      cancelledResults.append(result as? Bool ?? true)
    }
    let cancelled = try XCTUnwrap(presenter.picker)
    cancelled.delegate?.documentPickerWasCancelled?(cancelled)
    files.handle(exportCall(for: video)) { result in
      XCTAssertEqual(result as? Bool, true)
      retryResults.append(result as? Bool ?? false)
    }
    let retry = try XCTUnwrap(presenter.picker)

    files.documentPicker(cancelled, didPickDocumentsAt: [video])
    XCTAssertTrue(retryResults.isEmpty)
    retry.delegate?.documentPicker?(retry, didPickDocumentsAt: [video])

    XCTAssertEqual(cancelledResults, [false])
    XCTAssertEqual(retryResults, [true])
  }

  private func makeVideo() throws -> URL {
    let video = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString)
      .appendingPathExtension("mp4")
    try Data([0]).write(to: video)
    return video
  }

  private func exportCall(for video: URL) -> FlutterMethodCall {
    FlutterMethodCall(methodName: "export", arguments: ["path": video.path])
  }
}

@MainActor
private final class ExportPresenter: UIViewController {
  var acceptsPresentation = false
  private(set) var picker: UIDocumentPickerViewController?

  override var presentedViewController: UIViewController? {
    picker
  }

  override func present(
    _ viewControllerToPresent: UIViewController,
    animated flag: Bool,
    completion: (() -> Void)? = nil
  ) {
    if acceptsPresentation {
      picker = viewControllerToPresent as? UIDocumentPickerViewController
      completion?()
    }
  }
}
