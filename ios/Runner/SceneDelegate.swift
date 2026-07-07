import Flutter
import UIKit

class SceneDelegate: FlutterSceneDelegate {
  private var backgroundTask: UIBackgroundTaskIdentifier = .invalid

  override func sceneDidEnterBackground(_ scene: UIScene) {
    super.sceneDidEnterBackground(scene)
    beginShortBackgroundTask()
  }

  override func sceneWillEnterForeground(_ scene: UIScene) {
    super.sceneWillEnterForeground(scene)
    endShortBackgroundTask()
  }

  private func beginShortBackgroundTask() {
    endShortBackgroundTask()
    backgroundTask = UIApplication.shared.beginBackgroundTask(withName: "BIMMessageAck") {
      self.endShortBackgroundTask()
    }
  }

  private func endShortBackgroundTask() {
    if backgroundTask == .invalid {
      return
    }
    UIApplication.shared.endBackgroundTask(backgroundTask)
    backgroundTask = .invalid
  }
}
