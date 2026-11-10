import Flutter
import UIKit
import QuickLook
import UserNotifications

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private let filePreview = MukaiFilePreview()
  private let pushNotifications = MukaiPushNotifications()

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    UNUserNotificationCenter.current().delegate = self
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "MukaiPushNotifications") {
      pushNotifications.install(registrar.messenger())
    }
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "MukaiGlass") {
      let glass = FlutterMethodChannel(name: "com.mukai.mobile/glass", binaryMessenger: registrar.messenger())
      glass.setMethodCallHandler { call, result in
        switch call.method {
        case "isAvailable":
          if #available(iOS 26.0, *) { result(true) } else { result(false) }
        case "appearance":
          let args = call.arguments as? [String: Any]
          let dark = (args?["dark"] as? NSNumber)?.boolValue ?? false
          MukaiGlassView.setDark(dark)
          result(nil)
        default: result(FlutterMethodNotImplemented)
        }
      }
      registrar.register(MukaiGlassViewFactory(), withId: "mukai/glass_pill")
    }
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
  override func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken token: Data) {
    pushNotifications.registered(token)
    super.application(application, didRegisterForRemoteNotificationsWithDeviceToken: token)
  }
  override func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
    pushNotifications.failed(error)
    super.application(application, didFailToRegisterForRemoteNotificationsWithError: error)
  }
  override func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
    withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
    if let payload = notification.request.content.userInfo["mukai"] as? [String: Any] {
      if payload["type"] as? String == "pairing" {
        pushNotifications.emit(payload); completionHandler([])
      } else if pushNotifications.isVisible(payload) { completionHandler([]) }
      else { completionHandler([.banner, .sound]) }
    } else { super.userNotificationCenter(center, willPresent: notification, withCompletionHandler: completionHandler) }
  }
  override func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
    withCompletionHandler completionHandler: @escaping () -> Void) {
    if let payload = response.notification.request.content.userInfo["mukai"] as? [String: Any] {
      pushNotifications.emit(payload); completionHandler()
    } else { super.userNotificationCenter(center, didReceive: response, withCompletionHandler: completionHandler) }
  }
  override func application(_ application: UIApplication, didReceiveRemoteNotification userInfo: [AnyHashable: Any],
    fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void) {
    if let payload = userInfo["mukai"] as? [String: Any], payload["type"] as? String == "pairing" {
      pushNotifications.emit(payload); completionHandler(.newData)
    } else { super.application(application, didReceiveRemoteNotification: userInfo, fetchCompletionHandler: completionHandler) }
  }

}

/// Apple's liquid glass as a background material for Flutter-drawn controls.
/// Flutter keeps the buttons and their behaviour; this view only supplies the
/// UIGlassEffect material underneath. It is mounted only when the Dart side
/// sees `isAvailable` (iOS 26+); everywhere else the pre-glass UI is kept.
private final class MukaiGlassView: UIView {
  private let effectView = UIVisualEffectView()
  private let cornerRadius: CGFloat
  private var appliedStyle: UIUserInterfaceStyle?

  /// Live pills, so an in-app Light/Dark flip — which never changes the
  /// system appearance — can restyle every mounted pill at once. Weak: the
  /// platform view's lifetime decides membership.
  private static let mounted = NSHashTable<MukaiGlassView>.weakObjects()

  static func setDark(_ dark: Bool) {
    for view in mounted.allObjects {
      view.overrideUserInterfaceStyle = dark ? .dark : .light
    }
  }

  init(args: [String: Any?]?) {
    cornerRadius = (args?["cornerRadius"] as? NSNumber).map { CGFloat($0.doubleValue) } ?? 22
    super.init(frame: .zero)
    // The app can force Light or Dark while the system sits in the other
    // mode; a platform view only ever sees the system appearance, so Dart
    // passes the brightness explicitly and we pin the view's traits to it.
    if let dark = (args?["dark"] as? NSNumber)?.boolValue {
      overrideUserInterfaceStyle = dark ? .dark : .light
    }
    layer.cornerRadius = cornerRadius
    layer.cornerCurve = .continuous
    clipsToBounds = true
    addSubview(effectView)
    Self.mounted.add(self)
    applyGlass()
  }

  /// `.regular` glass tints heavily on light backgrounds and reads as a flat
  /// grey blob; `.clear` keeps the rim refraction without the fill, which is
  /// how ChatGPT's light-mode controls look. Dark keeps the richer `.regular`.
  private func applyGlass() {
    if #available(iOS 26.0, *) {
      let style = traitCollection.userInterfaceStyle
      guard style != .unspecified, style != appliedStyle else { return }
      appliedStyle = style
      let glass = UIGlassEffect(style: style == .light ? .clear : .regular)
      glass.isInteractive = true
      effectView.effect = glass
    } else {
      // Never mounted below iOS 26; stay boring if it somehow is.
      effectView.effect = UIBlurEffect(style: .systemThinMaterial)
    }
  }

  override func didMoveToWindow() {
    super.didMoveToWindow()
    // Traits are only trustworthy once the view has a window; the factory
    // builds the view before it joins one.
    if window != nil { applyGlass() }
  }

  override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
    super.traitCollectionDidChange(previousTraitCollection)
    if traitCollection.hasDifferentColorAppearance(comparedTo: previousTraitCollection) {
      applyGlass()
    }
  }

  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

  override func layoutSubviews() {
    super.layoutSubviews()
    effectView.frame = bounds
    effectView.layer.cornerRadius = cornerRadius
    effectView.layer.cornerCurve = .continuous
  }
}

