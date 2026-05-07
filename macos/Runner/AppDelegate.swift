import Cocoa
import FlutterMacOS

@main
class AppDelegate: FlutterAppDelegate {
  var pendingFile: String?
  var methodChannel: FlutterMethodChannel?

  override func application(_ sender: NSApplication, openFile filename: String) -> Bool {
    let url = URL(fileURLWithPath: filename)
    handleFiles([url])
    return true
  }

  override func application(_ application: NSApplication, open urls: [URL]) {
    handleFiles(urls)
  }

  private func handleFiles(_ urls: [URL]) {
    for url in urls {
      let path = url.path
      if let channel = methodChannel {
        channel.invokeMethod("onFileOpened", arguments: path)
      } else {
        pendingFile = path
      }
    }
  }

  override func applicationDidFinishLaunching(_ notification: Notification) {
    let controller = mainFlutterWindow?.contentViewController as! FlutterViewController
    let channel = FlutterMethodChannel(name: "com.orthoquant.md/file_open", binaryMessenger: controller.engine.binaryMessenger)
    methodChannel = channel
    
    channel.setMethodCallHandler({ (call, result) in
      if call.method == "getInitialFile" {
        result(self.pendingFile)
        self.pendingFile = nil
      } else {
        result(FlutterMethodNotImplemented)
      }
    })
  }

  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    return true
  }

  override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    return true
  }
}
