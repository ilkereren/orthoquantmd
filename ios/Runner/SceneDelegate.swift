import Flutter
import UIKit

class SceneDelegate: FlutterSceneDelegate {

  private var appDelegate: AppDelegate? {
    UIApplication.shared.delegate as? AppDelegate
  }

  // Cold launch: URLs the app was opened with arrive here instead of
  // application(_:open:options:) under the UIScene lifecycle.
  override func scene(
    _ scene: UIScene,
    willConnectTo session: UISceneSession,
    options connectionOptions: UIScene.ConnectionOptions
  ) {
    super.scene(scene, willConnectTo: session, options: connectionOptions)
    for context in connectionOptions.urlContexts {
      _ = appDelegate?.handleIncomingURL(context.url)
    }
  }

  // Warm launch: the app is already running or suspended.
  override func scene(_ scene: UIScene, openURLContexts URLContexts: Set<UIOpenURLContext>) {
    let unhandled = URLContexts.filter { appDelegate?.handleIncomingURL($0.url) != true }
    if !unhandled.isEmpty {
      super.scene(scene, openURLContexts: unhandled)
    }
  }
}
