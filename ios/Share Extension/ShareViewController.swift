import UIKit
import Social
import MobileCoreServices
import Photos
import UserNotifications

class ShareViewController: UIViewController {
    // KENDİ APP GROUP ID'NİZİ BURAYA YAZIN:
    let appGroupId = "group.com.ilkereren.orthoquant"
    let sharedKey = "ShareKey"

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        
        // Show a loading indicator
        let activityIndicator = UIActivityIndicatorView(style: .large)
        activityIndicator.center = view.center
        activityIndicator.startAnimating()
        view.addSubview(activityIndicator)
        view.backgroundColor = .systemBackground
        
        // Process the attachment
        if let content = extensionContext!.inputItems[0] as? NSExtensionItem {
            if let contents = content.attachments {
                for (index, attachment) in (contents).enumerated() {
                    if attachment.hasItemConformingToTypeIdentifier(kUTTypeImage as String) {
                        handleImage(content: content, attachment: attachment, index: index)
                        return
                    }
                }
            }
        }
        // If no image found, close
        extensionContext!.completeRequest(returningItems: [], completionHandler: nil)
    }

    private func handleImage(content: NSExtensionItem, attachment: NSItemProvider, index: Int) {
        attachment.loadItem(forTypeIdentifier: kUTTypeImage as String, options: nil) { [weak self] data, error in
            guard let this = self, let url = data as? URL, error == nil else {
                self?.extensionContext!.completeRequest(returningItems: [], completionHandler: nil)
                return
            }
            
            // Dosyayı App Group container'ına kopyala
            if let sharedContainer = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: this.appGroupId) {
                let fileName = "shared_image_\(Date().timeIntervalSince1970).jpg"
                let destinationURL = sharedContainer.appendingPathComponent(fileName)
                
                do {
                    if FileManager.default.fileExists(atPath: destinationURL.path) {
                        try FileManager.default.removeItem(at: destinationURL)
                    }
                    try FileManager.default.copyItem(at: url, to: destinationURL)
                    
                    // Ana uygulamayı tetikle
                    this.redirectToHostApp(savedPath: destinationURL.path)
                } catch {
                    print("Error saving file: \(error)")
                }
            }
        }
    }
    private func redirectToHostApp(savedPath: String) {
        // Shared Preferences (UserDefaults) ile yolu kaydet
        if let userDefaults = UserDefaults(suiteName: appGroupId) {
            userDefaults.set(savedPath, forKey: sharedKey)
            userDefaults.synchronize()
        }
        
        let url = URL(string: "ShareMedia://dataUrl=\(sharedKey)")!
        
        // Ensure UI operations are on main thread
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            // 1. Try extensionContext official API (Best effort)
            self.extensionContext?.open(url, completionHandler: nil)
            
            // 2. Schedule Local Notification (Fallback)
            // Even if openURL was called, it might fail silently in background.
            // This notification ensures user has a way to open the app.
            let content = UNMutableNotificationContent()
            content.title = "Image Received"
            content.body = "Tap to open OrthoQuant MD and measure."
            content.sound = UNNotificationSound.default
            
            // Trigger in 0.5 seconds
            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 0.5, repeats: false)
            let request = UNNotificationRequest(identifier: "OpenAppFallback", content: content, trigger: trigger)
            
            UNUserNotificationCenter.current().add(request) { (error) in
                if let error = error {
                    print("Error scheduling notification: \(error)")
                }
            }

            self.extensionContext!.completeRequest(returningItems: [], completionHandler: nil)
        }
    }
    
    // Helper to form selector
    func selector(string: String) -> Selector {
        return Selector(string)
    }
}
