import Flutter
import UIKit
import QuickLook

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private let filePreview = MukaiFilePreview()

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    guard let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "MukaiFilePreview") else { return }
    let channel = FlutterMethodChannel(name: "com.mukai.mobile/preview", binaryMessenger: registrar.messenger())
    channel.setMethodCallHandler { [weak self] call, result in
      guard call.method == "open" else { result(FlutterMethodNotImplemented); return }
      guard let arguments = call.arguments as? [String: Any],
        let bytes = arguments["bytes"] as? FlutterStandardTypedData,
        let name = arguments["name"] as? String else {
        result(FlutterError(code: "invalid_file", message: "The preview file is missing.", details: nil)); return
      }
      DispatchQueue.main.async { self?.filePreview.open(bytes.data, name: name, result: result) }
    }
  }
}

/// Quick Look keeps PDF, audio, video and other supported files inside iOS.
/// Preview bytes live only in a dedicated temporary directory and are removed
/// after dismissal; a server-supplied name can never choose a filesystem path.
private final class MukaiFilePreview: NSObject, QLPreviewControllerDataSource, QLPreviewControllerDelegate {
  private var fileURL: URL?
  private var directory: URL?
  private var controller: QLPreviewController?

  func open(_ bytes: Data, name: String, result: @escaping FlutterResult) {
    guard controller == nil else {
      result(FlutterError(code: "preview_busy", message: "Close the current preview first.", details: nil)); return
    }
    let safeName = (name as NSString).lastPathComponent.filter { !$0.isNewline && $0 != "\0" }
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent("mukai-preview-" + UUID().uuidString, isDirectory: true)
    let file = folder.appendingPathComponent(safeName.isEmpty || safeName == "." || safeName == ".." ? "File" : safeName)
    do {
      try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
      try bytes.write(to: file, options: .atomic)
      guard QLPreviewController.canPreview(file as NSURL) else {
        try? FileManager.default.removeItem(at: folder)
        result(FlutterError(code: "unsupported_file", message: "Use Share to open this file in another app.", details: nil)); return
      }
      let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
      var presenter = scenes.flatMap { $0.windows }.first(where: { $0.isKeyWindow })?.rootViewController
      while let next = presenter?.presentedViewController { presenter = next }
      guard let presenter = presenter else {
        try? FileManager.default.removeItem(at: folder)
        result(FlutterError(code: "no_presenter", message: "The native viewer is unavailable.", details: nil)); return
      }
      directory = folder; fileURL = file
      let preview = QLPreviewController()
      preview.dataSource = self; preview.delegate = self
      controller = preview
      presenter.present(preview, animated: true) { result(nil) }
    } catch {
      try? FileManager.default.removeItem(at: folder)
      result(FlutterError(code: "preview_failed", message: "The file could not be prepared for preview.", details: nil))
    }
  }

  func numberOfPreviewItems(in controller: QLPreviewController) -> Int { fileURL == nil ? 0 : 1 }
  func previewController(_ controller: QLPreviewController, previewItemAt index: Int) -> QLPreviewItem { fileURL! as NSURL }
  func previewControllerDidDismiss(_ controller: QLPreviewController) {
    if let directory = directory { try? FileManager.default.removeItem(at: directory) }
    self.controller = nil; fileURL = nil; directory = nil
  }
}
