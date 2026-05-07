import Flutter
import UIKit

import UserNotifications

@main
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    
    UNUserNotificationCenter.current().delegate = self as? UNUserNotificationCenterDelegate
    
    let controller : FlutterViewController = window?.rootViewController as! FlutterViewController
    let fileChannel = FlutterMethodChannel(name: "com.orthoquant.md/file_open",
                                          binaryMessenger: controller.binaryMessenger)
    
    fileChannel.setMethodCallHandler({
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

    GeneratedPluginRegistrant.register(with: self)
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  override func application(_ app: UIApplication, open url: URL, options: [UIApplication.OpenURLOptionsKey : Any] = [:]) -> Bool {
    // Check for ShareMedia custom scheme
    if let scheme = url.scheme, scheme.caseInsensitiveCompare("ShareMedia") == .orderedSame {
        let controller : FlutterViewController = window?.rootViewController as! FlutterViewController
        let fileChannel = FlutterMethodChannel(name: "com.orthoquant.md/file_open",
                                              binaryMessenger: controller.binaryMessenger)
        fileChannel.invokeMethod("onShareIntent", arguments: nil)
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
        let controller : FlutterViewController = window?.rootViewController as! FlutterViewController
        let fileChannel = FlutterMethodChannel(name: "com.orthoquant.md/file_open",
                                              binaryMessenger: controller.binaryMessenger)
        fileChannel.invokeMethod("onFileOpened", arguments: destinationURL.path)
        
        return true
      } catch {
        print("Error copying file: \(error)")
        return false
      }
    }
    
    return super.application(app, open: url, options: options)
  }
}
