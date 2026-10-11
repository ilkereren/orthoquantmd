import Flutter
import UIKit

import UserNotifications

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private var fileChannel: FlutterMethodChannel?
  // Calls made before the Flutter engine exists (e.g. a URL on cold launch).
  private var pendingFileChannelCalls: [(method: String, arguments: Any?)] = []

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {

    UNUserNotificationCenter.current().delegate = self as? UNUserNotificationCenterDelegate

    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  // Under the UIScene lifecycle the engine is created by the storyboard's
  // FlutterViewController, so window?.rootViewController is not available in
  // didFinishLaunching. Plugins and channels are registered here instead.
  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)

    let channel = FlutterMethodChannel(name: "com.orthoquant.md/file_open",
                                       binaryMessenger: engineBridge.applicationRegistrar.messenger())

    channel.setMethodCallHandler({
      (call: FlutterMethodCall, result: @escaping FlutterResult) -> Void in
      if call.method == "getInitialFile" {
        let appGroupId = "group.com.ilkereren.orthoquant"
        let sharedKey = "ShareKey"
        if let userDefaults = UserDefaults(suiteName: appGroupId) {
            if let savedPath = userDefaults.string(forKey: sharedKey) {
                // Clear it so we don't open it again next time
                userDefaults.set(nil, forKey: sharedKey)
                userDefaults.synchronize()
                if userDefaults.object(forKey: sharedKey) == nil {
                     print("DEBUG: Successfully cleared shared file key from UserDefaults")
                } else {
                     print("DEBUG: FAILED to clear shared file key from UserDefaults")
                }
                result(savedPath)
                return
            }
        }
        result(nil)
      } else if call.method == "requestNotificationPermission" {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            print("Notification permission granted: \(granted)")
            result(granted)
        }
      } else {
        result(FlutterMethodNotImplemented)
      }
    })

    fileChannel = channel
    for call in pendingFileChannelCalls {
      channel.invokeMethod(call.method, arguments: call.arguments)
    }
    pendingFileChannelCalls.removeAll()
  }

  private func invokeFileChannel(_ method: String, arguments: Any? = nil) {
    if let fileChannel = fileChannel {
      fileChannel.invokeMethod(method, arguments: arguments)
    } else {
      pendingFileChannelCalls.append((method: method, arguments: arguments))
    }
  }

  /// Handles ShareMedia and file URLs. Called from SceneDelegate, which
  /// receives URL opens under the UIScene lifecycle. Returns false for URLs
  /// that should be passed on to plugins.
  func handleIncomingURL(_ url: URL) -> Bool {
    // Check for ShareMedia custom scheme
    if let scheme = url.scheme, scheme.caseInsensitiveCompare("ShareMedia") == .orderedSame {
        invokeFileChannel("onShareIntent")
        return true
    }

    // Check if it's a file URL
    if url.isFileURL {
      let startAccess = url.startAccessingSecurityScopedResource()

      defer {
        if startAccess {
          url.stopAccessingSecurityScopedResource()
        }
      }

      do {
        // Create a temp file path
        let tempDirectoryURL = FileManager.default.temporaryDirectory
        let destinationURL = tempDirectoryURL.appendingPathComponent(url.lastPathComponent)

        // Remove existing file if necessary
        if FileManager.default.fileExists(atPath: destinationURL.path) {
          try FileManager.default.removeItem(at: destinationURL)
        }

        // Copy the file
        try FileManager.default.copyItem(at: url, to: destinationURL)

        // Send the NEW path to Flutter via MethodChannel (reusing the one we set up for desktop)
        invokeFileChannel("onFileOpened", arguments: destinationURL.path)

        return true
      } catch {
        print("Error copying file: \(error)")
        return false
      }
    }

    return false
  }
}
