import UIKit

class SceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?

    func sceneWillResignActive(_ scene: UIScene) {
        saveCode()
    }

    func sceneDidEnterBackground(_ scene: UIScene) {
        saveCode()
    }

    private func saveCode() {
        NotificationCenter.default.post(name: Notification.Name("saveCode"), object: nil)
    }
}
