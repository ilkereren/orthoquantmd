import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    
    // Open in a roomy iPad-like landscape layout, while keeping resizing free.
    let screenSize = NSScreen.main?.visibleFrame.size ?? CGSize(width: 1920, height: 1080)
    let targetWidth: CGFloat = min(1180, screenSize.width * 0.86)
    let targetHeight: CGFloat = min(820, screenSize.height * 0.82)
    
    // Define the frame
    let windowFrame = NSRect(
      x: (screenSize.width - targetWidth) / 2,
      y: (screenSize.height - targetHeight) / 2 + (screenSize.height * 0.05),
      width: targetWidth,
      height: targetHeight
    )
    
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)
    self.minSize = NSSize(width: 780, height: 560)

    // Keep a native titlebar so the macOS traffic-light buttons do not overlap
    // the Flutter top toolbar.
    self.titleVisibility = .hidden
    self.titlebarAppearsTransparent = false

    RegisterGeneratedPlugins(registry: flutterViewController)

    super.awakeFromNib()
  }
}
