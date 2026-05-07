import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    
    // Set size for iPad 13" aspect ratio (logical points: 1024 x 1366)
    let screenSize = NSScreen.main?.visibleFrame.size ?? CGSize(width: 1920, height: 1080)
    let targetHeight: CGFloat = screenSize.height * 0.9 
    let targetWidth: CGFloat = targetHeight * (1024.0 / 1366.0)
    
    // Define the frame
    let windowFrame = NSRect(
      x: (screenSize.width - targetWidth) / 2,
      y: (screenSize.height - targetHeight) / 2 + (screenSize.height * 0.05),
      width: targetWidth,
      height: targetHeight
    )
    
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)
    
    // LOCK ASPECT RATIO
    self.contentAspectRatio = NSSize(width: 1024, height: 1366)
    
    // Optional: If you want to prevent ANY resizing to keep it perfectly at this size:
    // self.styleMask.remove(.resizable)
    
    // Or set min/max to maintain scale but keep ratio
    self.minSize = NSSize(width: 400 * (1024.0/1366.0), height: 400)
    
    // Make it "penceresiz" (borderless/clean look)
    self.titleVisibility = .hidden
    self.titlebarAppearsTransparent = true
    self.styleMask.insert(.fullSizeContentView)

    RegisterGeneratedPlugins(registry: flutterViewController)

    super.awakeFromNib()
  }
}