private final class MukaiGlassPlatformView: NSObject, FlutterPlatformView {
  private let glassView: MukaiGlassView
  init(view: MukaiGlassView) { glassView = view }
  func view() -> UIView { glassView }
}

private final class MukaiGlassViewFactory: NSObject, FlutterPlatformViewFactory {
  func createArgsCodec() -> FlutterMessageCodec & NSObjectProtocol {
    FlutterStandardMessageCodec.sharedInstance()
  }

  func create(
    withFrame frame: CGRect, viewIdentifier viewId: Int64, arguments args: Any?
  ) -> FlutterPlatformView {
    MukaiGlassPlatformView(view: MukaiGlassView(args: args as? [String: Any]))
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

/// Native APNs only; no Firebase SDK or credentials are embedded in the client.
private final class MukaiPushNotifications {
  private var channel: FlutterMethodChannel?
  private var pendingRegistration: FlutterResult?
  private var events: [[String: Any]] = []
  private var visibleServer = ""
  private var visibleConversation = ""
  func install(_ messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(name: "com.mukai.mobile/push", binaryMessenger: messenger)
    self.channel = channel
    channel.setMethodCallHandler { [weak self] call, result in
      guard let self = self else { return }
      switch call.method {
      case "register":
        guard self.pendingRegistration == nil else {
          result(FlutterError(code: "registration_busy", message: "Notification registration is in progress.", details: nil)); return
        }
        self.pendingRegistration = result
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound]) { allowed, _ in
          DispatchQueue.main.async {
            if allowed { UIApplication.shared.registerForRemoteNotifications() }
            else { self.pendingRegistration?(["authorized": false]); self.pendingRegistration = nil }
          }
        }
      case "drain": let queued = self.events; self.events.removeAll(); result(queued)
      case "visible":
        let args = call.arguments as? [String: String] ?? [:]
        self.visibleServer = args["serverId"] ?? ""
        self.visibleConversation = args["conversationId"] ?? ""
        result(nil)
      case "openSettings":
        if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
        result(nil)
      case "clear":
        UNUserNotificationCenter.current().removeAllDeliveredNotifications()
        result(nil)
      default: result(FlutterMethodNotImplemented)
      }
    }
  }
  private func environment() -> String {
    // A distribution profile overrides Debug defaults; TestFlight uses production.
    if let path = Bundle.main.url(forResource: "embedded", withExtension: "mobileprovision"),
      let data = try? Data(contentsOf: path), let text = String(data: data, encoding: .isoLatin1),
      let start = text.range(of: "<?xml"), let end = text.range(of: "</plist>"),
      let xml = String(text[start.lowerBound..<end.upperBound]).data(using: .utf8),
      let profile = try? PropertyListSerialization.propertyList(from: xml, format: nil) as? [String: Any],
      let entitlements = profile["Entitlements"] as? [String: Any],
      let value = entitlements["aps-environment"] as? String { return value == "production" ? "production" : "sandbox" }
    return Bundle.main.object(forInfoDictionaryKey: "MukaiAPNSEnvironment") as? String == "production" ? "production" : "sandbox"
  }
  func registered(_ token: Data) {
    let value: [String: Any] = ["authorized": true, "deviceToken": token.map { String(format: "%02x", $0) }.joined(), "environment": environment()]
    if let result = pendingRegistration { pendingRegistration = nil; result(value) }
    else { emit(value.merging(["type": "tokenChanged"]) { _, new in new }) }
  }
  func failed(_ error: Error) {
    let failure = error as NSError
    // This OS registration error contains no relay credentials or provider key.
    NSLog("[Mukai push] APNs registration failed: %@ (%ld): %@", failure.domain, failure.code, failure.localizedDescription)
    pendingRegistration?(FlutterError(code: "apns_unavailable", message: "Apple notification registration failed. Check the app's signing and push capability.", details: ["domain": failure.domain, "code": failure.code, "reason": failure.localizedDescription]))
    pendingRegistration = nil
  }
  func isVisible(_ payload: [String: Any]) -> Bool {
    return !visibleConversation.isEmpty && payload["serverId"] as? String == visibleServer && payload["conversationId"] as? String == visibleConversation
  }
  func emit(_ payload: [String: Any]) {
    DispatchQueue.main.async {
      let eventId = UUID().uuidString
      var event = payload; event["nativeEventId"] = eventId
      self.events.append(event)
      if self.events.count > 32 { self.events.removeFirst() }
      self.channel?.invokeMethod("event", arguments: event) { answer in
        if answer as? Bool == true { self.events.removeAll { $0["nativeEventId"] as? String == eventId } }
      }
    }
  }
}
